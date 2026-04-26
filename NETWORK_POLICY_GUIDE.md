# Network Policy Implementation Guide

## Overview

This document explains the Network Policy implementation for the Library E2E Helm project, including use cases, how it works, and real-world applications.

## What is Network Policy?

A Network Policy is a Kubernetes resource that controls the traffic flow between pods (network segmentation). It acts like a firewall for your cluster, specifying which pods can communicate with each other and on which ports.

### Key Concepts

- **Ingress**: Incoming traffic to a pod
- **Egress**: Outgoing traffic from a pod
- **Pod Selector**: Defines which pods the policy applies to
- **Namespace Selector**: Defines which namespaces can communicate
- **Policy Types**: Can be Ingress, Egress, or both

## Our Implementation: Light Network Policy

### Policy Location
`templates/network-policy.yaml`

### Policy Configuration

```yaml
networkPolicy:
  enabled: true
```

### What Our Light Policy Does

Our network policy implements a **lightweight, permissive** approach that:

1. **Allows all intra-namespace traffic** - Services within the `chapterone` namespace can communicate freely
2. **Allows DNS resolution** - Pods can resolve DNS queries (required for service discovery)
3. **Allows MongoDB access** - Specific rule for database connectivity on port 27017
4. **Blocks external traffic** - Prevents unauthorized access from other namespaces

### Policy Rules Breakdown

#### Ingress Rules (Incoming Traffic)

```yaml
ingress:
  # Allow traffic from within the same namespace (inter-service communication)
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ .Values.global.namespace }}
```

**Purpose**: Enables microservices to communicate with each other within the same namespace.

**Dynamic Namespace**: The policy uses `{{ .Values.global.namespace }}` which dynamically adapts:
- **Dev environment**: `library-dev` (from values-dev.yaml)
- **Prod environment**: `library-prod` (from values-prod.yaml)

**Services affected**:
- Frontend → Gateway
- Gateway → Book Service, User Service, Borrow Service
- Borrow Service → Book Service, User Service
- All services → MongoDB

#### Egress Rules (Outgoing Traffic)

```yaml
egress:
  # Allow traffic to all pods in the same namespace
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ .Values.global.namespace }}
  
  # Allow DNS resolution (kube-system)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  
  # Allow MongoDB access (specific port)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ .Values.global.namespace }}
      podSelector:
        matchLabels:
          app: mongodb
    ports:
    - protocol: TCP
      port: 27017
```

**Purpose**: 
- Services can reach other services in the namespace
- DNS resolution works (critical for Kubernetes service discovery)
- Database connectivity is explicitly allowed

## Use Cases

### 1. Service-to-Service Communication

**Scenario**: The Borrow Service needs to call the Book Service to check book availability.

**How Policy Helps**: 
- Both services are in the same namespace
- Policy allows traffic between them
- No additional configuration needed

### 2. Database Access

**Scenario**: All microservices need to connect to MongoDB.

**How Policy Helps**:
- Explicit egress rule allows MongoDB access on port 27017
- Only pods in the same namespace can reach the database
- Port-specific rule limits exposure

### 3. Preventing Cross-Namespace Access

**Scenario**: A compromised pod in a different namespace tries to access our services.

**How Policy Helps**:
- Policy only allows traffic from `chapterone` namespace
- External namespace traffic is blocked by default
- Provides isolation between environments

### 4. DNS Resolution

**Scenario**: Services need to resolve `mongodb-0.mongodb` hostname.

**How Policy Helps**:
- Explicit DNS rules allow TCP/UDP port 53 to kube-system
- Kubernetes DNS can function properly
- Service discovery works as expected

## How Network Policy Works

### Mechanism

1. **Policy Enforcement**: When a network policy is applied, the Kubernetes network plugin (CNI) enforces the rules
2. **Default Deny**: If no policy exists, all traffic is allowed. If a policy exists, only specified traffic is allowed
3. **Whitelist Model**: Our policy uses a whitelist approach - only explicitly allowed traffic passes through

### Traffic Flow Example

