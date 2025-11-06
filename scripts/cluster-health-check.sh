#!/bin/bash
# Cluster Resource Health Check Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kubernetes Cluster Resource Health Check ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure you have a valid kubeconfig and cluster is running"
    exit 1
fi

echo -e "${GREEN}✓ Connected to cluster${NC}"

# Get cluster info
echo -e "\n${BLUE}=== Cluster Information ===${NC}"
kubectl cluster-info

# Node status
echo -e "\n${BLUE}=== Node Status ===${NC}"
kubectl get nodes -o wide

# Check if metrics server is available
echo -e "\n${BLUE}=== Resource Usage (requires metrics-server) ===${NC}"
if kubectl top nodes &> /dev/null; then
    echo -e "${GREEN}✓ Metrics server is available${NC}"
    
    echo -e "\n${YELLOW}Node Resource Usage:${NC}"
    kubectl top nodes
    
    echo -e "\n${YELLOW}Top 10 Pods by CPU:${NC}"
    kubectl top pods --all-namespaces --sort-by=cpu | head -11
    
    echo -e "\n${YELLOW}Top 10 Pods by Memory:${NC}"
    kubectl top pods --all-namespaces --sort-by=memory | head -11
else
    echo -e "${RED}✗ Metrics server not available${NC}"
    echo "Install metrics server to get resource usage data:"
    echo "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# Node resource allocation
echo -e "\n${BLUE}=== Node Resource Allocation ===${NC}"
kubectl describe nodes | grep -A 5 "Allocated resources" | grep -E "(Allocated resources|cpu|memory|ephemeral-storage)"

# System pods status
echo -e "\n${BLUE}=== System Pods Status ===${NC}"
kubectl get pods -n kube-system --no-headers | awk '{print $1, $3}' | while read pod status; do
    if [[ "$status" == "Running" ]]; then
        echo -e "${GREEN}✓${NC} $pod: $status"
    else
        echo -e "${RED}✗${NC} $pod: $status"
    fi
done

# Resource quotas
echo -e "\n${BLUE}=== Resource Quotas ===${NC}"
quotas=$(kubectl get resourcequotas --all-namespaces --no-headers 2>/dev/null | wc -l)
if [ "$quotas" -gt 0 ]; then
    kubectl get resourcequotas --all-namespaces
else
    echo "No resource quotas configured"
fi

# Recent events
echo -e "\n${BLUE}=== Recent Events (Last 10) ===${NC}"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10

# Check for resource pressure
echo -e "\n${BLUE}=== Node Conditions (Resource Pressure Check) ===${NC}"
kubectl get nodes -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,MEMORY_PRESSURE:.status.conditions[?(@.type=='MemoryPressure')].status,DISK_PRESSURE:.status.conditions[?(@.type=='DiskPressure')].status,PID_PRESSURE:.status.conditions[?(@.type=='PIDPressure')].status"

echo -e "\n${GREEN}=== Health Check Complete ===${NC}"