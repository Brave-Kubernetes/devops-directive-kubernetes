#!/bin/bash
# Continuous Resource Monitor for Kubernetes

# Configuration
REFRESH_INTERVAL=5  # seconds
LOG_FILE="cluster-resources.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE} Kubernetes Resource Monitor (Live)${NC}"
    echo -e "${BLUE} Press Ctrl+C to exit${NC}"
    echo -e "${BLUE} Refresh every ${REFRESH_INTERVAL}s${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e "$(date)"
}

# Function to check resource thresholds
check_thresholds() {
    local cpu_usage=$1
    local memory_usage=$2
    
    # Remove 'm' and '%' from values for comparison
    cpu_val=$(echo $cpu_usage | sed 's/[^0-9]//g')
    mem_val=$(echo $memory_usage | sed 's/[^0-9]//g')
    
    # Thresholds (adjust as needed)
    CPU_THRESHOLD=80  # 80% CPU
    MEM_THRESHOLD=85  # 85% Memory
    
    alerts=""
    
    if [ ! -z "$cpu_val" ] && [ "$cpu_val" -gt "$CPU_THRESHOLD" ]; then
        alerts="${alerts}HIGH CPU "
    fi
    
    if [ ! -z "$mem_val" ] && [ "$mem_val" -gt "$MEM_THRESHOLD" ]; then
        alerts="${alerts}HIGH MEMORY "
    fi
    
    echo $alerts
}

# Function to display node resources
show_node_resources() {
    echo -e "\n${YELLOW}=== Node Resource Usage ===${NC}"
    
    # Check if metrics server is available
    if kubectl top nodes &>/dev/null; then
        kubectl top nodes --no-headers | while read line; do
            node=$(echo $line | awk '{print $1}')
            cpu=$(echo $line | awk '{print $2}')
            cpu_pct=$(echo $line | awk '{print $3}')
            memory=$(echo $line | awk '{print $4}')
            memory_pct=$(echo $line | awk '{print $5}')
            
            alerts=$(check_thresholds $cpu_pct $memory_pct)
            
            if [ ! -z "$alerts" ]; then
                echo -e "${RED}⚠️  $node: CPU $cpu($cpu_pct) MEM $memory($memory_pct) - $alerts${NC}"
            else
                echo -e "${GREEN}✓${NC} $node: CPU $cpu($cpu_pct) MEM $memory($memory_pct)"
            fi
        done
    else
        echo -e "${RED}Metrics server not available${NC}"
    fi
}

# Function to show top resource consumers
show_top_consumers() {
    echo -e "\n${YELLOW}=== Top Resource Consumers ===${NC}"
    
    if kubectl top pods --all-namespaces &>/dev/null; then
        echo -e "\n${BLUE}Top 5 CPU:${NC}"
        kubectl top pods --all-namespaces --sort-by=cpu --no-headers | head -5 | awk '{printf "%-15s %-25s %s\n", $1, $2, $3}'
        
        echo -e "\n${BLUE}Top 5 Memory:${NC}"
        kubectl top pods --all-namespaces --sort-by=memory --no-headers | head -5 | awk '{printf "%-15s %-25s %s\n", $1, $2, $4}'
    fi
}

# Function to show cluster status
show_cluster_status() {
    echo -e "\n${YELLOW}=== Cluster Status ===${NC}"
    
    # Node status
    total_nodes=$(kubectl get nodes --no-headers | wc -l)
    ready_nodes=$(kubectl get nodes --no-headers | grep -w Ready | wc -l)
    
    if [ "$total_nodes" -eq "$ready_nodes" ]; then
        echo -e "${GREEN}✓${NC} Nodes: $ready_nodes/$total_nodes Ready"
    else
        echo -e "${RED}✗${NC} Nodes: $ready_nodes/$total_nodes Ready"
    fi
    
    # Pod status summary
    total_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -w Running | wc -l)
    echo -e "${GREEN}✓${NC} Pods: $running_pods/$total_pods Running"
    
    # System pod status
    system_pods_not_running=$(kubectl get pods -n kube-system --no-headers | grep -v Running | wc -l)
    if [ "$system_pods_not_running" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All system pods running"
    else
        echo -e "${RED}✗${NC} $system_pods_not_running system pods not running"
    fi
}

# Function to log critical events
log_events() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check for recent critical events
    critical_events=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | tail -5)
    
    if [ ! -z "$critical_events" ]; then
        echo "[$timestamp] WARNING EVENTS DETECTED:" >> "$LOG_FILE"
        echo "$critical_events" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
}

# Trap Ctrl+C
trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; exit 0' INT

# Main monitoring loop
main() {
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl not found${NC}"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}Error: Cannot connect to cluster${NC}"
        exit 1
    fi
    
    while true; do
        show_header
        show_cluster_status
        show_node_resources
        show_top_consumers
        log_events
        
        echo -e "\n${BLUE}Next refresh in ${REFRESH_INTERVAL}s...${NC}"
        sleep $REFRESH_INTERVAL
    done
}

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -i, --interval SECONDS    Set refresh interval (default: 5)"
    echo "  -l, --log-file FILE      Set log file (default: cluster-resources.log)"
    echo "  -h, --help               Show this help"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Start monitoring
main