# Logging Stack (Loki + Promtail)

Log aggregation and querying system.

## Installation

This is automatically installed via ArgoCD in the `logging` namespace.

## Components

- **Loki**: Log aggregation and storage (SingleBinary mode for simplicity)
- **Promtail**: Log collector running as DaemonSet on all nodes
- **Gateway**: Nginx gateway for Loki API

## Access

- **Loki API**: https://loki.k8s.yourdomain.com
- **Grafana**: View logs in Grafana (Loki datasource is pre-configured)

## Usage

### Query logs in Grafana

1. Open Grafana: https://grafana.k8s.yourdomain.com
2. Go to Explore → Select "Loki" datasource
3. Use LogQL to query logs

#### Example queries:

```logql
# All logs from a namespace
{namespace="default"}

# Logs from a specific pod
{pod="my-app-xyz"}

# Logs containing "error" (case-insensitive)
{namespace="default"} |~ "(?i)error"

# Count errors per minute
sum(rate({namespace="default"} |~ "(?i)error" [5m])) by (pod)

# Logs from a specific container
{namespace="default", container="my-container"}

# JSON log parsing
{namespace="default"} | json | level="error"

# Filter by severity level
{namespace="default"} | json | level=~"error|fatal"
```

### Query logs via API

```bash
# Get logs for the last hour
curl -G -s "https://loki.k8s.yourdomain.com/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="default"}' \
  --data-urlencode 'limit=100' \
  --data-urlencode "start=$(date -u -d '1 hour ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"
```

### LogCLI

Install logcli for command-line log queries:

```bash
# macOS
brew install logcli

# Linux
wget https://github.com/grafana/loki/releases/download/v2.9.0/logcli-linux-amd64.zip
unzip logcli-linux-amd64.zip
sudo mv logcli-linux-amd64 /usr/local/bin/logcli
```

Use it:

```bash
export LOKI_ADDR=https://loki.k8s.yourdomain.com

# Query logs
logcli query '{namespace="default"}'

# Tail logs
logcli query --tail '{pod="my-app-xyz"}'

# Get labels
logcli labels

# Get label values
logcli labels namespace
```

## Log Retention

- Default retention: 744h (31 days)
- Storage: 50GB persistent volume

Adjust retention in the Loki configuration:

```yaml
loki:
  limits_config:
    retention_period: 744h  # 31 days
```

## Promtail Configuration

Promtail is deployed as a DaemonSet and automatically:
- Collects logs from all pods on all nodes
- Adds Kubernetes metadata (namespace, pod, container, etc.)
- Parses JSON logs
- Ships logs to Loki

## Custom Log Parsing

Add custom pipeline stages in Promtail config:

```yaml
config:
  snippets:
    pipelineStages:
      - cri: {}
      - json:
          expressions:
            level: level
            timestamp: timestamp
            message: msg
      - timestamp:
          source: timestamp
          format: RFC3339
      - labels:
          level:
```

## Troubleshooting

### Check Loki is running
```bash
kubectl get pods -n logging
kubectl logs -n logging -l app.kubernetes.io/name=loki
```

### Check Promtail is collecting logs
```bash
kubectl get pods -n logging -l app.kubernetes.io/name=promtail
kubectl logs -n logging -l app.kubernetes.io/name=promtail
```

### Test Loki API
```bash
# Check ready
curl https://loki.k8s.yourdomain.com/ready

# Check metrics
curl https://loki.k8s.yourdomain.com/metrics

# List labels
curl https://loki.k8s.yourdomain.com/loki/api/v1/labels
```

### No logs in Grafana?

1. Check Promtail pods are running on all nodes
2. Check Promtail logs for errors
3. Verify the Loki datasource URL in Grafana: `http://loki-gateway.logging.svc.cluster.local`
4. Try a simple query: `{namespace="logging"}`

## Storage

Loki uses persistent storage (50GB). Logs are stored in filesystem mode.

For production at scale, consider:
- Switching to object storage (S3, GCS, etc.)
- Using distributed mode with separate read/write/backend components
- Configuring compaction and retention policies
