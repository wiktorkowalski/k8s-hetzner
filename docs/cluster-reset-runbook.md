# Cluster reset runbook — in-place rebuild (fallback path)

> **Use this only when Hetzner is out of stock for the configured server
> types.** Per [ADR-0002](adr/0002-capacity-aware-cluster-resets.md),
> the default reset path is `terraform destroy` followed by
> `terraform apply` against the current code. This document is the
> fallback for when destroy is unsafe because Hetzner cannot resupply
> replacement VMs.

Procedure: wipe each VM's disk via `hcloud server rebuild`
(keeps server ID and IPs), then `terraform taint` the module's
null_resources for k3s install and `terraform apply` to re-bootstrap.
Read top to bottom; do not skip the canary.

**Pre-check (always):** before choosing this path, test the actual
stock for your server type in each location with a throwaway create:

```
hcloud server create --name capacity-test --type <type> --location <loc> --image debian-12 --start-after-create=false
hcloud server delete capacity-test
```

If creates succeed in every required location, use the fresh
destroy+apply path instead and ignore the rest of this document.

## Phase 0 — Pre-flight

Before touching anything destructive.

### 0.1 Verify TF Cloud workspace env vars

`infra/backend.tf` configures TF Cloud as the state backend, so `apply`
runs on TF Cloud's runners — env vars from the GH Actions runner are
**not** forwarded. Verify these exist as workspace variables (Settings →
Variables → Environment Variables, marked sensitive):

- `HCLOUD_TOKEN`
- `CLOUDFLARE_API_TOKEN`
- `TF_VAR_cloudflare_zone_id`
- `TF_VAR_domain`
- `TF_VAR_ssh_public_key` (content, not path)
- `TF_VAR_ssh_private_key` (content, not path)

If any are missing, set them now. Without these, the rebuild's
`terraform apply` will fail mid-flight with no cluster to fall back to.

### 0.2 Local state cleanup

```
rm infra/terraform.tfstate infra/terraform.tfstate.backup
```

These are pre-TFCloud orphans; not in git, not authoritative.

### 0.3 Snapshot inventory

Confirm the MicroOS snapshot we'll rebuild onto exists:

```
hcloud image list --type snapshot
# Expect: 329330654 OpenSUSE MicroOS x86 by Kube-Hetzner
```

Snapshot is 2025-10-31 (~7 months old). MicroOS auto-updates on first
boot will catch it up. Optional: rebuild a fresh snapshot via
`packer build packer/hcloud-microos-snapshots.pkr.hcl` if you want to
skip those updates.

### 0.4 Note current LB IP and the IDs you'll need

```
hcloud server list -o columns=id,name -o noheader
hcloud load-balancer list -o columns=id,name -o noheader
hcloud network list -o columns=id,name -o noheader
```

Expected today (record for reference):

| Resource | ID | Name |
| --- | --- | --- |
| Server | 113006015 | k8s-hetzner-control-plane-hel1-duv |
| Server | 113006016 | k8s-hetzner-agent-small-nbg1-wdh (canary) |
| Server | 113006017 | k8s-hetzner-control-plane-fsn1-zkf |
| Server | 113006018 | k8s-hetzner-control-plane-nbg1-jhd |
| Server | 115387021 | k8s-hetzner-agent-small-hel1-exh |
| LB | 5139082 | k8s-hetzner-traefik (DNS target 128.140.28.152) |
| Network | 11635709 | k8s-hetzner |

## Phase 1 — Safety scaffolding

Lock the Hetzner-side delete bit on every resource we cannot afford to
lose. Note: **delete-only** — not rebuild — because we need rebuild for
the reset itself.

```
for id in 113006015 113006016 113006017 113006018 115387021; do
  hcloud server enable-protection "$id" delete
done

hcloud load-balancer enable-protection 5139082 delete
hcloud network enable-protection 11635709 delete
```

After this point, no API caller (TF, the console, you in a tired
moment) can delete any of these. Verify:

```
hcloud server describe 113006015 -o format='{{.Protection.Delete}}'
# expect: true
```

## Phase 2 — Canary rebuild on `nbg1-wdh`

The cordoned agent is the perfect test: already useless, no workloads.
Reset it first, verify the whole procedure, then do the other four.

### 2.1 Rebuild the canary

```
hcloud server rebuild 113006016 --image 329330654
```

This wipes the disk in place, keeps the server ID and all IPs. Wait
for `hcloud server describe 113006016 -o format='{{.Status}}'` to
return `running`. Boot takes ~1-2 min.

### 2.2 Clear stale SSH host key

```
ssh-keygen -R 116.203.145.53
```

### 2.3 Verify cloud-init actually re-ran

This is the make-or-break check. SSH in (using the same key TF uses):

