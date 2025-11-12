# External Secrets Operator

External Secrets Operator synchronizes secrets from external secret management systems (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, HashiCorp Vault, etc.) into Kubernetes Secrets.

## Installation

This is automatically installed via ArgoCD in the `external-secrets` namespace.

## Supported Backends

- AWS Secrets Manager
- AWS Parameter Store
- GCP Secret Manager
- Azure Key Vault
- HashiCorp Vault
- Doppler
- 1Password
- And many more...

## Usage Example

### 1. Create a SecretStore

A SecretStore defines how to access your external secret backend.

#### Example: AWS Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
```

#### Example: GCP Secret Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secrets
  namespace: default
spec:
  provider:
    gcpsm:
      projectID: my-project
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcp-credentials
            key: service-account-key
```

### 2. Create an ExternalSecret

An ExternalSecret defines which secrets to sync from the external backend.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: my-app-secrets  # Name of the Kubernetes Secret to create
    creationPolicy: Owner
  data:
    - secretKey: database-password  # Key in the Kubernetes Secret
      remoteRef:
        key: prod/my-app/database  # Key in AWS Secrets Manager
        property: password         # Optional: extract specific field from JSON
    - secretKey: api-key
      remoteRef:
        key: prod/my-app/api-key
```

### 3. Use the synchronized secret

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-app-secrets
                  key: database-password
```

## ClusterSecretStore

For organization-wide secret stores, use ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: global-aws-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            namespace: external-secrets
            key: access-key-id
```

## Verification

Check that the operator is running:

```bash
kubectl get pods -n external-secrets
```

Check ExternalSecret status:

```bash
kubectl get externalsecrets -A
kubectl describe externalsecret my-app-secrets
```

The created Kubernetes Secret:

```bash
kubectl get secret my-app-secrets -o yaml
```

## Documentation

Full documentation: https://external-secrets.io/
