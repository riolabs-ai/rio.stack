# Design record — the five decisions this layer implements

The layer exists because a Hermes fleet accumulated config by copying and drifting. The evidence
inventory (`specs/hermes-remake-brief.md`) measured seven defect classes on one host; the owner took
five decisions on 2026-11-22. This layer is those decisions as data, plus the mechanisms that keep
them true. A proposal that contradicts one of them needs a new decision, not a quiet exception.

## E1 — Identity: one name per thing

**Decision.** The chat identity is the profile name. A bot's display name equals its profile name, and
every registry (dispatch list, card assignee, cron delivery target, gateway route) names a profile
that exists.

**What the layer does.** `identity.root` declares the one exception, with its reason: the installation
root's id cannot be renamed, and `hermes` is a reserved name in core, so the root's display name and
its id cannot be reconciled. The layer records that as a declared exception rather than pretending it
away, and every other profile's charter renders its own name as its display name.

**Why it is not cosmetic.** The 8.5-hour silent skip happened because two name registries disagreed
after a rename: dispatch matched a card's assignee against *existing* profile names, and a mismatch
produced `skipped_nonspawnable` with no owner-visible alarm. A name that means two things is a bug
that only shows up as missing work.

**Cost.** A rename is now an atomic operation that must rewrite boards and config references. The
layer can only state the target; the rewrite stays a gated migration action.

## E2 — Secrets: no secret store in a worker's environment

**Decision.** Bitwarden sync lives only on the dedicated release profile, with `override_existing`
and an allowlist. No worker profile carries repo runtime config (`DATABASE_URL` and friends) in its
environment.

**What the layer does.** `secrets.bitwarden` declares the sync profile, the refusal list and the
canary. The mechanism is a default-deny allowlist in front of materialisation: a row named
`DATABASE_URL` is refused by name, not merely absent from today's vault. The layer renders only
references, and every `secrets.*` key is refused on write except the boolean that says whether a
profile syncs at all.

**Why absence is not a guarantee.** "Absent" is a snapshot of one vault on one day. A refusal is a
rule: the next row someone adds is still refused. The layer checks the rule, not the snapshot.

**Cost.** A profile that needs a secret now needs an explicit tool call or the release profile's
environment. That is the point — the secret stops being ambient.

## E3 — Merge and release rights: a profile whose job is merging

**Decision.** A dedicated release profile holds allow-listed `gh pr merge` and `release:cut`, so a
merge card can be closed by its assignee. Agents never merge outside it.

**What the layer does.** `merge_capable` marks exactly which profiles hold the verb, and the checker
fails if a non-merge-capable profile is missing its deny rule. `verbs:` owns the globs so the
invariant is stated in verbs, not in command strings that drift per profile.

**What it cannot fix.** A *tag* is still not a card outcome. `release:cut` refuses in a worker
(`HERMES_KANBAN_TASK` is set), so a tag card is assigned to a human and says so in its body. The layer
records that bound in `verification.tag_is_not_a_card_outcome` rather than pretending a card can cut a
tag.

**Cost.** Every merge goes through one profile. That is a bottleneck by design: it is the only way a
card's outcome is also its assignee's capability.

## E4 — Completion verification: measure what is measurable

**Decision.** Verify on PR state, tests and CI on the exact head. Do not read branch-protection rules:
the endpoint is identity- and plan-fragile and proved unclosable on a private free-plan repo.

**What the layer does.** `verification.contract` lists the three sources; `rules_read: not_a_failure`
states the fallback and its reason. The checker refuses a contract that names a rules endpoint.

**Why the fallback is the decision.** A verification policy with no fallback turns an unavailable
source into a failed card. A technically correct card then fails for a reason the worker cannot fix,
and the board learns to ignore verification — which is worse than not verifying.

**Cost.** A merge that bypasses branch protection is no longer caught by the contract. The layer
accepts that: PR state plus CI on the exact head is a real measurement, and a 403 is not a failure.

## E5 — Model policy: one policy, restated complete

**Decision.** One model policy at the root — flash/low for conversation, v4-pro/max for deep — with a
per-profile override only where the provider genuinely differs (rory/openrouter, blueberry-rio/dahl).

**What the layer does.** `model_policy` is the single source; `routes` declares every conversational
route; `exempt` names the genuine provider differences; `policy_keys` are the keys that must match.
The checker fails a profile that restates a root key with a different value, or omits one.

**Why "inherited" is impossible.** Hermes has no config inheritance. A profile that omits a key
resolves the shipped default, not the root's. So "one policy inherited by all profiles" cannot be
spelled by deleting keys — the only shape that exists is *one source, complete derived copies, drift
refused*. The layer states that plainly in invariant 6 instead of implying inheritance that does not
happen.

**What about `model_map`?** A map is a plugin-level structure, not a core config key, and it is inert
unless a backend selects it. So "one map at the root" has no behavioural meaning; the defect class is
a *second definition*. The checker refuses a second definer.

**Cost.** A model change is one edit plus a re-render, and a profile that genuinely needs a different
model needs a declared exemption. That is the trade: no silent per-profile drift, at the price of an
explicit declaration when a difference is real.

## What this layer does not decide

- Which profiles exist on a given host. The layer declares the resolved fleet; a host's migration to
  it is a separate, gated action.
- What a client's repo does. `release:cut` semantics are a client-repo rule.
- The owner's name choice for the root identity. E1's disposition is his; the layer records the state
  and the reason, and `verify.sh --host` reports the split as drift until he decides.
