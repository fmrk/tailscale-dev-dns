#!/bin/bash

# Tailscale Dev DNS Dashboard
# Shows comprehensive status of all components

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Icons
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
CERT="🔒"
NETWORK="🌐"
CLOCK="⏱️"

# Clear screen for clean display
clear

# Header
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║         Tailscale Dev DNS - System Dashboard                   ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${DIM}Last updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# Function to print status line
print_status() {
    local status=$1
    local service=$2
    local detail=$3

    if [ "$status" = "ok" ]; then
        echo -e "${CHECK} ${BOLD}${service}${NC}: ${GREEN}${detail}${NC}"
    elif [ "$status" = "warning" ]; then
        echo -e "${WARNING} ${BOLD}${service}${NC}: ${YELLOW}${detail}${NC}"
    elif [ "$status" = "error" ]; then
        echo -e "${CROSS} ${BOLD}${service}${NC}: ${RED}${detail}${NC}"
    else
        echo -e "${INFO} ${BOLD}${service}${NC}: ${detail}"
    fi
}

# Function to print section header
print_section() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ $1 ━━━${NC}"
    echo ""
}

# ============================================
# CONFIGURATION STATUS
# ============================================
print_section "${GEAR} Configuration"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env" 2>/dev/null || true
    print_status "ok" ".env file" "Found"

    # Show key config values
    echo -e "   ${DIM}Domain Pattern:${NC} ${DOMAIN_PATTERN:-\.dev}"
    echo -e "   ${DIM}Host IP Pattern:${NC} ${HOST_IP_PATTERN:-^(127\.0\.0\.1|10\.0\.0\.1)}"
    echo -e "   ${DIM}Cert Domains:${NC} ${CERT_DOMAINS:-*.dev localhost 127.0.0.1}"
else
    print_status "warning" ".env file" "Not found (using defaults)"
fi

# ============================================
# TAILSCALE STATUS
# ============================================
print_section "${NETWORK} Tailscale"

# Detect Tailscale command
TAILSCALE_CMD=""
if command -v tailscale &> /dev/null; then
    TAILSCALE_CMD="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TAILSCALE_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

if [ -z "$TAILSCALE_CMD" ]; then
    print_status "error" "Tailscale" "Not installed"
else
    print_status "ok" "Tailscale" "Installed ($TAILSCALE_CMD)"

    # Check connection status
    if $TAILSCALE_CMD status &> /dev/null; then
        print_status "ok" "Connection" "Connected"

        # Get Tailscale IP
        TAILSCALE_IP=$($TAILSCALE_CMD ip -4 2>/dev/null | head -1)
        if [ -n "$TAILSCALE_IP" ]; then
            echo -e "   ${DIM}Tailscale IP:${NC} ${GREEN}${TAILSCALE_IP}${NC}"
        fi

        # Show peer count
        PEER_COUNT=$($TAILSCALE_CMD status 2>/dev/null | grep -c "^[^#]" || echo "0")
        if [ "$PEER_COUNT" -gt 1 ]; then
            echo -e "   ${DIM}Network Peers:${NC} $((PEER_COUNT - 1)) online"
        fi
    else
        print_status "error" "Connection" "Not connected"
    fi
fi

# ============================================
# DNSMASQ STATUS
# ============================================
print_section "${ROCKET} dnsmasq DNS Server"

