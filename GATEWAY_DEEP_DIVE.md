# HAProxy + KGateway + Envoy: Deep Dive into Your Ingress Architecture

> A detailed breakdown of how external traffic enters your Kubernetes cluster, gets routed to the correct microservice, and how each layer is configured in your `ChapterOne-Helm` project.

---

## 1. The Big Picture: Three Layers of Routing

Your project uses a **layered ingress architecture** with three distinct roles:

| Layer | Component | Role | Analogy |
|-------|-----------|------|---------|
| **Layer 1** | **HAProxy** | External edge / TCP load balancer | The **doorman** of the building — receives visitors from the street |
| **Layer 2** | **Envoy Proxy** (inside KGateway) | HTTP application router | The **concierge** — knows which apartment (microservice) the visitor wants |
| **Control** | **KGateway Controller** | Configuration translator / brain | The **building manager** — tells the concierge who lives where and what the rules are |

**Why three layers instead of one?**
- **HAProxy** handles raw network traffic, TLS termination (future), and health-checks at the edge. It is battle-tested for 20+ years and extremely fast at Layer 4 (TCP) and Layer 7 (HTTP).
- **KGateway (Envoy)** handles advanced Layer 7 (HTTP) logic: path-based routing, header modification, timeouts, retries, observability. It is Kubernetes-native and speaks the modern **Gateway API**.
- **KGateway Controller** bridges Kubernetes declarative config (your YAML files) into Envoy's runtime config. Without it, you would have to write Envoy config by hand.

This separation is called **control plane / data plane separation** — the controller thinks, Envoy acts.

---

## 2. HAProxy — The Edge Load Balancer

### What Is HAProxy?
HAProxy is a high-performance TCP/HTTP load balancer and proxy server. It was created in 2001 and is used by some of the world's busiest websites (GitHub, Twitter, Reddit). It is written in C, extremely lightweight, and focused on reliability and performance.

### HAProxy in Your Project
In `ChapterOne-Helm/infrastructure/gateway/templates/haproxy.yaml`, you defined:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: haproxy
spec:
  replicas: {{ .Values.haproxy.replicaCount }}   # 2 in prod, 1 in dev
  template:
    spec:
      containers:
        - name: haproxy
          image: haproxy:2.8-alpine
          ports:
            - containerPort: 80
            - containerPort: 443
```

And a **LoadBalancer Service**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: haproxy
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 80
    - port: 443
      targetPort: 443
```

### What This Means
- **`type: LoadBalancer`** tells Kubernetes to request an external IP from your cloud provider (or MetalLB if on-prem). This IP is reachable from outside the cluster — from a user's browser.
- **Port 80** is for HTTP traffic.
- **Port 443** is reserved for future HTTPS/TLS termination.
- **Replicas** are controlled by `values-prod.yaml` (`haproxy.replicaCount: 2`) for high availability. If one HAProxy pod dies, the Service routes traffic to the other.

### What HAProxy Actually Does
When a user types `http://library.local/api/books`:
1. DNS resolves `library.local` to the **HAProxy LoadBalancer IP**.
2. The browser opens a **TCP connection** to that IP on port 80.
3. The cloud provider's load balancer (or MetalLB) forwards that TCP connection to one of the HAProxy pods.
4. HAProxy accepts the HTTP request and forwards it **into the cluster** toward the KGateway pods.

HAProxy does NOT look at the URL path `/api/books`. At this layer, it is either:
- Doing simple **round-robin** load balancing across KGateway instances, or
- Forwarding everything to a single backend (KGateway Service).

Its job is to be the **robust, fast, external entry point** that can survive high connection counts and eventually handle TLS termination.

---

## 3. KGateway — The Kubernetes Gateway API Implementation

### What Is KGateway?
**KGateway** is an open-source implementation of the Kubernetes **Gateway API**. It replaces the older Ingress API with a more powerful, more secure, and more flexible standard.

In your project, KGateway is the combination of:
- A **controller** (runs as a pod in the `kgateway-system` namespace) that watches Kubernetes resources.
- **Envoy proxies** (run as pods, usually in your application namespace or a gateway namespace) that actually route traffic.

### The Gateway API Resources in Your Project

Your project defines three Gateway API resources in `infrastructure/gateway/templates/`:

