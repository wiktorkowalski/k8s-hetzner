# Quick Start: Post-Cleanup Actions

## 🔴 Critical: Create Sealed Secrets (Required)

Values files currently have `TEMP-REPLACE-ME-WITH-SEALEDSECRET` placeholders.

### 1. Install kubeseal CLI
```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### 2. Create Authentik Secrets
```bash
# Generate secure values
AUTHENTIK_SECRET=$(openssl rand -base64 64)
DB_PASSWORD=$(openssl rand -base64 32)

# Create and seal
kubectl create secret generic authentik-secrets \
  --from-literal=secret-key="$AUTHENTIK_SECRET" \
  --from-literal=db-password="$DB_PASSWORD" \
  --namespace authentik \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > k8s/apps/authentik-helm/manifests/sealed-secret.yaml

# Commit to git
git add k8s/apps/authentik-helm/manifests/sealed-secret.yaml
```

### 3. Create Grafana Secret
```bash
GRAFANA_PASSWORD=$(openssl rand -base64 24)

kubectl create secret generic grafana-admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --namespace monitoring \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > k8s/apps/monitoring/manifests/sealed-secret.yaml

git add k8s/apps/monitoring/manifests/sealed-secret.yaml
```

### 4. Update values.yaml files

In `apps/authentik-helm/values.yaml`, uncomment the secretKeyRef sections and remove temp values.

In `apps/monitoring/values.yaml`, uncomment existingSecret config and remove temp value.

### 5. Commit everything
```bash
git add .
git commit -m "feat: add sealed secrets and complete security hardening"
git push
```

ArgoCD will auto-sync and deploy with sealed secrets.

## ✅ What Was Already Fixed

- Removed duplicate apps (authentik manual, authelia, headlamp, external-secrets)
- Fixed RBAC: dashboard now read-only (no cluster-admin)
- Added security contexts: runAsNonRoot, drop ALL caps
- Fixed domains: no more `k8s.k8s.vicio.ovh`
- Added sync waves: operators → infrastructure → apps
- Externalized Helm values for easier management
- Added NetworkPolicies and PodDisruptionBudgets (monitoring)
- Added Redis persistence to Authentik

## 📝 Optional Improvements

### Enable CNPG Backups
Edit `apps/authentik-helm/manifests/postgres-cnpg.yaml`:
- Uncomment backup sections
- Configure S3-compatible storage

### Add More NetworkPolicies
Template: `apps/monitoring/manifests/network-policy.yaml`
- Copy/adapt for other namespaces
- Implement zero-trust networking

### Add More PodDisruptionBudgets
Template: `apps/monitoring/manifests/pdb.yaml`
- Add for Authentik, Loki, Tempo

## 🚀 Deployment Order (Sync Waves)

ArgoCD deploys in this order:
1. **Wave 0**: sealed-secrets, cnpg, reloader
2. **Wave 1**: monitoring, logging, tracing
3. **Wave 2**: authentik, dashboard, etc.

Check sync status:
```bash
kubectl get applications -n argocd
```

## 📊 Verify Deployment

```bash
# Check all apps synced
kubectl get applications -n argocd

# Check sealed secrets controller
kubectl get pods -n kube-system | grep sealed-secrets

# Verify secrets created
kubectl get sealedsecrets -A
kubectl get secrets -n authentik authentik-secrets
kubectl get secrets -n monitoring grafana-admin

# Test Grafana login
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit http://localhost:3000 (use password from earlier)
```

## 🔒 Security Checklist

- [ ] Created and committed SealedSecrets
- [ ] Updated values.yaml to use secrets
- [ ] Removed TEMP placeholders
- [ ] Verified no plaintext secrets in git
- [ ] Dashboard has read-only RBAC
- [ ] All pods have security contexts
- [ ] NetworkPolicies deployed

## ⚠️ Breaking Changes

These apps will be deleted on next sync:
- `authentik` (manual version) - replaced by authentik-helm
- `authelia` - removed
- `headlamp` - removed
- `external-secrets` - removed

Manually clean up if needed:
```bash
kubectl delete namespace authelia
kubectl delete all -n headlamp -l app=headlamp
```

## 🆘 Troubleshooting

**SealedSecret not decrypting:**
```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify secret was created
kubectl get secrets -n <namespace> <secret-name>
```

**App not syncing:**
```bash
# Force sync
kubectl patch application <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**Need to rollback:**
```bash
git revert HEAD
git push
# ArgoCD will auto-sync to previous state
```
