#!/bin/bash
##############################################################################
# VoLTE System Initialization Script
# Checks and fixes all prerequisites for the VoLTE testbed
# Run this after VM boot or if services are in bad state
##############################################################################

set -e

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BOLD}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

##############################################################################
# Check and fix network interfaces
##############################################################################
check_network_interfaces() {
    log_info "Checking network interfaces..."
    
    # Check if ogstun exists
    if ! ip link show ogstun &>/dev/null; then
        log_warn "ogstun interface missing - Open5GS services need to create it"
        return 1
    fi
    
    # Check Data APN (10.45.0.1/16)
    if ! ip addr show ogstun | grep -q "10.45.0.1/16"; then
        log_warn "Data APN (10.45.0.1/16) missing on ogstun"
        log_info "Adding Data APN interface..."
        sudo ip addr add 10.45.0.1/16 dev ogstun 2>/dev/null || true
        log_success "Data APN interface configured"
    else
        log_success "Data APN (10.45.0.1/16) present"
    fi
    
    # Check IMS APN (10.46.0.1/16)
    if ! ip addr show ogstun | grep -q "10.46.0.1/16"; then
        log_warn "IMS APN (10.46.0.1/16) missing on ogstun"
        log_info "Adding IMS APN interface..."
        sudo ip addr add 10.46.0.1/16 dev ogstun 2>/dev/null || true
        log_success "IMS APN interface configured"
    else
        log_success "IMS APN (10.46.0.1/16) present"
    fi
    
    # Ensure interface is up
    sudo ip link set ogstun up 2>/dev/null || true
}

##############################################################################
# Check and fix IP forwarding
##############################################################################
check_ip_forwarding() {
    log_info "Checking IP forwarding..."
    
    FORWARD_STATUS=$(sysctl -n net.ipv4.ip_forward)
    if [ "$FORWARD_STATUS" != "1" ]; then
        log_warn "IP forwarding is disabled"
        log_info "Enabling IP forwarding..."
        sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
        log_success "IP forwarding enabled"
    else
        log_success "IP forwarding is enabled"
    fi
}

##############################################################################
# Check and start Open5GS services
##############################################################################
check_open5gs_services() {
    log_info "Checking Open5GS services..."
    
    SERVICES=(
        "open5gs-mmed"
        "open5gs-sgwcd"
        "open5gs-sgwud"
        "open5gs-hssd"
        "open5gs-pcrfd"
        "open5gs-smfd"
        "open5gs-upfd"
    )
    
    local all_running=true
    for service in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log_warn "$service is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        log_info "Starting Open5GS services..."
        for service in "${SERVICES[@]}"; do
            if ! systemctl is-active --quiet "$service"; then
                sudo systemctl start "$service"
                sleep 1
                if systemctl is-active --quiet "$service"; then
                    log_success "$service started"
                else
                    log_error "$service failed to start"
                fi
            fi
        done
    else
        log_success "All Open5GS services running"
    fi
    
    # Wait for services to stabilize
    sleep 2
    
    # Re-check network interfaces after Open5GS starts (creates ogstun)
    check_network_interfaces
}

##############################################################################
# Check and start Kamailio
##############################################################################
check_kamailio() {
    log_info "Checking Kamailio..."
    
    if ! systemctl is-active --quiet kamailio; then
        log_warn "Kamailio is not running"
        log_info "Starting Kamailio..."
        sudo systemctl start kamailio
        sleep 2
        if systemctl is-active --quiet kamailio; then
            log_success "Kamailio started"
        else
            log_error "Kamailio failed to start - check config"
            sudo journalctl -u kamailio.service -n 20 --no-pager
            return 1
        fi
    else
        log_success "Kamailio is running"
    fi
    
    # Verify Kamailio is listening on correct interface
    if ss -tulnp 2>/dev/null | grep -q "10.46.0.1:5060"; then
        log_success "Kamailio listening on IMS interface (10.46.0.1:5060)"
    else
        log_warn "Kamailio may not be listening on correct interface"
    fi
}

##############################################################################
# Check DNS resolution
##############################################################################
check_dns() {
    log_info "Checking DNS resolution..."
    
    if ! grep -q "ims.localdomain" /etc/hosts; then
        log_warn "ims.localdomain not in /etc/hosts"
        log_info "Adding ims.localdomain to /etc/hosts..."
        echo "10.46.0.1 ims.localdomain" | sudo tee -a /etc/hosts >/dev/null
        log_success "DNS entry added"
    else
        log_success "ims.localdomain DNS entry exists"
    fi
    
    # Verify resolution
    if ping -c 1 -W 1 ims.localdomain &>/dev/null; then
        log_success "ims.localdomain resolves correctly"
    else
        log_warn "DNS resolution test failed (non-critical)"
    fi
}

