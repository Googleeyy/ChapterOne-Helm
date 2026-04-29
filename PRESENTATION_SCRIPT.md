# ChapterOne Library Management Platform — Project Review Presentation Script

> **Duration:** 25–30 minutes  
> **Audience:** Technical review panel  
> **Tone:** Confident, honest, educational

---

## Section 1: Opening Hook — Why I Built This (2 min)

**[SLIDE: Title slide]**

"Good morning. I am [Your Name], and I built this platform to answer one question that kept bothering me when I started learning DevOps: **what actually happens after a developer types `git push`?**

I knew Docker. I knew Kubernetes. But I could not visualize the full chain — how code becomes a running container, how that container gets into a cluster, how traffic reaches it, or how we know if it breaks.

So I built the ChapterOne Library Management Platform — a complete microservices system with automated CI/CD, GitOps deployment, security scanning, ingress routing, secrets management, and monitoring. Everything is open-source under my GitHub organization `Googleeyy`, and I documented every step because I was learning."

**[PAUSE]**

---

## Section 2: The Application — What Runs Inside (2 min)

**[SLIDE: 4 backend boxes + frontend + MongoDB]**

"Before the infrastructure, here is what actually runs. I chose a library system because it naturally splits into three domains:

- **Book Service** — port 8081, Java Spring Boot, manages book inventory.
- **User Service** — port 8082, Spring Boot, handles authentication and issues JWT tokens.
- **Borrow Service** — port 8083, the orchestrator. When someone borrows a book, it calls the User and Book services internally over HTTP, then creates a borrow record. This taught me real distributed-systems patterns.
- **Frontend** — port 80, React UI consuming all three backend APIs.
- **MongoDB** — shared database layer running as a StatefulSet with persistent storage.

All source code lives in separate repos under `Googleeyy`, and the Helm packaging lives in `ChapterOne-Helm` — the repo we are reviewing today."

---

## Section 3: The Big Picture — Architecture at a Glance (2 min)

**[SLIDE: Full architecture diagram — Developer → GitHub → CI → Docker Hub → Helm → ArgoCD → K8s]**

"This single slide summarizes everything. Left to right:

A developer pushes code to a service repo. That triggers our GitHub Actions CI pipeline, which builds a Docker image, scans it with Trivy, pushes it to Docker Hub, and automatically updates the Helm chart in this repo.

ArgoCD watches the Helm repo. It detects the new commit, renders the templates, and syncs them into Kubernetes.

We run two environments on the SAME cluster — `library-dev` and `library-prod` — separated by namespaces. Traffic enters through HAProxy, then KGateway routes it based on the URL path.

**Zero manual `kubectl` commands.** Git is the single source of truth, and the platform heals itself."

**[PAUSE]**

---

## Section 4: Why Microservices + Why MongoDB (2 min)

**[SLIDE: Service-to-service call diagram]**

"Two technology choices I researched:

**Why microservices?** The Borrow Service taught me something no monolith could. It calls `user-service.library-dev.svc.cluster.local:8082` and `book-service.library-dev.svc.cluster.local:8081` over HTTP. Kubernetes DNS resolves those names to ClusterIP services, which load-balance across pods. That is real service-to-service communication.

**Why MongoDB instead of PostgreSQL?** I defaulted to SQL at first. But this project taught me when NoSQL wins:

- **Schema flexibility** — as a trainee, my data models kept changing. No migration scripts every time I added a field.
- **Document model maps to JSON** — our Spring Boot APIs return JSON, and MongoDB stores JSON-like documents. I learned about 'impedance mismatch' between relational tables and objects.
- **Three databases in one StatefulSet** — `chapterone_books`, `chapterone_users`, `chapterone_borrows`. Three separate PostgreSQL instances would mean three StatefulSets, three PVCs, and much more operational complexity.

