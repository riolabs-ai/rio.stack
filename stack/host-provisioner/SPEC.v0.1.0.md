# Host provisioner — v0.1.0 spec

**Status:** spec, approved for review. Not implemented — no `install.sh`, no `verify.sh` in this directory yet.
**Target:** bare-metal Linux Mint 22.3 (Zena), Ubuntu-noble base, x86_64, with a UI desktop.
**Pin:** Hermes Agent `v0.23.3+382.g52b5271` (measured `hermes --version`, 2026-11-21).
**Register:** [`elements.v1.yaml`](elements.v1.yaml) — every element, its source, its requirement.

---

## 1. What "done" proves

A single reviewed run takes a fresh Mint install to a host where:

1. the human user is provisioned to a documented standard (identity, groups, shell, sudo, SSH, PATH);
2. the directory standard exists and every profile's `terminal.cwd` is `$HOME` or a git repo — never a
   parent of projects (foundation **R-03**, mechanical);
3. Hermes is installed by the official installer, supervised as a systemd user service with lingering
   enabled, and `hermes doctor` exits 0;
4. every Hermes setting is applied by `hermes config set` or by a file this layer renders — there is no
   hand-edited `config.yaml` anywhere in the run;
5. `bash stack/host-provisioner/verify.sh` exits 0 and prints one `ok HP-nn` line per element in the
   register.

**Falsifier:** any element in the register that `verify.sh` cannot fail. An element with no working
negative test is documentation, not a guarantee, and does not count toward done.

## 2. What done does *not* prove

| Out of scope for v0.1.0 | Why |
|---|---|
| Client workspace setup, app deployment, the Obsidian vault | Different layers; the provisioner must not become a setup wizard for everything. |
| A backup engine | HP-09 creates the anchor and records the off-box target. **R-06 stays `partial`** until a snapshot job exists. |
| Secret values | The layer asserts modes and ownership. It writes no key. **HP-16 is `v0.1.0-partial`.** |
| Provider integration, models, cost ceilings | `stack/providers` (**R-32…R-35**). |
| Any client profile | Fleet/infra only. |

## 3. Decisions taken (each reversible, each recorded)

**D-1 — Identity model: provision the existing human desktop user, not a dedicated service user.**
Default: `--user jadenblack`, adopted if present.
Why: the upstream pattern in **S1** ("run the source installer as the intended service user") assumes a
headless server, where the service user and the human are different people. On this host they are the
same: `uid=1000(jadenblack)`, and every Hermes artefact — `~/.hermes` profiles `rio-hps`, `alignsynch`,
`default`, `~/local/rio`, `~/.hermes/kanban` — lives under it. Splitting them would move existing state
and break the desktop app, the browser profile and the vault.
A `--service-user <name>` mode (fresh `adduser`, `linger`, no desktop groups) is the documented upstream
shape and ships in v0.2.0; the element register already carries everything it needs except the desktop
group list.
*Confirm or overturn at spec review.*

**D-2 — `requirement: none` is allowed, once.** HP-01 (refuse a host that is not the pinned target) is a
precondition, not a guarantee. Forcing it onto an unrelated requirement would be the exact failure
R-16 exists to prevent. The register records it as unmapped with a reason; the gate count is
`21 mapped / 22 elements`, stated publicly, never rounded up.

**D-3 — Admit the owner's `$SUDO_USER` authorized_keys copy** (HP-04), on **S10** for the file modes and
on recorded evidence that no upstream Hermes doc covers SSH bootstrap. Append-only; never truncates.

**D-4 — `~/local/rio` stays the project root name** (HP-07) as a *value in the lock*, not a rule in the
script. Upstream fixes the shape (a workspace, not a parent of workspaces, **S3**) and R-03 fixes the
cwd rule; the name is site-local.

**D-5 — Managed scope is on by default, with `--no-managed-scope` for a single-user box.** HP-15 pins
policy keys (`security.redact_secrets`, three approval modes) to `/etc/hermes`, enforced by root
ownership (**S7**). It costs one sudo prompt. Never a secret: the managed `.env` is world-readable.

## 4. The layer contract (identical shape to every other layer that ships software)

```
stack/host-provisioner/
  README.md                     layer landing + status
  SPEC.v0.1.0.md                this file
  elements.v1.yaml              the register: element → source → requirement → verify check
  desired-state.v0.1.0.yaml     what install.sh renders (host facts, profiles, config keys)
  install.sh                    dry-run by default; --apply writes; idempotent; one sudo prompt
  host-provisioner-v0.1.0.lock.yaml   what it resolved to on the machine it ran on
  verify.sh                     one named check per element id; exit 0 = shippable
```

Rules the implementation must keep:

- **Dry run is the default.** `install.sh` with no `--apply` prints every decision and writes nothing —
  `stack/bot-profile/install.sh` and `stack/github-template/install.sh` are the reference.
