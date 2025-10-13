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
echo "  1) Remove configuration only (keep dnsmasq installed)"
echo "  2) Remove all (configuration + uninstall dnsmasq + remove certs)"
echo "  3) Cancel"
echo ""
echo -e "${YELLOW}Note:${NC} Tailscale is managed separately and won't be touched"
echo ""
read -p "Enter your choice (1-3): " -n 1 -r CHOICE
echo ""

if [ "$CHOICE" = "3" ]; then
    echo "Cancelled."
    exit 0
fi

# Create backup before cleanup
BACKUP_DIR="$HOME/proxy-certs/backups/cleanup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
print_info "Creating backup in $BACKUP_DIR..."

# Get script directory to find config folder
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$REPO_DIR/config"

# Backup configurations if they exist
if [ -f "/opt/homebrew/etc/dnsmasq.conf" ]; then
    cp /opt/homebrew/etc/dnsmasq.conf "$BACKUP_DIR/" 2>/dev/null || true
fi

# Backup project config folder
if [ -d "$CONFIG_DIR" ]; then
    cp -r "$CONFIG_DIR" "$BACKUP_DIR/" 2>/dev/null || true
fi

# Backup .env file
if [ -f "$REPO_DIR/.env" ]; then
    cp "$REPO_DIR/.env" "$BACKUP_DIR/" 2>/dev/null || true
fi

# Backup old system files (for backwards compatibility)
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

# Remove project config folder
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    print_success "Removed project config folder"
fi

# Remove .env configuration file
if [ -f "$REPO_DIR/.env" ]; then
    print_info "Remove .env configuration? (y/n): "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$REPO_DIR/.env"
        print_success "Removed .env configuration"
    else
        print_info "Kept .env configuration"
    fi
fi

# Remove old system files (backwards compatibility)
if [ -f "/opt/homebrew/etc/update-dnsmasq-hosts.sh" ]; then
    rm /opt/homebrew/etc/update-dnsmasq-hosts.sh
    print_success "Removed old update script"
fi

if [ -f "/opt/homebrew/etc/dnsmasq-tailscale-hosts" ]; then
    rm /opt/homebrew/etc/dnsmasq-tailscale-hosts
    print_success "Removed old hosts file"
fi

if [ -f "/opt/homebrew/etc/dnsmasq-tailscale.conf" ]; then
    rm /opt/homebrew/etc/dnsmasq-tailscale.conf
    print_success "Removed old config file"
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

# Option 2: Uninstall dnsmasq
if [ "$CHOICE" = "2" ]; then
    print_info "Stopping and uninstalling dnsmasq..."
    if brew services list | grep -q "dnsmasq.*started"; then
        sudo brew services stop dnsmasq
        print_success "dnsmasq service stopped"
    fi

    if brew list dnsmasq &>/dev/null; then
        brew uninstall dnsmasq
        print_success "dnsmasq uninstalled"

        # Clean up remaining files
        if [ -f "/opt/homebrew/etc/dnsmasq-hosts" ]; then
            rm /opt/homebrew/etc/dnsmasq-hosts
            print_success "Removed dnsmasq-hosts"
        fi

        if [ -d "/opt/homebrew/etc/dnsmasq.d" ]; then
            rm -rf /opt/homebrew/etc/dnsmasq.d
            print_success "Removed dnsmasq.d directory"
        fi
    else
        print_info "dnsmasq was not installed"
    fi
fi

# Option 2: Remove certificates and mkcert
if [ "$CHOICE" = "2" ]; then
    print_info "Removing certificates..."
    if [ -d "$REPO_DIR/certs" ]; then
        rm -rf "$REPO_DIR/certs"
        print_success "Removed certificates directory"
    fi

    print_info "Uninstalling mkcert local CA..."
    if command -v mkcert &> /dev/null; then
        mkcert -uninstall
        print_success "Uninstalled mkcert CA"
    fi
fi

# Final summary
echo ""
echo "============================================"
echo "            Cleanup Complete! 🧹             "
echo "============================================"
echo ""

case "$CHOICE" in
    1)
        print_success "Removed configuration only"
        echo "• LaunchAgent removed"
        echo "• Config files removed"
        echo "• dnsmasq is still installed"
        echo "• Tailscale is still installed"
        echo ""
        echo -e "To completely remove: ${YELLOW}make cleanup${NC} (choose option 2)"
        ;;
    2)
        print_success "Removed everything except Tailscale"
        echo "• Configuration removed"
        echo "• dnsmasq uninstalled"
        echo "• Certificates removed"
        echo "• Tailscale is still installed"
        ;;
esac

echo ""
echo -e "📁 ${GREEN}Backup location:${NC}"
echo "   $BACKUP_DIR"
echo ""

# Clean up temp files
rm -f /tmp/dnsmasq-updater.err /tmp/dnsmasq-updater.out 2>/dev/null || true

echo "============================================"