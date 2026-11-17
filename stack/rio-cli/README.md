# rioctl — user + project bootstrap (v1)

**Status:** v1. **Tracking:** [rio.stack#40](https://github.com/riolabs-ai/rio.stack/issues/40).

One engine for installing rio.stack on a machine and enrolling a project in it.
A thin [skill](../../skills/rioctl/SKILL.md) tells any agent to call the CLI and
read the output, instead of reimplementing it.

`rio` is the Hermes rio-profile launcher (`~/.local/bin/rio` on prodesk). This
CLI is `rioctl`. The installer does not touch that wrapper.

## What you get

**User level, once per machine.** `install.sh` creates `$RIO_HOME` (default `~/.rio/`):

| Path | What it is |
| --- | --- |
| `stack/` | A git checkout of rio.stack, pinned (default `main`) |
| `config.yaml` | Identities (`jadenblack`, `riolabs-ai`) and provider *references*. Never secrets. |
| `bin/rioctl` | Symlink to `stack/bin/rioctl` |

`install.sh` writes the home by default (the `curl | sh` contract). `--dry-run`
prints the plan and writes nothing. It prints a PATH hint; it never edits shell
rc unless you pass `--write` (appends one `export PATH` line to `~/.bashrc` if
missing).

**Project level, per repo.** `rioctl init` creates:

| Path | What it is |
| --- | --- |
| `rio.project.yaml` | The manifest at the repo root, which mission control (#28) reads |
| `.rio/rio.project.yaml` | The same file, kept under `.rio/` as #40 asked |
| `.rio/stack.lock` | Stack ref plus every layer version the pin currently ships |
| `.rio/overrides/` | Local, gitignored overrides (not secrets) |

Preview by default; `--write` applies. `--force` overwrites.

**The loop (stubs in v1).** `rioctl sync` previews trickle-down (#30). `rioctl promote`
prints the PR it would open against this repo (#29). Neither writes nor pushes.
`rioctl status` wraps `stack/mission-control/status.sh`.

## Use it

```bash
# from a checkout (also what verify.sh exercises)
sh install.sh --dry-run --home /tmp/rio-test --from . --worktree
sh install.sh --home /tmp/rio-test --from . --worktree

export PATH="/tmp/rio-test/bin:$PATH"
rioctl doctor
rioctl init                 # preview
rioctl init --write         # apply, inside a git repo
rioctl status --offline
rioctl sync
rioctl promote
```

Or, once this is on `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/riolabs-ai/rio.stack/main/install.sh | sh
```

Env: `RIO_HOME`, `RIO_STACK_URL` / `--from`, `RIO_STACK_REF` / `--ref`, `RIO_STACK`
(overrides the checkout `bin/rioctl` resolves). `--worktree` overlays uncommitted
files from a local `--from` path; it is a dev/test flag, not needed for a
normal clone.

## Verify

```bash
bash stack/rio-cli/verify.sh
```

Installs into a throwaway `RIO_HOME`, runs `rioctl init` preview and `--write` in a
temp git repo, checks the files, and deletes the temps. It never touches
`~/.rio`, `~/.bashrc`, or the Hermes `rio` wrapper.

## Layout

```
install.sh                 POSIX sh; user-level home. Dry-run with --dry-run
bin/rioctl                 the CLI (bash)
skills/rioctl/SKILL.md     thin agent skill — no duplicated logic
stack/rio-cli/README.md    this file
stack/rio-cli/verify.sh    the proof
stack/rio-cli/rio-cli-v1.lock.yaml
```

## Who changes what

- **Identities / provider refs**: the user's `~/.rio/config.yaml` (never commit it,
  never put a secret in it).
- **A project's pin**: `rio.project.yaml` and `.rio/stack.lock`, via `rioctl init`
  or a later `rioctl sync` PR.
- **The CLI itself**: files above, plus a lock and verify change in the same
  commit.
