# Library E2E Helm Deployment Guide

This guide provides end-to-end instructions for deploying the Library E2E platform using Helm with namespace-based environment separation.

## Environment Strategy

This project uses **Kubernetes namespaces** to separate development and production environments within a single cluster:

- **library-dev namespace**: Development environment with lower resource limits, fewer replicas, and dev-specific configurations
- **library-prod namespace**: Production environment with higher resource limits, more replicas, autoscaling, and production-grade settings

Both environments share the same physical cluster resources but are logically isolated at the Kubernetes API level.

### Key Differences Between Environments

| Configuration | Dev (library-dev) | Prod (library-prod) |
|--------------|-------------------|---------------------|
| Replicas | 1 per service | 3 per service |
| MongoDB Storage | 1Gi | 10Gi |
| Resource Limits | Lower (CPU: 250m, Memory: 256Mi) | Higher (CPU: 500m, Memory: 512Mi) |
| Autoscaling | Disabled | Enabled (3-10 replicas) |
| Image Tags | `dev` | `1.0.0` |
| TLS | Disabled | Enabled |
| Network Policies | Disabled | Enabled |
| Database Names | `*_dev` suffix | Production names |

## Prerequisites

- Kubernetes cluster with the following resources:
  - StorageClass: `nfs-client` (default)
  - GatewayClass: `kgateway`
- Helm 3.x installed
- kubectl configured to access your cluster
- Docker images pushed to registry (or using local images)

## Cluster Resources Verification

Verify your cluster has the required resources:

```bash
# Check StorageClass
kubectl get storageclass

# Check GatewayClass
kubectl get gatewayclass

# Check existing gateways
kubectl get gateway -A
```

Your cluster should have:
- `nfs-client` StorageClass (default)
- `kgateway` GatewayClass

## Quick Start

### 1. Update Secrets (IMPORTANT)

Before deploying, update the JWT secret in the appropriate values file:

**For Development (`values-dev.yaml`):**
```yaml
secrets:
  - name: user-service-secret
    data:
      JWT_SECRET: "dev-jwt-secret-not-for-production"
```

**For Production (`values-prod.yaml`):**
```yaml
secrets:
  - name: user-service-secret
    data:
      JWT_SECRET: "CHANGE-THIS-TO-A-SECURE-PRODUCTION-SECRET"
```

Note: MongoDB uses simple URIs without authentication (matching k8s deployments).

### 2. Deploy to Development Environment

Deploy to the `library-dev` namespace:

```bash
cd helm

# Update Helm dependencies
helm dependency update

# Deploy to dev namespace
helm upgrade --install library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --create-namespace \
  --wait --timeout 600s
```

