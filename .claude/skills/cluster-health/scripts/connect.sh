#!/usr/bin/env bash
# Establish kubectl access to the k8s-hetzner cluster from anywhere.
# 1. Tries direct API access (works from home IP / local machine).
# 2. Falls back to running `k3s kubectl` ON a control plane over SSH (port 22 is open
#    worldwide, key-only). sshd on the nodes has TCP forwarding disabled, so a tunnel
#    is not possible — instead a local `kubectl` wrapper execs every command remotely.
#    In this mode `kubectl port-forward` does NOT work; use the API service proxy
#    (kubectl get --raw '/api/v1/namespaces/<ns>/services/<svc>:<port>/proxy/...').
#
# Usage:  eval "$(bash scripts/connect.sh)"     — then plain `kubectl` works either way.
#
# Inputs (remote env):
#   CLUSTER_SSH_KEY_B64  base64 of the cluster SSH private key (the ssh_private_key
#                        from infra/terraform.tfvars). Optional if a default key works.
#   KUBECONFIG_B64       base64 of kubeconfig — only needed for the direct path.
#
# Host keys of the 3 CPs are pinned in scripts/known_hosts (api.k8s.vicio.ovh is
# round-robin DNS). After a cluster rebuild regenerate it:
#   for ip in <cp-ips>; do ssh-keyscan -t ed25519 $ip | sed "s/^$ip/api.k8s.vicio.ovh/"; done
set -euo pipefail

API_HOST="api.k8s.vicio.ovh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${CLUSTER_HEALTH_DIR:-${TMPDIR:-/tmp}/cluster-health}"
mkdir -p "$WORKDIR/bin"
chmod 700 "$WORKDIR"

log() { echo "[connect] $*" >&2; }

# --- direct access, if a kubeconfig is available ---
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

if [ -n "$KC" ] && KUBECONFIG="$KC" kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  log "direct API access OK"
  echo "export KUBECONFIG=$KC"
  exit 0
fi
log "no direct API access (expected outside home IP) — using kubectl-over-SSH via $API_HOST"

# --- ssh setup ---
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
  log "Set CLUSTER_SSH_KEY_B64 (base64 of the cluster SSH private key). If the host key"
  log "changed, the cluster was rebuilt — regenerate scripts/known_hosts (see header)."
  exit 1
fi

# --- kubectl wrapper: execs k3s kubectl on the CP, shell-safe quoting ---
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
