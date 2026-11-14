# Hermes Bot & Profile template — v1

An importable, batteries-included Hermes **bot + profile** that runs a project team on **native
Hermes Kanban**: it plans, routes work to specialist bots, holds the gate, and reports the decision.

This layer is deliberately boring and complete. Everything in it is a fact about how Hermes actually
behaves — measured on a live install, not aspirational. Where a value is a placeholder it is written
`{{LIKE_THIS}}` and `verify.sh` fails if one survives into a resolved profile without being replaced.

## What you get

| Battery | Where | Why it is in the box |
| --- | --- | --- |
| Persona + one job | `profile/SOUL.md` — the only copy | a bot with two jobs routes badly |
| Persona reference | `bot/botforge-template.json` (`soul_md_ref`) | the bot half points at the one persona instead of carrying a second copy that drifts |
| Renderer | `render-bot.sh` | inlines the persona into an import-ready template; a bare template file would import a generic one |
| Toolset ceiling | `bot/botforge-template.json` (`toolsets`) | kanban routing + delegation + files + shell; nothing decorative |
| Starter memory | `bot/botforge-template.json` (`memory`) | the five facts that stop a new lead re-learning them the hard way |
| One routine | `bot/botforge-template.json` (`routines`) | a daily board triage that reports only what changed |
| Profile config | `profile/config.yaml` | kanban ceilings, approvals, memory, toolsets — the wiring a persona cannot carry |
| Doctrine | `profile/SOUL.md` | the lead's operating rules, written as rules with a record — one source, asserted as a whole document |
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

Three paths, three audiences. Pick the first row that describes you; they do not stack.

| You want | Use | What it does |
| --- | --- | --- |
| **A new profile** | `hermes profile install stack/bot-profile/profile` | Hermes creates the profile home from `profile/distribution.yaml`, applies `config.yaml` and `SOUL.md`, and records what the distribution owns so `update` can refresh it |
| **An existing profile** | `bash stack/bot-profile/install.sh --profile <profile>` | Merges the same `config.yaml` into a profile you already have, one key at a time |
| **Just the persona + routines** | `import_agent path=stack/bot-profile/bot/botforge-template.json` | Bot half only — no `kanban.*` keys, so it composes with either of the above |

### A. A new profile — the native path

```bash
hermes profile install stack/bot-profile/profile              # --name to override, --force to replace
hermes profile update bot-profile                             # later: re-pull, user data preserved
```

`profile/` is a distribution root: `distribution.yaml` sits beside the files it owns. Hermes owns
`SOUL.md` and `config.yaml` and refreshes them on `update`; everything else in the profile home is
treated as user data. **The manifest carries names only, never values** — it reports which env vars
are missing (`DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `GH_TOKEN`, `BWS_ACCESS_TOKEN`,
`BWS_PROJECT_ID`) and you supply them.

Two constraints worth knowing before you start:

- **A git-URL install is impossible while this repository stays private.** `hermes profile install`
  accepts a git URL, but it needs a credential for a private remote; until then, install from a local
  checkout — `stack/bot-profile/profile` is the distribution root, not the layer root.
- **A distribution has no substitution step**, so `kanban.orchestrator_profile`,
  `kanban.default_assignee` and `kanban.dispatch_profiles` are *not* in `config.yaml`. Set them once
  after install; the commands are in the file's own comment, and an unset `dispatch_profiles` claims
  no cards at all, which is the safe failure.

### B. Merge into an existing profile

```bash
bash stack/bot-profile/install.sh --profile <profile>          # dry run: prints the merge
bash stack/bot-profile/install.sh --profile <profile> --apply  # writes it
```

`install.sh` never overwrites a value that is already set: it prints a per-key decision
(`set` / `keep` / `conflict`) and stops on `conflict` unless `--force`. Kanban ceilings are the one
place a stale value is dangerous, so they are reported in full. `--apply` also refuses while a
`{{PLACEHOLDER}}` survives in a file it would write — a bot that introduces itself as `{{BOT_NAME}}` is
worse than a dry run; `--allow-placeholders` overrides, and says so. This is the path for a live
profile — `hermes profile update --force-config` would clobber it instead of merging.

### C. Persona only

```bash
bash stack/bot-profile/render-bot.sh > /tmp/lead.botforge.json
import_agent path=/tmp/lead.botforge.json display_name="<Name>"
```

`import_agent` builds the profile fresh, scans the template for secrets, and opens the bot's chat with
its own introduction. Read the persona (`profile/SOUL.md`) and the routines before importing someone
else's — they are the bot's instructions and it will follow them.

**Render first, never import the bare template file.** `bot-forge` falls back to `render_soul()` when
`soul_md` is absent, which produces a generic persona and reports no error at all. `render-bot.sh`
inlines `profile/SOUL.md` byte-for-byte, so the bot you import is the one written here.

## The persona has exactly one source

`profile/SOUL.md` is it. The bot template carries `soul_md_ref: ../profile/SOUL.md` and no body, so
there is no second copy that can drift; `verify.sh` fails if either half grows one back. Import is a
render step, not a file you hand-edit.

The whole document is pinned: `template-v1.lock.yaml` carries `sha256` of `profile/SOUL.md`, and the
verifier compares the file against it byte-for-byte. Editing the persona is expected — but edit and
re-pin in the same commit, or `verify.sh` fails on whichever line you touched (line 60 as surely as
line 1). That is the point of the pin: a persona change is a deliberate change, never a silent one.


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

What `verify.sh` actually asserts, beyond "the files parse":

- **The persona, as a whole document.** `render-bot.sh` must resolve `soul_md_ref` to
  `profile/SOUL.md`; the rendered `soul_md` must equal the file byte-for-byte; the body must exist in
  exactly one file; and its `sha256` must match the pin. Any edited line fails, not just line 1.
- **The lock is enforced, not decorative.** A wrong toolset or routine count, a stale `one_job`, a
  bogus key in `pinned.profile.keys`, a config key the lock does not name, or a distribution version
  that disagrees with the lock is a FAIL.
- **No secrets and no machine specifics** — shapes only, so a real key cannot slip in with a template.

A layer that cannot pass its own `verify.sh` is not a template, it is a wish.
