# Tracing Stack (Tempo)

Distributed tracing system for microservices.

## Installation

This is automatically installed via ArgoCD in the `tracing` namespace.

## Components

- **Tempo**: Distributed tracing backend supporting multiple protocols

## Supported Protocols

Tempo accepts traces in multiple formats:
- **OpenTelemetry (OTLP)**: HTTP (4318) and gRPC (4317)
- **Jaeger**: Thrift HTTP (14268), gRPC (14250), Thrift Compact (6831)
- **Zipkin**: HTTP (9411)
- **OpenCensus**: gRPC (55678)

## Access

- **Tempo API**: https://tempo.k8s.yourdomain.com
- **Grafana**: Query traces in Grafana (Tempo datasource is pre-configured)

## Usage

### View traces in Grafana

1. Open Grafana: https://grafana.k8s.yourdomain.com
2. Go to Explore → Select "Tempo" datasource
3. Query by:
   - Trace ID
   - Service name
   - Tags/Labels

### Instrument your application

#### Option 1: OpenTelemetry (Recommended)

**Python example:**

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure OpenTelemetry
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Export to Tempo
otlp_exporter = OTLPSpanExporter(
    endpoint="http://tempo.tracing.svc.cluster.local:4317",
    insecure=True
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(otlp_exporter)
)

# Use it
with tracer.start_as_current_span("my-operation"):
    # Your code here
    pass
```

**Node.js example:**

```javascript
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');

const provider = new NodeTracerProvider();
const exporter = new OTLPTraceExporter({
  url: 'http://tempo.tracing.svc.cluster.local:4317'
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

**Go example:**

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

exporter, _ := otlptracegrpc.New(
    context.Background(),
    otlptracegrpc.WithEndpoint("tempo.tracing.svc.cluster.local:4317"),
    otlptracegrpc.WithInsecure(),
)

tp := sdktrace.NewTracerProvider(
    sdktrace.WithBatcher(exporter),
)
otel.SetTracerProvider(tp)
```

#### Option 2: Jaeger Client Libraries

**Java example:**

```java
import io.jaegertracing.Configuration;
import io.opentracing.Tracer;

Configuration config = new Configuration("my-service")
    .withSampler(new Configuration.SamplerConfiguration()
        .withType("const")
        .withParam(1))
    .withReporter(new Configuration.ReporterConfiguration()
        .withSender(new Configuration.SenderConfiguration()
            .withEndpoint("http://tempo.tracing.svc.cluster.local:14268/api/traces")));

Tracer tracer = config.getTracer();
```

### Query Tempo API directly

```bash
# Search for traces by service
curl "https://tempo.k8s.yourdomain.com/api/search?tags=service.name=my-service"

# Get a specific trace by ID
curl "https://tempo.k8s.yourdomain.com/api/traces/<trace-id>"

# Get trace summary
curl "https://tempo.k8s.yourdomain.com/api/echo"
```

## Service Endpoints (in-cluster)

Your applications should send traces to:

- **OTLP gRPC**: `http://tempo.tracing.svc.cluster.local:4317`
- **OTLP HTTP**: `http://tempo.tracing.svc.cluster.local:4318`
- **Jaeger Thrift HTTP**: `http://tempo.tracing.svc.cluster.local:14268`
- **Jaeger gRPC**: `http://tempo.tracing.svc.cluster.local:14250`
- **Zipkin**: `http://tempo.tracing.svc.cluster.local:9411`

## Example: Add OpenTelemetry Collector (Optional)

For advanced use cases, deploy OpenTelemetry Collector as a central aggregation point:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:
      batch:
    exporters:
      otlp:
        endpoint: tempo.tracing.svc.cluster.local:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp]
```

## Trace Retention

- Default retention: Based on storage (50GB)
- Traces are stored locally in `/var/tempo/traces`

For production at scale:
- Use object storage backend (S3, GCS, Azure Blob)
- Configure retention policies
- Use distributed mode with separate components

## Correlating Traces with Logs

In your application logs, include the trace ID:

```python
import logging
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("operation") as span:
    trace_id = format(span.get_span_context().trace_id, '032x')
    logging.info(f"Processing request", extra={"trace_id": trace_id})
```

Then in Grafana, you can:
1. Find the trace in Tempo
2. Copy the trace ID
3. Query Loki with the trace ID to see related logs

Or configure Grafana to auto-link:
- From logs to traces (via trace ID field)
- From traces to logs (via trace context)

## Troubleshooting

### Check Tempo is running
```bash
kubectl get pods -n tracing
kubectl logs -n tracing -l app.kubernetes.io/name=tempo
```

### Test sending a trace

Use the OpenTelemetry demo app:

```bash
# Install the demo app
kubectl create ns otel-demo
kubectl apply -n otel-demo -f https://raw.githubusercontent.com/open-telemetry/opentelemetry-demo/main/kubernetes/opentelemetry-demo.yaml
```

### No traces appearing?

1. Verify your application is sending traces to the correct endpoint
2. Check Tempo logs for errors
3. Verify the Tempo datasource in Grafana: `http://tempo.tracing.svc.cluster.local:3100`
4. Check network policies aren't blocking traffic

### Query Tempo metrics

Tempo exposes Prometheus metrics:

```bash
kubectl port-forward -n tracing svc/tempo 3100:3100
curl http://localhost:3100/metrics
```

## Documentation

- Tempo docs: https://grafana.com/docs/tempo/
- OpenTelemetry: https://opentelemetry.io/
- Jaeger clients: https://www.jaegertracing.io/docs/latest/client-libraries/
