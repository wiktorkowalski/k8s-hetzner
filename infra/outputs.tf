# Kubernetes Cluster Outputs

output "kubeconfig" {
  description = "Kubeconfig file content for accessing the cluster"
  value       = module.kube-hetzner.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = module.kube-hetzner.cluster_name
}

output "ingress_public_ipv4" {
  description = "Public IPv4 address of the load balancer"
  value       = module.kube-hetzner.ingress_public_ipv4
}

output "ingress_public_ipv6" {
  description = "Public IPv6 address of the load balancer"
  value       = module.kube-hetzner.ingress_public_ipv6
}

# DNS Outputs

output "cluster_domain" {
  description = "Full domain for the cluster"
  value       = "${var.cluster_subdomain}.${var.domain}"
}

output "cluster_wildcard_domain" {
  description = "Wildcard domain for cluster services"
  value       = "*.${var.cluster_subdomain}.${var.domain}"
}

output "dns_records" {
  description = "DNS records created in Cloudflare"
  value = {
    cluster_a_record = {
      name  = cloudflare_dns_record.cluster.name
      value = cloudflare_dns_record.cluster.content
      type  = cloudflare_dns_record.cluster.type
    }
    wildcard_a_record = {
      name  = cloudflare_dns_record.cluster_wildcard.name
      value = cloudflare_dns_record.cluster_wildcard.content
      type  = cloudflare_dns_record.cluster_wildcard.type
    }
  }
}

# Control Plane Information

output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value       = module.kube-hetzner.control_planes_public_ipv4
}

output "agents_public_ipv4" {
  description = "Public IPv4 addresses of agent nodes"
  value       = module.kube-hetzner.agents_public_ipv4
}
