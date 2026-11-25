# rio.stack

**Agentic Relationship Information Orchestration** — the pinned stack the RioLabs AI Hermes
bots run on.

Hermes · Project Stewardship · Obsidian · Paperclip — Agentic Organization Mission Control.

One directory per layer under `stack/`. This is also the checkout Paperclip projects branch
from, so `main` must always keep at least one commit: an empty repository has no valid
`HEAD`, and every task run fails at setup with `fatal: invalid reference: HEAD`.

## Layout

- `stack/` — the pinned, versioned stack layers listed below.
- `IDEA.md` — intake: needs, ideas and fixes dumped here before they become issues or
  layers. Not documentation; see the layers for what is actually true.

## Stack layers

| Layer | What it is | Verify |
| --- | --- | --- |
| [`stack/foundation/`](stack/foundation/) | The guarantees the stack must hold *before* any plugin, profile or tool is admitted — adversarially derived, each carrying the failure that produced it. | `bash stack/foundation/verify.sh` |
| [`stack/bot-profile/`](stack/bot-profile/) | **Bot & Profile template v1** — an importable, batteries-included Hermes bot (persona, toolset ceiling, starter memory, one routine) plus the profile config that makes it run a project team on native Kanban. No secrets, no chat history, no client specifics. | `bash stack/bot-profile/verify.sh` |
| [`stack/github-specops/`](stack/github-specops/) | The `specops` profile: a shell-first, evidence-led GitHub operator — persona, capability, five repeatable manifests with HIL gates. | docs + `tools/` (no `verify.sh` yet) |
| [`stack/github-template/`](stack/github-template/) | **GitHub template v1** — the `.github` base standard for any account or org: profile page, community health defaults, issue/PR forms, starter CI, labels. Placeholders + `render.sh`; first consumer `jadenblack`. | `bash stack/github-template/verify.sh` |
| [`stack/providers/`](stack/providers/) | Provider capability matrix, config as code, and permission tiers (R-32…R-35). | docs only |
| [`stack/mission-control/`](stack/mission-control/) | **Mission control v1** — the registry of every Rio project, the `rio.project.yaml` manifest each project carries, and the promote-up / trickle-down loop that keeps them on the stack. Read-only `status.sh`. | `bash stack/mission-control/verify.sh` |
| [`stack/agency-agents/`](stack/agency-agents/) | Pinned import of the 9 `paperclipai/companies` division leads as paused, $0-budget agents. | `bash stack/agency-agents/verify.sh` |

Layers that ship software (`bot-profile`, `agency-agents`, `github-template`, `mission-control`) follow the same contract: a
`*-lock.yaml` that pins what it resolves to, an `install.sh` that is dry-run by default, and a
`verify.sh` that must pass before the layer is considered shippable. `foundation` carries the
requirements plus its own `verify.sh`; `github-specops` and `providers` are docs-and-tools
layers with no installer.

## Checks

`.github/workflows/verify.yml` runs on pull requests, on pushes to `main`, and on `workflow_dispatch`.

The layers job runs every `stack/*/verify.sh`. `stack/foundation/verify.sh` and `stack/agency-agents/verify.sh` are skipped (they need a Hermes install and Paperclip credentials) and named in the job summary. A new layer is checked unless it is added to that skip list.

The lint job runs `shellcheck --severity=error` on tracked `*.sh` files and `actionlint` on `.github/workflows`.

Locally, from the repository root (`python3` with PyYAML, `shellcheck`, `actionlint`):

```bash
bash stack/github-template/verify.sh
bash stack/mission-control/verify.sh
bash stack/bot-profile/verify.sh
git ls-files '*.sh' | xargs -r shellcheck --severity=error
actionlint .github/workflows/*.yml
```
