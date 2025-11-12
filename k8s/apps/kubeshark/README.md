# Kubeshark - API Traffic Analyzer for Kubernetes

Kubeshark is like Wireshark for Kubernetes - it captures, analyzes, and monitors all API traffic (HTTP, REST, GraphQL, gRPC, Redis, Kafka, RabbitMQ, and more) in real-time.

## Installation

This is automatically installed via ArgoCD in the `kubeshark` namespace.

## Access

- **Kubeshark UI**: https://kubeshark.k8s.yourdomain.com

## Features

- **Real-time traffic capture** - See all API calls as they happen
- **Protocol support** - HTTP/REST, gRPC, GraphQL, Redis, Kafka, RabbitMQ, etc.
- **Service map** - Visualize service-to-service communication
- **Request/Response inspection** - See full payloads
- **Filtering** - Filter by namespace, pod, service, method, status code
- **Query language** - Powerful KFL (Kubeshark Filter Language)
- **Recording & Replay** - Save and replay traffic
- **Performance analysis** - Latency, errors, throughput
- **No code changes** - Works without instrumenting apps

## Using Kubeshark

### Web UI

Open https://kubeshark.k8s.yourdomain.com

The UI shows:

1. **Traffic view** - Real-time API calls
2. **Service map** - Topology of your services
3. **Dashboard** - Metrics and statistics
4. **Query builder** - Advanced filtering

### Basic Filtering

In the UI search bar:

```
# All HTTP requests
http

# Requests to a specific service
dst.name == "my-service"

# Failed requests (4xx, 5xx)
response.status >= 400

# Slow requests (>1 second)
response.latency > 1000

# POST requests
request.method == "POST"

# Requests to specific path
request.path == "/api/users"

# Requests from specific namespace
src.namespace == "production"
```

### Advanced Queries (KFL)

Kubeshark Filter Language examples:

```
# All Redis commands
redis

# Kafka messages to specific topic
kafka.topic == "user-events"

# gRPC calls with errors
grpc and response.status != 0

# GraphQL queries
graphql and request.query contains "mutation"

# Requests with specific header
request.headers["Authorization"] exists

# Slow database queries
postgres and response.latency > 500

# Failed HTTP calls between services
http and src.name == "frontend" and dst.name == "backend" and response.status >= 500

# High memory allocations
request.body.size > 1000000
```

## Use Cases

### 1. Debug Service Communication

**Problem**: Frontend can't connect to backend

1. Open Kubeshark
2. Filter: `src.name == "frontend" and dst.name == "backend"`
3. Check for:
   - Connection errors
   - 404/503 responses
   - Timeout issues
   - DNS resolution failures

### 2. Find Slow APIs

```
# Find all requests slower than 2 seconds
http and response.latency > 2000
```

Group by endpoint to find the slowest APIs.

### 3. Track Error Rates

```
# All 5xx errors
http and response.status >= 500 and response.status < 600
```

See which services are failing and why.

### 4. Monitor Database Queries

```
# Slow PostgreSQL queries
postgres and response.latency > 1000

# Redis cache misses
redis.command == "GET" and redis.response == null
```

### 5. Inspect Message Queues

```
# Kafka messages
kafka.topic == "orders"

# RabbitMQ messages
rabbitmq.exchange == "events"
```

### 6. Security Auditing

```
# Requests without authentication
http and not request.headers["Authorization"]

# Access to sensitive endpoints
request.path contains "/admin"

# Potential SQL injection attempts
request.body contains "DROP TABLE"
```

## Service Map

The Service Map view shows:
- All services in your cluster
- Connections between services
- Traffic volume
- Error rates
- Latency

Use it to:
- Understand your microservices architecture
- Identify bottlenecks
- Find unused services
- Detect circular dependencies

## Recording & Replay

### Save Traffic

1. Click "Record" in the UI
2. Perform actions you want to capture
3. Click "Stop"
4. Download the recording

### Replay Traffic

Use recordings for:
- Load testing
- Debugging issues in dev/staging
- Training and documentation
- Regression testing

## Performance Impact

Kubeshark uses:
- **eBPF or libpcap** for packet capture
- Minimal overhead (~5% CPU, ~256MB RAM per node)
- No code changes required
- Can be limited to specific namespaces

To reduce impact:

```yaml
tap:
  namespaces:
    - production  # Only capture production namespace
  packetCapture: ebpf  # Lower overhead than libpcap
```

## CLI Tool

Install the Kubeshark CLI for advanced features:

```bash
# macOS
brew install kubeshark

# Linux
sh <(curl -Ls https://kubeshark.co/install)
```

### CLI Commands

