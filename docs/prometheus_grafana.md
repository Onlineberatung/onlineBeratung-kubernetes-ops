# Prometheus & Grafana

#### Add the repository
`helm repo add prometheus-community https://prometheus-community.github.io/helm-charts`

#### Update the repository
`helm repo update`

#### Install the kubernetes prometheus stack
This will install the prometheus stack with grafana

`helm install prometheus-community --create-namespace -n monitoring prometheus-community/kube-prometheus-stack`

#### After installation forward the port to the service and login with the default credentials:
Username: `admin`

Password: `prom-operator`

## Issues

If an older version of prometheus/grafana was installed and there are problems first remove all old crd's and other data.
If it still fails with the error:
`Error: Internal error occurred: failed calling webhook "prometheusrulemutate.monitoring.coreos.com": Post "https://prometheus-prometheus-oper-operator.monitoring.svc:443/admission-prometheusrules/mutate?timeout=30s": service "prometheus-prometheus-oper-operator" not found`
follow this guide:
https://github.com/prometheus-community/helm-charts/issues/108#issuecomment-825689328
