# Lab GitOps on-prem en kind: Argo CD + OpenBao + External Secrets + app demo
CLUSTER ?= gitops-lab
REPO    ?=
# Versión del chart de External Secrets; su imagen usa el mismo número (vX.Y.Z).
ESO_VERSION ?= 2.15.0
ESO_IMAGE   := ghcr.io/external-secrets/external-secrets:v$(ESO_VERSION)
CACHE       := .cache

.PHONY: cluster argocd preload-eso secrets push bootstrap ui load rotate-secret harbor status destroy

cluster:
	kind create cluster --name $(CLUSTER) --config kind-config.yaml

argocd:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
	@echo "Usuario: admin"
	@echo -n "Password: "; kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
	@echo "Abre la UI con: make ui  (https://localhost:8080)"

# Baja la imagen de ESO una sola vez en el host y la copia a todos los nodos de kind,
# en vez de que cada nodo la descargue de ghcr.io (puede tardar >10 min y romper el --wait).
# Se exporta solo la plataforma de los nodos: con el containerd image store de Docker,
# "kind load docker-image" falla con imágenes multi-arch.
preload-eso:
	@set -e; \
	ARCH=$$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}'); \
	test -n "$$ARCH" || { echo "No encuentro nodos: ¿corriste make cluster?"; exit 1; }; \
	docker image inspect $(ESO_IMAGE) >/dev/null 2>&1 || docker pull --platform linux/$$ARCH $(ESO_IMAGE); \
	mkdir -p $(CACHE); \
	test -f $(CACHE)/eso-$(ESO_VERSION)-$$ARCH.tar || docker save --platform linux/$$ARCH -o $(CACHE)/eso-$(ESO_VERSION)-$$ARCH.tar $(ESO_IMAGE); \
	kind load image-archive $(CACHE)/eso-$(ESO_VERSION)-$$ARCH.tar --name $(CLUSTER)

secrets: preload-eso
	helm repo add openbao https://openbao.github.io/openbao-helm
	helm repo add external-secrets https://charts.external-secrets.io
	helm repo update
	helm upgrade --install openbao openbao/openbao -n openbao --create-namespace \
	  --set server.dev.enabled=true --set server.dev.devRootToken=root --set injector.enabled=false \
	  --wait --timeout 5m
	bash scripts/openbao-setup.sh
	helm upgrade --install external-secrets external-secrets/external-secrets --version $(ESO_VERSION) \
	  -n external-secrets --create-namespace --wait --timeout 5m
	kubectl apply -f manifests/cluster-secret-store.yaml
	@echo "OpenBao (modo dev) + ESO listos."

push:
	@test -n "$(REPO)" || (echo "Uso: make push REPO=https://github.com/USUARIO/gitops-lab.git"; exit 1)
	rm -rf .work && mkdir -p .work && cp -R gitops-repo/. .work/
	find .work -name '*.yaml' -exec sed -i.bak 's|__REPO__|$(REPO)|g' {} \;
	find .work -name '*.bak' -delete
	cd .work && git init -q -b main && git add -A && git commit -q -m "lab: contenido inicial" && git remote add origin $(REPO) && git push -f origin main
	@echo "Repo publicado. Clona $(REPO) aparte para hacer tus cambios del lab."

bootstrap:
	@test -n "$(REPO)" || (echo "Uso: make bootstrap REPO=https://github.com/USUARIO/gitops-lab.git"; exit 1)
	sed 's|__REPO__|$(REPO)|g' gitops-repo/clusters/lab/root-app.yaml | kubectl apply -f -
	@echo "Raiz aplicada. Mira la UI: make ui"

ui:
	kubectl -n argocd port-forward svc/argocd-server 8080:443

load:
	bash scripts/load.sh

rotate-secret:
	kubectl -n openbao exec openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=root \
	  bao kv put secret/lab/hello message="rotado $$(date +%T)"

harbor:
	helm repo add harbor https://helm.goharbor.io
	helm repo update
	helm upgrade --install harbor harbor/harbor -n harbor --create-namespace \
	  --set expose.type=clusterIP --set expose.tls.enabled=false \
	  --set externalURL=http://localhost:8081 --set persistence.enabled=false \
	  --wait --timeout 15m
	@echo "Harbor: kubectl -n harbor port-forward svc/harbor 8081:80  (admin / Harbor12345)"

status:
	kubectl -n argocd get applications.argoproj.io
	kubectl -n demo get deploy,pods,externalsecret,secret 2>/dev/null || true

destroy:
	kind delete cluster --name $(CLUSTER)