#### A) GatewayClass — The Controller Selector
You don't define this yourself — it is installed when you set up KGateway on the cluster. It looks like this:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kgateway
spec:
  controllerName: kgateway.io/kgateway
```

This tells Kubernetes: "Whenever you see a Gateway with `gatewayClassName: kgateway`, the `kgateway.io/kgateway` controller is responsible for it."

Think of `GatewayClass` as the **driver** for a hardware device. You plug in a Gateway, and the GatewayClass tells Kubernetes which driver (controller) should handle it.

#### B) Gateway — The Listener Definition
In `gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: library-e2e-gateway
spec:
  gatewayClassName: kgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
```

This resource says:
- "I am a Gateway named `library-e2e-gateway`."
- "My controller is `kgateway` (via GatewayClass)."
- "I am listening for HTTP traffic on port 80."
- "Only HTTPRoutes in the **same namespace** can attach to me (`from: Same`)."

The `allowedRoutes: from: Same` is a **security feature**. It means a malicious HTTPRoute in the `default` namespace or `kube-system` cannot hijack your Gateway. Only routes in `library-dev` or `library-prod` (where the Gateway lives) can bind to it.

#### C) HTTPRoute — The Path-Based Routing Rules
In `httproute.yaml`, you defined two HTTPRoutes:

**`api-route`** — routes API calls to backend microservices:

```yaml
kind: HTTPRoute
metadata:
  name: api-route
spec:
  parentRefs:
    - name: library-e2e-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/books
      backendRefs:
        - name: book-service
          port: 8081
      timeouts:
        request: 30s
```

| Match | Backend Service | Port | Timeout |
|-------|----------------|------|---------|
| `PathPrefix: /api/books` | `book-service` | 8081 | 30s |
| `PathPrefix: /api/users` | `user-service` | 8082 | 30s |
| `PathPrefix: /api/borrows` | `borrow-service` | 8083 | 30s |
| `Exact: /health` | `book-service` | 8081 | — |

**`frontend-route`** — routes root traffic to the React UI:

```yaml
kind: HTTPRoute
metadata:
  name: frontend-route
spec:
  parentRefs:
    - name: library-e2e-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: X-Forwarded-Path
                value: /
      backendRefs:
        - name: frontend
          port: 80
