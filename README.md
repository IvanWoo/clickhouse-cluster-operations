# clickhouse-cluster-operations <!-- omit in toc -->

- [prerequisites](#prerequisites)
- [setup](#setup)
  - [install dbmate](#install-dbmate)
  - [namespace](#namespace)
  - [zookeeper](#zookeeper)
  - [clickhouse](#clickhouse)
- [operations](#operations)
  - [create the test database in every single node](#create-the-test-database-in-every-single-node)
  - [migrate using dbmate](#migrate-using-dbmate)
  - [TODO: migrate using golang-migrate/migrate](#todo-migrate-using-golang-migratemigrate)
  - [write/read from distributed tables](#writeread-from-distributed-tables)
- [cleanup](#cleanup)

## prerequisites
- [Rancher Desktop](https://github.com/rancher-sandbox/rancher-desktop): `1.2.1`
- Kubernetes: `v1.22.6`
- kubectl `v1.23.3`
- Helm: `v3.7.2`
- [dbmate](https://github.com/amacneil/dbmate) `v1.15.0`

## setup

### install dbmate

```sh
brew install dbmate
```

### namespace

```sh
kubectl create namespace zoons
kubectl create namespace chns
```

### zookeeper

follow the [bitnami zookeeper chart](https://github.com/bitnami/charts/tree/master/bitnami/zookeeper) to install zookeeper.

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-zookeeper bitnami/zookeeper --namespace zoons
```

verify the installation

```sh
kubectl get pods --namespace zoons
```

```sh
NAME             READY   STATUS    RESTARTS   AGE
my-zookeeper-0   1/1     Running   0          41m
```


### clickhouse

follow the [altinity clickhouse operator](https://github.com/Altinity/clickhouse-operator) to install clickhouse

install the Custom Resource Definition(crd)

```sh
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
```

the following results are expected

```sh
customresourcedefinition.apiextensions.k8s.io/clickhouseinstallations.clickhouse.altinity.com created
customresourcedefinition.apiextensions.k8s.io/clickhouseinstallationtemplates.clickhouse.altinity.com created
customresourcedefinition.apiextensions.k8s.io/clickhouseoperatorconfigurations.clickhouse.altinity.com created
serviceaccount/clickhouse-operator created
clusterrole.rbac.authorization.k8s.io/clickhouse-operator-kube-system created
clusterrolebinding.rbac.authorization.k8s.io/clickhouse-operator-kube-system created
configmap/etc-clickhouse-operator-files created
configmap/etc-clickhouse-operator-confd-files created
configmap/etc-clickhouse-operator-configd-files created
configmap/etc-clickhouse-operator-templatesd-files created
configmap/etc-clickhouse-operator-usersd-files created
deployment.apps/clickhouse-operator created
service/clickhouse-operator-metrics created
```

verify the installation

```sh
kubectl get pods --namespace kube-system
```

```sh
NAME                                      READY   STATUS      RESTARTS        AGE
...
clickhouse-operator-78f59f855b-pqntt      2/2     Running     0               57s
...
```

install the clickhouse via the operator

```sh
kubectl apply -f clickhouse/ -n chns
```

verify the installation

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SHOW DATABASES"
```

```sh
INFORMATION_SCHEMA
default
information_schema
system
```

## operations

### create the test database in every single node

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE DATABASE IF NOT EXISTS test"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE DATABASE IF NOT EXISTS test"
```


### migrate using [dbmate](https://github.com/amacneil/dbmate)

[showstopper](https://github.com/amacneil/dbmate/issues/218): no multiple statements

port forward the clickhouse pod

```sh
kubectl port-forward svc/clickhouse-repl-05 -n chns 9000:9000
```

migrate the database

```sh
dbmate --url clickhouse://analytics:admin@127.0.0.1:9000/test up
```

### TODO: migrate using [golang-migrate/migrate](https://github.com/golang-migrate/migrate/tree/master/database/clickhouse)

### write/read from distributed tables

insert data into the test database

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(100);"
```

select data from the test database via another server (it does take sometime for the eventual consistency)

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_local;"
```

## cleanup

```sh
kubectl delete -f clickhouse/ -n chns
kubectl delete -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
helm uninstall my-zookeeper -n zoons
kubectl delete pvc --all -n zoons
kubectl delete pvc --all -n chns
kubectl delete namespace zoons
kubectl delete namespace chns
```
