# FluentBit

#### Install fluent-operator
`helm install fluent-operator --create-namespace -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.3.0/fluent-operator.tgz --set containerRuntime=containerd -f values-develop.yaml`

#### Upgrade fluent-operator
`helm upgrade fluent-operator -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.3.0/fluent-operator.tgz --set containerRuntime=containerd -f values-develop.yaml`

#### Basic Configuration
```yaml
fluentbit:
  enabled: true
  image:
    tag: "v2.1.4"
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
  filter:
    kubernetes:
      enable: false
    kubernetesOnlineberatung:
      enable: true
      excluded:
        loglevels:
          - INFO
          - DEBUG
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