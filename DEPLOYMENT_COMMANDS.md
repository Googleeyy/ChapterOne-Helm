# Deployment Commands - Namespace Strategy

This guide provides step-by-step commands to deploy your application using the namespace-based environment separation.

## Prerequisites

- Kubernetes cluster access (kubectl configured)
- Helm 3.x installed
- Docker images built and pushed to registry

## Quick Reference

| Environment | Namespace | Values File | Release Name |
|-------------|-----------|-------------|--------------|
| Development | library-dev | values-dev.yaml | library-dev |
| Production | library-prod | values-prod.yaml | library-prod |

---

## Step 1: Update Helm Dependencies

Before deploying, update the Helm chart dependencies:

```bash
cd helm
helm dependency update
```

This downloads and packages the subcharts (mongodb, gateway, and all microservices).

---

## Step 2: Deploy to Development Environment

### Deploy to library-dev Namespace

```bash
cd helm

helm upgrade --install library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --create-namespace \
  --wait --timeout 600s
```

**What this does:**
- `--install`: Install if not exists, upgrade if exists
- `library-dev`: Release name
- `-f values-dev.yaml`: Use dev-specific values
- `--namespace library-dev`: Deploy to library-dev namespace
- `--create-namespace`: Create namespace if it doesn't exist
- `--wait --timeout 600s`: Wait for all resources to be ready (max 10 minutes)

### Verify Dev Deployment

```bash
# Check pods in dev namespace
kubectl get pods -n library-dev

# Check services in dev namespace
kubectl get svc -n library-dev

# Check deployments in dev namespace
kubectl get deployments -n library-dev

# Check statefulsets (MongoDB) in dev namespace
kubectl get statefulsets -n library-dev

# Check gateway in dev namespace
kubectl get gateway -n library-dev
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
book-service-xxx                  1/1     Running   0          2m
user-service-xxx                  1/1     Running   0          2m
borrow-service-xxx                1/1     Running   0          2m
frontend-xxx                      1/1     Running   0          2m
mongodb-0                         1/1     Running   0          5m
library-gateway-xxx               1/1     Running   0          2m
```

### Access Dev Application

```bash
# Port forward to frontend (dev)
kubectl port-forward -n library-dev svc/frontend 3000:80
```

Open http://localhost:3000 in your browser.

---

## Step 3: Deploy to Production Environment

### Deploy to library-prod Namespace

```bash
cd helm

helm upgrade --install library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --create-namespace \
  --wait --timeout 600s
```

**What this does:**
- Deploys to `library-prod` namespace
- Uses production values (higher replicas, autoscaling enabled)
- Deploys production-tagged images
- Enables TLS and network policies

### Verify Prod Deployment

```bash
# Check pods in prod namespace
kubectl get pods -n library-prod

# Check services in prod namespace
kubectl get svc -n library-prod

# Check deployments in prod namespace
kubectl get deployments -n library-prod

# Check statefulsets (MongoDB) in prod namespace
kubectl get statefulsets -n library-prod

# Check gateway in prod namespace
kubectl get gateway -n library-prod
```

Expected output (more replicas than dev):
```
NAME                              READY   STATUS    RESTARTS   AGE
book-service-xxx                  3/3     Running   0          2m
book-service-xxx                  3/3     Running   0          2m
book-service-xxx                  3/3     Running   0          2m
user-service-xxx                  3/3     Running   0          2m
user-service-xxx                  3/3     Running   0          2m
user-service-xxx                  3/3     Running   0          2m
borrow-service-xxx                3/3     Running   0          2m
borrow-service-xxx                3/3     Running   0          2m
borrow-service-xxx                3/3     Running   0          2m
frontend-xxx                      3/3     Running   0          2m
frontend-xxx                      3/3     Running   0          2m
frontend-xxx                      3/3     Running   0          2m
mongodb-0                         1/1     Running   0          5m
library-gateway-xxx               2/2     Running   0          2m
library-gateway-xxx               2/2     Running   0          2m
```

### Access Prod Application

```bash
# Port forward to frontend (prod)
kubectl port-forward -n library-prod svc/frontend 3001:80
```

Open http://localhost:3001 in your browser.

---

## Step 4: Verify Both Environments

### Check All Namespaces

```bash
# List all namespaces
kubectl get ns

# Check pods across both namespaces
kubectl get pods -n library-dev
kubectl get pods -n library-prod

# Check services across both namespaces
kubectl get svc -n library-dev
kubectl get svc -n library-prod
```

### Verify Isolation

```bash
# Check that dev and prod have separate resources
kubectl get all -n library-dev
kubectl get all -n library-prod

# Verify they are isolated (different namespaces)
kubectl get pods -A | grep library
```

---

## Step 5: Update Deployments

### Update Dev Environment

After making changes to `values-dev.yaml` or building new images:

```bash
cd helm

helm upgrade library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --wait --timeout 600s
```

### Update Prod Environment

After making changes to `values-prod.yaml` or building new images:

```bash
cd helm

helm upgrade library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --wait --timeout 600s
```

---

## Step 6: Rollback Deployments

