# Mission control — one Rio Labs control plane for every project

**Status:** v1 design + first registry, 2026-11-17. **Board:** `stack`. **Tracking:** see
[Roadmap](#7-roadmap).

rio.stack is the foundation every Rio project is instantiated from. Mission control is the
loop that keeps that true after day one:

```
            promote up (qualified refinements)
   project ───────────────────────────────▶ rio.stack layer vN+1
      ▲                                           │
      │        trickle down (one PR per project)  │
      └───────────────────────────────────────────┘
```

Projects iterate on their own copy. What a project proves out is promoted *up* into a layer.
The layer gets a new version. That version is offered *down* to every project as a PR. Exceptions
are allowed, but they are written down, never implicit.

## 0. GitHub is the single source of truth

Every operating plan, every bit of progress and every observable signal lives on GitHub, so
the system stays tool-agnostic:

| What | Lives in |
|---|---|
| plans, needs, decisions | issues (labels for priority + area), milestones |
| progress | PRs, Projects (v2) fields, issue state |
| shipped versions | layer tags + GitHub Releases |
| health / observability | Actions check runs, `status.sh --json` attached to a run summary |
| project membership | `registry.yaml` + each repo's `rio.project.yaml` (both in git) |

Mission control **reads** its state from GitHub (`gh api`, `gh issue/pr/release list`). Hermes
(Project Stewardship, Kanban), Obsidian, Grok Bot and any dashboard are **views and consumers**:
they may mirror GitHub state and propose work, but a plan that exists only in a Kanban card,
a vault note or a chat is not a plan yet. Mirrors write back through issues/PRs, never around
them.

Mission control is **not** a new service in v1. It is three files and one script in this layer,
built on the conventions the other layers already use (`*-lock.yaml`, dry-run by default,
`verify.sh` must pass).

## 1. Instantiating a project — the project manifest

Every project carries one file at its root: **`rio.project.yaml`**. It is the project's lock
against rio.stack — which layers it uses, at which version, and where it deliberately differs.

```yaml
schema: rio.project/v1
id: alignsynch                 # same id as in mission-control/registry.yaml
owner: riolabs-ai
repo: riolabs-ai/alignsynch
domain: business               # rio | business | clients | creator  (workspace bucket, §6)
stack:
  ref: c8a3bfe                 # rio.stack commit the layers below were taken from
  layers:
    github-template: "1.0.0"   # layer -> version from stack/<layer>/*-lock.yaml
exceptions:
  - layer: github-template
    path: .github/workflows/check.yml
    reason: Next.js app needs its own CI; starter check would double-run
    until: 2027-01-31          # optional; no date = permanent, reviewed quarterly
```

Rules:

1. **Versions come from layer locks.** A layer's version is the `version:` in its
   `stack/<layer>/*-lock.yaml`. A manifest naming a version that no lock has ever carried is
   invalid.
2. **Instantiate = render + manifest in one PR.** A new project is created by running the
   layers' own renderers (`stack/github-template/render.sh`, `stack/bot-profile/install.sh`, …)
   in dry-run, reviewing, writing, and committing `rio.project.yaml` alongside. One PR, never
   merged by an agent.
3. **No manifest = not onboarded.** Mission control lists such repos as `candidate`; nothing
   trickles down to them.

The full spec (field list, validation, how a manifest is created for an existing repo) is its
own issue; [`project.example.yaml`](project.example.yaml) is the reference example.

## 2. The registry — what mission control *is* in v1

[`registry.yaml`](registry.yaml) is the single list of everything Rio Labs administers:
every project, where it lives on GitHub, where it lives on disk today and where it should live,
its onboarding status, and the layers it is expected to carry.

| Field | Meaning |
|---|---|
| `id` | stable short name, matches `rio.project.yaml` |
| `repo` | `owner/name` on GitHub, or `null` for local-only work |
| `local` | where it is on prodesk today (`null` = not cloned) |
| `target` | where it should live under the workspace standard (§6) |
| `domain` | `rio` · `business` · `clients` · `creator` (the workspace buckets, §6) · `personal` (Jaden's own account, lives outside the rio workspace) |
| `status` | `source` (rio.stack itself) · `onboarded` (has a manifest) · `candidate` (should onboard) · `review` (owner decides keep / archive / fold in) · `exception` (administered elsewhere, by decision) |
| `layers` | layer → version the project is *expected* to be on |
| `notes` | anything a human needs before touching it |

Forks are **not** projects. They are tracked by the GitHub cleanup inventory, not here.

[`status.sh`](status.sh) (a thin wrapper over `tools/mc.py status`) reads the registry and reports, read-only, for every project:

- **remote** — exists, visibility, fork/archived, default branch, last push;
- **local** — path exists, is a git checkout, `origin` matches `repo`, branch, dirty count,
  last commit;
- **drift** — layer versions in the project's `rio.project.yaml` (when present locally) vs the
  versions in this checkout's locks;
- **coverage** — riolabs-ai source repos missing from the registry, and folders under the
  workspace root that no entry claims.

```
bash stack/mission-control/status.sh            # table
bash stack/mission-control/status.sh --offline  # local only, no GitHub calls
bash stack/mission-control/status.sh --json     # for the later dashboard
```

It never writes, never fetches, never switches branches. Later: the same JSON feeds a dashboard
(rio.stack#5, Hermy HQ).

## 3. Promote up — how a refinement reaches rio.stack

A refinement is anything a project changed in a layer-owned file that should become the
default for everyone: a better CI job, a tighter `SECURITY.md`, a new label, a bot routine.

1. Open a **Promote** issue on rio.stack (form: `.github/ISSUE_TEMPLATE/promote.yml`, label
   `promote`). It names the source project, the layer, the commit or PR where it was proven, and
   the evidence.
2. A PR against `stack/<layer>/` implements it generically (placeholders, no client specifics),
   **bumps the layer version in its lock**, and adds a line to the layer's changelog section.
3. `verify.sh` for that layer must pass, including the new behaviour.

**Qualified** means all of:

- [ ] **Proven** — running in at least one project for a week or through one real use, with a
      link to it.
- [ ] **General** — no project, client, person or secret names; expressed as placeholders.
- [ ] **Verified** — the layer's `verify.sh` checks it, with a negative control that fails
      without it (the charter: a check that cannot fail is not a check).
- [ ] **Versioned** — lock bumped: patch = fix, minor = additive, major = breaking (needs an
      upgrade note).
- [ ] **Reversible** — a project can stay on the old version via an exception.

A promote issue that misses a box stays open with the missing evidence named; it is not
closed as rejected.

## 4. The pipeline — how config trickles down without CI waste or merge mess

This is the core problem right now: rio.stack config reaching every repo. Every change, up or
down, runs one pipeline:

```
issue ──▶ triage ──▶ eval ──▶ pool ──▶ PR ──▶ release ──▶ trickle-down PRs (one per project)
```

| Stage | What happens | Lives in GitHub as |
|---|---|---|
| **issue** | a need, a promote proposal, a provider finding | issue (forms: promote, chore, bug, feature) |
| **triage** | priority (`p0/p1/p2`), area label (`stack`, `github`, `hermes` …), layer named, dup check | labels + `triaged` state on the Project |
| **eval** | is it qualified (§3)? which layers/projects does it touch? blast radius, tier (T0–T2) | a checklist comment; `promote` items carry the 5 boxes |
| **pool** | related triaged issues are batched into **one PR per layer per release**. Two label tweaks and a CI fix for the same layer are one PR, not three | a milestone per layer release, e.g. `github-template 1.1.0` |
| **PR** | one squash-merged PR closes the pooled issues (`Closes #a, #b`) and bumps the layer lock | PR |
| **release** | tag `<layer>/v<semver>` + GitHub Release with notes from the pooled issues | tag + Release |
| **trickle-down** | `sync` previews every onboarded project, then opens **one PR per project** per release | PR labelled `trickle-down` in each project |

### Trickle-down sync

After a layer release:

1. `mc.py sync` (roadmap) walks the registry and compares each `onboarded` project's
   `rio.project.yaml` with the new lock.
2. **Preview by default:** per project, the files that would change and the exceptions that
   skip them. Nothing is written.
3. `--write --project <id>` opens one PR on `rio/sync-<layer>-<version>`. It never pushes to a
   default branch and never auto-merges. Projects go one at a time, with a pause between repos.
4. Exceptions are honoured file by file. An expired `until:` is reported, not silently
   dropped. Several pending releases for one project are **pooled into one sync PR**, not stacked.

### Minimal CI waste

- **Path filters:** each layer's workflow runs only on `stack/<layer>/**` (plus its own
  workflow file). Docs-only changes run nothing but a markdown link check.
- **Concurrency cancel:** `concurrency: {group: ${{ github.workflow }}-${{ github.ref }},
  cancel-in-progress: true}` on every PR workflow. A new push kills the stale run.
- **One required check:** a single `verify` workflow with no `paths:` filter is the only
  required status. Inside it, a changed-files step picks which layers' `verify.sh` to run, and a
  final `verify` job (`if: always()`) passes when every selected job passed or none were
  selected. Workflow-level `paths:` filters are only used on non-required workflows, because a
  required check whose workflow is skipped stays pending forever.
- **Batching:** pooling (above) is the main saving. Trickle-down PRs run the project's own CI
  once per release, not once per change.
- **No cron CI.** Scheduled jobs are limited to drift checks (`status.sh`), and they post one
  issue comment instead of failing a run nobody reads.

### No rebase / merge mess — recommendation

**Squash-merge only, short-lived branches off `main`, and no "require branch up to date"
rule.** Concretely:

- repo settings: squash merge on, merge commits and rebase merges off, auto-delete head
  branches, linear history required. Default squash message = PR title + body.
- **Don't require branches to be up to date.** That rule is what makes every merge trigger a
  rebase and a CI rerun on all other open PRs. Pooling keeps PRs few and disjoint by layer, so
  a post-merge `verify` run on `main` catches the rare semantic conflict more cheaply.
- **Merge queue** where GitHub offers it for free (public repos in an organization, so most of
  riolabs-ai) when two or more PRs routinely land on the same day. Personal-account repos don't
  get merge queue, which is one more reason they stay low-traffic.
- **Not chosen:** a long-lived integration branch (a second `main` to keep in sync), stacked-PR
  tooling (worth it for large features, overkill for config), and auto-rebase bots (they spend
  CI on every push to `main`). We can revisit if pooled PRs start colliding.

## 5. Exceptions

Exceptions live in two places, on purpose:

- **Per file / per layer** — in the project's `rio.project.yaml` `exceptions:`. The project owns
  the reason.
- **Per project** — `status: exception` in the registry, with `notes:` saying who administers it
  instead (e.g. a client repo owned by the client's account).

Both carry a `reason`. Status reports every exception and every expired one, so "we diverged"
is always visible.

## 6. Workspace standard (proposal)

Local root: **`~/local/rio`**, four buckets, as named by Jaden:

| Bucket | Holds | Today |
|---|---|---|
| `rio/` | the platform: rio.stack, rio.vault, brand, starters | rio.stack, rio.vault, brand |
| `business/` | Rio Labs products and sites | web.riolabs.ai (notes only, not a clone) |
| `clients/<client>/` | client repos, owned by the client | fourthwall (roryskagenart/fw-revops) |
| `creator/` | channels, video pipelines, content | youtube-pipe-ingest |

Nothing moves until the layout issue is decided. The registry records both `local` (today)
and `target` (proposed) so the move can be done later as one reviewed step per folder.

## 7. Agent config layer — every repo and account agent-ready, validated against providers

Agent setup is the main blocker for provider-validated config. Every agent that touches a repo
(Grok Bot, Hermes profiles, Cursor, Claude Code, Copilot, Codex, CI bots) needs to read the same
rules and run with the right permissions. The `agent-config` layer (roadmap) standardises this.

**Per-repo files: one source, thin pointers.**

| File | Read by | Content |
|---|---|---|
| `AGENTS.md` | Codex, Cursor, Copilot coding agent, Hermes, Grok Bot, most others | **the canonical file**: what the repo is, build/test/verify commands, the rio pipeline rules (§4), boundaries (no merge/delete/visibility), layer + `rio.project.yaml` pointer |
| `CLAUDE.md` | Claude Code | one line, `@AGENTS.md`, plus Claude-only notes if any |
| `.cursor/rules/rio.mdc` | Cursor | `alwaysApply: true` front-matter pointing to `AGENTS.md`. Only file-scoped rules live here |
| `.github/copilot-instructions.md` | Copilot (chat, review) | short pointer to `AGENTS.md` and the review checklist |
| `.github/copilot-setup-steps.yml` (workflow) | Copilot coding agent | environment setup, if the repo needs one |
| `.mcp.json` / `.cursor/mcp.json` | MCP-capable agents | server list only; secrets are `${ENV}` refs, never literals |

Rendered from the layer with placeholders, version-pinned in `rio.project.yaml`, and updated by
the same trickle-down PRs. Repo-specific content goes in a marked `<!-- rio:local -->` block that
sync never overwrites.

**Account level.** GitHub's `<owner>/.github` defaults only cover community-health files
(issue/PR templates, CONTRIBUTING, SECURITY…), *not* `AGENTS.md`. So:
`stack/github-template` carries the account defaults (forms, PR template with the pipeline
checklist, labels incl. `promote`/`trickle-down`, a reusable `verify` workflow under
`workflow-templates/`), and `agent-config` carries the per-repo files.

**Who gets what permission:**

| Actor | Identity | Scope |
|---|---|---|
| Jaden on prodesk | `gh` OAuth (keyring) | full owner; the only identity that merges, deletes, or changes visibility |
| Mission control / sync / CI bots | **one GitHub App per org** (`rio-mission-control`), installation tokens | contents, issues, pull requests: write. Metadata/checks: read. **No** administration, delete, or workflow-file write unless a card grants T2 |
| Hermes profiles (ase-github …) | the same App's installation token, issued per run through `bws` | as above, narrowed per profile; never a long-lived token in `.env` |
| Agents in a single repo (Copilot agent, Cursor/Claude cloud) | their vendor's GitHub App, installed per repo | that repo only |
| Fine-grained PATs | only where an App can't work (e.g. a user-account API with no App support) | single repo, expiry ≤ 90 days, recorded in the secrets plan (#8) |
| Classic PATs | none | retired |

Apps beat tokens because their permissions are declared, visible in settings, per-repo
installable, short-lived and attributed to the bot, not to Jaden.

**Validation against providers.** `agent-config/verify.sh` checks per repo: the canonical file
exists and every pointer resolves to it. It also confirms the MCP configs hold no literal
secrets, and that each provider the repo declares (`rio.project.yaml` →
`providers: [github, vercel, neon …]`) is reachable with the declared identity at the declared
tier. It does this read-only, through the provider layer's own `verify` (e.g. `gh api`
installation permissions, `vercel whoami` + project link, `neonctl` project list). A missing or
over-broad permission fails the check, and a phantom provider is the negative control.

## 8. Providers — Hermes first

Each provider is a layer with the `stack/providers/` shape (`desired.yaml`, `apply`, `verify`,
`STATUS.md`). That gives it a version, so it can be promoted and trickled like any other layer.

**1. Hermes: the first provider, re-slated around Project Stewardship (P0).** Hermes is
Jaden's main entry point. What prodesk shows today (read-only, 2026-11-17):

- Hermes Agent v0.23.1, git install, 11 profiles (`rio`, `ase-github`, `alignsynch`,
  `alignsynch-ops`, `design`, `infra`, `kestrel`, `rory`, `blueberry-rio`, `beaconprobe`,
  `tmplv1`). Plugin sets range from 0 to ~38 per profile with no declared standard.
- `hermes-project-stewardship` **v0.5.6** (Sahil-SS9, pinned `cc54a15`) is enabled in the
  root config, with a desktop panel installed. It is enabled but not enrolled. Its dockyard DB holds **one**
  stewarded project (Call Indigo, autonomy 1, lead `default`). It has **0** objectives, goals,
  cycles, initiatives, milestones, workflows, bots or merge gates. Hermes's project registry knows 3
  projects (jadenblack, Call Indigo, AlignSynch). `hermes stewardship` is not a CLI command in
  this build.
- Stewardship can only be enabled in **one profile per install** (the onboarding skill
  documents the duplicate-package failure). Duplicate installs from 11-04/11-06 sit in
  `backups/`.
- ~81 `config.yaml.bak*` files in `~/.hermes`. Config is not versioned anywhere.

The re-slate: Hermes config becomes **`stack/hermes/`**, with `desired.yaml` covering profiles,
plugin set per profile class and pinned versions, and Stewardship as the **config foundation**.
Every registry project becomes a stewarded project whose objectives are GitHub-checkable
(`gh api` evaluators: open p0 count, CI green on main, layer drift = 0) and whose initiatives
open GitHub issues (§0). `verify` re-reads the live Hermes state, and the backups are replaced
by git history. Folds in rio.stack#19 (Hermes reset), #15 (toolsets standard), #22 (steward
charter) and `stack/bot-profile`.

**2. Everything after Hermes + HPS is decided by #37, not presumed.** Jaden's rule is that 3
layers at 110% beat 28 half-done. #37 adversarially evaluates each candidate (claim, red-team
counter-case, evidence, then keep / cut / defer) and produces the agent-team roster for the
pipeline (§4). Follow-up issues get opened only for layers that survive. Candidates under review: Obsidian (vault app + REST API, `stack.yaml` already pins
it) · Vercel · Porkbun (registrar, DNS deferred but account config and API access in scope) ·
Neon · Resend · **Vercel Marketplace** integrations billed through Vercel project billing (one
entry per installed integration, with resources, billing owner and env vars it injects).
Google Workspace mail is rio.stack#25. Grok Bot follows the agent-config layer.

