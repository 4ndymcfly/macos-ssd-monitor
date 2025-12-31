#!/bin/bash

# =============================================================================
# Installation Script for macOS SSD Monitor
# =============================================================================

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                       ║"
echo "║     macOS SSD Monitor - Installation                                  ║"
echo "║                                                                       ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Check smartctl
echo -e "${BOLD}Checking requirements...${NC}\n"

if ! command -v smartctl &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} smartctl is not installed"
    echo -e "    Required to read SMART data from disks\n"

    read -p "$(echo -e ${WHITE}Would you like to install it with Homebrew? [y/N]: ${NC})" -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! command -v brew &>/dev/null; then
            echo -e "  ${YELLOW}⚠${NC} Homebrew is not installed"
            echo -e "    Install it from: https://brew.sh\n"
            exit 1
        fi

        echo -e "\n${CYAN}Installing smartmontools...${NC}\n"
        brew install smartmontools

        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✓${NC} smartmontools installed successfully"
        else
            echo -e "\n${YELLOW}⚠${NC} Error installing smartmontools"
            exit 1
        fi
    else
        echo -e "\n${YELLOW}⚠${NC} smartctl is required for operation"
        echo -e "    Install manually with: ${WHITE}brew install smartmontools${NC}\n"
        exit 1
    fi
else
    echo -e "  ${GREEN}✓${NC} smartctl found: $(which smartctl)"
fi

# Detect disks
echo -e "\n${BOLD}Detecting disks...${NC}\n"

# Source config to get disk definitions
source "$SCRIPT_DIR/config.sh"

# Check primary disk
if diskutil info "$DISK_APPLE_DEVICE" &>/dev/null; then
    disk_name=$(smartctl -a "$DISK_APPLE_DEVICE" 2>/dev/null | grep "Model Number:" | cut -d: -f2 | xargs)
    echo -e "  ${GREEN}✓${NC} Primary disk detected ($DISK_APPLE_DEVICE): ${WHITE}$disk_name${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Primary disk ($DISK_APPLE_DEVICE) not found"
    echo -e "      Check config.sh and update DISK_APPLE_DEVICE"
fi

# Check secondary disk
if diskutil info "$DISK_SAMSUNG_DEVICE" &>/dev/null; then
    disk_name=$(smartctl -a "$DISK_SAMSUNG_DEVICE" 2>/dev/null | grep "Model Number:" | cut -d: -f2 | xargs)
    echo -e "  ${GREEN}✓${NC} Secondary disk detected ($DISK_SAMSUNG_DEVICE): ${WHITE}$disk_name${NC}"
else
    echo -e "  ${YELLOW}⚠${NC} Secondary disk ($DISK_SAMSUNG_DEVICE) not connected"
    echo -e "      Connect it when you want to monitor it"
fi

# Set execution permissions
echo -e "\n${BOLD}Setting permissions...${NC}\n"

cd "$SCRIPT_DIR"

for script in *.sh; do
    chmod +x "$script"
    echo -e "  ${GREEN}✓${NC} $script"
done

# Create directories
echo -e "\n${BOLD}Creating directories...${NC}\n"

mkdir -p "$SCRIPT_DIR/logs"
echo -e "  ${GREEN}✓${NC} logs/"

mkdir -p "$SCRIPT_DIR/reports"
echo -e "  ${GREEN}✓${NC} reports/"

# Ask about aliases
echo -e "\n${BOLD}Alias Configuration${NC}\n"
echo -e "Aliases allow running scripts from any location."
echo -e "Examples: ${WHITE}ssd${NC}, ${WHITE}ssd-quick${NC}, ${WHITE}ssd-check${NC}\n"

read -p "$(echo -e ${WHITE}Would you like to install shell aliases? [Y/n]: ${NC})" -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    ./setup-aliases.sh
else
    echo -e "${YELLOW}ℹ${NC} You can install aliases later with: ${WHITE}./setup-aliases.sh${NC}"
fi

# Quick test
echo -e "\n${BOLD}Running verification test...${NC}\n"

./quick-check.sh --disk=apple 2>/dev/null || echo -e "${YELLOW}Apple disk test skipped${NC}"

# Final summary
echo -e "\n${BOLD}${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                       ║"
echo "║     ✓ Installation Complete                                           ║"
echo "║                                                                       ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

echo -e "${BOLD}Main Commands:${NC}\n"
echo -e "  ${WHITE}./ssd-dashboard.sh${NC}      - Interactive dashboard (recommended)"
echo -e "  ${WHITE}./quick-check.sh${NC}        - Quick check"
echo -e "  ${WHITE}./check-datos-ssd.sh${NC}    - Full analysis"
echo -e "  ${WHITE}cat README.md${NC}           - Full documentation"

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo -e "\n${BOLD}Or use installed aliases:${NC}\n"
    echo -e "  ${WHITE}ssd${NC}  ${WHITE}ssd-quick${NC}  ${WHITE}ssd-check${NC}  ${WHITE}ssd-speed${NC}  ${WHITE}ssd-temp${NC}"
    echo -e "\n${YELLOW}ℹ${NC} Reload your shell with: ${WHITE}source ~/.zshrc${NC}"
fi

echo -e "\n${BOLD}Configuration:${NC}\n"
echo -e "  Edit ${WHITE}config.sh${NC} to customize disk settings for your system."

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
