#!/usr/bin/env python3
"""issue_card_sync.py — assert the GitHub-issue ⇄ kanban-card seam.

Hermes `tasks` has no column for an external ref, so the link is a convention:
`idempotency_key = "gh:<owner>/<repo>#<n>"`. This tool enforces that convention and hard-fails on drift,
in the same shape as proj_sync.py: assert the postcondition on the collection, never trust an exit code.

Modes
  --check   (default) read-only. Exit 1 when any open issue is uncarded or any open card cites a
            missing/closed issue. This is the gate.
  --json    machine-readable report on stdout.

Exit codes
  0 converged · 1 drift · 2 usage/environment error

Never creates cards. Intake is the client bot's job (alignsynch, per issue #476's qualification gate);
this tool only proves whether the seam is honest.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
from typing import Any

KEY_RE = re.compile(r"^gh:(?P<repo>[^#]+)#(?P<num>\d+)$")
TERMINAL = {"done", "archived"}


def gh_json(args: list[str]) -> Any:
    proc = subprocess.run(["gh", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])} failed: {proc.stderr.strip()[:300]}")
    return json.loads(proc.stdout or "null")


def open_issues(repo: str) -> dict[int, dict]:
    rows = gh_json(["issue", "list", "-R", repo, "--state", "open", "--limit", "500",
                    "--json", "number,title,labels,url"])
    return {r["number"]: r for r in rows}


def cards(db_path: str) -> list[dict]:
    if not os.path.exists(db_path):
        raise RuntimeError(f"board db not found: {db_path}")
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "select id, title, status, assignee, idempotency_key from tasks"
        ).fetchall()
    finally:
        con.close()
    out = []
    for tid, title, status, assignee, key in rows:
        if status in TERMINAL:
            continue
        out.append({"id": tid, "title": title, "status": status,
                    "assignee": assignee, "key": key})
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/repo whose issues feed the board")
    ap.add_argument("--board", required=True, help="board slug, e.g. alignsynch")
    ap.add_argument("--home", default=os.path.expanduser("~/.hermes"))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    db = os.path.join(args.home, "kanban", "boards", args.board, "kanban.db")
    try:
        issues = open_issues(args.repo)
        rows = cards(db)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    # Map cards to issue numbers via the convention key.
    keyed: dict[int, dict] = {}
    unkeyed: list[dict] = []
    malformed: list[dict] = []
    for card in rows:
        key = (card["key"] or "").strip()
        if not key:
            unkeyed.append(card)
            continue
        m = KEY_RE.match(key)
        if not m or m.group("repo").lower() != args.repo.lower():
            malformed.append(card)
            continue
        keyed[int(m.group("num"))] = card

    uncarded = sorted(n for n in issues if n not in keyed)
    orphaned = sorted(n for n in keyed if n not in issues)   # card cites closed/missing issue

    report = {
        "repo": args.repo,
        "board": args.board,
        "open_issues": len(issues),
        "open_cards": len(rows),
        "carded_issues": sorted(keyed),
        "uncarded_issues": uncarded,
        "cards_citing_closed_or_missing": orphaned,
        "cards_without_key": [{"id": c["id"], "title": c["title"][:60]} for c in unkeyed],
        "cards_with_bad_key": [{"id": c["id"], "key": c["key"]} for c in malformed],
        "converged": not uncarded and not orphaned,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"issues open: {len(issues)} | cards open: {len(rows)} | "
              f"carded: {len(keyed)} | uncarded: {len(uncarded)} | "
              f"orphaned: {len(orphaned)}")
        if uncarded:
            print("  UNcarded issues (no card cites them): " + ", ".join(f"#{n}" for n in uncarded[:12])
                  + (" …" if len(uncarded) > 12 else ""))
        if orphaned:
            print("  cards citing a closed/missing issue: " + ", ".join(f"#{n}" for n in orphaned))
        if unkeyed:
            print(f"  cards with no gh: key (cannot be linked): "
                  + ", ".join(c["id"] for c in unkeyed[:8]))
        if malformed:
            print("  cards with a malformed key: " + ", ".join(c["id"] for c in malformed[:8]))
        print("CONVERGED — every open card cites an open issue" if report["converged"]
              else "DRIFT — the issue ⇄ card seam is not closed")

    return 0 if report["converged"] else 1


if __name__ == "__main__":
    sys.exit(main())
