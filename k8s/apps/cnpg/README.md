# CloudNativePG - PostgreSQL Operator

CloudNativePG is a comprehensive platform to seamlessly manage PostgreSQL databases within Kubernetes environments.

## Installation

This is automatically installed via ArgoCD in the `cnpg-system` namespace.

## Features

- **High Availability**: Automatic failover with 3-node clusters
- **Automated Backups**: Point-in-time recovery with Barman
- **Connection Pooling**: Built-in PgBouncer support
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Rolling Updates**: Zero-downtime PostgreSQL upgrades
- **Declarative Configuration**: Manage databases as Kubernetes resources

## Creating a Database Cluster

### Simple Development Cluster

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-db
  namespace: default
spec:
  instances: 1  # Single instance for dev
  imageName: ghcr.io/cloudnative-pg/postgresql:16.3
  storage:
    size: 5Gi
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
```

### Production HA Cluster with Backups

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: prod-db
  namespace: production
spec:
  instances: 3  # HA with automatic failover

  imageName: ghcr.io/cloudnative-pg/postgresql:16.3

  storage:
    size: 50Gi
    storageClass: longhorn

  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 4000m
      memory: 4Gi

  bootstrap:
    initdb:
      database: app
      owner: app

  # Automated backups to S3
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/postgres-backups/prod-db/
      s3Credentials:
        accessKeyId:
          name: aws-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-credentials
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: "30d"

  # Connection pooling
  pgBouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "1000"
      default_pool_size: "25"

  monitoring:
    enablePodMonitor: true
```

Apply it:

```bash
kubectl apply -f prod-db.yaml
```

## Connecting to the Database

### Get Connection Details

```bash
# Get the cluster status
kubectl get cluster my-db

# Primary service (read-write)
my-db-rw.default.svc.cluster.local:5432

# Read-only service (load-balanced across replicas)
my-db-ro.default.svc.cluster.local:5432

# Read service (primary and replicas)
my-db-r.default.svc.cluster.local:5432
```

### Get Credentials

The operator creates a secret with credentials:

```bash
# Get the app user password
kubectl get secret my-db-app -o jsonpath='{.data.password}' | base64 -d

# Get the postgres superuser password
kubectl get secret my-db-superuser -o jsonpath='{.data.password}' | base64 -d
```

### Connect from Application

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: DATABASE_URL
              value: "postgresql://app:password@my-db-rw.default.svc.cluster.local:5432/myapp?sslmode=require"
            # Or use secret
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-db-app
                  key: password
```

### Connect with psql

```bash
# Port forward to your local machine
kubectl port-forward svc/my-db-rw 5432:5432

# Connect with psql
psql -h localhost -U app -d myapp
```

Or use kubectl plugin:

```bash
kubectl cnpg psql my-db
```

## Backups and Recovery

### Configure S3 Backup

First, create a secret with AWS credentials:

```bash
kubectl create secret generic aws-credentials \
  --from-literal=ACCESS_KEY_ID=your-access-key \
  --from-literal=SECRET_ACCESS_KEY=your-secret-key
```

Then add backup configuration to your cluster (see example above).

### Scheduled Backups

Create a backup schedule:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: daily-backup
  namespace: default
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  backupOwnerReference: self
  cluster:
    name: my-db
```

### Manual Backup

```bash
kubectl cnpg backup my-db
```

### Point-in-Time Recovery

Restore to a specific timestamp:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-db-restored
spec:
  instances: 3
  bootstrap:
    recovery:
      source: my-db
      recoveryTarget:
        targetTime: "2024-01-15 10:30:00"
  externalClusters:
    - name: my-db
      barmanObjectStore:
        destinationPath: s3://my-bucket/postgres-backups/my-db/
        s3Credentials:
          accessKeyId:
            name: aws-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: aws-credentials
            key: SECRET_ACCESS_KEY
```

## Monitoring

### Check Cluster Status

```bash
# Get cluster status
kubectl get cluster my-db