**The trade-off:** MongoDB lacks ACID transactions across collections. For a library system, that is acceptable. For a bank ledger, I would absolutely choose PostgreSQL. Every technology choice has a context where it wins or loses."

---

## Section 5: Docker & Container Strategy (2 min)

**[SLIDE: Multi-stage Dockerfile diagram]**

"Before this project, I thought Docker was 'a lightweight VM.' Building this taught me it is really about **immutable application packaging.**

Each microservice has its own Dockerfile. I learned about multi-stage builds: a builder stage with the full JDK compiles the code, then only the compiled JAR is copied into a smaller JRE base image. Small images, reduced attack surface.

**Image tagging is critical.** Every image is tagged with the Git commit SHA — for example, `dev-a1b2c3d`. This is immutable traceability. If production breaks, I know precisely which code change caused it. The image Trivy scanned is the EXACT image that runs in the cluster. No rebuild, no 'works in CI but fails in prod.'

All images live on Docker Hub under `googleyy/<service-name>`."

---

## Section 6: Helm — Taming Kubernetes YAML (3 min)

**[SLIDE: Umbrella chart with 6 subchart dependencies]**

"When I first saw Kubernetes, I was overwhelmed. Every microservice needs a Deployment, Service, ConfigMap, Secret, HPA... and I had four services plus MongoDB plus a gateway. Writing thirty-plus YAML files by hand felt wrong.

Then I learned about **Helm**.

In `ChapterOne-Helm/Chart.yaml`, I declared six dependencies: MongoDB, Gateway, Book Service, User Service, Borrow Service, and Frontend. `helm dependency update` packages all subcharts into `charts/*.tgz`. One command bundles the entire platform.

**The values hierarchy** made environment management click. Helm deep-merges from least to most specific:

1. Subchart defaults
2. Parent `values.yaml`
3. Environment files — `values-dev.yaml` or `values-prod.yaml`

`values-dev.yaml` sets one replica, disables autoscaling, uses dev tags. `values-prod.yaml` sets three replicas, enables HPA 3–10, mounts TLS secrets, uses semantic tags.

The **same Helm chart** deploys to both environments. Only configuration changes. This is **environment parity.**

My lightbulb moment was `global.namespace`. Setting it in the parent `values-dev.yaml` automatically flows to ALL subcharts via Helm's `global` key. One variable places every pod, service, and secret into the right namespace."

---

## Section 7: CI/CD Pipeline — From Commit to Cluster (4 min)

**[SLIDE: CI/CD pipeline diagram — Build → Scan → Push → Update Helm → Notify]**
**[GESTURE: Trace each stage slowly]**

"This is the part I am most proud of understanding. The EXACT timeline from commit to cluster:

**Step 1:** Developer pushes to the `dev` branch in `ChapterOne-Book` under `Googleeyy`.

**Step 2:** The service repo calls our reusable `_build_trivy.yml` via `workflow_call`. `workflow_call` is how GitHub Actions does 'functions.'

**Step 3:** Java 21 Temurin builds the JAR with Maven. Docker builds the image.

**Step 4:** **Trivy scans the image BEFORE it ever leaves the GitHub runner.** This is 'shift-left security.' If CRITICAL or HIGH CVEs are found, the pipeline FAILS. Nothing gets pushed.

**Step 5:** The image is saved as a GitHub Actions artifact — temporary storage between jobs.

**Step 6:** `_push.yml` downloads the artifact and pushes `googleyy/chapterone-book:dev-a1b2c3d` to Docker Hub.

**Step 7:** `_update_helm_chart.yml` checks out `ChapterOne-Helm:dev`. It converts `book-service` to `bookService` with sed, then runs `yq` to set `bookService.image.tag = 'dev-a1b2c3d'` in `values-dev.yaml`. It commits as `github-actions[bot]` and pushes back using a PAT.

**Step 8:** `_notify.yml` posts success or failure to Slack `#deployments`.

