# Decision sheet — answer these, ASE executes

Six decisions block the ASE program. Each has a recommendation; override any of them.

| # | Decision | Recommendation | Why it blocks |
|---|---|---|---|
| D1 | Bot identity | `ase-github` (renamed from `specops`; `ase.github` as the handle) | **DONE** — profile live, cwd neutral |
| D2 | Secrets model | One **BWS account per GitHub org**, one project per profile; PAT per org identity | GitHub auth today is keyring-only, so every profile acts as `jadenblack` — no isolation |
| D3 | Workspace root | **`~/rio.prodesk`** as the only authored root; `~/Desktop/dev.local`, `~/rio.xps`, `~/rio.blacktop` demoted to read-only sources | One root = one backup target; today there are four |
| D4 | Repo scope | All **20 repos / 7 orgs**; sweep monthly, PRs weekly | ASE cannot custodian an undefined fleet |
| D5 | Board surface | `hermes-project-stewardship` first; Projects v2 and Gantt deferred | Four board truths is three too many |
| D6 | `rory` profile cwd | Move off `~/Desktop/dev.local/roryskagenart` (parent of two repos) | R-03 violation found by `verify.sh` |

## How to answer

Either post the answers on this issue, or fill the **ASE triage** form (`.github/ISSUE_TEMPLATE/ase-triage.yml`)
per run once D1–D6 are settled.
