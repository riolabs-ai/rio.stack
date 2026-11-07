#!/usr/bin/env python3
"""issue_card_sync.py — assert the GitHub ⇄ kanban-card seam.

Hermes `tasks` has no external-ref column, so the link is a convention carried in `idempotency_key`:

    gh:<owner>/<repo>#issue-<n>       a GitHub issue  (short form gh:owner/repo#<n> also accepted)
    gh:<owner>/<repo>#pr-<n>          a pull request  (Dependabot and hand-made alike)
    gh:<owner>/<repo>#advisory-<ref>  a security advisory / Dependabot alert reference

Why the grammar is wider than "just issues": six open cards on the alignsynch board came from Dependabot
PRs and advisories. They are GitHub-origin work, but no issue number names them, so an issue-only key
would mark them as drift forever.

Drift (exit 1) is ONLY:
  * an OPEN issue with no card citing it              — work exists but cannot be scheduled
  * a card citing an issue/PR that is no longer open  — a zombie card

Reported, but NOT drift:
  * cards with no key at all    — classifying origin is a human/bot decision, not a machine verdict
  * cards with a malformed key  — reported by id, so the typo is cheap to fix
  * advisory refs               — not validated (no stable public lookup without extra scopes)

Modes: (default) human report · --json machine report
Exit codes: 0 converged · 1 drift · 2 usage/environment error

Never creates or mutates cards. Intake belongs to the client bot (issue #476's qualification gate);
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

# gh:owner/repo#issue-554 | #pr-570 | #advisory-CVE-2026-1234 | #554 (short form = issue)
KEY_RE = re.compile(
    r"^gh:(?P<repo>[^#]+)#(?:(?P<kind>issue|pr|advisory)-)?(?P<ref>[A-Za-z0-9._-]+)$"
)
TERMINAL = {"done", "archived"}


def gh_json(args: list[str]) -> Any:
    proc = subprocess.run(["gh", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])} failed: {proc.stderr.strip()[:300]}")
    return json.loads(proc.stdout or "null")


def open_issues(repo: str) -> dict[int, dict]:
    rows = gh_json(["issue", "list", "-R", repo, "--state", "open", "--limit", "500",
                    "--json", "number,title,url"])
    return {r["number"]: r for r in rows}


def open_prs(repo: str) -> dict[int, dict]:
    rows = gh_json(["pr", "list", "-R", repo, "--state", "open", "--limit", "500",
                    "--json", "number,title,isDraft,url"])
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
    return [{"id": t, "title": ti, "status": s, "assignee": a, "key": k}
            for t, ti, s, a, k in rows if s not in TERMINAL]


def classify(key: str | None, repo: str) -> tuple[str, Any] | None:
    """-> (kind, ref) when the key names this repo, else None."""
    if not key or not key.strip():
        return None
    m = KEY_RE.match(key.strip())
    if not m or m.group("repo").lower() != repo.lower():
        return None
    ref, kind = m.group("ref"), (m.group("kind") or "issue")
    if kind in ("issue", "pr"):
        return (kind, int(ref)) if ref.isdigit() else None
    return kind, ref


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/repo whose issues/PRs feed the board")
    ap.add_argument("--board", required=True, help="board slug, e.g. alignsynch")
    ap.add_argument("--home", default=os.path.expanduser("~/.hermes"))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    db = os.path.join(args.home, "kanban", "boards", args.board, "kanban.db")
    try:
        issues = open_issues(args.repo)
        prs = open_prs(args.repo)
        rows = cards(db)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    by_issue: dict[int, list[dict]] = {}
    by_pr: dict[int, list[dict]] = {}
    advisories: list[tuple[str, dict]] = []
    unkeyed: list[dict] = []
    malformed: list[dict] = []

    for card in rows:
        got = classify(card["key"], args.repo)
        if got is None:
            (malformed if card["key"] else unkeyed).append(card)
            continue
        kind, ref = got
        if kind == "issue":
            by_issue.setdefault(ref, []).append(card)
        elif kind == "pr":
            by_pr.setdefault(ref, []).append(card)
        else:
            advisories.append((ref, card))

    uncarded = sorted(n for n in issues if n not in by_issue)
    orphan_issues = sorted(n for n in by_issue if n not in issues)
    orphan_prs = sorted(n for n in by_pr if n not in prs)

    report = {
        "repo": args.repo,
        "board": args.board,
        "open_issues": len(issues),
        "open_prs": len(prs),
        "open_cards": len(rows),
        "issues_carded": len(by_issue),
        "cards_on_prs": len(by_pr),
        "cards_on_advisories": len(advisories),
        "uncarded_issues": uncarded,
        "orphan_issue_cards": orphan_issues,
        "orphan_pr_cards": orphan_prs,
        "unclassified_cards": [{"id": c["id"], "status": c["status"], "title": c["title"][:70]}
                               for c in unkeyed],
        "malformed_keys": [{"id": c["id"], "key": c["key"]} for c in malformed],
        "converged": not uncarded and not orphan_issues and not orphan_prs,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"issues {len(issues)} · prs {len(prs)} · cards {len(rows)} | "
              f"on issues {len(by_issue)} · on prs {len(by_pr)} · on advisories {len(advisories)} | "
              f"uncarded issues {len(uncarded)} · orphan {len(orphan_issues) + len(orphan_prs)}")
        if uncarded:
            print("  uncarded issues: " + ", ".join(f"#{n}" for n in uncarded[:14])
                  + (" …" if len(uncarded) > 14 else ""))
        if orphan_issues:
            print("  cards citing closed/missing ISSUE: " + ", ".join(f"#{n}" for n in orphan_issues))
        if orphan_prs:
            print("  cards citing closed/missing PR: " + ", ".join(f"#{n}" for n in orphan_prs))
        if unkeyed:
            print(f"  {len(unkeyed)} card(s) with no key — classify origin (issue/pr/advisory); "
                  "not counted as drift: " + ", ".join(c["id"] for c in unkeyed[:6]))
        if malformed:
            print("  malformed keys: " + ", ".join(f"{c['id']}={c['key']!r}" for c in malformed[:6]))
        print("CONVERGED — every open card cites an open issue/PR, every open issue has a card"
              if report["converged"] else "DRIFT — the issue ⇄ card seam is not closed")

    return 0 if report["converged"] else 1


if __name__ == "__main__":
    sys.exit(main())
