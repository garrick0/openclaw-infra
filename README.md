# OpenClaw Infrastructure

OpenTofu configuration for deploying OpenClaw to Hetzner Cloud, with support for remote worker mode (server controls your laptop).

## Prerequisites

- [OpenTofu](https://opentofu.org/) installed (`brew install opentofu`)
- [Hetzner Cloud account](https://console.hetzner.cloud/)
- SSH key pair
- `jq` installed (`brew install jq`)

## Quick Start

```bash
# 1. First time setup
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your hcloud_token and ssh_public_key

# 2. Initialize OpenTofu
tofu init

# 3. Deploy (handles IP allowlisting, token generation, etc.)
./setup.sh

# 4. Configure your laptop as a remote worker
./configure-client.sh

# 5. Verify everything works
./status.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `./setup.sh` | Deploy new infra or safely update existing (won't destroy server) |
| `./configure-client.sh` | Configure laptop to connect to remote gateway |
| `./status.sh` | Health check for server and local client |
| `./setup-tailscale.sh` | Add Tailscale for encrypted access (recommended) |

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Your Laptop    │◄───────►│  Hetzner Server │
│  (remote mode)  │   WS    │  (gateway)      │
└─────────────────┘  :18789 └─────────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │  WhatsApp    │
                       │  Gmail, etc  │
                       └──────────────┘
```

- **Server**: Runs the gateway, connects to external services (WhatsApp, etc.)
- **Laptop**: Configured in "remote mode" - commands connect to server on-demand
- **No local gateway process** runs on your laptop in remote mode

## Configuration

All configuration is in `terraform.tfvars` (gitignored):

```hcl
# Required
hcloud_token   = "your-hetzner-api-token"
ssh_public_key = "ssh-rsa AAAA..."

# Gateway (managed by setup.sh)
gateway_token      = "auto-generated-or-set-manually"
gateway_bind       = "lan"              # Bind to all interfaces
allowed_client_ips = ["1.2.3.4/32"]     # Your IP, set by setup.sh
```

## Security

| Aspect | Status | Notes |
|--------|--------|-------|
| Secrets in git | ✅ | `terraform.tfvars` is gitignored |
| Firewall | ✅ | Port 18789 restricted to your IP only |
| Auth | ✅ | Token auth enabled |
| SSH | ✅ | Key-based only |
| TLS | ⚠️ | Not enabled by default (see below) |

### Adding TLS (Recommended)

**Option A: Tailscale (easiest)** - run the setup script:
```bash
./setup-tailscale.sh
```
This installs Tailscale, configures encrypted access, and optionally closes the public port.

**Option B: Reverse proxy**
Put nginx/caddy in front with Let's Encrypt.

### Rotating the Gateway Token

```bash
# Generate new token
NEW_TOKEN=$(openssl rand -hex 24)

# Update tfvars, then run setup
sed -i '' "s/gateway_token.*/gateway_token = \"$NEW_TOKEN\"/" terraform.tfvars
./setup.sh
./configure-client.sh  # Re-configure laptop with new token
```

## Costs

| Resource | Cost |
|----------|------|
| cax11 (ARM, 2 vCPU/4GB) | €3.79/mo |
| cpx11 (x86, 2 vCPU/2GB) | €4.85/mo |
| Volume (10GB) | €0.44/mo |
| **Total** | **~€4.25/mo** |

## Files

```
infra/
├── setup.sh              # Safe deployment script
├── configure-client.sh   # Laptop configuration
├── status.sh             # Health check
├── main.tf               # Server, firewall, volume
├── variables.tf          # Input variables
├── outputs.tf            # Outputs (IP, client config)
├── cloud-init.yaml       # Server bootstrap
├── templates/
│   └── openclaw.json.tpl # Gateway config template
├── terraform.tfvars      # Your config (gitignored)
└── terraform.tfvars.example
```

## Common Operations

### SSH to server
```bash
ssh root@$(tofu output -raw server_ip)
```

### View logs
```bash
ssh root@$(tofu output -raw server_ip) "journalctl -u openclaw -f"
```

### Restart service
```bash
ssh root@$(tofu output -raw server_ip) "systemctl restart openclaw"
```

### Update your IP (when it changes)
```bash
./setup.sh  # Auto-detects and prompts to update
```

### Migrate WhatsApp session from laptop
```bash
SERVER=$(tofu output -raw server_ip)
scp -r ~/.openclaw/credentials/whatsapp root@$SERVER:/mnt/data/openclaw/.openclaw/credentials/
ssh root@$SERVER "chown -R openclaw:openclaw /mnt/data/openclaw/.openclaw"
ssh root@$SERVER "systemctl restart openclaw"
```

## Troubleshooting

### "Gateway unreachable"
1. Check your IP hasn't changed: `curl -s ifconfig.me`
2. Run `./setup.sh` to update firewall if needed
3. Verify server is running: `./status.sh`

### "Token mismatch"
1. Ensure token matches on both ends
2. Re-run `./configure-client.sh`

### Server won't start
```bash
ssh root@$(tofu output -raw server_ip) "journalctl -u openclaw -n 50"
```

### WhatsApp 440 errors (conflict)
Another WhatsApp Web session is active. Close browser WhatsApp Web or restart:
```bash
ssh root@$(tofu output -raw server_ip) "systemctl restart openclaw"
```

## Destroy

```bash
tofu destroy
```

⚠️ **Warning**: This deletes the server AND the data volume. Back up first!

### Backup before destroy
```bash
SERVER=$(tofu output -raw server_ip)
scp -r root@$SERVER:/mnt/data/openclaw/.openclaw ~/openclaw-backup/
```
