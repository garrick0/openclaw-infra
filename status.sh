#!/bin/bash
#
# status.sh - Check health of OpenClaw infrastructure
#
# Checks: server connectivity, service status, gateway port, local config
#
# Usage: ./status.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}●${NC} $1"; }
fail() { echo -e "  ${RED}●${NC} $1"; }
warn() { echo -e "  ${YELLOW}●${NC} $1"; }
dim() { echo -e "  ${DIM}$1${NC}"; }

main() {
  cd "$SCRIPT_DIR"

  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   OpenClaw Infrastructure Status      ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""

  # Check if deployed
  if ! tofu output server_ip &>/dev/null 2>&1; then
    fail "Infrastructure not deployed"
    dim "Run: ./setup.sh"
    echo ""
    exit 1
  fi

  SERVER_IP=$(tofu output -raw server_ip 2>/dev/null)
  GATEWAY_URL=$(tofu output -raw gateway_url 2>/dev/null)

  echo -e "${BLUE}Remote Server${NC}"
  ok "IP: $SERVER_IP"
  ok "Gateway: $GATEWAY_URL"

  # Check SSH connectivity
  if timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes "root@$SERVER_IP" "true" 2>/dev/null; then
    ok "SSH: reachable"

    # Check service status
    SERVICE_STATUS=$(ssh "root@$SERVER_IP" "systemctl is-active openclaw 2>/dev/null" || echo "unknown")
    if [ "$SERVICE_STATUS" = "active" ]; then
      ok "Service: running"

      # Get recent logs
      echo ""
      echo -e "${BLUE}Recent Activity${NC}"
      ssh "root@$SERVER_IP" "journalctl -u openclaw -n 5 --no-pager 2>/dev/null" | while read -r line; do
        dim "$line"
      done
    else
      fail "Service: $SERVICE_STATUS"
    fi
  else
    warn "SSH: not reachable (check network/keys)"
  fi

  # Check gateway port
  echo ""
  echo -e "${BLUE}Gateway Port (18789)${NC}"
  if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/18789" 2>/dev/null; then
    ok "Port: open"
  else
    fail "Port: closed or filtered"
    dim "Your IP may not be in allowed_client_ips"
  fi

  # Check local gateway
  echo ""
  echo -e "${BLUE}Local Client${NC}"
  if command -v openclaw &>/dev/null; then
    ok "CLI: installed"

    LOCAL_MODE=$(openclaw config get gateway.mode 2>/dev/null || echo "unknown")
    if [ "$LOCAL_MODE" = "remote" ]; then
      ok "Mode: remote (connecting to server)"

      # In remote mode, check if we can reach the remote gateway
      REMOTE_URL=$(openclaw config get gateway.remote.url 2>/dev/null || echo "")
      if [ -n "$REMOTE_URL" ]; then
        if openclaw status --deep 2>&1 | grep -q "Gateway.*reachable"; then
          ok "Remote gateway: connected"
        else
          warn "Remote gateway: unreachable"
          dim "Check network/firewall settings"
        fi
      else
        warn "Remote URL not configured"
        dim "Run: ./configure-client.sh"
      fi
    else
      warn "Mode: $LOCAL_MODE (not configured as remote worker)"
      dim "Run: ./configure-client.sh"

      if pgrep -f "openclaw.*gateway" >/dev/null 2>&1; then
        ok "Gateway: running"
      else
        warn "Gateway: not running"
        dim "Run: openclaw gateway start"
      fi
    fi
  else
    fail "CLI: not installed"
  fi

  echo ""
}

main "$@"
