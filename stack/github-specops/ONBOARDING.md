# GitHub SpecialOps — onboarding pack

What RioLabs hands over, what the agent can do with it, and what it will refuse to do without.

## 1. The five manifests (pick one per run)

| Manifest | Blast radius | Grants needed | Typical run |
|---|---|---|---|
| `repo-custodian` | read-only, then PR batch | `repo`, `security_events`, `workflow` (read) | 100 repos, ~200 calls, one fleet report |
| `pr-machine` | PR batch | `repo` (write), `workflow` (read) | every open PR triaged, blockers quoted |
| `release-ops` | mutation | `repo` (write), `workflow` (read) | draft release + cited notes + rollback |
| `ruleset-gauntlet` | read-only | `repo` admin read, `read:org` | drift table, one issue per blocker |
| `foundry-onboarding` | mutation | `repo` admin, `workflow`, `project`, service tokens | new entity live + locked + verified |

## 2. Grants — what exists today

| Scope | State on this machine |
|---|---|
| `repo` | ✅ present |
| `workflow` | ✅ present |
| `read:org` | ✅ present |
| `project`, `read:project` | ❌ missing on both accounts → one command: `gh auth refresh -s project,read:project` |
| `read:packages`, `admin:org` | ⛔ not needed for the five manifests as written |

Without the project scopes: manifests 1–4 run fully; manifest 5 completes steps 1, 2, 4–7 and fails **only** on
the board link, with the exact 403 quoted.

## 3. The deets to hand over (intake)

```
owner/org:            e.g. riolabs-ai
repos:               <explicit list>  or  "all private in riolabs-ai" (agent runs discovery first)
manifest:            repo-custodian | pr-machine | release-ops | ruleset-gauntlet | foundry-onboarding
blast radius:        read-only  |  proposed PR batch  |  direct mutation
acceptance:          what "done" looks like for this run, in one sentence
result lands in:     issue  |  PR  |  project item  |  doc in repo
```

## 4. What it will not do

Delete a repo, release, ruleset or default branch — without an explicit "yes, delete <name>" in the session.
Force-push, rewrite published history, weaken a ruleset, print a secret, or claim a check passed that it did not
watch run.

## 5. "Hire a 25-year GitHub OG" — what is actually possible

Hermes has no hiring; it has four composable parts, and a person-shaped agent is exactly those four:

| Part | Command / file | What it buys |
|---|---|---|
| Profile | `hermes profile create specops` | an isolated identity: config, credentials, memory, board |
| Persona | `profiles/specops/SOUL.md` | the veteran's *practice*: what they check first, what they refuse |
| Capability | toolsets + `gh` + `gh api` + MCP | the actual work, at fleet scale |
| Procedure | the five manifests | repeatable runs with HIL gates and acceptance |

What cannot be bought: 25 years of judgment. What can be encoded is the *output* of that judgment — the
checklist order, the refusals, the evidence standard. That is why the persona here says "cite the command, never
claim experience": a fabricated résumé is the one thing an operator-grade agent must not have.
