# Kubernetes Applications - GitOps with ArgoCD

This directory contains all Kubernetes application manifests managed by ArgoCD using the "App of Apps" pattern.

## Architecture

```
k8s/
├── bootstrap/          # Initial ArgoCD installation (applied manually once)
├── root-app/          # Root "App of Apps" that manages everything
└── apps/              # All managed applications
    ├── argocd/        # ArgoCD configuration (ingress)
    ├── authelia/      # SSO and authentication
    ├── cnpg/          # CloudNativePG PostgreSQL operator
    ├── dashboard/     # Kubernetes Dashboard
    ├── external-secrets/  # External Secrets Operator
    ├── headlamp/      # Modern Kubernetes web UI
    ├── kubeshark/     # API traffic analyzer
    ├── logging/       # Loki + Promtail (log aggregation)
    ├── monitoring/    # Prometheus, Grafana, Alertmanager
    ├── opencost/      # Cost monitoring and optimization
    ├── reloader/      # Auto-reload pods on config changes
    ├── sealed-secrets/  # Encrypted secrets for Git
    ├── tracing/       # Tempo (distributed tracing)
    └── traefik-plugins/  # Enhanced Traefik capabilities
```

## Installed Components

### Core Infrastructure
- **ArgoCD** - GitOps continuous delivery
- **Kubernetes Dashboard** - Web UI for cluster management
- **Headlamp** - Modern, extensible Kubernetes web UI

### Observability (LGTM Stack)
- **Grafana** - Visualization and dashboards
- **Prometheus** - Metrics collection and storage
- **Alertmanager** - Alert routing and management
- **Loki** - Log aggregation
- **Promtail** - Log shipping agent
- **Tempo** - Distributed tracing

### Security & Authentication
- **Authelia** - SSO with Traefik ForwardAuth
- **External Secrets Operator** - Sync secrets from external sources
- **Sealed Secrets** - Encrypted secrets safe for Git

### Database & Stateful Apps
- **CloudNativePG** - PostgreSQL operator for HA databases

### Cost & Performance
- **OpenCost** - Kubernetes cost monitoring and optimization
- **Kubeshark** - API traffic analyzer for debugging

### Networking & Ingress
- **Traefik Plugins** - Rate limiting, GeoIP blocking, WAF, Fail2Ban

### Utilities
- **Reloader** - Auto-restart pods when ConfigMaps/Secrets change

## Deployment Guide

### Prerequisites

1. **Cluster is deployed** via Terraform (see `../infra/`)
2. **kubectl configured** with cluster access
3. **Domain configured** in Cloudflare with wildcard DNS

### Step 1: Configure Your Cluster

**Easy way:** Use the centralized configuration script:

```bash
cd k8s

# 1. Copy the example config
cp config.env.example config.env

# 2. Edit config.env with your values
nano config.env
# Set:
#   DOMAIN=yourdomain.com
#   GITHUB_USERNAME=your-github-username
#   (adjust other values as needed)

# 3. Apply configuration to all manifests
./scripts/apply-config.sh
```

This script will replace all placeholders (`YOURDOMAIN.COM`, `YOUR_USERNAME`) in all YAML files at once!

**Manual way (if you prefer):**

```bash
# Find all files that need domain updates
grep -r "YOURDOMAIN.COM" k8s/apps/ --include="*.yaml"

# Find all files with GitHub username
grep -r "YOUR_USERNAME" k8s/ --include="*.yaml"
```

Replace in each file:
- `YOURDOMAIN.COM` → Your actual domain (e.g., `example.com`)
- `YOUR_USERNAME` → Your GitHub username
- `k8s-hetzner` → Your repo name (if different)

### Step 2: Update Authelia Secrets

**CRITICAL:** Change default secrets in `apps/authelia/manifests/configmap.yaml`:

```bash
# Generate three secure secrets
openssl rand -base64 32  # jwt_secret
openssl rand -base64 32  # session.secret
openssl rand -base64 32  # storage.encryption_key
```

Also generate a new admin password:

```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourSecurePassword123!'
```

### Step 3: Bootstrap ArgoCD

```bash
# Set kubeconfig
export KUBECONFIG=$PWD/kubeconfig.yaml

# Install ArgoCD
kubectl apply -k k8s/bootstrap/argocd/

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Step 4: Commit and Push Your Changes

```bash
# Commit all k8s manifests to Git
git add k8s/
git commit -m "Add Kubernetes applications with ArgoCD"
git push origin main
```

### Step 5: Deploy Root App of Apps

```bash
# This will automatically deploy all applications
kubectl apply -f k8s/root-app/root-application.yaml

# Watch applications being created
kubectl get applications -n argocd --watch
```

### Step 6: Verify Deployment

```bash
# Check all applications are synced and healthy
kubectl get applications -n argocd

# Check pods across all namespaces
kubectl get pods -A

# Check ingress routes
kubectl get ingressroute -A
```

All applications should show `Synced` and `Healthy`.

### Step 7: Access Applications

Your applications will be available at:

- **ArgoCD**: https://argocd.k8s.yourdomain.com
- **Authelia**: https://auth.k8s.yourdomain.com
- **Grafana**: https://grafana.k8s.yourdomain.com
- **Prometheus**: https://prometheus.k8s.yourdomain.com
- **Alertmanager**: https://alertmanager.k8s.yourdomain.com
- **Kubernetes Dashboard**: https://dashboard.k8s.yourdomain.com
- **Headlamp**: https://headlamp.k8s.yourdomain.com
- **Loki**: https://loki.k8s.yourdomain.com
- **Tempo**: https://tempo.k8s.yourdomain.com
- **OpenCost**: https://opencost.k8s.yourdomain.com
- **Kubeshark**: https://kubeshark.k8s.yourdomain.com

### Step 8: Change Default Passwords

1. **ArgoCD**: Change admin password
   ```bash
   argocd login argocd.k8s.yourdomain.com
   argocd account update-password
   ```

2. **Grafana**: Change admin password (default: admin/admin)
   - Log in to Grafana
   - Profile → Change Password

3. **Authelia**: Already updated in Step 2

4. **Kubernetes Dashboard**: Get token
   ```bash
   kubectl -n kubernetes-dashboard create token admin-user
   ```

## Application Management

### Sync an Application

```bash
# Manually sync an application
argocd app sync <app-name>

