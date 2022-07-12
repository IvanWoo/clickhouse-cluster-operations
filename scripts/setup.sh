#!/bin/sh
set -euo pipefail

create_db() {
    kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="CREATE DATABASE IF NOT EXISTS test ON CLUSTER '{cluster}' ENGINE=Atomic"
}

run_migrate() {
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
}

seed_db() {
    kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.sales_distributed SELECT today(), rand()%10, 'ON', rand(), rand() + 0.42, rand() FROM numbers(100);"

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

    kubectl exec chi-repl-05-replicated-0-0-0 -n chns -- clickhouse-client -u analytics --password admin --query="INSERT INTO test.events_local SELECT today(), rand()%3, number, 'my title' FROM numbers(100);"
}

main() {
    create_db
    run_migrate
    seed_db
}

main
