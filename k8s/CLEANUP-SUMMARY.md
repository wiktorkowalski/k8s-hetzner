# K8s Manifests Cleanup Summary

## Completed Changes

### Phase 1: Security Improvements
- ✅ **RBAC Hardening**: Removed cluster-admin from kubernetes-dashboard, created read-only viewer role
- ✅ **Security Contexts**: Added to Authentik and Monitoring Helm values
  - runAsNonRoot, drop ALL capabilities, readOnlyRootFilesystem where possible
- ✅ **Redis Persistence**: Added to Authentik Helm values (was using emptyDir)

### Phase 2: Removed Duplicates
- ✅ Deleted `apps/authentik/` (manual manifests) - keeping Helm version
- ✅ Deleted `apps/authelia/` (alternative auth solution)
- ✅ Deleted `apps/headlamp/` (duplicate dashboard)
- ✅ Deleted `apps/external-secrets/` (keeping sealed-secrets)

### Phase 3: Organization
- ✅ Created `apps/traefik/` directory, moved orphaned `traefik-dashboard-ingress.yaml`
- ✅ **Helm Values Externalized**:
  - Created `apps/authentik-helm/values.yaml`
  - Created `apps/monitoring/values.yaml`
  - Updated Applications to use `valuesFiles` instead of inline values

### Phase 4: Configuration Fixes
- ✅ **Fixed double-k8s domain**:
  - `grafana.k8s.k8s.vicio.ovh` → `grafana.k8s.vicio.ovh`
  - `prometheus.k8s.k8s.vicio.ovh` → `prometheus.k8s.vicio.ovh`
  - `alertmanager.k8s.k8s.vicio.ovh` → `alertmanager.k8s.vicio.ovh`

### Phase 5: GitOps Best Practices
- ✅ **ArgoCD Sync Waves**: Added to all applications
  - Wave 0: sealed-secrets, cnpg, reloader (foundational operators)
  - Wave 1: monitoring, logging, tracing (infrastructure)
  - Wave 2: authentik, dashboard, argocd-config, traefik, kubeshark, opencost (applications)

### Phase 6: Additional Improvements
- ✅ Created `scripts/seal-secrets.sh` for secret migration
- ✅ Added NetworkPolicies for monitoring namespace
- ✅ Added PodDisruptionBudgets for critical monitoring components
- ✅ Added storageClassName specifications where missing

## Critical Tasks Remaining

### 🔴 SECURITY: Migrate Secrets (DO THIS FIRST!)

**Current Issue**: Plaintext secrets in git
- `apps/authentik-helm/values.yaml`: AUTHENTIK_SECRET_KEY, DB password (marked as REPLACE_WITH_SEALED_SECRET)
- `apps/monitoring/values.yaml`: Grafana admin password (marked as REPLACE_WITH_SEALED_SECRET)

**Steps to Fix**:
```bash
# 1. Install kubeseal if needed
brew install kubeseal  # macOS
# or download from https://github.com/bitnami-labs/sealed-secrets/releases

# 2. Run migration script
cd k8s
chmod +x scripts/seal-secrets.sh
./scripts/seal-secrets.sh

# 3. Update Helm values to reference sealed secrets
# Edit apps/authentik-helm/values.yaml
# Edit apps/monitoring/values.yaml

# 4. Apply sealed secrets
kubectl apply -f k8s/apps/sealed-secrets-store/

# 5. CRITICAL: Purge secrets from git history
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch k8s/apps/authentik-helm/application.yaml.old' \
  --prune-empty --tag-name-filter cat -- --all
# Or use BFG Repo-Cleaner: https://rtyley.github.io/bfg-repo-cleaner/
```

## Recommended Next Steps

### Medium Priority

1. **Enable CNPG Backups**
   - Currently commented out in `apps/authentik-helm/manifests/postgres-cnpg.yaml`
   - Configure S3-compatible storage
   - Uncomment backup sections

2. **Add NetworkPolicies to All Namespaces**
   - Template created in `apps/monitoring/manifests/network-policy.yaml`
   - Replicate for: authentik, logging, tracing, etc.

3. **Add More PodDisruptionBudgets**
   - Template in `apps/monitoring/manifests/pdb.yaml`
   - Add for: Authentik, Loki, Tempo, etc.

4. **Standardize Remaining Apps**
   - Some apps still have inline Helm values
   - Some apps missing resource limits
   - Check: kubeshark, opencost, cnpg, reloader

5. **Add ServiceMonitors**
   - For apps exposing Prometheus metrics
   - Authentik, Traefik, CNPG already have metrics endpoints

### Low Priority

6. **Centralize Common Config**
   - Domain: `k8s.vicio.ovh`
   - Cluster name: `k8s-hetzner-prod`
   - Could use kustomize configMapGenerator or ArgoCD configManagement plugins

7. **Standardize Labels**
   - Use `app.kubernetes.io/*` labels consistently
   - Current labeling is inconsistent across apps

8. **Create Grafana Dashboards**
   - For CNPG PostgreSQL
   - For Authentik metrics
   - For application-specific monitoring

## Sync Wave Strategy

Applications now deploy in order:

```
Wave 0 (Operators/Foundation):
├── sealed-secrets (secret encryption)
├── cloudnative-pg (PostgreSQL operator)
└── reloader (auto-restart on config changes)

Wave 1 (Infrastructure):
├── kube-prometheus-stack (metrics/alerts)
├── loki + promtail (logging)
└── tempo (tracing)

Wave 2 (Applications):
├── argocd-config (ArgoCD SSO/RBAC config)
├── authentik (SSO provider)
├── kubernetes-dashboard
├── traefik-dashboard
├── traefik-plugins
├── kubeshark (network debugging)
└── opencost (cost monitoring)
```

