# Switch ELK to OpenSearch

To switch from a running ELK stack to OpenSearch, you need to do the following steps.
The deployment have to be done in multiple steps, because OpenSearch will first start the operator and create the custom resources and in the second step it will start the Cluster.

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

3. Deploy the k8s-ops release to your helm chart

4. Follow the instructions inside [Opensearch](opensearch.md) to deploy the opensearch operator

5. Follow the instructions inside [Fluentd](fluentd.md) to deploy the fluentd operator and add the basic config to your values.yaml

### Step 2: Enable OpenSearch Cluster

In the second step you have to enable the cluster.

#### In values.yaml set the following values:

1. Enable the OpenSearch Cluster
```yaml
opensearch-cluster:
  enabled: true
```

2. (Optional) Change the logstash internal hosts from other services
```yaml
logstashHost: "http://fluentbit-http-service.monitoring:8888"
```

3. Deploy the k8s-ops release to your helm chart

### Step 3: Enable Fluentbit Operator

## Next Steps (optional)
1. Configure your monitors with destinations and alerts.
2. Create your custom dashboards
3. ...