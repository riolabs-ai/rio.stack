# Providers — capability, config as code, and permission tiers

**Status:** measured 2026-11-07 on this box. Hermes-global scope, not client work.
**Board:** `hermes` (kanban). **Authority:** this file plus `requirements.v1.yaml` R-32…R-35.

## 1. The gap this exists to close

Every provider we use is provisioned to the level of *barely passes a demo*: a default project, a key pasted
into a dashboard, one happy path exercised once by hand. Nothing is versioned, nothing is drift-checked, and
"maximized" is an aspiration rather than a measurement.

Measured composite scores (axes: configured · secured · assured · maximized · verifiable · versionable):

| Provider | Config | Secured | Assured | Maximized | Verifiable | Versionable | Avg |
|---|---|---|---|---|---|---|---|
| GitHub | 8 | 6 | 5 | 5 | 8 | 6 | **6.3** |
| Neon | 7 | 3 | 2 | 4 | 5 | 2 | **3.8** |
| Vercel | 6 | 3 | 2 | 2 | 4 | 2 | **3.2** |
| Resend | 6 | 2 | 2 | 3 | 5 | 1 | **3.2** |

The two weak axes are always the same: **assured** (nothing proves the config is what we think) and
**versionable** (it lives in a dashboard, so it cannot be reviewed, diffed or rolled back).

## 2. Capability matrix — what "maximum integration" means

Every provider gets an entry per channel, with an explicit "use when". A channel with no documented trigger is
not integrated; it is merely installed.

| Channel | Purpose | Use when |
|---|---|---|
| Docs / guides | the provider's own truth | first contact, and any time an API error is ambiguous |
| SDK | typed, in-process integration | application code inside a repo |
| CLI | scriptable ops with the agent's own auth | deploys, env vars, one-shot ops — **preferred for agents** |
| MCP | tool surface with provider-shaped tools | interactive diagnosis where the CLI has no equivalent |
| Raw API | anything the SDK/CLI/MCP does not expose | gaps, and reconcilers that must assert exact state |
| Skill | the *when* and the guardrails | every channel above that an agent is allowed to use |
| Examples | proven calls with real arguments | copied into a workflow, never invented |

Rule of thumb measured the hard way: **CLI beats MCP for agents** wherever both exist (MCP OAuth needs a
browser once; a CLI is already authenticated and costs no tool schema), and **MCP beats CLI** only for
provider-shaped read tools where hand-rolled curl would be guesswork.

## 3. Permission tiers

| Tier | Meaning | Default for | Evidence required |
|---|---|---|---|
| **T0 read-only** | list, describe, inspect | every agent, every provider | none |
| **T1 scoped write** | test/sandbox or non-production scopes | a card that names the scope | command output showing the target scope |
| **T2 production write** | money, email to real users, production data, deploys | **owner-gated, per assignment** | explicit grant recorded on the card + the action logged |

Read-only is the default *without special assignment*. T2 is never implied by a role, an MCP connection, or a
CLI already being authenticated.

## 4. What "done" per provider looks like

```
stack/providers/<provider>/
  README.md       the capability matrix entry + permission tier + links to provider docs
  desired.yaml    the config we want, versioned, secret-free (values are ${REF}s, never literals)
  apply.py        idempotent reconciler: diff -> apply -> settle -> re-read
  verify.py       postcondition assertions over the live API; exit 1 on drift
  STATUS.md       generated: current state, tier, last verified, drift
```

`apply.py` and `verify.py` are different files on purpose: **apply asserts by exit status, verify asserts by
re-reading the collection it changed.** R-29 in `requirements.v1.yaml` exists because exit 0 lied to us four
times in one afternoon.

## 5. Non-negotiables

1. **One owner, one home per secret** (R-28). No value exists in two places, and no secret is copied into a
   repo `.env` and a profile `.env` at once.
2. **A spawned process never sees a secret** — measured on two profiles: a tool-spawned shell carries ~148 env
   vars and zero credentials. Capability must be handed as commands (`withenv.sh`, `bws`, CLI), never assumed.
3. **Verification is two-transport.** A check that reads back through the same path that wrote it proves
   nothing; `proj_sync.py` and `issue_card_sync.py` both cross-check for this reason.
4. **A check that cannot fail is not a check.** Every gate ships with a phantom negative control.
5. **Nothing production-facing runs without a tier and a grant.** If the tier is unknown, it is T2.

## 6. Open questions

- Which profile owns provider reconcilers? Candidates: `infra` (fleet tooling) vs a new `providers` bot.
- Per-org BWS account layout (rio.stack #8) decides where T2 keys live.
- Stripe stays disabled until a restricted, test-mode key exists; production currently carries
  `STRIPE_TEST_*`, i.e. billing is not live — that is a decision, not an oversight.
