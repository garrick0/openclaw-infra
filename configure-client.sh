#!/bin/bash
#
# configure-client.sh - Configure local machine as remote worker
#
# Sets gateway.mode=remote and configures connection to server.
# In remote mode, commands connect to the server on-demand.
# No local gateway process runs.
#
# Usage: ./configure-client.sh
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
  echo -e "${BLUE}║   Configure Local Client              ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""

  cd "$SCRIPT_DIR"

  # Check if infrastructure is deployed
  if ! tofu output server_ip &>/dev/null; then
    error "Infrastructure not deployed. Run ./setup.sh first."
  fi

  # Check if openclaw CLI is available
  if ! command -v openclaw &>/dev/null; then
    error "openclaw CLI not found. Install it first: npm install -g openclaw"
  fi

  # Get client config from tofu
  info "Fetching client configuration from infrastructure..."

  CLIENT_CONFIG=$(tofu output -raw client_config)
  SERVER_IP=$(tofu output -raw server_ip)
  GATEWAY_URL=$(tofu output -raw gateway_url)

  success "Server: $SERVER_IP"
  success "Gateway: $GATEWAY_URL"

  # Test connectivity
  echo ""
  info "Testing connectivity to gateway..."
  if timeout 5 bash -c "echo >/dev/tcp/$SERVER_IP/18789" 2>/dev/null; then
    success "Gateway port is reachable"
  else
    warn "Cannot reach gateway port 18789"
    echo ""
    echo "  This could mean:"
    echo "  1. Your IP is not in allowed_client_ips (run ./setup.sh to add)"
    echo "  2. The server is still starting up"
    echo "  3. Firewall is blocking the connection"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
  fi

  # Write config
  echo ""
  info "Configuring local openclaw..."

  CONFIG_FILE="${HOME}/.openclaw/remote-gateway.json"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "$CLIENT_CONFIG" | jq . > "$CONFIG_FILE"

  success "Wrote config to $CONFIG_FILE"

  # Apply config using individual set commands
  local TOKEN
  TOKEN=$(echo "$CLIENT_CONFIG" | jq -r '.gateway.remote.token')

  info "Applying gateway configuration..."
  openclaw config set gateway.mode remote 2>/dev/null || true
  openclaw config set gateway.remote.url "$GATEWAY_URL" 2>/dev/null || true
  openclaw config set gateway.remote.token "$TOKEN" 2>/dev/null || true
  success "Gateway configured for remote mode"

  # In remote mode, no local gateway needed
  echo ""
  success "Done! Your laptop is configured as a remote worker."
  echo ""
  echo "In remote mode, commands connect directly to the server."
  echo "No local gateway process is needed."
  echo ""
  echo "Test the connection:"
  echo "  openclaw status --deep"
  echo ""
}

main "$@"
