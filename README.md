# Kubernetes Cluster on Hetzner Cloud

Production-ready High Availability Kubernetes cluster deployed on Hetzner Cloud using [terraform-hcloud-kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner), with automated DNS configuration via Cloudflare.

## Project Structure

```
.
├── infra/                  # Terraform infrastructure code
│   ├── providers.tf        # Provider configurations (Hetzner, Cloudflare)
│   ├── variables.tf        # Input variables
│   ├── kube.tf            # Kubernetes cluster configuration
│   ├── cloudflare.tf      # DNS records configuration
│   ├── outputs.tf         # Output values
│   └── terraform.tfvars.example  # Example variables file
├── k8s/                   # Kubernetes manifests
└── README.md
```

## Architecture

This configuration deploys:
- **3 Control Plane Nodes** across multiple locations (fsn1, nbg1, hel1) for high availability
- **3 Agent Nodes** (workers) for workload distribution
- **Cilium CNI** for advanced networking
- **Longhorn** for distributed storage
- **Traefik** ingress controller
- **Cert-Manager** for TLS certificate management
- **Cluster Autoscaler** for dynamic scaling
- **Automated DNS** with Cloudflare (subdomain + wildcard records)

## Prerequisites

Before deploying, ensure you have:

1. **Hetzner Cloud Account** with API token (Read & Write permissions)
   - Get it from: https://console.hetzner.cloud/ -> Security -> API Tokens

2. **Cloudflare Account** with domain and API token
   - Domain managed by Cloudflare DNS
   - API token with Zone.DNS (Edit) permissions: https://dash.cloudflare.com/profile/api-tokens
   - Zone ID from: https://dash.cloudflare.com/ -> Select domain -> Overview (right sidebar)

