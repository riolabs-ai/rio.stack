# Adversarial register v1

The requirements layer is only worth what survives attack. This file attacks the **set**, not just the members.
Each attack is scored: `answerable` (the set already answers it), `accepted` (a real weakness, recorded, not fixed),
or `rejected` (the attack is wrong, and why).

## Attack 1 — "These are one machine's war stories, dressed as principles" · **partially accepted**

Every one of the 22 requirements cites an observed failure, and all observations come from a single Hermes
install worked by two agents over roughly a week. That is a bias toward *this* stack's failure modes: restart
handling, worktree hygiene, and completion honesty are over-represented; multi-user, networked and
multi-tenant failures are absent entirely.

*Mitigation:* the citation requirement is kept deliberately. A requirement with no failure behind it is a
preference, and preferences should not gate admission. The bias is stated rather than hidden, and R-01/R-04/R-21
are the three that will need rewriting first for a multi-user install.

## Attack 2 — "A verifier that checks 6 of 22 requirements is theatre" · **accepted**

`verify.sh` enforces R-03, R-05, R-06, R-12, R-17, R-18. The other sixteen are marked manual and printed on
every run so they cannot quietly disappear — but printing a list is not checking it. The honest reading: this
layer is currently **27% mechanical**, and the seven `unmet` verdicts are mostly in the manual half, which is
exactly where verdicts are cheapest to assert.

*Mitigation:* every future requirement must ship with a check or be born `unverified`. The manual list is a
debt ledger, not a feature.

## Attack 3 — "Verdicts are self-assessed by the agent that owns the failing system" · **accepted**

`hermes` graded requirements about `hermes`. Seven are honestly marked unmet, which is some evidence against
grade inflation, but the grader is still the defendant. R-19 in particular ("a guard never overrides a session it
cannot observe") was marked `partial` by the same agent whose plugin fired the false positive.

*Mitigation:* verdicts are claims under R-16 and need a reproducing command. Where none exists, the verdict
should read `unverified`, and three should be downgraded on the next pass.

## Attack 4 — "R-14/R-15 (output) are style, not foundation" · **rejected**

They cite a measured failure: replies at roughly five times the reader's capacity, with decisions buried in
narration. Attention is the scarcest resource in the system, and a stack that produces unreadable output has
failed regardless of its uptime. Style preferences would not have a failure citation; these do.

## Attack 5 — "R-09/R-10/R-11/R-13 are upstream bugs, not requirements you can hold" · **rejected, with a caveat**

A requirement is a property the *stack* must have, not a property one component must provide. If the harness
cannot stop a blocked card's worker, the stack must compensate (kill the pid, refuse the card, park the branch) —
the requirement stands and the compensation is the design work. The caveat: until those compensations exist,
those four requirements carry unfunded work, and their `unmet` verdicts are load-bearing.

## Attack 6 — "Admission rules kill exploration" · **answerable**

The rule is not "no new plugins"; it is "new plugins enter through a scratch profile and are admitted on
evidence." Exploration stays cheap; only promotion is gated. What it does forbid is the pattern actually
observed: 24 plugins accumulated with three competing board UIs and two memory backends, none mapped to a need.

## Attack 7 — "The set has no cost model, so 'foundation' is unbounded" · **accepted**

There is no requirement about money, so nothing constrains the eventual stack from being correct and
unaffordable: per-profile provider keys, one secrets project per profile, one board per client. Cost is a
foundation property because it decides whether the stack survives contact with a budget.

*Mitigation:* R-23 (cost ceiling per profile) and R-24 (single owner per credential class) are the first
additions, and they are marked `unverified` until a real monthly figure exists.

## What would falsify this whole layer

1. A stack built on these 22 requirements that still loses work on restart → R-11/R-12 are mis-specified.
2. A plugin passing admission that turns out unused after 30 days → the admission rule is too permissive.
3. A `met` verdict that fails on a second machine → the verdicts measure this install, not the stack.

## Falsification schedule

| When | What |
|---|---|
| Every PR to this layer | `./verify.sh` must run; new requirements ship with a check |
| Weekly | re-read the manual list; downgrade any verdict without a reproducing command |
| On any new failure | the failure gets a requirement or an existing one is corrected — never left in chat |
