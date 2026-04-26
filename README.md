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

---

## Environment Management & Helm Value Mapping

### How Environments Are Managed

This repo uses an **umbrella Helm chart** (`helm/`) that contains multiple sub-charts (microservices and infrastructure). Environment-specific behavior is controlled by **value overrides**, not by separate charts.

| File | Purpose | Scope |
|------|---------|-------|
| `values.yaml` | Base defaults for all environments | Defines images, resources, secrets structure |
| `values-dev.yaml` | Dev overrides | Lower resources, 1 replica, dev image tags, TLS off |
| `values-prod.yaml` | Prod overrides | Higher resources, 3 replicas, semver tags, TLS on, autoscaling |

**Internal Helm Merge Order:**
```
values.yaml (base)
  └─ values-dev.yaml  or  values-prod.yaml (overrides)
```
Helm deep-merges these files. Anything in `values-dev.yaml` wins over `values.yaml`.

### How ArgoCD Maps Branches to Environments

ArgoCD Applications in `argocd/applications/` point to this repo and select a branch + values file:

| ArgoCD App | Git Branch | Values File | Namespace |
|------------|------------|-------------|-----------|
| `library-dev` | `dev` | `values-dev.yaml` | `library-dev` |
| `library-prod` | `production` | `values-prod.yaml` | `library-prod` |

**Real internal flow:**
1. ArgoCD polls the `dev` branch every 3 minutes (or via webhook).
2. When it sees a new commit, it runs:
   ```bash
   helm template library-dev ./helm \
     -f values.yaml \
     -f values-dev.yaml \
     --namespace library-dev
   ```
3. It applies the rendered manifests into the `library-dev` namespace.
4. Kubernetes then creates/updates Pods, Services, PVCs, etc.

**Repo folder mapped to ArgoCD:**
- The `library-dev` and `library-prod` apps both use `path: helm` (the umbrella chart root).
- They only differ by `targetRevision` (branch) and `helm.valueFiles`.

---

## Verifying Pods Are Working

After ArgoCD shows **Synced + Healthy**, verify inside the cluster:

```bash
# 1. See if pods are Running
kubectl get pods -n library-dev
kubectl get pods -n library-prod

# 2. Check pod details if any are not Running
kubectl describe pod -n library-dev <pod-name>

# 3. Check service logs
kubectl logs -n library-dev -l app=book-service --tail=50
kubectl logs -n library-dev -l app=user-service --tail=50
kubectl logs -n library-dev -l app=frontend --tail=50

# 4. Check health endpoints (port-forward)
kubectl port-forward -n library-dev svc/book-service 8081:8081
curl http://localhost:8081/api/books

# 5. Check MongoDB readiness
kubectl logs -n library-dev -l app=mongodb
kubectl get pvc -n library-dev

# 6. Verify from ArgoCD CLI
argocd app get library-dev
argocd app get library-prod
```

> **Rule of thumb:** If ArgoCD says **Healthy** but your app is not responding, the issue is usually inside the container (wrong env vars, missing DB connection) — not in ArgoCD or Helm.

---

## CD Architecture & Reusable Workflows

### Big Picture (CI -> Helm -> ArgoCD -> K8s)

```
Service Repo (e.g., ChapterOne-Book)
  │
  ├── CI Reusable Workflow (_build_trivy.yml)  ← builds image
  ├── CI Reusable Workflow (_push.yml)         ← pushes to Docker Hub
  └── CI Reusable Workflow (_update_helm_chart.yml) ← edits image tag in Helm repo
          │
          ▼
ChapterOne-Helm repo (this repo)
  │  dev branch        →  values-dev.yaml updated
  │  production branch →  values-prod.yaml updated
  │
  ▼
ArgoCD (running in cluster)
  │  detects new commit on branch
  │
  ▼
Kubernetes
   library-dev / library-prod namespaces updated
```

### What Is Already Working

Your existing reusable templates (`ChapterOne-Reusable-Templates`) already contain the CI + "trigger CD" workflow `_update_helm_chart.yml`. When a service pushes to `dev`, this workflow:

1. Clones `ChapterOne-Helm` at the `dev` branch.
2. Uses `yq` to update the correct service image tag in `values-dev.yaml`.
3. Commits and pushes back to the `dev` branch.
4. ArgoCD auto-syncs the change within ~3 minutes.

This means **you do NOT need a separate CD pipeline** in the traditional sense. ArgoCD *is* your CD engine. The only thing a service CI pipeline does is update the desired state in Git.

### What You Can Add: Optional Reusable CD Workflows