##############################################################################
# Check MySQL/Kamailio database
##############################################################################
check_database() {
    log_info "Checking MySQL database..."
    
    if ! systemctl is-active --quiet mysql; then
        log_warn "MySQL is not running"
        log_info "Starting MySQL..."
        sudo systemctl start mysql
        sleep 2
    fi
    
    if systemctl is-active --quiet mysql; then
        log_success "MySQL is running"
        
        # Quick database check
        if sudo mysql -u faabam -pfaabam kamailio -e "SELECT COUNT(*) FROM subscriber;" &>/dev/null; then
            SUBSCRIBER_COUNT=$(sudo mysql -u faabam -pfaabam kamailio -e "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | tail -1)
            log_success "Kamailio database accessible ($SUBSCRIBER_COUNT subscribers)"
        else
            log_warn "Kamailio database check failed (non-critical)"
        fi
    else
        log_error "MySQL failed to start"
    fi
}

##############################################################################
# Check MongoDB/Open5GS database
##############################################################################
check_mongodb() {
    log_info "Checking MongoDB..."
    
    if ! systemctl is-active --quiet mongod; then
        log_warn "MongoDB is not running"
        log_info "Starting MongoDB..."
        sudo systemctl start mongod
        sleep 2
    fi
    
    if systemctl is-active --quiet mongod; then
        log_success "MongoDB is running"
    else
        log_error "MongoDB failed to start"
    fi
}

##############################################################################
# Kill any stray srsRAN processes
##############################################################################
cleanup_stray_processes() {
    log_info "Cleaning up stray srsRAN processes..."
    
    local killed=false
    if pgrep -f "srsenb" >/dev/null; then
        log_warn "Found running srsenb process"
        sudo pkill -9 -f "srsenb" 2>/dev/null || true
        killed=true
    fi
    
    if pgrep -f "srsue" >/dev/null; then
        log_warn "Found running srsue process"
        sudo pkill -9 -f "srsue" 2>/dev/null || true
        killed=true
    fi
    
    if [ "$killed" = true ]; then
        sleep 1
        log_success "Stray processes cleaned up"
    else
        log_success "No stray srsRAN processes found"
    fi
}

##############################################################################
# Verify routing
##############################################################################
check_routing() {
    log_info "Checking IP routing..."
    
    # Check if default route exists
    if ip route show | grep -q "^default"; then
        log_success "Default route configured"
    else
        log_warn "No default route (may affect connectivity)"
    fi
}

##############################################################################
# System readiness check
##############################################################################
verify_system_ready() {
    log_info "Performing final system readiness check..."
    
    local ready=true
    
    # Check critical services
    for service in "open5gs-mmed" "open5gs-upfd" "kamailio" "mysql" "mongod"; do
        if ! systemctl is-active --quiet "$service"; then
            log_error "$service is not running"
            ready=false
        fi
    done
    
    # Check critical interfaces
    if ! ip addr show ogstun | grep -q "10.45.0.1/16"; then
        log_error "Data APN not configured"
        ready=false
    fi
    
    if ! ip addr show ogstun | grep -q "10.46.0.1/16"; then
        log_error "IMS APN not configured"
        ready=false
    fi
    
    if [ "$ready" = true ]; then
        echo ""
        log_success "=========================================="
        log_success "  VoLTE System Ready for Demonstration"
        log_success "=========================================="
        echo ""
        log_info "You can now run: ./volte-demo.sh"
        return 0
    else
        echo ""
        log_error "=========================================="
        log_error "  System NOT Ready - Fix errors above"
        log_error "=========================================="
        return 1
    fi
}

##############################################################################
# Main execution
##############################################################################
main() {
    echo ""
    echo "========================================================================"
    echo "  VoLTE Testbed Initialization"
    echo "========================================================================"
    echo ""
    
    # Run all checks and fixes
    cleanup_stray_processes
    check_mongodb
    check_database
    check_open5gs_services
    check_network_interfaces
    check_ip_forwarding
    check_routing
    check_dns
    check_kamailio
    
    echo ""
    
    # Final verification
    verify_system_ready
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
