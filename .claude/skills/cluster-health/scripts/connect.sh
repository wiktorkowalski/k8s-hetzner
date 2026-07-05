#!/usr/bin/env bash
# Establish kubectl access to the k8s-hetzner cluster from anywhere. Tries in order:
#   1. direct    — kube API 6443 (works from home IP / allowlisted egress)
#   2. lb-https  — kube API via LB 443 TLS-SNI passthrough (works from HTTPS-proxy-only
#                  envs like Claude cloud sandboxes; kubectl honors HTTPS_PROXY)
#   3. ssh       — run `k3s kubectl` ON a control plane over SSH 22 (laptops without
#                  kubeconfig; impossible in Claude cloud sandboxes: no raw TCP egress)
#
# Usage:  eval "$(bash scripts/connect.sh)"   — then plain `kubectl` works in any mode.
#
# Inputs (remote env):
#   KUBECONFIG_B64       base64 of kubeconfig (terraform output -raw kubeconfig | base64).
#                        Required for modes 1+2.
#   CLUSTER_SSH_KEY_B64  base64 of the dedicated SSH private key (mode 3 only).
#
# Modes 1+2 need a kubectl binary; mode 3 only needs ssh. Cloud sandbox setup script
# (installs kubectl): see REFERENCE.md "Remote environment setup".
# CP host keys pinned in scripts/known_hosts (round-robin DNS). After a cluster
# rebuild regenerate it:
#   for ip in <cp-ips>; do ssh-keyscan -t ed25519 $ip | sed "s/^$ip/api.k8s.vicio.ovh/"; done
set -euo pipefail

API_HOST="api.k8s.vicio.ovh"
LB_HOST="kubeapi.k8s.vicio.ovh"   # wildcard *.k8s.vicio.ovh -> Hetzner LB
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${CLUSTER_HEALTH_DIR:-${TMPDIR:-/tmp}/cluster-health}"
mkdir -p "$WORKDIR/bin"
chmod 700 "$WORKDIR"

log() { echo "[connect] $*" >&2; }

# --- locate kubeconfig (optional; required for modes 1+2) ---
KC=""
if [ -n "${KUBECONFIG_B64:-}" ]; then
  KC="$WORKDIR/kubeconfig"
  printf '%s' "$KUBECONFIG_B64" | base64 -d > "$KC"
  chmod 600 "$KC"
elif [ -n "${KUBECONFIG:-}" ] && [ -f "${KUBECONFIG:-}" ]; then
  KC="$KUBECONFIG"
elif [ -f "$HOME/.kube/config" ]; then
  KC="$HOME/.kube/config"
fi

if [ -n "$KC" ] && ! command -v kubectl >/dev/null 2>&1; then
  log "ERROR: kubeconfig found but no kubectl binary. Add the Setup script from"
  log "REFERENCE.md (remote environment setup), or install kubectl now."
  exit 1
fi

# --- mode 1: direct ---
if [ -n "$KC" ] && KUBECONFIG="$KC" kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  log "direct API access OK"
  echo "export KUBECONFIG=$KC"
  exit 0
fi

# --- mode 2: LB 443 SNI passthrough (kubectl honors HTTPS_PROXY automatically) ---
if [ -n "$KC" ]; then
  # No tls-server-name override: kubeapi.* is in the apiserver cert SANs, and the
  # Anthropic egress proxy resets TLS when SNI != CONNECT host (anti-fronting).
  LKC="$WORKDIR/kubeconfig-lb"
  sed "s|server: https://[^[:space:]]*|server: https://${LB_HOST}:443|" "$KC" > "$LKC"
  chmod 600 "$LKC"
  if KUBECONFIG="$LKC" kubectl get --raw /readyz --request-timeout=10s >/dev/null 2>&1; then
    log "API access via LB 443 SNI passthrough OK"
    echo "export KUBECONFIG=$LKC"
    exit 0
  fi
  log "LB 443 path failed — falling back to SSH"
else
  log "no kubeconfig (set KUBECONFIG_B64) — trying SSH mode"
fi

# --- mode 3: kubectl-over-SSH via a control plane ---
if ! command -v ssh >/dev/null 2>&1; then
  log "ERROR: no working access path. Direct/LB need KUBECONFIG_B64 + kubectl;"
  log "SSH mode needs an ssh client (impossible in Claude cloud sandboxes — no raw TCP)."
  exit 1
fi

SSH_KEY_OPT=""
if [ -n "${CLUSTER_SSH_KEY_B64:-}" ]; then
  KEY="$WORKDIR/ssh-key"
  printf '%s' "$CLUSTER_SSH_KEY_B64" | base64 -d > "$KEY"
  chmod 600 "$KEY"
  SSH_KEY_OPT="-i $KEY"
fi

SSH_OPTS="$SSH_KEY_OPT -o BatchMode=yes -o ConnectTimeout=10 \
 -o UserKnownHostsFile=$SCRIPT_DIR/known_hosts -o StrictHostKeyChecking=yes -o CheckHostIP=no \
 -o ControlMaster=auto -o ControlPath=$WORKDIR/ssh-mux -o ControlPersist=10m"

if ! ssh $SSH_OPTS "root@$API_HOST" true 2>"$WORKDIR/ssh-err"; then
  log "ERROR: SSH to $API_HOST failed:"
  sed 's/^/[connect]   /' "$WORKDIR/ssh-err" >&2
  log "Set CLUSTER_SSH_KEY_B64 (base64 of the dedicated SSH key). If the host key"
  log "changed, the cluster was rebuilt — regenerate scripts/known_hosts (see header)."
  exit 1
fi

# kubectl wrapper: execs k3s kubectl on the CP, shell-safe quoting
cat > "$WORKDIR/bin/kubectl" <<EOF
#!/usr/bin/env bash
args=""
for a in "\$@"; do args+=" \$(printf '%q' "\$a")"; done
exec ssh $SSH_OPTS "root@$API_HOST" "k3s kubectl\$args"
EOF
chmod 755 "$WORKDIR/bin/kubectl"

if "$WORKDIR/bin/kubectl" get --raw /readyz --request-timeout=10s >/dev/null 2>&1; then
  log "kubectl-over-SSH OK (port-forward unavailable; use the API service proxy)"
  echo "export PATH=$WORKDIR/bin:\$PATH"
else
  log "ERROR: SSH works but 'k3s kubectl' on the CP failed"
  exit 1
fi