# Check if dnsmasq is installed
if brew list dnsmasq &>/dev/null 2>&1; then
    print_status "ok" "dnsmasq" "Installed"

    # Check if running
    if pgrep dnsmasq > /dev/null; then
        print_status "ok" "Service" "Running"

        # Check brew services status
        BREW_STATUS=$(brew services list 2>/dev/null | grep dnsmasq | awk '{print $2}')
        if [ "$BREW_STATUS" = "started" ]; then
            echo -e "   ${DIM}Service Status:${NC} ${GREEN}Started${NC}"
        else
            echo -e "   ${DIM}Service Status:${NC} ${YELLOW}$BREW_STATUS${NC}"
        fi

        # Show listening addresses
        if [ -f "/opt/homebrew/etc/dnsmasq.conf" ]; then
            LISTEN_ADDRS=$(grep "^listen-address=" /opt/homebrew/etc/dnsmasq.conf 2>/dev/null | cut -d'=' -f2)
            if [ -n "$LISTEN_ADDRS" ]; then
                echo -e "   ${DIM}Listening on:${NC} ${LISTEN_ADDRS}"
            fi
        fi
    else
        print_status "error" "Service" "Not running"
    fi

    # Check configuration
    if [ -f "$CONFIG_DIR/dnsmasq-tailscale.conf" ]; then
        print_status "ok" "Config" "Found ($CONFIG_DIR/dnsmasq-tailscale.conf)"
    else
        print_status "warning" "Config" "Not found"
    fi

    # Check hosts file
    if [ -f "$CONFIG_DIR/hosts" ]; then
        HOST_COUNT=$(wc -l < "$CONFIG_DIR/hosts" | xargs)
        if [ "$HOST_COUNT" -gt 0 ]; then
            print_status "ok" "Hosts file" "$HOST_COUNT domains configured"
        else
            print_status "warning" "Hosts file" "Empty (no domains found)"
        fi
    else
        print_status "warning" "Hosts file" "Not found"
    fi
else
    print_status "error" "dnsmasq" "Not installed"
fi

# ============================================
# CERTIFICATE STATUS
# ============================================
print_section "${CERT} HTTPS Certificates"

CERT_EXPORT_DIR="${CERT_EXPORT_DIR:-$SCRIPT_DIR/certs}"

# Check mkcert installation
if command -v mkcert &> /dev/null; then
    print_status "ok" "mkcert" "Installed"

    # Check CA installation
    CAROOT=$(mkcert -CAROOT 2>/dev/null)
    if [ -d "$CAROOT" ] && [ -f "$CAROOT/rootCA.pem" ]; then
        print_status "ok" "CA Root" "Installed"
        echo -e "   ${DIM}CA Location:${NC} $CAROOT"
    else
        print_status "warning" "CA Root" "Not found"
    fi
else
    print_status "error" "mkcert" "Not installed"
fi

# Check exported certificates
if [ -d "$CERT_EXPORT_DIR" ]; then
    print_status "ok" "Certificate Export" "Directory exists"

    if [ -f "$CERT_EXPORT_DIR/rootCA.crt" ]; then
        print_status "ok" "rootCA.crt" "Available for device installation"

        # Check certificate expiration
        if command -v openssl &> /dev/null && [ -f "$CERT_EXPORT_DIR/cert.pem" ]; then
            CERT_REAL_PATH=$(readlink "$CERT_EXPORT_DIR/cert.pem" 2>/dev/null || echo "$CERT_EXPORT_DIR/cert.pem")
            if [ -f "$CERT_EXPORT_DIR/$CERT_REAL_PATH" ] || [ -f "$CERT_REAL_PATH" ]; then
                # Get the actual file path
                if [ -f "$CERT_EXPORT_DIR/$CERT_REAL_PATH" ]; then
                    CERT_FILE="$CERT_EXPORT_DIR/$CERT_REAL_PATH"
                else
                    CERT_FILE="$CERT_REAL_PATH"
                fi

                EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
                if [ -n "$EXPIRY_DATE" ]; then
                    EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || echo "0")
                    NOW_EPOCH=$(date +%s)
                    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

                    if [ "$DAYS_LEFT" -gt 30 ]; then
                        echo -e "   ${DIM}Expires in:${NC} ${GREEN}${DAYS_LEFT} days${NC}"
                    elif [ "$DAYS_LEFT" -gt 7 ]; then
                        echo -e "   ${DIM}Expires in:${NC} ${YELLOW}${DAYS_LEFT} days${NC}"
                    else
                        echo -e "   ${DIM}Expires in:${NC} ${RED}${DAYS_LEFT} days (renew soon!)${NC}"
                    fi
                fi
            fi
        fi
    else
        print_status "warning" "rootCA.crt" "Not found"
    fi

    echo -e "   ${DIM}Location:${NC} $CERT_EXPORT_DIR"
