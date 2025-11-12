# Monitoring Stack (kube-prometheus-stack)

Complete monitoring solution including Prometheus, Grafana, and Alertmanager.

## Installation

This is automatically installed via ArgoCD in the `monitoring` namespace.

## Components

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and management
- **Node Exporter**: Node-level metrics
- **Kube State Metrics**: Kubernetes object metrics
- **Prometheus Operator**: Manages Prometheus instances

## Access

- **Grafana**: https://grafana.k8s.yourdomain.com
  - Username: `admin`
  - Password: `admin` (CHANGE THIS!)

- **Prometheus**: https://prometheus.k8s.yourdomain.com
- **Alertmanager**: https://alertmanager.k8s.yourdomain.com

## Change Grafana Password

**Important**: Change the default Grafana password!

### Option 1: Via UI
1. Log in to Grafana
2. Click your profile icon → Preferences → Change Password

### Option 2: Via Sealed Secret (Recommended)

```bash
# Create a secret with your password
kubectl create secret generic grafana-admin-password \
  --from-literal=admin-password='YourSecurePassword123!' \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > grafana-admin-password-sealed.yaml

# Commit the sealed secret
git add grafana-admin-password-sealed.yaml
git commit -m "Add Grafana admin password"
```

Then update the kube-prometheus-stack values to use the secret:

```yaml
grafana:
  admin:
    existingSecret: grafana-admin-password
    userKey: admin-user
    passwordKey: admin-password
```

## Grafana Datasources

Pre-configured datasources:
- **Prometheus**: Default, includes all Kubernetes metrics
- **Loki**: For logs (from logging stack)
- **Tempo**: For distributed tracing (from tracing stack)

## Default Dashboards

Kube-prometheus-stack includes many pre-built dashboards:
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace
- Kubernetes / Compute Resources / Node
- Kubernetes / Compute Resources / Pod
- Kubernetes / Networking / Cluster
- Node Exporter / Nodes
- Prometheus / Overview
- And many more...

## Custom Alerts

Create custom PrometheusRule resources:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: custom-rules
      interval: 30s
      rules:
        - alert: HighPodMemory
          expr: |
            sum(container_memory_usage_bytes{container!=""}) by (pod, namespace)
            / sum(container_spec_memory_limit_bytes{container!=""}) by (pod, namespace)
            > 0.9
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} high memory usage"
            description: "Pod is using {{ $value | humanizePercentage }} of its memory limit"
```

## Configure Alertmanager

Edit the Alertmanager configuration to route alerts:

```yaml
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'null'
      routes:
        - match:
            alertname: Watchdog
          receiver: 'null'
        - match:
            severity: critical
          receiver: 'critical'
    receivers:
      - name: 'null'
      - name: 'critical'
        slack_configs:
          - api_url: 'YOUR_SLACK_WEBHOOK_URL'
            channel: '#alerts'
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## ServiceMonitor

To scrape metrics from your own applications, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: default
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

## Storage

- Prometheus: 50GB retention for 30 days
- Alertmanager: 10GB retention for 120 hours
- Grafana: 10GB for dashboards and data

Adjust storage in the Helm values if needed.

## Troubleshooting

### Check Prometheus targets
```bash
# Access Prometheus UI and go to Status → Targets
# Or use kubectl:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then open http://localhost:9090/targets
```

### Check Prometheus rules
```bash
kubectl get prometheusrules -n monitoring
```

### View Alertmanager alerts
```bash
# Access Alertmanager UI or:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Then open http://localhost:9093
```
