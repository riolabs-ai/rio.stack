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

## 4. Trickle down — how qualified refinements reach every project

After a layer version lands on `main`:

1. `sync` (roadmap item) walks the registry, and for each `onboarded` project compares its
   `rio.project.yaml` with the new lock.
2. **Preview by default:** prints, per project, the files that would change and the exceptions
   that skip them. Nothing is written.
3. With `--write`, it opens **one PR per project** on a `rio/sync-<layer>-<version>` branch:
   rendered changes + the manifest's version bump, labelled `trickle-down`. Never pushed to a
   default branch, never auto-merged, one project at a time with a pause between repos (the
   same pacing as the GitHub cleanup job).
4. Exceptions are honoured file by file. An expired exception (`until:` in the past) is
   reported, not silently dropped.

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

## 7. Roadmap

| # | Item | Done when |
|---|---|---|
| a | Mission control v1: registry + status | this PR merged, `status.sh` runs clean on prodesk |
| b | Project manifest / lock spec | `rio.project.yaml` schema + validator in `verify.sh` |
| c | Promote-up flow | form + `promote` label + criteria used on one real promotion |
| d | Trickle-down sync | `sync` previews all onboarded projects; `--write` opens one PR on one project |
| e | Workspace layout standard | `~/local/rio/{rio,business,clients,creator}` decided; moves done one by one |
| f | Onboard existing riolabs-ai repos | every registry entry is `onboarded`, `review`-resolved or `exception` |

Provider cores (GitHub template — shipped, Google Workspace mail rio.stack#25, Hermes,
Vercel, Obsidian, Grok Bot) plug into this loop as ordinary layers: each gets a lock, a
`verify.sh`, and therefore a version that can be promoted and trickled.

## 8. Boundaries

- Read-only by default; every write is a PR. No merge, delete, archive, transfer or visibility
  change from any mission-control tool.
- One repo at a time. No bulk apply across repos.
- DNS and domains are out of scope for v1.
