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

echo "Installing jq for JSON processing"
apk add --no-cache jq

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

if [ -n "$BUDIBASE_ADMIN_PASS" ]
then
  echo "Starting CouchDB backup"
  # Get the CouchDB pod using selector (similar to openldap approach)
  couchdb_pod=$(kubectl get pods --selector app=couchdb -n budibase | grep couchdb)
  couchdb_pod=$(echo $couchdb_pod | head -n1 | cut -d " " -f1)

  if [ -z "$couchdb_pod" ]; then
      echo "Error: Could not find CouchDB pod in budibase namespace"
      echo "Available pods in budibase namespace:"
      kubectl get pods -n budibase
  else
      echo "Found CouchDB pod: $couchdb_pod"

      # Create backup directory
      mkdir -p couchdb_backup

      # IMPROVED APPROACH: Get _all_dbs first (we know this works!)
      echo "Getting list of databases..."
      RETRY_COUNT=0
      MAX_RETRIES=3
      SUCCESS=false

      while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
          if [ $RETRY_COUNT -gt 0 ]; then
              echo "Retry $RETRY_COUNT for database list..."
              sleep 5
          fi

          # Get all databases and save to _all_dbs.json first
          kubectl exec -i $couchdb_pod -n budibase -- curl -s -m 30 -X GET "http://$BUDIBASE_ADMIN:$BUDIBASE_ADMIN_PASS@localhost:5984/_all_dbs" > "couchdb_backup/_all_dbs.json"

          # Check if the call was successful
          if [ -s "couchdb_backup/_all_dbs.json" ] && ! grep -q '"error"' "couchdb_backup/_all_dbs.json"; then
              echo "Successfully retrieved database list"
              # Extract database names from the working _all_dbs.json file
              jq -r '.[]' "couchdb_backup/_all_dbs.json" | grep -v '^_' > databases.txt
              SUCCESS=true
          else
              echo "Database list attempt $((RETRY_COUNT + 1)) failed"
              if [ -f "couchdb_backup/_all_dbs.json" ]; then
                  echo "Response: $(head -n 1 couchdb_backup/_all_dbs.json)"
              fi
              RETRY_COUNT=$((RETRY_COUNT + 1))
          fi
      done

      if [ "$SUCCESS" = false ]; then
          echo "Failed to get database list after $MAX_RETRIES attempts"
          exit 1
      fi

      # Check if we got any databases
      if [ ! -s databases.txt ]; then
          echo "Warning: No user databases found"
      else
          echo "Found databases:"
          cat databases.txt
          DB_COUNT=$(wc -l < databases.txt)
          echo "Total databases to backup: $DB_COUNT"

          # FIXED: Use a different approach for the while loop
          BACKUP_COUNT=0
          FAILED_COUNT=0

          # Read database names into an array first
          readarray -t DB_ARRAY < databases.txt

          # Process each database in the array
          for database in "${DB_ARRAY[@]}"; do
              if [ ! -z "$database" ]; then
                  BACKUP_COUNT=$((BACKUP_COUNT + 1))
                  echo "[$BACKUP_COUNT/$DB_COUNT] Backing up database: $database"

                  # Add timeout and retry mechanism
                  RETRY_COUNT=0
                  MAX_RETRIES=3
                  SUCCESS=false

                  while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SUCCESS" = false ]; do
                      if [ $RETRY_COUNT -gt 0 ]; then
                          echo "  Retry $RETRY_COUNT for database: $database"
                          sleep 2
                      fi

                      # Attempt backup with timeout
                      timeout 300 kubectl exec -i $couchdb_pod -n budibase -- curl -s -m 120 -X GET "http://$BUDIBASE_ADMIN:$BUDIBASE_ADMIN_PASS@localhost:5984/$database/_all_docs?include_docs=true" > "couchdb_backup/$database.json"

                      # Check if backup was successful
                      if [ -s "couchdb_backup/$database.json" ] && grep -q '"rows":' "couchdb_backup/$database.json"; then
                          echo "Successfully backed up database: $database"
                          SUCCESS=true
                      else
                          echo "Backup attempt $((RETRY_COUNT + 1)) failed for database: $database"
                          RETRY_COUNT=$((RETRY_COUNT + 1))

                          # Show file size for debugging
                          if [ -f "couchdb_backup/$database.json" ]; then
                              FILE_SIZE=$(stat -c%s "couchdb_backup/$database.json" 2>/dev/null || echo "unknown")
                              echo "    File size: $FILE_SIZE bytes"
                              # Show first few lines for debugging
                              echo "    First few lines:"
                              head -n 3 "couchdb_backup/$database.json" 2>/dev/null || echo "    Could not read file"
                          fi
                      fi
                  done

                  if [ "$SUCCESS" = false ]; then
                      echo "Failed to backup database after $MAX_RETRIES attempts: $database"
                      FAILED_COUNT=$((FAILED_COUNT + 1))
                      # Remove failed backup file
                      rm -f "couchdb_backup/$database.json"
                  fi
              fi
          done

          echo "Backup summary: $BACKUP_COUNT databases processed, $FAILED_COUNT failed"
      fi

      # _all_dbs.json is already backed up from the first step!
      echo "Database configuration already backed up as _all_dbs.json"

      # Create compressed archive
      FILE_NAME=$(date +"%FT%H%M%S"_couchdb_backup.tar.gz)
      tar -zcvf $FILE_NAME couchdb_backup
      rm -rf couchdb_backup databases.txt

      # Encrypt and upload
      echo $BACKUP_ENCRYPTION_KEY | gpg --batch -c --passphrase-fd 0 $FILE_NAME && rm $FILE_NAME
      s3cmd put $FILE_NAME.gpg $BUCKET_NAME
      echo "Finished CouchDB backup"
  fi
fi

echo "Deleting old backups while keeping most recent $BACKUPS_TO_KEEP"
s3cmd ls $BUCKET_NAME > /backups.txt
declare -a BACKUP_NAMES=( "mariadb_backup.tar.gz.gpg" "mongodb_backup.tar.gz.gpg" "ldap_backup.ldif.gpg" "postgres_dump.tar.gz.gpg" "couchdb_backup.tar.gz.gpg" )
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
