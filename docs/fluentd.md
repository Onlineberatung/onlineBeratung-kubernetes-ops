# FluentBit

#### Install fluent-operator
`helm install fluent-operator --create-namespace -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.1.0/fluent-operator.tgz --set containerRuntime=docker -f values-develop.yaml`

#### Upgrade fluent-operator
`helm upgrade fluent-operator -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.1.0/fluent-operator.tgz --set containerRuntime=docker -f values-develop.yaml`

#### Basic Configuration
```yaml
fluentbit:
  enabled: true
  image:
    tag: "v2.0.10"
  namespace: "monitoring"
  ingress:
    enable: true
  service:
    enable: true
  parser:
    systemdjson:
      enable: true
    systemdloglevel:
      enable: true
  input:
    tail:
      enable: false
    http:
      enable: true
    systemd:
      includeKubelet: false
  filter:
    systemdcustom:
      enable: true
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
    kubernetes:
      enable: false
      labels: false
      annotations: false
    containerd:
      # This is customized lua containerd log format converter, you can refer here:
      # https://github.com/fluent/fluent-operator/blob/master/charts/fluent-operator/templates/fluentbit-clusterfilter-containerd.yaml
      # https://github.com/fluent/fluent-operator/blob/master/charts/fluent-operator/templates/fluentbit-containerd-config.yaml
      enable: false
    systemd:
      enable: false
  output:
    stdout:
      enable: true
    opensearch:
      bufferSize: "1M"
      host: opensearch.monitoring
      port: 9200
      suppressTypeName: true
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