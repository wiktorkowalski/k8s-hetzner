# Centralized Configuration Guide

This guide explains how to configure your Kubernetes applications in one place.

## Overview

Instead of manually editing 20+ files to replace `YOURDOMAIN.COM` and `YOUR_USERNAME`, you can now:

1. Edit **one file** (`config.env`)
2. Run **one script** (`./scripts/apply-config.sh`)
3. All manifests are updated automatically

## Quick Start

```bash
# 1. Copy the example config
cp config.env.example config.env

# 2. Edit with your values
nano config.env

# 3. Apply to all manifests
./scripts/apply-config.sh
```

## Configuration Options

Edit `config.env`:

```bash
# Your domain (without subdomain)
DOMAIN=example.com

# Kubernetes subdomain (creates k8s.example.com)
CLUSTER_SUBDOMAIN=k8s

# Your GitHub username or organization
GITHUB_USERNAME=your-username

# Your GitHub repository name
GITHUB_REPO=k8s-hetzner

# Git branch to track
GIT_BRANCH=main
```

## What Gets Updated

The script replaces placeholders in all YAML files:

### Domain Replacements
- `YOURDOMAIN.COM` → `k8s.example.com` (in ingress files)
- `yourdomain.com` → `example.com` (in Authelia config)

### GitHub Replacements
- `YOUR_USERNAME` → Your actual username (in all application.yaml files)
- Updates Git repo URLs to: `https://github.com/your-username/k8s-hetzner.git`

### Files Affected
- All `apps/*/manifests/ingress.yaml` - Domain for ingress routes
- All `apps/*/application.yaml` - Git repository URLs
- `root-app/root-application.yaml` - Root app Git URL
- `apps/authelia/manifests/configmap.yaml` - Domain in configs
- `apps/authelia/manifests/middleware.yaml` - Domain in middleware

## Verification

After running the script, verify no placeholders remain:

```bash
# Check for remaining placeholders
grep -r "YOURDOMAIN.COM" . --include="*.yaml"
grep -r "YOUR_USERNAME" . --include="*.yaml"

# Should return nothing (exit code 1)
```

## Re-running the Script

You can safely run the script multiple times:
- It's idempotent (same result each time)
- Creates `.bak` backups before modifying files
- Cleans up backup files after successful replacement

To change configuration:

```bash
# 1. Edit config.env with new values
nano config.env

# 2. Re-run the script
./scripts/apply-config.sh
```

## Manual Override

If you need to customize specific files differently:

1. Run the script first to apply base configuration
2. Manually edit specific files as needed
3. Commit your changes

The script won't overwrite your changes unless you re-run it.

## Gitignore

`config.env` is gitignored (contains your actual values).

Only `config.env.example` is committed to Git (with placeholder values).

This means:
- ✅ You can commit updated manifests with your values
- ✅ Your actual domain/username are visible in manifests (fine for public repos)
- ❌ `config.env` stays local (team members create their own)

## Security Note

**Important:** This script does NOT handle secrets!

You still need to manually update:
- Authelia secrets in `apps/authelia/manifests/configmap.yaml`
- Any other sensitive values

See the main README for instructions on generating secure secrets.

## Troubleshooting

### Script fails with "DOMAIN is not set"

Make sure you copied `config.env.example` to `config.env` and edited it:

```bash
cp config.env.example config.env
nano config.env  # Change example.com to your domain
```

### Some placeholders remain after running script

Check that your `config.env` values don't contain the placeholders:

```bash
cat config.env | grep -E "example.com|YOUR_USERNAME"
```

If found, edit `config.env` with your actual values and re-run.

### Want to undo changes

If you haven't committed yet:

```bash
git checkout .
```

Then fix your `config.env` and re-run the script.

### Script creates .bak files everywhere

The script cleans up `.bak` files automatically. If you see them:

```bash
find . -name "*.bak" -delete
```

## Advanced: CI/CD Integration

For automated deployments, you can set environment variables instead:

```bash
export DOMAIN=example.com
export GITHUB_USERNAME=your-username
./scripts/apply-config.sh
```

Or pass them inline:

```bash
DOMAIN=example.com GITHUB_USERNAME=your-username ./scripts/apply-config.sh
```

## Alternative: Helm or Kustomize

If you prefer pure Kubernetes-native solutions:

- **Kustomize**: More complex, but doesn't modify source files
- **Helm**: Template-based, requires restructuring all manifests
- **This script**: Simple, bash-based, modifies files in place

The script approach is chosen for simplicity and ease of use.
