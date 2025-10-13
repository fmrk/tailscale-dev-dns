.PHONY: help setup setup-interactive cleanup install uninstall test status restart-dns logs config share-cert

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Tailscale Dev DNS - Make Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "💡 First time? Try: make setup-interactive"

setup-interactive: ## Interactive setup with auto-detection (recommended for first use)
	@bash scripts/setup-interactive.sh

setup: ## Setup Tailscale DNS server (non-interactive, uses .env or defaults)
	@echo "🚀 Setting up Tailscale DNS server..."
	@bash scripts/setup-tailscale-dns.sh

install: setup-interactive ## Alias for setup-interactive

cleanup: ## Remove Tailscale DNS configuration (interactive)
	@echo "🧹 Running cleanup..."
	@bash scripts/cleanup-tailscale-dns.sh

uninstall: cleanup ## Alias for cleanup

test: ## Test DNS resolution locally
	@echo "🧪 Testing DNS resolution..."
	@TAILSCALE_CMD=""; \
	if command -v tailscale &> /dev/null; then \
		TAILSCALE_CMD="tailscale"; \
	elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then \
		TAILSCALE_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"; \
	fi; \
	if [ -z "$$TAILSCALE_CMD" ]; then \
		echo "❌ Tailscale not found"; \
		exit 1; \
	fi; \
	TAILSCALE_IP=$$($$TAILSCALE_CMD ip -4 2>/dev/null | head -1); \
	if [ -z "$$TAILSCALE_IP" ]; then \
		echo "❌ Could not get Tailscale IP - is Tailscale connected?"; \
		exit 1; \
	fi; \
	echo "Your Tailscale IP: $$TAILSCALE_IP"; \
	echo ""; \
	echo "💡 To properly test, use another device on your Tailscale network:"; \
	echo "   ping api.dev"; \
	echo "   curl http://api.dev"; \
	echo ""; \
	echo "Testing local dnsmasq service..."; \
	if pgrep dnsmasq > /dev/null; then \
		echo "✅ dnsmasq is running"; \
	else \
		echo "❌ dnsmasq is not running - run 'make setup' first"; \
	fi

status: ## Show service status
	@echo "📊 Service Status"
	@echo ""
	@echo "Tailscale:"
	@TAILSCALE_CMD=""; \
	if command -v tailscale &> /dev/null; then \
		TAILSCALE_CMD="tailscale"; \
	elif [ -f "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]; then \
		TAILSCALE_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"; \
	fi; \
	if [ -z "$$TAILSCALE_CMD" ]; then \
		echo "  Not installed"; \
	else \
		$$TAILSCALE_CMD status 2>/dev/null || echo "  Not connected"; \
	fi
	@echo ""
	@echo "dnsmasq:"
	@brew services list 2>/dev/null | grep dnsmasq || echo "  Not installed"
	@echo ""
	@echo "Certificates:"
	@if [ -d "./certs" ]; then \
		echo "  ✅ Generated (./certs/)"; \
	else \
		echo "  ❌ Not generated"; \
	fi

restart-dns: ## Restart dnsmasq service
	@echo "🔄 Restarting dnsmasq..."
	@sudo brew services restart dnsmasq
	@echo "✅ dnsmasq restarted"

logs: ## Show dnsmasq logs (if logging is enabled)
	@if [ -f "/opt/homebrew/var/log/dnsmasq.log" ]; then \
		tail -f /opt/homebrew/var/log/dnsmasq.log; \
	else \
		echo "Logging not enabled. Showing system logs:"; \
		brew services info dnsmasq; \
	fi

config: ## Show current configuration
	@echo "⚙️  Configuration"
	@echo ""
	@if [ -f ".env" ]; then \
		echo "From .env:"; \
		cat .env | grep -v '^#' | grep -v '^$$'; \
	else \
		echo "No .env file found (using defaults)"; \
		echo ""; \
		echo "Defaults:"; \
		echo "  DOMAIN_PATTERN=\\.dev"; \
		echo "  HOST_IP_PATTERN=^(127\\.0\\.0\\.1|10\\.0\\.0\\.1)"; \
		echo "  CERT_DOMAINS=*.dev localhost 127.0.0.1"; \
		echo "  CERT_EXPORT_DIR=./certs"; \
	fi
	@echo ""
	@echo "To customize: cp .env.example .env"

share-cert: ## Open certs folder for easy sharing
	@if [ -d "./certs" ]; then \
		open ./certs; \
	else \
		echo "❌ Certificates not generated yet. Run 'make setup' first."; \
	fi
