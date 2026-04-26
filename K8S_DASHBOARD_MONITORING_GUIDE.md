# Kubernetes Dashboard Monitoring Guide
## Complete Understanding of Your K8s Monitoring Stack

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Data Flow & Internal Workflow](#data-flow--internal-workflow)
4. [Grafana Dashboard Components](#grafana-dashboard-components)
5. [Dashboard Variables Explained](#dashboard-variables-explained)
6. [Common Dashboard Panels](#common-dashboard-panels)
7. [Metrics Collection Layer](#metrics-collection-layer)
8. [Aggregation Layer](#aggregation-layer)
9. [Prometheus Query Language (PromQL)](#prometheus-query-language-promql)
10. [Practical Examples](#practical-examples)

---

## Overview

Your Kubernetes dashboard at `http://54.174.65.55:32632/d/adrlfng/k8s-dashboard` is a **Grafana** visualization interface that displays real-time metrics from your Kubernetes cluster. This dashboard provides insights into:

- **Cluster Health**: Overall status of nodes, pods, and services
- **Resource Utilization**: CPU, memory, disk, and network usage
- **Application Performance**: Response times, error rates, throughput
- **Infrastructure Metrics**: Node-level resource consumption

### What You're Seeing

The URL parameters reveal:
- **Port 32632**: Grafana service endpoint
- **Dashboard ID**: `adrlfng` (unique identifier for this dashboard)
- **Time Range**: Last 30 minutes (`from=now-30m&to=now`)
- **Variables**: Filters for Node, Namespace, Container, Pod

---

## Architecture Components

### 1. **Kubernetes Cluster**
The foundation where your applications run. It consists of:
- **Control Plane**: API Server, Scheduler, Controller Manager, etcd
- **Worker Nodes**: Machines running your pods
- **Pods**: Smallest deployable units (containers)
- **Services**: Network abstractions for pod communication

### 2. **kube-state-metrics**
**Purpose**: Generates metrics from Kubernetes objects

**What it does**:
- Listens to Kubernetes API Server
- Converts Kubernetes object state to Prometheus metrics
- Provides metrics about:
  - Pod status (running, pending, failed)
  - Deployment replicas
  - Node conditions
  - Service endpoints
  - Resource requests/limits

**Example Metrics**:
```
kube_pod_status_phase{phase="Running"}
kube_deployment_status_replicas_available
kube_node_status_condition{condition="Ready"}
```

### 3. **Node Exporter**
**Purpose**: Exposes hardware and OS metrics from each node

**What it does**:
- Runs as a DaemonSet (one pod per node)
- Collects:
  - CPU usage (user, system, idle, iowait)
  - Memory usage (free, used, cached, buffers)
  - Disk I/O (read/write operations, bytes)
  - Network traffic (bytes in/out, packets in/out)
  - Filesystem usage
  - System load (1min, 5min, 15min)

**Example Metrics**:
```
node_cpu_seconds_total
node_memory_MemAvailable_bytes
node_filesystem_size_bytes
node_network_receive_bytes_total
```

### 4. **cAdvisor (Container Advisor)**
**Purpose**: Built into Kubelet, exposes container metrics

**What it does**:
- Runs on every node (part of Kubelet)
- Collects container-level metrics:
  - Container CPU usage
  - Container memory usage
  - Container filesystem usage
  - Container network stats
  - Container lifecycle events

**Example Metrics**:
```
container_cpu_usage_seconds_total
container_memory_working_set_bytes
container_fs_usage_bytes
```

### 5. **Prometheus**
**Purpose**: Time-series database and metrics collection system

**What it does**:
- **Scrapes** metrics from targets (kube-state-metrics, node-exporter, cAdvisor)
- **Stores** metrics in a time-series database
- **Evaluates** recording rules and alerts
- **Serves** queries via PromQL
- **Retains** data for configurable duration (default 15 days)

**Key Components**:
- **Prometheus Server**: Main scraping and storage engine
- **Service Discovery**: Automatically finds Kubernetes pods/services
- **TSDB**: Time-series database for storage
- **PromQL**: Query language for data retrieval

### 6. **Grafana**
**Purpose**: Visualization and dashboarding platform

**What it does**:
- Connects to Prometheus as a data source
- Creates interactive dashboards
- Visualizes metrics with graphs, gauges, tables
- Supports variables for dynamic filtering
- Enables alerting and notifications

---

## Data Flow & Internal Workflow

### Complete Data Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Pod 1      │  │   Pod 2      │  │   Pod N      │          │
│  │ (App Container)│  │ (App Container)│  │ (App Container)│          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│                    ┌──────▼──────┐                               │
│                    │   Kubelet   │                               │
│                    │  (cAdvisor) │                               │
│                    └──────┬──────┘                               │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            │ Metrics: /metrics/cadvisor
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    KUBERNETES API SERVER                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              kube-state-metrics                          │  │
│  │  (Listens to API events, generates K8s object metrics)   │  │
│  └────────────────────────┬─────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            │ Metrics: /metrics
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    NODE EXPORTER (DaemonSet)                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  One pod per node, exposes hardware/OS metrics          │  │
│  └────────────────────────┬─────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            │ Metrics: /metrics
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    PROMETHEUS SERVER                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  1. Service Discovery (finds all targets)                 │  │
│  │  2. Scraping (pulls metrics every 15s)                   │  │
│  │  3. Storage (TSDB - time series database)                │  │
│  │  4. Evaluation (recording rules, alerts)                 │  │
│  │  5. Query Serving (PromQL API)                           │  │
│  └────────────────────────┬─────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            │ HTTP API: /api/v1/query
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    GRAFANA                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  1. Data Source Configuration (Prometheus)               │  │
│  │  2. Dashboard Definition (JSON)                          │  │
│  │  3. Query Builder (PromQL)                               │  │
│  │  4. Visualization (Panels)                               │  │
│  │  5. Variables (Dynamic filters)                          │  │
│  └────────────────────────┬─────────────────────────────────┘  │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            │ HTTP: Browser renders UI
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    YOUR BROWSER                                  │
│                    http://54.174.65.55:32632/...                 │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Workflow

#### Step 1: Metrics Generation (Every Second)
```
Kubelet (cAdvisor) → Collects container metrics → Exposes at :10250/metrics/cadvisor
Node Exporter → Collects node metrics → Exposes at :9100/metrics
kube-state-metrics → Watches K8s API → Exposes at :8080/metrics
```

#### Step 2: Service Discovery (Continuous)
```
Prometheus → Queries K8s API → Discovers all pods/endpoints → Updates scrape targets
```

#### Step 3: Scraping (Every 15 seconds by default)
```
Prometheus → HTTP GET /metrics → Parses metrics → Stores in TSDB
```

#### Step 4: Data Storage
```
Prometheus TSDB → Organizes by metric name + labels → Compresses data → Retains for 15 days
```

#### Step 5: Query Execution (On Dashboard Load)
```
Grafana → Sends PromQL query to Prometheus → Prometheus evaluates → Returns time series → Grafana renders
```

#### Step 6: Visualization
```
Grafana → Transforms data → Applies panel settings → Renders graphs/tables → Browser displays
```

---

## Grafana Dashboard Components

### Dashboard Structure

Your dashboard consists of:

#### 1. **Variables (Top Bar)**
These are the dropdown filters you see:
- **origin_prometheus**: Selects Prometheus data source (if multiple)
- **Node**: Filters by Kubernetes node
- **NameSpace**: Filters by Kubernetes namespace
- **Container**: Filters by container name
- **Pod**: Filters by specific pod

**How Variables Work**:
```
User selects "default" namespace → Grafana updates all queries → 
Queries now include: namespace="default" → Results filtered automatically
```

#### 2. **Panels (The Visualizations)**
Each panel shows a specific metric:
- **Time Series Graphs**: Show metrics over time
- **Stat Panels**: Show current values with sparklines
- **Tables**: Show tabular data
- **Gauges**: Show values against thresholds
- **Heatmaps**: Show distribution of values

#### 3. **Rows**
Panels are organized into rows (horizontal sections):
- **Cluster Overview**: High-level cluster health
- **Node Metrics**: Per-node resource usage
- **Pod Metrics**: Per-pod resource usage
- **Network Metrics**: Traffic and connectivity
- **Storage Metrics**: Disk usage and I/O

---

## Dashboard Variables Explained

### 1. **origin_prometheus**
- **Purpose**: Selects which Prometheus instance to query
- **Use Case**: When you have multiple Prometheus servers (e.g., dev, prod)
- **Impact**: Changes the data source for all queries

### 2. **Node ($__all)**
- **Purpose**: Filters metrics by Kubernetes node
- **Values**: 
  - `$__all`: Shows all nodes aggregated
  - Specific node name: Shows metrics for that node only
- **Example**: `node_cpu_seconds_total{node="worker-1"}`

### 3. **NameSpace ($__all)**
- **Purpose**: Filters by Kubernetes namespace
- **Values**:
  - `$__all`: Shows all namespaces
  - `default`: Default namespace
  - `kube-system`: Kubernetes system components
  - `monitoring`: Monitoring stack namespace
  - Custom namespaces: Your application namespaces
- **Example**: `container_memory_usage_bytes{namespace="book-service"}`

### 4. **Container ($__all)**
- **Purpose**: Filters by container name within pods
- **Values**:
  - `$__all`: All containers
  - Specific container: e.g., `book-service`, `nginx`, `redis`
- **Example**: `container_cpu_usage_seconds_total{container="book-service"}`

### 5. **Pod ($__all)**
- **Purpose**: Filters by specific pod
- **Values**:
  - `$__all`: All pods
  - Specific pod: e.g., `book-service-7d8f9c4b-x2k5p`
- **Example**: `kube_pod_status_ready{pod="book-service-7d8f9c4b-x2k5p"}`

### Variable Interpolation in Queries

When you select variables, Grafana automatically replaces them in queries:

**Before (with variables)**:
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="$NameSpace", pod="$Pod"}[5m]))
```

**After (with selections)**:
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="book-service", pod="book-service-7d8f9c4b-x2k5p"}[5m]))
```

---

## Common Dashboard Panels

### 1. **Cluster CPU Usage**
**Metric**: `sum(rate(container_cpu_usage_seconds_total{id="/"}[5m])) / sum(kube_node_status_capacity_cpu_cores)`

**What it shows**:
- Total CPU usage across the entire cluster
- Percentage of cluster CPU capacity being used
- Helps identify if cluster needs more nodes

**Data Source**: cAdvisor (via Kubelet)

### 2. **Cluster Memory Usage**
**Metric**: `sum(container_memory_working_set_bytes{id="/"}) / sum(kube_node_status_capacity_memory_bytes)`

**What it shows**:
- Total memory usage across cluster
- Percentage of cluster memory capacity
- Helps identify memory pressure

**Data Source**: cAdvisor (via Kubelet)

### 3. **Pod Count by Status**
**Metric**: `sum by (phase) (kube_pod_status_phase)`

**What it shows**:
- Number of pods in each state: Running, Pending, Failed, Succeeded
- Helps identify scheduling issues or crashes

**Data Source**: kube-state-metrics

### 4. **Node CPU Usage**
**Metric**: `sum by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))`

**What it shows**:
- CPU usage per node
- Identifies overloaded nodes
- Helps with pod scheduling decisions

**Data Source**: Node Exporter

### 5. **Container CPU Usage (Top 10)**
**Metric**: `topk(10, sum by (pod, namespace, container) (rate(container_cpu_usage_seconds_total{container!=""}[5m])))`

**What it shows**:
- Top 10 containers by CPU usage
- Helps identify resource-hungry applications
- Useful for capacity planning

**Data Source**: cAdvisor (via Kubelet)

### 6. **Network Traffic**
**Metric**: `sum(rate(container_network_receive_bytes_total[5m]))` and `sum(rate(container_network_transmit_bytes_total[5m]))`

**What it shows**:
- Network ingress (incoming) and egress (outgoing) traffic
- Bandwidth usage over time
- Helps identify network-intensive applications

**Data Source**: cAdvisor (via Kubelet)

### 7. **Disk I/O**
**Metric**: `rate(node_disk_io_time_seconds_total[5m])`

**What it shows**:
- Disk I/O operations per second
- Helps identify storage bottlenecks
- Useful for database performance analysis

**Data Source**: Node Exporter

### 8. **Pod Restart Count**
**Metric**: `sum by (pod) (increase(kube_pod_container_status_restarts_total[1h]))`

**What it shows**:
- Number of container restarts per pod
- High restarts indicate application crashes
- Critical for application health monitoring

**Data Source**: kube-state-metrics

---

## Metrics Collection Layer

### Scraping Configuration

Prometheus uses **Service Discovery** to find targets:

#### Kubernetes Service Discovery Types

1. **Node Scrape Config**
```yaml
- job_name: 'kubernetes-nodes'
  kubernetes_sd_configs:
  - role: node
  relabel_configs:
  - source_labels: [__address__]
    regex: '(.*):10250'
    replacement: '${1}:9100'
    target_label: __address__
```
**What it does**: Discovers all nodes, scrapes Node Exporter on port 9100

2. **Pod Scrape Config**
```yaml
- job_name: 'kubernetes-pods'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
```
**What it does**: Discovers pods with `prometheus.io/scrape: true` annotation

3. **Service Scrape Config**
```yaml
- job_name: 'kubernetes-services'
  kubernetes_sd_configs:
  - role: service
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
    action: keep
    regex: true
```
**What it does**: Discovers services with `prometheus.io/scrape: true` annotation

### Scrape Intervals

- **Default**: Every 15 seconds
- **High-frequency metrics**: Every 5 seconds (for critical alerts)
- **Low-frequency metrics**: Every 1 minute (for capacity planning)

### Metric Labels

Labels are key-value pairs that add context:

**Example**:
```
container_cpu_usage_seconds_total{
  namespace="book-service",
  pod="book-service-7d8f9c4b-x2k5p",
  container="book-service",
  image="book-service:1.0.0",
  node="worker-1"
}
```

**Common Labels**:
- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `node`: Node name
- `instance`: Hostname:port
- `job`: Scrape job name
- `__name__`: Metric name (internal)

---

## Aggregation Layer

### What is Aggregation?

Aggregation combines multiple time series into a single value using functions.

### Aggregation Functions

#### 1. **sum()**
Adds up all values:
```promql
sum(container_cpu_usage_seconds_total)
```
**Use Case**: Total cluster CPU usage

#### 2. **avg()**
Calculates average:
```promql
avg(node_memory_MemAvailable_bytes)
```
**Use Case**: Average memory available across nodes

#### 3. **min() / max()**
Finds minimum or maximum:
```promql
max(rate(container_cpu_usage_seconds_total[5m]))
```
**Use Case**: Find hottest container

#### 4. **rate()**
Calculates per-second rate of increase:
```promql
rate(container_cpu_usage_seconds_total[5m])
```
**Use Case**: CPU usage per second (counters only)

#### 5. **irate()**
Instant rate (last two data points):
```promql
irate(container_cpu_usage_seconds_total[5m])
```
**Use Case**: Fast-changing counters

#### 6. **increase()**
Total increase over time period:
```promql
increase(container_cpu_usage_seconds_total[1h])
```
**Use Case**: Total CPU seconds used in 1 hour

#### 7. **topk() / bottomk()**
Top or bottom K values:
```promql
topk(10, rate(container_cpu_usage_seconds_total[5m]))
```
**Use Case**: Top 10 CPU consumers

### Grouping with `by()`

Aggregates while preserving specific labels:

```promql
sum by (namespace) (container_cpu_usage_seconds_total)
```
**Result**: One time series per namespace

```promql
sum by (namespace, pod) (container_cpu_usage_seconds_total)
```
**Result**: One time series per pod in each namespace

### Aggregation Pipeline Example

**Query**: CPU usage by namespace
```promql
sum by (namespace) (
  rate(container_cpu_usage_seconds_total{container!=""}[5m])
)
```

**Step-by-step**:
1. `container_cpu_usage_seconds_total{container!=""}` - Filter out non-container metrics
2. `rate(...[5m])` - Calculate per-second rate over 5 minutes
3. `sum by (namespace)` - Sum all containers, group by namespace

**Result**:
```
{namespace="book-service"} 0.5
{namespace="borrow-service"} 0.3
{namespace="frontend"} 0.2
{namespace="kube-system"} 0.1
```

---

## Prometheus Query Language (PromQL)

### Basic Syntax

```
metric_name{label="value"} [time_range]
```

### Examples

#### 1. **Simple Metric**
```promql
container_cpu_usage_seconds_total
```
Returns all time series for this metric

#### 2. **With Label Filter**
```promql
container_cpu_usage_seconds_total{namespace="book-service"}
```
Returns only time series for book-service namespace

#### 3. **Multiple Label Filters**
```promql
container_cpu_usage_seconds_total{namespace="book-service", container="book-service"}
```
Returns only book-service container in book-service namespace

#### 4. **Regex Match**
```promql
container_cpu_usage_seconds_total{namespace=~"book-.*"}
```
Returns all namespaces starting with "book-"

#### 5. **Negative Match**
```promql
container_cpu_usage_seconds_total{namespace!="kube-system"}
```
Returns all except kube-system

### Operators

#### Arithmetic Operators
```promql
container_cpu_usage_seconds_total * 100  # Multiply
container_memory_usage_bytes / 1024 / 1024  # Convert to MB
```

#### Comparison Operators
```promql
container_cpu_usage_seconds_total > 0.5  # Greater than
container_memory_usage_bytes < 1073741824  # Less than 1GB
```

#### Logical Operators
```promql
container_cpu_usage_seconds_total > 0.5 and container_memory_usage_bytes < 1073741824
```

### Functions

#### rate()
```promql
rate(http_requests_total[5m])
```
Calculates per-second rate over 5 minutes

#### increase()
```promql
increase(http_requests_total[1h])
```
Total increase over 1 hour

#### predict_linear()
```promql
predict_linear(container_cpu_usage_seconds_total[1h], 3600)
```
Predicts value 1 hour in the future

#### histogram_quantile()
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```
Calculates 95th percentile

---

## Practical Examples

### Example 1: Find High CPU Pods

**Goal**: Find pods using more than 1 CPU core

**Query**:
```promql
sum by (pod, namespace) (
  rate(container_cpu_usage_seconds_total{container!=""}[5m])
) > 1
```

**Explanation**:
1. Filter out non-container metrics
2. Calculate per-second rate over 5 minutes
3. Sum by pod and namespace
4. Filter for values > 1 (1 CPU core)

### Example 2: Memory Usage by Namespace

**Goal**: Show memory usage per namespace

**Query**:
```promql
sum by (namespace) (
  container_memory_working_set_bytes{container!=""}
) / 1024 / 1024 / 1024
```

**Explanation**:
1. Filter for containers
2. Sum by namespace
3. Convert bytes to GB

### Example 3: Pod Restart Rate

**Goal**: Find pods with high restart rates

**Query**:
```promql
sum by (pod, namespace) (
  increase(kube_pod_container_status_restarts_total[1h])
) > 5
```

**Explanation**:
1. Calculate restarts in last hour
2. Sum by pod and namespace
3. Filter for > 5 restarts

### Example 4: Network Traffic by Service

**Goal**: Show network traffic per service

**Query**:
```promql
sum by (namespace) (
  rate(container_network_receive_bytes_total[5m]) +
  rate(container_network_transmit_bytes_total[5m])
)
```

**Explanation**:
1. Calculate ingress rate
2. Calculate egress rate
3. Add them together
4. Sum by namespace

### Example 5: Disk Usage Percentage

**Goal**: Show disk usage percentage per node

**Query**:
```promql
1 - (
  sum by (instance) (node_filesystem_avail_bytes{fstype!="tmpfs"}) /
  sum by (instance) (node_filesystem_size_bytes{fstype!="tmpfs"})
)
```

**Explanation**:
1. Get available bytes per node
2. Get total bytes per node
3. Calculate ratio
4. Subtract from 1 to get used percentage

---

## How to Use Your Dashboard Effectively

### Daily Monitoring Routine

1. **Check Cluster Health**
   - Look at overall CPU and memory usage
   - Check pod status (Running vs Failed)
   - Verify node availability

2. **Review Resource Utilization**
   - Identify top CPU consumers
   - Identify top memory consumers
   - Check for resource waste

3. **Investigate Anomalies**
   - Look for sudden spikes
   - Check for high restart counts
   - Review network traffic patterns

### Troubleshooting Guide

#### Issue: High CPU Usage
1. Select the namespace with high CPU
2. Drill down to specific pods
3. Identify the container causing high usage
4. Check if it's expected (scaling event) or abnormal (bug)

#### Issue: Pod Crashes
1. Check "Pod Restart Count" panel
2. Select the crashing pod
3. Look at logs (kubectl logs)
4. Check resource limits (might be OOM killed)

#### Issue: Network Latency
1. Check "Network Traffic" panel
2. Look for bandwidth saturation
3. Check for packet loss
4. Review network policies

#### Issue: Disk Full
1. Check "Disk Usage" panel
2. Identify full filesystems
3. Check for log rotation
4. Review PVC usage

---

## Advanced Topics

### Recording Rules

Pre-compute expensive queries for faster dashboard loading:

```yaml
groups:
- name: k8s.rules
  rules:
  - record: namespace:container_cpu_usage_seconds_total:sum_rate
    expr: sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
```

### Alerting

Set up alerts based on dashboard metrics:

```yaml
groups:
- name: k8s.alerts
  rules:
  - alert: HighCPUUsage
    expr: sum(rate(container_cpu_usage_seconds_total[5m])) / sum(kube_node_status_capacity_cpu_cores) > 0.8
    for: 5m
    annotations:
      summary: "Cluster CPU usage above 80%"
```

### Dashboard JSON Export

Your dashboard is defined as JSON. You can:
- Export it for version control
- Import it to other Grafana instances
- Share it with your team

---

## Summary

### Key Takeaways

1. **Data Flow**: Kubelet/cAdvisor → Prometheus → Grafana → Your Browser
2. **Metrics Sources**: kube-state-metrics (K8s objects), Node Exporter (hardware), cAdvisor (containers)
3. **Variables**: Dynamic filters that update all queries
4. **Aggregation**: Combines time series using functions like sum(), avg(), rate()
5. **PromQL**: Query language for retrieving and transforming metrics

### Components in Your Stack

- **Kubernetes**: Runs your applications
- **kube-state-metrics**: Exposes K8s object state
- **Node Exporter**: Exposes node hardware metrics
- **cAdvisor**: Exposes container metrics (built into Kubelet)
- **Prometheus**: Scrapes, stores, and serves metrics
- **Grafana**: Visualizes metrics in dashboards

### Next Steps

1. **Explore your dashboard**: Click through different panels and variables
2. **Build custom queries**: Use Grafana's query builder
3. **Set up alerts**: Configure alerts for critical metrics
4. **Create custom dashboards**: Build dashboards for your specific needs
5. **Optimize**: Adjust scrape intervals and retention based on needs

---

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Monitoring](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-usage-monitoring/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-27  
**Author**: Senior DevOps Engineer  
**Purpose**: Complete understanding of Kubernetes monitoring stack for beginners