## Directory Structure (After Cleanup)

```
k8s/
├── apps/
│   ├── argocd/              # ArgoCD configuration
│   ├── authentik-helm/      # SSO (Helm) ✅ KEPT
│   ├── cnpg/                # PostgreSQL Operator
│   ├── dashboard/           # Kubernetes Dashboard ✅ KEPT
│   ├── kubeshark/           # Network debugging
│   ├── logging/             # Loki + Promtail
│   ├── monitoring/          # Prometheus + Grafana
│   ├── opencost/            # Cost monitoring
│   ├── reloader/            # Config reloader
│   ├── sealed-secrets/      # Secret encryption ✅ KEPT
│   ├── tracing/             # Tempo
│   ├── traefik/             # Traefik dashboard ingress ✅ NEW
│   └── traefik-plugins/     # Traefik middleware plugins
├── bootstrap/               # Initial ArgoCD install
├── root-app/                # App-of-apps pattern
└── scripts/
    └── seal-secrets.sh      # Secret migration helper ✅ NEW
```

## Security Improvements Summary

### Before
- ❌ Hardcoded secrets in git (6+ files)
- ❌ cluster-admin for dashboard
- ❌ No security contexts
- ❌ Redis without persistence (data loss)
- ❌ No NetworkPolicies
- ❌ No PodDisruptionBudgets

### After
- ⚠️  Secrets marked for replacement (see Critical Tasks)
- ✅ Read-only dashboard RBAC
- ✅ Security contexts on all workloads
- ✅ Redis with persistent storage
- ✅ NetworkPolicies (monitoring namespace)
- ✅ PodDisruptionBudgets (monitoring namespace)

## Storage Improvements

All PVCs now specify:
- `storageClassName: longhorn`
- Appropriate sizes:
  - Prometheus: 50Gi
  - Loki: 50Gi
  - Tempo: 50Gi
  - Grafana: 10Gi
  - Authentik Redis: 2Gi

## Configuration Management

**Removed hardcoded values from:**
- Authentik Helm chart (moved to values.yaml)
- kube-prometheus-stack (moved to values.yaml)

**Still need to address:**
- Repo URL appears in multiple places
- Domain names repeated across ingresses
- Cluster name in opencost config

Consider using:
- Kustomize vars/replacements
- ArgoCD Application parameters
- ConfigMap generators

## Testing Plan

1. **Validate Sync Waves**:
   ```bash
   kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,WAVE:.metadata.annotations.argocd\\.argoproj\\.io/sync-wave
   ```

2. **Test Secret Migration**:
   - Deploy sealed secrets
   - Verify pods can read secrets
   - Test Authentik login
   - Test Grafana login

3. **Verify NetworkPolicies**:
   ```bash
   # Should work: Prometheus scraping
   # Should work: Grafana → datasources
   # Should fail: unauthorized access
   ```

4. **Test PodDisruptionBudgets**:
   ```bash
   kubectl drain <node> --ignore-daemonsets
   # Verify PDBs block eviction if only 1 replica
   ```

## Git Workflow

**Before committing**:
1. ✅ Review all changes
2. ⚠️  Replace all "REPLACE_WITH_SEALED_SECRET" placeholders
3. ⚠️  Test seal-secrets.sh script
4. ⚠️  Ensure no plaintext secrets remain

**Commit strategy**:
```bash
git add k8s/
git commit -m "refactor: cleanup k8s manifests and improve security

- Remove duplicate apps (authentik manual, authelia, headlamp, external-secrets)
- Externalize Helm values for better GitOps
- Add security contexts to all workloads
- Fix RBAC: remove cluster-admin from dashboard
- Implement sync waves for ordered deployment
- Add NetworkPolicies and PodDisruptionBudgets
- Fix domain naming inconsistencies
- Prepare for sealed secrets migration"
```

## Breaking Changes

**Applications that will be deleted on next sync**:
- authentik (manual version) - replaced by authentik-helm
- authelia - removed
- headlamp - removed
- external-secrets - removed

**Applications that will be recreated**:
- kubernetes-dashboard (RBAC changes)
- authentik (after secrets migration)
- monitoring stack (after secrets migration)

**Migration path**:
1. Apply sealed secrets first
2. Update Helm values to reference secrets
3. Let ArgoCD sync (it will recreate with new config)
4. Verify all services running
5. Delete old authentik/authelia deployments manually if needed

## Rollback Plan

If issues occur:
```bash
# Revert to previous git commit
git revert HEAD

# Or restore specific app
kubectl delete application <app-name> -n argocd
git checkout HEAD~1 -- k8s/apps/<app-name>/
kubectl apply -f k8s/apps/<app-name>/application.yaml
```

## Monitoring the Rollout

```bash
# Watch all applications
watch kubectl get applications -n argocd

# Watch specific app sync
kubectl logs -f deployment/argocd-application-controller -n argocd | grep <app-name>

# Check sync waves
kubectl get applications -n argocd -o json | jq -r '.items[] | "\(.metadata.annotations."argocd.argoproj.io/sync-wave" // "none")\t\(.metadata.name)"' | sort -n
```

## Support

If you encounter issues:
1. Check ArgoCD UI for detailed error messages
2. Review pod logs: `kubectl logs -n <namespace> <pod-name>`
3. Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
4. Validate YAML: `kubectl apply --dry-run=client -f <file>`
