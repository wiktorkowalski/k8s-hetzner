# Cloudflare DNS Configuration for Kubernetes Cluster

# Data source to get the zone information
data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

# A record for cluster subdomain pointing to load balancer
# e.g., k8s.example.com -> load balancer IP
resource "cloudflare_dns_record" "cluster" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv4
  type    = "A"
  ttl     = 300
  proxied = false

  comment = "Kubernetes cluster load balancer"
}

# Wildcard A record for all services under cluster subdomain
# e.g., *.k8s.example.com -> load balancer IP
resource "cloudflare_dns_record" "cluster_wildcard" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "*.${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv4
  type    = "A"
  ttl     = 300
  proxied = false

  comment = "Wildcard for Kubernetes cluster services"
}

# Optional: AAAA records for IPv6 support
# Uncomment if you want IPv6 support

# resource "cloudflare_record" "cluster_ipv6" {
#   zone_id = data.cloudflare_zone.main.zone_id
#   name    = var.cluster_subdomain
#   content = module.kube-hetzner.load_balancer_public_ipv6
#   type    = "AAAA"
#   ttl     = 300
#   proxied = false
#
#   comment = "Kubernetes cluster load balancer IPv6"
# }

# resource "cloudflare_record" "cluster_wildcard_ipv6" {
#   zone_id = data.cloudflare_zone.main.zone_id
#   name    = "*.${var.cluster_subdomain}"
#   content = module.kube-hetzner.load_balancer_public_ipv6
#   type    = "AAAA"
#   ttl     = 300
#   proxied = false
#
#   comment = "Wildcard for Kubernetes cluster services IPv6"
# }
