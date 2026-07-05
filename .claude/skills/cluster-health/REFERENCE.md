# Cluster Health — Reference

## Known failure modes (check these first)

| Symptom | Likely cause | Fix |
|---|---|---|
| `exec format error` crashloop after image pull | Registry pull-through mirror cached wrong-arch image (recurring) | Bump the image tag to force a fresh pull (via git). Tempo chart uses flat `tempo.tag` key. |
| Pods stuck ContainerCreating with snapshot/layer errors after node rebuild | containerd snapshot corruption | Runbook: `docs/containerd-snapshot-recovery.md` — wipe containerd state on affected agent (SSH, ask first). |
| Node DiskPressure + eviction storm on a control plane | Longhorn replicas landed on CP root disk | CPs are tainted for this reason; check for pods tolerating the taint. Never schedule workloads on CPs. |
| Grafana dashboard provisioning error every ~30s | Duplicate dashboard ID `836461839904768` (apiserver dashboard) | Known noise; fix is deduping the dashboard in `k8s/apps/grafana-dashboards`, not restarting Grafana. |
| Prometheus/Loki PVC filling | Retention vs PVC size mismatch | Prometheus retentionSize capped at 42GiB (commit 7db852f). If >80% used, adjust retention in git, don't resize imperatively. |
| helm-install-traefik job crashloop | Chart schema drift when unpinned | `traefik_version` is pinned in `infra/kube.tf`; if crashlooping, compare values schema vs chart version. |
| SUC cordons CPs / k3s version flap | update.k3s.io served stale version | `install_k3s_version` pinned in terraform; check pin still present. |
| ArgoCD app stuck OutOfSync, admission rejects `null` field | SSA shrink-to-null on CRD object (e.g. IngressRoute `tls: {}`) | Delete + recreate the resource (safe for stateless CRs like IngressRoute); not a sync retry issue. |
| Kernel panic / node NotReady after eBPF activity | Beyla kprobes (root cause unknown) | Beyla must STAY disabled (`k8s/apps/beyla` auto-sync off). Never re-enable. |
| Trivy scan jobs failing for cilium + grafana images | clang missing in scan job (known, unfixed) | Expected noise — ignore unless it spreads to other images. |
| Chart repo `*.github.io` 404 | Helm gh-pages hosting flake (recurred twice) | Point `repoURL` at the raw gh-pages branch instead. |

## Useful commands

```bash
# Force ArgoCD refresh of everything
kubectl -n argocd patch app root-app --type=merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Sync a single app (safe)
kubectl -n argocd patch app <name> --type=merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
# or simpler: annotate refresh, ArgoCD auto-syncs within ~3 min

# Prometheus API via service proxy (works in both access modes; no port-forward)
kubectl get --raw '/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D'

# Longhorn volume detail
kubectl -n longhorn-system get volumes.longhorn.io -o \
  custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,NODE:.status.currentNodeID

# Evicted pod cleanup (safe)
kubectl get pods -A --field-selector=status.phase=Failed -o name | head  # inspect first
kubectl delete pods -A --field-selector=status.phase=Failed
```

## Cluster facts

- 3 CP (cx33, tainted, no workloads) + 3 agents (cx43) across fsn1/nbg1/hel1
- kube API `api.k8s.vicio.ovh:6443` — firewalled to home IP; SSH 22 open worldwide (key-only)
- Node sshd disallows TCP forwarding — no SSH tunnels; remote access = `k3s kubectl` executed on a CP (the connect script wraps this as `kubectl`)
- ArgoCD/Prometheus/Alertmanager/Grafana ingresses are home-IP-only (Traefik `homeonly` middleware) — from remote, use the API service proxy (`kubectl get --raw '/api/v1/namespaces/<ns>/services/<svc>:<port>/proxy/...'`)
- Everything is GitOps: config changes via git commit to master, ArgoCD syncs ~3 min
- All observability in `monitoring` namespace; storage Longhorn 3-replica

## Remote environment setup (one-time, for the user)

One secret is required in any remote env (Claude Code cloud / another machine):

- `CLUSTER_SSH_KEY_B64` — `base64 < <path-to-cluster-ssh-private-key>` (the key whose
  content is `ssh_private_key` in `infra/terraform.tfvars`)

Optional: `KUBECONFIG_B64` (`cd infra && terraform output -raw kubeconfig | base64`) —
only used for the direct path when the env's egress IP is allowlisted; otherwise ignored.

Cloud env **Setup script** (the sandbox image has no ssh client or kubectl; the SSH
mode only needs the ssh client):

```bash
#!/bin/bash
# ssh client for cluster-health. update is best-effort: the sandbox image carries
# unrelated PPAs (e.g. ondrej/php) whose metadata changes make a strict update exit 100.
command -v ssh >/dev/null && exit 0
SUDO=""; [ "$(id -u)" != "0" ] && SUDO=sudo
$SUDO apt-get update --allow-releaseinfo-change -qq || true
$SUDO apt-get install -y -qq openssh-client
```

Network egress to `api.k8s.vicio.ovh` port 22 must be allowed. After a cluster rebuild,
regenerate `scripts/known_hosts` (command in the connect.sh header) and re-derive the key
if it changed.
