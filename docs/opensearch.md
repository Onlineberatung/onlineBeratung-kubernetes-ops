# Opensearch

#### Add the repository
`helm repo add opensearch-operator https://opster.github.io/opensearch-k8s-operator/`

#### Update the repository
`helm repo update`

#### Install the Opensearch Operator
`helm install opensearch-operator --create-namespace -n monitoring opensearch-operator/opensearch-operator -f values-develop.yaml`


