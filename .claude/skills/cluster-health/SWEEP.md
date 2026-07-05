# Cluster Health — Sweep Commands

Run all of these; collect findings, don't stop at the first hit. Every command works
in both access modes (direct and kubectl-over-SSH). `kubectl port-forward` does NOT
work in SSH mode — that's why Alertmanager/Prometheus go through the API service proxy.

```bash
# Firing alerts (source of truth — start here)
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

Node conditions at a glance:

```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,MEM:.status.conditions[?(@.type=="MemoryPressure")].status,DISK:.status.conditions[?(@.type=="DiskPressure")].status'
```

PVC fill levels (known risk: Prometheus, Loki) — Prometheus via service proxy:

```bash
kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$(python3 -c "import urllib.parse;print(urllib.parse.quote('kubelet_volume_stats_used_bytes/kubelet_volume_stats_capacity_bytes > 0.8'))")"
```

Expected noise (don't report as findings): the `Watchdog` alert always fires by
design; `beyla` app is intentionally OutOfSync (auto-sync disabled, must stay so);
trivy scan jobs for cilium + grafana images fail (known, unfixed).
