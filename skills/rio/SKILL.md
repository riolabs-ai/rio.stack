---
name: rio
description: Bootstrap and operate a project against rio.stack. Use when installing the rio CLI, running rio init / status / sync / promote / doctor in a repo, or when a user asks to enroll jadenblack, riolabs-ai, or rio.stack itself.
---

# rio

Do not reimplement install, init, sync, or promote logic. Run the CLI and read its
output. One engine, every agent (Hermes, Cursor, Grok Bot).

## Command

Prefer `rio` on PATH (`$RIO_HOME/bin/rio`, default `~/.rio/bin`). If it is missing,
run the installer from a rio.stack checkout, or:

```bash
curl -fsSL https://raw.githubusercontent.com/riolabs-ai/rio.stack/main/install.sh | sh
```

Follow the PATH hint the installer prints. Do not edit the user's shell rc; tell
them the `export PATH=...` line, or ask before passing `--write` to `install.sh`
(that flag only appends the PATH line to `~/.bashrc`).

Override the home with `RIO_HOME` (used in tests). Never write secrets into
`~/.rio/config.yaml` — it holds identities and provider *references* only.

## Commands

| Command | What it does |
| --- | --- |
| `rio doctor` | Checks git, gh auth, python/pyyaml, the stack checkout, and whether this repo is enrolled. |
| `rio init` | Preview of `.rio/` + root `rio.project.yaml`. Read the printed files. |
| `rio init --write` | Apply the preview. Refuses to overwrite unless `--force`. |
| `rio status` | Wraps `stack/mission-control/status.sh`. Pass `--offline` or `--json` through. |
| `rio sync` | v1 stub: lists layer drift and the trickle-down PR it *would* open (rio.stack#30). Never writes. |
| `rio promote` | v1 stub: prints the promote-up PR it *would* open against riolabs-ai/rio.stack (rio.stack#29). Never opens it. |
| `rio version` / `rio help` | Version and usage. |

Project writes (`init`) are preview-only until `--write`. `sync` and `promote` are
preview-only in v1.

## Rules

- GitHub is the source of truth. Do not merge PRs. Do not invent credentials.
- If `rio init` cannot match the repo in `registry.yaml`, fill `--id`, `--repo`,
  and `--domain` rather than guessing a business domain.
- After `--write`, show the user the paths that were created and stop for review
  before committing, unless they already asked to commit.

## Name collision

On prodesk, `~/.local/bin/rio` already launches the Hermes `rio` profile
(`hermes -p rio`). Do not overwrite that wrapper. Call this CLI as
`$RIO_HOME/bin/rio` or `./bin/rio` until the owner decides whether to rename
the CLI or the wrapper.
