#!/bin/bash
#
# setup.sh - Deploy or update OpenClaw infrastructure
#
# For new deployments: Creates server, firewall, volume
# For existing deployments: Updates firewall + config via SSH (no rebuild)
#
# Usage: ./setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS_FILE="$SCRIPT_DIR/terraform.tfvars"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Check dependencies
check_deps() {
  local missing=()
  for cmd in tofu jq curl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required tools: ${missing[*]}"
  fi
}

# Get current public IP
get_public_ip() {
  curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 icanhazip.com || echo ""
}

# Read a value from tfvars (strips quotes, comments, whitespace)
read_tfvar() {
  local key="$1"
  grep -E "^${key}\s*=" "$TFVARS_FILE" 2>/dev/null \
    | sed 's/.*=\s*//' \
    | sed 's/#.*//' \
    | tr -d '"' \
    | tr -d "'" \
    | xargs \
    || echo ""
}

# Update or add a tfvar
set_tfvar() {
  local key="$1"
  local value="$2"

  if grep -qE "^${key}\s*=" "$TFVARS_FILE" 2>/dev/null; then
    # Update existing (macOS compatible sed)
    sed -i '' "s|^${key}.*|${key} = ${value}|" "$TFVARS_FILE"
  elif grep -qE "^#.*${key}\s*=" "$TFVARS_FILE" 2>/dev/null; then
    # Uncomment and update
    sed -i '' "s|^#.*${key}.*|${key} = ${value}|" "$TFVARS_FILE"
  else
    # Append
    echo "${key} = ${value}" >> "$TFVARS_FILE"
  fi
}

# Generate a random token
generate_token() {
  openssl rand -hex 24
}

# Check if IP is in allowed list
ip_in_allowed() {
  local ip="$1"
  grep -qE "allowed_client_ips.*${ip}" "$TFVARS_FILE" 2>/dev/null
}

# Add IP to allowed list (appends, doesn't overwrite)
add_ip_to_allowed() {
  local new_ip="$1"
  local current
  current=$(grep -E "^allowed_client_ips\s*=" "$TFVARS_FILE" 2>/dev/null | sed 's/.*=\s*//' | xargs || echo "")

  if [ -z "$current" ] || [ "$current" = "[]" ]; then
    set_tfvar "allowed_client_ips" "[\"${new_ip}/32\"]"
  else
    # Append to existing list (insert before closing bracket)
    local updated
    updated=$(echo "$current" | sed "s/\]/, \"${new_ip}\/32\"]/")
    set_tfvar "allowed_client_ips" "$updated"
  fi
}

# Validate inputs to prevent shell injection
validate_gateway_bind() {
  local bind="$1"
  if [[ ! "$bind" =~ ^(loopback|lan|auto|tailnet|custom)$ ]]; then
    error "Invalid gateway_bind value: $bind (must be loopback|lan|auto|tailnet|custom)"
  fi
}

validate_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid IP address: $ip"
  fi
}

