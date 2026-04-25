# Namespace Strategy with Subcharts

## Overview

This document explains how the namespace-based environment separation works when each microservice has its own values file (subcharts).

## Helm Values Hierarchy

Helm uses a hierarchical values system where values from the parent chart override values in subcharts:

```
Priority (highest to lowest):
1. Parent chart values file passed with -f flag (values-dev.yaml or values-prod.yaml)
2. Parent chart default values (values.yaml)
3. Subchart values files (microservices/*/values.yaml)
4. Subchart default values
```

## How It Works

### Current Structure

```
helm/
├── Chart.yaml (parent chart)
├── values.yaml (parent defaults)
├── values-dev.yaml (dev overrides)
├── values-prod.yaml (prod overrides)
├── templates/
│   └── namespace.yaml
└── microservices/
    ├── book-service/
    │   ├── Chart.yaml (subchart)
    │   └── values.yaml (subchart defaults)
    ├── user-service/
    │   ├── Chart.yaml (subchart)
    │   └── values.yaml (subchart defaults)
    ├── borrow-service/
    │   ├── Chart.yaml (subchart)
    │   └── values.yaml (subchart defaults)
    └── frontend/
        ├── Chart.yaml (subchart)
        └── values.yaml (subchart defaults)
```

### Subchart Values Files (Defaults)

Each microservice has its own `values.yaml` with default configurations:

**Example: microservices/book-service/values.yaml**
```yaml
global:
  appName: library-e2e
  namespace: chapterone  # Default namespace
  imagePullPolicy: IfNotPresent

bookService:
  name: book-service
  replicas: 2  # Default replicas
  image:
    tag: latest  # Default image tag
```

### Parent Chart Overrides

When you deploy with a specific environment values file, the parent chart's values override the subchart defaults:

**Example: values-dev.yaml**
```yaml
global:
  namespace: library-dev  # OVERRIDES subchart's "chapterone"

bookService:
  replicas: 1  # OVERRIDES subchart's "2"
  image:
    tag: dev  # OVERRIDES subchart's "latest"
```

### Deployment Flow

When you run:
```bash
helm upgrade --install library-dev . -f values-dev.yaml --namespace library-dev
```

Helm performs the following:

1. **Loads parent chart dependencies** (subcharts)
2. **Merges values in priority order:**
   - Reads subchart values (microservices/*/values.yaml)
   - Reads parent defaults (values.yaml)
   - Applies environment overrides (values-dev.yaml)
3. **Final merged values for each subchart:**
   - `global.namespace`: `library-dev` (from values-dev.yaml)
   - `bookService.replicas`: `1` (from values-dev.yaml)
   - `bookService.image.tag`: `dev` (from values-dev.yaml)
   - Other values from subchart defaults remain unchanged

## Key Points

### 1. Namespace Propagation

The `global.namespace` value from the parent chart propagates to all subcharts:

- Parent values-dev.yaml: `global.namespace: library-dev`
- All subcharts receive: `global.namespace: library-dev`
- All resources in all subcharts are deployed to `library-dev` namespace

### 2. Subchart Values as Defaults

Subchart values files serve as **defaults** that can be overridden:

- If parent chart doesn't specify a value, subchart default is used
- If parent chart specifies a value, it overrides the subchart default
- This allows each microservice to have sensible defaults while maintaining environment-specific overrides at the parent level

### 3. No Changes Needed in Subcharts

**You do NOT need to modify subchart values files** for the namespace strategy to work:

- Subcharts continue to use their current values files as defaults
- Parent chart (values-dev.yaml, values-prod.yaml) handles all environment-specific overrides
- This keeps subcharts independent and reusable

### 4. Global Values Scope

Values under the `global` key are special in Helm:

- They are automatically passed to all subcharts
- All subcharts can access `global.namespace`, `global.imagePullPolicy`, etc.
- This is why we put `namespace` under `global` - to ensure all subcharts use the same namespace

## Example: Book Service

### Subchart Default (microservices/book-service/values.yaml)
```yaml
global:
  namespace: chapterone
  imagePullPolicy: IfNotPresent

bookService:
  name: book-service
  replicas: 2
  image:
    repository: googleyy/book-service
    tag: latest
  database:
    name: chapterone_books
```

### Parent Dev Override (values-dev.yaml)
```yaml
global:
  namespace: library-dev  # Overrides subchart default

bookService:
  replicas: 1  # Overrides subchart default
  image:
    tag: dev  # Overrides subchart default
  database:
    name: chapterone_books_dev  # Overrides subchart default
```

### Final Merged Values (what Helm actually uses)
```yaml
global:
  namespace: library-dev  # From values-dev.yaml
  imagePullPolicy: IfNotPresent  # From subchart default

bookService:
  name: book-service  # From subchart default
  replicas: 1  # From values-dev.yaml
  image:
    repository: googleyy/book-service  # From subchart default
    tag: dev  # From values-dev.yaml
  database:
    name: chapterone_books_dev  # From values-dev.yaml
```

## Why This Approach Works

### 1. Single Source of Truth for Environment

- Environment-specific configuration is centralized in parent chart (values-dev.yaml, values-prod.yaml)
- No need to modify multiple files when changing environment settings
- Easy to see all environment differences at a glance

### 2. Subchart Independence

- Subcharts remain independent and can be used standalone
- Subchart values files define sensible defaults
- Parent chart can override as needed for specific environments

### 3. Scalability

- Adding new environments only requires creating a new parent values file (e.g., values-staging.yaml)
- Subcharts don't need to be modified
- Works with any number of microservices

### 4. Namespace Isolation

- All resources from all subcharts go to the same namespace (library-dev or library-prod)
- Services in different namespaces are isolated from each other
- Network policies can control cross-namespace communication if needed

## Verification

To verify the namespace strategy is working:

```bash
# Deploy to dev
helm upgrade --install library-dev . -f values-dev.yaml --namespace library-dev --create-namespace

# Check which namespace resources are in
kubectl get pods -n library-dev
kubectl get svc -n library-dev

# Deploy to prod
helm upgrade --install library-prod . -f values-prod.yaml --namespace library-prod --create-namespace

# Check which namespace resources are in
kubectl get pods -n library-prod
kubectl get svc -n library-prod

# Verify isolation - dev and prod should have separate resources
kubectl get pods -A | grep library
```

## Summary

The namespace strategy works seamlessly with subcharts because:

1. **Parent chart values override subchart values** - Helm's built-in value merging
2. **Global values propagate to all subcharts** - Ensures consistent namespace across all services
3. **Subchart values remain as defaults** - No modification needed
4. **Environment-specific configuration is centralized** - Easy to manage and understand

This approach gives you the best of both worlds: independent microservices with their own defaults, and centralized environment management at the parent chart level.
