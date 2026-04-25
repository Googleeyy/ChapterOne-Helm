# Library E2E Helm Charts

This repo is the Kubernetes deployment source for the Library E2E microservices platform.

The intended production flow is same-origin traffic through Envoy Gateway:

- frontend is just another microservice
- frontend calls `/api/...` on the same host
- Envoy Gateway routes `/` to frontend and `/api/*` to backend services
- backend services do not need CORS for this deployment model

## Layout

- `values.yaml`: single global Helm values file for the full platform
- `secrets/`: plain Kubernetes Secret manifests you can convert to SealedSecrets later
- `microservices/`: per-service Helm charts
- `infrastructure/mongodb/`: shared MongoDB chart
- `infrastructure/gateway/`: Gateway API resources with backend refs driven from `values.yaml`
- `scripts/deploy.sh`: installs the stack into a Kubernetes cluster
- `scripts/build-images.sh`: optional helper that builds images from sibling service folders

## Expected Repo Split

When you split this repo into independent repositories, keep this repo as the place where:

- image repositories and tags are managed
- namespace, gateway, and shared infra are managed
- inter-service backend references stay consistent

## Deploy

1. Push service images to a registry and update `values.yaml`.
2. Replace every placeholder value under `secrets/`.
3. Convert those Secret manifests to SealedSecrets later if you want, but keep the same secret names from `values.yaml`.
4. Install Gateway API and Envoy Gateway in the cluster if they are not already present.
5. Run `./scripts/deploy.sh <namespace>`.

The deploy script creates the namespace, applies the plain Secret manifests, installs MongoDB, deploys all backend services, deploys the frontend, and then installs the Gateway routing resources.

For Kubernetes, the service Secret examples use the MongoDB StatefulSet primary host `mongodb-0.mongodb` because MongoDB runs behind a headless Service.

## Microservices

### Backend Services
- **book-service**: Book CRUD operations (port 8081)
- **user-service**: User authentication and management (port 8082)
- **borrow-service**: Book borrowing and return operations (port 8083)

### Frontend
- **frontend**: React-based web UI (port 80)

### Infrastructure
- **mongodb**: MongoDB 7.0 database
- **gateway**: Envoy Gateway API resources
- **haproxy**: HAProxy load balancer (optional)

## Values Reference

See `values.yaml` for all configurable options including:
- Image repositories and tags
- Resource limits and requests
- Autoscaling parameters
- Health check configurations
- Gateway settings