This will:
- Create the `library-dev` namespace (if it doesn't exist)
- Deploy all components with dev-specific configurations
- Use lower resource limits and fewer replicas
- Deploy dev-tagged images

### 3. Deploy to Production Environment

Deploy to the `library-prod` namespace:

```bash
cd helm

# Update Helm dependencies
helm dependency update

# Deploy to prod namespace
helm upgrade --install library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --create-namespace \
  --wait --timeout 600s
```

This will:
- Create the `library-prod` namespace (if it doesn't exist)
- Deploy all components with production-grade configurations
- Use higher resource limits and more replicas
- Enable autoscaling
- Deploy production-tagged images
- Enable TLS and network policies

### 4. Verify Both Environments

Check that both environments are running:

```bash
# Check dev environment
kubectl get pods -n library-dev
kubectl get svc -n library-dev

# Check prod environment
kubectl get pods -n library-prod
kubectl get svc -n library-prod

# List all namespaces
kubectl get ns
```

## Deployment Components

The Helm chart deploys the following components:

### Infrastructure
- **MongoDB**: StatefulSet with persistent storage using nfs-client
- **Gateway**: KGateway resources for routing (if enabled)

### Microservices
- **Book Service**: Manages book inventory
- **User Service**: Manages users and authentication
- **Borrow Service**: Manages book borrowing records
- **Frontend**: React-based web interface

### Secrets
- **user-service-secret**: Contains JWT_SECRET for authentication
- Other services have placeholder secrets (MongoDB uses simple URIs without auth)

## MongoDB Initialization

The MongoDB StatefulSet includes an init script that:
- Creates three databases: `chapterone_books`, `chapterone_users`, `chapterone_borrows`
- Seeds the `chapterone_books` database with 20 sample books
- Creates collections and indexes for users and borrow records

The init script runs automatically on first deployment when the volume is empty.

## Accessing the Application

### Access Development Environment

```bash
# Port forward to frontend (dev)
kubectl port-forward -n library-dev svc/frontend 3000:80
```

Then open http://localhost:3000 in your browser.

### Access Production Environment

```bash
# Port forward to frontend (prod)
kubectl port-forward -n library-prod svc/frontend 3001:80
```

Then open http://localhost:3001 in your browser.

### Access Individual Services

**Development:**
```bash
# Book Service
kubectl port-forward -n library-dev svc/book-service 8081:8081

# User Service
kubectl port-forward -n library-dev svc/user-service 8082:8082

# Borrow Service
kubectl port-forward -n library-dev svc/borrow-service 8083:8083
```

**Production:**
```bash
# Book Service
kubectl port-forward -n library-prod svc/book-service 8084:8081

# User Service
kubectl port-forward -n library-prod svc/user-service 8085:8082

# Borrow Service
kubectl port-forward -n library-prod svc/borrow-service 8086:8083
```

## Verification

Check the deployment status for both environments:

```bash
# Check dev pods
kubectl get pods -n library-dev

# Check dev services
kubectl get svc -n library-dev

# Check dev gateway
kubectl get gateway -n library-dev

# Check dev MongoDB initialization logs
kubectl logs -n library-dev -l app=mongodb

# Check prod pods
kubectl get pods -n library-prod

# Check prod services
kubectl get svc -n library-prod

# Check prod gateway
kubectl get gateway -n library-prod

# Check prod MongoDB initialization logs
kubectl logs -n library-prod -l app=mongodb
```

## Troubleshooting

### MongoDB Not Ready

If MongoDB is not starting in dev:
```bash
# Check MongoDB logs (dev)
kubectl logs -n library-dev -l app=mongodb

# Check MongoDB pod status (dev)
kubectl describe pod -n library-dev -l app=mongodb

# Check PVC status (dev)
kubectl get pvc -n library-dev
```

If MongoDB is not starting in prod:
```bash
# Check MongoDB logs (prod)
kubectl logs -n library-prod -l app=mongodb

# Check MongoDB pod status (prod)
kubectl describe pod -n library-prod -l app=mongodb

# Check PVC status (prod)
kubectl get pvc -n library-prod
```

### Services Not Connecting

If services can't connect to MongoDB:
1. Verify secrets are correctly applied in the correct namespace
2. Check ConfigMaps have correct MONGO_URI
3. Verify MongoDB is ready in the target namespace
4. Check service DNS resolution (e.g., `mongodb-0.mongodb.library-dev.svc.cluster.local`)

### Secrets Issues

If secrets are not working in dev:
```bash
# Check secrets exist (dev)
kubectl get secrets -n library-dev

# Decode a secret (dev)
kubectl get secret mongodb-secret -n library-dev -o jsonpath='{.data.MONGO_INITDB_ROOT_PASSWORD}' | base64 -d
```

If secrets are not working in prod:
```bash
# Check secrets exist (prod)
kubectl get secrets -n library-prod

# Decode a secret (prod)
kubectl get secret mongodb-secret -n library-prod -o jsonpath='{.data.MONGO_INITDB_ROOT_PASSWORD}' | base64 -d
```

## Updating the Deployment

To update the development deployment after making changes:

```bash
helm upgrade library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --wait --timeout 600s
```

To update the production deployment after making changes:

```bash
helm upgrade library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --wait --timeout 600s
```

## Uninstalling

To remove the development deployment:

```bash
helm uninstall library-dev -n library-dev

# Remove PVCs (optional - this deletes data)
kubectl delete pvc -n library-dev --all

# Remove namespace
kubectl delete namespace library-dev
```

To remove the production deployment:

```bash
helm uninstall library-prod -n library-prod

# Remove PVCs (optional - this deletes data)
kubectl delete pvc -n library-prod --all

# Remove namespace
kubectl delete namespace library-prod
```

## Configuration

### Environment-Specific Values Files

- `values-dev.yaml`: Development environment configuration
  - Namespace: `library-dev`
  - Lower resource limits and fewer replicas
  - Dev-tagged images
  - Autoscaling disabled
  - TLS disabled
  - Network policies disabled

- `values-prod.yaml`: Production environment configuration
  - Namespace: `library-prod`
  - Higher resource limits and more replicas
  - Production-tagged images
  - Autoscaling enabled
  - TLS enabled
  - Network policies enabled

### Key Configuration Options

- `global.namespace`: Target namespace (library-dev or library-prod)
- `global.environment`: Environment label (dev or prod)
- `createNamespace`: Whether to create the namespace via Helm
- `global.imagePullPolicy`: Image pull policy
- `gateway.enabled`: Enable/disable gateway
- `gateway.gatewayClassName`: Gateway class (kgateway)
- `mongodb.storage.storageClass`: Storage class for MongoDB PVC
- `mongodb.storage.size`: Storage size for MongoDB
- Service replicas and resource limits
- Autoscaling settings

## Security Notes

⚠️ **IMPORTANT SECURITY NOTES:**

1. **Replace all placeholder secrets** before production deployment
2. Use strong, unique passwords for each service
3. JWT secret must be at least 256 bits for security
4. Consider using sealed-secrets or external secret management for production
5. Enable TLS for the gateway in production
6. Use network policies to restrict traffic between services
7. Regularly rotate secrets

## Production Considerations

For production deployment:

1. **Secrets Management**: Use sealed-secrets, HashiCorp Vault, or cloud KMS
2. **TLS/SSL**: Enable TLS for all services and gateway
3. **Resource Limits**: Adjust resource requests/limits based on actual usage
4. **Monitoring**: Add Prometheus/Grafana for monitoring
5. **Logging**: Centralized logging (ELK, Loki, etc.)
6. **Backup**: Regular MongoDB backups
7. **High Availability**: Consider MongoDB replica set
8. **Ingress**: Use proper ingress controller with TLS termination