### Rollback Dev Environment

```bash
# View release history
helm history library-dev -n library-dev

# Rollback to previous version
helm rollback library-dev -n library-dev

# Rollback to specific revision
helm rollback library-dev -n library-dev 2
```

### Rollback Prod Environment

```bash
# View release history
helm history library-prod -n library-prod

# Rollback to previous version
helm rollback library-prod -n library-prod

# Rollback to specific revision
helm rollback library-prod -n library-prod 2
```

---

## Step 7: Uninstall Deployments

### Uninstall Dev Environment

```bash
# Uninstall the release
helm uninstall library-dev -n library-dev

# Remove PVCs (optional - this deletes data)
kubectl delete pvc -n library-dev --all

# Remove namespace
kubectl delete namespace library-dev
```

### Uninstall Prod Environment

```bash
# Uninstall the release
helm uninstall library-prod -n library-prod

# Remove PVCs (optional - this deletes data)
kubectl delete pvc -n library-prod --all

# Remove namespace
kubectl delete namespace library-prod
```

---

## Step 8: Access Individual Services

### Dev Services

```bash
# Book Service
kubectl port-forward -n library-dev svc/book-service 8081:8081

# User Service
kubectl port-forward -n library-dev svc/user-service 8082:8082

# Borrow Service
kubectl port-forward -n library-dev svc/borrow-service 8083:8083

# MongoDB
kubectl port-forward -n library-dev svc/mongodb 27017:27017
```

### Prod Services

```bash
# Book Service
kubectl port-forward -n library-prod svc/book-service 8084:8081

# User Service
kubectl port-forward -n library-prod svc/user-service 8085:8082

# Borrow Service
kubectl port-forward -n library-prod svc/borrow-service 8086:8083

# MongoDB
kubectl port-forward -n library-prod svc/mongodb 27018:27017
```

---

## Step 9: View Logs

### Dev Logs

```bash
# All pods in dev
kubectl logs -n library-dev --all-containers=true --tail=100

# Specific service
kubectl logs -n library-dev -l app=book-service --tail=100
kubectl logs -n library-dev -l app=user-service --tail=100
kubectl logs -n library-dev -l app=borrow-service --tail=100
kubectl logs -n library-dev -l app=frontend --tail=100

# MongoDB logs
kubectl logs -n library-dev -l app=mongodb --tail=100
```

### Prod Logs

```bash
# All pods in prod
kubectl logs -n library-prod --all-containers=true --tail=100

# Specific service
kubectl logs -n library-prod -l app=book-service --tail=100
kubectl logs -n library-prod -l app=user-service --tail=100
kubectl logs -n library-prod -l app=borrow-service --tail=100
kubectl logs -n library-prod -l app=frontend --tail=100

# MongoDB logs
kubectl logs -n library-prod -l app=mongodb --tail=100
```

---

## Step 10: Debug Common Issues

### Pods Not Starting

```bash
# Describe pod to see events
kubectl describe pod -n library-dev <pod-name>

# Check pod logs
kubectl logs -n library-dev <pod-name>

# Check events in namespace
kubectl get events -n library-dev --sort-by='.lastTimestamp'
```

### MongoDB Not Ready

```bash
# Check MongoDB pod status
kubectl get pods -n library-dev -l app=mongodb

# Check MongoDB logs
kubectl logs -n library-dev -l app=mongodb

# Check PVC status
kubectl get pvc -n library-dev

# Describe MongoDB pod
kubectl describe pod -n library-dev -l app=mongodb
```

### Services Not Connecting

```bash
# Check service endpoints
kubectl get endpoints -n library-dev

# Check service DNS resolution
kubectl run -n library-dev --rm -it --restart=Never debug --image=nicolaka/netshoot -- nslookup book-service

# Check network policies (if enabled)
kubectl get networkpolicy -n library-dev
```

---

## Complete Deployment Script

### Deploy Both Environments

```bash
#!/bin/bash
set -e

echo "=== Deploying to Development Environment ==="
cd helm
helm dependency update
helm upgrade --install library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --create-namespace \
  --wait --timeout 600s

echo "=== Deploying to Production Environment ==="
helm upgrade --install library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --create-namespace \
  --wait --timeout 600s

echo "=== Verification ==="
echo "Dev pods:"
kubectl get pods -n library-dev
echo "Prod pods:"
kubectl get pods -n library-prod

echo "=== Deployment Complete ==="
```

Save as `deploy-both.sh` and run:
```bash
chmod +x deploy-both.sh
./deploy-both.sh
```

---

## Summary

**Development Deployment:**
```bash
cd helm
helm dependency update
helm upgrade --install library-dev . -f values-dev.yaml --namespace library-dev --create-namespace --wait --timeout 600s
```

**Production Deployment:**
```bash
cd helm
helm dependency update
helm upgrade --install library-prod . -f values-prod.yaml --namespace library-prod --create-namespace --wait --timeout 600s
```

**Access:**
- Dev: http://localhost:3000 (port-forward to library-dev)
- Prod: http://localhost:3001 (port-forward to library-prod)