**Zero-touch deployment:** After step 8, a human NEVER runs `kubectl apply` or `helm upgrade`. The ONLY thing that touches the cluster is ArgoCD. This separation of CI and CD was the key DevOps principle I finally understood."

**[PAUSE]**

---

## Section 8: Reusable Workflows — DRY in CI/CD (2 min)

**[SLIDE: One template repo, four service repos calling it]**

"I did not start with reusable workflows. I copy-pasted GitHub Actions into every repo. Then I changed a Trivy scan threshold in one repo, forgot to update the other three, and had inconsistent builds. That taught me **DRY — Don't Repeat Yourself.**

In `ChapterOne-Reusable-Templates/.github/workflows/`, I centralized:

- `_build_trivy.yml` — build and scan
- `_push.yml` — push to registry
- `_update_helm_chart.yml` — update Helm values
- `_snyk.yml` — dependency vulnerability scanning
- `_sonar.yml` — code quality gates. I learned what 'code smells' and 'cyclomatic complexity' mean.
- `_notify.yml` — Slack alerts. A silent pipeline is a pipeline nobody trusts.

Now I edit ONE file, and all four microservices inherit it instantly."

---

## Section 9: Branch Strategy & Governance (2 min)

**[SLIDE: dev → PR → production diagram]**

"Early on, I pushed everything to one branch and accidentally deployed broken code. That taught me why branch strategy matters.

Two branches in `ChapterOne-Helm`:
- `dev` — active development, auto-deploys to `library-dev`
- `production` — protected, requires PR review, deploys to `library-prod`

Protection rules on `production`:
- Requires PR + one approval
- Dismisses stale approvals on new commits
- Requires `helm lint` and `helm template` status checks
- Blocks force pushes

**Promotion model:** Test in dev → create PR `dev` → `production` → review → merge → ArgoCD detects and syncs to `library-prod`.

The CI bot pushes directly to `dev` using a PAT because automated CD needs speed. But **human changes MUST go through PRs.** This taught me the difference between machine automation and human governance."

---

## Section 10: ArgoCD & GitOps — Git as Source of Truth (3 min)

**[SLIDE: ArgoCD UI showing Synced + Healthy apps]**

"I used to think deploying meant running `kubectl apply` from my laptop. Then I learned about **GitOps** — Git is the single source of truth, and a controller makes the cluster match Git.

Why ArgoCD?
1. **Visual UI** — green = synced, yellow = progressing, red = failed. As a trainee, colors helped me understand what was happening.
2. **Helm support natively** — it runs `helm template` with our exact `values-dev.yaml` or `values-prod.yaml`.
3. **Self-healing** — I tested this manually. I ran `kubectl edit deployment` to change a replica count, and within minutes ArgoCD reverted it. Git always wins.
4. **Pruning** — I removed a Service from Git, pushed, and ArgoCD deleted it from the cluster.
5. **Rollback history** — every Git commit is a rollback point. Reverting a Git commit IS a production rollback.

**App of Apps pattern:** an ArgoCD Application that manages OTHER ArgoCD Applications. In our repo:
- `app-of-apps.yaml` watches `argocd-apps/` on the `dev` branch
- `app-of-apps-prod.yaml` watches `argocd-apps-prod/` on the `production` branch
- Both use `directory: recurse: true` to discover ALL YAML files automatically

Adding a new microservice means adding ONE YAML file. The root app discovers it automatically."

---

## Section 11: Inside the Cluster — K8s Resources (2 min)

**[SLIDE: Deployment → ReplicaSet → Pods → Service → ClusterIP]**

"Each microservice has a standard Deployment template. It pulls the exact image tag from values, mounts `MONGO_URI` from a ConfigMap, and has readiness and liveness probes.

Services are ClusterIP for internal DNS. `book-service` resolves to Book Service pods. `mongodb-0.mongodb` resolves to the MongoDB StatefulSet via a headless service. Internal DNS format: `<service>.<namespace>.svc.cluster.local`.

