#!/bin/bash
################################################################################
# VoLTE IMS Testbed - Cleanup Script
# 
# This script stops all RAN processes and cleans up network resources.
# Use this when you want to stop the testbed or start fresh.
#
# Usage: sudo ./cleanup-demo.sh
################################################################################

echo "============================================"
echo "  VoLTE IMS Testbed - Cleanup Script"
echo "============================================"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

echo "[1/4] Stopping srsRAN processes..."
pkill -9 srsenb 2>/dev/null
pkill -9 srsue 2>/dev/null
killall -9 srsenb 2>/dev/null
killall -9 srsue 2>/dev/null
echo "      Done"

echo "[2/4] Releasing ZMQ ports..."
lsof -ti:2000 2>/dev/null | xargs -r kill -9 2>/dev/null
lsof -ti:2001 2>/dev/null | xargs -r kill -9 2>/dev/null
echo "      Done"

echo "[3/4] Cleaning up TUN interface..."
ip link del tun_srsue 2>/dev/null || true
echo "      Done"

echo "[4/4] Verifying cleanup..."
if pgrep -x srsenb > /dev/null || pgrep -x srsue > /dev/null; then
    echo "      WARNING: Some processes still running"
else
    echo "      All processes stopped"
fi
echo

echo "============================================"
echo "  Cleanup Complete"
echo "============================================"
echo
echo "Core network services (Open5GS, Kamailio) are still running."
echo "To stop them: sudo systemctl stop open5gs-* kamailio"
echo
