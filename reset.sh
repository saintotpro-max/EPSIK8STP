#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { echo -e "\033[1;33m[reset]\033[0m $*"; }

log "Deleting overlay test"
kubectl delete -k "${ROOT}/k8s/overlays/test" --ignore-not-found=true --wait=false || true

log "Deleting overlay prod"
kubectl delete -k "${ROOT}/k8s/overlays/prod" --ignore-not-found=true --wait=false || true

log "Forcing namespace removal"
kubectl delete ns prod test --ignore-not-found=true --wait=true || true

log "Reset done. Run ./deploy.sh to redeploy."