```
User Request → Gateway → Book Service
     ↓              ↓           ↓
   [Allowed]    [Allowed]   [Allowed]
   (Ingress)    (Ingress)   (Ingress)
```

### Policy Evaluation Order

1. Check if pod matches selector
2. Check if traffic source matches ingress rules
3. Check if traffic destination matches egress rules
4. Allow or deny based on rule match

## Where Network Policy is Used

### In Our Project

- **Namespaces**: Dynamic based on environment
  - **Dev environment**: `library-dev` (from values-dev.yaml)
  - **Prod environment**: `library-prod` (from values-prod.yaml)
- **Applies to**: All pods in the namespace (podSelector: {})
- **Scope**: Entire microservices application
- **Dynamic Configuration**: Uses `{{ .Values.global.namespace }}` Helm template variable

### Real-World Use Cases

#### 1. Multi-Tenant SaaS Applications

**Scenario**: A SaaS platform hosts multiple customers on the same cluster.

**Implementation**:
- Each customer gets their own namespace
- Network policies prevent cross-tenant communication
- Customer A's services cannot access Customer B's data

**Benefit**: Strong isolation and security compliance (SOC2, GDPR)

#### 2. Microservices Architecture

**Scenario**: E-commerce application with 50+ microservices.

**Implementation**:
- Group related services in namespaces (e.g., `payment`, `inventory`, `frontend`)
- Policies control which services can communicate
- Frontend can only call API gateway, not direct database

**Benefit**: Reduces attack surface, prevents lateral movement

#### 3. Development vs Production Environments

**Scenario**: Same cluster hosts dev, staging, and production.

**Implementation**:
- Separate namespaces for each environment
- Policies block dev from accessing production databases
- Production services cannot call dev services

**Benefit**: Prevents accidental data corruption, maintains environment separation

#### 4. Zero Trust Security Model

**Scenario**: Financial services requiring strict security.

**Implementation**:
- Default deny all traffic
- Explicitly allow only required communication paths
- Regular audits of policy rules

**Benefit**: Meets regulatory requirements, minimizes breach impact

#### 5. Legacy Application Migration

**Scenario**: Migrating monolith to microservices gradually.

**Implementation**:
- Policies allow monolith to communicate with new services
- Block direct database access from external services
- Gradually tighten rules as migration progresses

**Benefit**: Safe migration path, maintains availability

## Advantages of Our Light Policy

### 1. Simplicity
- Easy to understand and maintain
- Minimal configuration required
- Low operational overhead

### 2. Flexibility
- Services can communicate freely within namespace
- New services don't require policy updates
- Supports dynamic scaling

### 3. Security
- Blocks external namespace access
- Limits database exposure to specific port
- Provides basic segmentation

### 4. Compatibility
- Works with all CNIs that support network policies
- No special requirements
- Standard Kubernetes feature

## Limitations of Light Policy

### 1. Coarse-Grained Control
- Allows all intra-namespace traffic
- Doesn't restrict service-to-service communication
- Less restrictive than fine-grained policies

### 2. No Port-Level Service Restrictions
- Services can communicate on any port
- Relies on application-level security
- Not suitable for high-security requirements

### 3. No IP-Based Restrictions
- Cannot restrict by IP ranges
- Cannot limit to specific pod IPs
- Namespace-level only

## When to Upgrade to Stricter Policies

Consider upgrading if you need:

1. **Service-specific restrictions** - Only allow Gateway to call backend services
2. **Port-level control** - Restrict which ports services can use
3. **IP whitelisting** - Allow traffic only from specific IPs
4. **Compliance requirements** - Meet strict security standards (PCI-DSS, HIPAA)
5. **Defense in depth** - Multiple layers of security controls

## How to Apply Network Policy

### Automatic Application (Recommended)

The network policy is automatically applied when you deploy your Helm chart. No manual steps required.

**For Development Environment:**
```bash
cd helm
helm dependency update
helm upgrade --install library-dev . \
  -f values-dev.yaml \
  --namespace library-dev \
  --create-namespace \
  --wait --timeout 600s
```

