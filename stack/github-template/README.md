# GitHub template — account/org standardization (v1)

One provider core of rio.stack: the **`.github` base standard** every GitHub account or
org we run starts from. Render it with your values and you get a ready-to-push
`<owner>/.github` repo: profile page, community health defaults, issue/PR forms, starter
CI and a standard label set.

Derived structurally from `ai-seo-society/.github` (unlicensed, so ideas only). See
[`DECOMPOSITION.md`](DECOMPOSITION.md) for what was kept, adapted and deferred.

## Layout

```
template/             what lands in <owner>/.github, with {{PLACEHOLDERS}}
values.example.yaml   the acme values; copy and fill one per account
render.sh             template + values -> a .github tree (dry-run by default)
labels-sync.sh        push labels.yml to a repo via gh (dry-run by default, never deletes)
verify.sh             proves the layer is shippable
template-v1.lock.yaml pinned files and placeholders
```

## Instantiate it

```bash
cp stack/github-template/values.example.yaml ~/my-values.yaml   # fill every key
bash stack/github-template/render.sh --values ~/my-values.yaml --out ./out/.github          # dry run
bash stack/github-template/render.sh --values ~/my-values.yaml --out ./out/.github --apply  # write
gh repo create <owner>/.github --public    # must be public for GitHub to use the defaults
```

Then push the rendered tree through a PR like any other change.

- **Org:** `profile/README.md` in `<org>/.github` *is* the org page.
- **Personal account:** the page is the README of `<user>/<user>`; copy `profile/` there.
- `workflow-templates/` only shows up in the Actions tab for organizations.
- A value you do not have yet stays as words (`TODO: ...`); render refuses only empty values.
- Values files for real accounts live with their consumer, not here (no personal data in this layer).

## Who changes what

- **Words** (human): `template/` prose and each consumer's values file.
- **Shape** (reviewed): adding/renaming a placeholder or a file = edit `template-v1.lock.yaml`
  in the same commit, or `verify.sh` fails.
- **Facts** (machine): none in v1. A v2 refresher (repo catalog, releases) is in DECOMPOSITION.md.

## Verify

```bash
bash stack/github-template/verify.sh
```

Checks: every pinned file present; YAML parses; placeholders agree across template, values
and lock; example renders with zero leftovers; a missing value makes render refuse and write
nothing (negative control); no secrets, machine paths or hard-coded emails.

## Consumers

| Owner | Kind | Tracked in |
| --- | --- | --- |
| jadenblack | user | jadenblack/ops#10 |
