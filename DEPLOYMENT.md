# Library E2E Helm Deployment Guide

This guide provides end-to-end instructions for deploying the Library E2E platform using Helm.

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

Before deploying, update the JWT secret in `values.yaml`:

```yaml
secrets:
  - name: user-service-secret
    data:
      JWT_SECRET: "YOUR_SECURE_JWT_SECRET_MIN_256_BITS"  # CHANGE THIS
```

Note: MongoDB uses simple URIs without authentication (matching k8s deployments).

### 2. Deploy Using Script

The easiest way to deploy is using the provided script:

```bash
cd helm/scripts
./deploy.sh library-e2e-dev
```

This script will:
1. Create the namespace
2. Update Helm dependencies
3. Deploy all components using Helm
4. Wait for MongoDB to be ready
5. Show deployment status

### 3. Manual Deployment

If you prefer manual deployment:

```bash
cd helm

# Update Helm dependencies
helm dependency update

# Deploy the chart
helm upgrade --install library-e2e . \
  -f values.yaml \
  --namespace library-e2e-dev \
  --create-namespace \
  --wait --timeout 600s
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

### Port Forward to Frontend

```bash
kubectl port-forward -n library-e2e-dev svc/frontend 3000:80
```

Then open http://localhost:3000 in your browser.

### Access Individual Services

```bash
# Book Service
kubectl port-forward -n library-e2e-dev svc/book-service 8081:8081

# User Service
kubectl port-forward -n library-e2e-dev svc/user-service 8082:8082

# Borrow Service
kubectl port-forward -n library-e2e-dev svc/borrow-service 8083:8083
```

## Verification

Check the deployment status:

```bash
# Check pods
kubectl get pods -n library-e2e-dev

# Check services
kubectl get svc -n library-e2e-dev

# Check gateway
kubectl get gateway -n library-e2e-dev

# Check MongoDB initialization logs
kubectl logs -n library-e2e-dev -l app=mongodb
```

## Troubleshooting

### MongoDB Not Ready

If MongoDB is not starting:
```bash
# Check MongoDB logs
kubectl logs -n library-e2e-dev -l app=mongodb

# Check MongoDB pod status
kubectl describe pod -n library-e2e-dev -l app=mongodb

# Check PVC status
kubectl get pvc -n library-e2e-dev
```

### Services Not Connecting

If services can't connect to MongoDB:
1. Verify secrets are correctly applied
2. Check ConfigMaps have correct MONGO_URI
3. Verify MongoDB is ready
4. Check service DNS resolution

### Secrets Issues

If secrets are not working:
```bash
# Check secrets exist
kubectl get secrets -n library-e2e-dev

# Decode a secret
kubectl get secret mongodb-secret -n library-e2e-dev -o jsonpath='{.data.MONGO_INITDB_ROOT_PASSWORD}' | base64 -d
```

## Updating the Deployment

To update the deployment after making changes:

```bash
helm upgrade library-e2e . \
  -f values.yaml \
  --namespace library-e2e-dev \
  --wait --timeout 600s
```

## Uninstalling

To remove the deployment:

```bash
helm uninstall library-e2e -n library-e2e-dev

# Remove PVCs (optional - this deletes data)
kubectl delete pvc -n library-e2e-dev --all

# Remove namespace
kubectl delete namespace library-e2e-dev
```

## Configuration

Key configuration options in `values.yaml`:

- `global.namespace`: Target namespace
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
