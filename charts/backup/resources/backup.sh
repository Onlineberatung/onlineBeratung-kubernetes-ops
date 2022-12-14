#!/bin/bash
echo "Staring backup process"

echo "Installing kubectl"
apk add --update --no-cache curl ca-certificates git
curl -sLO https://storage.googleapis.com/kubernetes-release/release/v1.17.5/bin/linux/amd64/kubectl && \
mv kubectl /usr/bin/kubectl && \
chmod +x /usr/bin/kubectl

echo "Installing grid scale tool"
curl -sLO https://github.com/gridscale/gscloud/releases/download/v0.11.0/gscloud_0.11.0_linux_amd64.zip && \
  apk add unzip && \
  unzip gscloud_0.11.0_linux_amd64.zip && \
  ./gscloud make-config && \
  apk add nano && \
  sed '1,/""/s//'$GSCLOUD_USERID'/' /root/.config/gscloud/config.yaml -i && \
  sed '1,/""/s//'$GSCLOUD_TOKEN'/' /root/.config/gscloud/config.yaml -i && \
  ./gscloud kubernetes cluster save-kubeconfig --credential-plugin --cluster $GSCLOUD_CLUSTER_ID

echo "Installing mysql client"
apk add --no-cache mysql-client

echo "Installing postgresql client"
apk add --no-cache postgresql-client

echo "Installing s3cmd"
apk add --no-cache py-pip ca-certificates && pip install s3cmd
cp /s3config/.s3cfg /root

echo "Setting configuration parameters for s3cmd"
sed -i 's/secret_key_placeholder/'$BUCKET_SECRET_KEY'/g' /root/.s3cfg
sed -i 's/access_key_placeholder/'$BUCKET_ACCESS_KEY'/g' /root/.s3cfg

echo "Installing gpg"
apk add --update --no-cache gpg gpg-agent

echo "Installing mongodump version 100.6.0"
# APK 4.2.14-r12 DOES NOT WORK!
apk add --update --no-cache go krb5 krb5-dev
export GOROOT=/usr/lib/go
git clone https://github.com/mongodb/mongo-tools --branch=100.6.0 --single-branch
cd /mongo-tools/
./make build -tools=mongodump
cp /mongo-tools/bin/mongodump /bin/
cd /

echo "Starting MariaDB backup"
mkdir backup
IN=$DATABASES
OIFS=$IFS
IFS=','
databases=$IN
for database in $databases
do
    FILE_NAME=`date +"%FT%H%M%S"_$database.sql`
    mysqldump --host $DATABASE_HOST --user $DATABASE_USER --result_file=backup/$FILE_NAME $database
done

FILE_NAME=`date +"%FT%H%M%S"_mariadb_backup.tar.gz`
tar -zcvf $FILE_NAME backup
echo $BACKUP_ENCRYPTION_KEY | gpg --batch -c --passphrase-fd 0  $FILE_NAME && rm $FILE_NAME
s3cmd put $FILE_NAME.gpg $BUCKET_NAME

IFS=$OIFS

echo "Finished MariaDB backup"

echo "Starting MongoDB backup"
mongodump --host $MONGODB_HOST --port 27017 --username $MONGODB_ADMIN --password $MONGODB_ADMIN_PASS --authenticationDatabase admin
FILE_NAME=`date +"%FT%H%M%S"_mongodb_backup.tar.gz`
tar -zcvf $FILE_NAME dump
rm -rf /dump
echo $BACKUP_ENCRYPTION_KEY | gpg --batch -c --passphrase-fd 0 $FILE_NAME && rm $FILE_NAME
s3cmd put $FILE_NAME.gpg $BUCKET_NAME
echo "Finished MongoDB backup"

#backup ldap
echo "Starting OpenLdap backup"
openldap_pod=$(kubectl get pods --selector io.kompose.service=openldap -n $NAMESPACE | grep openldap)
openldap_pod=$(echo $openldap_pod | head -n1 | cut -d " " -f1)
kubectl exec -i $openldap_pod -n $NAMESPACE -- /bin/bash -c "slapcat -l /tmp/backup.ldif -F /opt/bitnami/openldap/etc/slapd.d"
FILE_NAME=$(date +"%FT%H%M%S"_ldap_backup.ldif)
kubectl cp $NAMESPACE/$openldap_pod:tmp/backup.ldif $FILE_NAME
echo $BACKUP_ENCRYPTION_KEY | gpg --batch -c --passphrase-fd 0 $FILE_NAME && rm $FILE_NAME
s3cmd put $FILE_NAME.gpg $BUCKET_NAME
echo "Finished OpenLdap backup"

if [ -n "$POSTGRESQL_PASSWORD" ]
then
  echo "Starting Postgres backup"
  export PGPASSWORD=$POSTGRESQL_PASSWORD
  pg_dump -h "$POSTGRESQL_HOST" -Fc -U calendso --format plain calendso > postgres_dump.sql
  FILE_NAME=`date +"%FT%H%M%S"_postgres_dump.tar.gz`
  tar -zcvf ./$FILE_NAME ./postgres_dump.sql
  echo $BACKUP_ENCRYPTION_KEY | gpg --batch -c --passphrase-fd 0 ./$FILE_NAME && rm $FILE_NAME
  s3cmd put $FILE_NAME.gpg $BUCKET_NAME
  echo "Finished Postgres backup"
fi
echo "Finished backup process"

echo "Deleting old backups while keeping most recent $BACKUPS_TO_KEEP"
s3cmd ls $BUCKET_NAME > /backups.txt
declare -a BACKUP_NAMES=( "mariadb_backup.tar.gz.gpg" "mongodb_backup.tar.gz.gpg" "ldap_backup.ldif.gpg" "postgres_dump.tar.gz.gpg" )
for backup in "${BACKUP_NAMES[@]}"
do
  COUNT=0
  grep $backup /backups.txt | sort -r | while read -r LINE ; do
      if [ $COUNT -ge $BACKUPS_TO_KEEP ]
      then
        FILE_TO_DELETE=$(grep -E "$BUCKET_NAME/.+\.gpg" -o <<< $LINE)
        echo "Deleting: $FILE_TO_DELETE"
        s3cmd del $FILE_TO_DELETE
      fi
      COUNT=$(( COUNT + 1 ))
  done
done
echo "Finished deleting old backups"
echo "Finished backup script. Exiting..."