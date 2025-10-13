# Local Dev Environment - Tailscale DNS Setup

Access your local development domains (e.g., `*.local.dev`) from any device, anywhere in the world using Tailscale VPN + DNS.

## Files

### ⚙️ `.env` (optional)
**Configuration file** - Customize which domains are served via DNS.

Create a `.env` file from the example:
```bash
cp .env.example .env
```

**Configuration options:**
- `DOMAIN_PATTERN` - Regex to match domains (default: `\.dev`)
- `HOST_IP_PATTERN` - Regex to match source IPs in /etc/hosts (default: `^(127\.0\.0\.1|10\.0\.0\.1)`)

See [.env.example](.env.example) for more details.

### 📜 `setup-tailscale-dns.sh`
**Main setup script** - Sets up your Mac as a DNS server for your Tailscale network.

**What it does:**
- Installs and configures Tailscale (if needed)
- Installs and configures dnsmasq as DNS server
- Makes all your `/etc/hosts` entries accessible via Tailscale
- Auto-syncs changes to `/etc/hosts`
- Configures your Mac to serve DNS on your Tailscale IP

**Usage:**
```bash
./setup-tailscale-dns.sh
```

**After setup:**
- Your iPhone/iPad can access your local dev domains from anywhere
- Other devices can join your tailnet and access local dev domains
- Works over cellular, coffee shop WiFi, etc.

### 🧹 `cleanup-tailscale-dns.sh`
**Cleanup script** - Removes the Tailscale DNS configuration (with options).

**Cleanup levels:**
1. Remove DNS config only (keep Tailscale & dnsmasq)
2. Remove config + stop dnsmasq
3. Remove config + uninstall dnsmasq
4. Remove everything (full cleanup)

**Usage:**
```bash
./cleanup-tailscale-dns.sh
```

**Features:**
- Interactive prompts
- Creates backups before removal
- Shows restoration instructions

## HTTPS Support

For full HTTPS support (accessing `https://yourapp.local.dev` without certificate warnings):

- **Install your local development CA certificate** on each device
- **Certificate location**: Usually in your local dev environment setup (e.g., `~/proxy-certs/`)
- **Transfer method**: AirDrop, email, or file sharing to other devices
- **Installation**: Follow your device's certificate installation process

Without the certificate, you can still access sites via HTTP or accept certificate warnings.

## Quick Start

### 1. Configure (Optional)
```bash
# Copy example config and customize patterns
cp .env.example .env
# Edit .env to match your domain patterns
```

### 2. Setup DNS Server on Mac
```bash
./setup-tailscale-dns.sh
```

### 3. Configure DNS for All Devices (One-time setup)
**Tailscale Admin Console (Recommended):**
1. Go to https://login.tailscale.com/admin/dns
2. Under "Nameservers" click "Add nameserver"
3. Enter your Mac's Tailscale IP (shown in script output)
4. Enable "Override local DNS"
5. Save

This automatically configures DNS for ALL devices in your tailnet!

### 4. Setup iPhone/iPad
1. Download Tailscale app from App Store
2. Sign in with your account (create one if needed)  
3. Connect - DNS is automatic via admin console setup above

### 5. Setup Other Devices

**Mac:**
```bash
# Install and setup Tailscale
brew install tailscale
tailscale up

# DNS is automatic via admin console setup above
```

**Windows:**
1. Download and install Tailscale from https://tailscale.com/download/windows
2. Login with same account
3. DNS is automatic via admin console setup above

**Android:**
1. Install Tailscale app from Play Store
2. Login with same account
3. DNS is automatic via admin console setup above

### 6. Test
From any Tailscale device:
```bash
# Test DNS resolution
dig yourapp.local.dev

# Test HTTP access
curl http://yourapp.local.dev

# Or test in browser
open http://yourapp.local.dev
```

## How It Works

1. **Tailscale** creates a private network between your devices
2. **dnsmasq** on your Mac serves DNS for .dev domains  
3. **Automatic sync** keeps DNS updated when you change /etc/hosts
4. **Certificate** enables HTTPS access without warnings

## Benefits vs LAN-only Setup

- ✅ Works from anywhere (not just home WiFi)
- ✅ Encrypted connection via Tailscale
- ✅ No manual IP configuration needed
- ✅ Automatic updates when /etc/hosts changes
- ✅ Centralized DNS management

## Troubleshooting

**DNS not working:**
```bash
# Check Tailscale status
tailscale status

# Check dnsmasq
ps aux | grep dnsmasq

# Test DNS manually
dig @$(tailscale ip -4) yourapp.local.dev
```

**Certificate errors:**
- Ensure your local CA certificate is installed AND trusted
- Check Certificate Trust Settings on iOS (Settings > General > About > Certificate Trust Settings)
- Verify certificate is in System keychain on Mac