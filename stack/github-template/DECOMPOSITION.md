# Decomposition: ai-seo-society/.github → rio.stack GitHub template

**Source:** [`ai-seo-society/.github`](https://github.com/ai-seo-society/.github) at
`30bec41` (2026-11-17), the repo behind the org page at github.com/ai-seo-society.

**License:** none. The repo has no `LICENSE` file and GitHub reports no license, so all
rights are reserved by default. We take **structure and ideas only**; every word and line
of code in this layer is original. The vendored fonts there are SIL OFL, but we do not copy
them either (not needed for v1).

## What the source actually is

It is not a community-health repo. It ships **no** CODE_OF_CONDUCT, CONTRIBUTING,
SECURITY, SUPPORT, FUNDING, issue/PR templates, discussion templates, workflow templates
or label config. It is a **generated organization profile**: a small Python engine
(`profilegen`) that turns words + facts + a page template into `profile/README.md` and
SVG artwork, with CI proving the page is current and an hourly autopilot refreshing facts.

## File-by-file

| Source file | Role | In v1 template |
| --- | --- | --- |
| `profile/README.md` | The org page GitHub renders. Generated, never hand-edited | **Adapted** → `template/profile/README.md`, rendered once from values (no generator yet) |
| `profile/assets/header-{dark,light}.svg` | Light/dark header via `<picture>` | **Deferred** → v2 (avatar image only in v1) |
| `profile/assets/buttons/*.svg`, `covers/*.svg` | CTA buttons and per-repo cover art, text as glyph outlines | **Deferred** → v2 |
| `templates/README.md.tmpl` | Page prose with `{{slots}}` | **Adapted** → the `{{PLACEHOLDER}}` idea, applied to every file |
| `catalog.yaml` | Words: one entry per repo (name, category, kicker, pitch, stack, links), tiers, buttons | **Deferred** → v2 repo catalog; v1 has `values.example.yaml` for account-level words |
| `data/org.json` | Facts from GitHub: repos, tier, empty, releases. Written only by `refresh` | **Deferred** → v2 (needs a refresher) |
| `profilegen/*.py` (`cli`, `build`, `readme`, `art`, `catalog`, `text`, `live`, `privacy`, `preview`) | Engine: pure build, one impure module (`live.py`) for gh/git, privacy gate, local preview | **Idea kept** → `render.sh` is a pure function of `template/` + values; generator deferred |
| `tests/test_architecture.py` etc. | Enforce purity, deterministic build, privacy | **Idea kept** → `verify.sh` with a negative control |
| `.github/workflows/check.yml` | CI: page equals a fresh build, tests pass, no secrets needed | **Adapted** → `template/.github/workflows/check.yml` (no leftover placeholders, YAML parses) |
| `.github/workflows/autopilot.yml` | Hourly fact refresh, commits facts only, never words; off until secrets exist; no PR triggers | **Deferred** → v2; its rules (facts vs words, off-by-default, no secrets on PRs) are recorded here |
| `CLAUDE.md` | Agent operating notes: who changes what, gates, rules | **Adapted** → layer `README.md` "who changes what" |
| `release.yaml` | Marks the repo as "not a product, push direct" | **Dropped** (we go issue → PR) |
| `.gitattributes` (LF everywhere) | Byte-identical builds across OSes | **Kept** → `template/.gitattributes` |
| `.gitignore` (`_private/`, `*.private.*`) | Local-only notes never reach a public repo | **Kept** → `template/.gitignore` |
| `pyproject.toml`, `uv.lock` | Python deps (pyyaml, fonttools, uharfbuzz) | **Dropped** for v1 (only pyyaml needed, already a stack dep) |
| `fonts/*.ttf` + OFL texts | Fonts for SVG glyph outlines | **Dropped** for v1 |

## Added from GitHub conventions (not in the source)

`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, `FUNDING.yml`,
`.github/ISSUE_TEMPLATE/` (bug, feature, chore, config), `.github/PULL_REQUEST_TEMPLATE.md`,
`workflow-templates/` (orgs only), `labels.yml` + `labels-sync.sh`.

## Ideas worth carrying forward (v2 backlog)

1. **Words vs facts split.** Humans own prose; a machine owns versions/dates/visibility.
   The machine can never add a repo to the page — a new repo waits for its words.
2. **Generated output is checked.** CI fails on any byte the build would not produce.
3. **Public-repo hygiene.** Privacy gate over every committed file; `--ci` mode that never
   prints names of unlisted repos in public Actions logs.
4. **Renderer gotchas.** A `<picture>` inside a link breaks GitHub's light/dark swap; SVGs
   shown via `<img>` load no fonts, so text must be outlines; alternate table rows get shaded,
   so use one table per card.
