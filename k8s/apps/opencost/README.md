# OpenCost - Kubernetes Cost Monitoring

OpenCost is an open-source project for measuring and allocating infrastructure and container costs in Kubernetes environments.

## Installation

This is automatically installed via ArgoCD in the `opencost` namespace.

## Access

- **OpenCost UI**: https://opencost.k8s.yourdomain.com

## Features

- **Real-time cost allocation** - By namespace, pod, label, deployment
- **Resource efficiency** - Identify over-provisioned workloads
- **Cost breakdown** - CPU, memory, storage, network costs
- **Multi-cloud support** - AWS, GCP, Azure pricing
- **Prometheus integration** - Uses existing metrics
- **API access** - Query costs programmatically

## Using OpenCost

### Web UI

Open https://opencost.k8s.yourdomain.com to see:

- **Total cluster costs** - Daily, weekly, monthly
- **Cost by namespace** - Which teams/apps cost the most
- **Cost by pod/deployment** - Granular cost breakdown
- **Efficiency metrics** - Resource requests vs actual usage
- **Cost trends** - Historical cost data

### Cost Breakdown Views

The UI provides multiple views:

1. **Namespace view** - Total cost per namespace
2. **Deployment view** - Cost per deployment
3. **Controller view** - Cost by controller type
4. **Pod view** - Individual pod costs
5. **Label view** - Group costs by any label

### Configure Cloud Pricing

By default, OpenCost uses on-premise pricing. For accurate cloud costs:

#### Hetzner Cloud

OpenCost doesn't have native Hetzner support, but you can configure custom pricing:

```bash
# Hetzner pricing (approximate)
# cpx21: €0.015/hour = ~€10.95/month
# cpx31: €0.023/hour = ~€16.79/month
```

#### Custom Pricing Configuration

Create a custom pricing ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-pricing
  namespace: opencost
data:
  default.json: |
    {
      "CPU": "0.031",
      "RAM": "0.004",
      "storage": "0.00005",
      "zoneNetworkEgress": "0.01",
      "regionNetworkEgress": "0.01",
      "internetNetworkEgress": "0.01"
    }
```

## API Usage

### Get Total Cluster Cost

```bash
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d"
```

### Get Cost by Namespace

```bash
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d&aggregate=namespace"
```

### Get Cost by Label

```bash
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d&aggregate=label:app"
```

### Cost for Specific Namespace

```bash
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d&filterNamespaces=production"
```

### Export to JSON

```bash
curl -s "https://opencost.k8s.yourdomain.com/allocation/compute?window=30d&aggregate=namespace" | jq
```

## Grafana Integration

### Add OpenCost Data Source

1. Open Grafana
2. Configuration → Data Sources → Add data source
3. Select "JSON API"
4. URL: `http://opencost.opencost.svc.cluster.local:9003`
5. Save & Test

### Import Dashboards

Import OpenCost community dashboards from Grafana:
- https://grafana.com/grafana/dashboards/15714-opencost-cost-allocation/
- https://grafana.com/grafana/dashboards/15715-opencost-namespace-cost/

Or query OpenCost API in Grafana:

```json
{
  "target": "allocation/compute",
  "window": "7d",
  "aggregate": "namespace"
}
```

## Cost Optimization Tips

### 1. Right-size Resources

Identify over-provisioned workloads:

```bash
# Get efficiency metrics
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d&aggregate=deployment" \
  | jq '.data[] | select(.cpuEfficiency < 0.5)'
```

Pods with <50% CPU efficiency are good candidates for reducing resource requests.

### 2. Find Idle Resources

```bash
# Find pods with low utilization
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=7d" \
  | jq '.data[] | select(.cpuEfficiency < 0.2)'
```

### 3. Spot Check Expensive Namespaces

```bash
curl -s "https://opencost.k8s.yourdomain.com/allocation/compute?window=30d&aggregate=namespace" \
  | jq '.data | sort_by(.totalCost) | reverse | .[0:5]'
```

### 4. Monitor Cost Trends

Set up alerts in Prometheus for cost increases:

```yaml
- alert: HighNamespaceCost
  expr: |
    opencost_allocation_total_cost{namespace="production"} > 100
  for: 1h
  annotations:
    summary: "Namespace cost exceeds threshold"
```

