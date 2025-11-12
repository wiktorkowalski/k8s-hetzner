# Authelia - SSO & Authentication

Authelia provides Single Sign-On (SSO) and multi-factor authentication for your applications via Traefik ForwardAuth.

## Installation

This is automatically installed via ArgoCD in the `authelia` namespace.

## Access

- **Authelia Portal**: https://auth.k8s.yourdomain.com

## Important: First Steps

### 1. Update Domain Names

Replace `YOURDOMAIN.COM` in all config files:
- `k8s/apps/authelia/manifests/configmap.yaml`
- `k8s/apps/authelia/manifests/ingress.yaml`
- `k8s/apps/authelia/manifests/middleware.yaml`

### 2. Change Secrets

**CRITICAL:** Change these secrets in `configmap.yaml`:

```yaml
jwt_secret: CHANGEME_JWT_SECRET_AT_LEAST_32_CHARS
session.secret: CHANGEME_SESSION_SECRET_AT_LEAST_32_CHARS
storage.encryption_key: CHANGEME_STORAGE_ENCRYPTION_KEY_32_CHARS
```

Generate secure random secrets:

```bash
# Generate three 32-character secrets
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
```

**For production**, use Sealed Secrets instead of ConfigMap:

```bash
kubectl create secret generic authelia-secrets \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=session-secret="$(openssl rand -base64 32)" \
  --from-literal=storage-key="$(openssl rand -base64 32)" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > authelia-secrets-sealed.yaml
```

### 3. Change Default Password

Default credentials:
- Username: `admin`
- Password: `changeme`

Generate a new password hash:

```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourNewSecurePassword123!'
```

Update `users_database.yml` in the ConfigMap with the new hash.

### 4. Configure Email (Optional but Recommended)

For production, configure SMTP in `configmap.yaml`:

```yaml
notifier:
  smtp:
    host: smtp.gmail.com
    port: 587
    username: your-email@gmail.com
    password: your-app-password  # Use Sealed Secret!
    sender: authelia@yourdomain.com
```

## Usage

### Protect an Application with Authelia

To require authentication for any application, add the `authelia` middleware to its IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: protected-app
  namespace: default
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`app.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authelia
          namespace: authelia  # Reference the Authelia middleware
      services:
        - name: my-app
          port: 80
  tls:
    certResolver: default
```

When users visit `app.k8s.yourdomain.com`, they'll be redirected to Authelia to log in first.

### Example: Protect Grafana

Update Grafana's IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`grafana.k8s.yourdomain.com`)
      kind: Rule
      middlewares:
        - name: authelia
          namespace: authelia
      services:
        - name: kube-prometheus-stack-grafana
          port: 80
  tls:
    certResolver: default
```

## Access Control Rules

Configure access rules in `configmap.yaml`:

```yaml
access_control:
  default_policy: deny  # Deny by default
  rules:
    # Bypass auth for Authelia itself
    - domain: auth.k8s.yourdomain.com
      policy: bypass

    # Bypass auth for public APIs
    - domain: "api.k8s.yourdomain.com"
      resources:
        - "^/public/.*$"
      policy: bypass

    # One-factor auth (password only) for most apps
    - domain: "*.k8s.yourdomain.com"
      policy: one_factor

    # Two-factor auth (password + TOTP) for admin apps
    - domain:
        - "grafana.k8s.yourdomain.com"
        - "prometheus.k8s.yourdomain.com"
      policy: two_factor

    # Restrict to specific groups
    - domain: "admin.k8s.yourdomain.com"
      policy: two_factor
      subject:
        - "group:admins"
```

## User Management

Add users in `users_database.yml`:

```yaml
users:
  john:
    disabled: false
    displayname: "John Doe"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # Use generated hash
    email: john@example.com
    groups:
      - dev

  jane:
    disabled: false
    displayname: "Jane Smith"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: jane@example.com
    groups:
      - admins
      - dev
```

## Enable Two-Factor Authentication (TOTP)

1. Log in to Authelia: https://auth.k8s.yourdomain.com
2. Click on your username (top right)
3. Select "Two-Factor Authentication"
4. Scan the QR code with an authenticator app:
   - Google Authenticator
   - Authy
   - 1Password
   - Bitwarden
5. Enter the verification code

Now your account requires TOTP for login.

## Integration with Applications

Authelia passes authentication info via headers:

- `Remote-User`: Username
- `Remote-Groups`: Comma-separated groups
- `Remote-Name`: Display name
- `Remote-Email`: Email address

Your apps can use these headers for authorization:

```python
# Flask example
from flask import request

@app.route('/admin')
def admin():
    user = request.headers.get('Remote-User')
    groups = request.headers.get('Remote-Groups', '').split(',')

    if 'admins' not in groups:
        return "Forbidden", 403

    return f"Welcome admin {user}!"
```

## Session Configuration

- **Duration**: 1 hour
- **Inactivity timeout**: 5 minutes
- **Storage**: Redis (in-memory, ephemeral)

For persistence, use Redis with PVC or external Redis.

## Regulation (Brute Force Protection)

- **Max retries**: 3
- **Find time**: 2 minutes
- **Ban time**: 5 minutes

After 3 failed login attempts within 2 minutes, the user is banned for 5 minutes.

## Troubleshooting

### Check Authelia logs
```bash
kubectl logs -n authelia -l app=authelia
```

### Test authentication flow

1. Visit a protected app
2. You should be redirected to Authelia
3. Log in
4. You should be redirected back to the app

### Common issues

**Redirect loops:**
- Check that the middleware URL is correct
- Verify the `default_redirection_url` matches your domain

**Session not persisting:**
- Check Redis is running: `kubectl get pods -n authelia -l app=authelia-redis`
- Verify `session.domain` is set to root domain (e.g., `k8s.yourdomain.com`)

**TOTP not working:**
- Verify time sync on the server and client
- Check `totp.period` and `totp.skew` settings

## Advanced: LDAP/Active Directory

For enterprise, use LDAP instead of file-based auth:

```yaml
authentication_backend:
  ldap:
    url: ldap://openldap.default.svc.cluster.local:389
    base_dn: dc=example,dc=com
    username_attribute: uid
    additional_users_dn: ou=users
    users_filter: (&({username_attribute}={input})(objectClass=person))
    additional_groups_dn: ou=groups
    groups_filter: (&(member={dn})(objectClass=groupOfNames))
    group_name_attribute: cn
    mail_attribute: mail
    display_name_attribute: displayName
    user: cn=admin,dc=example,dc=com
    password: admin_password
```

## Documentation

- Authelia docs: https://www.authelia.com/
- Traefik ForwardAuth: https://doc.traefik.io/traefik/middlewares/http/forwardauth/
