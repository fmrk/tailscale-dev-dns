#!/bin/bash

# Tailscale + dnsmasq Integration Script
# Makes your Mac a DNS server for your Tailscale network
# Automatically serves all /etc/hosts entries to Tailscale devices

set -e

# Load .env file if it exists
if [ -f "$(dirname "$0")/.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/.env" | xargs)
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration with defaults
DOMAIN_PATTERN="${DOMAIN_PATTERN:-\.dev}"
HOST_IP_PATTERN="${HOST_IP_PATTERN:-^(127\.0\.0\.1|10\.0\.0\.1)}"
CERT_DOMAINS="${CERT_DOMAINS:-*.dev localhost 127.0.0.1}"
CERT_EXPORT_DIR="${CERT_EXPORT_DIR:-$SCRIPT_DIR/certs}"

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

# Validate regex patterns
print_info "Validating configuration..."
if ! echo "test.dev" | grep -qE "$DOMAIN_PATTERN" 2>/dev/null && \
   ! echo "app.local.dev" | grep -qE "$DOMAIN_PATTERN" 2>/dev/null; then
    print_warning "DOMAIN_PATTERN may not match any domains: $DOMAIN_PATTERN"
    echo "Common patterns: \.dev | \.(dev|local) | \.local\.dev"
fi

if ! echo "127.0.0.1" | grep -qE "$HOST_IP_PATTERN" 2>/dev/null && \
   ! echo "10.0.0.1" | grep -qE "$HOST_IP_PATTERN" 2>/dev/null; then
    print_warning "HOST_IP_PATTERN may not match typical IPs: $HOST_IP_PATTERN"
    echo "Common patterns: ^127\.0\.0\.1 | ^(127\.0\.0\.1|10\.0\.0\.1)"
fi

# Header
clear
echo "============================================"
echo "   Tailscale + dnsmasq DNS Server Setup     "
echo "============================================"
echo ""

# Check if Tailscale is available (GUI app or CLI)
TAILSCALE_CMD=""
if command -v tailscale &> /dev/null; then
    TAILSCALE_CMD="tailscale"
elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then
    TAILSCALE_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
else
    print_warning "Tailscale is not installed."
    echo ""
    echo "Please install the official Tailscale app:"
    echo -e "1. Go to: ${YELLOW}https://tailscale.com/download/mac${NC}"
    echo "2. Download and install Tailscale.app"
    echo "3. Launch the app and sign in"
    echo "4. Run this script again"
    echo ""
    echo "Alternative (CLI only):"
    echo -e "  ${YELLOW}brew install tailscale${NC}"
    echo -e "  ${YELLOW}sudo brew services start tailscale${NC}"
    echo -e "  ${YELLOW}$TAILSCALE_CMD up${NC}"
    echo ""
    exit 0
fi

print_info "Found Tailscale: $TAILSCALE_CMD"

# Check if Tailscale is connected
if ! $TAILSCALE_CMD status &> /dev/null; then
    print_error "Tailscale is not connected. Please authenticate first:"
    echo ""
    echo "If using the GUI app:"
    echo "1. Launch Tailscale.app from Applications"
    echo "2. Sign in to your account (or create one)"
    echo "3. Ensure it shows 'Connected' in the menu bar"
    echo ""
    echo "If using CLI version:"
    echo -e "  ${YELLOW}$TAILSCALE_CMD up${NC} (may require daemon restart)"
    echo ""
    echo "After connecting, run this script again."
    exit 1
fi

# Get Tailscale IP
print_info "Getting Tailscale IP address..."
TAILSCALE_IP=$($TAILSCALE_CMD ip -4 2>/dev/null | head -1)

if [ -z "$TAILSCALE_IP" ]; then
    print_error "Could not get Tailscale IP. Is Tailscale running?"
    exit 1
fi

print_success "Your Tailscale IP: $TAILSCALE_IP"

# Setup HTTPS certificates with mkcert
echo ""
print_info "Setting up HTTPS certificates with mkcert..."

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    print_info "Installing mkcert..."
    brew install mkcert nss
    print_success "mkcert installed"
else
    print_info "mkcert is already installed"
fi

# Install local CA
print_info "Installing local Certificate Authority..."
mkcert -install

# Create certificate export directory
mkdir -p "$CERT_EXPORT_DIR"

# Generate wildcard certificate
print_info "Generating certificates for: $CERT_DOMAINS"
cd "$CERT_EXPORT_DIR"
mkcert $CERT_DOMAINS

