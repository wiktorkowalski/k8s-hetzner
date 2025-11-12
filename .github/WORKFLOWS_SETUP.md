# GitHub Actions Workflows Setup Guide

This guide covers setting up GitHub Actions workflows for Terraform and Kubernetes automation.

## Prerequisites

- GitHub repository with admin access
- Terraform Cloud account (free tier)
- Hetzner Cloud API token
- Cloudflare API token
- Running Kubernetes cluster with ArgoCD installed

## Setup Steps

### 1. Terraform Cloud Setup

1. **Create Terraform Cloud account**
   - Go to https://app.terraform.io/signup
   - Create free account

2. **Create organization and workspace**
   - Organization name: `YOUR_ORG_NAME`
   - Workspace name: `k8s-hetzner`
   - Execution mode: Remote

3. **Generate API token**
   - User Settings → Tokens → Create API Token
   - Save token for GitHub secrets

4. **Update backend config**
   - Edit `infra/backend.tf`
   - Replace `YOUR_ORG_NAME` with your org name

5. **Initialize backend**
   ```bash
   cd infra
   terraform init
   ```

### 2. GitHub Secrets Configuration

#### Required Secrets

Navigate to: Repository → Settings → Secrets and variables → Actions

**Terraform Secrets:**
- `TF_API_TOKEN` - Terraform Cloud API token
- `HCLOUD_TOKEN` - Hetzner Cloud API token (read/write)
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token (Zone:Read, DNS:Edit)

**Kubernetes Secrets:**
- `KUBECONFIG_BASE64` - Base64-encoded kubeconfig file
- `ARGOCD_SERVER` - ArgoCD server URL (e.g., `argocd.k8s.example.com`)
- `ARGOCD_AUTH_TOKEN` - ArgoCD authentication token

#### Generating Secrets

**KUBECONFIG_BASE64:**
```bash
cat ~/.kube/config | base64 | tr -d '\n'
```

**ARGOCD_AUTH_TOKEN:**
```bash
# Login to ArgoCD
argocd login argocd.k8s.example.com

# Generate token (no expiry)
argocd account generate-token --account github-actions
```

### 3. Optional: Variables for Cluster Validation

If you want to skip cluster validation on PRs (only run static validation):

Repository → Settings → Variables → Actions
- Name: `SKIP_CLUSTER_VALIDATION`
- Value: `true`

## Workflows Overview

### Terraform Workflows

**`terraform-plan.yml`** - Runs on PRs
- Validates Terraform code
- Runs `terraform plan`
- Posts plan as PR comment
- Warns about destructive changes

**`terraform-apply.yml`** - Runs on merge to main
- Automatically applies Terraform changes
- Updates infrastructure
- Posts summary to commit

### Kubernetes Workflows

**`k8s-validate.yml`** - Runs on PRs
- YAML syntax validation (yamllint)
- Kubernetes schema validation (kubeconform)
- Dry-run apply (kubectl)
- ArgoCD diff preview
- Posts validation report as PR comment

**`k8s-sync.yml`** - Runs on merge to main or manual trigger
- Syncs ArgoCD root-app
- Waits for sync completion
- Validates health status
- Can be manually triggered for specific apps

## Usage Examples

### Making Infrastructure Changes

1. Create PR with changes to `infra/`
2. Review Terraform plan in PR comment
3. Merge PR → automatic apply

### Updating Kubernetes Manifests

1. Create PR with changes to `k8s/`
2. Review validation report
3. Check ArgoCD diff preview
4. Merge PR → automatic sync

### Manual ArgoCD Sync

Go to Actions → ArgoCD Sync → Run workflow
- Choose app name (default: root-app)
- Enable/disable prune

## Troubleshooting

### Terraform Plan Fails

- Check Hetzner/Cloudflare tokens are valid
- Verify TF Cloud workspace exists
- Check backend.tf org name is correct

### Kubectl Dry Run Fails

- Verify KUBECONFIG_BASE64 is correct
- Check cluster is accessible
- Or set SKIP_CLUSTER_VALIDATION=true

### ArgoCD Sync Fails

- Verify ARGOCD_SERVER URL (no https://)
- Check ARGOCD_AUTH_TOKEN is valid
- Ensure token has sufficient permissions

### Workflow Not Triggering

- Check path filters match your changes
- Verify branch name (main vs master)
- Check workflow permissions

## Security Notes

- Never commit secrets to repository
- Rotate tokens regularly
- Use least-privilege access for tokens
- Review Terraform plans before merging
- Monitor ArgoCD sync status

## Cost Considerations

**Terraform Cloud Free Tier:**
- 500 managed resources (estimated usage: ~50-150)
- Unlimited users
- Remote state management included

**GitHub Actions:**
- 2,000 minutes/month for free accounts
- Public repos: unlimited minutes

## Next Steps

1. Test workflows with a small change
2. Monitor workflow runs in Actions tab
3. Set up branch protection rules (optional)
4. Configure ArgoCD auto-sync (optional)

## Support

For issues with workflows, check:
- GitHub Actions logs
- Terraform Cloud runs
- ArgoCD application status
