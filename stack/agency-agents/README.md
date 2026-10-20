# Agency Agents — Stack v1 layer

A pinned, versioned Stack v1 layer that imports the **9 division leads** of the
[`paperclipai/companies`](https://github.com/paperclipai/companies) `agency-agents`
package into the RioLabs AI company as paused, $0-budget agents.

## What this layer does

- Pins the upstream source to a single revision (`stack-v1.lock.yaml`).
- Imports exactly 9 agents — never the template `ceo`/`cmo`, and never the other
  156 non-lead agents (out of scope until a later checkpoint).
- Lands every imported agent **paused**, with **heartbeat timers disabled** and a
  **$0 monthly budget**. The company budget is unchanged.
- Remaps `vp-engineering` to report to our **CTO** (not a second CEO).

## Files

| File | Purpose |
| --- | --- |
| `stack-v1.lock.yaml` | Pinned source revision and import contract. |
| `install.sh` | Dry-run gate, apply, and `vp-engineering` remap. |
| `verify.sh` | Roster, status, budgets, timers, and reporting checks. |
| `README.md` | This document. |

## Source

| Field | Value |
| --- | --- |
| Repo | `paperclipai/companies` |
| Path | `agency-agents` |
| Commit | `514503bf4f0ca88ebf16d5dc648e085d587f268f` |
| Package | 167 agents, 10 divisions, 9 team docs, 0 skills/projects/tasks |

## The 9 imported leads

| Slug | Name | Reports to |
| --- | --- | --- |
| `vp-engineering` | VP of Engineering | CTO (remapped) |
| `creative-director` | Creative Director | CEO |
| `vp-product` | VP of Product | CEO |
| `vp-sales` | VP of Sales | CEO |
| `qa-director` | QA Director | `vp-engineering` |
| `vp-operations` | VP of Operations | CEO |
| `game-dev-director` | Game Development Director | CEO |
| `xr-director` | XR Director | `vp-engineering` |
| `chief-of-staff` | Chief of Staff | CEO |

## Install

The `/api/companies/:companyId/imports/*` routes require an actor whose Paperclip
**role is `ceo`** (or the board); any other agent role is rejected. Run as the
CEO agent (or board) with a short-lived run JWT:

```sh
export PAPERCLIP_API_URL="https://work.riolabs.ai"
export PAPERCLIP_API_KEY="<ceo-agent-run-jwt>"
export PAPERCLIP_COMPANY_ID="<company-id>"
export CTO_AGENT_ID="<cto-agent-id>"

./stack/agency-agents/install.sh
./stack/agency-agents/verify.sh
```

`install.sh` gates before applying: it runs the `--dry-run` preview and refuses
unless there are zero errors, zero unresolved reporting lines, zero replacements,
and exactly 9 `create` plans.

## Rollback

The layer is idempotent and reversible by board action. To undo an applied
import, archive or terminate the 9 imported agents in the Paperclip board
(`/companies/:companyId/agents`) — they are all paused and $0-budget, so no
spend or work runs before that. The company budget, core agents, projects, and
tasks are never modified by this layer.

## Out of scope (Phase 1)

The other 158 template agents, activation, any spend, Postiz/OpenSEO, and the
auto-update routine. No agent starts and no money is spent before the board's
activation checkpoint.
