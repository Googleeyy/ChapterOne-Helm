# Library E2E - Helm Deployment Guide

## Prerequisites Installation

### 1. Gateway API CRDs
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/standard-install.yaml
```

### 2. Metrics Server (Required for HPA)
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 3. Sealed Secrets Controller
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

### 4. kGateway Controller
```bash
helm repo add kgateway https://kgateway.dev/helm
helm repo update
helm install kgateway kgateway/kgateway -n kgateway-system --create-namespace
```

### 5. HAProxy Ingress Controller
```bash
helm repo add haproxy-ingress https://haproxy-ingress.github.io/charts
helm repo update
helm install haproxy-ingress haproxy-ingress/haproxy-ingress \
  -n haproxy-ingress --create-namespace \
  --set controller.ingressClass=haproxy \
  --set controller.replicaCount=2
```

---

## Sealing Secrets

```bash
# 1. Create raw secret (DO NOT COMMIT)
kubectl create secret generic app-secrets \
  --from-literal=JWT_SECRET=your-actual-jwt-secret \
  --dry-run=client -o yaml > /tmp/raw-secrets.yaml

# 2. Encrypt with kubeseal
kubeseal --controller-name=sealed-secrets \
         --controller-namespace=kube-system \
         --format yaml < /tmp/raw-secrets.yaml > helm/templates/secrets/sealedsecret.yaml

# 3. Delete raw secret
rm /tmp/raw-secrets.yaml

# 4. Verify secret is unsealed in cluster
kubectl get secret app-secrets -n <namespace>
```

---

## Deploy to Development

```bash
helm upgrade --install library-e2e ./helm \
  -f helm/values.yaml \
  -f helm/values-dev.yaml \
  --namespace dev --create-namespace
```

### Verify Dev Deployment
```bash
kubectl get pods -n dev
kubectl get httproute -n dev
kubectl get hpa -n dev
kubectl rollout status deployment/library-e2e-frontend -n dev
```

---

## Deploy to Production

```bash
helm upgrade --install library-e2e ./helm \
  -f helm/values.yaml \
  -f helm/values-prod.yaml \
  --namespace prod --create-namespace
```

---

## Testing

### Test Internal DNS
```bash
kubectl exec -n dev <frontend-pod> -- \
  curl http://book-svc.dev.svc.cluster.local:8081/api/books
```

### Test HPA (Load Generation)
```bash
kubectl run -n dev load-test --image=busybox --restart=Never -- \
  sh -c "while true; do wget -q -O- http://frontend-svc; done"

# Watch HPA in another terminal
kubectl get hpa -n dev -w

# Stop load test
kubectl delete pod -n dev load-test
```

### Test NetworkPolicy (Should Fail)
```bash
# Frontend should NOT reach database directly
kubectl exec -n dev <frontend-pod> -- \
  nc -z mongo-svc.dev.svc.cluster.local 27017
```

---

## Troubleshooting

### Check Gateway Status
```bash
kubectl get gateway -n <namespace>
kubectl describe gateway library-e2e-gateway -n <namespace>
```

### Check HTTPRoutes
```bash
kubectl get httproute -n <namespace>
kubectl describe httproute library-e2e-frontend-route -n <namespace>
```

### View Pod Logs
```bash
kubectl logs -n <namespace> -l app.kubernetes.io/component=frontend --tail=100
```

### Port Forward for Local Testing
```bash
kubectl port-forward -n <namespace> svc/frontend-svc 8080:80
```
