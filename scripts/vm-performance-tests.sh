#!/bin/bash
# VM Performance Diagnostic Tests Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Thresholds for warnings
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
SWAP_THRESHOLD=50
DISK_THRESHOLD=80
LOAD_THRESHOLD=2.0

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE} VM Performance Diagnostic Tests${NC}"
echo -e "${BLUE} $(date)${NC}"
echo -e "${BLUE}=============================================${NC}"

# Function to print section header
print_section() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# Function to check thresholds and warn
check_threshold() {
    local value=$1
    local threshold=$2
    local unit=$3
    local description=$4
    
    # Remove non-numeric characters for comparison
    numeric_value=$(echo "$value" | sed 's/[^0-9.]//g')
    
    if (( $(echo "$numeric_value > $threshold" | bc -l) 2>/dev/null )); then
        echo -e "${RED}⚠️  WARNING: $description is HIGH ($value$unit > $threshold$unit threshold)${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $description is OK ($value$unit)${NC}"
        return 0
    fi
}

# Function to test system resources
test_system_resources() {
    print_section "System Resource Overview"
    
    echo -e "${YELLOW}Memory Usage:${NC}"
    memory_info=$(free -m)
    echo "$memory_info"
    
    # Parse memory info
    total_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $2}')
    used_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $3}')
    available_mem=$(echo "$memory_info" | awk '/^Mem:/ {print $7}')
    
    # Calculate memory percentage
    mem_percentage=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc)
    
    echo -e "\n${YELLOW}Memory Analysis:${NC}"
    echo "Total: ${total_mem}MB"
    echo "Used: ${used_mem}MB (${mem_percentage}%)"
    echo "Available: ${available_mem}MB"
    
    check_threshold "$mem_percentage" "$MEMORY_THRESHOLD" "%" "Memory usage"
    
    echo -e "\n${YELLOW}Swap Usage:${NC}"
    swap_info=$(free -m | grep Swap)
    echo "$swap_info"
    
    total_swap=$(echo "$swap_info" | awk '{print $2}')
    used_swap=$(echo "$swap_info" | awk '{print $3}')
    
    if [ "$total_swap" -gt 0 ]; then
        swap_percentage=$(echo "scale=1; $used_swap * 100 / $total_swap" | bc)
        echo "Swap usage: ${used_swap}MB / ${total_swap}MB (${swap_percentage}%)"
        check_threshold "$swap_percentage" "$SWAP_THRESHOLD" "%" "Swap usage"
    else
        echo "No swap configured"
    fi
}

# Function to test CPU performance
test_cpu_performance() {
    print_section "CPU Performance Analysis"
    
    echo -e "${YELLOW}CPU Information:${NC}"
    lscpu | grep -E "(Model name|CPU\(s\)|Thread|Core|Socket)"
    
    echo -e "\n${YELLOW}System Load Average:${NC}"
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    echo "Load Average: $load_avg"
    
    # Get 1-minute load average
    load_1min=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    cpu_cores=$(nproc)
    load_per_core=$(echo "scale=2; $load_1min / $cpu_cores" | bc)
    
    echo "CPU Cores: $cpu_cores"
    echo "Load per core: $load_per_core"
    
    if (( $(echo "$load_per_core > $LOAD_THRESHOLD" | bc -l) )); then
        echo -e "${RED}⚠️  WARNING: High CPU load ($load_per_core > $LOAD_THRESHOLD per core)${NC}"
    else
        echo -e "${GREEN}✓ CPU load is normal${NC}"
    fi
    
    echo -e "\n${YELLOW}Current CPU Usage (5 second sample):${NC}"
    top -bn2 -d1 | grep "Cpu(s)" | tail -1
    
    echo -e "\n${YELLOW}CPU Usage by Process Type:${NC}"
    echo "User processes: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')"
    echo "System processes: $(top -bn1 | grep "Cpu(s)" | awk '{print $4}' | sed 's/%sy,//')"
    echo "I/O Wait: $(top -bn1 | grep "Cpu(s)" | awk '{print $10}' | sed 's/%wa,//')"
    
    # Check I/O wait
    io_wait=$(top -bn1 | grep "Cpu(s)" | awk '{print $10}' | sed 's/%wa,//' | sed 's/%//')
    if (( $(echo "$io_wait > 20" | bc -l) 2>/dev/null )); then
        echo -e "${RED}⚠️  WARNING: High I/O wait (${io_wait}%) - possible disk bottleneck${NC}"
    fi
}