```

**Key Gateway API concepts you are using:**
- **`parentRefs`** — "I (the HTTPRoute) want to attach to this Gateway." This is the binding mechanism.
- **`matches`** — rules for WHEN this route should trigger (path, header, query param).
- **`backendRefs`** — WHERE to send the traffic when matched (Kubernetes Service + port).
- **`filters`** — transformations to apply before forwarding (header injection, URL rewrite, request/response modification).
- **`timeouts`** — per-route timeout to prevent hung connections.

---

## 4. Envoy Proxy — The Data Plane

### What Is Envoy?
**Envoy** is a high-performance C++ distributed proxy designed for single services and applications, as well as a large microservice mesh. It was originally built at Lyft and is now a CNCF graduated project.

Envoy is the **data plane** of KGateway. The data plane is the component that actually handles your user's HTTP requests — parsing them, matching routes, forwarding them to backends, collecting metrics, and returning responses.

### How Envoy Gets Its Configuration
Envoy does NOT read Kubernetes YAML directly. Envoy speaks a protocol called **xDS** (Discovery Service). The KGateway Controller translates your Gateway and HTTPRoute YAML into xDS protobuf messages and pushes them to Envoy over gRPC.

**xDS stands for:**
- **LDS** — Listener Discovery Service (what ports to listen on)
- **RDS** — Route Discovery Service (what paths map to what backends)
- **CDS** — Cluster Discovery Service (what backend services exist)
- **EDS** — Endpoint Discovery Service (what Pod IPs are behind each service)

When you `kubectl apply` an HTTPRoute:
1. The Kubernetes API server stores it in etcd.
2. The KGateway Controller watches for changes via the Kubernetes API.
3. The Controller generates new xDS configuration.
4. The Controller pushes the new config to Envoy over gRPC (xDS).
5. Envoy hot-reloads the config **without restarting**.
6. New requests immediately use the new routes.

This is called **dynamic configuration** and is why Envoy is so powerful in Kubernetes — it reacts to pod changes, service changes, and route changes in real time.

### What Envoy Does for Each Request
When Envoy receives a request from HAProxy:

1. **Listener match** — Envoy sees the request came in on port 80 (HTTP listener).
2. **Virtual host match** — Envoy checks the `Host` header (`library.local`).
3. **Route match** — Envoy checks the HTTP path:
   - `/api/books` matches the `PathPrefix: /api/books` rule.
   - `/api/users/123` matches `PathPrefix: /api/users`.
   - `/` matches `PathPrefix: /`.
4. **Filter processing** — For the frontend route, Envoy injects `X-Forwarded-Path: /`.
5. **Backend selection** — Envoy resolves the backend Service (`book-service`) to actual Pod IPs using Kubernetes Endpoints.
6. **Load balancing** — Envoy picks one Pod IP (round-robin, least-request, or random) and opens a connection.
7. **Timeout enforcement** — If the backend takes longer than 30s, Envoy returns a 504 Gateway Timeout.
8. **Response return** — Envoy receives the response from the Pod and sends it back to HAProxy, which sends it to the browser.

---

## 5. KGateway Controller — The Control Plane

### What Is the KGateway Controller?
The **KGateway Controller** is a pod (or set of pods) running in the `kgateway-system` namespace. Its job is to:

1. **Watch** Kubernetes Gateway API resources (Gateway, HTTPRoute, TCPRoute, TLSRoute, etc.) via the Kubernetes API server.
2. **Translate** those high-level resources into low-level Envoy xDS configuration.
3. **Push** that configuration to Envoy proxies running in your application namespaces.
4. **Manage** Envoy proxy lifecycle — often deploying Envoy as a sidecar or as standalone gateway pods.

### Why "Control Plane" vs "Data Plane"?
This is a fundamental concept in modern networking:

| Plane | Responsibility | In Your Project |
|-------|---------------|-----------------|
| **Control Plane** | Thinks, decides, configures | KGateway Controller |
| **Data Plane** | Executes, forwards, handles traffic | Envoy Proxy |

**Analogy:** An airport.
- The **control tower** (control plane) watches all planes, decides landing order, and radios instructions.
- The **pilots** (data plane) actually fly the planes, follow instructions, and handle turbulence.

If the control tower goes down, planes already in the air keep flying (Envoy keeps routing with its last config). But new routes can't be added.

### What the Controller Does in Your Cluster
1. It sees `GatewayClass: kgateway` and knows it owns it.
2. It sees `Gateway: library-e2e-gateway` and tells Envoy to open a listener on port 80.
3. It sees `HTTPRoute: api-route` attached to `library-e2e-gateway` and tells Envoy:
   - "If the path starts with `/api/books`, send to the cluster named `book-service`."
   - "The `book-service` cluster targets port 8081."
4. It continuously watches the `book-service` Endpoints object in Kubernetes. When a Book Service Pod starts or dies, the Endpoints object updates, and the Controller pushes new EDS config to Envoy within seconds.

This means **Envoy always knows the current set of healthy Pod IPs** without DNS caching issues.

---

## 6. The Complete Workflow: A Request from Browser to Pod

Let us trace a single request: `GET http://library.local/api/books`

### Step 1: DNS Resolution (Outside Kubernetes)
- The user's browser asks DNS: "What is the IP for `library.local`?"
- If running locally, this might be `/etc/hosts` or a local DNS entry.
- The answer is the **HAProxy LoadBalancer IP** assigned by your cloud provider or MetalLB.

