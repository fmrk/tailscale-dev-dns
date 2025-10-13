#!/bin/bash

# Interactive Setup Script for Tailscale DNS
# Provides guided setup with auto-detection and smart defaults

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Tailscale Dev DNS - Interactive Setup       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "\n${BLUE}▸ $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

# Auto-detect domains from /etc/hosts
detect_domains() {
    print_step "Scanning /etc/hosts for local domains..."

    # Find all domains (excluding localhost, comments, and standard entries)
    DETECTED_DOMAINS=$(grep -v '^#' /etc/hosts 2>/dev/null | \
                   grep -v '^$' | \
                   awk '{for(i=2;i<=NF;i++) print $i}' | \
                   grep -E '\.' | \
                   grep -v '^localhost' | \
                   grep -v '^ip6-' | \
                   grep -v '^broadcasthost' | \
                   sort -u)

    if [ -z "$DETECTED_DOMAINS" ]; then
        echo "  No domains found in /etc/hosts"
        return 1
    fi

    # Analyze domain patterns
    local dev_count=$(echo "$DETECTED_DOMAINS" | grep -c '\.dev$' 2>/dev/null | head -1)
    local local_dev_count=$(echo "$DETECTED_DOMAINS" | grep -c '\.local\.dev$' 2>/dev/null | head -1)
    local local_count=$(echo "$DETECTED_DOMAINS" | grep -c '\.local$' 2>/dev/null | head -1)

    # Ensure they're numbers
    dev_count=${dev_count:-0}
    local_dev_count=${local_dev_count:-0}
    local_count=${local_count:-0}

    echo "  Found domains:"
    echo "$DETECTED_DOMAINS" | head -10 | sed 's/^/    • /'

    local total_count=$(echo "$DETECTED_DOMAINS" | wc -l | xargs)
    if [ "$total_count" -gt 10 ]; then
        echo "    ... and $(($total_count - 10)) more"
    fi
    echo ""

    # Suggest pattern based on analysis
    if [ "$local_dev_count" -gt 0 ]; then
        SUGGESTED_DOMAIN_PATTERN="\.local\.dev"
        SUGGESTED_CERT_DOMAIN="*.local.dev"
    elif [ "$dev_count" -gt 0 ]; then
        SUGGESTED_DOMAIN_PATTERN="\.dev"
        SUGGESTED_CERT_DOMAIN="*.dev"
    elif [ "$local_count" -gt 0 ]; then
        SUGGESTED_DOMAIN_PATTERN="\.(dev|local)"
        SUGGESTED_CERT_DOMAIN="*.dev *.local"
    else
        # Check first domain's TLD
        local first_tld=$(echo "$DETECTED_DOMAINS" | head -1 | rev | cut -d'.' -f1 | rev)
        SUGGESTED_DOMAIN_PATTERN="\.$first_tld"
        SUGGESTED_CERT_DOMAIN="*.$first_tld"
    fi

    print_success "Detected pattern: $SUGGESTED_DOMAIN_PATTERN"

    return 0
}

# Detect IPs from /etc/hosts
detect_ips() {
    local ips=$(grep -v '^#' /etc/hosts 2>/dev/null | \
               grep -v '^$' | \
               awk '{print $1}' | \
               grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | \
               sort -u | \
               grep -v '^127\.0\.0\.1$')

    if [ -n "$ips" ]; then
        echo "  Found IPs in /etc/hosts:"
        echo "$ips" | sed 's/^/    • /'

        # Build pattern from found IPs
        SUGGESTED_IP_PATTERN="^(127\.0\.0\.1"
        for ip in $ips; do
            escaped_ip=$(echo "$ip" | sed 's/\./\\./g')
            SUGGESTED_IP_PATTERN="$SUGGESTED_IP_PATTERN|$escaped_ip"
        done
        SUGGESTED_IP_PATTERN="$SUGGESTED_IP_PATTERN)"
    else
        SUGGESTED_IP_PATTERN="^127\.0\.0\.1"
    fi
}

# Main interactive flow
print_header

echo "This wizard will help you configure Tailscale DNS for your local development domains."
echo ""
read -p "Press Enter to continue..."