# Find the generated cert and key files
CERT_FILE=$(ls -t "$CERT_EXPORT_DIR"/*+*.pem 2>/dev/null | head -1)
KEY_FILE=$(ls -t "$CERT_EXPORT_DIR"/*+*-key.pem 2>/dev/null | head -1)

if [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ]; then
    # Create symlinks with predictable names
    ln -sf "$(basename "$CERT_FILE")" "$CERT_EXPORT_DIR/cert.pem"
    ln -sf "$(basename "$KEY_FILE")" "$CERT_EXPORT_DIR/key.pem"
    print_success "Certificates generated in: $CERT_EXPORT_DIR"
else
    print_warning "Certificate generation may have failed, check $CERT_EXPORT_DIR"
fi

# Export CA certificate for other devices
CAROOT=$(mkcert -CAROOT)
cp "$CAROOT/rootCA.pem" "$CERT_EXPORT_DIR/rootCA.pem"
cp "$CAROOT/rootCA.pem" "$CERT_EXPORT_DIR/rootCA.crt"
print_success "CA certificate exported to: $CERT_EXPORT_DIR/rootCA.crt"

cd - > /dev/null

# Get all local network IPs
print_info "Detecting all network interfaces..."
LOCAL_IPS="127.0.0.1"

# Get LAN IP from en0/en1
for interface in en0 en1; do
    IP=$(ifconfig $interface 2>/dev/null | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}')
    if [ -n "$IP" ]; then
        LOCAL_IPS="$LOCAL_IPS,$IP"
        print_info "Found IP on $interface: $IP"
    fi
done

# Add Tailscale IP
LOCAL_IPS="$LOCAL_IPS,$TAILSCALE_IP"

# Check if dnsmasq is installed
if ! brew list dnsmasq &>/dev/null; then
    print_info "Installing dnsmasq..."
    brew install dnsmasq
    print_success "dnsmasq installed"
else
    print_info "dnsmasq is already installed"
fi

# Create project config directory
CONFIG_DIR="$SCRIPT_DIR/config"
mkdir -p "$CONFIG_DIR"
print_success "Created config directory: $CONFIG_DIR"

# Backup existing configuration
BACKUP_DIR="$HOME/proxy-certs/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -f "/opt/homebrew/etc/dnsmasq.conf" ]; then
    print_info "Backing up existing configuration..."
    cp /opt/homebrew/etc/dnsmasq.conf "$BACKUP_DIR/dnsmasq.conf.backup"
fi

# Create dnsmasq configuration for Tailscale
print_info "Configuring dnsmasq for Tailscale..."

# Check if we already have custom configuration
if grep -q "# Tailscale DNS Configuration" /opt/homebrew/etc/dnsmasq.conf 2>/dev/null; then
    print_info "Updating existing Tailscale configuration..."
    # Remove old Tailscale configuration
    sed -i '' '/# Tailscale DNS Configuration/,/# End Tailscale Configuration/d' /opt/homebrew/etc/dnsmasq.conf
fi

# Add Tailscale configuration that points to project folder
cat >> /opt/homebrew/etc/dnsmasq.conf << EOF

# Tailscale DNS Configuration
# Added on $(date)
# This configuration makes your Mac a DNS server for your Tailscale network
# Project location: $CONFIG_DIR

# Listen on all necessary interfaces
listen-address=$LOCAL_IPS

# Use Tailscale-specific hosts file (check if exists to prevent dnsmasq crash)
no-hosts  # Don't read /etc/hosts directly
conf-file=$CONFIG_DIR/dnsmasq-tailscale.conf

# End Tailscale Configuration
EOF

# Create project-specific dnsmasq config with safety checks
cat > "$CONFIG_DIR/dnsmasq-tailscale.conf" << EOF
# Tailscale DNS Configuration
# Generated on $(date)
# Safe to delete - dnsmasq will continue working without this file

# Only load hosts file if it exists
addn-hosts=$CONFIG_DIR/hosts

# For all other queries, forward to upstream DNS
server=1.1.1.1
server=8.8.8.8

# Cache settings
cache-size=1000

# Log queries (uncomment for debugging)
# log-queries
# log-facility=$CONFIG_DIR/dnsmasq.log
EOF

print_success "dnsmasq configured"

# Create tailscale-specific hosts file
print_info "Creating Tailscale hosts file..."

# Generate hosts file with Tailscale IP for all local domains matching patterns
grep -E "$HOST_IP_PATTERN" /etc/hosts | grep -E "$DOMAIN_PATTERN" | awk -v ip="$TAILSCALE_IP" '{$1=ip; print}' > "$CONFIG_DIR/hosts"

print_success "Generated hosts file with $(wc -l < "$CONFIG_DIR/hosts" | xargs) entries"

# Create update script in project folder
cat > "$CONFIG_DIR/update-hosts.sh" << EOF
#!/bin/bash
# This script updates dnsmasq hosts file with current Tailscale IP
# Project location: $CONFIG_DIR

# Load configuration
DOMAIN_PATTERN="${DOMAIN_PATTERN}"
HOST_IP_PATTERN="${HOST_IP_PATTERN}"
CONFIG_DIR="$CONFIG_DIR"

TAILSCALE_IP=\$(${TAILSCALE_CMD} ip -4 2>/dev/null | head -1)

if [ -z "\$TAILSCALE_IP" ]; then
    echo "Error: Could not get Tailscale IP"
    exit 1
fi

# Generate hosts file with current Tailscale IP matching configured patterns
grep -E "\$HOST_IP_PATTERN" /etc/hosts | grep -E "\$DOMAIN_PATTERN" | awk -v ip="\$TAILSCALE_IP" '{\$1=ip; print}' > "\$CONFIG_DIR/hosts"

echo "Updated dnsmasq hosts with Tailscale IP: \$TAILSCALE_IP"
echo "Domain pattern: \$DOMAIN_PATTERN"
echo "Host IP pattern: \$HOST_IP_PATTERN"
echo "Entries: \$(wc -l < "\$CONFIG_DIR/hosts" | xargs)"

# Restart dnsmasq if it's running
if pgrep dnsmasq > /dev/null; then
    sudo brew services restart dnsmasq
fi
EOF

chmod +x "$CONFIG_DIR/update-hosts.sh"

print_success "Created update script: $CONFIG_DIR/update-hosts.sh"

# Set up automatic updates when /etc/hosts changes
print_info "Setting up automatic hosts file updates..."

# Create a LaunchAgent to watch /etc/hosts for changes
cat > ~/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.localdev.dnsmasq-hosts-updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CONFIG_DIR/update-hosts.sh</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/etc/hosts</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/updater.err</string>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/updater.out</string>
</dict>
</plist>
EOF

# Load the LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.localdev.dnsmasq-hosts-updater.plist

print_success "Automatic hosts file syncing enabled"

# Start dnsmasq as daemon
print_info "Starting dnsmasq service (requires sudo)..."
echo "Please enter your password to start dnsmasq:"
sudo brew services start dnsmasq

sleep 2

# Configure Tailscale to advertise this machine as a DNS server
print_info "Configuring Tailscale..."

# Enable IP forwarding
sudo sysctl -w net.inet.ip.forwarding=1 > /dev/null 2>&1 || true

# Advertise routes and accept DNS
print_info "Updating Tailscale configuration..."
$TAILSCALE_CMD up --accept-routes --accept-dns=false

# Test DNS resolution
print_info "Testing DNS resolution..."

# Test with domain matching the configured pattern
TEST_DOMAIN=$(grep -E "$HOST_IP_PATTERN" /etc/hosts | grep -E "$DOMAIN_PATTERN" | head -1 | awk '{print $2}' 2>/dev/null)
if [ -n "$TEST_DOMAIN" ]; then
    RESOLVED=$(dig @"$TAILSCALE_IP" "$TEST_DOMAIN" +short 2>/dev/null | head -1)
    if [ -n "$RESOLVED" ]; then
        print_success "DNS test successful: $TEST_DOMAIN → $RESOLVED"
    else
        print_warning "DNS test failed for $TEST_DOMAIN"
    fi
else
    print_info "No domains matching pattern '$DOMAIN_PATTERN' found in /etc/hosts to test"
fi

# Generate Tailscale DNS configuration for clients
echo ""
echo "============================================"
echo "    Tailscale DNS Setup Complete! 🎉        "
echo "============================================"
echo ""
print_success "Your Mac is now a DNS server for your Tailscale network"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  Configure Tailscale DNS (Required)"
echo ""
echo -e "   Go to: ${YELLOW}https://login.tailscale.com/admin/dns${NC}"
echo ""
echo -e "   Add nameserver: ${GREEN}$TAILSCALE_IP${NC}"
echo -e "   Enable: ${YELLOW}Override local DNS${NC}"
echo ""
echo "2️⃣  Install HTTPS Certificate on Devices (Optional)"
echo ""
echo -e "   Certificate: ${GREEN}$CERT_EXPORT_DIR/rootCA.crt${NC}"
echo "   Transfer via AirDrop, email, or USB"
echo ""
echo "   • macOS: Double-click → Keychain → Trust"
echo "   • iOS: Install profile → Settings → Trust"
echo "   • Android: Settings → Security → Install cert"
echo ""
echo "3️⃣  Test from Another Device"
echo ""
echo "   On your phone or another computer:"
if [ -n "$TEST_DOMAIN" ]; then
echo -e "   ${YELLOW}ping $(echo "$TEST_DOMAIN" | awk '{print $1}')${NC}"
echo -e "   ${YELLOW}curl http://$(echo "$TEST_DOMAIN" | awk '{print $1}')${NC}"
else
echo -e "   ${YELLOW}ping yourdomain.dev${NC}"
echo -e "   ${YELLOW}curl http://yourdomain.dev${NC}"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "📁 Files: ${GREEN}$CONFIG_DIR${NC}"
echo -e "🔧 Status: ${YELLOW}make status${NC}"
echo -e "⚙️  Config: ${YELLOW}make config${NC}"
echo ""
echo "============================================"