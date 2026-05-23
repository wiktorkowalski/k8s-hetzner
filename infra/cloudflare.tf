data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "cluster" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv4
  type    = "A"
  ttl     = 300
  proxied = false
  comment = "Kubernetes cluster load balancer"
}

resource "cloudflare_dns_record" "cluster_wildcard" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "*.${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv4
  type    = "A"
  ttl     = 300
  proxied = false
  comment = "Wildcard for Kubernetes cluster services"
}

resource "cloudflare_dns_record" "cluster_v6" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv6
  type    = "AAAA"
  ttl     = 300
  proxied = false
  comment = "Kubernetes cluster load balancer (IPv6)"
}

resource "cloudflare_dns_record" "cluster_wildcard_v6" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "*.${var.cluster_subdomain}.${var.domain}"
  content = module.kube-hetzner.ingress_public_ipv6
  type    = "AAAA"
  ttl     = 300
  proxied = false
  comment = "Wildcard for Kubernetes cluster services (IPv6)"
}
