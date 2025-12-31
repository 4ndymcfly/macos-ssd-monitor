#!/bin/bash

# =============================================================================
# Centralized Configuration - SSD Monitoring System
# =============================================================================
# This file contains disk configuration and common functions
# Edit the values below to match your system's disks
# =============================================================================

# -----------------------------------------------------------------------------
# Project Paths (auto-detected, no need to change)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/ssd-history.csv"
REPORTS_DIR="$SCRIPT_DIR/reports"

# -----------------------------------------------------------------------------
# Disk Configuration - CUSTOMIZE THESE VALUES
# -----------------------------------------------------------------------------
# Run 'diskutil list' to find your disk identifiers
# Run 'smartctl -a /dev/diskX' to verify SMART support

# Primary Disk (typically internal Apple SSD)
DISK_APPLE_DEVICE="disk0"
DISK_APPLE_NAME="APPLE"
DISK_APPLE_DESC="Internal Apple SSD"
DISK_APPLE_VOLUME=""  # Empty for system disk
DISK_APPLE_SPEED_TEST_PATH="/tmp"  # Use /tmp for speed tests

# Secondary Disk (external SSD via USB/Thunderbolt)
DISK_SAMSUNG_DEVICE="disk4"
DISK_SAMSUNG_NAME="SAMSUNG"
DISK_SAMSUNG_DESC="External Samsung SSD"
DISK_SAMSUNG_VOLUME="/Volumes/ExternalSSD"
DISK_SAMSUNG_SPEED_TEST_PATH="/Volumes/ExternalSSD"

# -----------------------------------------------------------------------------
# Colors for Output
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Global Selection Variables
# -----------------------------------------------------------------------------
SELECTED_DISKS=()
CURRENT_DISK_DEVICE=""
CURRENT_DISK_NAME=""
CURRENT_DISK_DESC=""
CURRENT_DISK_VOLUME=""
CURRENT_SPEED_TEST_PATH=""

# -----------------------------------------------------------------------------
# Disk Configuration Functions
# -----------------------------------------------------------------------------

# Configure variables for Apple disk
set_disk_apple() {
    CURRENT_DISK_DEVICE="$DISK_APPLE_DEVICE"
    CURRENT_DISK_NAME="$DISK_APPLE_NAME"
    CURRENT_DISK_DESC="$DISK_APPLE_DESC"
    CURRENT_DISK_VOLUME="$DISK_APPLE_VOLUME"
    CURRENT_SPEED_TEST_PATH="$DISK_APPLE_SPEED_TEST_PATH"
}

# Configure variables for Samsung disk
set_disk_samsung() {
    CURRENT_DISK_DEVICE="$DISK_SAMSUNG_DEVICE"
    CURRENT_DISK_NAME="$DISK_SAMSUNG_NAME"
    CURRENT_DISK_DESC="$DISK_SAMSUNG_DESC"
    CURRENT_DISK_VOLUME="$DISK_SAMSUNG_VOLUME"
    CURRENT_SPEED_TEST_PATH="$DISK_SAMSUNG_SPEED_TEST_PATH"
}

# Configure variables by disk name
set_disk_by_name() {
    local disk_name="$1"
    case "$disk_name" in
        "APPLE"|"apple")
            set_disk_apple
            ;;
        "SAMSUNG"|"samsung")
            set_disk_samsung
            ;;
        *)
            echo -e "${RED}Error: Unknown disk: $disk_name${NC}"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Interactive Disk Selection Function
