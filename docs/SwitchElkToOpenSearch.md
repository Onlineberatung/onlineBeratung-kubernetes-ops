# Switch ELK to OpenSearch

To switch from a running ELK stack to OpenSearch, you need to do the following steps.
The deployment have to be done in two steps, because OpenSearch will first start the operator and create the custom resources and in the second step it will start the Cluster.

### Step 1: Deploy OpenSearch Operator
In the first step you have to disable the ELK stack, adapt the values and start the OpenSearch Operator pod.

#### In values.yaml set the following values:

1. Disable elk stack
```yaml
global:
    elkDisabled: true
```

2. Set the namespace for the OpenSearch Cluster but keep it disabled
```yaml
opensearch-cluster:
  enabled: false
  namespace: <your namespace>
```

3. Add the config for the new OpenSearch Logstash pod
ingress.enabled needs to be disabled on first deploy
```yaml
opensearch-logstash:
  service:
    ports:
      - name: http
        port: 8080
        protocol: TCP
        targetPort: 8080
  ingress:
    enabled: false
    annotations:
      nginx.ingress.kubernetes.io/rewrite-target: /$1$2
    className: "nginx"
    pathtype: Prefix
    hosts:
      - host: "<your.domain.com>"
        paths:
          - path: /service/logstash
            servicePort: 8080
  fullnameOverride: "opensearch-logstash"
  image: "opensearchproject/logstash-oss-with-opensearch-output-plugin"
  persistence:
    enabled: true
  logstashConfig:
    logstash.yml: |
      http.host: 0.0.0.0
      pipeline.ecs_compatibility: disabled
  logstashPipeline:
    logstash.conf: |
      input {
       http { 
            port => 8080 # default: 8080, not 9600 
            codec => "json" 
          }
      }
      filter {
         if [serviceName] != "frontend" and [serviceName] != "users" {
            drop{}
         }
         if ![request][correlationId] or ![request][timestamp] {
           drop{}
         }
      }
      output {
        opensearch
        {
          hosts => ["https://opensearch.<your namespace>:9200"]
          user => '${ELASTICSEARCH_USERNAME}'
          password => '${ELASTICSEARCH_PASSWORD}'
          index => "http-log-%{+YYYY.MM.dd}" 
          document_type => "json"
          ssl_certificate_verification => false
          ssl => true
        }
      }
```

#### In values-secrets.yaml set the following values:
The user is the default admin user which is added by opensearch. 
Because it is not reachable from outside you can use the default password.

```yaml
opensearch-logstash:
  extraEnvs:
    - name: "ELASTICSEARCH_USERNAME"
      value: "admin"
    - name: "ELASTICSEARCH_PASSWORD"
      value: "admin"
```

#### Deploy 

Run helm upgrade and wait until the opensearch-operator pod is up and running and the elk stack is disabled

### Step 2: Enable OpenSearch Cluster and Logstash Ingress

In the second step you have to enable the cluster and start the logstash ingress.

#### In values.yaml set the following values:

1. Enable the OpenSearch Cluster
```yaml
opensearch-cluster:
  enabled: true
```

2. Enable the logstash ingress
```yaml
opensearch-logstash:
  ingress:
    enabled: true
```

3. (Optional) Change the logstash internal hosts from other services
```yaml
logstashHost: "http://opensearch-logstash.<your namespace>:8080"
```

#### Deploy

Run helm upgrade again and wait until all pods are up and running.

That's it. Now you can forward the opensearch-dashboard service and login with the default credentials.

## Next Steps (optional)
1. Configure your monitors with destinations and alerts.
2. Create your custom dashboards
3. ...