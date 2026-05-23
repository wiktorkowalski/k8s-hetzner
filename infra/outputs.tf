output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = module.kube-hetzner.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  description = "Cluster name"
  value       = module.kube-hetzner.cluster_name
}

output "ingress_public_ipv4" {
  description = "Public IPv4 of the Traefik load balancer"
  value       = module.kube-hetzner.ingress_public_ipv4
}

output "ingress_public_ipv6" {
  description = "Public IPv6 of the Traefik load balancer"
  value       = module.kube-hetzner.ingress_public_ipv6
}

output "cluster_domain" {
  description = "FQDN for the cluster"
  value       = "${var.cluster_subdomain}.${var.domain}"
}

output "cluster_wildcard_domain" {
  description = "Wildcard FQDN for cluster services"
  value       = "*.${var.cluster_subdomain}.${var.domain}"
}

output "control_plane_ips" {
  description = "Public IPv4 addresses of the control plane nodes"
  value       = module.kube-hetzner.control_planes_public_ipv4
}

output "agents_public_ipv4" {
  description = "Public IPv4 addresses of the agent nodes"
  value       = module.kube-hetzner.agents_public_ipv4
}
