#!/bin/bash
#
# VoLTE Demo Script - Fully Automated
# Group5: KURNIYANSYA, ABDULRASHEED, BASHARAT
#
# This script runs a complete VoLTE demonstration including:
# - SIP registration from two UEs
# - VoLTE call between UEs
# - Automatic packet capture with timestamped storage
#
# Usage: sudo ./volte_demo.sh
#

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)"
    echo "Usage: sudo ./volte_demo.sh"
    exit 1
fi

set -e

#=============================================================================
# Configuration
#=============================================================================
DEMO_BASE_DIR="/home/open5gs/demo"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEMO_DIR="${DEMO_BASE_DIR}/${TIMESTAMP}"
PCAP_FILE="${DEMO_DIR}/volte_capture.pcap"
LOG_FILE="${DEMO_DIR}/demo.log"
RESULTS_FILE="${DEMO_DIR}/results.txt"

# SIP Configuration
SIP_SERVER="10.45.0.1"
SIP_PORT="5060"
UE1_USER="001010000000001"
UE1_PASS="secret123"
UE2_USER="001010000000002"
UE2_PASS="secret456"
SIP_DOMAIN="ims.localdomain"

# UE IPs (populated by setup_srsran)
UE1_IP=""
UE2_IP=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Create demo directory early
mkdir -p "$DEMO_DIR"
touch "$LOG_FILE"

#=============================================================================
# Helper Functions
#=============================================================================
log() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
step() { echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null; }
header() { echo -e "${CYAN}$1${NC}" | tee -a "$LOG_FILE" 2>/dev/null; }

cleanup() {
    log "Cleaning up..."
    # Kill any background processes we started
    [[ -n "$TSHARK_PID" ]] && kill $TSHARK_PID 2>/dev/null || true
    pkill -f "linphonec" 2>/dev/null || true
    pkill -f "tail -f.*fifo" 2>/dev/null || true
    # Remove FIFOs
    rm -f /tmp/ue1_fifo_* /tmp/ue2_fifo_* 2>/dev/null || true
    # Fix pcap permissions
    [[ -f "$PCAP_FILE" ]] && chmod 644 "$PCAP_FILE" 2>/dev/null || true
}

trap cleanup EXIT

#=============================================================================
# srsRAN Setup - Starts eNBs and UEs if not running
#=============================================================================
ENB1_CONFIG="/home/open5gs/two-cell-voip/enb1.conf"
ENB2_CONFIG="/home/open5gs/two-cell-voip/enb2.conf"
UE1_CONFIG="/home/open5gs/two-cell-voip/ue1.conf"
UE2_CONFIG="/home/open5gs/two-cell-voip/ue2.conf"

