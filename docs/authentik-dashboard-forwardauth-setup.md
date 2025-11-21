# Kubernetes Dashboard SSO with Authentik ForwardAuth

## Step 1: Create Proxy Provider in Authentik

1. Go to **Applications** → **Providers**
2. Click **Create**
3. Select **Proxy Provider**
4. Fill in:
   - **Name**: `Kubernetes Dashboard`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Type**: `Forward auth (single application)`
   - **External host**: `https://dashboard.k8s.vicio.ovh`
5. Click **Finish**

## Step 2: Create Application in Authentik

1. Go to **Applications** → **Applications**
2. Click **Create**
3. Fill in:
   - **Name**: `Kubernetes Dashboard`
   - **Slug**: `kubernetes-dashboard`
   - **Provider**: Select **Kubernetes Dashboard** (provider from Step 1)
   - **Launch URL**: `https://dashboard.k8s.vicio.ovh`
4. Click **Create**

## Step 3: Create Authentik Outpost (if not exists)

1. Go to **Applications** → **Outposts**
2. Check if **authentik Embedded Outpost** exists
3. If not, click **Create**:
   - **Name**: `authentik Embedded Outpost`
   - **Type**: `Proxy`
   - **Integration**: `local` (no integration needed)
4. Click **Create**
5. Edit the outpost:
   - **Applications**: Select **Kubernetes Dashboard**
   - Click **Update**

## Step 4: Apply Kubernetes Manifests

Manifests already created and will be applied via ArgoCD automatically.

## Step 5: Test

1. Go to https://dashboard.k8s.vicio.ovh
2. Should redirect to Authentik login
3. Login with GitHub or akadmin
4. Should redirect back to Dashboard
5. You're logged in!

## Troubleshooting

If you get permission errors in Dashboard:
1. Create group in Authentik: `kubernetes-admins`
2. Add your user to the group
3. Create ClusterRoleBinding in K8s (already done via rbac.yaml if group matches)
