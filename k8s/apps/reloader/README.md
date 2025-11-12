# Reloader

Reloader watches for changes in ConfigMaps and Secrets and automatically triggers rolling restarts of Deployments, StatefulSets, and DaemonSets that use them.

## Installation

This is automatically installed via ArgoCD in the `kube-system` namespace.

## Usage

Add annotations to your Deployments, StatefulSets, or DaemonSets to enable auto-reload:

### Watch specific ConfigMaps or Secrets

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    # Reload when these ConfigMaps change
    reloader.stakater.com/match: "true"
    configmap.reloader.stakater.com/reload: "my-config,another-config"
    # Reload when these Secrets change
    secret.reloader.stakater.com/reload: "my-secret,another-secret"
spec:
  template:
    spec:
      containers:
        - name: app
          envFrom:
            - configMapRef:
                name: my-config
            - secretRef:
                name: my-secret
```

### Auto-detect all ConfigMaps and Secrets

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    reloader.stakater.com/auto: "true"
spec:
  template:
    spec:
      containers:
        - name: app
          envFrom:
            - configMapRef:
                name: my-config
```

With `reloader.stakater.com/auto: "true"`, Reloader will automatically detect all ConfigMaps and Secrets used by the pod and trigger a reload when any of them change.

## Verification

Check Reloader logs:

```bash
kubectl logs -n kube-system -l app=reloader
```

You should see messages like:
```
Changes detected in 'my-secret' of type 'SECRET' in namespace 'default'
Updated 'my-app' of type 'Deployment' in namespace 'default'
```
