# Headlamp OIDC Integration with Authentik

## Step 1: Create OIDC Provider in Authentik

1. Go to **Applications** → **Providers**
2. Click **Create**
3. Select **OAuth2/OpenID Provider**
4. Fill in:
   - **Name**: `Headlamp`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Client type**: `Confidential`
   - **Client ID**: `headlamp` (or auto-generate)
   - **Redirect URIs/Origins (RegEx)**:
     ```
     https://headlamp.k8s.vicio.ovh/oidc-callback
     ```
   - **Signing Key**: Select auto-generated certificate
   - **Sub mode**: `Based on the User's hashed ID`
   - **Include claims in id_token**: ✓
5. Click **Finish**
6. **Save the Client ID and Client Secret**

## Step 2: Create Application in Authentik

1. Go to **Applications** → **Applications**
2. Click **Create**
3. Fill in:
   - **Name**: `Headlamp`
   - **Slug**: `headlamp`
   - **Provider**: Select **Headlamp** (provider from Step 1)
   - **Launch URL**: `https://headlamp.k8s.vicio.ovh`
4. Click **Create**

## Step 3: Create Authentik Group for K8s Admins

1. Go to **Directory** → **Groups**
2. Click **Create**
3. Fill in:
   - **Name**: `kubernetes-admins`
4. Add your user to this group

## Step 4: Configure Headlamp with OIDC

I'll update the Helm values with your Client ID and Secret.

## Step 5: Test

1. Go to https://headlamp.k8s.vicio.ovh
2. Should see "Sign in with OIDC" button
3. Click it → redirects to Authentik
4. Login → redirects back to Headlamp
5. Full K8s access based on your groups!