```bash
# View traffic in terminal
kubeshark tap

# Filter traffic
kubeshark tap -n production

# Record traffic to file
kubeshark tap --set tap.record=true

# Replay traffic
kubeshark replay traffic.tar

# Export to PCAP (for Wireshark)
kubeshark export --format pcap -o traffic.pcap
```

## Integration with Grafana

### Create Dashboard

1. Add Kubeshark as Prometheus data source (if metrics enabled)
2. Create dashboard with panels for:
   - Request rate
   - Error rate
   - Latency percentiles (p50, p95, p99)
   - Top endpoints by traffic

### Example PromQL Queries

```promql
# Request rate
rate(kubeshark_requests_total[5m])

# Error rate
rate(kubeshark_requests_total{status=~"5.."}[5m])

# P95 latency
histogram_quantile(0.95, kubeshark_request_duration_seconds_bucket)
```

## Webhooks & Alerts

Configure webhooks to send alerts:

```yaml
# In the UI: Settings → Webhooks
webhooks:
  - name: slack-alerts
    url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
    filter: "http and response.status >= 500"
    message: "{{.src.name}} → {{.dst.name}}: {{.response.status}} {{.request.path}}"
```

Get notified when:
- Services return errors
- Latency exceeds threshold
- Unusual traffic patterns detected

## Scripting with KFL

Create reusable queries:

```yaml
# Save as queries.yaml
queries:
  slow-requests:
    name: "Slow Requests"
    query: "http and response.latency > 1000"

  database-errors:
    name: "Database Errors"
    query: "postgres and response.status != 0"

  cache-misses:
    name: "Redis Cache Misses"
    query: "redis.command == 'GET' and not redis.hit"
```

Import in UI: Settings → Queries → Import

## Troubleshooting

### No traffic visible

1. Check tapper pods are running:
   ```bash
   kubectl get pods -n kubeshark -l app=kubeshark-tap
   ```

2. Check tapper logs:
   ```bash
   kubectl logs -n kubeshark -l app=kubeshark-tap
   ```

3. Verify RBAC permissions:
   ```bash
   kubectl auth can-i list pods --as=system:serviceaccount:kubeshark:kubeshark -n default
   ```

### High resource usage

1. Limit to specific namespaces:
   ```yaml
   tap:
     namespaces:
       - production
       - staging
   ```

2. Use eBPF instead of libpcap:
   ```yaml
   tap:
     packetCapture: ebpf
   ```

3. Reduce packet capture:
   ```yaml
   tap:
     maxCapturedSize: 512  # KB
   ```

### TLS/HTTPS traffic not visible

Enable TLS interception:

```yaml
tap:
  tls: true
```

Note: This requires Kubeshark to have access to TLS certificates.

### Can't access UI

1. Check ingress:
   ```bash
   kubectl get ingressroute kubeshark -n kubeshark
   kubectl describe ingressroute kubeshark -n kubeshark
   ```

2. Port forward directly:
   ```bash
   kubectl port-forward -n kubeshark svc/kubeshark-front 8080:80
   # Access at http://localhost:8080
   ```

## Privacy & Security

**Important**: Kubeshark captures all traffic including:
- Authentication tokens
- API keys
- Passwords
- Personal data

### Best Practices

1. **Limit access** - Protect the UI with Authelia
2. **Filter sensitive data** - Redact in UI settings
3. **Limit namespaces** - Only capture what's needed
4. **Retention policy** - Auto-delete old recordings
5. **RBAC** - Restrict who can deploy Kubeshark
6. **Audit logs** - Track who accesses what

### Protect with Authelia

Update the IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubeshark
  namespace: kubeshark
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`kubeshark.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authelia
          namespace: authelia
      services:
        - name: kubeshark-front
          port: 80
  tls:
    certResolver: default
```

## Comparison with Alternatives

| Feature | Kubeshark | Wireshark | Jaeger | Service Mesh |
|---------|-----------|-----------|---------|--------------|
| Real-time traffic | ✅ | ✅ | ❌ | ⚠️ |
| No code changes | ✅ | ✅ | ❌ | ❌ |
| Protocol support | 🌟 Many | 🌟 All | HTTP only | HTTP/gRPC |
| Service map | ✅ | ❌ | ✅ | ✅ |
| Easy to use | ✅ | ⚠️ | ✅ | ⚠️ |
| Overhead | Low | N/A | Low | Medium |

## Documentation

- Kubeshark docs: https://docs.kubeshark.co/
- KFL reference: https://docs.kubeshark.co/en/filtering
- GitHub: https://github.com/kubeshark/kubeshark
- Examples: https://docs.kubeshark.co/en/examples
