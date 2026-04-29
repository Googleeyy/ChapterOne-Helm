# ChapterOne Library Management Platform — End-to-End Application Explanation

> Written from the perspective of a junior DevOps trainee documenting what was built, why each choice was made, and how every component connects.

---

## 1. What Is This Project?

The **ChapterOne Library Management Platform** is a microservices-based library system I built during my DevOps training to understand how code travels from a developer's laptop to a user's browser. It is not just an application — it is a complete platform with automated CI/CD, GitOps deployment, security scanning, ingress routing, secrets management, and monitoring.

**GitHub Organization:** https://github.com/Googleeyy  
**Helm Charts & GitOps:** https://github.com/Googleeyy/ChapterOne-Helm  
**Reusable CI Workflows:** https://github.com/Googleeyy/ChapterOne-Reusable-Templates/tree/main/.github/workflows

The platform has:
- **4 backend microservices** (Book, User, Borrow) + **1 Frontend**
- **MongoDB** as the shared database layer
- **Kubernetes** for container orchestration
- **Helm** for packaging all Kubernetes manifests
- **GitHub Actions** for CI/CD with reusable workflows
- **ArgoCD** for GitOps continuous deployment
- **KGateway + HAProxy** for layered ingress routing
- **Sealed Secrets** for encrypted secret management in Git
- **Network Policies** for namespace-level firewall rules
- **Prometheus + Grafana** for monitoring

---

## 2. The Application Layer — What the User Sees

### 2.1 Book Service (`googleyy/chapterone-book`)
- **Framework:** Java Spring Boot
- **Port:** 8081
- **Purpose:** Manages the book inventory. CRUD operations for books — add a book, list all books, update a book's details, delete a book.
- **Database:** `chapterone_books` collection in MongoDB
- **ConfigMap reference:** `book-service-config` mounts `MONGO_URI` pointing to `mongodb://mongodb.library-dev.svc.cluster.local:27017/chapterone_books_dev`
- **Health check:** TCP socket probe on port 8081

When I started, I thought one monolithic Java app would be simpler. But I learned that splitting into microservices forces you to think about service boundaries, API contracts, and independent deployments. The Book Service owns everything about books — no other service touches the `chapterone_books` database directly.

### 2.2 User Service (`googleyy/chapterone-user`)
- **Framework:** Java Spring Boot
- **Port:** 8082
- **Purpose:** User registration, authentication, and JWT token issuance
- **Database:** `chapterone_users` collection in MongoDB
- **Secrets:** `user-service-secret` contains `JWT_SECRET` (sealed in production)
- **Health check:** `/actuator/health` endpoint

I learned about JWT (JSON Web Tokens) here. The User Service signs tokens with a secret. When a user logs in, they get a token. Every subsequent API call to the Borrow Service includes that token in the `Authorization` header, and the Borrow Service validates it (or asks the User Service to validate it internally).

### 2.3 Borrow Service (`googleyy/chapterone-borrow`)
- **Framework:** Java Spring Boot
- **Port:** 8083
- **Purpose:** The orchestrator. Handles "borrow a book" and "return a book" operations.
- **Database:** `chapterone_borrows` collection in MongoDB
- **Internal calls:** Makes HTTP requests to User Service (verify user) and Book Service (check availability)
- **Health check:** `/api-docs` endpoint

This was the most interesting service to build because it taught me about **distributed systems**. When someone borrows a book, the Borrow Service does NOT own the user data or the book data. It asks the other services. This pattern is called **orchestration** — one service coordinates work across others.

The internal DNS names I learned about:
```
http://user-service.library-dev.svc.cluster.local:8082/api/users/{id}
http://book-service.library-dev.svc.cluster.local:8081/api/books/{id}
```

Kubernetes kube-dns resolves `user-service.library-dev.svc.cluster.local` to the ClusterIP of the User Service, which load-balances across all User Service pods.

### 2.4 Frontend (`googleyy/chapterone-frontend`)
- **Framework:** React (JavaScript)
- **Port:** 80
- **Purpose:** The user interface. A web page where librarians and users can search books, see borrowing history, and manage accounts.
- **API base URL:** `http://library-dev.local` (configured via ConfigMap)
- **Health check:** HTTP GET on `/`

The frontend taught me about cross-origin concerns and why we need a unified gateway. The browser talks to one domain (`library.local`), and the gateway routes to the correct backend based on the URL path.

### 2.5 MongoDB (`mongo:7.0`)
- **Type:** StatefulSet with 1 replica
- **Port:** 27017
- **Purpose:** Shared database server hosting three logical databases:
  - `chapterone_books_dev` / `chapterone_books` (prod)
  - `chapterone_users_dev` / `chapterone_users` (prod)
  - `chapterone_borrows_dev` / `chapterone_borrows` (prod)
- **Storage:** `nfs-client` StorageClass, PVC mounted at `/data/db`
  - Dev: 1Gi
  - Prod: 10Gi
