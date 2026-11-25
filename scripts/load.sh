#!/usr/bin/env bash
# Bucle de peticiones desde dentro del clúster. Muestra aciertos y fallos mientras despliegas.
# Ctrl+C para parar.
kubectl -n demo delete pod load --ignore-not-found >/dev/null 2>&1 || true
kubectl -n demo run load --rm -i --restart=Never --image=curlimages/curl -- sh -c '
ok=0; fail=0
while true; do
  if curl -fs -m 1 http://hello:9898/healthz >/dev/null; then ok=$((ok+1)); else fail=$((fail+1)); fi
  printf "\rok=%s fail=%s   " "$ok" "$fail"
  sleep 0.1
done'
