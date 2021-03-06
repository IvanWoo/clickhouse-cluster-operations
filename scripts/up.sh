#!/bin/sh
# This file is autogenerated - DO NOT EDIT!

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${BASE_DIR}/.."
(
cd ${REPO_DIR}
kubectl create namespace zoons --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chns --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml
kubectl apply -f clickhouse/ -n chns
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install my-zookeeper bitnami/zookeeper --namespace zoons -f zookeeper/values.yaml
)
