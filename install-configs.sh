#!/bin/bash
# VoLTE IMS Testbed - Configuration Installation Script
# This script copies configuration files to their system locations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VoLTE IMS Testbed Configuration Installer ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${YELLOW}Installing configurations from: $SCRIPT_DIR${NC}\n"

# Check if required packages are installed
echo "Checking for required packages..."
MISSING_PACKAGES=""

if ! dpkg -l | grep -q "^ii  open5gs"; then
    MISSING_PACKAGES="$MISSING_PACKAGES open5gs"
fi

if ! dpkg -l | grep -q "^ii  kamailio"; then
    MISSING_PACKAGES="$MISSING_PACKAGES kamailio"
fi

if ! command -v srsue &> /dev/null; then
    MISSING_PACKAGES="$MISSING_PACKAGES srsran"
fi

if [ -n "$MISSING_PACKAGES" ]; then
    echo -e "${RED}Error: Missing required packages:$MISSING_PACKAGES${NC}"
    echo -e "${YELLOW}Please install them first. See QUICKSTART.md for installation instructions.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All required packages are installed${NC}\n"

# Backup existing configurations
echo "Creating backups of existing configurations..."
BACKUP_DIR="/etc/volte-testbed-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -d "/etc/open5gs" ]; then
    cp -r /etc/open5gs "$BACKUP_DIR/"
    echo -e "${GREEN}✓ Backed up /etc/open5gs to $BACKUP_DIR${NC}"
fi

if [ -f "/etc/kamailio/kamailio.cfg" ]; then
    mkdir -p "$BACKUP_DIR/kamailio"
    cp /etc/kamailio/kamailio.cfg "$BACKUP_DIR/kamailio/"
    echo -e "${GREEN}✓ Backed up /etc/kamailio/kamailio.cfg to $BACKUP_DIR${NC}"
fi

echo ""

# Install Open5GS configurations
echo "Installing Open5GS configurations..."
if [ -d "$SCRIPT_DIR/open5gs-config" ]; then
    cp "$SCRIPT_DIR/open5gs-config"/*.yaml /etc/open5gs/
    echo -e "${GREEN}✓ Copied Open5GS configs to /etc/open5gs/${NC}"
else
    echo -e "${RED}Error: open5gs-config directory not found${NC}"
    exit 1
fi

# Install Kamailio configuration
echo "Installing Kamailio configuration..."
if [ -f "$SCRIPT_DIR/kamailio-config/kamailio.cfg" ]; then
    cp "$SCRIPT_DIR/kamailio-config/kamailio.cfg" /etc/kamailio/
    echo -e "${GREEN}✓ Copied Kamailio config to /etc/kamailio/${NC}"
else
    echo -e "${RED}Error: kamailio-config/kamailio.cfg not found${NC}"
    exit 1
fi

# srsRAN configs stay in the repo directory (used with absolute paths)
echo -e "${YELLOW}Note: srsRAN configs in $SCRIPT_DIR/srsran-config/ will be used with absolute paths${NC}"

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}\n"
echo "Next steps:"
echo "1. Verify network setup: sudo ./initialize-system.sh"
echo "2. Add subscribers via Open5GS WebUI: http://$(hostname -I | awk '{print $1}'):9999"
echo "3. Start services: sudo systemctl restart open5gs-mmed kamailio"
echo "4. Run the demo: ./volte-demo.sh"
echo ""
echo -e "${YELLOW}Backup location: $BACKUP_DIR${NC}"
echo "See QUICKSTART.md for detailed instructions."
