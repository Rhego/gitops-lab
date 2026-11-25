# Lab GitOps on-prem (kind)

Mini plataforma local: **kind + Argo CD + OpenBao (modo dev) + External Secrets + app demo** con probes, PDB y un hook PreSync.

> OpenBao en modo dev es solo para aprender: no persiste, no usa TLS y el token raíz es "root".
> No lo probé de punta a punta en el entorno donde lo generé: si algún chart cambió un nombre de valor, el mensaje de error te dirá cuál.

## Requisitos
Docker, kind, kubectl, helm, git. Un repositorio vacío y público (GitHub o GitLab.com) con credenciales para hacer push.

## Pasos
```bash
make cluster
make argocd
make secrets
make push      REPO=https://github.com/TU_USUARIO/gitops-lab.git
make bootstrap REPO=https://github.com/TU_USUARIO/gitops-lab.git
make ui        # https://localhost:8080  (usuario admin)
```
Después clona tu repo aparte (no uses .work/) y haz los cambios del lab sobre ese clon.

`make secrets` descarga primero la imagen de External Secrets en tu máquina y la carga en los nodos de kind (`make preload-eso`); la copia queda en `.cache/` para la próxima vez que recrees el cluster. Para cambiar de versión: `make secrets ESO_VERSION=2.14.0`.

## Ejercicios
1. **Drift y self-heal**: `kubectl -n demo scale deploy/hello --replicas=5`. Observa cómo vuelve a 3. Desactiva selfHeal en la Application y repite.
2. **Rollback con git revert**: cambia `newTag` a 6.7.1 en `apps/hello/overlays/dev/kustomization.yaml`, push, espera el sync. Luego `git revert HEAD` y push.
3. **Zero-downtime visible**: en otra terminal `make load`; despliega 6.7.1 y cuenta los fallos. Quita readinessProbe y preStop, repite.
4. **Release fallida**: usa `newTag: 6.7.99-no-existe`. Los pods nuevos no arrancan, los viejos siguen sirviendo (maxUnavailable 0). Corrige con `git revert`.
5. **Hook PreSync que falla**: cambia `exit 0` por `exit 1` en `migration-job.yaml`. El sync se detiene y el Deployment viejo sigue.
6. **Secreto rotado**: `make rotate-secret`. En 30 s ESO actualiza el Secret. ¿El pod ve el cambio? (pista: variables de entorno vs archivos).
7. **Dos sitios**: copia el overlay a `site-b` y convierte la Application en un ApplicationSet con dos elementos.
8. **Bonus**: `make harbor` (usa ~2 GB).

## Limpieza
```bash
make destroy
```
# gitops-lab
