#!/bin/bash
# VM Performance Optimization Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== VM Performance Optimization Script ===${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show memory usage
show_memory() {
    echo -e "\n${BLUE}Current Memory Usage:${NC}"
    free -h
    echo -e "\n${BLUE}Swap Usage Details:${NC}"
    swapon --show
}

# Function to clean system cache
clean_cache() {
    echo -e "\n${YELLOW}🧹 Cleaning System Cache...${NC}"
    
    # Clear page cache, dentries, and inodes
    echo "Clearing filesystem cache..."
    sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    
    # Clean package cache
    if command_exists apt; then
        echo "Cleaning APT cache..."
        sudo apt clean
        sudo apt autoclean
        sudo apt autoremove -y
    fi
    
    # Clean snap cache
    if command_exists snap; then
        echo "Cleaning snap cache..."
        sudo snap refresh --list 2>/dev/null || true
    fi
    
    # Clean journal logs
    echo "Cleaning journal logs..."
    sudo journalctl --vacuum-time=3d
    
    # Clean temporary files
    echo "Cleaning temporary files..."
    sudo find /tmp -type f -atime +3 -delete 2>/dev/null || true
    
    echo -e "${GREEN}✓ Cache cleanup complete${NC}"
}

# Function to optimize swap usage
optimize_swap() {
    echo -e "\n${YELLOW}💾 Optimizing Swap Usage...${NC}"
    
    # Reduce swappiness (how aggressively system uses swap)
    current_swappiness=$(cat /proc/sys/vm/swappiness)
    echo "Current swappiness: $current_swappiness"
    
    if [ "$current_swappiness" -gt 10 ]; then
        echo "Setting swappiness to 10 (less aggressive swapping)..."
        echo 10 | sudo tee /proc/sys/vm/swappiness > /dev/null
        
        # Make it persistent
        echo "vm.swappiness = 10" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi
    
    echo -e "${GREEN}✓ Swap optimization complete${NC}"
}

# Function to stop unnecessary services
stop_heavy_services() {
    echo -e "\n${YELLOW}🛑 Managing Heavy Services...${NC}"
    
    # List of services that might be running and consuming resources
    services_to_check=("jenkins" "docker" "snapd")
    
    for service in "${services_to_check[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "Found running service: $service"
            read -p "Stop $service? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo systemctl stop "$service"
                echo -e "${GREEN}✓ Stopped $service${NC}"
            fi
        fi
    done
}

# Function to optimize Kubernetes clusters
optimize_kubernetes() {
    echo -e "\n${YELLOW}⚙️  Kubernetes Optimization Options...${NC}"
    
    # Check running clusters
    echo "Detected Kubernetes clusters:"
    
    # Check minikube
    if command_exists minikube && minikube status &>/dev/null; then
        echo "- Minikube (running)"
        read -p "Stop minikube to free ~500MB RAM? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            minikube stop
            echo -e "${GREEN}✓ Minikube stopped${NC}"
        fi
    fi
    
    # Check kind clusters
    if command_exists kind; then
        clusters=$(kind get clusters 2>/dev/null || true)
        if [ ! -z "$clusters" ]; then
            echo "- Kind clusters: $clusters"
            read -p "Delete kind clusters to free memory? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                kind delete cluster
                echo -e "${GREEN}✓ Kind clusters deleted${NC}"
            fi
        fi
    fi
}

# Function to clean Docker
clean_docker() {
    echo -e "\n${YELLOW}🐳 Docker Cleanup...${NC}"
    
    if command_exists docker && docker info &>/dev/null; then
        echo "Docker system usage:"
        docker system df
        
        read -p "Clean unused Docker data? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker system prune -f
            docker image prune -f
            echo -e "${GREEN}✓ Docker cleanup complete${NC}"
        fi
    fi
}

# Function to show process recommendations
show_process_recommendations() {
    echo -e "\n${YELLOW}📊 High Memory Process Analysis...${NC}"
    
    echo "Top 5 memory consumers:"
    ps aux --sort=-%mem | head -6 | awk '{printf "%-10s %6s %6s %s\n", $1, $4"%", $6/1024"MB", $11}'
    
    echo -e "\n${BLUE}Recommendations:${NC}"
    echo "1. Close unnecessary browser tabs"
    echo "2. Close unused VS Code windows/extensions"
    echo "3. Consider stopping Jenkins if not actively used"
    echo "4. Use only one Kubernetes cluster at a time"
}

# Function to create monitoring alias
create_monitoring_aliases() {
    echo -e "\n${YELLOW}📈 Creating Performance Monitoring Aliases...${NC}"
    
    cat >> ~/.bashrc << 'EOF'

# Performance monitoring aliases
alias meminfo='free -h && echo "=== Top Memory Users ===" && ps aux --sort=-%mem | head -6'
alias diskinfo='df -h && echo "=== Largest Directories ===" && du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10'
alias sysload='uptime && echo "=== CPU Usage ===" && top -bn1 | head -5'
alias cleanmem='sync && echo 3 | sudo tee /proc/sys/vm/drop_caches'
EOF

    echo -e "${GREEN}✓ Aliases added to ~/.bashrc${NC}"
    echo "New aliases available after running: source ~/.bashrc"
    echo "- meminfo: Show memory usage and top consumers"
    echo "- diskinfo: Show disk usage and largest directories" 
    echo "- sysload: Show system load and CPU usage"
    echo "- cleanmem: Clear filesystem cache"
}

# Main menu
main_menu() {
    echo -e "\n${BLUE}=== Performance Optimization Menu ===${NC}"
    echo "1. Clean system cache and temporary files"
    echo "2. Optimize swap usage"
    echo "3. Manage heavy services (Jenkins, Docker, etc.)"
    echo "4. Optimize Kubernetes clusters"
    echo "5. Clean Docker unused data"
    echo "6. Show memory analysis and recommendations"
    echo "7. Create monitoring aliases"
    echo "8. Run all optimizations (recommended)"
    echo "9. Show current system status"
    echo "0. Exit"
    echo
    
    read -p "Select option (0-9): " choice
    
    case $choice in
        1) clean_cache ;;
        2) optimize_swap ;;
        3) stop_heavy_services ;;
        4) optimize_kubernetes ;;
        5) clean_docker ;;
        6) show_process_recommendations ;;
        7) create_monitoring_aliases ;;
        8) 
            clean_cache
            optimize_swap
            clean_docker
            show_process_recommendations
            ;;
        9) show_memory ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option"; main_menu ;;
    esac
}

# Initial system status
echo -e "${BLUE}Initial System Status:${NC}"
show_memory

# Show main menu
main_menu

# Final status
echo -e "\n${BLUE}Final System Status:${NC}"
show_memory

echo -e "\n${GREEN}=== Optimization Complete! ===${NC}"
echo "Restart applications as needed. Consider restarting the VM for full effect."