# Step 1: Detect and configure domains
print_header
if detect_domains; then
    echo ""
    echo -e "Suggested domain pattern: ${GREEN}$SUGGESTED_DOMAIN_PATTERN${NC}"
    echo -e "This will match domains like: ${YELLOW}$(echo "$DETECTED_DOMAINS" | head -3 | tr '\n' ' ')${NC}"
    echo ""
    read -p "Use this pattern? (Y/n): " use_suggested

    if [[ ! "$use_suggested" =~ ^[Nn] ]]; then
        DOMAIN_PATTERN="$SUGGESTED_DOMAIN_PATTERN"
        CERT_DOMAINS="$SUGGESTED_CERT_DOMAIN localhost 127.0.0.1"
    else
        echo ""
        echo "Common patterns:"
        echo "  • \.dev              (all .dev domains)"
        echo "  • \.local\.dev       (only .local.dev)"
        echo "  • \.(dev|local)      (.dev and .local domains)"
        echo ""
        read -p "Enter domain pattern: " DOMAIN_PATTERN
        read -p "Enter certificate domains (space-separated): " CERT_DOMAINS
    fi
else
    echo ""
    echo -e "Using default pattern: ${GREEN}\.dev${NC}"
    echo ""
    read -p "Change it? (y/N): " change_default

    if [[ "$change_default" =~ ^[Yy] ]]; then
        read -p "Enter domain pattern: " DOMAIN_PATTERN
        read -p "Enter certificate domains: " CERT_DOMAINS
    else
        DOMAIN_PATTERN="\.dev"
        CERT_DOMAINS="*.dev localhost 127.0.0.1"
    fi
fi

# Step 2: Detect and configure IPs
print_header
print_step "Configuring source IPs..."

detect_ips

echo ""
echo -e "Suggested IP pattern: ${GREEN}$SUGGESTED_IP_PATTERN${NC}"
echo "This will match /etc/hosts entries from these IPs"
echo ""
read -p "Use this pattern? (Y/n): " use_ip_suggested

if [[ "$use_ip_suggested" =~ ^[Nn] ]]; then
    echo ""
    echo "Common patterns:"
    echo "  • ^127\.0\.0\.1              (localhost only)"
    echo "  • ^(127\.0\.0\.1|10\.0\.0\.1)  (localhost + proxy)"
    echo ""
    read -p "Enter IP pattern: " HOST_IP_PATTERN
else
    HOST_IP_PATTERN="$SUGGESTED_IP_PATTERN"
fi

# Step 3: HTTPS Configuration
print_header
print_step "HTTPS Certificate Configuration"

echo "Generate HTTPS certificates with mkcert?"
echo "This allows accessing your sites via https:// without browser warnings."
echo ""
read -p "Generate certificates? (Y/n): " gen_certs

if [[ "$gen_certs" =~ ^[Nn] ]]; then
    SKIP_CERTS="true"
else
    SKIP_CERTS="false"
fi

# Step 4: Summary and confirmation
print_header
print_step "Configuration Summary"

echo -e "Domain Pattern:     ${GREEN}$DOMAIN_PATTERN${NC}"
echo -e "IP Pattern:         ${GREEN}$HOST_IP_PATTERN${NC}"
echo -e "Certificate Domains: ${GREEN}$CERT_DOMAINS${NC}"
echo -e "Generate Certs:     ${GREEN}$([ "$SKIP_CERTS" = "false" ] && echo "Yes" || echo "No")${NC}"
echo -e "Cert Location:      ${GREEN}./certs/${NC}"
echo ""
read -p "Proceed with installation? (Y/n): " confirm

if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Step 5: Create .env file
print_header
print_step "Creating configuration..."

cat > "$REPO_DIR/.env" <<EOF
# Generated by interactive setup on $(date)

DOMAIN_PATTERN="$DOMAIN_PATTERN"
HOST_IP_PATTERN="$HOST_IP_PATTERN"
CERT_DOMAINS="$CERT_DOMAINS"
CERT_EXPORT_DIR="./certs"
EOF

print_success "Configuration saved to .env"

# Step 6: Run setup script
print_step "Running setup script..."
echo ""

export SKIP_CERTS="$SKIP_CERTS"
bash "$SCRIPT_DIR/setup-tailscale-dns.sh"

# Done
echo ""
print_header
print_success "Interactive setup complete!"
echo ""
echo "Next steps:"
echo "  1. Configure DNS in Tailscale admin console"
echo "  2. Install rootCA.crt on your devices (if HTTPS enabled)"
echo "  3. Test with: ${YELLOW}make test${NC}"
echo ""
echo "Configuration saved in .env - you can edit it anytime."
echo ""
