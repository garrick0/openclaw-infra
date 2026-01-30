variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx11" # 2 vCPU, 2GB RAM, €4.85/mo
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "fsn1" # Falkenstein, Germany (cheapest)
}

variable "volume_size_gb" {
  description = "Size of persistent data volume in GB"
  type        = number
  default     = 10
}

variable "openclaw_version" {
  description = "OpenClaw version to install"
  type        = string
  default     = "latest"
}

variable "timezone" {
  description = "Server timezone"
  type        = string
  default     = "America/Los_Angeles"
}

variable "gateway_token" {
  description = "Gateway auth token (shared between server and clients)"
  type        = string
  sensitive   = true
}

variable "gateway_bind" {
  description = "Gateway bind mode: loopback, lan (0.0.0.0), auto, tailnet, custom"
  type        = string
  default     = "loopback"

  validation {
    condition     = contains(["loopback", "lan", "auto", "tailnet", "custom"], var.gateway_bind)
    error_message = "gateway_bind must be one of: loopback, lan, auto, tailnet, custom"
  }
}

variable "gateway_port" {
  description = "Gateway WebSocket port"
  type        = number
  default     = 18789
}

variable "allowed_client_ips" {
  description = "IPs allowed to connect to gateway (for remote workers). Leave empty to keep port closed."
  type        = list(string)
  default     = []
}

variable "allowed_ssh_ips" {
  description = "IPs allowed to SSH. Default: anywhere. Set to your IPs for better security."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
