# Sealed Secrets

Sealed Secrets allows you to encrypt Kubernetes secrets and safely store them in Git.

## Installation

This is automatically installed via ArgoCD. The controller is deployed to the `kube-system` namespace.

## Usage

### 1. Install kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/kubeseal-0.27.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### 2. Create a secret

```bash
# Create a normal Kubernetes secret (don't apply it yet)
kubectl create secret generic mysecret \
  --from-literal=password=mypassword \
  --dry-run=client \
  -o yaml > mysecret.yaml
```

### 3. Seal the secret

```bash
kubeseal -f mysecret.yaml -w mysealedsecret.yaml

# Clean up the unencrypted secret
rm mysecret.yaml
```

### 4. Commit the sealed secret to Git

```bash
git add mysealedsecret.yaml
git commit -m "Add encrypted secret"
```

### 5. Apply the sealed secret

```bash
kubectl apply -f mysealedsecret.yaml
```

The controller will automatically decrypt it and create the actual Secret in your cluster.

## Backup the Master Key

**IMPORTANT:** Back up the sealing key! If you lose it, you won't be able to decrypt your secrets.

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > master.key

# Store this file securely (e.g., password manager, encrypted backup)
# DO NOT commit this to Git!
```

## Restore the Master Key

If you need to restore the key (e.g., disaster recovery):

```bash
kubectl apply -f master.key
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
```
