# 0002 — Capacity-aware cluster resets

Date: 2026-05-23
Status: Accepted

## Context

The cluster runs on Hetzner Cloud in `fsn1`/`nbg1`/`hel1`. Those locations
periodically run out of stock for specific server types (most recently
cx43, which was unobtainable in all three DCs for 2–6 days). When stock
is absent, a destroyed VM cannot be recreated until restock — a window
of unknown duration.

When working with capacity-constrained server types, a `terraform destroy`
or any TF action that triggers `destroy → create` on a VM is potentially
unrecoverable. But when the configured server type is in stock, the
constraint doesn't apply: destroy+create is just routine.

We need a rule that adapts to current stock, not a one-size-fits-all
prohibition.

## Decision

The reset strategy is chosen at reset time based on current Hetzner
stock for our server types:

1. **Stock present → fresh destroy+apply.** Standard `terraform destroy`
   then `terraform apply`. Simpler, cheaper to execute, no protection
   dance. Used in 2026-05-23 reset.
2. **Stock absent for our types → in-place rebuild.** `hcloud server
   rebuild --image <microos-snapshot>` per VM (keeps server ID and IPs),
   then `terraform taint` the module's null_resources for k3s install
   and apply. Procedure documented at
   `docs/cluster-reset-runbook.md`.

A pre-reset checklist (in `docs/cluster-reset-runbook.md`) requires
verifying stock for all configured `server_type` × `location`
combinations before choosing the path. A capacity-check via
`hcloud server create --start-after-create=false` (and immediate delete)
is the authoritative test — the Hetzner availability tracker UI lags.

The cluster's configured server types should favor **broadly-available
types** (cx23, cx33) over scarce ones (cx43, cx53). cx43 nodes
remain a longer-term target once they are reliably back in stock.

## Consequences

- Resets are slightly more deliberate: always start with the stock check.
- The rebuild runbook stays useful even though we'd rather not need it.
- Topology choices need to weigh "stock reliability" alongside cost and
  performance. cx23 and cx33 are the safe defaults; cx43 and bigger
  require monitoring availability before adopting.
- Module upgrades still need plan-review for forced VM replacement,
  but the consequence of a forced replace is bounded by current stock,
  not catastrophic by default.
