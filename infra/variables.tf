variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with DNS edit permissions"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
  default     = ""
}

variable "domain" {
  description = "Your domain name (e.g., example.com)"
  type        = string
}

variable "cluster_subdomain" {
  description = "Subdomain for the cluster (e.g., k8s -> k8s.example.com)"
  type        = string
  default     = "k8s"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "k8s-hetzner"
  # Cluster name is used for resource naming in Hetzner Cloud
}

variable "network_region" {
  description = "Hetzner network region (eu-central, us-east, us-west)"
  type        = string
  default     = "eu-central"
}

variable "ssh_public_key" {
  description = "SSH public key content (not path)"
  type        = string
  sensitive   = false
}

variable "ssh_private_key" {
  description = "SSH private key content (not path)"
  type        = string
  sensitive   = true
}