- **Idempotent, converging.** Second run changes nothing and exits 0. Every mutation is
  "absent → create", "present + different → report unless `--force`".
- **The lock is output, not input.** Written by `--apply`; `verify.sh` fails when the lock and the host
  disagree.
- **One sudo prompt, declared up front.** The only privileged writes are `/etc/hermes/*` and
  `loginctl enable-linger`. No sudoers fragment, no NOPASSWD.
- **No secret ever written by this layer.** No key generation, no rotation, no value in `config.yaml`.

## 5. The element set (summary — the register is authoritative)

| Stage | IDs | What it covers |
|---|---|---|
| Preflight | HP-01 | distro/arch pin, loud refusal |
| User | HP-02 … HP-05 | identity + groups, sudo policy, SSH modes, PATH |
| Directories | HP-06 … HP-10 | `~/.hermes` 0700 tree, `~/local/rio`, `terminal.cwd`, backup anchors, permission audit |
| Install | HP-11 … HP-13 | official installer as the user, `hermes doctor`, user service + linger |
| Config as code | HP-14 … HP-20 | render rule, managed scope, secrets posture, profile baseline, toolset ceilings, plugin single-source, approvals |
| Contract | HP-21 … HP-22 | install/lock/verify, one named check per element |

**Requirement coverage:** 17 of 35 requirements touched, 22 elements. The provisioner moves
**R-02** from `unmet` to `met` on a provisioned host (HP-18: every charter "must not" gets a key), and
makes **R-03** mechanical (HP-07/HP-08). It cannot move R-06 or R-05 above the layer's own writes, and
says so instead of claiming otherwise.

## 6. Sources

Cited by ID in the register. Upstream docs are unversioned HTML; they are pinned by the release tag
above and by fetch date (2026-11-21). If a cited section disappears, that is a spec change, reviewed —
not a silent edit.

| ID | Source | What it gives |
|---|---|---|
| S1 | Installation → *Non-Sudo / System Service User Installs* | the pro-grade Linux pattern; home/tool store/config/launcher ownership; `loginctl enable-linger` |
| S2 | Installation → *Install layout*, *What the source installer does* | official installer, `~/.hermes`, `~/.local/bin/hermes`, `--non-interactive` |
| S3 | Nix setup → `nixosModules.default`, *Directory Layout* | the reference implementation of this layer, and the state/home/workspace tree with modes |
| S4 | Nix setup → *Cron on a native install needs a lingering service user* | why linger is not optional |
| S5 | Security → *Gateway Deployment Checklist*, *Securing API Keys* | ten production checks incl. "never run the gateway as root", `.env` 600 |
| S6 | Security → *Approval Modes* | `cron_mode` / `single_query_mode` / `unattended_mode` defaults, advisory acks |
| S7 | Managed Scope | root-owned `/etc/hermes`, leaf-level pinning, filesystem-only enforcement |
| S8 | Bitwarden Secrets Manager | one machine-account token replaces N provider keys; non-interactive setup |
| S9 | Security → *Securing API Keys* | keys in `.env` with proper permissions, never committed |
| S10 | `sshd(8)` FILES | `~/.ssh` 700, `authorized_keys` 600 |

**Not depended on, only mined:** the NixOS module. It is Tier 2, best-effort, NixOS-only — S3 says so
plainly. It is the checklist of what "complete" means, not a runtime dependency.

## 7. Definition of ready — status

| # | Deliverable | State |
|---|---|---|
| 1 | layer name and directory | `stack/host-provisioner/` — no collision with the seven existing layers |
| 2 | complete element list, each with a source | 22 elements, 10 sources (`elements.v1.yaml`) |
| 3 | each element mapped to a foundation requirement | 21/22 mapped; HP-01 unmapped with recorded reason (D-2) |
| 4 | evidence note for any would-be bespoke element | `bespoke:` block — 3 admitted (each with evidence), 2 rejected |
| 5 | the v0.1.0 spec file in the repo | this file + `elements.v1.yaml` |

**Ready to build** once the owner confirms D-1 (identity model) and D-5 (managed scope default). Every
other decision has a stated default and is reversible.

## 8. Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| Upstream docs are unversioned | a cited section moves | pin by release tag + fetch date; a missing section is a reviewed spec change |
| Fresh-box assumption | the layer runs on a box that already has state (it did, on the first run) | every element is adopt-not-overwrite; `--force` is the only way to change an existing value |
| Verification is mostly a shell script asserting shell state | "green" without evidence | each check prints the value it read (`cwd=/home/jadenblack`, `linger=yes`), not just `ok` |
| The register drifts from `verify.sh` | elements silently unverified | HP-22 asserts check count == element count; `verify.sh` fails on a register entry with no check |
| A second editor on `/etc/hermes` | two sources of truth for policy | the lock names every managed key; `hermes config` output is captured into the run log |