**HPA** — Horizontal Pod Autoscaler — queries the Metrics API every 15 seconds. If CPU exceeds 70%, it adds replicas. Below threshold, it scales down. Enabled only in production. Dev does not need it."

---

## Section 12: Gateway Routing — KGateway + HAProxy (3 min)

**[SLIDE: Request path diagram]**
**[GESTURE: Trace the request path with your finger]**

"I thought Kubernetes 'just routes traffic.' Then I tried accessing services from outside the cluster and realized I needed a proper ingress layer. I researched the older Ingress API, discovered Gateway API, and chose KGateway as the modern standard.

**Two-layer routing:**

**Layer 1 — HAProxy:** the external edge. Deployment + LoadBalancer Service. Listens on 80 and 443. It is the single external entry point. In production it runs two replicas; in dev it is disabled to save resources.

**Layer 2 — KGateway:** the Kubernetes-native router. Implements the Gateway API using Envoy under the hood.

Why Gateway API over Ingress?
1. More expressive routing — HTTPRoute, TCPRoute, TLSRoute, custom filters
2. Separation of concerns — cluster admin defines Gateway, app developer defines HTTPRoute
3. Future-proof — SIG-Network is investing in Gateway API as the long-term standard

**Gateway resource:** `library-e2e-gateway`, GatewayClass `kgateway`. Security feature `allowedRoutes: from: Same` — only HTTPRoutes in the SAME namespace can attach.

**HTTPRoutes define path matching:**
- `/api/books` → Book Service :8081
- `/api/users` → User Service :8082
- `/api/borrows` → Borrow Service :8083
- `/` → Frontend :80

**Request walkthrough — user visits `http://library.local/api/books`:**

1. DNS resolves `library.local` to HAProxy LoadBalancer IP
2. HAProxy forwards into the cluster, targeting KGateway pods
3. KGateway matches path `/api/books` against HTTPRoute rules
4. It rewrites the destination internally to Book Service pod IPs
5. Book Service receives the request on port 8081
6. It connects to MongoDB using the ConfigMap MONGO_URI
7. Response flows back: MongoDB → Book Service → KGateway → HAProxy → Browser

**Internal calls** — Borrow Service → User/Book Service — use Kubernetes DNS directly. This is east-west traffic; it bypasses the gateway for efficiency."

---

## Section 13: Security — DevSecOps Layers (2 min)

**[SLIDE: Security matrix — Trivy, Snyk, SonarQube, NetworkPolicy, Sealed Secrets]**

"Security is not a single tool. It is layers — **defense in depth.**

- **Trivy** scans every image BEFORE push. CRITICAL/HIGH threshold. Pipeline stops if it finds something.
- **Snyk** scans Maven/npm dependencies for known CVEs.
- **SonarQube** enforces code quality gates.
- **NetworkPolicy** acts as a namespace firewall. By default, Kubernetes allows ALL pods to talk to ALL pods in ALL namespaces. I did not realize this until I read about it.

Our policy in `templates/network-policy.yaml`:
- Allows intra-namespace traffic
- Allows DNS to kube-system on port 53
- Allows MongoDB on port 27017
- Denies everything else by default

Enabled in production, disabled in dev while validating.

**Secrets:** I needed JWT secrets and MongoDB credentials in Git for ArgoCD. But Kubernetes Secrets are only base64-encoded — NOT encryption.

I solved this with **Bitnami Sealed Secrets:**
1. Create a standard Secret locally
2. Run `kubeseal` against the cluster's public key → produces a SealedSecret CRD
3. Commit the SealedSecret to Git safely — encrypted, bound to a specific namespace
4. ArgoCD syncs it into the cluster
5. Sealed Secrets Controller decrypts it → creates native Secret ONLY in target namespace

Asymmetric encryption: `kubeseal` uses the PUBLIC key. Only the controller has the PRIVATE key.

