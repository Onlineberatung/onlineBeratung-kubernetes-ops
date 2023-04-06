# FluentBit

#### Install fluent-operator
`helm install fluent-operator --create-namespace -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.1.0/fluent-operator.tgz --set containerRuntime=docker -f values-develop.yaml`

#### Upgrade fluent-operator
`helm upgrade fluent-operator -n monitoring https://github.com/fluent/fluent-operator/releases/download/v2.1.0/fluent-operator.tgz --set containerRuntime=docker -f values-develop.yaml`

