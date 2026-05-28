#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-cl1}"

log() { echo -e "\033[1;34m[deploy]\033[0m $*"; }

ensure_cluster() {
  if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    log "Creating kind cluster ${CLUSTER_NAME}"
    kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT}/kind-config.yaml"
  else
    log "Cluster ${CLUSTER_NAME} already exists"
  fi
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
}

install_metallb() {
  if ! kubectl get ns metallb-system >/dev/null 2>&1; then
    log "Installing MetalLB v0.16.0"
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.0/config/manifests/metallb-native.yaml
  else
    log "MetalLB already installed"
  fi
  kubectl wait --namespace metallb-system --for=condition=available deployment/controller --timeout=180s
  kubectl wait --namespace metallb-system --for=condition=ready pod -l component=speaker --timeout=180s
  kubectl apply -f "${ROOT}/infra/metallb/pool.yaml"
}

install_ingress() {
  if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
    log "Installing Ingress NGINX (kind variant)"
    kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
  else
    log "Ingress NGINX already installed"
  fi
  kubectl wait --namespace ingress-nginx --for=condition=available deployment/ingress-nginx-controller --timeout=180s
  log "Patching ingress controller -> control-plane + hostNetwork"
  kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
    --type=strategic --patch-file="${ROOT}/infra/ingress-nginx/patch.yaml"
  kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
}

deploy_overlay() {
  local overlay="$1"
  log "Applying overlay: ${overlay}"
  kubectl apply -k "${ROOT}/k8s/overlays/${overlay}"
}

wait_app() {
  local ns="$1" app="$2"
  log "Waiting ${app} ready in ${ns}"
  kubectl wait --namespace "${ns}" --for=condition=ready pod -l app="${app}" --timeout=240s || true
}

main() {
  ensure_cluster
  install_metallb
  install_ingress

  deploy_overlay prod
  wait_app prod postgres
  wait_app prod gitea
  wait_app prod flatnotes

  deploy_overlay test
  wait_app test postgres
  wait_app test gitea

  log "Summary"
  kubectl get all -n prod
  echo
  kubectl get all -n test
  echo
  kubectl get ingress -n prod
  echo
  kubectl get svc -n prod gitea-lb
  log "Done. Add to /etc/hosts: 127.0.0.1 flatnotes.local gitea.local"
}

main "$@"