- **Init script:** A ConfigMap (`init-script-configmap.yaml`) seeds 20 sample books when the StatefulSet starts for the first time

I chose MongoDB because I was learning about microservices and my data models kept changing. With a document database, I didn't need to write SQL migration scripts every time I added a field. The three databases are logically separate inside one MongoDB server, which is simpler operationally than running three PostgreSQL instances. The trade-off is no ACID transactions across collections, but for a library system, that is acceptable.

---

## 3. Docker & Containerization

Each microservice has its own Dockerfile in its respective repository under `Googleeyy`.

### Why Docker?
Before this project, I thought Docker was "a lightweight VM." Building this taught me Docker is really about **immutable application packaging**. I build the Java JAR or the React bundle, put it in an image, and that image runs identically on my laptop, in the CI runner, and in the Kubernetes cluster.

### Multi-Stage Builds
I learned about multi-stage Dockerfiles:
1. **Builder stage:** Use a full JDK + Maven/Node image to compile the code.
2. **Runtime stage:** Copy only the compiled artifact (JAR or static files) into a smaller JRE or Nginx base image.

This keeps images small and reduces the attack surface — fewer packages in the final image means fewer things to patch.

### Image Tagging Strategy
Images are tagged with the **Git commit SHA** for immutable traceability.

| Environment | Image Tag Example |
|-------------|-------------------|
| Dev | `dev-a1b2c3d` |
| Prod | `v1.0.0` (semantic) + `prod-d4e5f6a` (SHA) |

The tag `dev-399298d` tells you exactly which Git commit is running. If production breaks, I know precisely which code change caused it. The image Trivy scanned in CI is the EXACT image that runs in the cluster. No rebuild, no "works in CI but fails in prod."

### Docker Hub
All images are published to `googleyy/<service-name>` on Docker Hub. This is free for public repositories and integrates natively with GitHub Actions.

---

## 4. Kubernetes & Helm — Packaging Everything

When I first saw Kubernetes, I was overwhelmed — every microservice needs a Deployment, a Service, a ConfigMap, maybe a Secret, an HPA... and I had four services plus MongoDB plus a gateway. Writing 30+ YAML files by hand felt wrong.

Then I learned about **Helm**.

### The Umbrella Chart (`library-e2e`)
Helm lets you package Kubernetes manifests into "charts." An umbrella chart is a chart that depends on other charts. In `ChapterOne-Helm/Chart.yaml`, I declared 6 dependencies:

```yaml
dependencies:
  - name: mongodb
    repository: file://infrastructure/mongodb
  - name: gateway
    repository: file://infrastructure/gateway
  - name: book-service
    repository: file://microservices/book-service
  - name: user-service
    repository: file://microservices/user-service
  - name: borrow-service
    repository: file://microservices/borrow-service
  - name: frontend
    repository: file://microservices/frontend
```

Running `helm dependency update` packages all subcharts into `charts/*.tgz` files. One command bundles the entire platform.

### Values Hierarchy
Helm has a powerful override system. I learned that values flow from least to most specific:

1. **Subchart `values.yaml`** — defaults (e.g., `namespace: chapterone`, `replicas: 1`)
2. **Parent `values.yaml`** — project-wide defaults
3. **Environment files** — `values-dev.yaml` and `values-prod.yaml` — the highest priority

For example, `values-dev.yaml` sets:
```yaml
global:
  namespace: library-dev
bookService:
  replicas: 1
  autoscaling:
    enabled: false
```

While `values-prod.yaml` sets:
```yaml
global:
  namespace: library-prod
bookService:
  replicas: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
```

The **same Helm chart** deploys to both environments. Only the configuration changes. This is called **environment parity**.

### Global Namespace Propagation
A lightbulb moment for me was `global.namespace`. Setting it in the parent `values-dev.yaml` automatically flows to ALL subcharts via Helm's `global` key. I don't repeat `namespace: library-dev` in six places. One variable places every pod, service, and secret into the right namespace.

---

## 5. Namespace Division — Dev vs Prod on One Cluster

I initially thought dev and prod needed separate clusters. Then I learned about Kubernetes **namespaces** — they provide logical isolation at the API server level.

### Why Namespaces Instead of Two Clusters?
- **Cost:** As a trainee, I didn't have budget for two clusters.
- **Operational simplicity:** One Kubernetes API to learn, one ArgoCD instance to manage.
- **Realistic:** Many real startups start this way.

### What Changes Between Environments?

| Feature | Dev (`library-dev`) | Prod (`library-prod`) |
|---------|--------------------|-----------------------|
| Replicas | 1 per service | 3 per service |
| HPA | Disabled | Enabled (3–10 replicas) |
| MongoDB Storage | 1Gi | 10Gi |
| CPU Request | 100m | 250m |
| Memory Request | 128Mi | 256Mi |
| TLS | Disabled | Enabled |
| Network Policy | Disabled | Enabled |
| Image Tag | `dev-<sha>` | Semantic version |
| HAProxy | Disabled | Enabled (2 replicas) |

