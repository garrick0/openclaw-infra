#!/bin/bash
#
# setup-tailscale.sh - Install and configure Tailscale for encrypted gateway access
#
# This script:
# 1. Installs Tailscale on the remote server
# 2. Prompts you to authenticate
# 3. Configures the gateway to use Tailscale
#
# After setup, access the gateway via Tailscale IP (encrypted, no port exposure needed)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

main() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   Tailscale Setup for OpenClaw        ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""

  cd "$SCRIPT_DIR"

  # Get server IP
  SERVER_IP=$(tofu output -raw server_ip 2>/dev/null || echo "")
  if [ -z "$SERVER_IP" ]; then
    error "No server deployed. Run ./setup.sh first."
  fi

  info "Server: $SERVER_IP"

  # Check if Tailscale is already installed
  echo ""
  info "Checking Tailscale status on server..."

  TAILSCALE_STATUS=$(ssh "root@$SERVER_IP" "tailscale status --json 2>/dev/null || echo 'not_installed'" 2>/dev/null)

  if [ "$TAILSCALE_STATUS" = "not_installed" ]; then
    info "Installing Tailscale on server..."
    ssh "root@$SERVER_IP" "curl -fsSL https://tailscale.com/install.sh | sh"
    success "Tailscale installed"
  else
    success "Tailscale already installed"
  fi

  # Check if authenticated
  echo ""
  TAILSCALE_IP=$(ssh "root@$SERVER_IP" "tailscale ip -4 2>/dev/null || echo ''")

  if [ -z "$TAILSCALE_IP" ]; then
    info "Tailscale not authenticated. Starting authentication..."
    echo ""
    echo "  A login URL will appear. Open it in your browser to authenticate."
    echo "  Press Enter when ready..."
    read -r

    ssh "root@$SERVER_IP" "tailscale up --ssh"

    # Get the new IP
    TAILSCALE_IP=$(ssh "root@$SERVER_IP" "tailscale ip -4 2>/dev/null || echo ''")
  fi

  if [ -z "$TAILSCALE_IP" ]; then
    error "Could not get Tailscale IP. Authentication may have failed."
  fi

  success "Tailscale IP: $TAILSCALE_IP"

  # Configure gateway to use Tailscale
  echo ""
  info "Configuring gateway for Tailscale..."

  ssh "root@$SERVER_IP" bash << 'REMOTE_SCRIPT'
    set -e

    # Update gateway config to bind to tailnet
    jq '.gateway.bind = "tailnet"' \
      /home/openclaw/.openclaw/openclaw.json > /tmp/oc.json
    mv /tmp/oc.json /home/openclaw/.openclaw/openclaw.json
    chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
    chmod 600 /home/openclaw/.openclaw/openclaw.json

    # Restart gateway
    systemctl restart openclaw
REMOTE_SCRIPT

  success "Gateway configured for Tailscale"

  # Update local client config
  echo ""
  info "Updating local client configuration..."

  GATEWAY_TOKEN=$(grep -E "^gateway_token\s*=" terraform.tfvars | sed 's/.*=\s*//' | tr -d '"' | tr -d "'" | sed 's/#.*//' | xargs)

  openclaw config set gateway.remote.url "ws://${TAILSCALE_IP}:18789" 2>/dev/null || true
  success "Local client updated"

  # Summary
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Tailscale setup complete!${NC}"
  echo ""
  echo "  Server Tailscale IP: $TAILSCALE_IP"
  echo "  Gateway URL:         ws://${TAILSCALE_IP}:18789"
  echo ""
  echo "  Traffic is now encrypted via Tailscale."
  echo "  You can optionally close port 18789 in the firewall."
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo ""
  echo "Test the connection:"
  echo "  openclaw status --deep"
  echo ""

  # Offer to close public port
  echo ""
  read -p "Close public gateway port 18789? (Tailscale-only access) [y/N] " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove allowed_client_ips to close public port
    sed -i '' 's/^allowed_client_ips.*/#allowed_client_ips = []  # Disabled - using Tailscale/' terraform.tfvars
    tofu apply -target=hcloud_firewall.openclaw -auto-approve
    success "Public gateway port closed. Access via Tailscale only."
  fi
}

main "$@"
