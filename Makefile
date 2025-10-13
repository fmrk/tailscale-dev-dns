.PHONY: help setup config configure install start cleanup uninstall test status restart logs show-config share-cert

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Tailscale Dev DNS - Make Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Commands:"
	@grep -E '^(setup|config|cleanup|test|status):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Aliases:"
	@grep -E '^(install|start|configure|uninstall):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Advanced:"
	@grep -E '^(restart|logs|show-config|share-cert):.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Smart setup (interactive if no .env, else uses config)
	@if [ ! -f .env ]; then \
		echo "💡 No .env found - running interactive configuration..."; \
		echo ""; \
		bash scripts/configure-interactive.sh; \
	else \
		echo "🚀 Using existing .env configuration..."; \
		bash scripts/setup-tailscale-dns.sh; \
	fi

config: ## Interactive configuration wizard (creates/updates .env)
	@bash scripts/configure-interactive.sh

configure: config ## Alias for config

install: setup ## Alias for setup

start: setup ## Alias for setup

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

restart: ## Restart dnsmasq service
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

show-config: ## Show current configuration
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
	@echo "To customize: make config"

share-cert: ## Open certs folder for easy sharing
	@if [ -d "./certs" ]; then \
		open ./certs; \
	else \
		echo "❌ Certificates not generated yet. Run 'make setup' first."; \
	fi
