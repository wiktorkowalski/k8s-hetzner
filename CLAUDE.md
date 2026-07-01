# CLAUDE.md

## What this repo is

k3s cluster on Hetzner Cloud, managed by Terraform (infra/) + ArgoCD (k8s/). 
Domain: `*.k8s.vicio.ovh` via Cloudflare DNS-only (grey cloud, no proxy).

## Repo structure

```
infra/                  # Terraform — kube-hetzner module v2.19.3, HCL + tfvars
k8s/
  root-app/             # ArgoCD app-of-apps, watches k8s/apps/ recursively
  apps/<name>/          # Each subdir has one application.yaml (ArgoCD Application CRD)
  base/<name>/          # Raw K8s manifests referenced by apps (e.g. cert-manager-issuers, traefik-config)
  bootstrap/argocd/     # ArgoCD install + ingress, applied by Terraform on first deploy
  config.env            # Cluster config sourced by bootstrap scripts
docs/                   # Runbooks
```

**WARNING:** root-app uses `directory.recurse: true` on `k8s/apps/`. Only ArgoCD Application CRDs belong there — any other YAML placed in that directory tree will be applied to the cluster.

Raw K8s manifests go in `k8s/base/` and are referenced by an Application via `source.path`.

## Cluster topology

- 3 control planes (cx33, 4 vCPU / 8 GB) — fsn1, nbg1, hel1. Not for workloads. (cx23/4GB OOM'd with the observability DaemonSets, upsized.)
- 3 agents (cx43, 8 vCPU / 16 GB) — fsn1, nbg1, hel1. All workloads here.
- OS: openSUSE MicroOS, kernel 7.0.12-1-default (was 7.0.9 when Beyla panicked; auto-upgrades via automatically_upgrade_os)
- CNI: Cilium 1.17 with Hubble
- Storage: Longhorn, 3 replicas across DCs
- Ingress: Traefik v3.7 behind Hetzner LB, PROXY protocol enabled

## Kubeconfig

```
cd infra && terraform output -raw kubeconfig > ~/.kube/config
```
API endpoint: `api.k8s.vicio.ovh:6443` (round-robin across 3 CPs).

## Working with ArgoCD apps

- Helm apps: `k8s/apps/<name>/application.yaml` with `source.repoURL` pointing to a Helm repo and values in `valuesObject`.
- Manifest apps: `k8s/apps/<name>/application.yaml` with `source.path` pointing to `k8s/base/<name>/`.
- After pushing, ArgoCD auto-syncs within ~3 min. Force with: `kubectl -n argocd patch app root-app --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`
- All apps use `ServerSideApply=true`. Don't mix with `--force` in manual syncs.

## Ingress access control

Admin services are restricted to home IP via Traefik IPAllowList middleware.

- Middleware: `k8s/base/traefik-config/home-only-middleware.yaml` — `homeonly` in `traefik` namespace
- To restrict a service: add annotation `traefik.io/router.middlewares: traefik-homeonly@kubernetescrd` to its Ingress
- Currently applied to: ArgoCD, Prometheus, Alertmanager, Grafana
- Public services: omit the annotation
- Cloudflare MUST stay grey-cloud (DNS-only) — orange-cloud proxying would mask real client IPs and break the allowlist

## Beyla — DISABLED

Beyla's kprobe eBPF triggers kernel panics on MicroOS 7.0.9-1-default (CVE-2026-43010). Auto-sync is disabled in `k8s/apps/beyla/application.yaml`. DaemonSet is deleted from the cluster. Do not re-enable until MicroOS kernel is updated.

## Grafana chart quirk

kube-prometheus-stack 85.2.1 bundles Grafana chart 12.3.3 which has a template bug: `persistence.enabled=true` + `persistence.type=emptyDir` renders no Deployment or StatefulSet. Use `persistence.enabled: false`.

## Terraform

- State in Terraform Cloud
- Secrets in `infra/terraform.tfvars` (gitignored) + TF Cloud env vars
- SealedSecrets: reseal after any cluster rebuild (`kubeseal --cert` with new cluster's cert)

## Conventions

- Commit directly to master for infra/config changes (no feature branches for single-commit fixes)
- PR for multi-commit features or anything that benefits from review
- Commit messages: `fix:` / `feat:` / `docs:` prefix
