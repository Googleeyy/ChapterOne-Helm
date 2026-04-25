# CI/CD with Namespace Strategy - Complete Guide

## Table of Contents

1. [Overview](#overview)
2. [Current CI Workflow](#current-ci-workflow)
3. [Git Branch Strategy](#git-branch-strategy)
4. [Problem with Current Approach](#problem-with-current-approach)
5. [Updated CI Workflow for Namespace Strategy](#updated-ci-workflow-for-namespace-strategy)
6. [Real-Life Scenarios](#real-life-scenarios)
7. [Implementation Steps](#implementation-steps)
8. [Best Practices](#best-practices)

---

## Overview

This guide explains how to integrate the namespace-based environment separation strategy with your existing CI/CD workflow that updates Helm chart image tags.

### Key Concepts

- **Namespace Strategy**: Using `library-dev` and `library-prod` namespaces to separate environments in a single cluster
- **Parent Chart Values**: Environment-specific values files (`values-dev.yaml`, `values-prod.yaml`) that override subchart defaults
- **Git Branch Strategy**: Using `dev` and `production` branches to track environment-specific configurations
- **CI Workflow**: GitHub Actions workflow that updates image tags in Helm chart values files

---

## Current CI Workflow

### Workflow File

The current reusable workflow is located at:
```
.github/workflows/_update_helm_chart.yml
```

### How It Works

**Input Parameters:**
- `service-name`: Name of the microservice (e.g., book-service, user-service)
- `image-tag`: Docker image tag to deploy (e.g., v1.0.5)
- `environment`: Environment branch (dev or production)
- `helm-repo`: Helm chart repository (default: Googleeyy/ChapterOne-Helm)
- `values-path`: Path to microservices values files (default: microservices)

**Workflow Steps:**

1. **Checkout Helm Repository**
   ```yaml
   - uses: actions/checkout@v4
     with:
       repository: ${{ inputs.helm-repo }}
       ref: ${{ inputs.environment }}  # Checks out dev or production branch
   ```

2. **Convert Service Name to YAML Key**
   ```bash
   # Convert kebab-case to camelCase for YAML key
   # book-service → bookService
   # user-service → userService
   SERVICE_KEY=$(echo "${{ inputs.service-name }}" | sed 's/-\([a-z]\)/\U\1/g')
   ```

3. **Update Image Tag in Subchart**
   ```bash
   FILE="helm-charts/microservices/${{ inputs.service-name }}/values.yaml"
   yq -i ".${SERVICE_KEY}.image.tag = \"${{ inputs.image-tag }}\"" "$FILE"
   ```

4. **Commit and Push**
   ```bash
   git add microservices/${{ inputs.service-name }}/values.yaml
   git commit -m "cd: update ${{ inputs.service-name }} image tag to ${{ inputs.image-tag }} [${{ inputs.environment }}]"
   git push origin ${{ inputs.environment }}
   ```

**Why This Conversion?**
- **Input parameter** (`service-name`): Uses kebab-case (`book-service`) because service names in Kubernetes and Docker are typically kebab-case
- **YAML key** (`bookService`): Uses camelCase because that's the convention in the values.yaml files
- **Automatic conversion**: The workflow converts kebab-case to camelCase using `sed` so you don't have to manually specify the correct YAML key format

### What It Updates

Currently, the workflow updates the **subchart values file**:
```
microservices/book-service/values.yaml
microservices/user-service/values.yaml
microservices/borrow-service/values.yaml
microservices/frontend/values.yaml
```

Example update in `microservices/book-service/values.yaml`:
```yaml
bookService:
  image:
    tag: "v1.0.5"  # Updated by CI
```

---

## Git Branch Strategy

### Branch Structure

The Helm repository uses two main branches:

```
ChapterOne-Helm/
├── dev/           # Development environment configurations
└── production/    # Production environment configurations
```

### Branch Purpose

**dev branch:**
- Contains Helm chart values for development environment
- Tracks development image tags (e.g., `dev`, `v1.0.5-dev`)
- Changes are pushed here when deploying to dev namespace

**production branch:**
- Contains Helm chart values for production environment
- Tracks production image tags (e.g., `v1.0.0`, `v1.0.5`)
- Changes are pushed here when deploying to production namespace

### Workflow Integration

When the CI workflow runs:
- If `environment: dev` → checks out `dev` branch → updates values → pushes to `dev` branch
- If `environment: production` → checks out `production` branch → updates values → pushes to `production` branch

---

## Problem with Current Approach

### The Issue

With the new namespace strategy, we have:

**Parent-level environment files:**
- `values-dev.yaml` - Overrides for dev environment
- `values-prod.yaml` - Overrides for prod environment

**Subchart default files:**
- `microservices/book-service/values.yaml` - Default values
- `microservices/user-service/values.yaml` - Default values
- etc.

**Current CI workflow problem:**
- Updates subchart default files (`microservices/*/values.yaml`)
- These are **defaults**, not environment-specific values
- Changes affect both dev and production (since both use the same subchart defaults)
- Doesn't leverage the parent-level environment override capability

### Example Problem

**Current behavior:**
```bash
# CI updates subchart default
microservices/book-service/values.yaml:
  bookService.image.tag: "v1.0.5"

# This affects BOTH environments because:
# - values-dev.yaml doesn't override bookService.image.tag
# - values-prod.yaml doesn't override bookService.image.tag
# - Both use the subchart default
```

**Desired behavior:**
```bash
# CI should update parent-level environment files
values-dev.yaml:
  bookService.image.tag: "v1.0.5-dev"

values-prod.yaml:
  bookService.image.tag: "v1.0.5"

# Each environment has its own image tag
```

---

## Updated CI Workflow for Namespace Strategy

### Required Changes

The CI workflow needs to update **parent-level environment files** instead of subchart files.

### New Workflow Logic

**For dev environment:**
- Checkout `dev` branch
- Update `values-dev.yaml` with the new image tag
- Commit and push to `dev` branch

**For production environment:**
- Checkout `production` branch
- Update `values-prod.yaml` with the new image tag
- Commit and push to `production` branch

### Updated Workflow Steps

```yaml
- name: Update image tag
  run: |
    if [ "${{ inputs.environment }}" == "dev" ]; then
      FILE="helm-charts/values-dev.yaml"
    else
      FILE="helm-charts/values-prod.yaml"
    fi
    
    if [ -f "$FILE" ]; then
      echo "Updating $FILE with tag ${{ inputs.image-tag }}"
      
      # Convert kebab-case to camelCase (e.g., book-service → bookService)
      SERVICE_KEY=$(echo "${{ inputs.service-name }}" | sed 's/-\([a-z]\)/\U\1/g')
      
      # Update the tag in the parent values file
      yq -i ".${SERVICE_KEY}.image.tag = \"${{ inputs.image-tag }}\"" "$FILE"
      echo "Updated tag successfully"
      yq ".${SERVICE_KEY}.image" "$FILE"
    else
      echo "::error::File not found: $FILE"
      exit 1
    fi

- name: Commit and Push changes
  run: |
    cd helm-charts
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    
    git remote set-url origin https://${{ secrets.HELM_REPO_PAT }}@github.com/${{ inputs.helm-repo }}.git
    
    if [ "${{ inputs.environment }}" == "dev" ]; then
      git add values-dev.yaml
    else
      git add values-prod.yaml
    fi
    
    if git diff --staged --quiet; then
      echo "No changes detected (tag might already be up to date)"
    else
      git commit -m "cd: update ${{ inputs.service-name }} image tag to ${{ inputs.image-tag }} [${{ inputs.environment }}]"
      git push origin ${{ inputs.environment }}
      echo "Successfully pushed changes to ${{ inputs.environment }} branch"
    fi
```

### Updated Input Parameters

Add a new optional parameter:

```yaml
inputs:
  use-parent-values:
    required: false
    type: boolean
    default: true
    description: "Update parent-level values files (values-dev.yaml/values-prod.yaml) instead of subchart files"
```

---

## Real-Life Scenarios

### Scenario 1: Development Deployment

**Situation:** Developer pushes code to book-service, builds image with tag `v1.0.5-dev`, wants to deploy to dev environment.

**Workflow:**
1. CI builds Docker image: `googleyy/book-service:v1.0.5-dev`
2. CI calls update Helm chart workflow:
   ```yaml
   service-name: book-service
   image-tag: v1.0.5-dev
   environment: dev
   ```
3. Workflow checks out `dev` branch
4. Workflow updates `values-dev.yaml`:
   ```yaml
   bookService:
     image:
       tag: v1.0.5-dev
   ```
5. Workflow commits and pushes to `dev` branch
6. ArgoCD/Flux detects change in `dev` branch
7. ArgoCD/Flux syncs to cluster:
   ```bash
   helm upgrade library-dev . -f values-dev.yaml --namespace library-dev
   ```
8. New image deployed to `library-dev` namespace

**Result:** Dev environment updated with new image, production unaffected.

### Scenario 2: Production Deployment

**Situation:** Book-service v1.0.5 is tested and ready for production deployment.

**Workflow:**
1. CI builds Docker image: `googleyy/book-service:v1.0.5`
2. CI calls update Helm chart workflow:
   ```yaml
   service-name: book-service
   image-tag: v1.0.5
   environment: production
   ```
3. Workflow checks out `production` branch
4. Workflow updates `values-prod.yaml`:
   ```yaml
   bookService:
     image:
       tag: v1.0.5
   ```
5. Workflow commits and pushes to `production` branch
6. ArgoCD/Flux detects change in `production` branch
7. ArgoCD/Flux syncs to cluster:
   ```bash
   helm upgrade library-prod . -f values-prod.yaml --namespace library-prod
   ```
8. New image deployed to `library-prod` namespace

**Result:** Production environment updated with new image, dev unaffected.

### Scenario 3: Multiple Services Deployment

**Situation:** Full platform update with multiple services.

**Workflow:**
```yaml
# Parallel deployment to dev
- service-name: book-service, image-tag: v1.0.5-dev, environment: dev
- service-name: user-service, image-tag: v2.1.3-dev, environment: dev
- service-name: borrow-service, image-tag: v1.2.0-dev, environment: dev
- service-name: frontend, image-tag: v3.0.0-dev, environment: dev

# After testing, deploy to production
- service-name: book-service, image-tag: v1.0.5, environment: production
- service-name: user-service, image-tag: v2.1.3, environment: production
- service-name: borrow-service, image-tag: v1.2.0, environment: production
- service-name: frontend, image-tag: v3.0.0, environment: production
```

**Result:** Each environment has its own set of image tags, tracked in separate Git branches.

### Scenario 4: Rollback

**Situation:** Production deployment has issues, need to rollback.

**Workflow:**
1. Checkout `production` branch
2. Manually revert `values-prod.yaml` to previous commit:
   ```bash
   git revert HEAD
   git push origin production
   ```
3. ArgoCD/Flux detects change and syncs
4. Helm upgrade with previous image tag

**Result:** Production rolled back to previous version, dev continues with latest.

---

## Implementation Steps

### Step 1: Update CI Workflow

Update the reusable workflow file in your reusable templates repository:

**File:** `.github/workflows/_update_helm_chart.yml`

**Changes:**
1. Add `use-parent-values` input parameter
2. Modify the file path logic to use parent values files
3. Update the git add/commit logic for the correct file

### Step 2: Update Helm Repository Structure

Ensure your Helm repository has the correct structure:

```
ChapterOne-Helm/
├── dev/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml  # Environment-specific overrides
│   ├── values-prod.yaml # Environment-specific overrides
│   ├── templates/
│   │   └── namespace.yaml
│   └── microservices/
│       ├── book-service/
│       │   └── values.yaml  # Defaults
│       ├── user-service/
│       │   └── values.yaml  # Defaults
│       └── ...
└── production/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    ├── templates/
    │   └── namespace.yaml
    └── microservices/
        ├── book-service/
        │   └── values.yaml
        └── ...
```

### Step 3: Configure Git Branches

Ensure your Helm repository has `dev` and `production` branches:

```bash
# Create dev branch
git checkout -b dev
git push origin dev

# Create production branch
git checkout -b production
git push origin production
```

### Step 4: Set Up ArgoCD/Flux (Optional)

If using GitOps:

**ArgoCD Application for dev:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: library-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Googleeyy/ChapterOne-Helm
    targetRevision: dev
    path: helm
  destination:
    server: https://kubernetes.default.svc
    namespace: library-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**ArgoCD Application for prod:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: library-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Googleeyy/ChapterOne-Helm
    targetRevision: production
    path: helm
  destination:
    server: https://kubernetes.default.svc
    namespace: library-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Step 5: Test the Workflow

**Test dev deployment:**
```yaml
# In your service repository's CI workflow
- name: Update Helm Chart
  uses: ./.github/workflows/_update_helm_chart.yml
  with:
    service-name: book-service
    image-tag: v1.0.5-dev
    environment: dev
    use-parent-values: true
  secrets:
    HELM_REPO_PAT: ${{ secrets.HELM_REPO_PAT }}
```

**Test production deployment:**
```yaml
- name: Update Helm Chart
  uses: ./.github/workflows/_update_helm_chart.yml
  with:
    service-name: book-service
    image-tag: v1.0.5
    environment: production
    use-parent-values: true
  secrets:
    HELM_REPO_PAT: ${{ secrets.HELM_REPO_PAT }}
```

---

## Best Practices

### 1. Branch Protection

Enable branch protection for `production` branch:
- Require pull request reviews
- Require status checks to pass
- Restrict who can push

### 2. Image Tagging Strategy

Use semantic versioning for production:
- `v1.0.0`, `v1.0.5`, `v2.0.0`

Use descriptive tags for development:
- `dev`, `v1.0.5-dev`, `feature-xyz`

### 3. Separate Secrets

Use different secrets for dev and production:
- `HELM_REPO_DEV_PAT` for dev branch
- `HELM_REPO_PROD_PAT` for production branch

### 4. Validation

Add validation steps to CI:
- Validate YAML syntax
- Validate Helm chart
- Test deployment in staging namespace first

### 5. Rollback Strategy

Keep track of previous image tags:
- Git history in values files
- Helm release history
- Consider using Helm rollback capability

### 6. Monitoring

Monitor deployments:
- Set up alerts for failed deployments
- Track deployment frequency
- Monitor application health after deployment

### 7. Documentation

Document your deployment process:
- Update this guide with any customizations
- Document any service-specific requirements
- Keep runbooks for common scenarios

---

## Summary

### Key Changes

1. **CI Workflow**: Update parent-level values files (`values-dev.yaml`, `values-prod.yaml`) instead of subchart files
2. **Git Branches**: Use `dev` and `production` branches to track environment-specific configurations
3. **Namespace Strategy**: Each environment deploys to its own namespace with its own image tags
4. **GitOps**: ArgoCD/Flux syncs changes from Git branches to Kubernetes namespaces

### Benefits

- **Isolation**: Dev and production are completely isolated
- **Traceability**: Git history shows exactly what was deployed and when
- **Safety**: Production changes require explicit action (pushing to production branch)
- **Flexibility**: Easy to add new environments (staging, QA, etc.)
- **Consistency**: Same Helm chart structure across all environments

### Workflow Summary

```
Developer Push → CI Build Image → CI Update Helm Chart → Git Push → ArgoCD Sync → Kubernetes Deploy
     ↓                ↓                    ↓              ↓           ↓              ↓
  Feature branch   docker:tag      values-dev.yaml   dev branch   library-dev    Dev Pods
                                                   or
                                                 values-prod.yaml  production branch  library-prod  Prod Pods
```

This approach provides a robust, scalable CI/CD pipeline with clear separation between development and production environments.