```
ssh -o StrictHostKeyChecking=accept-new root@116.203.145.53 \
  'cloud-init status --long; uptime'
```

Expect `status: done`. If you see `disabled` or `not_run`, the packer
snapshot's cloud-init state wasn't fully cleaned — stop here, do not
proceed to the other four. Investigate before continuing.

### 2.4 Force kube-hetzner to re-bootstrap this node

In `infra/`:

```
terraform state list | grep "agent-small-nbg1"
# find the null_resource.agents["agent-small-nbg1-..."] entry
terraform taint 'module.kube-hetzner.null_resource.agents["..."]'
terraform plan -out=canary.plan
# REVIEW: must show zero "destroy" actions on any hcloud_server resource
terraform apply canary.plan
```

### 2.5 Verify canary rejoined

```
kubectl get node k8s-hetzner-agent-small-nbg1-wdh -o wide
# Status: Ready (will be SchedulingDisabled until you uncordon)
kubectl uncordon k8s-hetzner-agent-small-nbg1-wdh
```

If the node is Ready: procedure works. Proceed to Phase 3. If it
doesn't rejoin cleanly: stop, diagnose, do not touch the other VMs.

## Phase 3 — Full reset

Now repeat for the remaining four. The cluster will be unavailable
~5-10 minutes total; DNS stays pointing at the LB IP, which persists
through the rebuild because the LB itself is untouched.

### 3.1 Drain ArgoCD (optional, but tidy)

```
kubectl scale deployment -n argocd --replicas=0 --all
```

Prevents ArgoCD from frantically reconciling against half-dead nodes.

### 3.2 Rebuild remaining four

Do them in parallel or sequentially; the cluster is going down either
way.

```
for id in 113006015 113006017 113006018 115387021; do
  hcloud server rebuild "$id" --image 329330654
done
```

Wait for all four to return to `running`.

### 3.3 Clear stale SSH host keys

```
for ip in 37.27.8.119 49.12.188.113 157.90.172.249 77.42.34.73; do
  ssh-keygen -R "$ip"
done
```

### 3.4 Taint module bootstrap resources

```
cd infra
terraform state list | grep -E "null_resource\.(first_control_plane|control_planes|agents|kustomization)" \
  | xargs -n1 terraform taint
terraform plan -out=reset.plan
# CRITICAL REVIEW: zero "destroy" on hcloud_server, hcloud_load_balancer, hcloud_network.
# If any of those show destroy: STOP. The delete-protection from Phase 1 should make the
# apply fail anyway, but don't even try.
terraform apply reset.plan
```

### 3.5 Verify all five nodes Ready

```
kubectl get nodes
# all five: STATUS Ready, VERSION matches whatever k3s the v2.18.4 module installs
```

The LB will be `mixed` for a few minutes while hcloud-cloud-controller-
manager re-registers targets. Verify the IP is unchanged:

```
hcloud load-balancer describe 5139082 -o format='{{.PublicNet.IPv4.IP}}'
# expect: 128.140.28.152 (unchanged)
```

## Phase 4 — Module upgrade to v2.19.3

Disks are blank, cluster is freshly bootstrapped. Now bump the module
against a known-clean baseline.

### 4.1 In `infra/kube.tf`

```hcl
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.19.3"   # was "2.18.4"

  initial_k3s_channel = "v1.32"   # new — pin explicitly so v2.19 default doesn't surprise us

  # ... rest unchanged
}
```

### 4.2 Plan + line-by-line review

```
terraform init -upgrade
terraform plan -out=upgrade.plan
```

Read every line of the plan. Specifically watch for:
- `# hcloud_server.* will be destroyed` → **STOP**.
- Forced replacement on `image`, `user_data`, `server_type`, `location`,
  `public_net`, or labels with create-before-destroy → **STOP**.
- In-place updates to null_resources / outputs / labels → fine.
- If `disable_hetzner_csi` removed (renamed upstream) → adjust input.

If clean:

```
terraform apply upgrade.plan
```

## Phase 5 — Repo cleanup

Cluster is up on v2.19.3 but ArgoCD isn't installed yet (we tore it
down in Phase 3). Clean the repo first, then re-bootstrap.

### 5.1 Wipe `k8s/apps`

```
rm -rf k8s/apps
rm k8s/{CLEANUP,IMPLEMENTATION,QUICK-START}-SUMMARY.md k8s/CONFIGURATION.md
# keep: k8s/README.md (rewrite below), k8s/bootstrap/, k8s/root-app/, k8s/scripts/
mkdir -p k8s/apps
```

### 5.2 Recreate MVP apps

Re-add `k8s/apps/argocd/` (self-managing ArgoCD `Application`) and
`k8s/apps/sealed-secrets/` (Helm chart `Application`). Each as one
`application.yaml` + `kustomization.yaml`; values inline or in
`values.yaml`. Keep them tight — under 50 lines each.

