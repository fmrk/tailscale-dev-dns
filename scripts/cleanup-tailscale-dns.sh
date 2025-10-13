#!/bin/bash

# Tailscale + dnsmasq Cleanup Script
# Removes the Tailscale DNS server setup and optionally uninstalls components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Header
clear
echo "============================================"
echo "   Tailscale + dnsmasq Cleanup Script       "
echo "============================================"
echo ""

print_warning "This script will remove the Tailscale DNS server setup"
echo ""
echo "What would you like to do?"
echo "  1) Remove Tailscale DNS configuration only (keep dnsmasq & Tailscale)"
echo "  2) Remove DNS config and stop dnsmasq (keep installed)"
echo "  3) Remove DNS config and uninstall dnsmasq (keep Tailscale)"
echo "  4) Remove everything (DNS, dnsmasq, and Tailscale)"
echo "  5) Cancel"
echo ""
read -p "Enter your choice (1-5): " -n 1 -r CHOICE
echo ""

if [ "$CHOICE" = "5" ]; then
    echo "Cancelled."
    exit 0
fi

# Create backup before cleanup
BACKUP_DIR="$HOME/proxy-certs/backups/cleanup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
print_info "Creating backup in $BACKUP_DIR..."

# Backup configurations if they exist
if [ -f "/opt/homebrew/etc/dnsmasq.conf" ]; then
    cp /opt/homebrew/etc/dnsmasq.conf "$BACKUP_DIR/" 2>/dev/null || true
fi

if [ -f "/opt/homebrew/etc/dnsmasq-tailscale-hosts" ]; then
    cp /opt/homebrew/etc/dnsmasq-tailscale-hosts "$BACKUP_DIR/" 2>/dev/null || true
fi

if [ -f "/opt/homebrew/etc/update-dnsmasq-hosts.sh" ]; then
    cp /opt/homebrew/etc/update-dnsmasq-hosts.sh "$BACKUP_DIR/" 2>/dev/null || true
fi

if [ -f "$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist" ]; then
    cp "$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist" "$BACKUP_DIR/" 2>/dev/null || true
fi

# Step 1: Remove automatic hosts updater (all options)
print_info "Removing automatic hosts file updater..."
if [ -f "$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist" ]; then
    launchctl unload "$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist" 2>/dev/null || true
    rm "$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist"
    print_success "Removed automatic hosts updater"
else
    print_info "Automatic hosts updater not found"
fi

# Remove update script
if [ -f "/opt/homebrew/etc/update-dnsmasq-hosts.sh" ]; then
    rm /opt/homebrew/etc/update-dnsmasq-hosts.sh
    print_success "Removed update script"
fi

# Remove Tailscale hosts file
if [ -f "/opt/homebrew/etc/dnsmasq-tailscale-hosts" ]; then
    rm /opt/homebrew/etc/dnsmasq-tailscale-hosts
    print_success "Removed dnsmasq-tailscale-hosts"
fi

# Step 2: Clean dnsmasq configuration (all options)
if [ -f "/opt/homebrew/etc/dnsmasq.conf" ]; then
    print_info "Cleaning dnsmasq configuration..."
    
    # Remove Tailscale-specific configuration
    if grep -q "# Tailscale DNS Configuration" /opt/homebrew/etc/dnsmasq.conf; then
        sed -i '' '/# Tailscale DNS Configuration/,/# End Tailscale Configuration/d' /opt/homebrew/etc/dnsmasq.conf
        print_success "Removed Tailscale DNS configuration from dnsmasq"
    fi
fi

# Remove dnsmasq-hosts if it exists
if [ -f "/opt/homebrew/etc/dnsmasq-hosts" ]; then
    print_info "Remove dnsmasq-hosts file? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm /opt/homebrew/etc/dnsmasq-hosts
        print_success "Removed dnsmasq-hosts"
    fi
fi

# Options 2, 3, 4: Stop dnsmasq
if [ "$CHOICE" = "2" ] || [ "$CHOICE" = "3" ] || [ "$CHOICE" = "4" ]; then
    print_info "Stopping dnsmasq service..."
    if brew services list | grep -q "dnsmasq.*started"; then
        sudo brew services stop dnsmasq
        print_success "dnsmasq service stopped"
    else
        print_info "dnsmasq service was not running"
    fi
fi

