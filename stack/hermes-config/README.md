# Hermes config v0.1.0

The RioLabs-customized Hermes configuration as a versioned layer: one resolved fleet config, rendered
from templates, installed by a dry-run-by-default script, and held to six invariants that fail loudly.

This is the layer `stack/host-provisioner` leaves behind: the provisioner builds the host, this layer
configures Hermes on it. The first consumer is the RioLabs host; the layer is the versioned artifact,
the host is one installation of it.

## What it guarantees

| Invariant | What it means | Where it is enforced |
| --- | --- | --- |
| **One name per thing** | Every dispatch entry and every card assignee names a live profile; a bot's chat name equals its profile name (the installation root is the one declared exception). | `inv_one_name_per_thing` |
| **No secrets in harness env** | No worker profile syncs a secret store; a canary row named `DATABASE_URL` is *refused*, not merely absent. | `inv_no_secrets_in_harness_env` |
| **Closable cards** | A merge card has an assignee whose profile holds the verb; a tag is not a card outcome. | `inv_closable_cards` |
| **Verification is measurable** | Contracts verify on PR + tests + CI on the exact head; a rules-endpoint 403 is not a failure. | `inv_verification_is_measurable` |
| **One model policy** | One `model_map` at the root; a profile that restates a root key fails the checker. | `inv_one_model_policy` |
| **Nothing inherited by accident** | Profiles render complete, because Hermes has no config inheritance. | `inv_nothing_inherited_by_accident` |

Each invariant has a negative control: a mutation the checker must refuse. A control that slips
through fails `verify.sh`, because an invariant nobody can break is an invariant nobody checked.

## What it deliberately does not do

- **It does not fork Hermes for inheritance.** Hermes has no config inheritance — a profile that omits
  a key resolves the *shipped default*, not the root's value (`agent.clarify_timeout` is `7200` at the
  root and `90` in a profile that omits it). The layer's own merge supplies the completeness, and a
  profile renders as a complete document. No core patch, no "inherited" flag.
- **It does not hold a secret.** It renders *references* — an env var name, an access-token env key,
  a vault project id — never a value. Every key under `secrets.*` is refused on write except the
  boolean that says whether a profile syncs a store at all.
- **It does not delete a profile, a board or a card.** Migration is a separate, gated action; this
  layer only states and installs the target config.
- **It does not own a client's repository.** Client delivery stays in that client's profile and on
  that client's board.
- **It does not write by default.** `install.sh` is dry-run; `--apply` writes; `--force` overwrites a
  differing value. A key that differs is a CONFLICT and stays put.

## Use

```bash
bash install.sh                    # dry run: every decision, nothing written
bash install.sh --apply            # write the keys the layer owns
bash install.sh --apply --force    # also overwrite values that differ
bash install.sh --profile rio-hps  # one profile at a time
bash verify.sh                     # hermetic: files, invariants, negative controls
bash verify.sh --host              # also audit the install this layer is running on
```

`verify.sh` without flags is hermetic: no Hermes install, no `~/.hermes`, no network. That is what
runs in CI. `--host` adds the audit against the machine you installed onto.

## Layout

| Path | What it is |
| --- | --- |
| `hermes-config.lock.yaml` | The resolved state: profiles, model policy, plugin set, MCP registry, verbs, secrets policy, invariants, known drift. |
| `install.sh` | Dry-run by default; renders each profile from the templates and applies the owned keys. |
| `verify.sh` | The six invariants plus structural checks; `--host` audits a live install. |
| `tools/hermes_config_check.py` | The renderer and the invariant checker. Every invariant lives here as code. |
| `templates/root.config.yaml` | The policy source every profile renders complete. |
| `templates/roles/*.yaml` | One delta per role; the layer's merge is what makes a profile complete. |
| `templates/dispatch_profiles.yaml` | The dispatch allow-list (mirrors the lock; verify fails if they disagree). |
| `templates/soul/ROLE.md` | The charter skeleton; per-role prose lives in the lock's `charters:`. |
| `docs/decisions.md` | The five owner decisions this layer implements, and what each one costs. |

## Using this layer somewhere that is not RioLabs

**A consumer who is not RioLabs must change the profile list, the provider and model identifiers in
`hermes-config.lock.yaml`, the boards and client names in the charters, and the vault project id in
the secrets section — everything else in the layer is generic.**

## Status

v0.1.0 — the layer is resolved against one host. Its `drift:` block names what that host still owes
(`install.sh --apply` closes each one); a layer without a drift block is a layer nobody has installed.
