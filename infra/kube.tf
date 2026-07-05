module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.19.3"

  hcloud_token = var.hcloud_token

  providers = {
    hcloud = hcloud
  }

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  # Dedicated key for remote cluster-health checks from Claude cloud envs
  # (.claude/skills/cluster-health). Revocable independently of the main key.
  ssh_additional_public_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPhUbOHYUj4v9vHlDFZKOSW8YijDlEUrR0tl/Jy+/gVr claude-cloud-cluster-health",
  ]

  network_region = var.network_region
  cluster_name   = var.cluster_name

  # Pin k3s minor channel so module defaults don't drift
  initial_k3s_channel = "v1.35"

  # Pin the exact k3s version (supersedes the channel for the system-upgrade plans).
  # The v1.35 channel endpoint on update.k3s.io intermittently serves the older v1.35.5+k3s1
  # (~2/12 requests observed 2026-06-26). system-upgrade-controller has no downgrade guard, so
  # each stale read cordoned a control plane and spawned a doomed downgrade job, leaving CPs
  # cordoned. Pinning the version stops the controller polling the channel entirely.
  # Bump this manually for future k3s upgrades.
  install_k3s_version = "v1.35.6+k3s1"

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

  # Control planes are dedicated (cx23, ~80GB root). Tainting them control-plane:NoSchedule
  # keeps workloads + Longhorn default disks off them — Longhorn storage lives on the 3 cx43
  # agents (one replica per DC). Previously `true`, which let a Longhorn replica fill cp-nbg1's
  # root disk → DiskPressure eviction storm (2026-06-04).
  allow_scheduling_on_control_plane = false

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
      metrics:
        enabled:
          - dns
          - drop
          - tcp
          - flow
          - icmp
          - http
          - port-distribution
    prometheus:
      enabled: true
  EOT

  enable_longhorn     = true
  longhorn_version    = "1.12.0" # PIN: unpinned HelmChart floats at "*" and auto-upgrades to latest on any helm-install re-run (terraform apply / CP reboot) — same class that broke Traefik 2026-06-26. Longhorn forbids version skips.
  disable_hetzner_csi = true

  enable_cert_manager   = true
  cert_manager_version  = "v1.20.3" # PIN: same reason — a floating latest-pull with a breaking CRD stops wildcard *.k8s.vicio.ovh renewal.
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

  # Pin the Traefik helm chart. Unpinned (module default ""), the k3s helm-controller pulls
  # the latest chart on every reconcile. Chart 41.0.0 removed the top-level `logs:` key
  # (split into `log:` + `accessLog:`), so the old values failed schema validation and the
  # helm-install-traefik job crashlooped. Pin + new schema keeps reconciles green.
  traefik_version = "41.0.0"

  # Traefik: JSON access logs + OTLP tracing to Tempo (chart 41.x schema)
  traefik_merge_values = <<-EOT
    log:
      level: INFO
    accessLog:
      enabled: true
      format: json
    ports:
      postgres:
        port: 5432
        expose:
          default: true
        exposedPort: 5432
        protocol: TCP
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
