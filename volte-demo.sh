#!/bin/bash
################################################################################
# VoLTE IMS Testbed - Automated Demonstration Script
# 
# This script orchestrates a complete VoLTE demonstration including:
# - Service health checks and initialization
# - RAN deployment (srsRAN eNB + UE)
# - SIP registration and call setup testing
# - Performance measurement and packet capture
#
# Author: VoLTE IMS Testbed Project
# Date: November 29, 2025
################################################################################

set -e  # Exit on error
trap cleanup EXIT INT TERM

# Configuration
DEMO_DIR="/home/open5gs/demo"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${DEMO_DIR}/${TIMESTAMP}"
ENB_CONFIG="/home/open5gs/srsran-config/enb.conf"
UE_CONFIG="/home/open5gs/srsran-config/ue.conf"
TEST_SCRIPT="/home/open5gs/sip_register_test.py"
MAX_ATTACH_RETRIES=2
ATTACH_TIMEOUT=30

# Process tracking
ENB_PID=""
UE_PID=""
TCPDUMP_PID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_separator() {
    echo "=============================================================================="
}

cleanup() {
    log_info "Cleaning up previous processes..."
    
    # Stop packet capture
    if [ ! -z "$TCPDUMP_PID" ]; then
        sudo kill $TCPDUMP_PID 2>/dev/null || true
    fi
    
    # Stop UE
    if [ ! -z "$UE_PID" ]; then
        sudo kill $UE_PID 2>/dev/null || true
    fi
    
    # Stop eNB
    if [ ! -z "$ENB_PID" ]; then
        sudo kill $ENB_PID 2>/dev/null || true
    fi
    
    # Additional cleanup
    sudo pkill -f srsue 2>/dev/null || true
    sudo pkill -f srsenb 2>/dev/null || true
    
    log_info "Cleanup complete"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed or not in PATH"
        exit 1
    fi
}

################################################################################
# Service Checks
################################################################################