# Function to test disk performance
test_disk_performance() {
    print_section "Disk Performance Analysis"
    
    echo -e "${YELLOW}Disk Space Usage:${NC}"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom'
    
    echo -e "\n${YELLOW}Disk Usage Analysis:${NC}"
    # Check each mounted filesystem
    while read line; do
        usage=$(echo $line | awk '{print $5}' | sed 's/%//')
        mount=$(echo $line | awk '{print $6}')
        
        if [ "$usage" -gt "$DISK_THRESHOLD" ] 2>/dev/null; then
            echo -e "${RED}⚠️  WARNING: $mount is ${usage}% full (> ${DISK_THRESHOLD}% threshold)${NC}"
        else
            echo -e "${GREEN}✓ $mount: ${usage}% used${NC}"
        fi
    done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom')
    
    echo -e "\n${YELLOW}Largest Directories in Home:${NC}"
    du -h --max-depth=2 ~/ 2>/dev/null | sort -hr | head -10
    
    echo -e "\n${YELLOW}I/O Statistics (5 second sample):${NC}"
    if command -v iostat &> /dev/null; then
        iostat -x 1 2 | tail -n +4
    else
        echo "iostat not available - install with: sudo apt install sysstat"
    fi
}

# Function to test network performance
test_network_performance() {
    print_section "Network Performance Analysis"
    
    echo -e "${YELLOW}Network Interfaces:${NC}"
    ip addr show | grep -E "(^[0-9]|inet )"
    
    echo -e "\n${YELLOW}Network Connectivity Test:${NC}"
    echo "Testing DNS resolution..."
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution working${NC}"
    else
        echo -e "${RED}✗ DNS resolution failed${NC}"
    fi
    
    echo "Testing internet connectivity..."
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Internet connectivity working${NC}"
    else
        echo -e "${RED}✗ Internet connectivity failed${NC}"
    fi
    
    echo -e "\n${YELLOW}Network Statistics:${NC}"
    cat /proc/net/dev | grep -E "(eth|wlan|ens)" | head -5
}

# Function to test process analysis
test_process_analysis() {
    print_section "Process Analysis"
    
    echo -e "${YELLOW}Top 10 Memory Consumers:${NC}"
    printf "%-10s %6s %8s %s\n" "USER" "MEM%" "RSS(MB)" "COMMAND"
    ps aux --sort=-%mem | head -11 | tail -10 | awk '{printf "%-10s %6s %8.1f %s\n", $1, $4"%", $6/1024, $11}'
    
    echo -e "\n${YELLOW}Top 10 CPU Consumers:${NC}"
    printf "%-10s %6s %6s %s\n" "USER" "CPU%" "MEM%" "COMMAND"
    ps aux --sort=-%cpu | head -11 | tail -10 | awk '{printf "%-10s %6s %6s %s\n", $1, $3"%", $4"%", $11}'
    
    echo -e "\n${YELLOW}Process Count by User:${NC}"
    ps aux | awk '{print $1}' | sort | uniq -c | sort -nr
    
    echo -e "\n${YELLOW}System Process Summary:${NC}"
    echo "Total processes: $(ps aux | wc -l)"
    echo "Running processes: $(ps aux | grep -c " R ")"
    echo "Sleeping processes: $(ps aux | grep -c " S ")"
    echo "Zombie processes: $(ps aux | grep -c " Z ")"
}

# Function to test Docker and containers
test_docker_containers() {
    print_section "Docker and Container Analysis"
    
    if command -v docker &> /dev/null; then
        if docker info &>/dev/null; then
            echo -e "${YELLOW}Docker System Information:${NC}"
            docker system df
            
            echo -e "\n${YELLOW}Running Containers:${NC}"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}"
            
            echo -e "\n${YELLOW}Docker Resource Usage:${NC}"
            docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || echo "No running containers"
        else
            echo "Docker daemon not running"
        fi
    else
        echo "Docker not installed"
    fi
}