If you want services to also call an explicit ArgoCD sync/wait (instead of waiting for the 3-minute poll), you can create caller workflows in each service repo. Here is the recommended pattern, mirroring your existing reusable CI approach:

**1. Create a reusable ArgoCD workflow** in `ChapterOne-Reusable-Templates/.github/workflows/_argocd_sync.yml`:

```yaml
name: Reusable ArgoCD Sync
on:
  workflow_call:
    inputs:
      app_name:
        required: true
        type: string
      argocd_server:
        required: true
        type: string
    secrets:
      ARGOCD_USERNAME:
        required: true
      ARGOCD_PASSWORD:
        required: true
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: Install ArgoCD CLI
        run: |
          curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
          sudo install -m 555 argocd /usr/local/bin/argocd
      - name: Login & Sync
        run: |
          argocd login ${{ inputs.argocd_server }} \
            --username ${{ secrets.ARGOCD_USERNAME }} \
            --password ${{ secrets.ARGOCD_PASSWORD }} \
            --grpc-web --insecure
          argocd app sync ${{ inputs.app_name }} --prune
          argocd app wait ${{ inputs.app_name }} --health
```

**2. Call it from a service repo** (e.g., `ChapterOne-Book/.github/workflows/cd.yml`):

```yaml
name: CD - Sync ArgoCD
on:
  push:
    branches: [dev, production]
jobs:
  sync-dev:
    if: github.ref == 'refs/heads/dev'
    uses: Googleeyy/ChapterOne-Reusable-Templates/.github/workflows/_argocd_sync.yml@main
    with:
      app_name: library-dev
      argocd_server: ${{ vars.ARGOCD_SERVER }}
    secrets:
      ARGOCD_USERNAME: ${{ secrets.ARGOCD_USERNAME }}
      ARGOCD_PASSWORD: ${{ secrets.ARGOCD_PASSWORD }}

  sync-prod:
    if: github.ref == 'refs/heads/production'
    uses: Googleeyy/ChapterOne-Reusable-Templates/.github/workflows/_argocd_sync.yml@main
    with:
      app_name: library-prod
      argocd_server: ${{ vars.ARGOCD_SERVER }}
    secrets:
      ARGOCD_USERNAME: ${{ secrets.ARGOCD_USERNAME }}
      ARGOCD_PASSWORD: ${{ secrets.ARGOCD_PASSWORD }}
```

> **Note:** This is optional. ArgoCD auto-sync already covers 90% of cases. Explicit sync workflows are useful when you want immediate feedback in GitHub Actions or when webhooks are not configured.

---

## What To Do Next

1. **Verify pods are running** using the commands above.
2. **Check ArgoCD auto-sync is enabled:** In the UI, confirm `library-dev` and `library-prod` show `Auto sync is enabled`.
3. **Push a change to a service repo** (e.g., `ChapterOne-Book:dev`) and watch the CI pipeline update `values-dev.yaml` in this repo.
4. **Watch ArgoCD sync:** Within ~3 minutes, the `library-dev` app in ArgoCD should turn blue (syncing) then green (synced + healthy).
5. **(Optional) Add explicit CD caller workflows** in each service repo if you want GitHub Actions to show the ArgoCD sync result inline.
6. **(Optional) Add the `_argocd_sync.yml` reusable template** to `ChapterOne-Reusable-Templates` so all services share the same sync logic.

---

## Real-Life Internal Working (Step-by-Step)

**Scenario: Developer pushes a bug-fix to `book-service:dev`**

1. **GitHub Actions** in `ChapterOne-Book` triggers on `push:dev`.
2. **Prepare job** computes tag `dev-a1b2c3d`.
3. **Build job** compiles JAR, builds Docker image, scans with Trivy.
4. **Push job** pushes `googleyy/chapterone-book:dev-a1b2c3d` to Docker Hub.
5. **Update-Helm job** (reusable `_update_helm_chart.yml`) clones this repo (`ChapterOne-Helm:dev`), edits `bookService.image.tag` to `dev-a1b2c3d` in `values-dev.yaml`, commits, and pushes.
6. **ArgoCD** (running inside your cluster) detects the new commit on `dev`.
7. ArgoCD runs `helm template` with `values-dev.yaml`.
8. Kubernetes sees the `book-service` Deployment manifest now has a new image tag.
9. Kubernetes performs a **RollingUpdate**: creates new pod with `dev-a1b2c3d`, waits for readiness probe (`/api/books`), then terminates old pod.
10. ArgoCD marks `library-dev` as **Healthy** once all pods pass readiness.

At no point did a human run `kubectl apply` or `helm upgrade`. The entire flow was Git -> CI -> Git (Helm repo) -> ArgoCD -> Kubernetes.