else
    print_status "warning" "Certificate Export" "Directory not found"
fi

# ============================================
# LAUNCHAGENT STATUS
# ============================================
print_section "${CLOCK} Auto-Update Service"

LAUNCHAGENT_PATH="$HOME/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist"

if [ -f "$LAUNCHAGENT_PATH" ]; then
    print_status "ok" "LaunchAgent" "Configured"

    # Check if loaded
    if launchctl list | grep -q "com.localdev.dnsmasq-hosts-updater"; then
        print_status "ok" "Status" "Active (watching /etc/hosts)"
    else
        print_status "warning" "Status" "Not loaded"
    fi

    # Check update script
    if [ -f "$CONFIG_DIR/update-hosts.sh" ]; then
        print_status "ok" "Update Script" "Found"

        # Show last update time
        if [ -f "$CONFIG_DIR/updater.out" ]; then
            LAST_UPDATE=$(tail -1 "$CONFIG_DIR/updater.out" 2>/dev/null | grep "Updated dnsmasq" || echo "")
            if [ -n "$LAST_UPDATE" ]; then
                echo -e "   ${DIM}Last activity:${NC}"
                echo -e "   ${DIM}$(tail -3 "$CONFIG_DIR/updater.out" 2>/dev/null | sed 's/^/   /')${NC}"
            fi
        fi

        # Show any recent errors
        if [ -f "$CONFIG_DIR/updater.err" ] && [ -s "$CONFIG_DIR/updater.err" ]; then
            print_status "warning" "Errors" "Check $CONFIG_DIR/updater.err"
        fi
    else
        print_status "warning" "Update Script" "Not found"
    fi
else
    print_status "error" "LaunchAgent" "Not configured"
fi

# ============================================
# SYSTEM HEALTH CHECK
# ============================================
print_section "${INFO} Quick Health Check"

# Test DNS resolution if everything is set up
if [ -n "$TAILSCALE_CMD" ] && [ -n "$TAILSCALE_IP" ] && pgrep dnsmasq > /dev/null && [ -f "$CONFIG_DIR/hosts" ]; then
    # Try to find a test domain
    TEST_DOMAIN=$(head -1 "$CONFIG_DIR/hosts" 2>/dev/null | awk '{print $2}')

    if [ -n "$TEST_DOMAIN" ]; then
        if command -v dig &> /dev/null; then
            RESOLVED=$(dig @"$TAILSCALE_IP" "$TEST_DOMAIN" +short 2>/dev/null | head -1)
            if [ -n "$RESOLVED" ]; then
                print_status "ok" "DNS Test" "$TEST_DOMAIN → $RESOLVED"
            else
                print_status "warning" "DNS Test" "Failed to resolve $TEST_DOMAIN"
            fi
        else
            print_status "info" "DNS Test" "dig not available"
        fi
    else
        print_status "info" "DNS Test" "No test domains configured"
    fi
else
    print_status "warning" "System" "Setup incomplete - run 'make setup'"
fi

# ============================================
# QUICK ACTIONS
# ============================================
print_section "${INFO} Quick Actions"

echo -e "   ${BLUE}make setup${NC}        - Run/update setup"
echo -e "   ${BLUE}make config${NC}       - Configure settings"
echo -e "   ${BLUE}make restart${NC}      - Restart dnsmasq"
echo -e "   ${BLUE}make logs${NC}         - View dnsmasq logs"
echo -e "   ${BLUE}make test${NC}         - Test DNS resolution"
echo -e "   ${BLUE}make cleanup${NC}      - Remove configuration"

# ============================================
# FOOTER
# ============================================
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${DIM}Press Ctrl+C to exit | Run 'make dashboard' to refresh${NC}"
echo ""