## Understanding Costs

### CPU Cost

Based on:
- vCPU hours used
- CPU requests (reserved capacity)
- Cloud provider pricing

### Memory Cost

Based on:
- GB hours used
- Memory requests (reserved capacity)
- Cloud provider pricing

### Storage Cost

Based on:
- PVC size
- Storage class
- Provider storage pricing

### Network Cost

Based on:
- Egress traffic
- Inter-zone traffic
- Cloud provider network pricing

## Cost Allocation Methods

OpenCost uses two allocation models:

### 1. Usage-based

Allocates cost based on actual resource usage (CPU, memory used).

**Pros**: Fair, reflects actual consumption
**Cons**: Ignores reserved capacity

### 2. Request-based (Default)

Allocates cost based on resource requests.

**Pros**: Predictable, encourages right-sizing
**Cons**: May not reflect actual usage

Toggle in UI or via API: `?costModel=usage` or `?costModel=request`

## Prometheus Metrics

OpenCost exports metrics to Prometheus:

```promql
# Total cluster cost
sum(opencost_allocation_total_cost)

# Cost by namespace
sum(opencost_allocation_total_cost) by (namespace)

# CPU efficiency
opencost_allocation_cpu_efficiency

# Memory efficiency
opencost_allocation_memory_efficiency

# Idle cost (waste)
opencost_allocation_idle_cost
```

## Troubleshooting

### No cost data appearing

1. Check OpenCost is running:
   ```bash
   kubectl get pods -n opencost
   kubectl logs -n opencost -l app=opencost
   ```

2. Verify Prometheus connection:
   ```bash
   kubectl logs -n opencost -l app=opencost | grep prometheus
   ```

3. Check Prometheus has metrics:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   # Open http://localhost:9090 and search for container_cpu_usage_seconds_total
   ```

### Incorrect costs

1. Verify cloud provider configuration
2. Check custom pricing ConfigMap
3. Review cost allocation model (usage vs request)

### UI not loading

1. Check ingress:
   ```bash
   kubectl get ingressroute -n opencost
   kubectl describe ingressroute opencost -n opencost
   ```

2. Test service locally:
   ```bash
   kubectl port-forward -n opencost svc/opencost 9090:9090
   # Open http://localhost:9090
   ```

## Export and Reporting

### CSV Export

```bash
# Get costs as CSV
curl "https://opencost.k8s.yourdomain.com/allocation/compute?window=30d&aggregate=namespace&format=csv" \
  > costs.csv
```

### Schedule Reports

Create a CronJob to email weekly cost reports:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: weekly-cost-report
  namespace: opencost
spec:
  schedule: "0 9 * * 1"  # Monday 9 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: reporter
              image: curlimages/curl:latest
              command:
                - sh
                - -c
                - |
                  curl -s "http://opencost.opencost.svc.cluster.local:9003/allocation/compute?window=7d&aggregate=namespace" \
                    | mail -s "Weekly K8s Cost Report" team@example.com
          restartPolicy: OnFailure
```

## Cost Alerts

Set up Prometheus alerts for cost anomalies:

```yaml
groups:
  - name: opencost-alerts
    rules:
      - alert: HighClusterCost
        expr: sum(opencost_allocation_total_cost) > 1000
        for: 1h
        annotations:
          summary: "Cluster cost exceeds $1000/day"

      - alert: NamespaceCostSpike
        expr: |
          (opencost_allocation_total_cost - opencost_allocation_total_cost offset 1d)
          / opencost_allocation_total_cost offset 1d > 0.5
        for: 30m
        annotations:
          summary: "Namespace cost increased by >50% in 24h"
```

## Best Practices

1. **Review costs weekly** - Identify trends early
2. **Set resource requests** - Ensures accurate cost allocation
3. **Use labels** - Tag workloads for better cost tracking
4. **Right-size regularly** - Use efficiency metrics to optimize
5. **Monitor idle costs** - Reduce waste
6. **Set up alerts** - Get notified of cost anomalies
7. **Export reports** - Share with team/management

## Documentation

- OpenCost docs: https://www.opencost.io/docs/
- API reference: https://www.opencost.io/docs/api
- GitHub: https://github.com/opencost/opencost
