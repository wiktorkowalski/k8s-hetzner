# Traefik Plugins - Enhanced Ingress Capabilities

Traefik supports plugins to extend its functionality. This directory contains configuration for popular Traefik plugins.

## Note on kube-hetzner Traefik

Your cluster uses Traefik installed by kube-hetzner. To enable plugins, you'll need to configure Traefik via Helm values or ConfigMap.

## Available Plugins

### 1. Rate Limiting (traefik-rate-limit)

**Plugin:** `github.com/traefik/plugin-ratelimit`

Limit requests per IP address or per client.

### 2. GeoIP Blocking (traefik-geoblock)

**Plugin:** `github.com/PascalMinder/geoblock`

Block or allow traffic based on country (uses GeoIP database).

### 3. ModSecurity WAF

**Plugin:** `github.com/acouvreur/traefik-modsecurity-plugin`

Web Application Firewall using ModSecurity rules.

### 4. Fail2Ban

**Plugin:** `github.com/tommoulard/fail2ban`

Automatically ban IPs that exceed rate limits or show malicious behavior.

### 5. Real IP

**Plugin:** `github.com/soulbalz/traefik-real-ip`

Get real client IP when behind CloudFlare or other proxies.

### 6. Rewrite Body

**Plugin:** `github.com/traefik/plugin-rewritebody`

Modify response bodies (replace text, inject scripts, etc.).

## Installation Methods

Since kube-hetzner manages Traefik, you have two options:

### Option 1: Via Traefik ConfigMap (Simpler)

**Note:** This requires modifying kube-hetzner's Traefik installation.

1. Find the Traefik ConfigMap:
   ```bash
   kubectl get configmap -n kube-system | grep traefik
   ```

2. Add plugins configuration:
   ```yaml
   experimental:
     plugins:
       ratelimit:
         moduleName: github.com/traefik/plugin-ratelimit
         version: v0.8.0
       geoblock:
         moduleName: github.com/PascalMinder/geoblock
         version: v0.2.7
       fail2ban:
         moduleName: github.com/tommoulard/fail2ban
         version: v1.0.0
   ```

### Option 2: Deploy Additional Traefik Instance (Recommended)

Deploy a second Traefik instance with plugins for specific use cases:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: traefik-plugins
  namespace: kube-system
spec:
  chart: traefik
  repo: https://helm.traefik.io/traefik
  targetNamespace: traefik-plugins
  valuesContent: |-
    experimental:
      plugins:
        enabled: true
        ratelimit:
          moduleName: github.com/traefik/plugin-ratelimit
          version: v0.8.0
    ports:
      web:
        port: 8000
      websecure:
        port: 8443
```

## Plugin Examples

### Example 1: Rate Limiting

Limit requests to 100 per minute per IP:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: default
spec:
  plugin:
    ratelimit:
      average: 100
      period: 1m
      burst: 50
```

