---
name: cluster-health
description: Diagnose and fix the k8s-hetzner cluster (k3s on Hetzner) from anywhere — sweeps firing alerts, nodes, pods, ArgoCD apps, Longhorn volumes, certs and events, then applies safe fixes automatically and asks before risky ones. Works remotely via LB 443 SNI passthrough to the kube API (Claude cloud sandboxes) or kubectl-over-SSH on a control plane (laptops). Use when the user asks to check/health-check the cluster, says something is down/broken/alerting, or invokes /cluster-health.
---

# Cluster Health

Diagnose-and-fix loop for the k3s cluster (`api.k8s.vicio.ovh`). Three access modes,
auto-selected by the connect script: direct 6443 (home IP), HTTPS via LB 443 SNI
passthrough (Claude cloud sandboxes — their egress is HTTPS-only, SSH can never work
there), and kubectl-over-SSH on a control plane (laptops without kubeconfig).

Load the other files only when you reach that step:
- [SWEEP.md](SWEEP.md) — the sweep command list (step 2)
- [REFERENCE.md](REFERENCE.md) — known failure modes, fix commands, cluster facts, remote setup

## 1. Connect

```bash
eval "$(bash .claude/skills/cluster-health/scripts/connect.sh)"
kubectl get nodes   # sanity — works identically in all modes
```

> **Web/cloud sessions run each Bash call in a fresh shell — exported env does NOT
> persist between commands.** connect.sh handles this: it installs the winning
> kubeconfig as `~/.kube/config` (kubeconfig modes) or the SSH wrapper as
> `/usr/local/bin/kubectl` / `~/.local/bin/kubectl` (SSH mode) when those spots are
> free, so **bare `kubectl` keeps working in later commands with no eval**. It never
> overwrites an existing file. If it logged no "installed …" line, fall back to
> prepending the printed `export …` line to each command. If kubectl starts failing
> with `connection refused` / `localhost:8080`, re-run the full eval once.

## Access failures are REPORT-ONLY — never fix the access path

If the connect script fails, SSH errors out, the API times out, or kubectl itself
is broken, **stop and tell the user exactly what failed** (verbatim error + what to
check). Do NOT attempt to repair access yourself. Concretely, never:

- edit firewall rules, terraform, or sshd/node config to regain access
- regenerate or bypass `scripts/known_hosts` (a mismatch can mean rebuild — or MITM)
- hunt for/derive alternative credentials, keys, or kubeconfigs
- retry in a loop hoping it recovers

The user may be on a phone with no other path to the cluster — a wrong "fix" locks
them out or worse. Report and wait. (Once access WORKS and the cluster itself is
sick, the normal fix policy below applies.)

If access works but a single probe fails (e.g. metrics-server down breaks
`kubectl top`), note it as a finding, skip it, and finish the rest of the sweep.

## 2. Sweep

Run every check in [SWEEP.md](SWEEP.md) — all of them, don't stop at the first hit.

## 3. Diagnose

For each finding: `kubectl describe` + `kubectl logs --previous` + recent events.
Check the **known failure modes** table in [REFERENCE.md](REFERENCE.md) first — most
incidents on this cluster are recurrences. Runbooks live in `docs/`.

## 4. Fix policy

**Auto-apply (safe, no confirmation):**
- Delete crashlooping / stuck / Evicted pods (controller recreates them)
- `kubectl rollout restart` deploy/sts/ds
- ArgoCD refresh/hard-refresh/sync of an app
- Uncordon a node that is Ready but cordoned with no active maintenance

**Ask the user first (AskUserQuestion):**
- Node drain, reboot, cordon; anything via SSH on the node itself beyond kubectl
- Deleting/resizing PVCs or Longhorn volumes; any Longhorn salvage/replica ops
- Scaling workloads, editing live resources (`kubectl edit/patch` of config)
- Git commits (config fixes belong in git — propose the diff, ask, then commit to master)
- Anything touching etcd, terraform, or Hetzner resources

Never `kubectl apply` config imperatively — this repo is GitOps; config changes go
through git + ArgoCD. Never re-enable Beyla.

## 5. Verify & report

After each fix re-check the specific symptom AND re-run the alert query — logs and
data flow, not just pod status. Finish with a short report: findings, fixes applied,
what needs the user, what to watch. If the thermal-printer MCP is available (local
sessions), print the summary.