3. **Required Tools**:
   - [Terraform](https://www.terraform.io/downloads) or [OpenTofu](https://opentofu.org/docs/intro/install/) (>= 1.5.0)
   - [Packer](https://www.packer.io/downloads) (for creating MicroOS snapshot)
   - [hcloud CLI](https://github.com/hetznercloud/cli)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/)

4. **SSH Key Pair** (ed25519 without passphrase recommended)
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ```

## Installation

### 1. Install Required Tools

```bash
# macOS
brew install terraform packer hcloud kubectl

# Linux (Debian/Ubuntu)
# See official installation guides for each tool
```

### 2. Configure Environment

```bash
# Copy the example environment file
cp .envrc.example .envrc

# Edit .envrc and add your credentials
nano .envrc

# Required values:
# - HCLOUD_TOKEN (Hetzner Cloud API token)
# - CLOUDFLARE_API_TOKEN (Cloudflare API token)
# - TF_VAR_cloudflare_zone_id (Your Cloudflare zone ID)
# - TF_VAR_domain (Your domain name)

# Load environment variables
source .envrc
```

Alternatively, you can use `terraform.tfvars`:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

### 3. Customize Configuration (Optional)

Edit `infra/kube.tf` to adjust:
- Server types and locations (infra/kube.tf:20-87)
- Node counts
- CNI plugin choice
- Storage options

Edit `infra/variables.tf` or `infra/terraform.tfvars` to change:
- Cluster subdomain (default: "k8s")
- Cluster name
- Network region
- SSH key paths

### 4. Create MicroOS Snapshot

The cluster requires a MicroOS base image. First, download the Packer configuration:

```bash
# Create packer directory
mkdir -p packer
cd packer

# Download the Packer configuration from kube-hetzner repo
# Or follow: https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner#-creating-a-new-cluster

# Build the snapshot
packer init .
packer build -var hcloud_token=$HCLOUD_TOKEN microos-snapshot.pkr.hcl
cd ..
```

### 5. Deploy the Cluster

```bash
cd infra

# Initialize Terraform
terraform init --upgrade

# Validate configuration
terraform validate

# Plan deployment (review changes)
terraform plan

# Apply configuration (deploy cluster)
terraform apply

# Deployment takes approximately 5-10 minutes
```

### 6. Verify DNS Configuration

After deployment, verify your DNS records:

```bash
# Check the created DNS records
terraform output dns_records

# Verify DNS resolution (replace with your domain)
dig k8s.example.com
dig test.k8s.example.com  # wildcard test
```

Your DNS will be configured with:
- `k8s.example.com` → Load Balancer IP
- `*.k8s.example.com` → Load Balancer IP (wildcard)

### 7. Access Your Cluster

```bash
# Get kubeconfig (run from infra/ directory)
terraform output -raw kubeconfig > ../kubeconfig.yaml
cd ..
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Verify cluster is healthy
kubectl get nodes
kubectl get pods -A
```

## Configuration Details

### Control Plane Nodes
- 3 nodes across different locations for HA
- Server type: cpx21 (3 vCPU, 4GB RAM)
- Locations: fsn1, nbg1, hel1

### Agent Nodes
- 3 nodes for workload distribution
- Server type: cpx31 (4 vCPU, 8GB RAM)
- Auto-scaling enabled (0-5 additional nodes)

### Networking
- CNI: Cilium (advanced networking and security)
- Load Balancer: Hetzner LB (lb11)
- Network region: EU-Central
- DNS: Automated Cloudflare records (subdomain + wildcard)

### Storage
- Longhorn: Distributed block storage
- Hetzner CSI: For Hetzner volumes

### Automatic Updates
- OS updates: Enabled (MicroOS automatic updates)
- K3s updates: Enabled

## Cost Estimate

Approximate monthly costs (EU region):
- Control Plane (3x cpx21): ~€25/month
- Agent Nodes (3x cpx31): ~€40/month
- Load Balancer (lb11): ~€6/month
- **Total**: ~€71/month base cost + traffic/storage

## Maintenance

### Scaling Nodes

Edit the `count` field in `infra/kube.tf` for any nodepool, then:
```bash
cd infra
terraform apply
```

### Upgrading Kubernetes

Set `automatically_upgrade_k3s = true` in `infra/kube.tf` for automatic upgrades, or manually set the version.

### Destroying the Cluster

```bash
cd infra
terraform destroy
```

This will remove:
- All Hetzner resources (servers, load balancer, network)
- Cloudflare DNS records

## Troubleshooting

### Check cluster status
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Access control plane logs
```bash
kubectl logs -n kube-system -l component=kube-apiserver
```

### Hetzner Cloud Console
https://console.hetzner.cloud/

## Resources

- [terraform-hcloud-kube-hetzner Documentation](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)
- [Hetzner Cloud Pricing](https://www.hetzner.com/cloud)
- [K3s Documentation](https://docs.k3s.io/)

## DNS Configuration

The Terraform setup automatically creates:

1. **A Record**: `k8s.yourdomain.com` → Load Balancer IPv4
2. **Wildcard A Record**: `*.k8s.yourdomain.com` → Load Balancer IPv4

This means any service can be accessed via:
- `app1.k8s.yourdomain.com`
- `app2.k8s.yourdomain.com`
- `monitoring.k8s.yourdomain.com`
- etc.

All traffic will be routed through the Hetzner Load Balancer to your Traefik ingress controller.

## Deploying Applications

Example ingress configuration for your apps (save in `k8s/` directory):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  rules:
  - host: myapp.k8s.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
  tls:
  - hosts:
    - myapp.k8s.yourdomain.com
    secretName: myapp-tls
```

## Kubernetes Applications (GitOps with ArgoCD)

After deploying the cluster, you can deploy a full observability and security stack using ArgoCD.

See **[k8s/README.md](./k8s/README.md)** for complete documentation.

### Included Applications

**Observability (LGTM Stack):**
- **Grafana** - Unified dashboards and visualization
- **Prometheus** - Metrics collection and alerting
- **Loki** - Log aggregation
- **Tempo** - Distributed tracing
- **Alertmanager** - Alert routing
- **Promtail** - Log collector

**Security & Auth:**
- **Authelia** - SSO with Traefik ForwardAuth
- **Sealed Secrets** - Encrypted secrets for Git
- **External Secrets Operator** - Sync from external secret managers

**Database & Stateful Apps:**
- **CloudNativePG** - PostgreSQL operator for HA databases

**Cost & Performance:**
- **OpenCost** - Cost monitoring and optimization
- **Kubeshark** - API traffic analyzer for debugging

**Networking & Ingress:**
- **Traefik Plugins** - Rate limiting, GeoIP, WAF, Fail2Ban

**Infrastructure:**
- **ArgoCD** - GitOps continuous delivery
- **Kubernetes Dashboard** - Traditional web UI
- **Headlamp** - Modern, extensible web UI
- **Reloader** - Auto-restart pods on config changes

### Quick Start

```bash
# 1. Configure your cluster (one-time setup)
cd k8s
cp config.env.example config.env
nano config.env  # Edit with your domain and GitHub username
./scripts/apply-config.sh

# 2. Bootstrap ArgoCD
kubectl apply -k k8s/bootstrap/argocd/

# 3. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# 4. Deploy all applications
kubectl apply -f k8s/root-app/root-application.yaml

# 5. Watch applications deploy
kubectl get applications -n argocd --watch
```

### Access Your Applications

All apps will be available at `https://<app>.k8s.yourdomain.com`:

- **argocd** - GitOps dashboard
- **auth** - Authelia SSO portal
- **grafana** - Metrics, logs, and traces visualization
- **prometheus** - Metrics and alerts
- **alertmanager** - Alert management
- **dashboard** - Kubernetes Dashboard (traditional)
- **headlamp** - Modern Kubernetes web UI
- **loki** - Log query API
- **tempo** - Trace query API
- **opencost** - Cost monitoring dashboard
- **kubeshark** - API traffic analyzer

Default credentials:
- **ArgoCD**: admin / (see step 3 above)
- **Grafana**: admin / admin (change on first login!)
- **Authelia**: admin / changeme (update in config!)

## Next Steps

Once your cluster and applications are running:
1. ✅ Cluster deployed with Terraform
2. ✅ DNS configured via Cloudflare
3. ✅ ArgoCD managing all applications
4. ✅ Full observability stack (LGTM)
5. ✅ SSO with Authelia
6. 🔲 Configure SMTP for Authelia email notifications
7. 🔲 Set up Alertmanager notifications (Slack, PagerDuty, etc.)
8. 🔲 Create custom Grafana dashboards
9. 🔲 Set up backup strategy with Velero
10. 🔲 Deploy your applications!
