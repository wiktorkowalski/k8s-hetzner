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

  # Blue/green control-plane swap in progress: the cx33 nodepools are the existing CPs (created
  # 2026-05-23 during the fresh-start bootstrap). The cx23 nodepools are the new dedicated CPs.
  # Both run together for one apply; in a follow-up PR we'll remove the cx33 entries so only the
  # cx23 CPs remain (etcd transitions 3 -> 6 -> 3 cleanly).
  control_plane_nodepools = [
    # Existing — will be removed in next PR
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
    # New dedicated CPs (cx23 — 2 vCPU / 4 GB) — sufficient for CP-only duty when we add proper workers
    {
      name        = "cp-fsn1-v2"
      server_type = "cx23"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-nbg1-v2"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-hel1-v2"
      server_type = "cx23"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    },
  ]

  # First real worker. cx43: 8 vCPU / 16 GB / 160 GB disk.
  # Stock as of 2026-05-23T16: fsn1 OUT, nbg1 OUT (was IN earlier but went OUT mid-apply),
  # hel1 IN. Moving from nbg1 to hel1.
  agent_nodepools = [
    {
      name        = "agent-hel1"
      server_type = "cx43"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    },
  ]

  # Combine CP+worker on the same nodes
  allow_scheduling_on_control_plane = true

  load_balancer_type     = "lb11"
  load_balancer_location = "fsn1"

  cni_plugin              = "cilium"
  enable_klipper_metal_lb = false

  # Enable Hubble (cilium flow visibility + UI) on top of module defaults.
  # Hubble UI service is ClusterIP only — reach it with
  #   kubectl -n kube-system port-forward svc/hubble-ui 12000:80
  # We'll put it behind Authentik once that's installed (follow-up PR).
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

  # Lock down the Kubernetes API (6443) to management CIDRs only.
  # SSH stays open (module default 0.0.0.0/0) because the module's remote-exec provisioner needs
  # to reach the VMs from wherever terraform runs (TF Cloud workers / GH runners). SSH itself uses
  # ed25519 key-only auth (no passwords) so brute force is impractical.
  firewall_kube_api_source = var.management_cidrs

  # Traefik: enable JSON access logs. Dashboard is NOT exposed via Ingress yet — wait for Authentik so it's behind auth.
  traefik_merge_values = <<-EOT
    logs:
      access:
        enabled: true
        format: json
  EOT

  # Bootstrap ArgoCD as part of cluster install. After this runs, ArgoCD owns the rest via the
  # root-app which watches k8s/apps in this repo and auto-syncs.
  # NB: --server-side is required because ArgoCD v3's CRDs (especially applicationsets) exceed
  # kubectl's 256KB client-side annotation limit. The module's `kubectl apply -k` of the
  # extra-manifests/ kustomization is client-side, which is why that kustomization only creates
  # the argocd namespace — the heavy lifting is here with --server-side.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl apply -k https://github.com/wiktorkowalski/k8s-hetzner.git//k8s/bootstrap/argocd?ref=master --server-side --force-conflicts
    kubectl wait --for=condition=established --timeout=120s crd/applications.argoproj.io
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
    kubectl apply -f https://raw.githubusercontent.com/wiktorkowalski/k8s-hetzner/master/k8s/root-app/root-application.yaml --server-side --force-conflicts
  EOT
}