# Option 3, 4: Uninstall dnsmasq
if [ "$CHOICE" = "3" ] || [ "$CHOICE" = "4" ]; then
    print_info "Uninstalling dnsmasq..."
    if brew list dnsmasq &>/dev/null; then
        brew uninstall dnsmasq
        print_success "dnsmasq uninstalled"
        
        # Clean up any remaining files
        if [ -d "/opt/homebrew/etc/dnsmasq.d" ]; then
            print_info "Remove dnsmasq.d directory? (y/n): "
            read -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf /opt/homebrew/etc/dnsmasq.d
                print_success "Removed dnsmasq.d directory"
            fi
        fi
    else
        print_info "dnsmasq was not installed"
    fi
fi

# Option 4: Uninstall Tailscale
if [ "$CHOICE" = "4" ]; then
    print_info "Uninstalling Tailscale..."
    print_warning "This will disconnect you from your Tailscale network!"
    echo "Are you sure? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Logout from Tailscale
        if command -v tailscale &> /dev/null; then
            tailscale logout 2>/dev/null || true
        fi
        
        # Quit Tailscale app
        osascript -e 'quit app "Tailscale"' 2>/dev/null || true
        
        # Uninstall via brew
        if brew list tailscale &>/dev/null; then
            brew uninstall tailscale
            print_success "Tailscale uninstalled via Homebrew"
        fi
        
        # Remove Tailscale app if installed separately
        if [ -d "/Applications/Tailscale.app" ]; then
            rm -rf "/Applications/Tailscale.app"
            print_success "Removed Tailscale.app"
        fi
        
        # Clean up Tailscale preferences
        rm -rf ~/Library/Preferences/com.tailscale.ipn.macos.plist 2>/dev/null || true
        rm -rf ~/Library/Application\ Support/Tailscale/ 2>/dev/null || true
        
        print_success "Tailscale uninstalled"
    else
        print_info "Skipped Tailscale uninstallation"
    fi
fi

# Reset DNS settings on current machine
print_info "Reset DNS settings on this Mac? (y/n): "
read -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Reset to automatic DNS
    sudo networksetup -setdnsservers Wi-Fi Empty 2>/dev/null || true
    sudo networksetup -setdnsservers Ethernet Empty 2>/dev/null || true
    print_success "DNS settings reset to automatic"
fi

# Final summary
echo ""
echo "============================================"
echo "            Cleanup Complete! 🧹             "
echo "============================================"
echo ""

case "$CHOICE" in
    1)
        print_success "Removed Tailscale DNS configuration"
        echo "• dnsmasq is still installed and can be used"
        echo "• Tailscale is still installed and connected"
        ;;
    2)
        print_success "Removed DNS configuration and stopped dnsmasq"
        echo "• dnsmasq is installed but not running"
        echo "• To restart: ${YELLOW}sudo brew services start dnsmasq${NC}"
        echo "• Tailscale is still installed and connected"
        ;;
    3)
        print_success "Removed DNS configuration and uninstalled dnsmasq"
        echo "• dnsmasq has been completely removed"
        echo "• Tailscale is still installed and connected"
        ;;
    4)
        print_success "Removed everything"
        echo "• dnsmasq has been uninstalled"
        echo "• Tailscale has been uninstalled"
        echo "• DNS settings reset to automatic"
        ;;
esac

echo ""
echo "📁 ${GREEN}Backup location:${NC}"
echo "   $BACKUP_DIR"
echo ""
echo "To restore from backup:"
echo "   ${YELLOW}cp $BACKUP_DIR/* /opt/homebrew/etc/${NC}"
echo ""

# Clean up temp files
rm -f /tmp/dnsmasq-updater.err /tmp/dnsmasq-updater.out 2>/dev/null || true

# Offer to remove proxy-certs directory if empty
if [ "$CHOICE" = "4" ]; then
    echo "Remove ~/proxy-certs directory? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Keep backups directory
        print_warning "Keeping backups directory. Remove manually if not needed:"
        echo "   ${YELLOW}rm -rf ~/proxy-certs${NC}"
    fi

    echo ""
    echo "Remove certificates directory (./certs)? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        if [ -d "$SCRIPT_DIR/certs" ]; then
            rm -rf "$SCRIPT_DIR/certs"
            print_success "Removed certificates directory"
        fi
    fi

    echo ""
    echo "Uninstall mkcert local CA? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v mkcert &> /dev/null; then
            mkcert -uninstall
            print_success "Uninstalled mkcert CA"
        fi
    fi
fi

echo "============================================"