# Describe cluster details
kubectl describe cluster my-db

# Get cluster pods
kubectl get pods -l postgresql=my-db
```

### Prometheus Metrics

CloudNativePG exports metrics at:
- `http://<pod>:9187/metrics`

The PodMonitor is automatically created. View metrics in Grafana:

```promql
# Connection count
cnpg_backends_total

# Database size
cnpg_pg_database_size_bytes

# Replication lag
cnpg_pg_replication_lag

# Transaction rate
rate(cnpg_pg_stat_database_xact_commit[5m])
```

### Grafana Dashboards

Import CloudNativePG dashboards from:
- https://grafana.com/grafana/dashboards/18857-cloudnativepg/

## Maintenance Operations

### Scale Replicas

```bash
kubectl patch cluster my-db --type merge -p '{"spec":{"instances":5}}'
```

### Upgrade PostgreSQL Version

Update the image version:

```bash
kubectl patch cluster my-db --type merge \
  -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:17.0"}}'
```

The operator will perform a rolling update.

### Switchover (Promote a Replica)

```bash
kubectl cnpg promote my-db <replica-pod-name>
```

### Restart Cluster

```bash
kubectl cnpg restart my-db
```

### Change Configuration

Edit the cluster and update `postgresql.parameters`:

```bash
kubectl edit cluster my-db
```

## Connection Pooling with PgBouncer

Enable PgBouncer for better connection management:

```yaml
spec:
  pgBouncer:
    poolMode: transaction  # or session/statement
    parameters:
      max_client_conn: "1000"
      default_pool_size: "25"
      min_pool_size: "5"
      reserve_pool_size: "5"
      max_db_connections: "100"
```

Access via pooler service:

```
my-db-pooler-rw.default.svc.cluster.local:5432
```

## Troubleshooting

### Check Operator Logs

```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### Check Cluster Events

```bash
kubectl get events --field-selector involvedObject.name=my-db
```

### Check Pod Logs

```bash
# Primary pod
kubectl logs my-db-1

# All pods
kubectl logs -l postgresql=my-db
```

### Check Replication Status

```bash
kubectl cnpg status my-db
```

### Common Issues

**Pod not starting:**
- Check PVC is bound: `kubectl get pvc -l postgresql=my-db`
- Check storage class exists: `kubectl get storageclass`
- Check pod events: `kubectl describe pod my-db-1`

**Replication lag:**
- Check network between pods
- Monitor disk I/O performance
- Increase resources if needed

**Backup failures:**
- Verify S3 credentials are correct
- Check S3 bucket permissions
- Review backup logs: `kubectl logs job/backup-my-db-<timestamp>`

## kubectl Plugin

Install the kubectl-cnpg plugin for easier management:

```bash
# macOS
brew install cloudnative-pg/tap/cnpg

# Linux
curl -sSfL \
  https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | \
  sudo sh -s -- -b /usr/local/bin
```

Commands:

```bash
kubectl cnpg status my-db
kubectl cnpg backup my-db
kubectl cnpg psql my-db
kubectl cnpg certificate my-db
kubectl cnpg reload my-db
kubectl cnpg restart my-db
kubectl cnpg promote my-db my-db-2
```

## Best Practices

1. **Use 3 instances for production** - Enables automatic failover
2. **Configure backups** - Always use object storage for backups
3. **Set resource limits** - Prevent PostgreSQL from consuming all node resources
4. **Enable monitoring** - Use Prometheus and Grafana dashboards
5. **Use PgBouncer** - For applications with many connections
6. **Regular updates** - Keep PostgreSQL and operator up to date
7. **Test recovery** - Regularly test backup restoration
8. **Use secrets** - Store credentials in Sealed Secrets or External Secrets

## Documentation

- CloudNativePG docs: https://cloudnative-pg.io/documentation/
- Examples: https://github.com/cloudnative-pg/cloudnative-pg/tree/main/docs/src/samples