# Function to test Kubernetes clusters
test_kubernetes_clusters() {
    print_section "Kubernetes Cluster Analysis"
    
    echo -e "${YELLOW}Kubernetes Context:${NC}"
    if command -v kubectl &> /dev/null; then
        current_context=$(kubectl config current-context 2>/dev/null || echo "No context set")
        echo "Current context: $current_context"
        
        if kubectl cluster-info &>/dev/null; then
            echo -e "\n${YELLOW}Cluster Information:${NC}"
            kubectl cluster-info
            
            echo -e "\n${YELLOW}Node Status:${NC}"
            kubectl get nodes -o wide
            
            echo -e "\n${YELLOW}Resource Usage (if metrics-server available):${NC}"
            if kubectl top nodes &>/dev/null; then
                kubectl top nodes
                echo -e "\n${YELLOW}Top Resource Consuming Pods:${NC}"
                kubectl top pods --all-namespaces --sort-by=memory | head -6
            else
                echo "Metrics server not available"
            fi
            
            echo -e "\n${YELLOW}System Pods Status:${NC}"
            kubectl get pods -n kube-system --no-headers | awk '{print $1, $3}' | while read pod status; do
                if [[ "$status" == "Running" ]]; then
                    echo -e "${GREEN}✓${NC} $pod: $status"
                else
                    echo -e "${RED}✗${NC} $pod: $status"
                fi
            done
        else
            echo "Cannot connect to Kubernetes cluster"
        fi
    else
        echo "kubectl not installed"
    fi
    
    # Check minikube
    if command -v minikube &> /dev/null; then
        echo -e "\n${YELLOW}Minikube Status:${NC}"
        minikube status 2>/dev/null || echo "Minikube not running"
    fi
    
    # Check kind
    if command -v kind &> /dev/null; then
        echo -e "\n${YELLOW}Kind Clusters:${NC}"
        kind_clusters=$(kind get clusters 2>/dev/null || echo "No kind clusters")
        echo "$kind_clusters"
    fi
}

# Function to test system services
test_system_services() {
    print_section "System Services Analysis"
    
    echo -e "${YELLOW}Heavy Services Status:${NC}"
    services=("jenkins" "docker" "snapd" "mysql" "postgresql" "apache2" "nginx")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            status="RUNNING"
            color="${YELLOW}"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            status="STOPPED (enabled)"
            color="${GREEN}"
        else
            status="NOT INSTALLED"
            color="${NC}"
        fi
        echo -e "${color}$service: $status${NC}"
    done
    
    echo -e "\n${YELLOW}Failed Services:${NC}"
    failed_services=$(systemctl --failed --no-pager -q)
    if [ -z "$failed_services" ]; then
        echo -e "${GREEN}✓ No failed services${NC}"
    else
        echo -e "${RED}Failed services found:${NC}"
        systemctl --failed --no-pager
    fi
}

