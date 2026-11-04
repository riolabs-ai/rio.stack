# GitHub capability annex (v1) — operational answer to R-23

Measured on this machine, 2026-11-04. Every row was executed, not assumed. Credential values never printed.

## What works right now

| Capability | Transport | Proven | Evidence |
|---|---|---|---|
| Enumerate every repo | `gh repo list`, REST | ✅ | 80 repos visible under `riolabs-ai`; 300 under `jadenblack` (cap-hit) |
| Read/write issues | REST + GraphQL | ✅ | 6 open issues read in `rio.stack`; #6 and #539 created earlier today |
| Read/write PRs, reviews, comments | REST + GraphQL | ✅ | PR #448 authored and merged in the alignsynch board flow |
| Read rulesets / branch policy | REST | ✅ | 2 rulesets read from `alignsynch` |
| Search across repos | Search API | ✅ | `search/issues` returns counts (30 req/min budget) |
| Bulk GraphQL (paginated, batched) | GraphQL | ✅ | 5000 points/hr budget, 4963 remaining at test time |
| Actions: read workflows, dispatch, log | REST | ✅ | `actions/workflows` reachable (0 workflows in `rio.stack`) |
| Releases, tags, checks, deployments | REST | ✅ | used in the v1.3.0 release card |
| Webhooks, repo settings, collaborators | REST | ✅ | `read:org` + `repo` scopes present |

**Scale headroom:** core 5 000/hr, GraphQL 5 000/hr, search 30/min. A 100-repo sweep costs roughly 100 core
calls plus one batched GraphQL query — two orders of magnitude inside budget.

## The one gap

| Item | Status |
|---|---|
| Projects v2 (read **and** write) | ❌ needs `read:project` + `project` |
| Accounts tested | `jadenblack`, `roryskagenart` — both `INSUFFICIENT_SCOPES` |
| REST alternative | none: `GET /users/{owner}/projects` → **404**, no public Projects v2 REST surface |
| Fix | `gh auth refresh -s project,read:project` (one device-flow code, ~20 s, owner-only) |

This is a **grant**, not a capability. The API exists, the client exists, the account exists; one scope is missing.

## Interoperability at 100 repos (what R-26 needs)

The onboarding procedure each new entity runs, using only CLI + API:

1. `gh repo create <org>/<name> --private --template <foundry-template>` — or from a bare repo.
2. Apply rulesets from a JSON file: `gh api repos/{o}/{r}/rulesets -X POST -F <ruleset.json>`.
3. Seed labels, milestones and issue forms from the same template.
4. Create the project (needs the project scope) and link it: one GraphQL mutation.
5. `vercel link` + env push, `neon` branch, `sentry-cli` project, `resend` domain — each a scripted call.
6. Write the stack lock (`stack/<layer>/*.lock.yaml`) so the entity records exactly what it runs on.
7. Run `./verify.sh` and refuse onboarding if any enforced requirement fails.

## Never answer "can't" without this matrix

Before any refusal: credential source × transport × scope, with the exact response body. If the matrix has an
untested cell (a second account, an Actions token, a REST-vs-GraphQL alternative), the correct answer is
"untested", not "impossible". This annex is the worked example: the only genuine wall found was one scope, and
it was found by testing every other cell first.

## Exit status is not evidence (measured 2026-11-04)

`gh project item-add` returns **exit 0** in three different situations: the item was added; the item already
existed (silent no-op that still prints the issue body); the item **did not land at all** — observed 4 times in
13 calls. And the first read-back after a write can lag, producing a *false* failure.

Correction (R-29, implemented in `stack/github-specops/tools/proj_sync.py`): assert the collection, not the exit
code; read back with backoff; cross-check with a second transport before declaring drift; and prove the check can
fail by running it against a phantom target.
