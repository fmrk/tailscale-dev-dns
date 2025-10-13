# Local Dev Environment - Tailscale DNS Setup

Access your local development domains (e.g., `*.local.dev`) from any device, anywhere in the world using Tailscale VPN + DNS.

## ✨ Features

- 🌐 **Access local dev domains from anywhere** - Works over cellular, coffee shop WiFi, anywhere
- 🔒 **Automatic HTTPS certificates** - mkcert generates trusted certs, no browser warnings
- 🔄 **Auto-sync** - Changes to `/etc/hosts` automatically propagate to all devices
- ⚙️ **Configurable** - Regex patterns for domains and IPs via `.env` file
- 📱 **Multi-device** - iPhone, iPad, Android, Mac, Windows - one setup works everywhere
- 🚀 **One-command setup** - `make setup` does everything
- 🔐 **Private & secure** - Encrypted via Tailscale, only accessible to your devices
- 🎯 **Zero client config** - Set DNS once in Tailscale admin, forget about it

## Quick Usage

```bash
# Smart setup (interactive first time, then uses saved config)
make setup

# Or force interactive setup
make setup-interactive

# Check status
make status

# Test DNS
make test

# Cleanup
make cleanup
```

**Aliases:** `make install` or `make start` (same as `make setup`)

See all available commands: `make help`

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
- `CERT_DOMAINS` - Domains for certificate generation (default: `*.dev localhost 127.0.0.1`)
- `CERT_EXPORT_DIR` - Where to store certificates (default: `./certs`)

See [.env.example](.env.example) for more details.

### 📜 `Makefile`
**Easy command interface** - Simplifies setup and management.

**Available commands:**
- `make setup` - **Smart setup** (interactive first time, then uses .env)
- `make setup-interactive` - Force interactive wizard with auto-detection
- `make start` / `make install` - Aliases for `make setup`
- `make cleanup` - Remove configuration (interactive)
- `make status` - Show service status
- `make test` - Test DNS resolution
- `make restart-dns` - Restart dnsmasq service
- `make config` - Show current configuration
- `make share-cert` - Open certs folder for sharing
- `make help` - Show all available commands

### 📂 `scripts/`
Contains the core bash scripts:
- `setup-interactive.sh` - Interactive setup wizard with auto-detection
- `setup-tailscale-dns.sh` - Main setup script (non-interactive)
- `cleanup-tailscale-dns.sh` - Cleanup script with multiple removal options

**What the setup does:**
- Installs and configures Tailscale (if needed)
- Installs and configures dnsmasq as DNS server
- **Automatically generates HTTPS certificates with mkcert**
- Makes all your `/etc/hosts` entries accessible via Tailscale
- Auto-syncs changes to `/etc/hosts`
- Configures your Mac to serve DNS on your Tailscale IP
- Exports CA certificate for easy device installation

## HTTPS Support

The setup script automatically generates HTTPS certificates using **mkcert** for your configured domains (default: `*.dev`).

### Automatic Certificate Generation
- Wildcard certificates are created based on your `.env` configuration
- CA certificate is exported to `./certs/rootCA.crt` (in the repo folder)
- Works with any domain pattern you specify

### Installing Certificates on Devices

**macOS:**
1. AirDrop `./certs/rootCA.crt` to your other Mac
2. Double-click the file to open Keychain Access
3. Find "mkcert" certificate and set to "Always Trust"

**iOS/iPadOS:**
1. AirDrop `./certs/rootCA.crt` to your device
2. Settings → Profile Downloaded → Install
3. Settings → General → About → Certificate Trust Settings
4. Enable full trust for "mkcert" root certificate

**Android:**
1. Transfer `./certs/rootCA.crt` to your device
2. Settings → Security → Install from storage
3. Select the certificate file

Once installed, HTTPS will work without warnings on all your local domains!

## Quick Start

### Just run setup!

```bash
make setup
```

**What happens:**
- 🆕 **First time?** → Interactive wizard with auto-detection
- 🔄 **Already configured?** → Uses your saved `.env` settings

The wizard will:
- 🔍 Auto-detect domains from your `/etc/hosts`
- 💡 Suggest optimal patterns
- ❓ Ask simple yes/no questions
- ✨ Configure everything automatically

**Force reconfiguration:**
```bash
make setup-interactive
```

**Manual configuration (advanced):**
```bash
cp .env.example .env
# Edit .env, then:
make setup
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
2. **dnsmasq** on your Mac serves DNS for your configured domains
3. **mkcert** generates trusted HTTPS certificates
4. **Automatic sync** keeps DNS updated when you change /etc/hosts
5. **LaunchAgent** watches for changes and restarts dnsmasq

## Make Commands Reference

```bash
make setup             # Smart setup (interactive first time, then uses .env)
make start / install   # Aliases for setup
make setup-interactive # Force interactive wizard
make cleanup           # Remove configuration
make status            # Show service status
make test              # Test DNS resolution
make restart-dns       # Restart dnsmasq
make config            # Show current config
make share-cert        # Open certs folder
make help              # Show all commands
```

## Benefits vs LAN-only Setup

- ✅ Works from anywhere (not just home WiFi)
- ✅ Encrypted connection via Tailscale
- ✅ Automatic HTTPS certificate generation
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
- Ensure `./certs/rootCA.crt` is installed AND trusted on your device
- On iOS: Check Certificate Trust Settings (Settings > General > About > Certificate Trust Settings)
- On Mac: Verify "mkcert" certificate is set to "Always Trust" in Keychain Access
- Regenerate certificates: Delete `./certs` folder and run setup script again