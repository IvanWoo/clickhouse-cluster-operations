# clickhouse-cluster-operations <!-- omit in toc -->

- [prerequisites](#prerequisites)
- [setup](#setup)
  - [build images](#build-images)
  - [namespace](#namespace)
  - [zookeeper](#zookeeper)
  - [clickhouse](#clickhouse)
- [operations](#operations)
  - [create the test database on cluster](#create-the-test-database-on-cluster)
  - [migrate using dbmate](#migrate-using-dbmate)
    - [on k8s cluster(preferred)](#on-k8s-clusterpreferred)
    - [on local mac machine](#on-local-mac-machine)
  - [migrate using golang-migrate/migrate](#migrate-using-golang-migratemigrate)
  - [write/read from replicated tables](#writeread-from-replicated-tables)
  - [write/read from distributed tables](#writeread-from-distributed-tables)
  - [truncate the distributed tables](#truncate-the-distributed-tables)
  - [join two distributed tables](#join-two-distributed-tables)
  - [exchange tables](#exchange-tables)
    - [create table with schema similar to the distributed table](#create-table-with-schema-similar-to-the-distributed-table)
    - [exchange the tables](#exchange-the-tables)
- [cleanup](#cleanup)
- [gotcha](#gotcha)
  - [migrations](#migrations)
  - [database is not resolved in the CTE with join](#database-is-not-resolved-in-the-cte-with-join)

## prerequisites
- [Rancher Desktop](https://github.com/rancher-sandbox/rancher-desktop): `1.2.1`
- Kubernetes: `v1.22.6`
- kubectl `v1.23.3`
- Helm: `v3.7.2`
- [dbmate](https://github.com/amacneil/dbmate) `v1.15.0`
- [golang-migrate](https://github.com/golang-migrate/migrate/tree/master/cmd/migrate) `v4.15.1`

## setup

tl;dr: `bash scripts/up.sh`

### build images

```sh
nerdctl --namespace=k8s.io build -t my/dbmate -f Dockerfile .
```

### namespace

```sh
kubectl create namespace zoons --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chns --dry-run=client -o yaml | kubectl apply -f -
```

### zookeeper

follow the [bitnami zookeeper chart](https://github.com/bitnami/charts/tree/master/bitnami/zookeeper) to install zookeeper.

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install my-zookeeper bitnami/zookeeper --namespace zoons -f zookeeper/values.yaml
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

**attention**: it takes around 10 mins for a 2 replica + 2 shards cluster to be ready.

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

### create the test database on cluster

**attention**: we need to specify the engine type Atomic for cluster;

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="DROP DATABASE IF EXISTS test ON CLUSTER '{cluster}'"
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE DATABASE IF NOT EXISTS test ON CLUSTER '{cluster}' ENGINE=Atomic"
```


### migrate using [dbmate](https://github.com/amacneil/dbmate)

known caveats
- [no multiple statements](https://github.com/amacneil/dbmate/issues/218)
- no cluster mode out of box: the migration metadata is stored in only one node
  - can manually create the migration metadata in the cluster first
- `dbmate status` didn't work >= v1.14.0 due to [this pr](https://github.com/amacneil/dbmate/pull/242)
  - `Error: sql: expected 0 arguments, got 1`

#### on k8s cluster(preferred)

run all migrations

```sh
kubectl run dbmate-migrate -n chns -ti --rm --restart=Never --image=my/dbmate --overrides='
{
  "spec": {
    "containers":[{
      "name": "migrate",
      "image": "my/dbmate",
      "imagePullPolicy":"Never",
      "args": ["-db", "test", "migrate"],
      "stdin": true,
      "tty": true,
      "env": [
        {"name":"DATABASE_URL","value":"clickhouse://analytics:admin@clickhouse-repl-05.chns:9000"}
      ],"volumeMounts": [{"mountPath": "/app/databases","name": "store"}]
    }],
    "volumes": [{"name":"store","hostPath":{"path":"'$PWD/databases'","type":"Directory"}}]
  }
}'
```

create new migration

```sh
kubectl run dbmate-migrate -n chns -ti --rm --restart=Never --image=my/dbmate --overrides='
{
  "spec": {
    "containers":[{
      "name": "migrate",
      "image": "my/dbmate",
      "imagePullPolicy":"Never",
      "args": ["-db", "test", "new", "-p", "new one"],
      "stdin": true,
      "tty": true,
      "env": [
        {"name":"DATABASE_URL","value":"clickhouse://analytics:admin@clickhouse-repl-05.chns:9000"}
      ],"volumeMounts": [{"mountPath": "/app/databases","name": "store"}]
    }],
    "volumes": [{"name":"store","hostPath":{"path":"'$PWD/databases'","type":"Directory"}}]
  }
}'
```

#### on local mac machine

install migration tools

```sh
brew install dbmate
```

port forward the clickhouse pod

```sh
kubectl port-forward svc/clickhouse-repl-05 -n chns 9000:9000
```

create the replicated migration metadata table

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="DROP TABLE IF EXISTS test.schema_migrations ON CLUSTER '{cluster}';"

kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE TABLE test.schema_migrations ON CLUSTER '{cluster}' 
(
    version String,
    ts DateTime DEFAULT now(),
    applied UInt8 DEFAULT 1
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/{cluster}/tables/{database}/{table}', '{replica}', ts)
PRIMARY KEY version
ORDER BY version;"
```

migrate the database

```sh
dbmate --url clickhouse://analytics:admin@127.0.0.1:9000/test up
```


### migrate using [golang-migrate/migrate](https://github.com/golang-migrate/migrate/tree/master/database/clickhouse)

caveats
- FIXME: BROKEN
- very buggy
- poor documentation, it didn't work the way described in the docs
- claim support the multiple statements, but I didn't make it work
- [still hard to use migrate in some multi server environment](https://kb.altinity.com/altinity-kb-setup-and-maintenance/schema-migration-tools/golang-migrate/)

create the replicated migration metadata table

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE TABLE test.schema_migrations ON CLUSTER '{cluster}' 
(
    version UInt32,
    dirty UInt8,
    sequence UInt64
)
ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{database}/{table}/1', '{replica}')
PRIMARY KEY version
ORDER BY version;"
```

port forward the clickhouse pod

```sh
kubectl port-forward svc/clickhouse-repl-05 -n chns 9000:9000
```

migrate the database

```sh
migrate -source file://./golang-migrate/migrations -database "clickhouse://analytics:admin@127.0.0.1:9000/x-multi-statement=true?database=test" up
```

### write/read from replicated tables

**attention**: it takes sometimes for the eventual consistency between different replicas.

insert data into the replicated table

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.events_local SELECT today(), rand()%3, number, 'my title' FROM numbers(100);"
```

select data from the test database via all servers

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.events_local;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.events_local;"
kubectl exec chi-repl-05-replicated-0-1-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.events_local;"
kubectl exec chi-repl-05-replicated-1-1-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.events_local;"
```

### write/read from distributed tables

**attention**: it takes sometimes for the eventual consistency between different replicas.

insert data into the test database

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(100);"
```

verify the data

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_local;"
```

select data from the test database via another replica

```sh
kubectl exec chi-repl-05-replicated-0-1-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-0-1-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_local;"
```

select data from the test database via another shard

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_local;"
```

### truncate the distributed tables

we can only truncate the local tables rather than the distributed proxy tables

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="TRUNCATE TABLE IF EXISTS test.sales_local ON CLUSTER '{cluster}';"
```

### join two distributed tables

insert data into the test database

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(100);"
```

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="
INSERT INTO test.products_distributed
WITH
uniq_products AS (
  SELECT DISTINCT PRODUCT_ID FROM test.sales_distributed
),
products AS (
  SELECT row_number() OVER () AS rn, PRODUCT_ID FROM uniq_products
),
names AS (
  SELECT row_number() OVER () AS rn, randomString(20) as PRODUCT_NAME FROM numbers(1000)
),
products_with_names AS (
  SELECT
    PRODUCT_ID,
    PRODUCT_NAME
  FROM products
  LEFT JOIN names ON products.rn = names.rn
  where PRODUCT_ID > 0
)
SELECT * FROM products_with_names;"
```

global join

**attention**: `GLOBAL` keyword is required, but [be careful when using it](https://clickhouse.com/docs/en/sql-reference/statements/select/join/#distributed-join)

```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="
SELECT
  *
FROM test.sales_distributed as s
GLOBAL LEFT JOIN test.products_distributed as p
ON s.PRODUCT_ID=p.PRODUCT_ID
LIMIT 10;"
```


### exchange tables 

#### create table with schema similar to the distributed table

create the temp local and distributed tables
- we cannot use `"CREATE TABLE IF NOT EXISTS test.temp_sales_local ON CLUSTER '{cluster}' AS test.sales_local"` b/c the zookeeper path must be unique.
- b/c distributed table is the proxy point to the previous local table, we need to overwrite the ENGINE to point to the temp local table.

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="
CREATE TABLE IF NOT EXISTS test.temp_sales_local ON CLUSTER '{cluster}' (
    WEEK Date32,
    COUNTRY_ID Decimal(38, 9),
    REGION String,
    PRODUCT_ID Nullable(Decimal(38, 10)),
    UNITS Nullable(Float64),
    DOLLAR_VOLUME Nullable(Decimal(38, 10))
) ENGINE = ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}')
PARTITION BY
    toYYYYMM(WEEK)
ORDER BY
    (COUNTRY_ID, WEEK, REGION);"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE TABLE IF NOT EXISTS test.temp_sales_distributed ON CLUSTER '{cluster}' AS test.sales_distributed ENGINE = Distributed('{cluster}', test, temp_sales_local, rand())"
```

verify

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.temp_sales_distributed;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.temp_sales_local;"
```

```sh
0
0
```

cleanup the original tables with the truncate above

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="TRUNCATE TABLE IF EXISTS test.sales_local ON CLUSTER '{cluster}';"
```

insert dummy data into all tables: 500 rows for original tables, 300 rows for temp tables


```sh
kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(500);"

kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.temp_sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(300);"
```

verify

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.temp_sales_distributed;"
```

```sh
500
300
```

#### exchange the tables

**attention**: you just need to exchange local tables, b/c the distributed table points to a hard coded local table

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="EXCHANGE TABLES test.temp_sales_local AND test.sales_local ON CLUSTER '{cluster}';"
# kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="EXCHANGE TABLES test.temp_sales_distributed AND test.sales_distributed ON CLUSTER '{cluster}';"
```

verify

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.sales_distributed;"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SELECT count() FROM test.temp_sales_distributed;"
```

```sh
300
500
```

drop the temp tables

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="DROP TABLE IF EXISTS test.temp_sales_local ON CLUSTER '{cluster}';"
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="DROP TABLE IF EXISTS test.temp_sales_distributed ON CLUSTER '{cluster}';"
```

verify

```sh
kubectl exec chi-repl-05-replicated-1-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="SHOW TABLES IN test;"
```

## cleanup

tl;dr: `bash scripts/down.sh`

```sh
kubectl delete -f clickhouse/ -n chns
kubectl delete -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
helm uninstall my-zookeeper -n zoons
kubectl delete pvc --all -n zoons
kubectl delete pvc --all -n chns
kubectl delete namespace zoons
kubectl delete namespace chns
```

## gotcha

### migrations

```sh
Error: code: 253, message: There was an error on [chi-repl-05-replicated-0-1:9000]: Code: 253. DB::Exception: Replica /clickhouse/repl-05/replicated/tables/test/events_local/replicas/chi-repl-05-replicated-0-1 already exists. (REPLICA_IS_ALREADY_EXIST) (version 22.3.3.44 (official build))
```

due to the nature of the replication setup, migrations up and down very quickly can cause the above issue.
the solution is to have `SYNC` on the down sql statement, which will wait for the replica to be removed before proceeding.

the final solution is to delete all the information regarding the replication on Zookeeper

```sh
zkCli.sh deleteall /clickhouse/repl-05/replicated/tables/test/events_local
```

### [database is not resolved in the CTE with join](https://github.com/ClickHouse/ClickHouse/issues/39278)

```sh
cat examples/cte_join.sql | curl --data-binary @- "http://analytics:admin@localhost:8123/?database=test"
```

```sh
Code: 60. DB::Exception: Received from chi-repl-05-replicated-1-1:9000. DB::Exception: Table default.entity_category_local doesn't exist. (UNKNOWN_TABLE) (version 22.6.3.35 (official build))
```

this query fails on `2 replicas x 2 shards` and `1 replicas x 2 shards` setup, but works on `2 replicas x 1 shards` and `1 replicas x 1 shards` setup
