# Bootstrap ArgoCD

This directory contains the initial ArgoCD installation that must be applied manually once.

## Prerequisites

1. Ensure your cluster is running and kubectl is configured:
   ```bash
   export KUBECONFIG=../kubeconfig.yaml
   kubectl get nodes
   ```

2. Verify Traefik and cert-manager are running:
   ```bash
   kubectl get pods -n kube-system | grep traefik
   kubectl get pods -n kube-system | grep cert-manager
   ```

## Installation Steps

### 1. Install ArgoCD

```bash
# From the k8s/bootstrap directory
kubectl apply -k argocd/
```

### 2. Wait for ArgoCD to be ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### 3. Get the initial admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 4. Apply the root "App of Apps"

This will deploy all other applications managed by ArgoCD:

```bash
kubectl apply -f ../root-app/root-application.yaml
```

### 5. Access ArgoCD UI

After the ingress is configured (via the root app), access ArgoCD at:
- URL: https://argocd.k8s.yourdomain.com
- Username: admin
- Password: (from step 3)

**Important:** Change the admin password immediately after first login!

```bash
# Or use the ArgoCD CLI
argocd login argocd.k8s.yourdomain.com
argocd account update-password
```

## Verification

Check that all applications are synced:

```bash
kubectl get applications -n argocd
```

All apps should show "Synced" and "Healthy" status.

## Troubleshooting

### Check ArgoCD logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Check application status
```bash
kubectl describe application <app-name> -n argocd
```

### Force sync an application
```bash
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```