The templates are identical. The only difference is the configuration layer. If it works in dev, the Helm chart itself is proven correct — I just change variables for prod.

---

## 6. GitHub Actions & Reusable Workflows

### Why GitHub Actions Instead of Jenkins?
I evaluated Jenkins but as a trainee, setting up a Jenkins master with agents felt like extra infrastructure I didn't need. GitHub Actions won because:
1. Native GitHub integration — no separate server to maintain.
2. `workflow_call` allows a single definition to be called from any repo.
3. GitHub-hosted runners scale automatically — I don't manage agent pools.
4. Secrets live in the same platform where my code lives.
5. Everyone on the team already has a GitHub account.

### The Reusable Templates Repository
I started by writing GitHub Actions in every microservice repo. Then I changed a Trivy scan threshold in one repo, forgot to update the other three, and had inconsistent builds. That taught me about **reusable workflows**.

In `ChapterOne-Reusable-Templates/.github/workflows/`, I created:

| Workflow | Purpose |
|----------|---------|
| `_build_trivy.yml` | Builds Docker image + runs Trivy vulnerability scan. Fails on CRITICAL/HIGH CVEs. |
| `_push.yml` | Loads artifact, pushes to Docker Hub. In prod, tags `latest` + creates Git tag. |
| `_update_helm_chart.yml` | Clones `ChapterOne-Helm`, checks out correct branch, uses `yq` to update image tag in `values-dev.yaml` or `values-prod.yaml`, commits as `github-actions[bot]`. |
| `_snyk.yml` | Scans Maven/npm dependencies for CVEs. |
| `_sonar.yml` | SonarQube code quality gates. I learned about "code smells" and "cyclomatic complexity." |
| `_notify.yml` | Slack webhook notification. A silent pipeline is a pipeline nobody trusts. |

### DRY Principle
DRY stands for "Don't Repeat Yourself." Now, if I need to change the Trivy severity threshold, I edit ONE file in `ChapterOne-Reusable-Templates`. All 4 microservices inherit it instantly. This taught me the real value of centralized CI governance.

---

## 7. CI/CD Pipeline — The Complete Flow

This is the part I'm most proud of understanding. Here is the EXACT timeline from commit to cluster:

**Step 1:** Developer pushes to the `dev` branch in `ChapterOne-Book` under `Googleeyy`.

**Step 2:** The service repo calls `_build_trivy.yml` via `workflow_call`. I learned that `workflow_call` is how GitHub Actions does "functions."

**Step 3:** Java 21 Temurin builds the JAR with Maven. Then Docker builds the image.

**Step 4:** **Trivy scans the image BEFORE it ever leaves the GitHub runner.** This is "shift-left security" — catching vulnerabilities before they reach the registry. If CRITICAL or HIGH CVEs are found, the pipeline FAILS here. Nothing gets pushed.

**Step 5:** The image is saved as a GitHub Actions artifact (1-day retention). Artifacts are temporary storage between workflow jobs.

**Step 6:** `_push.yml` downloads the artifact, loads the image, and pushes `googleyy/chapterone-book:dev-a1b2c3d` to Docker Hub.

**Step 7:** `_update_helm_chart.yml` checks out `ChapterOne-Helm:dev` branch.
- It converts kebab-case to camelCase: `book-service` → `bookService` using `sed`. I learned about case conventions in different systems.
- It runs `yq` to set `bookService.image.tag = "dev-a1b2c3d"` inside `values-dev.yaml`.
- It commits as `github-actions[bot]` and pushes back using `HELM_REPO_PAT`. I learned about Personal Access Tokens for cross-repo authentication.

**Step 8:** `_notify.yml` posts success or failure to the Slack `#deployments` channel.

**What I learned about zero-touch deployment:** After step 8, a human NEVER runs `kubectl apply` or `helm upgrade`. The ONLY thing that touches the cluster is ArgoCD. This separation of CI (build) and CD (deploy) was a key DevOps principle I finally understood.

---

## 8. GitHub Branch Strategy

I made a mistake early: I pushed everything to one branch and accidentally deployed broken code. That taught me why branch strategy matters.

- **`dev` branch:** Active development, auto-deploys to `library-dev` namespace.
- **`production` branch:** Protected, requires PR review, deploys to `library-prod`.

### Branch Protection Rules on `production`
- **Require PR + 1 approval** — prevents direct pushes that skip review.
- **Dismiss stale approvals on new commits** — if someone pushes new code after approval, the old approval is invalidated.
- **Require status checks (`helm-validate`)** — runs `helm lint` and `helm template` dry-run before merge.
- **Block force pushes** — prevents `git push --force` which could rewrite history.

### Promotion Model
1. Test in `dev`
2. Create PR from `dev` → `production` in `ChapterOne-Helm`
3. Someone reviews
4. Merge
5. ArgoCD detects the merge and syncs to `library-prod`