check_prerequisites() {
    print_separator
    log_info "Checking system prerequisites..."
    
    # Check required commands
    check_command srsenb
    check_command srsue
    check_command python3
    check_command tcpdump
    
    # Check test script exists
    if [ ! -f "$TEST_SCRIPT" ]; then
        log_error "Test script not found: $TEST_SCRIPT"
        exit 1
    fi
    
    # Check config files
    if [ ! -f "$ENB_CONFIG" ]; then
        log_error "eNB config not found: $ENB_CONFIG"
        exit 1
    fi
    
    if [ ! -f "$UE_CONFIG" ]; then
        log_error "UE config not found: $UE_CONFIG"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

check_open5gs_services() {
    print_separator
    log_info "Checking Open5GS core network services..."
    
    local services=("open5gs-mmed" "open5gs-sgwcd" "open5gs-sgwud" "open5gs-hssd" "open5gs-pcrfd" "open5gs-smfd" "open5gs-upfd")
    local all_running=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo "  ✓ $service: running"
        else
            echo "  ✗ $service: not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        log_error "Some Open5GS services are not running. Please start them first."
        exit 1
    fi
    
    log_success "All Open5GS services operational"
}

check_kamailio() {
    print_separator
    log_info "Checking Kamailio IMS core..."
    
    if systemctl is-active --quiet kamailio; then
        log_success "Kamailio is running"
    else
        log_error "Kamailio is not running. Starting it now..."
        sudo systemctl start kamailio
        sleep 2
        if systemctl is-active --quiet kamailio; then
            log_success "Kamailio started successfully"
        else
            log_error "Failed to start Kamailio"
            exit 1
        fi
    fi
    
    # Check if Kamailio is listening on IMS interface
    if sudo netstat -tulpn | grep -q ":5060.*kamailio"; then
        log_success "Kamailio listening on port 5060"
    else
        log_warn "Kamailio may not be listening on port 5060"
    fi
}

check_network_interfaces() {
    print_separator
    log_info "Checking network interfaces..."
    
    # Check ogstun interface
    if ip addr show ogstun &>/dev/null; then
        log_success "ogstun interface exists"
        
        # Check IMS APN address
        if ip addr show ogstun | grep -q "10.46.0.1"; then
            log_success "IMS APN address (10.46.0.1) configured"
        else
            log_warn "IMS APN address not found, adding it..."
            sudo ip addr add 10.46.0.1/16 dev ogstun 2>/dev/null || true
        fi
        
        # Check Data APN address
        if ip addr show ogstun | grep -q "10.45.0.1"; then
            log_success "Data APN address (10.45.0.1) configured"
        else
            log_warn "Data APN address not found, adding it..."
            sudo ip addr add 10.45.0.1/16 dev ogstun 2>/dev/null || true
        fi
    else
        log_error "ogstun interface not found"
        exit 1
    fi
}

################################################################################
# RAN Deployment
################################################################################

start_enb() {
    print_separator
    log_info "Starting srsRAN eNodeB..."
    
    sudo srsenb $ENB_CONFIG < /dev/null > ${RUN_DIR}/enb_output.log 2>&1 &
    ENB_PID=$!
    
    log_info "eNB started with PID: $ENB_PID"
    log_info "Waiting for eNB initialization (5 seconds)..."
    sleep 5
    
    # Check if process is still running
    if ps -p $ENB_PID > /dev/null; then
        log_success "eNB is running"
    else
        log_error "eNB failed to start. Check ${RUN_DIR}/enb_output.log"
        exit 1
    fi
}

start_ue() {
    print_separator
    log_info "Starting srsRAN UE..."
    
    sudo srsue $UE_CONFIG < /dev/null > ${RUN_DIR}/ue_output.log 2>&1 &
    UE_PID=$!
    
    log_info "UE started with PID: $UE_PID"
    log_info "Waiting for UE initialization (3 seconds)..."
    sleep 3
    
    # Check if process is still running
    if ps -p $UE_PID > /dev/null; then
        log_success "UE process is running"
    else
        log_error "UE failed to start. Check ${RUN_DIR}/ue_output.log"
        exit 1
    fi
}

check_ue_attachment() {
    local retry_count=0
    local attached=false
    
    print_separator
    log_info "Checking UE network attachment..."
    
    while [ $retry_count -le $MAX_ATTACH_RETRIES ] && [ "$attached" = false ]; do
        if [ $retry_count -gt 0 ]; then
            log_warn "Attachment attempt $retry_count of $MAX_ATTACH_RETRIES failed"
            log_info "Restarting RAN components..."
            
            # Kill existing processes
            sudo kill $UE_PID 2>/dev/null || true
            sudo kill $ENB_PID 2>/dev/null || true
            sleep 2
            sudo pkill -f srsue 2>/dev/null || true
            sudo pkill -f srsenb 2>/dev/null || true
            sleep 1
            
            # Restart
            start_enb
            start_ue
        fi
        
        log_info "Polling for network attachment (timeout: ${ATTACH_TIMEOUT}s)..."
        
        local elapsed=0
        while [ $elapsed -lt $ATTACH_TIMEOUT ]; do
            # Check if tun_srsue interface exists with IP address
            if ip addr show tun_srsue 2>/dev/null | grep -q "inet 10.45"; then
                local ue_ip=$(ip addr show tun_srsue | grep "inet 10.45" | awk '{print $2}' | cut -d'/' -f1)
                log_success "UE attached successfully with IP: $ue_ip"
                attached=true
                break
            fi
            
            sleep 2
            elapsed=$((elapsed + 2))
            echo -n "."
        done
        
        echo ""
        
        if [ "$attached" = false ]; then
            retry_count=$((retry_count + 1))
        fi
    done
    
    if [ "$attached" = false ]; then
        log_error "UE failed to attach after $MAX_ATTACH_RETRIES retries"
        log_error "Check logs in ${RUN_DIR}/"
        exit 1
    fi
    
    # Verify connectivity to P-CSCF
    log_info "Testing connectivity to P-CSCF (10.46.0.1)..."
    if ping -c 2 -W 2 10.46.0.1 &>/dev/null; then
        log_success "P-CSCF is reachable from UE"
    else
        log_warn "P-CSCF ping failed, but proceeding with tests"
    fi
}

################################################################################
# Packet Capture
################################################################################

start_packet_capture() {
    print_separator
    log_info "Starting SIP packet capture..."
    
    # Capture on all interfaces, filter for SIP port 5060
    sudo tcpdump -i any port 5060 -w ${RUN_DIR}/sip_capture.pcap -n > /dev/null 2>&1 &
    TCPDUMP_PID=$!
    
    log_info "Packet capture started (PID: $TCPDUMP_PID)"
    log_info "Capture file: ${RUN_DIR}/sip_capture.pcap"
    sleep 1
}

################################################################################
# VoLTE Testing
################################################################################

run_sip_registration_test() {
    print_separator
    log_info "Running SIP Registration Test..."
    echo ""
    
    python3 $TEST_SCRIPT 2>&1 | tee ${RUN_DIR}/registration_test_output.log
    
    local exit_code=${PIPESTATUS[0]}
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        log_success "SIP registration test completed"
    else
        log_error "SIP registration test failed with exit code $exit_code"
        return 1
    fi
}

parse_results() {
    print_separator
    log_info "Parsing test results..."
    
    if [ -f "${RUN_DIR}/registration_test_output.log" ]; then
        # Extract timing information
        local total_delay=$(grep "Total Registration Delay:" ${RUN_DIR}/registration_test_output.log | awk '{print $4}')
        local challenge_delay=$(grep "Initial REGISTER to 401:" ${RUN_DIR}/registration_test_output.log | awk '{print $5}')
        local auth_delay=$(grep "Auth REGISTER to 200 OK:" ${RUN_DIR}/registration_test_output.log | awk '{print $6}')
        
        echo ""
        echo "Performance Metrics:"
        echo "  Challenge Response:     $challenge_delay"
        echo "  Authentication:         $auth_delay"
        echo "  Total Delay:            $total_delay"
        echo ""
        
        # Save summary
        cat > ${RUN_DIR}/summary.txt << EOF
VoLTE IMS Testbed - Execution Summary
======================================
Timestamp: $TIMESTAMP
Date: $(date)

Performance Metrics:
  Challenge Response:     $challenge_delay
  Authentication:         $auth_delay  
  Total Delay:            $total_delay

Files Generated:
  - sip_capture.pcap          SIP packet capture
  - registration_test_output.log   Test execution log
  - enb_output.log            eNodeB logs
  - ue_output.log             UE logs
  - summary.txt               This summary

Status: SUCCESS
EOF
        
        log_success "Results saved to ${RUN_DIR}/summary.txt"
    else
        log_warn "Could not parse results - log file not found"
    fi
}

analyze_packet_capture() {
    print_separator
    log_info "Analyzing captured SIP packets..."
    
    # Stop capture
    if [ ! -z "$TCPDUMP_PID" ]; then
        sudo kill $TCPDUMP_PID 2>/dev/null || true
        sleep 1
    fi
    
    # Count SIP messages
    local total_packets=$(sudo tcpdump -r ${RUN_DIR}/sip_capture.pcap 2>/dev/null | wc -l)
    local register_packets=$(sudo tcpdump -r ${RUN_DIR}/sip_capture.pcap -A 2>/dev/null | grep -c "REGISTER" || echo "0")
    local ok_responses=$(sudo tcpdump -r ${RUN_DIR}/sip_capture.pcap -A 2>/dev/null | grep -c "200 OK" || echo "0")
    local auth_challenges=$(sudo tcpdump -r ${RUN_DIR}/sip_capture.pcap -A 2>/dev/null | grep -c "401 Unauthorized" || echo "0")
    
    echo ""
    echo "Packet Capture Analysis:"
    echo "  Total SIP packets:      $total_packets"
    echo "  REGISTER requests:      $register_packets"
    echo "  200 OK responses:       $ok_responses"
    echo "  401 challenges:         $auth_challenges"
    echo ""
    
    log_success "Packet capture saved: ${RUN_DIR}/sip_capture.pcap"
}

################################################################################
# Main Execution
################################################################################

main() {
    clear
    print_separator
    echo "           VoLTE IMS Testbed - Automated Demonstration"
    print_separator
    echo ""
    echo "This script will execute a complete VoLTE demonstration including:"
    echo "  - Service health verification"
    echo "  - RAN deployment (eNB + UE)"
    echo "  - Network attachment with retry mechanism"
    echo "  - SIP registration and performance measurement"
    echo "  - Packet capture and analysis"
    echo ""
    echo "Run directory: $RUN_DIR"
    echo ""
    print_separator
    
    # Create run directory
    mkdir -p $RUN_DIR
    
    # Initial cleanup of any existing processes
    print_separator
    log_info "Performing initial cleanup of existing processes..."
    sudo pkill -9 srsenb 2>/dev/null || true
    sudo pkill -9 srsue 2>/dev/null || true
    sudo killall -9 srsenb 2>/dev/null || true
    sudo killall -9 srsue 2>/dev/null || true
    
    # Kill any processes holding ZMQ ports
    sudo lsof -ti:2000 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
    sudo lsof -ti:2001 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
    
    sleep 2
    log_success "Initial cleanup completed"
    
    # Execute test sequence
    check_prerequisites
    check_open5gs_services
    check_kamailio
    check_network_interfaces
    
    start_enb
    start_ue
    check_ue_attachment
    
    start_packet_capture
    
    sleep 2  # Allow capture to stabilize
    
    run_sip_registration_test
    
    sleep 1
    
    parse_results
    analyze_packet_capture
    
    # Final summary
    print_separator
    log_success "Demonstration completed successfully"
    print_separator
    echo ""
    echo "Results Location: $RUN_DIR"
    echo ""
    echo "Files generated:"
    echo "  - sip_capture.pcap               SIP packets (Wireshark compatible)"
    echo "  - registration_test_output.log   Detailed test output"
    echo "  - summary.txt                    Performance summary"
    echo "  - enb_output.log                 eNodeB logs"
    echo "  - ue_output.log                  UE logs"
    echo ""
    echo "RAN processes are still running for further inspection."
    echo "To stop: sudo pkill -f 'srs(enb|ue)'"
    echo ""
    print_separator
}

# Execute main function
main "$@"
