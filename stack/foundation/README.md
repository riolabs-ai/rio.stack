# Foundation requirements (v1) — adversarially derived

This layer is deliberately **not** a plugin list. It is the set of guarantees the stack must hold *before* any
plugin, profile or tool is admitted to it. Every requirement here exists because something failed without it —
each carries the observed failure, the adversarial test that would falsify it, and the strongest objection
against it.

Method: a requirement is admitted only if (a) a real failure exists without it, (b) it can be tested by a check
a human or `verify.sh` can run, and (c) the strongest counter-argument is recorded next to it, not buried.

- Machine-readable: `requirements.v1.yaml`
- Mechanical checks: `./verify.sh` (exit 0 = every objective requirement passes)
- Adversarial register: `adversarial.v1.md`
- GitHub capability annex (R-23): `github.v1.md`

## The eight clusters

| Cluster | Requirements | Question it answers |
|---|---|---|
| A · Identity & isolation | R-01…R-03 | Who is acting, in what tree, under what rules? |
| B · Secrets | R-04…R-06 | Where do keys live and what happens when the machine dies? |
| C · Work tracking | R-07…R-10 | What is true about a piece of work? |
| D · Survivability | R-11…R-13 | What survives a restart, a kill, a stall? |
| E · Output & attention | R-14…R-16 | What does the human actually receive? |
| F · Toolsets & plugins | R-17…R-20 | What may an agent do, and what may run in its process? |
| G · Memory & knowledge | R-21…R-22 | What outlives the conversation? |
| H · Legibility & posture | R-23…R-29 | Where does truth live, what may an agent refuse, and does the foundry stay up? |

## Admission rule

A plugin, skill, profile or tool joins the stack only when it is mapped to the requirement(s) it serves, and
`verify.sh` can show the requirement it claims to serve is actually met. "Useful" is not a criterion.
