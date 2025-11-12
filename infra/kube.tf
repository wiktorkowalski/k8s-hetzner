module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.18.4"

  hcloud_token = var.hcloud_token != "" ? var.hcloud_token : env("HCLOUD_TOKEN")
  providers = {
    hcloud = hcloud
  }

  # SSH Configuration
  ssh_public_key  = file(var.ssh_public_key_path)
  ssh_private_key = file(var.ssh_private_key_path)

  # Network Configuration
  network_region = var.network_region

  # Cluster Configuration
  cluster_name = var.cluster_name

  # Control Plane Nodes (3 for HA)
  control_plane_nodepools = [
    {
      name        = "control-plane-fsn1"
      server_type = "cx23" # 2 vCPU, 4GB RAM, x86
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "control-plane-nbg1"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "control-plane-hel1"
      server_type = "cx23"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # Agent Nodes (Workers)
  agent_nodepools = [
    {
      name        = "agent-small-fsn1"
      server_type = "cx33" # 4 vCPU, 8GB RAM, x86
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "agent-small-nbg1"
      server_type = "cx33"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # Load Balancer Configuration
  load_balancer_type     = "lb11"
  load_balancer_location = "fsn1"

  # CNI Plugin (Cilium is recommended for production)
  cni_plugin = "cilium"

  # Enable Cluster Autoscaler
  enable_klipper_metal_lb = false
  autoscaler_nodepools = [
    {
      name        = "autoscaler-fsn1"
      server_type = "cx33"
      location    = "fsn1"
      min_nodes   = 0
      max_nodes   = 5
    },
    {
      name        = "autoscaler-nbg1"
      server_type = "cx33"
      location    = "nbg1"
      min_nodes   = 0
      max_nodes   = 5
    }
  ]

  # Storage Configuration
  enable_longhorn = true

  # Disable Hetzner CSI to avoid conflicts with Longhorn
  disable_hetzner_csi = true

  # Note: Traefik is installed by default in kube-hetzner
  # We'll manage additional ingress configuration via ArgoCD in k8s/ directory

  # Enable Cert-Manager for TLS
  enable_cert_manager = true

  # Rancher (optional, set to false if not needed)
  enable_rancher = false

  # Additional Options
  automatically_upgrade_k3s = true
  automatically_upgrade_os  = true

  # Restrict API server access (optional - remove or modify for your IP)
  # restrict_outbound_traffic = false

  # Firewall configuration
  # extra_firewall_rules = []

  enable_metrics_server = true
}