The CI bot uses `HELM_REPO_PAT` to push directly to `dev` because automated CD needs speed. But **human changes MUST go through PRs.** This taught me the difference between machine automation and human governance.

---

## 9. ArgoCD & GitOps

I used to think deploying meant running `kubectl apply` from my laptop. Then I learned about **GitOps** — the idea that Git is the single source of truth, and a controller makes the cluster match Git.

### Why ArgoCD?
1. **Visual UI** — green = synced, yellow = progressing, red = failed. As a trainee, this helped me understand what was happening.
2. **Declarative Application CRDs** — apps defined as YAML inside the Git repo.
3. **Built-in Helm support** — ArgoCD runs `helm template` with my exact `values-dev.yaml` or `values-prod.yaml`.
4. **Self-healing** — I tested this manually. I ran `kubectl edit deployment` to change a replica count, and within minutes ArgoCD reverted it. Git always wins.
5. **Pruning** — I removed a Service from Git, pushed, and ArgoCD deleted it from the cluster. "Prune" means garbage collection for Kubernetes.
6. **Rollback history** — every Git commit is a rollback point. Reverting a Git commit IS a production rollback.

### Installation
I installed ArgoCD using its own Helm chart from `argo/argo-cd`, with a custom `argocd-values.yaml` exposing NodePort 30080. I disabled Dex to keep authentication simple while learning.

### App of Apps Pattern
An ArgoCD Application that manages OTHER ArgoCD Applications. It's like a manager whose direct reports are also managers.

In `ChapterOne-Helm`:
- `app-of-apps.yaml` (dev) → watches the `argocd-apps/` directory on `dev` branch
- `app-of-apps-prod.yaml` (prod) → watches `argocd-apps-prod/` on `production` branch
- Both use `directory: recurse: true` so they discover ALL YAML files in those directories automatically.

**Why this pattern clicked:**
- Adding a new microservice means adding ONE YAML file to `argocd-apps/apps/`. The root app discovers it automatically. No `kubectl apply` needed.
- All child apps inherit sync policies from the parent.

### Individual Application Manifests
Each service has its own ArgoCD Application manifest:
- `sync-wave: "0"` — controls deployment ORDER. Infrastructure like MongoDB might be wave "-2", gateway wave "-1", microservices wave "0".
- `automated: prune: true, selfHeal: true`
- `CreateNamespace=true` — ArgoCD creates `library-dev` or `library-prod` if they don't exist.
- `ServerSideApply=true` — newer Kubernetes apply mechanism that handles field ownership better.
- Retry: 3 attempts with exponential backoff (5s → 10s → 20s) — prevents transient errors from failing the whole sync.

---

## 10. Inside the Cluster — Deployments, Services, HPA, ConfigMaps

### Deployments
Each microservice has a Deployment under `microservices/<service>/templates/deployment.yaml`:
- Pulls the exact image tag from values (e.g., `dev-399298d`).
- Mounts `MONGO_URI` from a ConfigMap — ConfigMaps are for non-sensitive configuration.
- **Readiness probes** (`tcpSocket` on port 8081) tell Kubernetes when a pod is ready to receive traffic.
- **Liveness probes** tell Kubernetes when to restart a crashing pod.
- `imagePullPolicy: IfNotPresent` — Kubernetes only pulls the image if it's not already cached on the node.

### Services
Standard ClusterIP Services for internal DNS discovery:
- `book-service` resolves to the Book Service pods via kube-dns.
- `mongodb-0.mongodb` resolves to the MongoDB StatefulSet pod via headless service.
- Internal DNS format: `<service>.<namespace>.svc.cluster.local`

### ConfigMaps
Each service mounts its own ConfigMap. For example, `book-service-config` contains:
```yaml
APP_NAME: "Book Service"
HOST: "0.0.0.0"
PORT: "8081"
MONGO_URI: "mongodb://mongodb.library-dev.svc.cluster.local:27017/chapterone_books_dev"
```

The MongoDB init script ConfigMap (`init-script-configmap.yaml`) seeds 20 sample books on first startup. I learned that init scripts in StatefulSets run only when the volume is empty.

### HorizontalPodAutoscaler (HPA)
Only enabled in production (`values-prod.yaml`).
- Target: 70% CPU, 80% memory.
- Min 3 replicas, max 10.
- The YAML has a `scaleTargetRef` pointing to the Deployment name, and a `metrics` block telling the Metrics Server what to watch.

I learned that HPA queries the Kubernetes Metrics API every 15 seconds. If average CPU across all pods exceeds 70%, it adds replicas. If below threshold for a sustained period, it scales down. Dev doesn't need HPA — one replica is enough and saves cluster resources.

---

## 11. Gateway Routing — KGateway + HAProxy in Detail

