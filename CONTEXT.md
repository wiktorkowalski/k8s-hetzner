# Context

Glossary for this repo. Operational/infra terminology. Update inline as
terms are clarified.

## Cluster

The k3s deployment running on the Hetzner VMs. Freshly rebuilt
2026-05-23 on `kube-hetzner` v2.19.3, k3s v1.32. State is
`destroy → apply`-able when Hetzner stock is present (see ADR-0002).

## VM

A Hetzner Cloud server. Currently `cx33` (4 vCPU / 8 GB / 80 GB) in
each of `fsn1`, `nbg1`, `hel1`. Each VM acts as **both control plane
and worker** (`allow_scheduling_on_control_plane = true`). The cluster
has no dedicated agent nodepool yet; one or two will be added once
`cx43` is reliably back in Hetzner stock.

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

`var.management_cidrs` is the allow-list for SSH (22) and the
Kubernetes API server (6443). Both are firewalled at Hetzner-level
to these CIDRs only. Update the variable when the operator's public
IP changes.

## MVP cluster

The minimum app set deployed onto a freshly-built [[Cluster]]: ArgoCD
+ sealed-secrets, plus what the [[Module]] installs (Traefik,
cert-manager, Longhorn, metrics-server, Cilium with Hubble).
Everything else (LGTM, Authentik, CNPG, Headlamp, backup config) lands
in subsequent PRs.

## Root app

`k8s/root-app/root-application.yaml` is the ArgoCD `Application` that
watches `k8s/apps/` and creates child Applications for everything in
there. App-of-apps pattern.

## Sealed key

The asymmetric key pair held by the sealed-secrets controller. A fresh
[[Cluster]] generates a new private key on first install, so any
SealedSecret manifests committed against a previous cluster cannot be
decrypted until re-sealed with the new public cert.
