# Context

Glossary for this repo. Operational/infra terminology. Update inline as
terms are clarified.

## Cluster

The k3s deployment running on the Hetzner VMs. Freshly rebuilt
2026-05-23 on `kube-hetzner` v2.19.3, k3s v1.32. State is
`destroy → apply`-able when Hetzner stock is present (see ADR-0002).

## VM

A Hetzner Cloud server. Current topology:

- **3× cx23** control planes (2 vCPU / 4 GB / 40 GB) — one each in
  `fsn1`, `nbg1`, `hel1`. CP-only; workloads stay off them by
  scheduler preference (CPs are small) even though
  `allow_scheduling_on_control_plane = true` is set as a fallback.
- **3× cx43** agents (8 vCPU / 16 GB / 160 GB) — one each in `fsn1`,
  `nbg1`, `hel1`. Workload HA per-DC: any single DC can go dark
  without taking workloads down. Longhorn 3-replica spreads one
  replica per DC.

## Reset

Wiping cluster state. Two paths depending on Hetzner stock (see
[[0002-capacity-aware-cluster-resets]]):
- **Fresh** (stock present): `terraform destroy` then `terraform apply`.
- **In-place** (stock absent): `hcloud server rebuild` per VM, taint
  module null_resources, apply. Runbook: `docs/cluster-reset-runbook.md`.

## Module

`kube-hetzner/kube-hetzner/hcloud` pinned to **v2.19.3**. Provisions
VMs, Hetzner LB, private network, firewall, and bootstraps k3s. Also
runs `extra_kustomize_deployment_commands` after install — currently
used to install ArgoCD and apply the [[Root app]].

## LB

Hetzner load balancer named `<cluster_name>-traefik`. Created by the
cluster's hcloud-cloud-controller-manager when the Traefik Service
applies. The Service annotation `load-balancer.hetzner.cloud/name`
makes future cluster resets adopt the same LB by name (preserves the
IP when not destroyed). DNS records `k8s.<domain>` and
`*.k8s.<domain>` point here.

## Management CIDRs

`var.management_cidrs` is the allow-list for the Kubernetes API server
(6443) only. **SSH (22) is intentionally NOT locked** to these CIDRs
— see [[Gotchas]] for why.

## MVP cluster

The minimum app set deployed onto a freshly-built [[Cluster]]: ArgoCD
+ sealed-secrets, plus what the [[Module]] installs (Traefik,
cert-manager, Longhorn, metrics-server, Cilium with Hubble).
Everything else (LGTM, Authentik, CNPG, Headlamp, backup config) lands
in subsequent PRs.

## Observability stack

Deployed 2026-05-24. All in `monitoring` namespace, managed by ArgoCD.

- **kube-prometheus-stack** — Prometheus (20Gi, 15d retention),
  Grafana (ClusterIP, port-forward only until Authentik), Alertmanager
  (2Gi), node-exporter (6 pods), kube-state-metrics, Prometheus
  operator. k3s-incompatible monitors disabled (controller-manager,
  scheduler, proxy, etcd).
- **Loki** — SingleBinary mode, filesystem storage (10Gi Longhorn).
  Log aggregation for all pods.
- **Tempo** — Single binary, filesystem storage (10Gi Longhorn), 72h
  retention. OTLP gRPC+HTTP receivers enabled.
- **Alloy** — DaemonSet (6 pods, all nodes). Ships pod logs → Loki.
  OTLP receiver for traces → Tempo.
- **Beyla** — DaemonSet (6 pods, all nodes). eBPF auto-instrumentation
  for HTTP/gRPC. Sends traces → Tempo. Requires `privileged: true` +
  `spc_t` SELinux context on MicroOS — see [[Gotchas]].

Grafana datasources provisioned: Prometheus (default), Loki, Tempo.
Cross-linked: Loki traceID → Tempo, Tempo → Loki logs, Tempo service
map → Prometheus.

## API HA

`api.k8s.vicio.ovh` is a DNS round-robin A record pointing to all 3
CP public IPs. Kubeconfig uses this hostname instead of a single CP
IP. No health checks — if one CP dies, ~1/3 of requests fail until
DNS cache expires (TTL 300s). The API server TLS cert includes
`api.k8s.<domain>` as a SAN via `additional_tls_sans`.

## Root app

`k8s/root-app/root-application.yaml` is the ArgoCD `Application` that
watches `k8s/apps/` and creates child Applications for everything in
there. App-of-apps pattern. **Requires `directory.recurse: true`** —
see [[Gotchas]].

## Sealed key

The asymmetric key pair held by the sealed-secrets controller. A fresh
[[Cluster]] generates a new private key on first install, so any
SealedSecret manifests committed against a previous cluster cannot be
decrypted until re-sealed with the new public cert.