I originally thought Kubernetes "just routes traffic." Then I tried accessing my services from outside the cluster and realized I needed a proper ingress layer. I researched Ingress, then discovered Gateway API, and chose KGateway because it's the modern standard.

### Layer 1: HAProxy (The External Edge / Load Balancer)
HAProxy is deployed via `infrastructure/gateway/templates/haproxy.yaml` as a Deployment + LoadBalancer Service.
- It listens on ports 80 (HTTP) and 443 (HTTPS for future TLS).
- Its job: be the single external entry point. The HAProxy Service gets a real external IP (from the LoadBalancer) or a NodePort IP that browsers can reach.
- In production, HAProxy is enabled with 2 replicas and resource limits. In dev, it's disabled to save resources.

**Why HAProxy?**
- NGINX Ingress is common but I wanted to learn something new.
- HAProxy is battle-tested for 20+ years, extremely lightweight, and supports both TCP and HTTP routing.
- It gives a clear separation: HAProxy handles the "outside world → cluster" boundary, while KGateway handles "inside the cluster → correct microservice" routing.

**What HAProxy actually does:** It receives the HTTP request from the user's browser and forwards it to the KGateway pods. It can do round-robin load balancing across multiple KGateway instances.

### Layer 2: KGateway (The Kubernetes-Native Router)
**What is KGateway?** It's an implementation of the Kubernetes **Gateway API** (`gateway.networking.k8s.io/v1`), the official successor to the older Ingress API. KGateway uses **Envoy** under the hood as its data plane.

**Why Gateway API instead of Ingress?**
1. **More expressive routing** — Ingress only supports host and path. Gateway API supports HTTPRoute, TCPRoute, TLSRoute, GRPCRoute, and custom filters like header modification.
2. **Separation of concerns** — The cluster admin defines the `Gateway` resource (listener, port, TLS). The app developer defines `HTTPRoute` resources (path matching). In Ingress, one object mixes both roles. This is important for RBAC in teams.
3. **Future-proof** — The Kubernetes SIG-Network community is investing in Gateway API as the long-term standard.

**The Gateway resource** (`infrastructure/gateway/templates/gateway.yaml`):
- Name: `library-e2e-gateway`
- GatewayClass: `kgateway` — tells Kubernetes which controller should manage it.
- Listener: port 80, protocol HTTP, name "http"
- `allowedRoutes: from: Same` — a security feature. Only HTTPRoutes in the SAME namespace can attach to this Gateway. It prevents accidental hijacking from other namespaces.

**The HTTPRoute resources** (`infrastructure/gateway/templates/httproute.yaml`):
There are TWO HTTPRoute objects: `api-route` and `frontend-route`.

Each HTTPRoute has `parentRefs` pointing to `library-e2e-gateway` — this is the "attachment" mechanism.

Path matching rules:
| Path | Backend Service | Port |
|------|----------------|------|
| `/api/books` | `book-service` | 8081 |
| `/api/users` | `user-service` | 8082 |
| `/api/borrows` | `borrow-service` | 8083 |
| `/health` | `book-service` | 8081 |
| `/` | `frontend` | 80 |

The frontend route also has a `RequestHeaderModifier` filter injecting `X-Forwarded-Path: /`. Each route has `timeouts: request: 30s` to prevent hung connections.

**What the KGateway controller does:**
There is a control plane and a data plane:
1. The KGateway controller (running in `kgateway-system` namespace) watches the `Gateway` and `HTTPRoute` resources via the Kubernetes API.
2. When a route is created or changed, the controller translates it into Envoy configuration via the xDS protocol.
3. The Envoy proxy (the data plane) receives this config and starts routing traffic accordingly.
4. This is called "dynamic configuration" — Envoy hot-reloads without restart.

### The Complete Request Walkthrough

Here is what happens, step by step, when a user opens their browser and visits `http://library.local/api/books`:

**Step 1:** User types `http://library.local/api/books` in the browser.

**Step 2:** DNS resolution happens. `library.local` resolves to the HAProxy LoadBalancer IP (or NodePort IP).

**Step 3:** HAProxy receives the TCP connection on port 80. It accepts the HTTP request with headers like `Host: library.local` and path `/api/books`.

**Step 4:** HAProxy forwards the request into the Kubernetes cluster. It targets the KGateway Service endpoints. HAProxy's LoadBalancer distributes across available KGateway pods.

**Step 5:** KGateway (Envoy data plane) receives the request. It looks at the HTTP host header and the path.

**Step 6:** KGateway matches against HTTPRoute rules loaded from the Kubernetes API:
- Path starts with `/api/books`? Yes → match rule 1.
- Which backend? `book-service` on port 8081.

**Step 7:** KGateway rewrites the destination internally. It knows from Kubernetes Endpoints that `book-service` currently points to Pod IPs (e.g., `10.244.1.15:8081`, `10.244.2.8:8081`).