### 5.3 Patch traefik LB-adoption annotation

The MicroOS rebuild deleted `/var/lib/rancher/k3s/server/manifests/`,
so the kube-hetzner-installed Traefik comes back with the module's
defaults. The annotation
`load-balancer.hetzner.cloud/name: k8s-hetzner-traefik` must be set on
its Service or hcloud-cloud-controller-manager will create a **new** LB
and your DNS will break.

Add via `extra_manifests` in kube.tf or via a `k8s/apps/traefik-patch/`
ArgoCD app that patches the Service. The module supports
`traefik_additional_options`, `traefik_values` etc. — pick whichever
is cleanest; verify the annotation is on the resulting Service before
considering Phase 7 done.

### 5.4 Commit + push

```
git checkout -b reset/mvp-rebuild
git add CONTEXT.md docs/ k8s/ infra/
git commit -m "chore: cluster reset, MVP rebuild on kube-hetzner v2.19.3"
git push -u origin reset/mvp-rebuild
gh pr create --base master
# after CI green and review: gh pr merge <N> --squash --delete-branch
```

## Phase 6 — Bootstrap ArgoCD via the module

After Phase 4's apply, ArgoCD is gone. We could `kubectl apply` it
manually, but cleaner is to wire it into kube-hetzner so a fresh
`terraform apply` always brings ArgoCD up.

In `infra/kube.tf` (this lands in the same PR as Phase 5):

```hcl
extra_kustomize_parameters = {
  argocd_repo_url        = "https://github.com/wiktorkowalski/k8s-hetzner.git"
  argocd_target_revision = "master"
}

extra_kustomize_deployment_commands = <<-EOT
  kubectl apply -k https://github.com/wiktorkowalski/k8s-hetzner.git//k8s/bootstrap/argocd?ref=master
  kubectl apply -f https://raw.githubusercontent.com/wiktorkowalski/k8s-hetzner/master/k8s/root-app/root-application.yaml
EOT
```

(Verify field names against module docs at the pinned version —
upstream renamed some `extra_kustomize_*` fields between v2.18 and
v2.19.)

After merge, `terraform-apply.yml` runs in TF Cloud → ArgoCD installs
→ root-app picks up `k8s/apps/argocd` (self-managing) and
`k8s/apps/sealed-secrets` → cluster reaches green MVP.

## Phase 7 — Verify MVP green

```
kubectl get nodes                              # 5 Ready
kubectl get applications -n argocd             # argocd, sealed-secrets — Synced/Healthy
kubectl get svc -n traefik traefik -o yaml | grep load-balancer.hetzner
# annotation present: name=k8s-hetzner-traefik
hcloud load-balancer describe 5139082 -o format='{{.PublicNet.IPv4.IP}}'
# 128.140.28.152 (unchanged)
dig +short k8s.<your-domain>                   # 128.140.28.152
```

## Phase 8 — GH Actions cleanup

Now that ArgoCD owns app deployment, simplify CI.

- `terraform-plan.yml` / `terraform-apply.yml`: drop `main` from
  triggers (you use master). Remove the env vars that TF Cloud
  workspace variables already supply (or leave them — harmless
  duplicates).
- `k8s-bootstrap.yml`, `k8s-sync.yml`: delete. ArgoCD handles both.
- `k8s-validate.yml`: keep, runs yamllint + kubeconform on PRs.
- Remove `KUBECONFIG_BASE64` / `ARGOCD_AUTH_TOKEN` secrets if no
  workflow consumes them.

## Phase 9 — Follow-up PRs (not part of this reset)

One PR per app, each verified before the next:

1. `kube-prometheus-stack` (Prometheus + Grafana + Alertmanager)
2. `loki` + promtail
3. `tempo`
4. `cnpg` (operator)
5. `authentik` (depends on CNPG cluster manifest)
6. `headlamp`
7. Longhorn `BackupTarget` + `RecurringJob` pointing at Hetzner Storage
   Box (see [task #8](#) in TaskList)
8. CNPG WAL archiving to R2 (after CNPG is up)

## Rollback considerations

If Phase 3 rebuild fails partway and the cluster cannot recover:

- VMs are protected from delete — they aren't going anywhere.
- The old etcd / Longhorn data is gone (that's the whole point).
- Worst case: SSH to a node, manually run k3s install with the
  module's `_data/install.sh` payload, or `terraform taint` + apply
  again.
- The LB persists with its IP, so DNS keeps working even while the
  cluster behind it is empty.

No restoring-from-backup path exists for the MVP; that's accepted
because the MVP holds no state worth preserving. Once Longhorn backups
are configured (Phase 9 #7) and CNPG WAL is on (Phase 9 #8), real
recovery becomes possible.