**For Production Environment:**
```bash
cd helm
helm dependency update
helm upgrade --install library-prod . \
  -f values-prod.yaml \
  --namespace library-prod \
  --create-namespace \
  --wait --timeout 600s
```

The network policy is applied because:
- `networkPolicy.enabled: true` is set in both values-dev.yaml and values-prod.yaml
- The template `templates/network-policy.yaml` is part of the Helm chart
- Helm automatically renders and applies all templates in the templates/ directory

### Manual Application (If Needed)

If you need to apply the network policy separately (rare cases):

```bash
# For dev environment
kubectl apply -f <(helm template library-dev . -f values-dev.yaml --namespace library-dev) | grep -A 50 "kind: NetworkPolicy"

# For prod environment
kubectl apply -f <(helm template library-prod . -f values-prod.yaml --namespace library-prod) | grep -A 50 "kind: NetworkPolicy"
```

### Where It's Applied

The network policy is applied to:
- **Namespace**: Dynamically set by `{{ .Values.global.namespace }}`
  - Dev: `library-dev`
  - Prod: `library-prod`
- **Scope**: All pods in the namespace (podSelector: {})
- **Location**: Kubernetes API server via Helm

### When It's Applied

The network policy is applied:
1. **Initial deployment**: When you first run `helm install`
2. **Updates**: When you run `helm upgrade` with `networkPolicy.enabled: true`
3. **Re-enabled**: If you disabled it and set `networkPolicy.enabled: true` again

### Disabling Network Policy

To disable the network policy temporarily:

```yaml
# In values-dev.yaml or values-prod.yaml
networkPolicy:
  enabled: false
```

Then run:
```bash
# For dev
helm upgrade library-dev . -f values-dev.yaml --namespace library-dev

# For prod
helm upgrade library-prod . -f values-prod.yaml --namespace library-prod
```

## ArgoCD Integration

### Current ArgoCD Setup

Your project uses ArgoCD with an "app-of-apps" pattern:
- `app-of-apps.yaml` - Root application that syncs all applications in `argocd-apps/` directory
- `argocd-apps/apps/book-service.yaml` - Deploys book-service subchart
- `argocd-apps/apps/user-service.yaml` - Deploys user-service subchart
- `argocd-apps/apps/borrow-service.yaml` - Deploys borrow-service subchart
- `argocd-apps/apps/frontend.yaml` - Deploys frontend subchart
- `argocd-apps/infra/gateway.yaml` - Deploys gateway subchart
- `argocd-apps/infra/mongodb.yaml` - Deploys mongodb subchart

The `app-of-apps.yaml` uses `directory: recurse: true` to automatically sync all YAML files in the `argocd-apps/` directory.

### Important: Network Policy Won't Deploy with Current Setup

**The network policy (templates/network-policy.yaml) is in the root Helm chart, but your ArgoCD applications deploy individual subcharts. This means the network policy will NOT be deployed automatically.**

### Why This Happens

- Network policy template location: `helm/templates/network-policy.yaml` (root chart)
- ArgoCD applications deploy from: `microservices/book-service`, `infrastructure/mongodb`, etc. (subcharts)
- Individual subcharts don't include the root `templates/` directory
- No ArgoCD application deploys the complete root chart

### Solution Options

#### Option 0: Disable Network Policy (If You Don't Want It)

If you don't want to deploy the network policy at all, simply disable it in your values files:

**For Development:**
```yaml
# In values-dev.yaml
networkPolicy:
  enabled: false
```

**For Production:**
```yaml
# In values-prod.yaml
networkPolicy:
  enabled: false
```

Then commit and push:
```bash
git add values-dev.yaml values-prod.yaml
git commit -m "Disable network policy"
git push origin dev
```

ArgoCD will automatically sync the change and remove the network policy if it was previously deployed.

#### Option 1: Create Root-Level ArgoCD Application (Recommended)

Create a new ArgoCD application that deploys the complete root chart including network policy:

**Create `argocd-apps/apps/library-root-chart.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: library-root-chart
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: library-e2e
    app.kubernetes.io/component: infrastructure
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: library-e2e
  source:
    repoURL: https://github.com/Googleeyy/ChapterOne-Helm.git
    targetRevision: dev
    path: .  # Root of the helm directory
    helm:
      releaseName: library-root
      valueFiles:
        - values-dev.yaml  # or values-prod.yaml for production
  destination:
    server: https://kubernetes.default.svc
    namespace: library-dev  # or library-prod for production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - PrunePropagationPolicy=foreground
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 3
```

**For production**, create `argocd-apps/apps/library-root-chart-prod.yaml` with:
- `targetRevision: main` (or your production branch)
- `valueFiles: values-prod.yaml`
- `namespace: library-prod`

#### Option 2: Add Network Policy to Each Subchart

Add network policy templates to each individual subchart:
- `microservices/book-service/templates/network-policy.yaml`
- `microservices/user-service/templates/network-policy.yaml`
- etc.

**Pros**: Each service has its own policy
**Cons**: Redundant, harder to maintain, inconsistent policies

#### Option 3: Separate Network Policy Application

Create a standalone ArgoCD application just for the network policy:

**Create `argocd-apps/infra/network-policy.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: network-policy
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: library-e2e
    app.kubernetes.io/component: infrastructure
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: library-e2e
  source:
    repoURL: https://github.com/Googleeyy/ChapterOne-Helm.git
    targetRevision: dev
    path: templates
    helm:
      releaseName: network-policy
      valueFiles:
        - ../values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: library-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  revisionHistoryLimit: 3
```

**Note**: This requires restructuring the network policy as a standalone Helm chart.

### Recommended Approach

**Use Option 1** - Create a root-level ArgoCD application. This is the cleanest approach because:

1. Network policy is deployed once at the root level
2. Maintains the existing chart structure
3. Easier to manage and update
4. Follows Helm best practices

### Steps to Implement Option 1

1. **Create the ArgoCD application file** in `argocd-apps/apps/library-root-chart.yaml` (as shown above)
2. **Push to GitHub**:
   ```bash
   git add argocd-apps/apps/library-root-chart.yaml
   git commit -m "Add root chart ArgoCD application with network policy"
   git push origin dev
   ```
3. **ArgoCD will automatically sync** - The `app-of-apps.yaml` will detect the new file and sync it automatically (since it uses `directory: recurse: true`)
4. **NO kubectl apply needed** - ArgoCD handles everything. Just push to GitHub and wait for auto-sync.
5. **Or manually sync** (if auto-sync is disabled or you want immediate deployment):
   ```bash
   argocd app sync library-root  # Syncs the app-of-apps
   # or
   argocd app sync library-root-chart  # Syncs the specific application
   ```

**Important**: With ArgoCD, you should NOT run `kubectl apply` manually. ArgoCD manages the resources and will override any manual changes.

### Verification in ArgoCD

After deployment, verify the network policy is applied:

```bash
# Check network policy in cluster
kubectl get networkpolicy -n library-dev

# Describe the policy
kubectl describe networkpolicy library-network-policy -n library-dev

# Check ArgoCD application status
argocd app get library-root-chart
```

### Production Deployment

For production, you'll need:
1. A separate root chart application pointing to production branch
2. Use `values-prod.yaml` instead of `values-dev.yaml`
3. Deploy to `library-prod` namespace

**Example production application:**
```yaml
# argocd-apps/apps/library-root-chart-prod.yaml
spec:
  source:
    targetRevision: main  # or your production branch
    helm:
      valueFiles:
        - values-prod.yaml
  destination:
    namespace: library-prod
```

### How ArgoCD Gets the Network Policy

When you create the root-level ArgoCD application (`library-root-chart.yaml`), here's how ArgoCD deploys the network policy:

1. **ArgoCD detects the new application** - Your `app-of-apps.yaml` with `directory: recurse: true` finds the new YAML file in `argocd-apps/apps/`
2. **ArgoCD clones your repository** - Fetches the specified `targetRevision` (dev branch)
3. **ArgoCD renders the Helm chart** - Runs `helm template` on the root chart (path: `.` which is the helm directory)
4. **Helm processes templates** - The `templates/network-policy.yaml` is rendered with values from `values-dev.yaml`
5. **ArgoCD applies to Kubernetes** - The rendered NetworkPolicy resource is applied to the cluster
6. **Network policy becomes active** - Kubernetes CNI plugin enforces the rules

**Flow:**
```
GitHub → ArgoCD → Helm Template → NetworkPolicy YAML → Kubernetes API → CNI Enforcement
```

### Manual Application (Without ArgoCD)

If you want to apply the network policy manually without using ArgoCD:

```bash
cd helm

# Render and apply for dev
helm template library-dev . -f values-dev.yaml --namespace library-dev | kubectl apply -f -

# Render and apply for prod
helm template library-prod . -f values-prod.yaml --namespace library-prod | kubectl apply -f -
```

This bypasses ArgoCD entirely and applies the network policy directly to the cluster.

## Verification

### Check if Network Policy is Applied

**For Development Environment:**
```bash
kubectl get networkpolicy -n library-dev
```

**For Production Environment:**
```bash
kubectl get networkpolicy -n chapterone
```

Expected output:
```
NAME                    POD-SELECTOR   AGE
library-network-policy   <none>         1m
```

### Check Policy Details

**For Development Environment:**
```bash
kubectl describe networkpolicy library-network-policy -n library-dev
```

**For Production Environment:**
```bash
kubectl describe networkpolicy library-network-policy -n library-prod
```

### Test Connectivity

**In Development Environment:**
```bash
# Test from one pod to another
kubectl exec -it <pod-name> -n library-dev -- curl http://book-service:8081/api/books
```

**In Production Environment:**
```bash
# Test from one pod to another
kubectl exec -it <pod-name> -n library-prod -- curl http://book-service:8081/api/books
```

### Troubleshooting

If services cannot communicate:

1. Verify network policy is applied
2. Check if services are in the correct namespace
3. Ensure DNS is working (check kube-system access)
4. Verify port numbers match policy rules
5. Check CNI plugin supports network policies

## Best Practices

1. **Start with light policies** - Begin permissive, tighten over time
2. **Document exceptions** - Keep track of why rules exist
3. **Test thoroughly** - Validate in non-production first
4. **Monitor traffic** - Use network monitoring tools
5. **Review regularly** - Update policies as architecture evolves
6. **Use labels effectively** - Make selectors clear and meaningful
7. **Version control policies** - Track changes in Git

## Security Considerations

### What Our Policy Protects Against

- **Unauthorized namespace access** - Blocks traffic from other namespaces
- **Lateral movement** - Limits potential breach spread
- **Database exposure** - Restricts MongoDB to specific port

### What Our Policy Does NOT Protect Against

- **Pod-to-pod attacks within namespace** - Services can still attack each other
- **Application vulnerabilities** - Doesn't fix code-level issues
- **External attacks** - Requires additional security layers
- **Insider threats** - Assumes namespace is trusted

### Defense in Depth

Network policy is one layer. Combine with:

- **Image scanning** - Vulnerability-free containers
- **RBAC** - Access control at Kubernetes level
- **Secrets management** - Secure credential storage
- **Runtime security** - Monitor pod behavior
- **WAF/Ingress controls** - Edge protection

## Conclusion

Our light network policy provides a balance between security and operational simplicity. It:

- ✅ Enables all required service communication
- ✅ Blocks unauthorized cross-namespace access
- ✅ Maintains DNS and database connectivity
- ✅ Requires minimal maintenance
- ✅ Suits most microservices use cases

For higher security requirements, consider upgrading to service-specific or port-level policies. However, for our Library E2E application, this light policy provides adequate protection while ensuring smooth operation.

## References

- [Kubernetes Network Policies Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policy Editor](https://editor.cilium.io/)
- [Cilium Network Policies](https://docs.cilium.io/en/stable/policy/)
- [Calico Network Policies](https://docs.projectcalico.org/security/network-policy)