**Step 8:** KGateway opens a new connection to the Book Service Pod (or reuses an existing connection from Envoy's connection pool). The request is forwarded.

**Step 9:** Book Service Pod receives the HTTP request on port 8081. Spring Boot routes it to the `/api/books` controller.

**Step 10:** Book Service needs data. It connects to MongoDB using the `MONGO_URI` from its ConfigMap: `mongodb://mongodb.library-dev.svc.cluster.local:27017/chapterone_books_dev`.

**Step 11:** MongoDB StatefulSet (`mongodb-0`) receives the query from the Book Service Pod over the cluster network.

**Step 12:** Response flows back: MongoDB → Book Service → KGateway → HAProxy → User's Browser.

### Internal Service-to-Service Call (Borrow Request)
When a user borrows a book, the flow is even more interesting because it shows **east-west traffic** inside the cluster:

1. User hits `/api/borrows` → routes to Borrow Service (port 8083) via the same HAProxy → KGateway path.
2. Borrow Service's business logic says: "I need to verify this user exists and this book is available."
3. Borrow Service makes an **internal HTTP call** to `http://user-service.library-dev.svc.cluster.local:8082/api/users/{id}`.
4. Then it calls `http://book-service.library-dev.svc.cluster.local:8081/api/books/{id}`.
5. This is **service-to-service communication inside the cluster** — it never leaves Kubernetes. It uses kube-dns for name resolution and ClusterIP Services for load balancing across pods.
6. Both responses return → Borrow Service creates the borrow record → responds to the user.

### What I Learned About Networking
- HAProxy handles **north-south** traffic (external → cluster).
- KGateway handles **north-south** routing at the application layer using Gateway API.
- Service-to-service calls (Borrow → Book) are **east-west** traffic and use Kubernetes DNS + ClusterIP directly, bypassing the gateway entirely for efficiency.
- This separation taught me that not all traffic should go through the edge gateway — internal calls should be direct.

---

## 12. Sealed Secrets — Git-Safe Secrets

I needed to store a JWT secret and MongoDB credentials in Git so ArgoCD could deploy them. But I learned that Kubernetes Secrets are only base64-encoded — that's NOT encryption. Anyone who clones the repo can read them.

**The solution I implemented:** Bitnami Sealed Secrets.

1. Create a standard Kubernetes Secret locally (e.g., `user-service-secret` with `JWT_SECRET`).
2. Run `kubeseal` CLI against your cluster's public key. This produces a `SealedSecret` CRD.
3. Commit the `SealedSecret` YAML to Git safely — it's encrypted and cryptographically bound to a specific namespace.
4. ArgoCD syncs the `SealedSecret` into the cluster.
5. The Sealed Secrets Controller (running in the cluster) decrypts it and creates a native `Secret` ONLY in the target namespace.

### What I Learned
- The encryption is asymmetric. `kubeseal` uses the cluster's PUBLIC key. Only the controller in the cluster has the PRIVATE key.
- If someone steals the `SealedSecret` file, they can't decrypt it without access to the cluster.
- The secret is namespace-bound — a SealedSecret encrypted for `library-prod` cannot be decrypted in `library-dev` or `default`. This prevents accidental leakage.

**Production usage in my project:** `sealed-secrets-prod/` directory in `ChapterOne-Helm` contains production SealedSecrets.

### Why Not Vault?
I evaluated HashiCorp Vault but realized it requires running a Vault server, unsealing it, managing tokens, and setting up AppRoles. That's a whole infrastructure project on its own. Sealed Secrets is simpler, self-hosted, has zero external cloud dependency. Vault is enterprise-grade; Sealed Secrets is pragmatic-grade.

---

## 13. Network Policies — My First Kubernetes Firewall

By default, Kubernetes allows ALL pods to talk to ALL other pods in ALL namespaces. I didn't realize this until I read about it. That's like having no firewall inside your datacenter.

My network policy is located in `templates/network-policy.yaml` in `ChapterOne-Helm`.
- Enabled in production (`values-prod.yaml: networkPolicy.enabled: true`)
- Disabled in dev (`values-dev.yaml: networkPolicy.enabled: false`)

### What My Policy Does
- **Ingress:** Allows all traffic from within the SAME namespace. So Book Service can talk to MongoDB, Borrow Service can talk to Book Service, Frontend can talk to Gateway.
- **Egress to kube-system:** Allows DNS resolution on TCP/UDP port 53. Without this, pods can't resolve service names like `mongodb.library-dev.svc.cluster.local`.
- **Egress to kgateway-system:** Allows the gateway controller to receive configuration updates.
- **Egress to MongoDB:** Explicitly allows TCP port 27017 to the MongoDB pod.
- **Default deny:** Everything else is blocked. A pod in `default` namespace cannot reach my services.

The Helm template uses `{{ .Values.global.namespace }}` so the same policy works in `library-dev` or `library-prod`. I learned that using Helm variables makes one template work across environments.

### Why a "Light" Policy?
I started permissive. I learned that "default deny all + whitelist" is the zero-trust principle, but if you're too strict on day one, you break legitimate traffic and spend hours debugging. My policy allows all intra-namespace traffic because I trust my own microservices, but blocks external namespaces.

### Defense in Depth
NetworkPolicy is just one layer. Combined with:
- Trivy (clean images, no known CVEs)
- RBAC (who can access the Kubernetes API)
- Sealed Secrets (credential encryption)
...you get multiple overlapping security controls.

---

## 14. NFS Storage — How I Learned Persistent Volumes

I thought containers were stateless. Then I realized MongoDB needs to survive pod restarts, and that means storage.

MongoDB runs as a **StatefulSet** with a PersistentVolumeClaim template. StatefulSets are for stateful applications because they guarantee pod identity — `mongodb-0` always comes back as `mongodb-0`, with the same storage attached.

### How Dynamic Provisioning Works
1. When the StatefulSet creates `mongodb-0`, the `volumeClaimTemplates` block requests a PVC.
2. The `nfs-client` provisioner sees the PVC with StorageClass `nfs-client`.
3. It dynamically creates a folder on the NFS server and maps it as a PersistentVolume.
4. The PV is mounted at `/data/db` inside the MongoDB container.

I set up an NFS server in another cluster (or on dedicated storage nodes), then installed the `nfs-client` provisioner in my Kubernetes cluster.

### Why NFS?
- Universal protocol — works on-prem, in VMs, in cloud.
- The `nfs-client` provisioner is easy to set up and creates folders automatically.
- I didn't want cloud-provider lock-in (EBS, Azure Disk) because I was learning on a generic cluster.

Dev: 1Gi. Prod: 10Gi. Same chart, different values — this is the power of Helm.

### What I Know Now
For true production at scale, I'd move to distributed storage like Ceph, Longhorn, or a cloud CSI driver. NFS is my pragmatic, vendor-neutral learning choice. It's good enough for a trainee project and teaches me the Kubernetes storage abstraction layer.

---

## 15. Monitoring & Observability

I deployed my first service, it crashed, and I didn't know why. That's when I learned: you cannot operate what you cannot observe.

### Prometheus + Grafana
I deployed Prometheus and Grafana in a `monitoring` namespace.

**Prometheus:** Scrapes metrics via HTTP endpoints. Every pod exposes `/metrics` (or Prometheus discovers them via ServiceMonitor CRDs). It stores time-series data. Prometheus scrapes metrics from both `library-dev` and `library-prod` — namespace boundaries don't stop monitoring if you configure scrape targets correctly.

**Grafana dashboards I set up:**
- Cluster overview — node CPU, memory, disk pressure.
- Pod resources — which pod is using too much CPU.
- Service latency — how fast are my APIs responding.
- MongoDB connections — am I approaching connection limits.

### Alert Thresholds
- CPU > 80% for 5 minutes → either HPA scales up, or I get a Slack alert.
- Memory > 85% → investigate for a memory leak.
- Pod restarts > 3 in 10 minutes → check crash logs.
- ArgoCD OutOfSync > 10 minutes → someone or something changed the cluster manually. Drift detected.

### What I Learned
Metrics are not just pretty graphs — they are the feedback loop that tells you if your platform is healthy before users complain.

---

## 16. Day-2 Operations & Rollback

Building the platform was only half the journey. I had to learn what "Day-2 operations" means — keeping it running, fixing it when it breaks, and rolling back safely.

### ArgoCD CLI Commands I Learned
- `argocd app list` — view all application statuses at once. I learned to look for "Synced" vs "OutOfSync."
- `argocd app history <app>` — see every deployment revision with Git commit SHAs.
- `argocd app rollback <app> <revision>` — instant rollback to a previous Git commit. I tested this in dev and watched ArgoCD sync the old version.

### GitOps Rollback Advantage
Rollback doesn't mean running mystery commands. It means `git revert` or restoring a previous `values-prod.yaml`. ArgoCD sees the Git change and syncs backward automatically. The cluster state is ALWAYS tied to a Git SHA. I can audit exactly what was running at any point in time.

### Self-Healing I Demonstrated
- I manually deleted a pod with `kubectl delete pod`. Kubernetes Deployment recreated it within seconds.
- I manually edited a Deployment with `kubectl edit deployment` to change the replica count. Within minutes, ArgoCD reverted it back to match Git.
- This is called "desired state reconciliation" — the system constantly checks reality against Git, and fixes drift automatically.

### What I Learned About Operations
In traditional ops, you SSH in and fix things. In GitOps, you fix Git, and the platform heals itself. That was a mindset shift for me as a trainee.

---

## 17. Complete Request Journey — From Browser to Database and Back

To tie everything together, here is the complete journey of a "borrow book" request:

1. **Browser** sends `POST /api/borrows` to `library.local`.
2. **DNS** resolves `library.local` to the **HAProxy LoadBalancer IP**.
3. **HAProxy** accepts the TCP connection on port 80 and forwards into the cluster.
4. **KGateway (Envoy)** receives the request, matches the path `/api/borrows` against the `api-route` HTTPRoute, and routes to the `borrow-service` backend on port 8083.
5. **Borrow Service Pod** receives the request. Spring Boot routes it to the borrow controller.
6. **Borrow Service** needs to verify the user. It makes an internal HTTP call to `user-service.library-dev.svc.cluster.local:8082`.
7. **kube-dns** resolves that to the User Service ClusterIP.
8. **User Service Pod** validates the JWT token (using the secret from `user-service-secret`) and returns user details.
9. **Borrow Service** needs to check book availability. It calls `book-service.library-dev.svc.cluster.local:8081`.
10. **Book Service Pod** queries **MongoDB** via `mongodb://mongodb.library-dev.svc.cluster.local:27017/chapterone_books_dev`.
11. **MongoDB** (`mongodb-0` in the StatefulSet) responds with the book record.
12. **Book Service** confirms availability → returns to Borrow Service.
13. **Borrow Service** creates a borrow record in its own MongoDB database (`chapterone_borrows_dev`).
14. **Borrow Service** returns `201 Created` with the borrow record.
15. Response flows back: **Borrow Service** → **KGateway** → **HAProxy** → **Browser**.

Every hop is logged, every pod is monitored by Prometheus, every image was scanned by Trivy, and every configuration came from Git via ArgoCD.

---

## 18. What I Built and What I Learned

Six months ago, I didn't know what GitOps meant. Today, I can trace a single commit through Trivy scanning, Docker Hub, Helm chart updates, ArgoCD sync, KGateway routing, and into a user's browser.

### Key Achievements
- Built multi-repo CI/CD using reusable GitHub Actions workflows across 4 microservices + frontend.
- Achieved zero manual cluster access for deployments — ArgoCD is the only actor touching the cluster.
- Implemented 3 security gates (Trivy, Snyk, SonarQube) in every pipeline.
- Learned environment parity: same Helm chart, different values files.
- Achieved sub-minute rollback via Git revert — every Git commit is a rollback point.
- Implemented namespace isolation with Kubernetes NetworkPolicies.
- Solved secrets-in-Git using Sealed Secrets.
- Built production autoscaling with HPA (3–10 replicas).
- Documented everything because I was learning and wanted to remember.

### What I Want to Learn Next
- Argo Rollouts for canary deployments — gradually shifting traffic to new versions.
- Distributed tracing with Jaeger — visualizing that Borrow Service → Book Service call across pods.
- External secrets with cloud KMS — integrating AWS/GCP secret managers.
- cert-manager for automatic TLS certificate provisioning.

---

## 19. Quick Reference — Key Files and Commands

### Key Files in `ChapterOne-Helm`
| File | Purpose |
|------|---------|
| `Chart.yaml` | Umbrella chart dependencies |
| `values-dev.yaml` | Dev environment overrides |
| `values-prod.yaml` | Prod environment overrides (HPA, TLS, network policy) |
| `app-of-apps.yaml` | ArgoCD root app for dev |
| `app-of-apps-prod.yaml` | ArgoCD root app for prod |
| `templates/network-policy.yaml` | Namespace firewall rules |
| `infrastructure/gateway/templates/gateway.yaml` | KGateway resource |
| `infrastructure/gateway/templates/httproute.yaml` | HTTPRoute path rules |
| `infrastructure/gateway/templates/haproxy.yaml` | HAProxy Deployment + Service |
| `infrastructure/mongodb/templates/statefulset.yaml` | MongoDB StatefulSet + PVC |
| `microservices/book-service/templates/deployment.yaml` | Book Service Deployment |
| `microservices/book-service/templates/configmap.yaml` | Book Service configuration |
| `argocd-apps/apps/book-service.yaml` | ArgoCD app for Book Service |

### Key Commands
```bash
# Update Helm dependencies
helm dependency update

# Deploy to dev
helm upgrade --install library-e2e . -f values-dev.yaml --namespace library-dev --create-namespace

# Deploy to prod
helm upgrade --install library-e2e . -f values-prod.yaml --namespace library-prod --create-namespace

# Check ArgoCD apps
argocd app list

# Rollback an app
argocd app rollback book-service 3

# Check HPA status
kubectl get hpa -n library-prod

# View sealed secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Port-forward for local testing
kubectl port-forward svc/frontend 8080:80 -n library-dev
```

### GitHub Repositories
- **All repos:** https://github.com/Googleeyy
- **Helm charts & GitOps:** https://github.com/Googleeyy/ChapterOne-Helm
- **Reusable CI workflows:** https://github.com/Googleeyy/ChapterOne-Reusable-Templates/tree/main/.github/workflows

---

*This document was written as part of a DevOps training journey. It is honest about mistakes made, lessons learned, and principles discovered along the way.*
