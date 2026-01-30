output "server_ip" {
  description = "Public IP address of the OpenClaw server"
  value       = hcloud_server.openclaw.ipv4_address
}

output "server_ipv6" {
  description = "IPv6 address of the OpenClaw server"
  value       = hcloud_server.openclaw.ipv6_address
}

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.openclaw.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.openclaw.ipv4_address}"
}

output "volume_id" {
  description = "Hetzner volume ID for persistent data"
  value       = hcloud_volume.openclaw_data.id
}

output "gateway_url" {
  description = "Gateway WebSocket URL"
  value       = "ws://${hcloud_server.openclaw.ipv4_address}:${var.gateway_port}"
}

output "client_config" {
  description = "Config for laptop to connect as remote worker"
  sensitive   = true
  value = jsonencode({
    gateway = {
      mode = "remote"
      remote = {
        url   = "ws://${hcloud_server.openclaw.ipv4_address}:${var.gateway_port}"
        token = var.gateway_token
      }
    }
  })
}
