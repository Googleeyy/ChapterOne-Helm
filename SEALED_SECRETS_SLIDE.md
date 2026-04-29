# Sealed Secrets — How We Encrypt Secrets for Git

> A presentation slide replacing the generic "Secrets Management & Configuration" slide with the actual Bitnami Sealed Secrets implementation used in the ChapterOne project.

---

## Slide Title
**SEALED SECRETS — GIT-SAFE ENCRYPTION**

---

## Left Panel: The Problem We Solved

### Why Kubernetes Secrets Are NOT Safe in Git

- Kubernetes Secrets are only **base64-encoded** — not encrypted.
- Anyone with repo access can read them with `echo <string> | base64 -d`.
- We needed to store credentials in Git so ArgoCD could deploy them automatically.
- **Our solution:** Bitnami Sealed Secrets.

### What We Encrypt in Production
| Sealed Secret File | Protects | Namespace-Bound |
|---|---|---|
| `sealed-mongodb-secret-prod.yaml` | MongoDB connection URI | `library-prod` only |
| `sealed-user-service-secret-prod.yaml` | `JWT_SECRET` signing key | `library-prod` only |

> **Key insight:** A SealedSecret encrypted for `library-prod` **cannot** be decrypted in `library-dev` or `default`. This prevents accidental secret leakage across environments.

---

## Right Panel: Dev vs Production

### Development (`library-dev`)
- Secrets stored as plain Kubernetes Secrets in `values-dev.yaml`
- `JWT_SECRET: "dev-jwt-secret-not-for-production"`
- No encryption needed — low-risk environment
- Mounted via standard `envFrom: secretRef`

### Production (`library-prod`)
- **Sealed Secrets** stored in `sealed-secrets-prod/` directory
- `JWT_SECRET` is encrypted with the cluster's **public key**
- Only the Sealed Secrets **Controller** (running inside the cluster) holds the **private key**
- ArgoCD syncs the `SealedSecret` → Controller decrypts → creates native `Secret` automatically

---

## Bottom Panel: The Sealed Secrets Workflow

### How It Works — Step by Step

```
Developer Laptop                          GitHub Repo                          Kubernetes Cluster
┌─────────────────┐                   ┌─────────────────┐                   ┌─────────────────────────┐
│  1. Create      │                   │  2. Commit      │                   │  3. ArgoCD detects      │
│     standard    │───kubeseal──────▶│     SealedSecret│◀───git push───────│     new SealedSecret    │
│     Secret YAML │   (public key)    │     to repo     │                   │     in repo             │
│                 │                   │                 │                   │                         │
│  JWT_SECRET=... │                   │  encrypted blob │                   │  4. Syncs SealedSecret  │
│                 │                   │                 │                   │     to library-prod     │
└─────────────────┘                   └─────────────────┘                   │                         │
                                                                            │  5. Sealed Secrets      │
                                                                            │     Controller decrypts │
                                                                            │     (private key)       │
                                                                            │                         │
                                                                            │  6. Native Secret       │
                                                                            │     created in NS only  │
                                                                            │                         │
                                                                            │  7. Pod mounts Secret   │
                                                                            │     via envFrom         │
                                                                            └─────────────────────────┘
```

### Asymmetric Encryption
- **Public key** (used by `kubeseal` CLI) → encrypts the secret on your laptop.
- **Private key** (held only by the Controller inside the cluster) → decrypts it.
- If someone steals the `SealedSecret` file from Git, they **cannot** decrypt it without cluster access.

---

## Why We Chose Sealed Secrets Over Alternatives

| Option | Why We Did NOT Choose It |
|--------|--------------------------|
| **External Secrets Operator** | Requires cloud KMS (AWS/Azure/GCP) integration — adds external dependency. |
| **HashiCorp Vault** | Requires running a Vault server, unsealing, managing tokens/AppRoles. Too complex for our learning-stage project. |
| **SOPS + Age** | Good alternative, but Sealed Secrets has native Kubernetes CRD support and works seamlessly with ArgoCD. |
| **Manual `kubectl apply`** | Breaks GitOps — ArgoCD is our single source of truth. |

**Our reasoning:** Sealed Secrets is self-hosted, zero external cloud dependency, and perfect for homelab/on-prem learning environments. It teaches the core principle — **asymmetric encryption for Git-safe secrets** — without operational overhead.

---

## Files in Our Repo

```
ChapterOne-Helm/
├── sealed-secrets-prod/
│   ├── sealed-mongodb-secret-prod.yaml
│   └── sealed-user-service-secret-prod.yaml
├── values-dev.yaml          # Plain secrets for dev
├── values-prod.yaml         # References sealed secrets
└── templates/
    └── network-policy.yaml   # Only prod has strict egress to kgateway-system + MongoDB
```

---

## Presenter Talking Points

> "Early in the project, I stored secrets in Git as base64. Then I ran `base64 -d` on one and realized anyone could read it. That was my wake-up call."

> "Sealed Secrets uses asymmetric encryption. I encrypt on my laptop with the cluster's public key. Only the controller inside the cluster has the private key. Even if someone steals our repo, the secrets are useless without the cluster."

> "Namespace-binding is critical. A secret sealed for `library-prod` won't decrypt in `library-dev`. That prevents accidents where prod credentials leak into dev."

> "We chose Sealed Secrets over Vault because as trainees, we wanted to learn encryption-in-Git without also having to learn Vault HA, unsealing, and token lifecycles. Sealed Secrets gives us the security concept without the infrastructure complexity."

---

## Slide Design Notes

- **Color scheme:** Dark background with green accents for "encrypted" and red accents for "plain text warning."
- **Icons:** Lock icon for Sealed Secrets, unlocked warning for base64.
- **Diagram:** Use the step-by-step flow above as a visual.
- **Code snippet:** Show a small before/after:
  - BEFORE: `apiVersion: v1, kind: Secret, data: { password: cGFzc3dvcmQxMjM= }` (base64 — unsafe)
  - AFTER: `apiVersion: bitnami.com/v1alpha1, kind: SealedSecret, spec: { encryptedData: {...} }` (encrypted — safe)
