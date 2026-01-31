# OpenClaw

Self-hosted WhatsApp gateway infrastructure for **~$5/month**.

Run your own always-on WhatsApp automation server on Hetzner Cloud. Your laptop connects on-demand — no local daemon required.

## Why?

- **Cheap**: ~€4.25/month on Hetzner (vs $50+/month for commercial APIs)
- **Self-hosted**: Your data, your server, your rules
- **Always-on**: Server maintains WhatsApp session 24/7
- **On-demand**: Laptop connects via WebSocket only when needed
- **Secure**: Token auth, IP allowlisting, fail2ban protection

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Your Laptop    │◄───────►│  Hetzner Server │
│  (on-demand)    │   WS    │  (always-on)    │
└─────────────────┘  :18789 └─────────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │   WhatsApp   │
                       └──────────────┘
```

Your laptop runs in "remote mode" — commands connect to the server, execute, and disconnect. The server maintains persistent connections to WhatsApp.

## What Can You Build?

- **Notification bot** — Send yourself alerts from scripts, cron jobs, CI/CD
- **AI chatbot** — Connect Claude/GPT to WhatsApp for personal assistant
- **Automation** — Auto-respond to messages, forward to Slack/Discord
- **Group management** — Moderation tools, scheduled messages
- **Backup** — Archive your WhatsApp messages programmatically

## Quick Start

```bash
# Clone and configure
git clone https://github.com/garrick0/openclaw-infra.git
cd openclaw-infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Hetzner token and SSH key

# Deploy
tofu init
./setup.sh

# Configure laptop to connect to server
./configure-client.sh

# Verify
./status.sh
```

## Requirements

- [OpenTofu](https://opentofu.org/) (`brew install opentofu`)
- [Hetzner Cloud account](https://console.hetzner.cloud/)
- SSH key pair
- `jq` (`brew install jq`)

## Scripts

| Script | Purpose |
|--------|---------|
| `./setup.sh` | Deploy new infra or safely update existing (won't destroy server) |
| `./configure-client.sh` | Configure laptop to connect to remote gateway |
| `./status.sh` | Health check for server and local client |
| `./setup-tailscale.sh` | Add Tailscale for encrypted access (recommended) |

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

**Option B: Reverse proxy** - Put nginx/caddy in front with Let's Encrypt.

## Costs

| Resource | Cost |
|----------|------|
| cax11 (ARM, 2 vCPU/4GB) | €3.79/mo |
| cpx11 (x86, 2 vCPU/2GB) | €4.85/mo |
| Volume (10GB) | €0.44/mo |
| **Total** | **~€4.25/mo** |

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

### Rotate gateway token
```bash
NEW_TOKEN=$(openssl rand -hex 24)
sed -i '' "s/gateway_token.*/gateway_token = \"$NEW_TOKEN\"/" terraform.tfvars
./setup.sh
./configure-client.sh  # Re-configure laptop with new token
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

## Project Structure

```
openclaw-infra/
├── README.md              # You are here
├── LICENSE
├── setup.sh               # Deploy/update infrastructure
├── configure-client.sh    # Configure laptop as remote worker
├── status.sh              # Health check
├── setup-tailscale.sh     # Add encrypted access (optional)
├── main.tf                # Server, firewall, volume resources
├── variables.tf           # Input variables
├── outputs.tf             # Outputs (IP, client config)
├── cloud-init.yaml        # Server bootstrap
├── templates/
│   └── openclaw.json.tpl  # Gateway config template
└── terraform.tfvars.example
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

## License

MIT License — see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome. Please open an issue first to discuss major changes.

## Disclaimer

This project interacts with WhatsApp Web unofficially. Use responsibly and in accordance with WhatsApp's Terms of Service. This is intended for personal automation, not spam or bulk messaging.
