# GitHub SpecialOps layer

The `specops` profile: a shell-first, evidence-led GitHub operator. Persona + capability + five repeatable
manifests with HIL gates.

- Profile: `hermes profile create specops` (config, SOUL, manifests all live under `~/.hermes/profiles/specops/`)
- Manifests: `manifests/*.yaml` — mirrored into the profile at install time
- Onboarding pack (grants, intake, refusals): `ONBOARDING.md`
- Requirement it serves: R-23 (GitHub as source of truth), R-24 (no "cannot" without a tested matrix), R-26 (onboarding is a procedure)

Smoke test, 2026-11-04: `pwd` -> /home/jadenblack, `gh repo list riolabs-ai` -> 80 repos, `rio.stack` rulesets -> 0.
