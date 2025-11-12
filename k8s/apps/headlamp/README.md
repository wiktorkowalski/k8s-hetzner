# Headlamp - Modern Kubernetes Web UI

Headlamp is a modern, extensible, and user-friendly web UI for managing Kubernetes clusters.

## Installation

This is automatically installed via ArgoCD in the `headlamp` namespace.

## Access

- **Headlamp UI**: https://headlamp.k8s.yourdomain.com

## Features

- **Modern Interface** - Clean, intuitive design
- **Multi-cluster Support** - Manage multiple clusters (configure via kubeconfig)
- **RBAC Aware** - Respects Kubernetes RBAC permissions
- **Real-time Updates** - Live updates without refresh
- **Resource Management** - Create, edit, delete K8s resources via UI
- **Logs & Exec** - View logs and exec into containers
- **Plugin System** - Extend with custom plugins
- **Dark Mode** - Built-in dark/light themes
- **Metrics** - Resource usage graphs (CPU, memory)
- **CRD Support** - Manage custom resources

## Using Headlamp

### Dashboard View

The main dashboard shows:
- Cluster overview (nodes, pods, deployments)
- Resource usage graphs
- Recent events
- Namespace overview

### Navigate Resources

Left sidebar provides quick access to:
- **Workloads**: Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs
- **Config**: ConfigMaps, Secrets
- **Network**: Services, Ingresses, Network Policies
- **Storage**: PVCs, PVs, Storage Classes
- **Access Control**: ServiceAccounts, Roles, RoleBindings
- **Custom Resources**: CRDs and their instances

### Common Operations

#### View Pod Logs

1. Navigate to Workloads → Pods
2. Click on a pod
3. Click "Logs" tab
4. Select container (if multiple)
5. View real-time logs with auto-scroll

#### Execute into Container

1. Navigate to Workloads → Pods
2. Click on a pod
3. Click "Terminal" tab
4. Select container
5. Execute commands in the shell

#### Edit Resources

1. Navigate to any resource
2. Click the edit icon (pencil)
3. Edit YAML directly in the UI
4. Click "Apply" to save changes

#### Create Resources

1. Click "+" button (top right)
2. Paste YAML manifest
3. Click "Apply"

Or use the resource-specific "Create" button.

#### Delete Resources

1. Navigate to the resource
2. Click the delete icon (trash)
3. Confirm deletion

### Filtering and Search

- **Namespace filter**: Top bar - select specific namespaces or "All Namespaces"
- **Search**: Use search bar to find resources by name
- **Label filter**: Filter resources by labels

## Authentication

### Default Setup

By default, Headlamp uses the ServiceAccount token from the `headlamp` ServiceAccount (cluster-admin permissions).

### Protect with Authelia (Recommended)

Update the IngressRoute to require authentication:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: headlamp
  namespace: headlamp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`headlamp.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authelia
          namespace: authelia
      services:
        - name: headlamp
          port: 80
  tls:
    certResolver: default
```

### Multi-User RBAC

For multi-user access with different permissions:

1. Create separate ServiceAccounts for different roles:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: developer
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: developer-role
subjects:
  - kind: ServiceAccount
    name: developer
    namespace: headlamp
```

2. Users log in with their ServiceAccount token:

```bash
kubectl create token developer -n headlamp
```

3. In Headlamp, click "Settings" → "Cluster" → Add token

## Plugins

Headlamp supports plugins for extending functionality.

### Install Plugins

1. Enable persistence in the Helm values:

```yaml
persistentVolumeClaim:
  enabled: true
  size: 1Gi
```

2. Mount plugins directory and install plugins:

```bash
# Exec into Headlamp pod
kubectl exec -it -n headlamp deployment/headlamp -- sh

