#!/bin/bash

# =============================================================================
# Alias Setup Script for macOS SSD Monitor
# =============================================================================

# Auto-detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_RC=""

# Detect shell
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    # Try to detect by default
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
        SHELL_NAME="zsh"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
        SHELL_NAME="bash"
    else
        echo "Unrecognized shell. Please add aliases manually."
        exit 1
    fi
fi

# Source config to get disk definitions
source "$SCRIPT_DIR/config.sh"

echo "═══════════════════════════════════════════════════════════"
echo "  macOS SSD Monitor - Alias Configuration"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Detected shell: $SHELL_NAME"
echo "Configuration file: $SHELL_RC"
echo "Script directory: $SCRIPT_DIR"
echo ""

# Create backup of rc file
if [ -f "$SHELL_RC" ]; then
    cp "$SHELL_RC" "${SHELL_RC}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✓ Backup created: ${SHELL_RC}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Check if aliases already exist
if grep -q "# SSD Monitor Aliases" "$SHELL_RC" 2>/dev/null; then
    echo ""
    echo "⚠ Aliases are already configured in $SHELL_RC"
    echo ""
    read -p "Would you like to replace them? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    # Remove old aliases
    sed -i.bak '/# SSD Monitor Aliases/,/# End SSD Monitor Aliases/d' "$SHELL_RC"
fi

# Add aliases to rc file
cat >> "$SHELL_RC" << EOF

# SSD Monitor Aliases
# Added automatically - Do not edit this section manually
alias ssd='$SCRIPT_DIR/ssd-dashboard.sh'
alias ssd-check='$SCRIPT_DIR/check-datos-ssd.sh'
alias ssd-quick='$SCRIPT_DIR/quick-check.sh'
alias ssd-speed='$SCRIPT_DIR/check-datos-ssd.sh --speed-test'
alias ssd-temp='smartctl -a $DISK_APPLE_DEVICE | grep -E "(Temperature|Sensor)"; echo "---"; smartctl -a $DISK_SAMSUNG_DEVICE | grep -E "(Temperature|Sensor)" 2>/dev/null || echo "Secondary disk not connected"'
alias ssd-health='echo "=== PRIMARY ==="; smartctl -H $DISK_APPLE_DEVICE; echo "=== SECONDARY ==="; smartctl -H $DISK_SAMSUNG_DEVICE 2>/dev/null || echo "Secondary disk not connected"'
alias ssd-info='echo "=== PRIMARY ==="; diskutil info $DISK_APPLE_DEVICE; echo "=== SECONDARY ==="; diskutil info $DISK_SAMSUNG_DEVICE 2>/dev/null || echo "Secondary disk not connected"'
alias ssd-eject='diskutil unmount $DISK_SAMSUNG_VOLUME && echo "✓ Disk ejected safely"'
alias ssd-history='$SCRIPT_DIR/view-history.sh'
alias ssd-track='$SCRIPT_DIR/track-ssd-history.sh'
# End SSD Monitor Aliases
EOF

echo ""
echo "✓ Aliases added successfully to $SHELL_RC"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Available Aliases"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  ssd            - Interactive dashboard (main menu)"
echo "  ssd-check      - Full disk analysis"
echo "  ssd-quick      - Quick check (summary)"
echo "  ssd-speed      - Full analysis + speed test"
echo "  ssd-temp       - View temperatures of both disks"
echo "  ssd-health     - View SMART status of both disks"
echo "  ssd-info       - View information of both disks"
echo "  ssd-eject      - Safely eject secondary disk"
echo "  ssd-history    - View metrics history"
echo "  ssd-track      - Record current metrics"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "To activate aliases run:"
echo "  source $SHELL_RC"
echo ""
echo "Or simply open a new terminal."
echo ""