# Sync all applications
argocd app sync -l argocd.argoproj.io/instance=root-app
```

### Check Application Status

```bash
# Get application details
argocd app get <app-name>

# View application logs
argocd app logs <app-name>

# Get events
kubectl describe application <app-name> -n argocd
```

### Add a New Application

1. Create a new directory: `k8s/apps/my-app/`
2. Add manifests or `application.yaml`
3. Commit and push
4. ArgoCD will automatically detect and sync

## Protecting Apps with Authelia

To require authentication for any application:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-protected-app
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`app.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authelia
          namespace: authelia  # Add Authelia middleware
      services:
        - name: my-app
          port: 80
  tls:
    certResolver: default
```

## Observability Stack Usage

### View Logs (Loki)

1. Open Grafana
2. Go to Explore → Select "Loki" datasource
3. Query: `{namespace="default"} |~ "error"`

### View Metrics (Prometheus)

1. Open Grafana
2. Go to Explore → Select "Prometheus" datasource
3. Query: `rate(container_cpu_usage_seconds_total[5m])`

### View Traces (Tempo)

1. Instrument your app to send traces to Tempo
2. Open Grafana
3. Go to Explore → Select "Tempo" datasource
4. Search by trace ID or service name

## Secrets Management

### Option 1: Sealed Secrets (Recommended for GitOps)

```bash
# Create and seal a secret
kubectl create secret generic my-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > my-secret-sealed.yaml

# Commit to Git
git add my-secret-sealed.yaml
git commit -m "Add encrypted secret"
```

### Option 2: External Secrets

Create a SecretStore and ExternalSecret to sync from external providers (AWS, GCP, Vault, etc).

See `apps/external-secrets/README.md` for examples.

## Troubleshooting

### ArgoCD application out of sync

```bash
# Check diff
argocd app diff <app-name>

# Force sync
argocd app sync <app-name> --force

# Prune resources
argocd app sync <app-name> --prune
```

### Pod not starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Ingress not working

```bash
# Check IngressRoute
kubectl get ingressroute -n <namespace>
kubectl describe ingressroute <name> -n <namespace>

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# Test DNS resolution
dig app.k8s.yourdomain.com
```

### Authentication issues (Authelia)

```bash
# Check Authelia logs
kubectl logs -n authelia -l app=authelia

# Check Redis is running
kubectl get pods -n authelia -l app=authelia-redis

# Test Authelia health
curl https://auth.k8s.yourdomain.com/api/health
```

## Backup and Disaster Recovery

### Backup ArgoCD Applications

ArgoCD applications are defined in Git, so your Git repository is the source of truth.

### Backup Sealed Secrets Master Key

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key.yaml

# Store this file securely (NOT in Git!)
```

### Backup Persistent Data

Important persistent volumes:
- Prometheus: `/prometheus/` (50GB)
- Loki: `/var/loki/` (50GB)
- Tempo: `/var/tempo/` (50GB)
- Grafana: `/var/lib/grafana/` (10GB)

Use Velero or Longhorn's built-in backup features.

## Scaling

### Scale Applications

Edit the application's Helm values or manifests and commit to Git. ArgoCD will automatically sync.

### Scale Cluster

Edit node pools in `../infra/kube.tf` and run `terraform apply`.

## Security Best Practices

1. ✅ **Secrets**: Use Sealed Secrets or External Secrets
2. ✅ **Authentication**: Enable Authelia for all sensitive apps
3. ✅ **RBAC**: Use Kubernetes RBAC for fine-grained access control
4. ✅ **Network Policies**: Define NetworkPolicies to restrict pod communication
5. ✅ **Resource Limits**: Set resource requests/limits for all pods
6. ✅ **Image Scanning**: Use tools like Trivy or Snyk
7. ✅ **Pod Security**: Use Pod Security Standards

## Next Steps

1. Configure SMTP for Authelia notifications
2. Set up Alertmanager with Slack/PagerDuty/email
3. Create custom Grafana dashboards
4. Set up Prometheus recording rules
5. Configure log retention policies
6. Set up regular backups with Velero
7. Implement NetworkPolicies
8. Configure Pod Security Policies

## Documentation

Each application has its own README:

- [ArgoCD](./apps/argocd/)
- [Authelia](./apps/authelia/README.md)
- [CloudNativePG](./apps/cnpg/README.md)
- [Dashboard](./apps/dashboard/README.md)
- [External Secrets](./apps/external-secrets/README.md)
- [Headlamp](./apps/headlamp/README.md)
- [Kubeshark](./apps/kubeshark/README.md)
- [Logging Stack](./apps/logging/README.md)
- [Monitoring Stack](./apps/monitoring/README.md)
- [OpenCost](./apps/opencost/README.md)
- [Reloader](./apps/reloader/README.md)
- [Sealed Secrets](./apps/sealed-secrets/README.md)
- [Tracing](./apps/tracing/README.md)
- [Traefik Plugins](./apps/traefik-plugins/README.md)