# Install a plugin (example)
cd /headlamp/plugins
wget https://github.com/headlamp-k8s/plugins/releases/download/v0.1.0/plugin.tar.gz
tar -xzf plugin.tar.gz
```

3. Restart Headlamp:

```bash
kubectl rollout restart deployment headlamp -n headlamp
```

### Popular Plugins

- **App Catalog** - Deploy popular applications from a catalog
- **Cost Viewer** - Integration with OpenCost
- **Pod Security** - View pod security policies
- **Resource Recommendations** - VPA recommendations

### Develop Custom Plugins

Headlamp plugins are TypeScript/React. See docs: https://headlamp.dev/docs/latest/development/plugins/

## Themes

Headlamp supports light and dark themes.

Change theme:
1. Click settings icon (top right)
2. Select "Light" or "Dark" theme

## Comparison with Kubernetes Dashboard

| Feature | Headlamp | K8s Dashboard |
|---------|----------|---------------|
| UI Design | Modern, clean | Traditional |
| Performance | Faster | Slower |
| Plugin Support | ✅ Yes | ❌ No |
| Multi-cluster | ✅ Easy | ⚠️ Complex |
| Terminal/Exec | ✅ Built-in | ✅ Built-in |
| Log Streaming | ✅ Real-time | ✅ Real-time |
| Resource Editing | ✅ YAML editor | ✅ YAML editor |
| Metrics | ✅ Built-in | ⚠️ Via metrics-server |
| Active Development | ✅ Very active | ⚠️ Slower |
| RBAC Support | ✅ Full | ✅ Full |

## Configuration

### Custom Branding

Configure Headlamp appearance:

```yaml
config:
  title: "My K8s Cluster"
  logoURL: "https://example.com/logo.png"
```

### Resource Limits

Adjust for larger clusters:

```yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Enable Metrics

Ensure metrics-server is installed:

```bash
kubectl top nodes
kubectl top pods -A
```

Headlamp will automatically show resource usage graphs.

## Troubleshooting

### Can't access UI

1. Check pod is running:
   ```bash
   kubectl get pods -n headlamp
   kubectl logs -n headlamp -l app.kubernetes.io/name=headlamp
   ```

2. Check ingress:
   ```bash
   kubectl get ingressroute headlamp -n headlamp
   kubectl describe ingressroute headlamp -n headlamp
   ```

3. Port forward directly:
   ```bash
   kubectl port-forward -n headlamp svc/headlamp 8080:80
   # Access at http://localhost:8080
   ```

### 403 Forbidden / RBAC errors

Headlamp needs appropriate RBAC permissions. By default, it has cluster-admin.

For custom permissions, create appropriate Role/RoleBindings.

### Resources not showing

1. Check namespace filter (top bar)
2. Verify RBAC permissions for the ServiceAccount
3. Check if resources exist:
   ```bash
   kubectl get all -A
   ```

### Logs not streaming

1. Ensure pods are running
2. Check if logs exist:
   ```bash
   kubectl logs <pod-name> -n <namespace>
   ```
3. Check browser console for errors

### Terminal/Exec not working

1. Verify pod has a shell:
   ```bash
   kubectl exec -it <pod-name> -- sh
   ```
2. Check browser console for WebSocket errors
3. Ensure ingress supports WebSockets (Traefik does by default)

## Security Best Practices

1. **Use Authelia** - Protect Headlamp behind SSO
2. **RBAC** - Use minimal permissions, not cluster-admin
3. **Read-only users** - Create view-only ServiceAccounts for developers
4. **Audit logs** - Enable K8s audit logging to track who does what
5. **Network policies** - Restrict Headlamp pod network access

### Read-only Access Example

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: viewer
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view  # Built-in read-only role
subjects:
  - kind: ServiceAccount
    name: viewer
    namespace: headlamp
```

Users can get token:

```bash
kubectl create token viewer -n headlamp --duration=24h
```

## Multi-Cluster Setup

To manage multiple clusters from one Headlamp instance:

1. Create a kubeconfig with multiple contexts
2. Mount it as a secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kubeconfig
  namespace: headlamp
type: Opaque
stringData:
  config: |
    apiVersion: v1
    kind: Config
    clusters:
      - name: prod-cluster
        cluster:
          server: https://prod.k8s.example.com
      - name: staging-cluster
        cluster:
          server: https://staging.k8s.example.com
    # ... contexts and users
```

3. Mount in Headlamp deployment:

```yaml
volumeMounts:
  - name: kubeconfig
    mountPath: /kubeconfig
volumes:
  - name: kubeconfig
    secret:
      secretName: kubeconfig
```

## Documentation

- Headlamp docs: https://headlamp.dev/docs/
- GitHub: https://github.com/headlamp-k8s/headlamp
- Plugin development: https://headlamp.dev/docs/latest/development/plugins/
