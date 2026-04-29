# ChapterOne Library Platform — End-to-End Kubernetes Architecture Prompt

## Your Role
Generate a comprehensive end-to-end Kubernetes architecture diagram with detailed documentation for the **ChapterOne Library Management Platform**.

**Output:**
1. Mermaid architecture diagram (flowchart)
2. Component tables
3. Traffic flow narratives
4. Written explanations per layer

---

## Project Context

**GitHub Org:** `Googleeyy` (https://github.com/Googleeyy)  
**Helm Repo:** `ChapterOne-Helm`  
**Reusable Workflows:** `ChapterOne-Reusable-Templates`

**Microservices:**
| Service | Port | DB | Internal DNS |
|---------|------|----|-------------|
| book-service | 8081 | chapterone_books | `book-service.<ns>.svc.cluster.local` |
| user-service | 8082 | chapterone_users | `user-service.<ns>.svc.cluster.local` |
| borrow-service | 8083 | chapterone_borrows | `borrow-service.<ns>.svc.cluster.local` |
| frontend | 80 | N/A | `frontend.<ns>.svc.cluster.local` |
| mongodb | 27017 | All | `mongodb-0.mongodb.<ns>.svc.cluster.local` |

**Environments:** `library-dev` (1 replica, dev tags, low resources) and `library-prod` (3 replicas, HPA 3-10, TLS, strict policies).

---

## Architecture Layers

### Layer 1: External Ingress — HAProxy
- Deployment + LoadBalancer Service in target namespace
- Ports 80/443. Receives browser traffic, forwards to KGateway
- Prod: 2 replicas, limits 100m-200m CPU / 128Mi-256Mi memory
- Dev: disabled

### Layer 2: Gateway API — KGateway
- **GatewayClass:** `kgateway` (controller in `kgateway-system`)
- **Gateway:** `library-e2e-gateway`, listener port 80, `allowedRoutes: Same` namespace
- **HTTPRoutes** (`infrastructure/gateway/templates/httproute.yaml`):
  - `/api/books` → `book-service:8081`
  - `/api/users` → `user-service:8082`
  - `/api/borrows` → `borrow-service:8083`
  - `/health` → `book-service:8081`
  - `/` → `frontend:80` (injects `X-Forwarded-Path`)
- Controller watches CRDs, translates to Envoy xDS config. Hot reload, no restart.

### Layer 3: Microservices
Each has: Deployment (Git SHA image tag, probes), ClusterIP Service, ConfigMap (MONGO_URI), Secret, HPA (prod only, CPU 70%, mem 80%, min 3 max 10).

**Borrow Service orchestration:** Receives request → calls `user-service:8082` → calls `book-service:8081` → creates record → responds.

### Layer 4: Data — MongoDB StatefulSet
- 1 replica, headless Service `mongodb`, PVC via `nfs-client` StorageClass
- Dev: 1Gi, Prod: 10Gi
- Init ConfigMap seeds 20 sample books on first start

### Layer 5: GitOps — ArgoCD
- Namespace: `argocd`
- App of Apps: `app-of-apps.yaml` (dev) and `app-of-apps-prod.yaml` (prod) with `recurse: true`
- Child apps per service with `sync-wave` ordering (-2 infra, -1 gateway, 0 apps)
- Auto sync: `prune: true`, `selfHeal: true`, `CreateNamespace=true`, `ServerSideApply=true`

### Layer 6: Security
- **Sealed Secrets:** `sealed-secrets-prod/` contains encrypted secrets. Asymmetric, namespace-bound.
- **NetworkPolicy** (`templates/network-policy.yaml`, prod only):
  - Allow same-namespace ingress/egress
  - Allow DNS (kube-system:53), kgateway-system, MongoDB:27017
  - Deny cross-namespace by default

### Layer 7: Observability
- Prometheus + Grafana in `monitoring`. Scrapes all namespaces.
- Alerts: CPU >80% 5min, Memory >85%, Pod restarts >3/10min, ArgoCD OutOfSync >10min.

### Layer 8: CI/CD Integration
- GitHub Actions reusable workflows build, scan (Trivy), push (Docker Hub `googleyy/*`), update Helm values via `yq`, notify Slack.
- ArgoCD detects Helm changes and syncs to cluster.

---

## Diagram Requirements

Generate a Mermaid flowchart with:
- Subgraphs: [External User], [library-prod], [library-dev], [argocd], [monitoring], [kgateway-system], [kube-system]
- HAProxy LoadBalancer as external entry point
- KGateway (Envoy) with HTTPRoute diamonds
- Deployments + Services + Pods for all 4 microservices
- MongoDB StatefulSet + PVC
- ArgoCD App-of-Apps hierarchy
- Prometheus scrape arrows
- SealedSecret → Secret transformation
- NetworkPolicy firewall boundary around prod
- CI/CD external boxes (GitHub, Docker Hub) with dashed arrows
- Color code: Green=user, Blue=infra, Orange=data, Purple=GitOps, Red=security

Also generate:
- **Request Flow:** Browser → HAProxy → KGateway → HTTPRoute → Service → Pod → MongoDB
- **GitOps Flow:** Push → Actions → Docker Hub → Helm update → ArgoCD sync → Cluster
- **Namespace Isolation:** Allowed/denied traffic matrix
- **HPA Scaling:** Metrics Server → HPA → Deployment → ReplicaSet → Pods

---

## Written Explanations

For each component, provide:
1. **What it is**
2. **Why it exists in this project**
3. **Which file defines it** (path in `ChapterOne-Helm`)
4. **Key configuration values**
5. **What happens if it fails**

For traffic flows, provide step-by-step packet narratives with:
- Source IP/Service
- Destination IP/Service
- Protocol and port
- Kubernetes resource handling the hop
- Any transformation (path rewrite, header injection, load balancing)

---

## Reference URLs to Include

- https://github.com/Googleeyy
- https://github.com/Googleeyy/ChapterOne-Helm
- https://github.com/Googleeyy/ChapterOne-Reusable-Templates/tree/main/.github/workflows

---

## Output Format

```markdown
# ChapterOne Library Platform — Kubernetes Architecture

## 1. High-Level Architecture Diagram
[Mermaid diagram]

## 2. Component Inventory
[Tables]

## 3. Layer-by-Layer Deep Dive
[Written explanations]

## 4. Traffic Flow Narratives
[Step-by-step request journeys]

## 5. Supplementary Diagrams
[Request flow, GitOps flow, isolation, HPA]

## 6. Failure Scenarios
[What breaks if each component fails]
```

Ensure the diagram is technically accurate to the project's actual Helm templates and values files.