## Gotchas

Hard-won findings from the 2026-05-23 rebuild. Worth keeping a feel
for, especially before another cluster reset.

### `firewall_ssh_source` lockdown breaks TF Cloud apply

The `kube-hetzner` module installs k3s via `provisioner "remote-exec"`
from wherever Terraform runs. TF Cloud's workers run on arbitrary AWS
IPs — locking SSH (port 22) to a fixed CIDR via `firewall_ssh_source`
will firewall those workers out and the apply hangs/fails at the k3s
install step. **Lock `firewall_kube_api_source` (6443) only**; SSH
key-only auth is the safety net for port 22.

### `extra_kustomize_deployment_commands` is silently gated

The module's `terraform_data.kustomization_user_deploy` only runs when
`infra/extra-manifests/` contains at least one `.yaml.tpl` file
(`count = length(local.user_kustomization_templates) > 0 ? 1 : 0`).
Without that directory the entire `extra_kustomize_deployment_commands`
block is silently skipped — no warning, no error. For ArgoCD
auto-bootstrap to fire on fresh apply, `infra/extra-manifests/` must
exist with at minimum a `kustomization.yaml.tpl` referencing one
resource.

### ArgoCD v3 CRDs exceed kubectl's client-side annotation limit

`kubectl apply` (client-side) stores a copy of the manifest in the
`kubectl.kubernetes.io/last-applied-configuration` annotation. ArgoCD
v3's `applicationsets.argoproj.io` CRD exceeds the 256 KB annotation
limit. Any `kubectl apply -k` of the ArgoCD bootstrap manifest fails
mid-way with `metadata.annotations: Too long`. Always pass
`--server-side --force-conflicts` for ArgoCD applies — including in
`extra_kustomize_deployment_commands`. The module's own
`kubectl apply -k /var/user_kustomize/` is client-side, so the
`extra-manifests` kustomization must stay small (namespace-only) and
the heavy ArgoCD install runs from the deployment-commands hook with
`--server-side`.

### Root app needs `directory.recurse: true`

ArgoCD's Directory source is non-recursive by default. With
`path: k8s/apps`, it reads only YAMLs at the top level of `k8s/apps/`
— `k8s/apps/<name>/application.yaml` files in subfolders are
**silently ignored**. Root-app reports Synced+Healthy with zero
managed resources. Fix: add `spec.source.directory.recurse: true`.

### Removing the original "first" control plane breaks bootstrap state

`kube-hetzner` tracks a `first_control_plane_node_id` in TF state
(referenced by `terraform_data.kustomization` and `agent_config`
provisioners). When that exact CP VM is destroyed (e.g., by removing
its nodepool entry or via `terraform_apply -replace`), subsequent
remote-execs in the same or later applies fail because they try to
SSH to the now-dead IP — even though the cluster's etcd has a leader
elsewhere. **Symptoms**: `dial tcp <dead-ip>:22: connection refused`
or apply hangs on `Waiting for the cluster to become ready...` until
its 6m timeout. Worse: destroying multiple CPs in parallel (as a
single `terraform apply` does for symmetric nodepool reductions) loses
etcd quorum before the cluster can gracefully reconcile member
removal, leaving the API server returning `ServiceUnavailable`. **A
blue/green CP swap is not safe via `terraform apply` alone** — the
recovery path is a full destroy+recreate (or, if VMs must be
preserved, manual etcd member surgery and state mv).

### Beyla requires privileged + spc_t on MicroOS

Beyla's eBPF memlock setup needs to detect cgroup memory accounting.
Unprivileged mode with individual capabilities (`BPF`, `SYS_PTRACE`,
`PERFMON`, `SYS_ADMIN`, etc.) is NOT sufficient — the chart's
`privileged: true` flag only adds capabilities, it does **not** set
`container.securityContext.privileged: true`. You must explicitly set
`securityContext.privileged: true` in the Helm values. Additionally,
MicroOS SELinux enforcing requires `seLinuxOptions.type: spc_t`.

### kube-hetzner indexes subnets by `count.index`

`hcloud_network_subnet.control_plane` uses `count = length(var.control_plane_nodepools)`
and computes `ip_range = local.network_ipv4_subnets[var.subnet_amount - 1 - count.index]`.
Removing entries from `control_plane_nodepools` (or `agent_nodepools`)
shifts every later entry's `count.index` down, which means every
remaining subnet wants a *different* IP range — forcing all the
later VMs to be replaced because their `network` block changes. The
**`count = 0` trick** keeps list positions stable: entries stay in
place, only the VM-creating `for_each` over `local.control_plane_nodes`
loses keys.
