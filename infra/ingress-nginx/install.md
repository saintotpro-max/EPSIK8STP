# Installation Ingress NGINX (kind)

## Étapes (exécutées par `deploy.sh`)

```bash
# 1. Manifeste officiel kind (LoadBalancer + tolerations control-plane)
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml

# 2. Attendre la création du Deployment puis patcher pour épingler sur control-plane + hostNetwork
#    (pour exposer 80/443 via extraPortMappings du host)
kubectl wait --namespace ingress-nginx --for=condition=available deployment/ingress-nginx-controller --timeout=180s

kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=strategic --patch-file=infra/ingress-nginx/patch.yaml

kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
```

## Résultat attendu

- Pod `ingress-nginx-controller` sur le node `cl1-control-plane` (IP host `172.23.0.4`)
- Deux chemins d'accès :
  - `http://localhost/` (via extraPortMappings du kind config → hostNetwork du pod)
  - `http://172.23.255.200/` (via Service LoadBalancer + MetalLB)

## Validation

```bash
curl -sS -o /dev/null -w "localhost -> %{http_code}\n" http://localhost/        # 404
curl -sS -o /dev/null -w "metallb  -> %{http_code}\n" http://172.23.255.200/   # 404
```
