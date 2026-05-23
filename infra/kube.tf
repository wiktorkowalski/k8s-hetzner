module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.19.3"

  hcloud_token = var.hcloud_token

  providers = {
    hcloud = hcloud
  }

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  network_region = var.network_region
  cluster_name   = var.cluster_name

  # Pin k3s minor channel so module defaults don't drift
  initial_k3s_channel = "v1.32"

  # 3 cx33 nodes — one per DC. Each acts as BOTH control plane and worker.
  # cx33: 4 vCPU / 8 GB / 80 GB disk. cx43 currently out-of-stock; will scale up agents when it returns.
  control_plane_nodepools = [
    {
      name        = "cp-fsn1"
      server_type = "cx33"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-nbg1"
      server_type = "cx33"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-hel1"
      server_type = "cx33"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    },
  ]

  # No dedicated agent nodes for MVP; control planes carry workloads. Add agents when cx43 stock returns.
  agent_nodepools = []

  # Combine CP+worker on the same nodes
  allow_scheduling_on_control_plane = true

  load_balancer_type     = "lb11"
  load_balancer_location = "fsn1"

  cni_plugin              = "cilium"
  enable_klipper_metal_lb = false

  # Enable Hubble (cilium flow visibility + UI) on top of module defaults
  cilium_merge_values = <<-EOT
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
  EOT

  enable_longhorn     = true
  disable_hetzner_csi = true

  enable_cert_manager   = true
  enable_metrics_server = true
  enable_rancher        = false

  automatically_upgrade_k3s = true
  automatically_upgrade_os  = true

  # Lock down SSH (22) and Kubernetes API (6443) to management CIDRs only.
  # Update var.management_cidrs from TF Cloud workspace vars if your IP changes.
  firewall_ssh_source      = var.management_cidrs
  firewall_kube_api_source = var.management_cidrs

  # Traefik: enable JSON access logs. Dashboard is NOT exposed via Ingress yet — wait for Authentik so it's behind auth.
  traefik_merge_values = <<-EOT
    logs:
      access:
        enabled: true
        format: json
  EOT

  # Bootstrap ArgoCD as part of cluster install. After this runs, ArgoCD owns the rest via the root-app
  # which watches k8s/apps in this repo and auto-syncs.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl apply -k https://github.com/wiktorkowalski/k8s-hetzner.git//k8s/bootstrap/argocd?ref=master
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
    kubectl apply -f https://raw.githubusercontent.com/wiktorkowalski/k8s-hetzner/master/k8s/root-app/root-application.yaml
  EOT
}
