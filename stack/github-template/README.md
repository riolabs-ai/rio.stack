# GitHub template v1: the `.github` base standard

One provider core of rio.stack. Fill in one values file, render, and any GitHub account
or org gets the same pro-grade baseline: a profile page, community health defaults,
issue and PR forms, a starter CI and a standard label set.

## What you get

| Output | Lands in | GitHub uses it for |
| --- | --- | --- |
| Profile page + avatar | **org:** `<org>/.github/profile/` · **user:** `<user>/<user>/` | The page at github.com/&lt;owner&gt; |
| `CODE_OF_CONDUCT`, `CONTRIBUTING`, `SECURITY`, `SUPPORT`, `FUNDING.yml` | `<owner>/.github/` | Default for every repo without its own |
| Issue forms (bug, feature, chore) + PR template | `<owner>/.github/.github/` | Default for every repo without its own |
| `check` workflow | `<owner>/.github/.github/workflows/` | Fails on leftover placeholders or broken YAML |
| `dependabot.yml` | `<owner>/.github/.github/` | Weekly grouped `chore(deps)` PRs that keep that repo's GitHub Actions current (free) |
| `workflow-templates/` | `<owner>/.github/` | Starter CI in the Actions tab (orgs only) |
| `labels.yml` | `<owner>/.github/` | Pushed per repo with `labels-sync.sh` |

**The profile rule.** GitHub reads an org's profile from `<org>/.github/profile/README.md`,
but a personal account's from the README of the repo named after it, `<user>/<user>`.
`render.sh` handles both: for `ACCOUNT_KIND: user` it writes the page to `--profile-out`
and leaves a one-paragraph pointer in `.github/profile/`, so there is one source of words
(the values file) and no second copy to drift.

## Use it

```bash
T=stack/github-template
cp $T/values.example.yaml rio-template.values.yaml        # fill every key

# org
bash $T/render.sh --values rio-template.values.yaml --out ../acme-org/.github            # dry run
bash $T/render.sh --values rio-template.values.yaml --out ../acme-org/.github --apply

# personal account
bash $T/render.sh --values rio-template.values.yaml \
  --out ../me/.github --profile-out ../me/me --apply
```

Both repos must be **public** (`gh repo create <owner>/.github --public`, and
`<user>/<user>` for a person). Ship the rendered trees through PRs like any other change,
and keep `rio-template.values.yaml` in `<owner>/.github` so the next render is one command.

Labels, per repo, dry run first: `bash $T/labels-sync.sh --repo <owner>/<repo> [--apply]`
(creates or updates, never deletes).

**Values.** Every key is required; multi-line Markdown is fine. A value you don't have yet
is written as words (`TODO(name): ...`), never invented. `render.sh` refuses empty values,
unknown account kinds and a user render without `--profile-out`, and writes nothing when
it refuses.

## Layout

```
template/                files with {{PLACEHOLDERS}}; template/_user/ only renders for personal accounts
values.example.yaml      the acme values (also the list of every key)
render.sh                values + template -> .github (+ profile repo); dry run by default
labels-sync.sh           labels.yml -> one repo via gh; dry run by default
verify.sh                proves the layer is shippable
template-v1.lock.yaml    pinned files, placeholders and profile targets
DECOMPOSITION.md         what came from ai-seo-society/.github, and what's deferred to v2
```

## Verify

```bash
bash stack/github-template/verify.sh
```

Renders an org and a personal account against a throwaway avatar and checks: every pinned
file is present and nothing in `template/` is unpinned; YAML parses; placeholders agree
across template, values and lock; zero leftovers; the profile lands where GitHub reads it
(and `.github/profile` is only a pointer for users); every relative link and image
resolves. Negative controls prove each refusal actually refuses. Hygiene: no secrets,
machine paths or hard-coded emails.

## Who changes what

- **Words**: the consumer's `rio-template.values.yaml`, and the prose in `template/`.
- **Shape**: adding or renaming a file or placeholder means editing `template-v1.lock.yaml`
  in the same commit, or `verify.sh` fails.
- **Facts** (repo lists, releases, stars): none in v1. A generator that refreshes them,
  the ai-seo-society pattern, is the v2 backlog in `DECOMPOSITION.md`.

## Consumers

| Owner | Kind | Profile repo | Tracked in |
| --- | --- | --- | --- |
| jadenblack | user | jadenblack/jadenblack | jadenblack/ops#10 |
