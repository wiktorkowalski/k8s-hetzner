# Cluster Health — Glance Mode (preventive checkup)

Trend-focused daily checkup: "is anything heading toward a problem?" **Report-only —
apply NO fixes in glance mode**, not even the safe ones. If something looks actionable,
say so and suggest a full `/cluster-health` run instead. Connect first (SKILL.md step 1).

Prometheus helper (service proxy, works in every access mode):

```bash
bash .claude/skills/cluster-health/scripts/promq.sh '<promql>'
```

## Checks — run all, then report one compact table

```bash
# 1. Firing alerts other than Watchdog (baseline sanity)
kubectl get --raw '/api/v1/namespaces/monitoring/services/kube-prometheus-stack-alertmanager:9093/proxy/api/v2/alerts?active=true&silenced=false&inhibited=false' \
  | python3 -m json.tool | grep '"alertname"' | grep -v Watchdog

# 2. PVC trajectory — flag: filling within 14d AND already >70% used
bash .claude/skills/cluster-health/scripts/promq.sh \
  '(predict_linear(kubelet_volume_stats_available_bytes[24h], 14*86400) < 0) and (kubelet_volume_stats_used_bytes/kubelet_volume_stats_capacity_bytes > 0.7)'
# current fill levels for the report:
bash .claude/skills/cluster-health/scripts/promq.sh \
  'topk(5, kubelet_volume_stats_used_bytes/kubelet_volume_stats_capacity_bytes)'

# 3. Restart delta last 24h (kured reboots Sat 3-6am Warsaw bump everything — baseline)
bash .claude/skills/cluster-health/scripts/promq.sh \
  'sum by (namespace,pod) (increase(kube_pod_container_status_restarts_total[24h])) > 0'

# 4. Ingress certs <21d to expiry (LE renews at 30d — <21d means renewal is stuck)
bash .claude/skills/cluster-health/scripts/promq.sh \
  '(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 21'

# 5. Node pressure + memory headroom <15%
bash .claude/skills/cluster-health/scripts/promq.sh \
  'kube_node_status_condition{condition=~"DiskPressure|MemoryPressure|PIDPressure",status="true"} == 1'
bash .claude/skills/cluster-health/scripts/promq.sh \
  'node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.15'

# 6. Longhorn storage headroom (>80% node usage = start planning)
bash .claude/skills/cluster-health/scripts/promq.sh \
  'longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes > 0.8'

# 7. Failed jobs + pending pods
bash .claude/skills/cluster-health/scripts/promq.sh 'kube_job_status_failed > 0'
kubectl get pods -A --field-selector=status.phase=Pending 2>/dev/null | grep -v "^NAME" || true

# 8. GitOps drift
kubectl -n argocd get applications.argoproj.io | grep -vE 'Synced\s+Healthy|^NAME|beyla'
```

Empty result = healthy for that check. Expected noise: see SWEEP.md (Watchdog, beyla,
trivy cilium/grafana, Prometheus PVC 78-85%, Saturday restart bumps).

**Long-horizon items to mention when relevant:** kubeconfig client cert expires
2027-05-24 (static copies in Claude cloud envs need re-pasting before then); Longhorn
was at ~65% per node on 2026-07-05 — if check 6 fires, capacity planning time.

**Known gap:** node-exporter filesystem metrics (`node_filesystem_*`) are not scraped,
so node ROOT disk usage is invisible here — only the DiskPressure condition (check 5)
covers it, which fires late. Flag this if root-disk trouble is suspected.

## Report format

One table: check | status (OK / ⚠ detail) | trend note if interesting. End with a
one-line verdict. If anything is ⚠, recommend `/cluster-health` (full mode) — do not
fix from glance.
