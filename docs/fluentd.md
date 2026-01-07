# FluentBit

#### Install fluent-operator
`helm install fluent-operator --create-namespace -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.7.0/fluent-operator.tgz --set containerRuntime=containerd -f values-develop.yaml`

#### Upgrade fluent-operator
`helm upgrade fluent-operator -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.7.0/fluent-operator.tgz --set containerRuntime=containerd -f values-develop.yaml`

#### Required steps on upgrade
If you upgrade fluent-operator with a new version it could require to remove the old configs completely
1. Go to Lens -> Custom Resources -> fluentbit.fluent.io
2. Go through all sub categories and remove the entries inside 
3. Run `helm uninstall fluent-operator -n monitoring`
4. Open Custom Resources -> Definitions and search for fluent. Remove all entries in group `fluentbit.fluent.io` and `fluentd.fluent.io` 
5. Run Command from "Install fluent-operator"

#### Basic Configuration
```yaml
fluentbit:
  enabled: true
  image:
    tag: "v2.2.2"
  namespace: "monitoring"
  ingress:
    enable: true
  service:
    enable: true
  input:
    tail:
      enable: false
    onlineberatungTail:
      enable: true
    http:
      enable: true
    systemd:
      enable: false
  parser:
    kubernetesOnlineberatungLoglevel:
      enable: true
  filter:
    kubernetes:
      enable: false
    kubernetesOnlineberatung:
      enable: true
## Excluded disabled on develop/staging
#      excluded:
#        loglevels:
#          - DEBUG
#          - INFO
      included:
        pods:
          - mongodb
          - rocketchat
          - uploadservice
          - userservice
          - messageservice
          - frontend
          - statisticsservice
          - mailservice
          - videoservice
          - adminconsole
          - agencyservice
          - consultingtypeservice
          - liveservice
          - tenantservice
    systemd:
      enable: false
  output:
    stdout:
      enable: false
    opensearch:
      bufferSize: "20M"
      host: opensearch.monitoring
      port: 9200
      suppressTypeName: true
      traceError: true
      tls:
        verify: false
      httpUser:
        valueFrom:
          secretKeyRef:
            key: username
            name: opensearch-cluster-secret
      httpPassword:
        valueFrom:
          secretKeyRef:
            key: password
            name: opensearch-cluster-secret
      logstashFormat: true
      logstashPrefix: "fluentd"
```