I evaluated HashiCorp Vault but it requires running a Vault server, unsealing it, managing tokens, setting up AppRoles. That is a whole infrastructure project. Sealed Secrets is simpler, self-hosted, zero cloud dependency. Vault is enterprise-grade; Sealed Secrets is pragmatic-grade."

---

## Section 14: Monitoring & Day-2 Operations (2 min)

**[SLIDE: Grafana dashboards or Prometheus architecture]**

"I deployed my first service, it crashed, and I did not know why. That is when I learned: **you cannot operate what you cannot observe.**

Prometheus + Grafana in a `monitoring` namespace. Prometheus scrapes metrics from both `library-dev` and `library-prod`.

Dashboards:
- Cluster overview — node CPU, memory, disk pressure
- Pod resources — which pod is using too much CPU
- Service latency — how fast our APIs respond
- MongoDB connections

Alerts:
- CPU > 80% for 5 min → HPA scales up or Slack alert
- Memory > 85% → investigate leak
- Pod restarts > 3 in 10 min → check crash logs
- ArgoCD OutOfSync > 10 min → drift detected

**Day-2 operations with ArgoCD:**
- `argocd app list` — all statuses
- `argocd app history` — every deployment with Git commit SHAs
- `argocd app rollback` — instant rollback

I tested self-healing: deleted a pod, Kubernetes recreated it in seconds. Edited a Deployment replica count, ArgoCD reverted it in minutes. Desired-state reconciliation."

---

## Section 15: Closing — What I Learned & What Comes Next (2 min)

**[SLIDE: Key achievements + future roadmap]**

"Six months ago, I did not know what GitOps meant. Today, I can trace a single commit through Trivy scanning, Docker Hub, Helm chart updates, ArgoCD sync, KGateway routing, and into a user's browser.

**Key achievements:**
- Multi-repo CI/CD using reusable GitHub Actions across 4 microservices + frontend
- Zero manual cluster access — ArgoCD is the only actor touching the cluster
- Three security gates in every pipeline: Trivy, Snyk, SonarQube
- Environment parity — same Helm chart, different values files
- Sub-minute rollback via Git revert
- Namespace isolation with NetworkPolicies
- Sealed Secrets solving secrets-in-Git
- Production autoscaling with HPA 3–10 replicas

**What I want to learn next:**
- Argo Rollouts for canary deployments
- Jaeger distributed tracing to visualize Borrow Service → Book Service calls
- External Secrets with cloud KMS

This project started as my DevOps training assignment. It ended up teaching me that DevOps is not about tools — it is about connecting people, code, and infrastructure into a single reliable pipeline. All of this is open-source at github.com/Googleeyy, and I am happy to talk about any part of it."

**[PAUSE — open for questions]**

---

## Appendix: Key File Paths & Commands for Q&A

| What | Path |
|------|------|
| Helm umbrella chart | `ChapterOne-Helm/Chart.yaml` |
| Dev values | `ChapterOne-Helm/values-dev.yaml` |
| Prod values | `ChapterOne-Helm/values-prod.yaml` |
| Reusable CI workflows | `ChapterOne-Reusable-Templates/.github/workflows/` |
| Build + Trivy scan | `_build_trivy.yml` |
| Helm chart updater | `_update_helm_chart.yml` |
| Gateway resource | `infrastructure/gateway/templates/gateway.yaml` |
| HTTPRoutes | `infrastructure/gateway/templates/httproute.yaml` |
| NetworkPolicy | `templates/network-policy.yaml` |
| App of Apps (dev) | `app-of-apps.yaml` |
| App of Apps (prod) | `app-of-apps-prod.yaml` |

**Quick commands if asked:**
```bash
# Check pod status
kubectl get pods -n library-dev

# Check ArgoCD app status
argocd app get library-dev

# Rollback to previous revision
argocd app rollback library-dev 2

# View Helm rendered output
helm template library-dev . -f values-dev.yaml
```