## 9. Roadmap

**P0, in this order of leverage:** the pipeline, agent config, and Hermes + HPS, gated by the
minimal-stack research in #37 (3 layers at 110% beat 28 half-done). Everything else waits on #37's verdicts.

| Pri | Issue | Item | Done when |
|---|---|---|---|
| p0 | #37 | Research: adversarially prove the minimal stack (Hermes + HPS first, agent teams) | `docs/stack-decisions.md` approved by Jaden; follow-ups only for kept layers |
| p0 | #33 | Pipeline: issue → triage → eval → pool → PR → release, minimal CI, squash-only | one layer release runs end to end with a single trickle-down PR |
| p0 | #34 | Agent config layer: AGENTS.md + pointers, GitHub App permissions, provider validation | rendered into rio.stack + one consumer, verify passes |
| p0 | #35 | Hermes as the first provider, re-slated around Project Stewardship | `stack/hermes` desired/verify, rio.stack enrolled at autonomy 1 |
| p0 | #27 | Mission control v1: registry + status | this PR merged, `status.sh` clean on prodesk |
| p1 | #28 | Project manifest / lock spec (`rio.project.yaml`) | schema + validator + first real manifest |
| p1 | #29 | Promote-up flow | one real promotion end to end |
| p1 | #30 | Trickle-down sync (the pipeline's last stage) | preview for all, `--write` on one project |
| p1 | #31 | Workspace layout standard | `~/local/rio/{rio,business,clients,creator}` decided, moves one by one |
| p1 | #32 | Onboard existing riolabs-ai repos | every entry onboarded, exception, or decided |
| — | #36 | Provider candidates after Hermes (Obsidian, Vercel, Vercel Marketplace, Neon, Resend, Porkbun) | parked; superseded by #37's keep/cut/defer verdicts |
| p1 | #25 | Google Workspace mail pipelines | (existing) |

Shipped provider core: `stack/github-template` (#23).

## 10. Boundaries

- Read-only by default; every write is a PR. No merge, delete, archive, transfer or visibility
  change from any mission-control tool.
- One repo at a time. No bulk apply across repos.
- DNS and domains are out of scope for v1.
