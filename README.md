# k8s-hetzner

K3s cluster on Hetzner Cloud, provisioned by Terraform via the
[`kube-hetzner`](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)
module. ArgoCD pulls applications from this repo (GitOps).

## Topology

- 3× `cx33` VMs (4 vCPU / 8 GB / 80 GB) — one in each of `fsn1`,
  `nbg1`, `hel1`. Each is both control plane and worker.
- 1× Hetzner Load Balancer (`lb11`, `fsn1`) for Traefik ingress.
- Private network `10.0.0.0/8`.
- Cilium + Hubble, Longhorn, cert-manager, Traefik, metrics-server.
- ArgoCD + sealed-secrets installed via GitOps.

## Repo layout

```
infra/                 # Terraform: VMs, LB, network, DNS, k3s bootstrap
docs/adr/              # Architecture decisions
docs/                  # Runbooks and operational guides
k8s/
├── bootstrap/argocd/  # Raw ArgoCD install manifests (applied by `kube-hetzner` extra_kustomize)
├── apps/              # ArgoCD Applications (one per app)
└── root-app/          # The "app of apps" — watches k8s/apps/
.github/workflows/     # CI: terraform plan/apply + yaml/kubeconform validation
```

## Operating model

1. PR → `terraform-plan.yml` + `k8s-validate.yml` run.
2. Merge to `master` → `terraform-apply.yml` runs in TF Cloud → cluster
   reconciles. ArgoCD picks up `k8s/apps` changes automatically (sync
   policy = automated + selfHeal + prune).
3. New apps land via PR adding `k8s/apps/<name>/application.yaml`.

## Bootstrap (fresh cluster)

Triggered automatically by `terraform apply` via the module's
`extra_kustomize_deployment_commands`:

```
kubectl apply -k https://github.com/wiktorkowalski/k8s-hetzner.git//k8s/bootstrap/argocd?ref=master
kubectl apply -f https://raw.githubusercontent.com/wiktorkowalski/k8s-hetzner/master/k8s/root-app/root-application.yaml
```

After the TF apply completes (~10 min), ArgoCD self-syncs and owns the
rest.

## TF Cloud workspace variables

Required (set in `app.terraform.io/wiktor9196667/workspaces/k8s-hetzner`):

**Environment variables (sensitive):**
- `HCLOUD_TOKEN`
- `CLOUDFLARE_API_TOKEN`

**Terraform variables:**
- `cloudflare_zone_id`
- `domain` (e.g. `vicio.ovh`)
- `ssh_public_key` (content)
- `ssh_private_key` (content, sensitive)
- `management_cidrs` (optional — defaults to current operator IP)

## Reset playbook

See `docs/cluster-reset-runbook.md`. Two paths depending on Hetzner
stock (ADR-0002):
- Stock present: `terraform destroy` then `terraform apply`.
- Stock absent: in-place rebuild via `hcloud server rebuild` per VM.

Always start a reset by verifying current stock with a throwaway
`hcloud server create --start-after-create=false` test.

## Costs

| Item | Cost (€/mo) |
| --- | --- |
| 3× cx33 | 23.88 |
| 1× lb11 | ~6 |
| Network + IPv4 + traffic | ~3 |
| **Subtotal** | **~33** |

Excludes follow-up phases (Longhorn backup target on Hetzner Storage
Box: +€3.20/mo per TB; Cloudflare R2 for etcd snapshots + CNPG WAL:
~free at homelab scale).

## Status

Fresh cluster pending — destroyed 2026-05-23, awaiting apply on
v2.19.3 module.

Follow-up PRs planned (one per app, each verified before the next):
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- Loki + promtail
- Tempo
- CNPG operator
- Authentik (on CNPG)
- Headlamp
- Backup wiring: Longhorn → Storage Box, etcd snapshots → R2, CNPG
  WAL → R2