### Step 2: TCP Connection to HAProxy
- Browser opens a TCP connection to `HAProxy-IP:80`.
- The Kubernetes LoadBalancer Service receives the connection.
- kube-proxy (or the cloud provider's load balancer) forwards the connection to one of the HAProxy Pods.

### Step 3: HAProxy Forwards Into the Cluster
- HAProxy receives the HTTP request:
  ```
  GET /api/books HTTP/1.1
  Host: library.local
  User-Agent: Mozilla/5.0
  ```
- HAProxy is configured (by default or via a configmap) to forward all HTTP traffic to the **KGateway Service** inside the cluster.
- HAProxy opens a new TCP connection to the KGateway Service's ClusterIP (or to an Envoy Pod directly).

**Important:** HAProxy is NOT doing path-based routing here. It forwards the entire request to KGateway. It may be doing:
- Health checks on KGateway pods
- Connection pooling
- Basic load balancing across multiple Envoy instances

### Step 4: Envoy (KGateway Data Plane) Receives the Request
- Envoy receives the HTTP request from HAProxy.
- Envoy looks at its **dynamic configuration** (pushed by the KGateway Controller via xDS).

### Step 5: Envoy Matches the HTTPRoute
- Envoy checks the Listener (port 80, HTTP).
- Envoy checks the Route table:
  - Path = `/api/books`
  - Does it match `PathPrefix: /api/books` in `api-route`? **Yes.**
- Envoy selects the backend: `book-service` on port 8081.

### Step 6: Envoy Resolves the Backend to Pod IPs
- Envoy does NOT use DNS to find `book-service`. It uses the **EDS (Endpoint Discovery Service)** config pushed by the Controller.
- The Controller watches Kubernetes Endpoints for `book-service`.
- Current Endpoints might be:
  - `10.244.1.15:8081` (Book Service Pod 1)
  - `10.244.2.8:8081` (Book Service Pod 2)
  - `10.244.3.12:8081` (Book Service Pod 3)
- Envoy picks one using its load balancing algorithm (default is round-robin or least-request).

### Step 7: Envoy Forwards to the Book Service Pod
- Envoy opens a connection to `10.244.1.15:8081`.
- The request is forwarded:
  ```
  GET /api/books HTTP/1.1
  Host: library.local
  X-Forwarded-For: <original client IP>
  ```
- The Book Service Spring Boot application receives the request on port 8081.
- Spring Boot routes it to the `/api/books` controller.

### Step 8: Book Service Queries MongoDB
- The Book Service needs data. It reads `MONGO_URI` from its ConfigMap:
  ```
  mongodb://mongodb.library-dev.svc.cluster.local:27017/chapterone_books_dev
  ```
- The Book Service connects to MongoDB via the cluster network.
- MongoDB (`mongodb-0` in the StatefulSet) responds.

### Step 9: Response Flows Back
- MongoDB → Book Service Pod → Envoy → HAProxy → Browser.
- Envoy may add response headers like `X-Envoy-Upstream-Service-Time`.
- HAProxy may add connection headers.
- The browser receives the JSON list of books.

---

## 7. A Borrow Request — Internal + External Routing

A more complex request: `POST /api/borrows` (user wants to borrow a book).

**External path (Browser → HAProxy → Envoy → Borrow Service):**
1. Browser sends `POST /api/borrows` to HAProxy.
2. HAProxy forwards to Envoy.
3. Envoy matches `PathPrefix: /api/borrows` → routes to `borrow-service:8083`.
4. Borrow Service Pod receives the request.

**Internal path (Borrow Service → Book Service + User Service):**
5. Borrow Service's business logic says: "I need to verify this user exists."
6. Borrow Service makes an **internal HTTP call** to:
   ```
   http://user-service.library-dev.svc.cluster.local:8082/api/users/{id}
   ```
7. Kubernetes **kube-dns** resolves `user-service.library-dev.svc.cluster.local` to the User Service ClusterIP.
8. The User Service ClusterIP load-balances to one of the User Service Pods.
9. User Service validates the JWT token and returns user data.
10. Borrow Service then calls:
    ```
    http://book-service.library-dev.svc.cluster.local:8081/api/books/{id}
    ```
11. Book Service returns book availability.
12. Borrow Service creates the borrow record in its own MongoDB database.
13. Borrow Service returns `201 Created` to Envoy.
14. Envoy → HAProxy → Browser.

**Key insight:** The internal calls (steps 6–11) go through Kubernetes **ClusterIP Services** and **kube-dns**. They do NOT go through HAProxy or Envoy. This is more efficient — internal traffic should not leave the application namespace to go through the edge gateway.

---

## 8. What Happens If Each Component Fails?

### If HAProxy Fails
- **Symptom:** External users cannot reach `library.local` at all. Browser shows "connection refused."
- **Mitigation:** You have 2 replicas in production. The LoadBalancer Service automatically removes the failed Pod from its endpoints and sends traffic to the healthy one.
- **Recovery:** Kubernetes Deployment recreates the failed Pod.

### If KGateway Controller Fails
- **Symptom:** Existing routes keep working! Envoy has the last config in memory.
- **But:** New HTTPRoutes won't be applied. If you add a new microservice, Envoy won't know about it. If a Pod IP changes, Envoy won't get the update (until the Controller recovers).
- **Mitigation:** The Controller should run with multiple replicas for high availability.
- **Recovery:** Kubernetes recreates the Controller Pod. It re-syncs all resources on startup.

### If Envoy Proxy (KGateway Data Plane) Fails
- **Symptom:** Traffic from HAProxy has nowhere to go. Requests fail with 502/503.
- **Mitigation:** Run multiple Envoy replicas behind a Service. HAProxy should be configured with health checks to avoid sending traffic to dead Envoys.
- **Recovery:** Kubernetes recreates the Envoy Pod.

### If Book Service Pod Fails
- **Symptom:** Envoy routes to the dead Pod → connection refused → Envoy returns 503.
- **Mitigation:**
  - Kubernetes Deployment recreates the Pod.
  - Kubernetes Endpoints remove the dead Pod IP within seconds.
  - The KGateway Controller pushes the updated Endpoints to Envoy via EDS.
  - Envoy stops sending traffic to the dead Pod.
  - Readiness probes on Book Service prevent it from receiving traffic until it is truly ready.

---

## 9. Configuration Files in Your Project

| File | What It Defines |
|------|-----------------|
| `infrastructure/gateway/templates/haproxy.yaml` | HAProxy Deployment (replicas, resources) + LoadBalancer Service (external IP, ports 80/443) |
| `infrastructure/gateway/templates/gateway.yaml` | Gateway resource (listener port 80, `gatewayClassName: kgateway`, `allowedRoutes: Same`) |
| `infrastructure/gateway/templates/httproute.yaml` | Two HTTPRoutes (`api-route`, `frontend-route`) with path matching and backend refs |
| `infrastructure/gateway/values.yaml` | Default values (gateway enabled, haproxy disabled by default) |
| `values-dev.yaml` | Dev overrides (`haproxy.enabled: false`, gateway host: `library-dev.local`) |
| `values-prod.yaml` | Prod overrides (`haproxy.enabled: true`, `haproxy.replicaCount: 2`, TLS enabled) |

---

## 10. Summary: Why This Architecture Works for You

As a trainee, this architecture taught you several industry patterns:

1. **Separation of concerns:** HAProxy handles the raw network edge. KGateway/Envoy handles application routing. The Controller handles configuration.
2. **Declarative routing:** You define routes in YAML (HTTPRoute), and the system makes it so. You never edit HAProxy or Envoy config files by hand.
3. **Dynamic discovery:** When a Book Service Pod crashes and a new one starts, Envoy learns the new IP within seconds — no manual updates.
4. **Namespace security:** `allowedRoutes: from: Same` prevents other namespaces from hijacking your Gateway.
5. **Future-proof:** Gateway API is the Kubernetes-native standard. Learning it now prepares you for production environments using Istio, NGINX Gateway Fabric, or other Gateway API implementations.
6. **Observability:** Envoy emits metrics (latency, request count, error rate) that Prometheus can scrape and Grafana can visualize.

---

## 11. Key Terms Glossary

| Term | Definition |
|------|------------|
| **Gateway API** | The modern Kubernetes API for managing ingress traffic (successor to Ingress). |
| **GatewayClass** | Tells Kubernetes which controller should manage a Gateway. Like a "driver" for a Gateway. |
| **Gateway** | Defines a listener (port + protocol) and which namespaces can attach routes. |
| **HTTPRoute** | Defines path-based routing rules that attach to a Gateway. |
| **KGateway** | An open-source implementation of Gateway API that uses Envoy as the data plane. |
| **Envoy** | A high-performance C++ proxy that handles the actual HTTP routing (data plane). |
| **xDS** | Envoy's configuration protocol (gRPC-based). Stands for Discovery Services (LDS, RDS, CDS, EDS). |
| **Control Plane** | The component that thinks, watches Kubernetes, and generates config (KGateway Controller). |
| **Data Plane** | The component that executes, forwards traffic, and handles requests (Envoy Proxy). |
| **LoadBalancer Service** | A Kubernetes Service type that gets an external IP for ingress traffic. |
| **ClusterIP** | A Kubernetes Service type for internal-only traffic (default). |
| **kube-dns / CoreDNS** | Kubernetes internal DNS that resolves service names to ClusterIPs. |
| **Endpoints** | A Kubernetes object that lists the current Pod IPs behind a Service. |
| **EDS** | Endpoint Discovery Service — the xDS protocol that tells Envoy which Pod IPs are healthy. |
