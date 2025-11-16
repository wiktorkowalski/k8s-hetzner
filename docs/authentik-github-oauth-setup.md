# GitHub OAuth Setup for Authentik

## 1. Create GitHub OAuth App

1. Go to https://github.com/settings/developers
2. Click "New OAuth App"
3. Fill in:
   - **Application name**: `Authentik SSO - k8s.vicio.ovh`
   - **Homepage URL**: `https://auth.k8s.vicio.ovh`
   - **Authorization callback URL**: `https://auth.k8s.vicio.ovh/source/oauth/callback/github/`
4. Click "Register application"
5. Copy **Client ID**
6. Click "Generate a new client secret" and copy it

## 2. Configure in Authentik UI

1. Login to https://auth.k8s.vicio.ovh/if/admin/
2. Go to **Directory** → **Federation & Social login**
3. Click **Create** → **GitHub**
4. Fill in:
   - **Name**: `GitHub`
   - **Slug**: `github`
   - **Consumer key**: `<GitHub Client ID>`
   - **Consumer secret**: `<GitHub Client Secret>`
   - **Enabled**: ✓
5. Click **Finish**

## 3. Add to Authentication Flow

1. Go to **Flows & Stages** → **Flows**
2. Edit **default-authentication-flow**
3. Click **Stage Bindings**
4. Add GitHub source stage (should appear automatically)

## 4. Test

1. Logout from Authentik
2. Go to https://auth.k8s.vicio.ovh
3. Click "Login with GitHub"
4. Authorize app
5. You should be logged in
