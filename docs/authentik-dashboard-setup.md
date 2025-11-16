# Kubernetes Dashboard Setup

## Current Configuration: Token-Based Auth

Dashboard now requires token authentication. To get admin token:

```bash
kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

Copy token and use it to login at https://dashboard.k8s.vicio.ovh

## Alternative: Authentik OIDC Integration

**Note:** Kubernetes Dashboard OIDC integration is complex and requires:
- OAuth2 Proxy sidecar
- Additional middleware configuration
- More maintenance overhead

For production SSO, consider using:
1. **kubectl + kubeconfig**: Use Authentik OIDC for kubectl access
2. **Lens IDE**: Supports OIDC natively with better UX
3. **k9s**: Terminal UI with kubeconfig support

### If you still want OIDC for Dashboard:

1. Deploy OAuth2 Proxy with Authentik backend
2. Create Authentik OIDC provider for Dashboard
3. Configure Traefik ForwardAuth middleware
4. Update dashboard ingress to use ForwardAuth

This is significantly more complex than token-based auth and usually not worth the effort for Dashboard specifically.
