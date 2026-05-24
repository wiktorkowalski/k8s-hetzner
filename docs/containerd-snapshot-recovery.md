# Containerd snapshot recovery after cluster rebuild

## Problem

After a full `terraform destroy` + `terraform apply` cycle, agent nodes may have corrupted containerd overlayfs snapshots. The containerd metadata database (bolt DB) references snapshot directories that don't exist on disk.

Symptoms:
- Pods stuck in `CreateContainerError` with: `failed to stat parent: stat /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/NNN/fs: no such file or directory`
- `ImagePullBackOff` where the pull succeeds but unpacking fails
- `exec format error` on some images (wrong platform variant cached)

## Root cause

During cluster provisioning, k3s pre-pulls images via containerd. On MicroOS nodes provisioned by kube-hetzner, some images end up with broken snapshot chains — the metadata database records parent snapshot references that point to nonexistent directories. This is a containerd bug where the snapshot GC doesn't reconcile metadata vs filesystem state.

Key facts:
- The bolt database (`meta.db`) survives k3s-agent restarts
- It survives full node reboots (stored on persistent disk)
- `crictl rmi` and `ctr images rm` don't clean orphaned snapshots
- `ctr snapshot rm` fails with "cannot remove snapshot with child"

## Fix

SSH to each affected agent node and wipe all containerd state. Use `nohup` because stopping k3s-agent may drop the SSH connection (it manages firewall rules).

```bash
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<NODE_IP> \
  "nohup bash -c 'systemctl stop k3s-agent; \
    rm -rf /var/lib/rancher/k3s/agent/containerd/io.containerd.metadata.v1.bolt \
           /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs \
           /var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content; \
    systemctl start k3s-agent' > /tmp/cleanup.log 2>&1 &"
```

Repeat for all 3 agent nodes. Get IPs from `hcloud server list`.

After the wipe, wait for each node to rejoin (`kubectl get nodes`), then delete any pods stuck in error states — they'll be rescheduled and pull fresh images.

## Impact

- ~10-15 minutes of scheduling disruption per node while all images re-pull
- No data loss — application data on Longhorn PVCs is unaffected
- Longhorn may briefly report nodes as "not ready" for volume attachment; volumes reattach after the node stabilises

## Prevention

This only happens after a full cluster destroy+rebuild. To avoid it entirely:

- **Never full destroy for server type changes.** Use `hcloud server change-type` in-place (power off → change type → power on). The filesystem persists and containerd state stays clean.
- If a full rebuild is unavoidable, proactively wipe containerd on all agent nodes immediately after `terraform apply` completes, before deploying workloads.

## When this was hit

2026-05-24 — cx23 → cx33 control plane upgrade required a full rebuild. All 3 agent nodes had corrupted snapshots affecting grafana, k8s-sidecar, and sealed-secrets-controller images.
