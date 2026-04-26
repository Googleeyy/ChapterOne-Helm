# ArgoCD GitOps Implementation Guide

This guide implements ArgoCD-based GitOps CD for the Library E2E Helm chart.

## Table of Contents
1. [Architecture](#1-architecture-overview)
2. [Install ArgoCD](#2-install-argocd)
3. [Configure Access](#3-configure-access)
4. [Create Applications](#4-create-applications)
5. [Workflow](#5-how-it-works)
6. [Real Scenario](#6-real-life-scenario)
7. [Changes Made](#7-changes-summary)
8. [Day-2 Ops](#8-day-2-operations)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Architecture Overview

ArgoCD watches your Git branches and auto-syncs the cluster state.

```
GitHub ChapterOne-Helm                Kubernetes Cluster
- dev branch  --------watch------>   library-dev namespace
- production branch --watch------>    library-prod namespace

Microservice CI --update image tag--> Helm repo branch --> ArgoCD syncs
```

**Branch to Environment Mapping:**

| Branch | ArgoCD App | Values File | Namespace |
|--------|-----------|-------------|-----------|
| `dev` | `library-dev` | `values-dev.yaml` | `library-dev` |
| `production` | `library-prod` | `values-prod.yaml` | `library-prod` |

---

## 2. Install ArgoCD

Run on any machine with kubectl cluster-admin access:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f ChapterOne-Helm/helm/argocd/install/argocd-values.yaml
```

**Wait for pods:**
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=120s
```

---

## 3. Configure Access

### Port-Forward (Local)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open http://localhost:8080
```

### NodePort (Remote)
```bash
# ArgoCD UI is exposed on NodePort 30080
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://${NODE_IP}:30080"
```

### Get Admin Password
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d; echo
```
- **Username:** `admin`
- **Password:** (command output)

---

## 4. Create Applications

Apply the manifests provided in this repo.

### Method A: App of Apps (Recommended)
```bash
kubectl apply -f ChapterOne-Helm/helm/argocd/applications/app-of-apps.yaml
```
This single manifest creates an ArgoCD Application that manages all other Applications.

### Method B: Direct Apply
```bash
kubectl apply -f ChapterOne-Helm/helm/argocd/applications/library-dev.yaml
kubectl apply -f ChapterOne-Helm/helm/argocd/applications/library-prod.yaml
```

### Verify
```bash
argocd app list
```

---

## 5. How It Works

### Pure GitOps Flow (Helm Repo Changes)
1. You edit `values-dev.yaml` or Helm templates and push to branch.
2. ArgoCD detects the commit (polls every 3 min, or via webhook).
3. ArgoCD runs `helm template` with the matching `values-*.yaml`.
4. ArgoCD applies generated manifests to the mapped namespace.

### CI-Driven Flow (Microservice Changes)
1. Developer pushes to `dev` branch of `book-service`.
2. Reusable `_update_helm_chart.yml` is triggered.
3. It clones Helm repo `dev` branch, updates `bookService.image.tag` in `values-dev.yaml`.
4. It commits and pushes back to `ChapterOne-Helm:dev`.
5. ArgoCD detects the new commit on `dev`.
6. ArgoCD syncs `library-dev` Application automatically.

> **Key Point:** You never manually run `helm upgrade` on the cluster. ArgoCD does it for you.

---

## 6. Real-Life Scenario

### Deploy a Book Service Fix to Dev

1. Developer fixes a bug in `book-service` repo and pushes to `dev`.
2. CI builds image `googleyy/chapterone-book:dev-a1b2c3d`.
3. Reusable workflow updates `values-dev.yaml`:
   ```yaml
   bookService:
     image:
       tag: dev-a1b2c3d
   ```
4. Commit pushed to `ChapterOne-Helm:dev`.
5. ArgoCD sees new commit on `dev`.
6. ArgoCD syncs `library-dev` app.
7. Kubernetes rolls out new `book-service` pods in `library-dev`.

### Promote to Production

1. Create PR from `dev` to `production` in the Helm repo (or update `values-prod.yaml` directly).
2. Merge changes to `production` branch.
3. ArgoCD sees new commit on `production`.
4. ArgoCD syncs `library-prod` app.
5. Production environment updates with zero manual cluster access.

---

## 7. Changes Summary

### New Files Created

| File | Purpose |
|------|---------|
| `argocd/applications/library-dev.yaml` | ArgoCD Application tracking `dev` branch |
| `argocd/applications/library-prod.yaml` | ArgoCD Application tracking `production` branch |
| `argocd/applications/app-of-apps.yaml` | Meta-Application managing all environment apps |
| `argocd/install/argocd-values.yaml` | Helm values for ArgoCD installation on your cluster |
| `.github/workflows/helm-validate.yaml` | Validates Helm charts on PR/push before ArgoCD syncs |
| `.github/workflows/argocd-manual-sync.yaml` | Optional manual sync trigger via GitHub Actions |
| `ARGOCD_IMPLEMENTATION_GUIDE.md` | This guide |

### Existing Files You Must Configure

| File | Action Required |
|------|----------------|
| `values-dev.yaml` | Ensure `global.namespace: library-dev` is set (already done) |
| `values-prod.yaml` | Ensure `global.namespace: library-prod` is set (already done) |
| GitHub Secrets | Add `HELM_REPO_PAT` to microservice repos (already configured for CI) |
| ArgoCD Secrets | Add `chapterone-helm-repo` secret if repo is private (see Step 3) |

---

## 8. Day-2 Operations

### View Sync Status
```bash
argocd app get library-dev
argocd app get library-prod
```

### Force a Manual Sync
```bash
argocd app sync library-dev
argocd app sync library-prod --prune
```

### Enable Auto-Sync (if disabled)
```bash
argocd app set library-dev --sync-policy automated --auto-prune --self-heal
```

### Rollback an Application
```bash
# List history
argocd app history library-dev

# Rollback to previous revision
argocd app rollback library-dev 1
```

### Update ArgoCD
```bash
helm repo update
helm upgrade argocd argo/argo-cd --namespace argocd -f ChapterOne-Helm/helm/argocd/install/argocd-values.yaml
```

---

## 9. Troubleshooting

### ArgoCD Cannot Reach GitHub
- Check network from cluster to GitHub.
- For private repos, verify the repo secret `chapterone-helm-repo` exists in `argocd` namespace.

### Sync Failed / Helm Template Error
- Check the ArgoCD UI > Application > Sync Status for exact errors.
- Run local validation: `helm template library-dev . -f values-dev.yaml`.
- Ensure `helm dependency update` has been run and `charts/` folder is committed if needed.

### Application Shows OutOfSync Repeatedly
- Some resources generate fields server-side (e.g., PVCs, Services). Add `ignoreDifferences` to the Application spec if needed.

### Pods Not Starting After Sync
- Check namespace: `kubectl get pods -n library-dev`.
- Check ArgoCD events: `argocd app get library-dev`.
- Verify cluster resources (StorageClass, GatewayClass) still exist.

### Image Tag Not Updating
- Confirm the microservice CI workflow committed the tag change to the correct branch.
- Verify ArgoCD shows the latest commit SHA in the Application details.

---

## Quick Reference Commands

```bash
# Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f ChapterOne-Helm/helm/argocd/install/argocd-values.yaml

# Port-forward UI
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Apply all Applications
kubectl apply -f ChapterOne-Helm/helm/argocd/applications/app-of-apps.yaml

# Check status
argocd app list
kubectl get pods -n library-dev
kubectl get pods -n library-prod
```
