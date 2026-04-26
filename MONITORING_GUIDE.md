# Monitoring with Prometheus and Grafana

This guide provides comprehensive documentation for installing, configuring, and understanding the monitoring stack (Prometheus and Grafana) for the Library E2E platform using Helm.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Accessing Grafana](#accessing-grafana)
6. [Internal Workflow](#internal-workflow)
7. [Data Flow](#data-flow)
8. [Use Cases](#use-cases)
9. [Custom Dashboards](#custom-dashboards)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The monitoring stack consists of:

- **Prometheus**: An open-source systems monitoring and alerting toolkit that collects and stores metrics as time series data.
- **Grafana**: An open-source analytics and interactive visualization web platform that provides charts, graphs, and alerts for visualizing metrics.
- **Node Exporter**: A Prometheus exporter for hardware and OS metrics exposed by *NIX kernels.
- **Kube State Metrics**: A simple service that listens to the Kubernetes API server and generates metrics about the state of the objects.

### Key Features

- **Time Series Data Collection**: Prometheus scrapes metrics from configured targets at specified intervals
- **Multi-dimensional Data Model**: Metrics are identified by metric name and key-value pairs (labels)
- **Powerful Query Language**: PromQL allows flexible querying and aggregation of time series data
- **Flexible Visualization**: Grafana provides rich visualization capabilities with pre-built dashboards
- **Alert Management**: Configurable alerts based on metric thresholds
- **Long-term Storage**: Persistent storage for historical data analysis

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                       │
│                                                                  │
│  ┌──────────────┐         ┌──────────────┐                      │
│  │ Microservices│         │   Node       │                      │
│  │              │         │   Exporter   │                      │
│  │ - Book Svc   │         │              │                      │
│  │ - User Svc   │         │ - CPU        │                      │
│  │ - Borrow Svc │         │ - Memory     │                      │
│  │ - Frontend   │         │ - Disk       │                      │
│  └──────┬───────┘         └──────┬───────┘                      │
│         │                        │                               │
│         │ Metrics                │ Metrics                       │
│         │                        │                               │
│         ▼                        ▼                               │
│  ┌──────────────────────────────────────────┐                   │
│  │           Prometheus Server              │                   │
│  │                                          │                   │
│  │  - Scrapes metrics every 15s             │                   │
│  │  - Stores in TSDB (Time Series DB)       │                   │
│  │  - Retention: 7d (dev) / 15d (default)  │                   │
│  │  - Retention: 30d (prod)                 │                   │
│  └──────────────────┬───────────────────────┘                   │
│                     │                                            │
│                     │ Queries                                    │
│                     │                                            │
│                     ▼                                            │
│  ┌──────────────────────────────────────────┐                   │
│  │              Grafana                     │                   │
│  │                                          │                   │
│  │  - Visualizes metrics                    │                   │
│  │  - Pre-configured dashboards             │                   │
│  │  - Custom queries (PromQL)               │                   │
│  │  - Alert management                      │                   │
│  └──────────────────────────────────────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Components

1. **Prometheus Server**
   - Scrapes metrics from targets
   - Evaluates alerting rules
   - Stores time series data
   - Serves queries via HTTP API

2. **Grafana**
   - Visualization layer
   - Dashboard management
   - User authentication
   - Alert notification

3. **Node Exporter**
   - Runs on each Kubernetes node
   - Exposes hardware and OS metrics
   - Metrics include: CPU, memory, disk, network

4. **Kube State Metrics**
   - Listens to Kubernetes API
   - Generates metrics about cluster state
   - Metrics include: pod status, deployment info, resource quotas

5. **Kubelet**
   - Built-in Prometheus metrics
   - Container and pod metrics
   - Resource usage statistics

---

## Installation

### Prerequisites

- Kubernetes cluster (v1.20+)
- Helm 3.x installed
- kubectl configured
- Storage class configured (default: nfs-client)
- Sufficient cluster resources

### Step 1: Update Helm Dependencies

```bash
# Navigate to the helm chart directory
cd d:\CapsOnProject\ChapterOne-Helm\helm

# Update Helm dependencies
helm dependency update
```

This downloads the kube-prometheus-stack chart from the Prometheus Community repository.

### Step 2: Deploy with Helm

#### Development Environment

```bash
# Deploy to development namespace
helm install library-e2e . -f values-dev.yaml --namespace library-dev --create-namespace
```

#### Production Environment

```bash
# Deploy to production namespace
helm install library-e2e . -f values-prod.yaml --namespace library-prod --create-namespace
```

#### Default Environment

```bash
# Deploy with default values
helm install library-e2e . --namespace chapterone --create-namespace
```

### Step 3: Verify Installation

```bash
# Check Prometheus pods
kubectl get pods -n <namespace> -l app.kubernetes.io/name=prometheus

# Check Grafana pods
kubectl get pods -n <namespace> -l app.kubernetes.io/name=grafana

# Check all monitoring components
kubectl get all -n <namespace> -l release=library-e2e
```

Expected output:
```
NAME                                                 READY   STATUS    RESTARTS   AGE
prometheus-kube-prometheus-prometheus-0              2/2     Running   0          2m
alertmanager-kube-prometheus-alertmanager-0          1/1     Running   0          2m
grafana-kube-prometheus-grafana-6d5f8b9f7c-abc123    1/1     Running   0          2m
kube-state-metrics-kube-prometheus-kube-state-...   1/1     Running   0          2m
prometheus-node-exporter-abc123                      1/1     Running   0          2m
```

### Step 4: Deploy with ArgoCD

The monitoring stack can also be deployed via ArgoCD:

#### Development

```bash
# Apply the monitoring application
kubectl apply -f argocd-apps/apps/monitoring.yaml
```

#### Production

```bash
# Apply the monitoring application
kubectl apply -f argocd-apps-prod/apps/monitoring.yaml
```

---

## Configuration

### Environment-Specific Configurations

#### Development (values-dev.yaml)

- **Namespace**: library-dev
- **Prometheus Retention**: 7 days
- **Storage**: 5Gi
- **Resources**: Lower limits for cost efficiency
- **Ingress**: Disabled (access via port-forward)

#### Production (values-prod.yaml)

- **Namespace**: library-prod
- **Prometheus Retention**: 30 days
- **Storage**: 50Gi
- **Resources**: Higher limits for performance
- **Ingress**: Enabled with TLS
- **Admin Password**: Must be changed from default

#### Default (values.yaml)

- **Namespace**: chapterone
- **Prometheus Retention**: 15 days
- **Storage**: 10Gi
- **Resources**: Balanced configuration

### Key Configuration Parameters

#### Prometheus Configuration

```yaml
monitoring:
  prometheus:
    enabled: true
    prometheusSpec:
      retention: 15d                    # Data retention period
      resources:
        requests:
          cpu: "500m"
          memory: "512Mi"
        limits:
          cpu: "1000m"
          memory: "2Gi"
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: "nfs-client"
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: "10Gi"
```

#### Grafana Configuration

```yaml
monitoring:
  grafana:
    enabled: true
    adminPassword: "admin"              # CHANGE IN PRODUCTION
    persistence:
      enabled: true
      size: "5Gi"
    service:
      type: ClusterIP
      port: 3000
    ingress:
      enabled: false                    # Enable in production
```

#### Service Monitors

The configuration allows discovery of ServiceMonitor CRDs:

```yaml
serviceMonitorSelectorNilUsesHelmValues: false
serviceMonitorSelector: {}
```

This enables Prometheus to discover ServiceMonitor resources created by your applications.

---

## Accessing Grafana

### Method 1: Port Forwarding (Development)

```bash
# Forward Grafana port to localhost
kubectl port-forward -n <namespace> svc/library-e2e-kube-prometheus-grafana 3000:80

# Access Grafana at http://localhost:3000
```

**Default Credentials:**
- Username: `admin`
- Password: `admin` (change immediately in production)

### Method 2: Ingress (Production)

If ingress is configured:

```bash
# Add to /etc/hosts
<ingress-ip> grafana.library.local

# Access at https://grafana.library.local
```

### Method 3: NodePort (Alternative)

Modify values to use NodePort:

```yaml
monitoring:
  grafana:
    service:
      type: NodePort
      nodePort: 30000
```

Then access at `http://<node-ip>:30000`

---

## Internal Workflow

### Prometheus Workflow

#### 1. Service Discovery

Prometheus automatically discovers targets through:

- **Kubernetes API**: Discovers pods, services, and nodes
- **ServiceMonitors**: Custom resources that define scrape configurations
- **PodMonitors**: Alternative to ServiceMonitors for pod-based discovery

#### 2. Metric Scraping

```
Every 15 seconds (default scrape interval):
┌─────────────┐
│ Prometheus  │
│   Server    │
└──────┬──────┘
       │
       ├──► Scrapes /metrics endpoint from Node Exporter
       │    Returns: node_cpu_seconds_total, node_memory_*, etc.
       │
       ├──► Scrapes /metrics endpoint from Kubelet
       │    Returns: container_cpu_usage, container_memory_*, etc.
       │
       ├──► Scrapes /metrics endpoint from Kube State Metrics
       │    Returns: kube_pod_status, kube_deployment_*, etc.
       │
       └──► Scrapes /metrics endpoint from applications (if configured)
            Returns: custom application metrics
```

#### 3. Data Storage

Scraped metrics are stored in Prometheus's Time Series Database (TSDB):

- **Metric Name**: e.g., `http_requests_total`
- **Labels**: Key-value pairs, e.g., `method="GET", status="200"`
- **Timestamp**: Unix timestamp
- **Value**: Float64 value

Example stored metric:
```
http_requests_total{method="GET",status="200",service="book-service"} 1234 @ 1714280000
```

#### 4. Data Retention

- Data is compressed and stored on disk
- Old data is automatically deleted based on retention period
- Compaction runs periodically to optimize storage

#### 5. Query Evaluation

When Grafana (or any client) queries Prometheus:

1. PromQL query is parsed
2. Time range is determined
3. Relevant time series are selected
4. Aggregation functions are applied
5. Results are returned

### Grafana Workflow

#### 1. Data Source Configuration

Grafana is pre-configured with Prometheus as a data source:

```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://library-e2e-kube-prometheus-prometheus:9090
        access: proxy
        isDefault: true
```

#### 2. Dashboard Rendering

When a dashboard is loaded:

```
User Request
    │
    ▼
┌─────────────┐
│   Grafana   │
└──────┬──────┘
       │
       ├──► Parse dashboard JSON definition
       │
       ├──► For each panel:
       │    │
       │    ├──► Extract PromQL query
       │    │
       │    ├──► Send query to Prometheus
       │    │
       │    └──► Receive time series data
       │
       ├──► Apply visualization settings
       │
       └──► Render panel (graph, gauge, table, etc.)
```

#### 3. Panel Types

- **Time Series**: Line/area charts for metrics over time
- **Stat**: Single value with sparkline
- **Gauge**: Single value with min/max thresholds
- **Table**: Tabular data display
- **Heatmap**: Density visualization
- **Logs**: Log aggregation and search

#### 4. Auto-Refresh

Dashboards can auto-refresh at configured intervals (5s, 10s, 30s, 1m, etc.)

---

## Data Flow

### Complete Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA FLOW                                    │
└─────────────────────────────────────────────────────────────────────┘

1. METRIC EXPOSURE
   ┌──────────────┐
   │ Application  │ ──► Exposes /metrics endpoint (HTTP)
   │   / Pod      │     Format: Prometheus text format
   └──────────────┘     Example: http_requests_total{method="GET"} 123

2. SCRAPING
   ┌──────────────┐
   │ Prometheus   │ ──► HTTP GET /metrics every 15s
   │   Server     │     Parses text format into time series
   └──────────────┘

3. STORAGE
   ┌──────────────┐
   │   TSDB       │ ──► Stores metrics with labels and timestamps
   │ (Time Series │     Compresses data for efficiency
   │   Database)  │     Retention policy applies
   └──────────────┘

4. QUERYING
   ┌──────────────┐
   │   PromQL     │ ──► Query language for data retrieval
   │   Engine     │     Aggregates, filters, transforms data
   └──────────────┘

5. VISUALIZATION
   ┌──────────────┐
   │   Grafana    │ ──► Queries Prometheus via HTTP API
   │   Frontend   │     Renders charts and dashboards
   └──────────────┘

6. USER INTERACTION
   ┌──────────────┐
   │   User       │ ──► Views dashboards, creates alerts
   │   Browser    │     Investigates issues
   └──────────────┘
```

### Example: HTTP Request Rate Monitoring

```
Step 1: Application exposes metric
book-service:8081/metrics
  http_requests_total{method="GET",endpoint="/api/books",status="200"} 1500

Step 2: Prometheus scrapes metric
Every 15s, Prometheus fetches this value
Timestamp: 1714280000, Value: 1500
Timestamp: 1714280015, Value: 1505
Timestamp: 1714280030, Value: 1510

Step 3: Grafana queries rate
PromQL: rate(http_requests_total[5m])
Calculates: (1510 - 1500) / 300s = 0.033 requests/second

Step 4: Visualization
Graph shows request rate over time
User can see spikes, drops, trends
```

---

## Use Cases

### 1. Infrastructure Monitoring

**What to Monitor:**
- Node CPU, memory, disk, network usage
- Pod resource consumption
- Cluster capacity planning

**Key Metrics:**
- `node_cpu_seconds_total`: CPU usage per node
- `node_memory_MemAvailable_bytes`: Available memory
- `node_filesystem_avail_bytes`: Disk space
- `kube_pod_status_phase`: Pod status

**Dashboard:** Kubernetes Cluster Overview (pre-installed)

### 2. Application Performance Monitoring

**What to Monitor:**
- Request rates and error rates
- Response times (latency)
- Throughput
- Custom business metrics

**Key Metrics:**
- `http_requests_total`: Total HTTP requests
- `http_request_duration_seconds`: Request latency
- `jvm_memory_used_bytes`: JVM memory (if Java apps)

**Dashboard:** Create custom dashboard for your services

### 3. Resource Utilization

**What to Monitor:**
- CPU and memory usage per service
- Resource limits vs. actual usage
- Autoscaling triggers

**Key Metrics:**
- `container_cpu_usage_seconds_total`: Container CPU
- `container_memory_working_set_bytes`: Container memory
- `kube_pod_container_resource_limits`: Resource limits

**Dashboard:** Pods Overview (pre-installed)

### 4. Capacity Planning

**What to Monitor:**
- Long-term trends in resource usage
- Growth patterns
- Predictive scaling

**Key Metrics:**
- Historical CPU/memory trends
- Storage growth over time
- Network traffic patterns

**Dashboard:** Node Exporter Full (pre-installed)

### 5. Alerting

**Example Alerts:**
- High CPU usage (>80% for 5 minutes)
- High memory usage (>90% for 5 minutes)
- Pod crash loops
- High error rates (>5% for 5 minutes)
- Disk space running low (<10% free)

**Setup:** Configure in Prometheus or Grafana

---

## Custom Dashboards

### Adding Custom Dashboards

#### Method 1: Import from Grafana.com

1. Visit https://grafana.com/grafana/dashboards/
2. Find a dashboard (e.g., ID: 11135 for Spring Boot)
3. In Grafana UI: Dashboards → Import
4. Enter dashboard ID
5. Select Prometheus data source
6. Click Import

#### Method 2: Create Custom Dashboard

1. In Grafana UI: Dashboards → New → New Dashboard
2. Add panels with PromQL queries
3. Configure visualization settings
4. Save dashboard

#### Method 3: Add via Helm Values

Add custom dashboards to your values file:

```yaml
monitoring:
  grafana:
    dashboards:
      default:
        my-custom-dashboard:
          gnetId: 12345
          revision: 1
          datasource: Prometheus
```

#### Method 4: Use ConfigMap

Create a ConfigMap with dashboard JSON:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-dashboards
  namespace: library-dev
data:
  custom-dashboard.json: |
    {
      "dashboard": {
        "title": "Custom Dashboard",
        "panels": [...]
      }
    }
```

### Example PromQL Queries

#### CPU Usage by Pod

```promql
sum(rate(container_cpu_usage_seconds_total{image!=""}[5m])) by (pod)
```

#### Memory Usage by Pod

```promql
sum(container_memory_working_set_bytes{image!=""}) by (pod)
```

#### HTTP Request Rate

```promql
sum(rate(http_requests_total[5m])) by (service, method)
```

#### Error Rate

```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
```

#### Pod Restart Count

```promql
sum(kube_pod_container_status_restarts_total) by (pod)
```

---

## Troubleshooting

### Common Issues

#### 1. Prometheus Not Scraping Metrics

**Symptoms:** No data in Grafana dashboards

**Solutions:**
```bash
# Check Prometheus targets
kubectl port-forward -n <namespace> svc/library-e2e-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check if ServiceMonitors exist
kubectl get servicemonitors -n <namespace>

# Check pod labels match ServiceMonitor selector
kubectl describe pod <pod-name> -n <namespace>
```

#### 2. Grafana Cannot Connect to Prometheus

**Symptoms:** "Datasource not found" or connection errors

**Solutions:**
```bash
# Check Grafana datasource configuration
kubectl get configmap library-e2e-kube-prometheus-grafana -n <namespace> -o yaml

# Verify Prometheus service
kubectl get svc library-e2e-kube-prometheus-prometheus -n <namespace>

# Check network policies
kubectl get networkpolicy -n <namespace>
```

#### 3. High Memory Usage

**Symptoms:** Prometheus OOMKilled

**Solutions:**
- Increase memory limits in values.yaml
- Reduce retention period
- Reduce scrape interval
- Add more targets filtering

```yaml
monitoring:
  prometheus:
    prometheusSpec:
      resources:
        limits:
          memory: "4Gi"  # Increase from 2Gi
      retention: 7d      # Reduce from 15d
```

#### 4. Storage Issues

**Symptoms:** PVC pending or insufficient space

**Solutions:**
```bash
# Check PVC status
kubectl get pvc -n <namespace>

# Check storage class
kubectl get storageclass

# Increase storage size in values.yaml
monitoring:
  prometheus:
    prometheusSpec:
      storageSpec:
        volumeClaimTemplate:
          spec:
            resources:
              requests:
                storage: "20Gi"  # Increase from 10Gi
```

#### 5. Port Forward Not Working

**Symptoms:** Connection refused when port-forwarding

**Solutions:**
```bash
# Check if pod is running
kubectl get pods -n <namespace>

# Use correct service name
kubectl get svc -n <namespace>

# Try different port
kubectl port-forward -n <namespace> svc/<service-name> 3000:80
```

### Logs and Debugging

#### Prometheus Logs

```bash
# View Prometheus logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=prometheus -f

# Check for scraping errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=prometheus | grep ERROR
```

#### Grafana Logs

```bash
# View Grafana logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=grafana -f
```

#### Node Exporter Logs

```bash
# View Node Exporter logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=node-exporter -f
```

### Performance Tuning

#### Reduce Scrape Load

```yaml
monitoring:
  prometheus:
    prometheusSpec:
      scrapeInterval: 30s  # Increase from 15s
      evaluationInterval: 30s
```

#### Enable Compression

```yaml
monitoring:
  prometheus:
    prometheusSpec:
      storageSpec:
        tsdb:
          outOfOrderTimeWindow: 30m
```

#### Add Resource Limits

```yaml
monitoring:
  prometheus:
    prometheusSpec:
      resources:
        requests:
          cpu: "1000m"
          memory: "1Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
```

---

## Security Best Practices

### 1. Change Default Credentials

```yaml
monitoring:
  grafana:
    adminPassword: "your-secure-password-here"
```

### 2. Enable Authentication

```yaml
monitoring:
  grafana:
    grafana.ini:
      auth.anonymous:
        enabled: false
      auth.basic:
        enabled: true
```

### 3. Use TLS in Production

```yaml
monitoring:
  grafana:
    ingress:
      enabled: true
      tls:
        - secretName: grafana-tls-secret
          hosts:
            - grafana.library.local
```

### 4. Network Policies

Ensure network policies allow traffic between components:

```yaml
# Prometheus should be able to scrape targets
# Grafana should be able to query Prometheus
```

### 5. RBAC

Use RBAC to restrict access:

```yaml
# Create dedicated service accounts
# Limit permissions to necessary resources
```

---

## Maintenance

### Upgrading the Stack

```bash
# Update Helm dependencies
helm dependency update

# Upgrade release
helm upgrade library-e2e . -f values-dev.yaml -n library-dev
```

### Backup Grafana Dashboards

```bash
# Export dashboards via UI
# Or backup ConfigMaps
kubectl get configmap -n <namespace> -l grafana_dashboard=1 -o yaml > backup.yaml
```

### Backup Prometheus Data

```bash
# Backup PVC
kubectl get pvc -n <namespace>
# Use volume snapshot or copy data
```

---

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kube-Prometheus-Stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

---

## Summary

This monitoring stack provides:

- **Comprehensive Visibility**: Into cluster, node, and application metrics
- **Scalable Architecture**: Handles growing workloads
- **Flexible Configuration**: Environment-specific settings
- **Rich Visualization**: Pre-built and custom dashboards
- **Production-Ready**: Persistence, security, and performance tuning

By following this guide, you can effectively monitor your Library E2E platform, troubleshoot issues, and ensure optimal performance.
