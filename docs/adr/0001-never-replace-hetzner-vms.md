# 0001 — Never replace Hetzner VMs

Date: 2026-05-22
Status: **Superseded by [ADR-0002](0002-capacity-aware-cluster-resets.md)** (2026-05-23)

## Context

The cluster runs on five Hetzner Cloud servers in `fsn1`, `nbg1`, `hel1`.
These locations have repeatedly hit capacity exhaustion: a destroyed VM
of the configured server type may not be replaceable for an unpredictable
amount of time. In the worst case, losing a VM bricks the cluster
indefinitely because we cannot get a replacement.

## Decision (superseded)

VMs were to be treated as immortal: protected at the Hetzner API level
with delete-protection, reset via in-place `hcloud server rebuild` rather
than recreate, and module upgrades reviewed line-by-line for any forced
replacement.

## Why superseded

While preparing to execute the in-place reset, we re-verified Hetzner
capacity and confirmed cx23 and cx33 were in stock across all three
DCs. We switched to a fresh destroy+apply strategy and rebuilt the
cluster from scratch on a simpler topology (3× cx33). The constraint
is real but **conditional on current Hetzner stock**, not always-on, so
the rule is reframed in [[0002-capacity-aware-cluster-resets]].

The kept lesson: **always check current stock before initiating a
destroy**, and have an in-place rebuild fallback documented if stock is
absent. The rebuild runbook lives at
`docs/cluster-reset-runbook.md` (kept as reference for any future reset
that has to happen during a capacity outage).