# -----------------------------------------------------------------------------
select_disk() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                        Disk Selection                                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    # Check disk availability
    local apple_available=false
    local samsung_available=false

    if diskutil info "$DISK_APPLE_DEVICE" &>/dev/null; then
        apple_available=true
    fi

    if diskutil info "$DISK_SAMSUNG_DEVICE" &>/dev/null; then
        samsung_available=true
    fi

    echo -e "${BOLD}Available Disks:${NC}\n"

    # Show Apple option
    if [ "$apple_available" = true ]; then
        echo -e "  ${GREEN}1${NC}) ${WHITE}$DISK_APPLE_NAME${NC} - $DISK_APPLE_DESC ${GREEN}[Connected]${NC}"
    else
        echo -e "  ${RED}1${NC}) ${WHITE}$DISK_APPLE_NAME${NC} - $DISK_APPLE_DESC ${RED}[Not available]${NC}"
    fi

    # Show Samsung option
    if [ "$samsung_available" = true ]; then
        echo -e "  ${GREEN}2${NC}) ${WHITE}$DISK_SAMSUNG_NAME${NC} - $DISK_SAMSUNG_DESC ${GREEN}[Connected]${NC}"
    else
        echo -e "  ${RED}2${NC}) ${WHITE}$DISK_SAMSUNG_NAME${NC} - $DISK_SAMSUNG_DESC ${RED}[Not available]${NC}"
    fi

    # Show Both option
    if [ "$apple_available" = true ] && [ "$samsung_available" = true ]; then
        echo -e "  ${GREEN}3${NC}) ${WHITE}BOTH${NC} - Analyze both disks sequentially"
    else
        echo -e "  ${RED}3${NC}) ${WHITE}BOTH${NC} - Requires both disks connected ${RED}[Not available]${NC}"
    fi

    echo ""

    # Read selection
    while true; do
        read -p "$(echo -e ${WHITE}Select an option [1-3]: ${NC})" choice

        case $choice in
            1)
                if [ "$apple_available" = true ]; then
                    SELECTED_DISKS=("APPLE")
                    set_disk_apple
                    echo -e "\n${GREEN}✓${NC} Selected disk: ${WHITE}$DISK_APPLE_NAME${NC} - $DISK_APPLE_DESC\n"
                    return 0
                else
                    echo -e "${RED}Apple disk is not available${NC}"
                fi
                ;;
            2)
                if [ "$samsung_available" = true ]; then
                    SELECTED_DISKS=("SAMSUNG")
                    set_disk_samsung
                    echo -e "\n${GREEN}✓${NC} Selected disk: ${WHITE}$DISK_SAMSUNG_NAME${NC} - $DISK_SAMSUNG_DESC\n"
                    return 0
                else
                    echo -e "${RED}Samsung disk is not available${NC}"
                fi
                ;;
            3)
                if [ "$apple_available" = true ] && [ "$samsung_available" = true ]; then
                    SELECTED_DISKS=("APPLE" "SAMSUNG")
                    echo -e "\n${GREEN}✓${NC} Selected disks: ${WHITE}BOTH${NC} (APPLE + SAMSUNG)\n"
                    return 0
                else
                    echo -e "${RED}Both disks must be connected${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Parse Disk Argument Function
# -----------------------------------------------------------------------------
parse_disk_arg() {
    local arg="$1"

    case "$arg" in
        --disk=apple|--disk=APPLE|-d=apple|-d=APPLE)
            SELECTED_DISKS=("APPLE")
            set_disk_apple
            return 0
            ;;
        --disk=samsung|--disk=SAMSUNG|-d=samsung|-d=SAMSUNG)
            SELECTED_DISKS=("SAMSUNG")
            set_disk_samsung
            return 0
            ;;
        --disk=both|--disk=BOTH|-d=both|-d=BOTH)
            SELECTED_DISKS=("APPLE" "SAMSUNG")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Print Disk Separator Function
# -----------------------------------------------------------------------------
print_disk_separator() {
    local disk_name="$1"
    local disk_desc="$2"

    echo -e "\n${BOLD}${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║  DISK: $disk_name"
    echo "║  $disk_desc"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

# -----------------------------------------------------------------------------
# Utility Function: Check Disk Available
# -----------------------------------------------------------------------------
check_disk_available() {
    local device="$1"
    if diskutil info "$device" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Utility Function: Get Disk Info
# -----------------------------------------------------------------------------
get_disk_model() {
    local device="$1"
    smartctl -a "$device" 2>/dev/null | grep "Model Number:" | cut -d: -f2 | xargs
}

get_disk_serial() {
    local device="$1"
    smartctl -a "$device" 2>/dev/null | grep "Serial Number:" | cut -d: -f2 | xargs
}

# -----------------------------------------------------------------------------
# Screen Clear Function (full reset)
# -----------------------------------------------------------------------------
clear_screen() {
    # Full terminal reset (clears screen and scrollback)
    printf '\033c'
}

# -----------------------------------------------------------------------------
# Create Directories if They Don't Exist
# -----------------------------------------------------------------------------
ensure_directories() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$REPORTS_DIR"
}