# Function to generate performance score
generate_performance_score() {
    print_section "Performance Score Summary"
    
    score=100
    issues=()
    
    # Memory check
    mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 85 ]; then
        score=$((score - 20))
        issues+=("High memory usage (${mem_usage}%)")
    elif [ "$mem_usage" -gt 70 ]; then
        score=$((score - 10))
        issues+=("Moderate memory usage (${mem_usage}%)")
    fi
    
    # Swap check
    swap_usage=$(free | awk '/^Swap:/ {if($2>0) printf "%.0f", $3*100/$2; else print "0"}')
    if [ "$swap_usage" -gt 50 ]; then
        score=$((score - 25))
        issues+=("High swap usage (${swap_usage}%)")
    elif [ "$swap_usage" -gt 20 ]; then
        score=$((score - 10))
        issues+=("Moderate swap usage (${swap_usage}%)")
    fi
    
    # Load average check
    load_1min=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    cpu_cores=$(nproc)
    if (( $(echo "$load_1min > $cpu_cores * 2" | bc -l) )); then
        score=$((score - 20))
        issues+=("High CPU load ($load_1min on $cpu_cores cores)")
    fi
    
    # Disk usage check
    max_disk_usage=$(df | awk 'NR>1 {gsub("%","",$5); if($5>max) max=$5} END {print max}')
    if [ "$max_disk_usage" -gt 90 ]; then
        score=$((score - 15))
        issues+=("Very high disk usage (${max_disk_usage}%)")
    elif [ "$max_disk_usage" -gt 80 ]; then
        score=$((score - 5))
        issues+=("High disk usage (${max_disk_usage}%)")
    fi
    
    # Performance rating
    if [ "$score" -ge 80 ]; then
        rating="${GREEN}EXCELLENT${NC}"
    elif [ "$score" -ge 60 ]; then
        rating="${YELLOW}GOOD${NC}"
    elif [ "$score" -ge 40 ]; then
        rating="${YELLOW}FAIR${NC}"
    else
        rating="${RED}POOR${NC}"
    fi
    
    echo -e "${BLUE}Performance Score: $score/100 - $rating${NC}"
    
    if [ ${#issues[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Issues Found:${NC}"
        for issue in "${issues[@]}"; do
            echo -e "${RED}• $issue${NC}"
        done
    else
        echo -e "\n${GREEN}✓ No major performance issues detected${NC}"
    fi
}

# Function to generate recommendations
generate_recommendations() {
    print_section "Performance Recommendations"
    
    mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3*100/$2}')
    swap_usage=$(free | awk '/^Swap:/ {if($2>0) printf "%.0f", $3*100/$2; else print "0"}')
    
    recommendations=()
    
    if [ "$mem_usage" -gt 80 ]; then
        recommendations+=("🧹 Clear system cache: sync && echo 3 | sudo tee /proc/sys/vm/drop_caches")
        recommendations+=("🛑 Close unnecessary applications (browser tabs, VS Code windows)")
        recommendations+=("📦 Consider stopping unused services (Jenkins, Docker)")
    fi
    
    if [ "$swap_usage" -gt 30 ]; then
        recommendations+=("💾 Reduce swap usage: echo 10 | sudo tee /proc/sys/vm/swappiness")
        recommendations+=("🚀 Add more RAM or reduce running applications")
    fi
    
    if docker ps &>/dev/null && [ "$(docker ps -q | wc -l)" -gt 3 ]; then
        recommendations+=("🐳 Clean Docker: docker system prune -f")
        recommendations+=("⚙️  Stop unused containers")
    fi
    
    if pgrep -f "kube-apiserver" >/dev/null; then
        recommendations+=("☸️  Consider using only one Kubernetes cluster at a time")
        recommendations+=("⏸️  Stop minikube when not needed: minikube stop")
    fi
    
    if [ ${#recommendations[@]} -gt 0 ]; then
        for rec in "${recommendations[@]}"; do
            echo -e "$rec"
        done
    else
        echo -e "${GREEN}✓ System is performing well - no immediate recommendations${NC}"
    fi
    
    echo -e "\n${BLUE}Quick Commands:${NC}"
    echo "• Run optimization script: ./scripts/optimize-vm-performance.sh"
    echo "• Monitor resources: watch -n 2 'free -h && echo && top -bn1 | head -5'"
    echo "• Check processes: ps aux --sort=-%mem | head -10"
}

# Main execution
main() {
    # Check if bc is available for calculations
    if ! command -v bc &> /dev/null; then
        echo -e "${YELLOW}Installing bc for calculations...${NC}"
        sudo apt update && sudo apt install -y bc &>/dev/null || echo "Could not install bc"
    fi
    
    # Run all tests
    test_system_resources
    test_cpu_performance  
    test_disk_performance
    test_network_performance
    test_process_analysis
    test_docker_containers
    test_kubernetes_clusters
    test_system_services
    
    # Generate summary
    generate_performance_score
    generate_recommendations
    
    echo -e "\n${BLUE}=============================================${NC}"
    echo -e "${BLUE} Diagnostic Complete - $(date)${NC}"
    echo -e "${BLUE}=============================================${NC}"
}

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --quick       Run quick tests only (system resources)"
    echo "  --full        Run all diagnostic tests (default)"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Run full diagnostic"
    echo "  $0 --quick       # Quick system check"
}

# Parse command line arguments
case "${1:-}" in
    --quick)
        test_system_resources
        test_process_analysis
        generate_performance_score
        ;;
    --full|"")
        main
        ;;
    --help|-h)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac