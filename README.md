# rio.stack

**Agentic Relationship Information Orchestration** — the pinned stack the RioLabs AI Hermes
bots run on.

Hermes · Project Stewardship · Obsidian · Paperclip — Agentic Organization Mission Control.

One directory per layer under `stack/`. This is also the checkout Paperclip projects branch
from, so `main` must always keep at least one commit: an empty repository has no valid
`HEAD`, and every task run fails at setup with `fatal: invalid reference: HEAD`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/riolabs-ai/rio.stack/main/install.sh | sh
```

Creates `~/.rio/` (pinned stack checkout, `config.yaml`, `bin/rioctl`) and prints a PATH
hint. It does not edit shell rc unless you pass `--write`. Preview with
`sh install.sh --dry-run`. Then, in a project: `rioctl init` (preview) or
`rioctl init --write`. See [`stack/rio-cli/`](stack/rio-cli/).

## Layout

- `stack/` — the pinned, versioned stack layers listed below.
- `install.sh`, `bin/rioctl`, `skills/rioctl/` — the user-level installer and CLI (see rio-cli).
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
| [`stack/rio-cli/`](stack/rio-cli/) | **rioctl v1** — `install.sh` + `rioctl` (init, status, sync, promote, doctor). User home `~/.rio/`, project `.rio/` + `rio.project.yaml`. Thin agent skill at `skills/rioctl/`. `rio` remains the Hermes profile launcher. | `bash stack/rio-cli/verify.sh` |
| [`stack/agency-agents/`](stack/agency-agents/) | Pinned import of the 9 `paperclipai/companies` division leads as paused, $0-budget agents. | `bash stack/agency-agents/verify.sh` |

Layers that ship software (`bot-profile`, `agency-agents`, `github-template`, `mission-control`, `rio-cli`) follow the same contract: a
`*-lock.yaml` that pins what it resolves to, and a `verify.sh` that must pass before the layer is considered shippable. Layer `install.sh` scripts are dry-run by default; the repo-root `install.sh` (the curl | sh entrypoint) writes `~/.rio/` by default and previews with `--dry-run`. `foundation` carries the
requirements plus its own `verify.sh`; `github-specops` and `providers` are docs-and-tools
layers with no installer.
