variable "hcloud_token" {
  description = "Hetzner Cloud API Token (set as HCLOUD_TOKEN env var in TF Cloud workspace)"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Zone.DNS edit permissions (set as CLOUDFLARE_API_TOKEN env var in TF Cloud workspace)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
}

variable "domain" {
  description = "Your domain name (e.g., vicio.ovh)"
  type        = string
}

variable "cluster_subdomain" {
  description = "Subdomain for the cluster (e.g., k8s -> k8s.vicio.ovh)"
  type        = string
  default     = "k8s"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for Hetzner resource naming)"
  type        = string
  default     = "k8s-hetzner"
}

variable "network_region" {
  description = "Hetzner network region (eu-central, us-east, us-west)"
  type        = string
  default     = "eu-central"
}

variable "ssh_public_key" {
  description = "SSH public key content (not a path)"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key content (not a path)"
  type        = string
  sensitive   = true
}

variable "management_cidrs" {
  description = "Source CIDRs allowed to reach SSH (22) and the Kubernetes API (6443). Update when your public IP changes."
  type        = list(string)
  default     = ["185.14.151.136/32"]
}
