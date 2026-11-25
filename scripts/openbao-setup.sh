#!/usr/bin/env bash
# Configura OpenBao (modo dev) para el lab: KV, policy y Kubernetes auth para ESO.
set -euo pipefail

bao() { kubectl -n openbao exec -i openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=root bao "$@"; }

# En modo dev, secret/ ya viene montado como KV v2.
bao kv put secret/lab/hello message="hola desde OpenBao v1"

bao policy write hello-read - <<'POLICY'
path "secret/data/lab/hello"     { capabilities = ["read"] }
path "secret/metadata/lab/hello" { capabilities = ["read", "list"] }
POLICY

if ! bao auth list | grep '^kubernetes/' >/dev/null; then
  bao auth enable kubernetes
fi
bao write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc"
bao write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=hello-read ttl=15m

echo "OpenBao configurado: kv + policy hello-read + auth kubernetes (rol eso)."
