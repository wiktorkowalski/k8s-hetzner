---
name: cluster-health
description: Diagnose and fix the k8s-hetzner cluster (k3s on Hetzner) from anywhere — sweeps firing alerts, nodes, pods, ArgoCD apps, Longhorn volumes, certs and events, then applies safe fixes automatically and asks before risky ones. Works remotely by running kubectl on a control plane over SSH when the kube API (home-IP-only) is unreachable. Use when the user asks to check/health-check the cluster, says something is down/broken/alerting, or invokes /cluster-health.
---

# Cluster Health

Diagnose-and-fix loop for the k3s cluster (`api.k8s.vicio.ovh`). Works from the home
network (direct kubectl) or any remote env (kubectl-over-SSH via a control plane —
node sshd forbids TCP forwarding, so there is no tunnel; `kubectl port-forward` does
NOT work remotely, use the API service proxy as shown below).

## 1. Connect

```bash
eval "$(bash .claude/skills/cluster-health/scripts/connect.sh)"
kubectl get nodes   # sanity — works identically in both modes
```

If the script errors about missing secrets, relay its message to the user verbatim
(remote env needs `CLUSTER_SSH_KEY_B64`; `KUBECONFIG_B64` only enables the direct path).

## 2. Sweep — run all, don't stop at the first hit

```bash
# Firing alerts (source of truth — start here). Service proxy, works in both modes:
kubectl get --raw '/api/v1/namespaces/monitoring/services/kube-prometheus-stack-alertmanager:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false' \
  | python3 -m json.tool | grep -E '"alertname"|"namespace"|"severity"|"summary"|"description"'

kubectl get nodes -o wide                                   # Ready? kernel drift?
kubectl top nodes; kubectl top pods -A --sort-by=memory | head -15
kubectl get pods -A | grep -vE 'Running|Completed'          # crashloops, Pending, ImagePull…
kubectl get pods -A -o wide | awk '$5 > 20'                 # restart hotspots
kubectl -n argocd get applications.argoproj.io              # Synced/Healthy for every app
kubectl -n longhorn-system get volumes.longhorn.io          # robustness must be healthy
kubectl -n longhorn-system get nodes.longhorn.io            # disk pressure / schedulable
kubectl get certificates -A | grep -v True                  # cert-manager
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30
```

PVC fill levels (known risk: Prometheus, Loki) — query Prometheus via service proxy:

```bash
kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$(python3 -c "import urllib.parse;print(urllib.parse.quote('kubelet_volume_stats_used_bytes/kubelet_volume_stats_capacity_bytes > 0.8'))")"
```

## 3. Diagnose

For each finding: `kubectl describe` + `kubectl logs --previous` + recent events.
Check [REFERENCE.md](REFERENCE.md) **known failure modes first** — most incidents on
this cluster are recurrences (wrong-arch image, containerd snapshot corruption,
Longhorn disk pressure, ArgoCD SSA quirk…). Runbooks live in `docs/`.

## 4. Fix policy

**Auto-apply (safe, no confirmation):**
- Delete crashlooping / stuck / Evicted pods (controller recreates them)
- `kubectl rollout restart` deploy/sts/ds
- ArgoCD refresh/hard-refresh/sync of an app (`kubectl -n argocd patch app …`)
- Uncordon a node that is Ready but cordoned with no active maintenance
- Kill and re-create a stuck SSH mux session (`rm ${TMPDIR:-/tmp}/cluster-health/ssh-mux`)

**Ask the user first (AskUserQuestion):**
- Node drain, reboot, cordon; anything via SSH on the node itself
- Deleting/resizing PVCs or Longhorn volumes; any Longhorn salvage/replica ops
- Scaling workloads, editing live resources (`kubectl edit/patch` of config)
- Git commits (config fixes belong in git — propose the diff, ask, then commit to master)
- Anything touching etcd, terraform, or Hetzner resources

Never `kubectl apply` config imperatively — this repo is GitOps; config changes go
through git + ArgoCD. Never re-enable Beyla.

## 5. Verify & report

After each fix re-check the specific symptom AND re-run the alert query (step 2) —
logs and data flow, not just pod status. Finish with a short report: findings,
fixes applied, what needs the user, what to watch. If the thermal-printer MCP is
available (local sessions), print the summary.
