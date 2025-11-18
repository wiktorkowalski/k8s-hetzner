# ArgoCD OIDC Integration with Authentik

## 1. Create OIDC Provider in Authentik

1. Login to https://auth.k8s.vicio.ovh/if/admin/
2. Go to **Applications** → **Providers**
3. Click **Create** → **OAuth2/OpenID Provider**
4. Fill in:
   - **Name**: `ArgoCD`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Client type**: `Confidential`
   - **Client ID**: `argocd` (or generate)
   - **Client Secret**: Generate and save
   - **Redirect URIs**: `https://argocd.k8s.vicio.ovh/auth/callback`
   - **Signing Key**: Select auto-generated cert
5. Click **Finish**

## 2. Create Application in Authentik

1. Go to **Applications** → **Applications**
2. Click **Create**
3. Fill in:
   - **Name**: `ArgoCD`
   - **Slug**: `argocd`
   - **Provider**: `ArgoCD` (from step 1)
   - **Launch URL**: `https://argocd.k8s.vicio.ovh`
4. Click **Create**

## 3. Create Group for ArgoCD Admins

1. Go to **Directory** → **Groups**
2. Click **Create**
3. Fill in:
   - **Name**: `argocd-admins`
4. Add your user to this group

## 4. Update ArgoCD Secret with Client Secret

```bash
kubectl create secret generic argocd-secret \
  -n argocd \
  --from-literal=oidc.authentik.clientSecret='<CLIENT_SECRET_FROM_AUTHENTIK>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 5. Update argocd-cm ConfigMap

Edit `k8s/apps/argocd/manifests/argocd-cm.yaml`:
- Replace `<SET_IN_AUTHENTIK_UI>` with the Client ID from Authentik

## 6. Apply Manifests

Commit and push changes. ArgoCD will sync automatically.

## 7. Test

1. Logout from ArgoCD
2. Go to https://argocd.k8s.vicio.ovh
3. Click "Login via Authentik"
4. Should redirect to Authentik, then back to ArgoCD
5. If you're in `argocd-admins` group, you'll have admin access
