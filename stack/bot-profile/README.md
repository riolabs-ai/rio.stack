# Hermes Bot & Profile template — v1

An importable, batteries-included Hermes **bot + profile** that runs a project team on **native
Hermes Kanban**: it plans, routes work to specialist bots, holds the gate, and reports the decision.

This layer is deliberately boring and complete. Everything in it is a fact about how Hermes actually
behaves — measured on a live install, not aspirational. Where a value is a placeholder it is written
`{{LIKE_THIS}}` and `verify.sh` fails if one survives into a resolved profile without being replaced.

## What you get

| Battery | Where | Why it is in the box |
| --- | --- | --- |
| Persona + one job | `bot/botforge-template.json` (`soul_md`) | a bot with two jobs routes badly |
| Toolset ceiling | `bot/botforge-template.json` (`toolsets`) | kanban routing + delegation + files + shell; nothing decorative |
| Starter memory | `bot/botforge-template.json` (`memory`) | the five facts that stop a new lead re-learning them the hard way |
| One routine | `bot/botforge-template.json` (`routines`) | a daily board triage that reports only what changed |
| Profile config | `profile/config.yaml` | kanban ceilings, approvals, memory, toolsets — the wiring a persona cannot carry |
| Doctrine | `profile/SOUL.md` | the lead's operating rules, written as rules with a record |
| Kanban conventions | `docs/kanban-conventions.md` | card shapes, completion contracts, workspace and block discipline |
| Env template | `profile/.env.example` | names only. **Never a value.** |
| Checks | `verify.sh` | parses every file, refuses secrets, refuses un-replaced placeholders |

## What it deliberately does not include

- **Credentials.** No key, token or URL with a secret. `.env.example` carries names and comments.
- **Chat history or the exporter's memory.** A shared template never carries a person's facts.
- **Client or personal specifics.** Names of companies, people, repos and paths are placeholders.
- **Plugins.** `plugins.enabled: []`. A template that ships plugins breaks on an install that has
  none, and one plugin class (`hermes-project-stewardship`) may only be enabled in one profile per
  install — a duplicate is a hard dependency failure, not a warning.

## Install

Two paths, same result. Pick by whether you want the bot's persona or a profile you keep.

### A. Import the bot (recommended — one command path)

```bash
# from a Hermes session, with the bot-forge plugin available
import_agent path=stack/bot-profile/bot/botforge-template.json display_name="<Name>"
```

`import_agent` builds the profile fresh, scans the template for secrets, and opens the bot's chat with
its own introduction. Read the template's `soul_md` and `routines` before importing someone else's —
they are the bot's instructions and it will follow them.

### B. Merge the profile config into an existing profile

```bash
bash stack/bot-profile/install.sh --profile <profile>          # dry run: prints the merge
bash stack/bot-profile/install.sh --profile <profile> --apply  # writes it
```

`install.sh` never overwrites a value that is already set: it prints a per-key decision
(`set` / `keep` / `conflict`) and stops on `conflict` unless `--force`. Kanban ceilings are the one
place a stale value is dangerous, so they are reported in full.

## The one thing to know before you change a ceiling

`kanban.max_spawn` is the real concurrency ceiling and it is read **at boot**. Changing it in
`config.yaml` while the gateway is running changes nothing until the next start — the dispatcher logs
`kanban dispatcher: max_spawn=N` on every boot, and that line, not the file, is the truth:

```bash
grep "kanban dispatcher: max_spawn" ~/.hermes/logs/gateway.log | tail -1
```

`max_in_progress` and `max_in_progress_per_profile` are checked after `max_spawn` and cannot raise it.

## Verify

```bash
bash stack/bot-profile/verify.sh          # parses, scans, and checks the contracts
bash stack/bot-profile/verify.sh --strict # also refuses any un-replaced {{PLACEHOLDER}}
```

A layer that cannot pass its own `verify.sh` is not a template, it is a wish.
