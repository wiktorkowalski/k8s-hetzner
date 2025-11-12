# Kubernetes Dashboard

Web-based UI for Kubernetes clusters.

## Installation

This is automatically installed via ArgoCD in the `kubernetes-dashboard` namespace.

## Access

Access the dashboard at: https://dashboard.k8s.yourdomain.com

## Authentication

### Get the admin token

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

Copy the token and use it to log in to the dashboard.

### Create a long-lived token (optional)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
```

Apply it and retrieve:

```bash
kubectl apply -f admin-token-secret.yaml
kubectl get secret admin-user-token -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
```

## Security Warning

The admin-user ServiceAccount has cluster-admin privileges. For production:

1. Create separate ServiceAccounts with limited permissions for different users
2. Use Authelia/Authentik for SSO authentication
3. Consider using RBAC to limit access to specific namespaces

### Example: Read-only user

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: readonly-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: readonly-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: ServiceAccount
    name: readonly-user
    namespace: kubernetes-dashboard
```

## Features

- View cluster resources (pods, deployments, services, etc.)
- View logs and exec into containers
- View resource usage (CPU, memory)
- Create and edit resources via UI
- RBAC support

## Metrics

The dashboard includes a metrics scraper. For full metrics support, ensure metrics-server is installed:

```bash
kubectl top nodes
kubectl top pods -A
```
