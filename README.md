# EPSIK8STP

TP Kubernetes — Flatnotes & Gitea sur cluster kind, déploiement Kustomize avec namespaces `prod` et `test`, exposition par Ingress NGINX et LoadBalancer (MetalLB), sauvegarde par CronJob, isolation par NetworkPolicy et RBAC.

## Prérequis

- Docker
- kind (>= 0.20)
- kubectl (>= 1.32)
- Kustomize intégré à kubectl

## Démarrage rapide

```bash
./deploy.sh
```

Le script crée le cluster kind `cl1` si absent, installe MetalLB v0.16.0 + son pool d'IP, installe Ingress NGINX (patch pour épingler sur le control-plane en hostNetwork), puis applique les deux overlays Kustomize.

Ajouter dans `/etc/hosts` pour utiliser l'Ingress :

```
127.0.0.1  flatnotes.local gitea.local
```

## Accès aux applications

| Service    | URL                                | Voie                     |
|------------|------------------------------------|--------------------------|
| Flatnotes  | http://flatnotes.local             | Ingress NGINX            |
| Gitea      | http://gitea.local                 | Ingress NGINX            |
| Gitea (LB) | http://172.23.255.201:3000         | Service LoadBalancer + MetalLB |

## Structure

```
.
├── kind-config.yaml              cluster kind 1 control-plane + 2 workers (extraPortMappings 80/443)
├── deploy.sh / reset.sh          orchestration idempotente
├── infra/
│   ├── metallb/pool.yaml         pool IP 172.23.255.200-250
│   └── ingress-nginx/patch.yaml  hostNetwork + nodeSelector ingress-ready
└── k8s/
    ├── base/                     postgres + gitea (partagés entre overlays)
    └── overlays/
        ├── prod/                 + flatnotes + ingress + LB + cronjob + RBAC + NetworkPolicies
        └── test/                 postgres + gitea (sans flatnotes) + NetworkPolicy deny-from-prod
```

## Vérifications

```bash
kubectl get all -n prod
kubectl get all -n test
kubectl get ingress -n prod
kubectl get svc -n prod gitea-lb
kubectl get cronjob -n prod
kubectl get pvc -A

curl -H "Host: flatnotes.local" http://localhost/
curl -H "Host: gitea.local" http://localhost/
curl http://172.23.255.201:3000/

kubectl auth can-i list pods   --as=system:serviceaccount:prod:dev-readonly -n prod
kubectl auth can-i delete pods --as=system:serviceaccount:prod:dev-readonly -n prod
kubectl auth can-i delete pods --as=system:serviceaccount:prod:ops-admin    -n prod
```

### Persistance

```bash
kubectl delete pod -l app=flatnotes -n prod
kubectl wait --for=condition=ready pod -l app=flatnotes -n prod --timeout=120s
```

Les notes créées dans Flatnotes restent présentes après suppression du pod (PVC `flatnotes-data`).

### Isolation NetworkPolicy

```bash
kubectl run -n test probe --rm -i --restart=Never --image=busybox:1.36 -- nc -zv postgres-svc.prod 5432   # BLOQUÉ
kubectl run -n prod probe --rm -i --restart=Never --image=busybox:1.36 --labels=app=flatnotes -- nc -zv postgres-svc 5432  # OK
```

### Sauvegarde CronJob

```bash
kubectl get jobs -n prod
```

Une archive `flatnotes_YYYYMMDD_HHMMSS.tar.gz` est créée toutes les 10 minutes dans le PVC `flatnotes-backup`.

## Reset

```bash
./reset.sh
```

Supprime les namespaces `prod` et `test`. Le cluster, MetalLB et Ingress restent en place. Pour repartir à zéro complet : `kind delete cluster --name cl1 && ./deploy.sh`.
