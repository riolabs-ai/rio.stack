# rio.stack

Paperclip-managed stack repository for Rio Stack AOS.

This repository is the managed checkout used by Paperclip projects. It must keep at
least one commit on its default branch (`main`) so Paperclip can create task worktrees
with `git worktree add`. An empty repository has no valid `HEAD`, and every task run
in this project fails at setup with `fatal: invalid reference: HEAD`.

## Layout

- `stack/` — pinned, versioned stack layers (see `stack/agency-agents/` once landed).
