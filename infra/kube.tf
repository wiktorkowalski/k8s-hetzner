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
  initial_k3s_channel = "v1.35"

  # 3 cx33 control planes — one per DC for geo-HA + etcd quorum.
  # cx33 (4 vCPU / 8 GB / 80 GB) needed for CP + DaemonSet monitoring (Alloy, Beyla, node-exporter).
  # cx23 (4 GB) OOM'd with the full observability stack.
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

  # 3 cx43 worker nodes (8 vCPU / 16 GB / 160 GB each) — one per DC for full geo-coverage.
  # Real workload HA + perfect Longhorn 3-replica spread (one replica per DC).
  # ORDER MATTERS: agent-hel1 and agent-nbg1 are at positions 0 and 1 in TF state (created
  # during the 2026-05-23 fresh apply). New agent-fsn1 goes at the END to avoid renumbering
  # the existing two via count.index-based subnet assignment (see [[Gotchas]] in CONTEXT.md).
  agent_nodepools = [
    {
      name        = "agent-hel1"
      server_type = "cx43"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "agent-nbg1"
      server_type = "cx43"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "agent-fsn1"
      server_type = "cx43"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
  ]

  # Combine CP+worker on the same nodes
  allow_scheduling_on_control_plane = true

  load_balancer_type     = "lb11"
  load_balancer_location = "fsn1"
  lb_hostname            = "${var.cluster_subdomain}.${var.domain}"

  # DNS round-robin API HA: api.k8s.vicio.ovh resolves to all 3 CP IPs.
  # Kubeconfig uses this hostname instead of a single CP IP, so kubectl
  # survives any single CP failure (no health checks though).
  additional_tls_sans       = ["api.${var.cluster_subdomain}.${var.domain}"]
  kubeconfig_server_address = "api.${var.cluster_subdomain}.${var.domain}"

  enable_delete_protection = {
    floating_ip   = true
    load_balancer = true
    volume        = true
  }

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

  # Reserve resources for kubelet/containerd so workload OOM can't starve the node
  k3s_global_kubelet_args = [
    "kube-reserved=cpu=200m,memory=512Mi",
    "system-reserved=cpu=100m,memory=256Mi",
  ]

  # Restrict kured reboots to Saturday 3-6 AM Warsaw time
  kured_options = {
    "reboot-days" = "sa"
    "start-time"  = "3am"
    "end-time"    = "6am"
    "time-zone"   = "Europe/Warsaw"
  }

  # Lock down the Kubernetes API (6443) to management CIDRs only.
  # SSH stays open (module default 0.0.0.0/0) because the module's remote-exec provisioner needs
  # to reach the VMs from wherever terraform runs (TF Cloud workers / GH runners). SSH itself uses
  # ed25519 key-only auth (no passwords) so brute force is impractical.
  firewall_kube_api_source = var.management_cidrs

  # Traefik: JSON access logs + OTLP tracing to Tempo
  traefik_merge_values = <<-EOT
    logs:
      access:
        enabled: true
        format: json
    tracing:
      otlp:
        enabled: true
        grpc:
          enabled: true
          endpoint: tempo.monitoring.svc:4317
          insecure: true
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