Apply to an IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  routes:
    - match: Host(`app.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: rate-limit
      services:
        - name: my-app
          port: 80
```

### Example 2: GeoIP Blocking

Block traffic from specific countries:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: geoblock
  namespace: default
spec:
  plugin:
    geoblock:
      silentStartUp: false
      allowLocalRequests: true
      logLocalRequests: false
      logAllowedRequests: false
      logApiRequests: true
      api: https://get.geojs.io/v1/ip/country/{ip}
      apiTimeoutMs: 500
      cacheSize: 25
      forceMonthlyUpdate: true
      allowUnknownCountries: false
      unknownCountryApiResponse: nil
      blackListMode: true
      countries:
        - CN  # China
        - RU  # Russia
        - KP  # North Korea
```

### Example 3: Fail2Ban

Automatically ban malicious IPs:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: fail2ban
  namespace: default
spec:
  plugin:
    fail2ban:
      rules:
        bantime: 3h
        findtime: 10m
        maxretry: 4
        enabled: true
```

Combine with rate limiting:

```yaml
middlewares:
  - name: rate-limit
  - name: fail2ban
```

### Example 4: Real IP (CloudFlare)

Get real client IP when behind CloudFlare:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: real-ip
  namespace: default
spec:
  plugin:
    real-ip:
      excludednets:
        - 10.0.0.0/8
        - 192.168.0.0/16
```

### Example 5: ModSecurity WAF

Web Application Firewall with OWASP rules:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: waf
  namespace: default
spec:
  plugin:
    modsecurity:
      modSecurityUrl: http://modsecurity:8080
      timeoutMillis: 2000
```

Requires ModSecurity instance:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: modsecurity
spec:
  replicas: 1
  selector:
    matchLabels:
      app: modsecurity
  template:
    metadata:
      labels:
        app: modsecurity
    spec:
      containers:
        - name: modsecurity
          image: owasp/modsecurity-crs:nginx
          ports:
            - containerPort: 8080
```

## Common Use Cases

### 1. Protect Admin Panel

```yaml
# Rate limit + GeoIP + Authelia
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: admin
spec:
  routes:
    - match: Host(`admin.k8s.yourdomain.com`)
      middlewares:
        - name: rate-limit  # Limit requests
        - name: geoblock    # Block certain countries
        - name: authelia    # Require authentication
          namespace: authelia
      services:
        - name: admin-panel
          port: 80
```

### 2. Public API with Rate Limiting

```yaml
# Higher rate limit for authenticated users
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: api-rate-limit
spec:
  plugin:
    ratelimit:
      average: 1000
      period: 1m
      burst: 100

---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api
spec:
  routes:
    - match: Host(`api.k8s.yourdomain.com`)
      middlewares:
        - name: api-rate-limit
        - name: fail2ban
      services:
        - name: api
          port: 80
```

### 3. Bot Protection

```yaml
# Strict rate limiting + fail2ban
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: bot-protection
spec:
  plugin:
    ratelimit:
      average: 20
      period: 1m
      burst: 5

---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strict-fail2ban
spec:
  plugin:
    fail2ban:
      rules:
        bantime: 24h
        findtime: 5m
        maxretry: 3
```

## Enabling Plugins in kube-hetzner

To enable plugins in your kube-hetzner Traefik installation:

### 1. Create Traefik ConfigMap Patch

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-plugins-config
  namespace: kube-system
data:
  traefik-plugins.yaml: |
    experimental:
      plugins:
        ratelimit:
          moduleName: github.com/traefik/plugin-ratelimit
          version: v0.8.0
        geoblock:
          moduleName: github.com/PascalMinder/geoblock
          version: v0.2.7
        fail2ban:
          moduleName: github.com/tommoulard/fail2ban
          version: v1.0.0
        realip:
          moduleName: github.com/soulbalz/traefik-real-ip
          version: v1.0.3
```

### 2. Restart Traefik

```bash
kubectl rollout restart deployment traefik -n kube-system
```

**Note:** This approach may be overwritten by kube-hetzner updates.

### Alternative: Terraform Configuration

Modify your `infra/kube.tf` to add Traefik values:

```hcl
module "kube-hetzner" {
  # ... existing configuration

  traefik_values = <<-EOT
    experimental:
      plugins:
        ratelimit:
          moduleName: github.com/traefik/plugin-ratelimit
          version: v0.8.0
  EOT
}
```

Then run `terraform apply`.

## Monitoring Plugin Performance

Check Traefik metrics for plugin impact:

```promql
# Request duration by middleware
histogram_quantile(0.95,
  sum(rate(traefik_service_request_duration_seconds_bucket[5m]))
  by (le, middleware)
)

# Requests blocked by rate limit
rate(traefik_middleware_requests_total{middleware="rate-limit",code="429"}[5m])
```

## Troubleshooting

### Plugin not loading

1. Check Traefik logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
   ```

2. Verify plugin configuration:
   ```bash
   kubectl exec -n kube-system deployment/traefik -- traefik version
   ```

3. Check plugin version compatibility

### Rate limiting not working

1. Verify middleware is applied to IngressRoute
2. Check if using correct IP (may need Real IP plugin behind CloudFlare)
3. Review Traefik access logs

### GeoIP blocking issues

1. Verify GeoIP API is accessible
2. Check cache size and TTL
3. Review logs for blocked countries

## Security Considerations

1. **Rate limiting** - Essential for preventing abuse and DoS
2. **GeoIP blocking** - Use for compliance or threat reduction
3. **Fail2Ban** - Automatic threat mitigation
4. **WAF (ModSecurity)** - Protect against OWASP Top 10
5. **Real IP** - Accurate logging and security behind proxies

## Plugin Resources

- Traefik Plugin Catalog: https://plugins.traefik.io/
- Creating custom plugins: https://doc.traefik.io/traefik/plugins/
- Plugin examples: https://github.com/traefik/plugindemo

## Best Practices

1. **Start simple** - Add one plugin at a time
2. **Test in staging** - Verify plugin behavior before production
3. **Monitor performance** - Some plugins add latency
4. **Version pin** - Use specific plugin versions
5. **Rate limits** - Tune based on actual traffic patterns
6. **Combine plugins** - Layer security (rate limit + fail2ban + auth)
7. **Logs** - Enable plugin logging for troubleshooting