# Update server config via SSH (for existing deployments)
update_server_config() {
  local server_ip="$1"
  local gateway_token
  gateway_token=$(read_tfvar "gateway_token" | tr -d '"')
  local gateway_bind
  gateway_bind=$(read_tfvar "gateway_bind" | tr -d '"')

  # Validate inputs before SSH to prevent injection
  validate_ip "$server_ip"
  validate_gateway_bind "$gateway_bind"
  if [[ ${#gateway_token} -lt 32 ]]; then
    warn "Gateway token seems too short (${#gateway_token} chars)"
  fi

  # Use printf to safely pass values, avoiding shell injection
  ssh "root@$server_ip" bash -s "$gateway_bind" "$gateway_token" << 'REMOTE_SCRIPT'
    set -e
    BIND="$1"
    TOKEN="$2"
    jq --arg bind "$BIND" --arg token "$TOKEN" \
      '.gateway.bind = $bind | .gateway.auth.token = $token' \
      /home/openclaw/.openclaw/openclaw.json > /tmp/oc.json
    mv /tmp/oc.json /home/openclaw/.openclaw/openclaw.json
    chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
    chmod 600 /home/openclaw/.openclaw/openclaw.json
    systemctl restart openclaw
REMOTE_SCRIPT

  if [ $? -eq 0 ]; then
    success "Server config updated and service restarted"
  else
    warn "Could not update server config via SSH"
  fi
}

# Main setup
main() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   OpenClaw Infrastructure Setup       ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
  echo ""

  check_deps
  cd "$SCRIPT_DIR"

  # 1. Check/generate gateway token
  info "Checking gateway token..."
  current_token=$(read_tfvar "gateway_token")
  if [ -z "$current_token" ] || [ "$current_token" = '""' ]; then
    new_token=$(generate_token)
    set_tfvar "gateway_token" "\"$new_token\""
    success "Generated new gateway token"
  else
    success "Gateway token already set"
  fi

  # 2. Check/update allowed client IPs
  info "Fetching your public IP..."
  my_ip=$(get_public_ip)

  if [ -z "$my_ip" ]; then
    warn "Could not detect public IP. Set allowed_client_ips manually."
  else
    success "Your IP: $my_ip"

    if ip_in_allowed "$my_ip"; then
      success "Your IP is already in allowed_client_ips"
    else
      echo ""
      warn "Your IP ($my_ip) is not in the allowed list."
      read -p "Add it now? [Y/n] " -n 1 -r
      echo ""
      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        validate_ip "$my_ip"
        add_ip_to_allowed "$my_ip"
        success "Added $my_ip/32 to allowed_client_ips"
      fi
    fi
  fi

  # 3. Validate configuration
  echo ""
  info "Validating OpenTofu configuration..."
  if tofu validate &>/dev/null; then
    success "Configuration is valid"
  else
    error "Configuration invalid. Run 'tofu validate' for details."
  fi

  # 4. Check if this is an existing deployment
  echo ""
  SERVER_EXISTS=$(tofu output -raw server_ip 2>/dev/null || echo "")

  if [ -n "$SERVER_EXISTS" ]; then
    info "Existing server detected: $SERVER_EXISTS"

    # Check what would change
    PLAN_OUTPUT=$(tofu plan -no-color 2>&1)

    if echo "$PLAN_OUTPUT" | grep -q "must be replaced"; then
      warn "Plan wants to REPLACE the server (destructive!)"
      echo ""
      echo "  This would destroy your server and WhatsApp session."
      echo "  For existing servers, we'll update config via SSH instead."
      echo ""

      # Apply only non-destructive changes (firewall)
      if echo "$PLAN_OUTPUT" | grep -q "hcloud_firewall"; then
        info "Applying firewall changes only..."
        tofu apply -target=hcloud_firewall.openclaw -auto-approve
      fi

      # Update server config via SSH
      info "Updating server config via SSH..."
      update_server_config "$SERVER_EXISTS"

      echo ""
      success "Server updated (no rebuild required)!"

    elif echo "$PLAN_OUTPUT" | grep -q "No changes"; then
      success "Infrastructure is up to date"
    else
      # Safe changes only
      info "Generating plan..."
      tofu plan -out=tfplan
      echo ""
      read -p "Apply these changes? [y/N] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        tofu apply tfplan
        rm -f tfplan
        success "Changes applied!"
      else
        rm -f tfplan
        info "Aborted."
      fi
    fi
  else
    # Fresh deployment
    info "No existing server. Generating plan for new deployment..."
    echo ""
    tofu plan -out=tfplan

    echo ""
    read -p "Apply these changes? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      tofu apply tfplan
      rm -f tfplan
      success "Infrastructure deployed!"
    else
      rm -f tfplan
      info "Aborted."
    fi
  fi

  # Show connection info
  SERVER_IP=$(tofu output -raw server_ip 2>/dev/null || echo "")
  if [ -n "$SERVER_IP" ]; then
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}Server IP:${NC} $SERVER_IP"
    echo -e "${GREEN}Gateway:${NC}   ws://${SERVER_IP}:18789"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    echo "To configure your laptop as a remote worker:"
    echo ""
    echo "  $SCRIPT_DIR/configure-client.sh"
    echo ""
  fi
}

main "$@"