setup_srsran() {
    header "\n=========================================="
    header "  Setting Up srsRAN"
    header "==========================================\n"
    
    # Create namespaces if missing (srsue needs them to exist)
    if ! ip netns list | grep -q "^ue1"; then
        log "Creating UE1 namespace..."
        ip netns add ue1
        ip netns exec ue1 ip link set lo up
    fi
    
    if ! ip netns list | grep -q "^ue2"; then
        log "Creating UE2 namespace..."
        ip netns add ue2
        ip netns exec ue2 ip link set lo up
    fi
    
    # Start srsenb1 if not running
    if ! pgrep -f "srsenb.*enb1.conf" > /dev/null; then
        log "Starting srsenb (Cell 1)..."
        srsenb "$ENB1_CONFIG" > /tmp/srsenb1_demo.log 2>&1 &
        sleep 3
    else
        log "srsenb (Cell 1): Already running"
    fi
    
    # Start srsenb2 if not running
    if ! pgrep -f "srsenb.*enb2.conf" > /dev/null; then
        log "Starting srsenb (Cell 2)..."
        srsenb "$ENB2_CONFIG" > /tmp/srsenb2_demo.log 2>&1 &
        sleep 3
    else
        log "srsenb (Cell 2): Already running"
    fi
    
    # Verify eNBs started
    sleep 2
    local enb_count=$(pgrep -c srsenb 2>/dev/null || echo 0)
    if [[ $enb_count -ge 2 ]]; then
        log "Both eNBs started ($enb_count processes)"
    else
        error "eNB startup issue: only $enb_count running"
    fi
    
    # Start srsue for UE1 if not attached
    UE1_IP=$(ip netns exec ue1 ip -4 addr show tun_srsue 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
    if [[ -z "$UE1_IP" ]]; then
        log "Starting srsue for UE1..."
        srsue "$UE1_CONFIG" > /tmp/srsue1_demo.log 2>&1 &
    else
        log "UE1: Already attached ($UE1_IP)"
    fi
    
    # Start srsue for UE2 if not attached
    UE2_IP=$(ip netns exec ue2 ip -4 addr show tun_srsue 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
    if [[ -z "$UE2_IP" ]]; then
        log "Starting srsue for UE2..."
        srsue "$UE2_CONFIG" > /tmp/srsue2_demo.log 2>&1 &
    else
        log "UE2: Already attached ($UE2_IP)"
    fi
    
    # Wait for UEs to attach (up to 30 seconds)
    log "Waiting for UE attachment..."
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        UE1_IP=$(ip netns exec ue1 ip -4 addr show tun_srsue 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
        UE2_IP=$(ip netns exec ue2 ip -4 addr show tun_srsue 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
        
        if [[ -n "$UE1_IP" && -n "$UE2_IP" ]]; then
            log "UE1 attached: $UE1_IP"
            log "UE2 attached: $UE2_IP"
            break
        fi
        
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if [[ -z "$UE1_IP" || -z "$UE2_IP" ]]; then
        error "UE attachment failed after ${max_wait}s"
        [[ -z "$UE1_IP" ]] && error "UE1: Not attached"
        [[ -z "$UE2_IP" ]] && error "UE2: Not attached"
        return 1
    fi
}

#=============================================================================
# Network Setup - Creates bridge for packet capture
#=============================================================================
setup_network() {
    header "\n=========================================="
    header "  Setting Up Network Bridge"
    header "==========================================\n"
    
    # Create br-sip bridge if missing (for packet capture)
    if ! ip link show br-sip &>/dev/null; then
        log "Creating br-sip bridge..."
        ip link add name br-sip type bridge
        ip link set br-sip up
        ip addr add 10.45.0.1/16 dev br-sip 2>/dev/null || true
    else
        log "br-sip bridge: Exists"
    fi
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
}


check_prerequisites() {
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        local failed=0
        
        if [[ $retry -eq 0 ]]; then
            header "\n=========================================="
            header "  Checking Prerequisites"
            header "==========================================\n"
        else
            header "\n=========================================="
            header "  Retry $retry/$((max_retries-1)): Re-checking After Fixes"
            header "==========================================\n"
        fi
        
        # Check Kamailio
        if systemctl is-active --quiet kamailio; then
            log "Kamailio SIP server: Running"
        else
            error "Kamailio SIP server: NOT RUNNING"
            warn "Attempting to start Kamailio..."
            systemctl start kamailio
            sleep 2
            if ! systemctl is-active --quiet kamailio; then
                error "Failed to start Kamailio"
                failed=1
            else
                log "Kamailio: Started successfully"
            fi
        fi
        
        # Check UE attachment (IPs should be set by setup_srsran)
        if [[ -n "$UE1_IP" ]]; then
            log "UE1 attached: $UE1_IP"
        else
            error "UE1: NOT ATTACHED (no tun_srsue)"
            failed=1
        fi
        
        if [[ -n "$UE2_IP" ]]; then
            log "UE2 attached: $UE2_IP"
        else
            error "UE2: NOT ATTACHED (no tun_srsue)"
            failed=1
        fi
        
        # Set up routing for UE IPs via ogstun
        if [[ -n "$UE1_IP" ]]; then
            ip route replace ${UE1_IP}/32 dev ogstun 2>/dev/null && log "Route for UE1 ($UE1_IP) via ogstun"
        fi
        if [[ -n "$UE2_IP" ]]; then
            ip route replace ${UE2_IP}/32 dev ogstun 2>/dev/null && log "Route for UE2 ($UE2_IP) via ogstun"
        fi
        
        # Check network connectivity using ping with retries
        local ue1_reachable=0
        local ue2_reachable=0
        
        if ip netns exec ue1 ping -c 1 -W 5 $SIP_SERVER &>/dev/null; then
            log "UE1 -> SIP Server: Reachable"
            ue1_reachable=1
        else
            error "UE1 -> SIP Server: NOT REACHABLE"
        fi
        
        if ip netns exec ue2 ping -c 1 -W 5 $SIP_SERVER &>/dev/null; then
            log "UE2 -> SIP Server: Reachable"
            ue2_reachable=1
        else
            error "UE2 -> SIP Server: NOT REACHABLE"
        fi
        
        # Try to fix connectivity issues
        if [[ $ue1_reachable -eq 0 || $ue2_reachable -eq 0 ]]; then
            failed=1
            if [[ $retry -lt $((max_retries-1)) ]]; then
                warn "Attempting to fix connectivity issues..."
                
                # Fix 1: Add default route via tun_srsue in namespaces
                if [[ $ue1_reachable -eq 0 && -n "$UE1_IP" ]]; then
                    warn "  Adding default route for UE1..."
                    ip netns exec ue1 ip route replace default dev tun_srsue 2>/dev/null || true
                fi
                if [[ $ue2_reachable -eq 0 && -n "$UE2_IP" ]]; then
                    warn "  Adding default route for UE2..."
                    ip netns exec ue2 ip route replace default dev tun_srsue 2>/dev/null || true
                fi
                
                # Fix 2: Add route to SIP server network
                ip netns exec ue1 ip route replace 10.45.0.0/16 dev tun_srsue 2>/dev/null || true
                ip netns exec ue2 ip route replace 10.45.0.0/16 dev tun_srsue 2>/dev/null || true
                
                # Fix 3: Wait for ZMQ radio to stabilize
                warn "  Waiting 5s for radio link to stabilize..."
                sleep 5
            fi
        fi
        
        # Check linphonec
        if command -v linphonec &>/dev/null; then
            log "Linphone CLI: Installed"
        else
            error "Linphone CLI: NOT INSTALLED"
            failed=1
        fi
        
        # Check tshark
        if command -v tshark &>/dev/null; then
            log "Tshark: Installed"
        else
            error "Tshark: NOT INSTALLED"
            failed=1
        fi
        
        # If everything passed, we're done
        if [[ $failed -eq 0 ]]; then
            log "\nAll prerequisites satisfied!"
            return 0
        fi
        
        retry=$((retry + 1))
        
        # If we've exhausted retries, exit
        if [[ $retry -ge $max_retries ]]; then
            error "\nPrerequisite check failed after $max_retries attempts."
            error "Please check srsRAN logs: /tmp/srsenb*.log, /tmp/srsue*.log"
            exit 1
        fi
    done
}
    fi
    
    log "\nAll prerequisites satisfied!"
}

start_capture() {
    header "\n=========================================="
    header "  Starting Packet Capture"
    header "==========================================\n"
    
    log "Starting packet capture..."
    log "PCAP file: $PCAP_FILE"
    
    # Kill any existing capture processes
    pkill -9 tshark 2>/dev/null || true
    pkill -9 tcpdump 2>/dev/null || true
    sleep 1
    
    # Determine capture interface - ogstun for real srsRAN, br-sip for simulated
    local capture_iface="ogstun"
    if ! ip link show ogstun &>/dev/null; then
        capture_iface="any"
    fi
    
    # Capture SIP and RTP traffic
    # Filter: SIP port 5060 OR common RTP port ranges OR ffmpeg audio port
    tcpdump -i "$capture_iface" -U -w "$PCAP_FILE" "port 5060 or udp portrange 7078-7099 or udp port 9000 or udp portrange 16384-32767" 2>/dev/null &
    TSHARK_PID=$!
    
    sleep 2
    
    if ps -p $TSHARK_PID > /dev/null 2>&1; then
        log "Packet capture started (PID: $TSHARK_PID)"
    else
        error "Failed to start packet capture"
        error "Manual alternative: In another terminal run:"
        error "  sudo tcpdump -i any -w $PCAP_FILE 'port 5060'"
        exit 1
    fi
}

# Use FIFOs to control persistent linphonec instances
UE1_FIFO="/tmp/ue1_fifo_$$"
UE2_FIFO="/tmp/ue2_fifo_$$"
UE1_HOME="/tmp/ue1_home_$$"
UE2_HOME="/tmp/ue2_home_$$"

setup_ue_fifos() {
    # Create FIFOs for controlling linphonec
    rm -f "$UE1_FIFO" "$UE2_FIFO"
    mkfifo "$UE1_FIFO" "$UE2_FIFO"
    
    # Create home directories
    rm -rf "$UE1_HOME" "$UE2_HOME"
    mkdir -p "$UE1_HOME/.local/share/linphone" "$UE2_HOME/.local/share/linphone"
    chmod -R 777 "$UE1_HOME" "$UE2_HOME"
    
    # Copy config files with fixed RTP ports
    cp /home/open5gs/sip-clients/linphonerc-ue1-demo "$UE1_HOME/.linphonerc"
    cp /home/open5gs/sip-clients/linphonerc-ue2-demo "$UE2_HOME/.linphonerc"
}

start_ue1() {
    log "Starting UE1 (001010000000001)..."
    
    # Start linphonec reading from FIFO with config
    ip netns exec ue1 bash -c "
        export HOME='$UE1_HOME'
        tail -f '$UE1_FIFO' | linphonec -c '$UE1_HOME/.linphonerc' 2>&1
    " >> "$LOG_FILE" 2>&1 &
    UE1_LINPHONE_PID=$!
    sleep 2
}

start_ue2() {
    log "Starting UE2 (001010000000002)..."
    
    # Start linphonec reading from FIFO with config
    ip netns exec ue2 bash -c "
        export HOME='$UE2_HOME'
        tail -f '$UE2_FIFO' | linphonec -c '$UE2_HOME/.linphonerc' 2>&1
    " >> "$LOG_FILE" 2>&1 &
    UE2_LINPHONE_PID=$!
    sleep 2
}

send_ue1() {
    echo "$1" >> "$UE1_FIFO"
}

send_ue2() {
    echo "$1" >> "$UE2_FIFO"
}

register_both_ues() {
    log "Registering UE1..."
    send_ue1 "register sip:${UE1_USER}@${SIP_DOMAIN} sip:${SIP_SERVER}:${SIP_PORT} ${UE1_PASS}"
    sleep 3
    
    log "Registering UE2..."
    send_ue2 "register sip:${UE2_USER}@${SIP_DOMAIN} sip:${SIP_SERVER}:${SIP_PORT} ${UE2_PASS}"
    sleep 3
}

make_and_answer_call() {
    log "UE1 calling UE2..."
    send_ue1 "call sip:${UE2_USER}@${SIP_DOMAIN}"
    
    sleep 8  # Wait for INVITE to reach UE2 and start ringing
    
    log "UE2 answering call..."
    send_ue2 "answer"
    
    log "Call connected - streaming real audio via ffmpeg..."
    sleep 2  # Wait for RTP to establish
    
    # Stream real audio from UE1 to UE2 using ffmpeg
    # Using separate port 9000 to avoid conflict with linphonec
    ip netns exec ue1 ffmpeg -re -i /home/open5gs/sip-clients/sample_call_audio.wav \
        -ar 48000 -ac 1 -c:a libopus -b:a 64k \
        -f rtp rtp://${UE2_IP}:9000 </dev/null >/dev/null 2>&1 &
    FFMPEG_PID=$!
    
    log "Audio streaming started (PID: $FFMPEG_PID)"
    sleep 12  # Wait for audio to finish (~11 seconds)
    
    # Kill ffmpeg if still running
    kill $FFMPEG_PID 2>/dev/null || true
    wait $FFMPEG_PID 2>/dev/null || true
    
    log "UE1 terminating call..."
    send_ue1 "terminate"
    sleep 2
}

quit_both_ues() {
    log "Closing UE1..."
    send_ue1 "quit"
    sleep 1
    
    log "Closing UE2..."
    send_ue2 "quit"
    sleep 2
    
    # Cleanup
    rm -f "$UE1_FIFO" "$UE2_FIFO"
    pkill -f "tail -f.*fifo" 2>/dev/null || true
}

analyze_capture() {
    header "\n=========================================="
    header "  Analyzing Capture"
    header "==========================================\n"
    
    # Fix permissions
    chmod 644 "$PCAP_FILE" 2>/dev/null || true
    
    # Wait for file to be written
    sleep 2
    
    if [[ ! -f "$PCAP_FILE" ]]; then
        error "PCAP file not found!"
        return 1
    fi
    
    local file_size=$(stat -c%s "$PCAP_FILE" 2>/dev/null || echo "0")
    log "PCAP file size: $file_size bytes"
    
    # Count packets
    local rtp_packets=$(tshark -r "$PCAP_FILE" -Y "rtp" 2>/dev/null | wc -l)
    
    # Calculate SIP registration delays
    # UE1: Time from first REGISTER to 200 OK
    local ue1_reg_start=$(tshark -r "$PCAP_FILE" -Y "sip.Method == REGISTER && ip.src == $UE1_IP" -T fields -e frame.time_relative 2>/dev/null | head -1)
    local ue1_reg_end=$(tshark -r "$PCAP_FILE" -Y "sip.Status-Code == 200 && sip.CSeq.method == REGISTER && ip.dst == $UE1_IP" -T fields -e frame.time_relative 2>/dev/null | head -1)
    local ue1_reg_delay="N/A"
    if [[ -n "$ue1_reg_start" && -n "$ue1_reg_end" ]]; then
        local ue1_delay_sec=$(echo "$ue1_reg_end - $ue1_reg_start" | bc 2>/dev/null)
        local ue1_delay_ms=$(printf "%.1f" $(echo "$ue1_delay_sec * 1000" | bc) 2>/dev/null)
        ue1_reg_delay="${ue1_delay_ms}ms"
    fi
    
    # UE2: Time from first REGISTER to 200 OK
    local ue2_reg_start=$(tshark -r "$PCAP_FILE" -Y "sip.Method == REGISTER && ip.src == $UE2_IP" -T fields -e frame.time_relative 2>/dev/null | head -1)
    local ue2_reg_end=$(tshark -r "$PCAP_FILE" -Y "sip.Status-Code == 200 && sip.CSeq.method == REGISTER && ip.dst == $UE2_IP" -T fields -e frame.time_relative 2>/dev/null | head -1)
    local ue2_reg_delay="N/A"
    if [[ -n "$ue2_reg_start" && -n "$ue2_reg_end" ]]; then
        local ue2_delay_sec=$(echo "$ue2_reg_end - $ue2_reg_start" | bc 2>/dev/null)
        local ue2_delay_ms=$(printf "%.1f" $(echo "$ue2_delay_sec * 1000" | bc) 2>/dev/null)
        ue2_reg_delay="${ue2_delay_ms}ms"
    fi
    
    header "\n=========================================="
    header "  DEMO RESULTS"
    header "==========================================\n"
    
    echo ""
    echo "SIP Registration Delay:"
    echo "  UE1 ($UE1_IP):       ${ue1_reg_delay}"
    echo "  UE2 ($UE2_IP):       ${ue2_reg_delay}"
    echo ""
    echo "RTP Media:"
    echo "  RTP packets:           $rtp_packets"
    echo ""
    
    # Generate results file
    cat > "$RESULTS_FILE" << EOF
Date: $(date)
Session: $TIMESTAMP
==================

SIP Registration Delay:
  UE1 ($UE1_IP):       ${ue1_reg_delay}
  UE2 ($UE2_IP):       ${ue2_reg_delay}

Network Configuration:
  SIP Server: $SIP_SERVER:$SIP_PORT
  UE1: $UE1_IP (User: $UE1_USER)
  UE2: $UE2_IP (User: $UE2_USER)

RTP Media Analysis:
  Audio Source: /home/open5gs/sip-clients/sample_call_audio.wav (OPUS codec via ffmpeg)
  Total RTP packets:     $rtp_packets

Files Generated:
  PCAP Capture: $PCAP_FILE
EOF

    log "Results saved to: $RESULTS_FILE"
}

show_sip_flow() {
    header "\n=========================================="
    header "  SIP Message Flow"
    header "==========================================\n"
    
    tshark -r "$PCAP_FILE" -Y "sip" -T fields \
        -e frame.time_relative \
        -e ip.src \
        -e ip.dst \
        -e sip.Method \
        -e sip.Status-Code \
        2>/dev/null | head -30
}

#=============================================================================
# Main Script
#=============================================================================
main() {
    clear
    
    header "=============================================="
    header "   Kamailio SIP Server with srsRAN and Open5GS"
    header "   G5: MOMODU / KURNIANSYAH / BASHARAT"
    header "=============================================="
    
    log "Demo session: $TIMESTAMP"
    log "Output directory: $DEMO_DIR"
    
    # Setup srsRAN (starts eNB and UEs if needed)
    setup_srsran
    
    # Setup network bridge for capture
    setup_network
    
    # Check prerequisites
    check_prerequisites
    
    # Setup FIFOs for controlling linphonec
    setup_ue_fifos
    
    # Start packet capture
    start_capture
    
    # Phase 1: Start UE clients
    header "\n=========================================="
    header "  Phase 1: Starting SIP Clients"
    header "==========================================\n"
    
    start_ue1
    start_ue2
    
    # Phase 2: SIP Registration (one per UE)
    header "\n=========================================="
    header "  Phase 2: SIP Registration"
    header "==========================================\n"
    
    register_both_ues
    log "Both UEs registered successfully"
    sleep 2
    
    # Phase 3: VoLTE Call
    header "\n=========================================="
    header "  Phase 3: VoLTE Call"
    header "==========================================\n"
    
    make_and_answer_call
    
    # Phase 4: Cleanup and de-register
    header "\n=========================================="
    header "  Phase 4: Call Ended, De-registering"
    header "==========================================\n"
    
    quit_both_ues
    
    # Stop capture
    header "\n=========================================="
    header "  Stopping Capture"
    header "==========================================\n"
    
    log "Stopping packet capture..."
    kill $TSHARK_PID 2>/dev/null || true
    TSHARK_PID=""
    sleep 3
    
    # Cleanup any remaining linphone processes
    pkill -f "linphonec" 2>/dev/null || true
    sleep 2
    
    # Analyze results
    analyze_capture
    
    # Show SIP flow
    show_sip_flow
    
    header "\n=============================================="
    header "  Demo Complete!"
    header "=============================================="
    echo ""
    log "All files saved to: $DEMO_DIR"
    echo ""
    echo "To open in Wireshark:"
    echo "  wireshark $PCAP_FILE"
    echo ""
    echo "To view summary:"
    echo "  cat $RESULTS_FILE"
    echo ""
}

# Run main
main "$@"
