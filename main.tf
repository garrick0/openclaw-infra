# OpenClaw Infrastructure - Hetzner Cloud
#
# Resources: server, firewall, persistent volume
# Gateway port (18789) is restricted to allowed_client_ips
#
# Note: Changing cloud-init (user_data) will trigger server replacement.
# Use setup.sh for existing servers - it updates via SSH instead.

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# SSH Key
resource "hcloud_ssh_key" "openclaw" {
  name       = "openclaw-${var.environment}"
  public_key = var.ssh_public_key
}

# Firewall
resource "hcloud_firewall" "openclaw" {
  name = "openclaw-${var.environment}"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Gateway port for remote workers (only if allowed_client_ips is set)
  dynamic "rule" {
    for_each = length(var.allowed_client_ips) > 0 ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(var.gateway_port)
      source_ips = var.allowed_client_ips
    }
  }
}

# Server
resource "hcloud_server" "openclaw" {
  name        = "openclaw-${var.environment}"
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.location

  ssh_keys = [hcloud_ssh_key.openclaw.id]

  firewall_ids = [hcloud_firewall.openclaw.id]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    openclaw_version = var.openclaw_version
    timezone         = var.timezone
    openclaw_config = templatefile("${path.module}/templates/openclaw.json.tpl", {
      gateway_port  = var.gateway_port
      gateway_bind  = var.gateway_bind
      gateway_token = var.gateway_token
    })
  })

  labels = {
    environment = var.environment
    app         = "openclaw"
  }
}

# Volume for persistent data (workspace, WhatsApp session)
resource "hcloud_volume" "openclaw_data" {
  name     = "openclaw-data-${var.environment}"
  size     = var.volume_size_gb
  location = var.location
  format   = "ext4"
}

resource "hcloud_volume_attachment" "openclaw_data" {
  volume_id = hcloud_volume.openclaw_data.id
  server_id = hcloud_server.openclaw.id
  automount = true
}
