#!/bin/bash
# Deploy the Library E2E stack using Helm with dependencies.
# Usage: ./deploy.sh [namespace]

set -euo pipefail

NAMESPACE="${1:-library-e2e-dev}"
HELM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALUES_FILE="${HELM_DIR}/values.yaml"
RELEASE_NAME="library-e2e"

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Missing values file: ${VALUES_FILE}" >&2
  exit 1
fi

echo "Deploying Library E2E to Kubernetes"
echo "Namespace: ${NAMESPACE}"
echo "Helm Chart: ${HELM_DIR}"

echo ""
echo "Step 1: Check and clean namespace if needed"
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Namespace ${NAMESPACE} exists, deleting..."
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true --force --grace-period=0 || true
  echo "Waiting for namespace to be fully deleted..."
  for i in {1..30}; do
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
      echo "Namespace deleted successfully"
      break
    fi
    echo "Still waiting... ($i/30)"
    sleep 2
  done
  # Force remove if still stuck
  if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace still exists, attempting force removal..."
    kubectl get namespace "${NAMESPACE}" -o json > /tmp/ns.json
    if [ -f /tmp/ns.json ]; then
      sed -i '/"finalizers"/d' /tmp/ns.json
      kubectl replace --raw "/api/v1/namespaces/${NAMESPACE}/finalize" -f /tmp/ns.json || true
      sleep 2
    fi
  fi
fi
echo "Namespace ready"

echo ""
echo "Step 2: Update Helm dependencies"
cd "${HELM_DIR}"
helm dependency update
echo "Dependencies updated"

echo ""
echo "Step 3: Deploy using Helm"
helm upgrade --install "${RELEASE_NAME}" \
  "${HELM_DIR}" \
  -f "${VALUES_FILE}" \
  --set global.namespace="${NAMESPACE}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait --timeout 600s
echo "Deployment complete"

echo ""
echo "Step 4: Wait for MongoDB to be ready"
kubectl wait --for=condition=ready pod -l app=mongodb -n "${NAMESPACE}" --timeout=180s || true
echo "MongoDB status checked"

echo ""
echo "Deployment complete. Current workload status:"
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
kubectl get svc -n "${NAMESPACE}"
echo ""
echo "Gateway status:"
kubectl get gateway -n "${NAMESPACE}" 2>/dev/null || echo "No gateway found"
