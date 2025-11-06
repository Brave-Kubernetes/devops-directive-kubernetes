# Kubernetes Resource Monitoring Commands

## Basic Resource Usage Commands

### 1. Check Node Resource Usage
```bash
# Get overall node resource usage
kubectl top nodes

# Get detailed node information including capacity and allocatable resources
kubectl describe nodes

# Get node resource usage in JSON format for programmatic use
kubectl top nodes --output=json
```

### 2. Check Pod Resource Usage
```bash
# Get resource usage for all pods across all namespaces
kubectl top pods --all-namespaces

# Get resource usage for pods in a specific namespace
kubectl top pods -n <namespace>

# Get resource usage with container breakdown
kubectl top pods --containers=true
```

### 3. Check Resource Quotas and Limits
```bash
# Check resource quotas in all namespaces
kubectl get resourcequotas --all-namespaces

# Check limit ranges
kubectl get limitranges --all-namespaces

# Describe specific resource quota
kubectl describe resourcequota <quota-name> -n <namespace>
```

### 4. Check Cluster-wide Resource Allocation
```bash
# Get all pods with their resource requests and limits
kubectl get pods -o=custom-columns="NAME:.metadata.name,NAMESPACE:.metadata.namespace,CPU_REQUEST:.spec.containers[*].resources.requests.cpu,MEMORY_REQUEST:.spec.containers[*].resources.requests.memory,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEMORY_LIMIT:.spec.containers[*].resources.limits.memory" --all-namespaces

# Get node capacity and allocation summary
kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Advanced Monitoring with Metrics Server

### Install Metrics Server (if not already installed)
```bash
# For kind clusters
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For kind specifically, you might need to patch the metrics-server deployment
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

### Verify Metrics Server
```bash
# Check if metrics-server is running
kubectl get pods -n kube-system | grep metrics-server

# Test metrics collection
kubectl top nodes
kubectl top pods --all-namespaces
```

## Using kubectl for Resource Analysis

### 1. Find Resource-Heavy Pods
```bash
# Sort pods by CPU usage
kubectl top pods --all-namespaces --sort-by=cpu

# Sort pods by memory usage
kubectl top pods --all-namespaces --sort-by=memory
```

### 2. Check Events for Resource Issues
```bash
# Check recent events that might indicate resource issues
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Filter for resource-related events
kubectl get events --all-namespaces --field-selector reason=FailedScheduling
kubectl get events --all-namespaces --field-selector reason=Killing
```

### 3. Analyze Resource Pressure
```bash
# Check node conditions for resource pressure
kubectl get nodes -o custom-columns="NAME:.metadata.name,MEMORY_PRESSURE:.status.conditions[?(@.type=='MemoryPressure')].status,DISK_PRESSURE:.status.conditions[?(@.type=='DiskPressure')].status,PID_PRESSURE:.status.conditions[?(@.type=='PIDPressure')].status"
```

## Using Monitoring Tools

### 1. K9s (Terminal-based Dashboard)
```bash
# Install k9s
# On Ubuntu/Debian:
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar xz -C /tmp
sudo mv /tmp/k9s /usr/local/bin/

# Run k9s
k9s
```

### 2. Lens (GUI Dashboard)
- Download from https://k8slens.dev/
- Provides visual resource monitoring

### 3. Kubernetes Dashboard
```bash
# Install Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin user (for testing only)
kubectl create serviceaccount dashboard-admin-sa
kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=default:dashboard-admin-sa

# Get token
kubectl create token dashboard-admin-sa

# Port forward to access dashboard
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard-kong-proxy 8443:443
```

## Custom Resource Monitoring Scripts

### 1. Node Resource Summary Script
```bash
#!/bin/bash
# save as node-resource-summary.sh

echo "=== Node Resource Summary ==="
kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,CPU_CAPACITY:.status.capacity.cpu,MEMORY_CAPACITY:.status.capacity.memory,CPU_ALLOCATABLE:.status.allocatable.cpu,MEMORY_ALLOCATABLE:.status.allocatable.memory"

echo -e "\n=== Current Resource Usage ==="
kubectl top nodes

echo -e "\n=== Resource Allocation by Namespace ==="
kubectl get pods --all-namespaces -o=jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests.cpu}{"\t"}{.spec.containers[*].resources.requests.memory}{"\n"}{end}' | sort
```

### 2. Pod Resource Usage Script
```bash
#!/bin/bash
# save as pod-resource-usage.sh

echo "=== Top 10 CPU Consuming Pods ==="
kubectl top pods --all-namespaces --sort-by=cpu | head -11

echo -e "\n=== Top 10 Memory Consuming Pods ==="
kubectl top pods --all-namespaces --sort-by=memory | head -11

echo -e "\n=== Pods without Resource Limits ==="
kubectl get pods --all-namespaces -o=jsonpath='{range .items[*]}{@.metadata.namespace}{"\t"}{@.metadata.name}{"\t"}{@.spec.containers[*].resources.limits}{"\n"}{end}' | grep -v 'cpu\|memory' | head -10
```

## Prometheus + Grafana (Advanced)

### Quick Prometheus Setup with Helm
```bash
# Add prometheus-community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

# Port forward to access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Default credentials: admin/prom-operator
```

## Cloud Provider Specific Tools

### For GKE (Google Cloud)
```bash
# View cluster resource usage in GCP Console
gcloud container clusters describe ${CLUSTER_NAME} --zone ${GCP_ZONE}

# Get node pool information
gcloud container node-pools list --cluster ${CLUSTER_NAME} --zone ${GCP_ZONE}
```

### For Civo
```bash
# Check cluster status and size
civo kubernetes show ${CLUSTER_NAME} --region ${CIVO_REGION}

# List all nodes
civo kubernetes node ls ${CLUSTER_NAME} --region ${CIVO_REGION}
```

## Quick Health Check Script

### Cluster Health Overview
```bash
#!/bin/bash
# save as cluster-health-check.sh

echo "=== Cluster Info ==="
kubectl cluster-info

echo -e "\n=== Node Status ==="
kubectl get nodes

echo -e "\n=== System Pod Status ==="
kubectl get pods -n kube-system

echo -e "\n=== Resource Usage Summary ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available - install metrics-server first"

echo -e "\n=== Namespace Resource Quotas ==="
kubectl get resourcequotas --all-namespaces

echo -e "\n=== Recent Events ==="
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10
```