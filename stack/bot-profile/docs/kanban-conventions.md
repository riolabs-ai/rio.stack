# Native Kanban conventions — how this template's board is used

The board is the record. Anything that is not a card, a comment on a card, or a completion summary
does not survive the session that said it.

## Card shapes

A card that asks a worker to change something carries four things, in this order:

1. **Scope** — the files or surfaces it may touch, and explicitly what it must not.
2. **Acceptance** — the check that proves it, named (`bash scripts/verify.sh`, a test path, a URL
   that must answer).
3. **Completion contract** — `local-only`, `OWNER/REPO`, or an exact PR URL. A card with a push and
   no contract cannot complete honestly.
4. **Evidence to return** — the head sha, the gate result on that sha, and the one thing that stays
   unproven.

A card that asks for a *decision* carries: the question, the options, a recommendation, and what
happens by default if nobody answers.

## Workspaces

- Use a worktree per card, named for the card (`t_<taskid>`). Two cards in one tree is one card's
  work destroyed by the other's branch.
- Never reuse a `dir` workspace for a second card. The debris of the first run is read as the state
  of the second.
- A worktree is not a CI clone: it often has no `origin/main`, so gate tooling must resolve its diff
  base by fetching, or fall back to the conservative full gate — and say loudly which it did.

## Statuses mean what they say

| Status | Meaning | Who moves it |
| --- | --- | --- |
| `triage` | needs a spec before it is work | the lead |
| `todo` | specified, waiting on a parent card | the board, automatically |
| `ready` | specified, unblocked, dispatchable | the board |
| `running` | a worker holds a claim on it | dispatcher |
| `blocked` | typed blocker recorded (`dependency`, `needs_input`, `capability`, `transient`) | worker or lead |
| `review` | finished and self-verified, awaiting a human or reviewer | the implementer |
| `done` | completed with evidence | the implementer or reviewer |

`request_review` is not a blocker and does not count toward unblock-loop detection. Use it instead of
`block` with a free-text "review required" — a task can cycle through review without ever being
escalated as if it were stuck.

## Two rules that cost the most when broken

**Blocking a card does not stop its worker.** `kanban_block` clears the run id; the process keeps
compiling, writing, and holding the shared state. If work has to stop, stop the process on a verified
condition and log the decision — a watcher that silently kills is indistinguishable from a flaky host.

**A restart is not a crash.** A clean gateway restart kills in-flight workers; the reconciliation path
then records them as crashed and may auto-block the cards. If a restart is planned, drain the board
first or expect to unblock by hand, and say which it was in the card comment.

## Evidence over summaries

Executors publish to exact-head green and stop: no merge, no approve, no `--auto`, no `--admin`. The
lead re-reads the head sha before merging, because a squash-merge landing one PR moves `main` under
every other branch in flight. A PR that is `BEHIND` needs a sync and a fresh CI run, not a merge.
