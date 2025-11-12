terraform {
  required_version = "~> 1.13.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.54.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.12.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.4.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  # Anonymous access - required by kube-hetzner module
}
