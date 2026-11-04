#!/usr/bin/env python3
"""proj_sync.py — set-based reconciliation for a GitHub project (Projects v2).

Exists because `gh project item-add` returns exit 0 in three different situations:
  1. the item was added,
  2. the item already existed (silent no-op, still prints the issue body),
  3. the item did not land at all (observed 4 times out of 13 on 2026-11-04).

A write's exit status is therefore not evidence. The only evidence is a read-back of the
collection you intended to change. This tool asserts the postcondition and refuses to
report success on a mismatch.

Usage:
  ./proj_sync.py --owner riolabs-ai --number 5 --issues 7-19            # converge
  ./proj_sync.py --owner riolabs-ai --number 5 --issues 7-19 --check    # assert only
  ./proj_sync.py --owner riolabs-ai --number 5 --repo riolabs-ai/rio.stack --all-open

Exit 0 = the observed set equals the intended set. Exit 1 = drift (details on stderr).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

QUERY = """
query($owner: String!, $number: Int!, $cursor: String) {
  user(login: $owner) {
    projectV2(number: $number) {
      id
      items(first: 100, after: $cursor) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes { id content { ... on Issue { number } } }
      }
    }
  }
}
"""


def gh(*args: str) -> tuple[int, str]:
    p = subprocess.run(["gh", *args], capture_output=True, text=True)
    return p.returncode, (p.stdout or p.stderr).strip()


def parse_ranges(spec: str) -> list[int]:
    """'7-19,25' -> [7..19, 25]"""
    out: list[int] = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            a, b = chunk.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(chunk))
    return sorted(set(out))


def project_state(owner: str, number: int) -> tuple[str, dict[int, str], int]:
    """Return (project_id, {issue_number: item_id}, totalCount), following pagination."""
    items: dict[int, str] = {}
    cursor: str | None = None
    pid = ""
    total = 0
    while True:
        args = ["api", "graphql", "-f", "query=" + QUERY,
                "-f", f"owner={owner}", "-F", f"number={number}"]
        if cursor:
            args += ["-f", f"cursor={cursor}"]
        rc, out = gh(*args)
        if rc != 0:
            raise SystemExit(f"graphql failed: {out[:300]}")
        proj = json.loads(out)["data"]["user"]["projectV2"]
        pid = proj["id"]
        page = proj["items"]
        total = page["totalCount"]
        for n in page["nodes"]:
            c = n.get("content")
            if c and "number" in c:
                items[c["number"]] = n["id"]
        if not page["pageInfo"]["hasNextPage"]:
            break
        cursor = page["pageInfo"]["endCursor"]
    return pid, items, total


def item_list_numbers(owner: str, number: int) -> set[int] | None:
    """Second transport: REST-ish CLI listing. Used to tell 'absent' from 'not yet visible'."""
    rc, out = gh("project", "item-list", str(number), "--owner", owner,
                 "--limit", "500", "--format", "json")
    if rc != 0:
        return None
    try:
        return {i["content"]["number"] for i in json.loads(out)["items"] if i.get("content")}
    except (KeyError, json.JSONDecodeError):
        return None


def settle(owner: str, number: int, expected: list[int], attempts: int = 4) -> tuple[dict[int, str], list[int]]:
    """Read back with backoff. Projects v2 reads can lag a write by a second or two, and a
    false FAIL is as corrosive as a false PASS: it teaches people to ignore the check."""
    delay = 1.0
    items: dict[int, str] = {}
    missing: list[int] = list(expected)
    for i in range(attempts):
        _, items, _ = project_state(owner, number)
        missing = [n for n in expected if n not in items]
        if not missing:
            return items, missing
        if i < attempts - 1:
            time.sleep(delay)
            delay *= 2
    # still missing after backoff: ask a second transport before we call it drift
    alt = item_list_numbers(owner, number)
    if alt is not None:
        truly = [n for n in missing if n not in alt]
        if not truly:
            print(f"  note: graphql lag — all {len(missing)} were present in item-list; treating as converged")
        return items, truly
    return items, missing


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--number", type=int, required=True)
    ap.add_argument("--issues", help="issue numbers, e.g. 7-19,25")
    ap.add_argument("--repo", help="owner/repo, used with --all-open")
    ap.add_argument("--all-open", action="store_true")
    ap.add_argument("--check", action="store_true", help="assert only, never mutate")
    ap.add_argument("--retries", type=int, default=1)
    a = ap.parse_args()

    intended: list[int]
    if a.all_open:
        if not a.repo:
            return fail("--all-open needs --repo")
        rc, out = gh("issue", "list", "-R", a.repo, "--state", "open",
                     "--limit", "500", "--json", "number")
        if rc != 0:
            return fail(f"issue list failed: {out[:200]}")
        intended = sorted(i["number"] for i in json.loads(out))
    elif a.issues:
        intended = parse_ranges(a.issues)
    else:
        return fail("give --issues or --repo + --all-open")

    have, missing = settle(a.owner, a.number, intended)
    extra = sorted(set(have) - set(intended))

    print(f"intended {len(intended)} | observed {len(have)} | missing {len(missing)} | extra {len(extra)}")
    if extra:
        print(f"  note: {len(extra)} item(s) in the project are outside the intended set: {extra[:10]}")

    if not missing:
        print("CONVERGED — every intended item is present (verified by read-back, not by exit status)")
        return 0

    if a.check:
        return fail(f"DRIFT — {len(missing)} missing: {missing}")

    for attempt in range(1, a.retries + 2):
        for n in missing:
            url = f"https://github.com/{a.repo}/issues/{n}" if a.repo else None
            if not url:
                return fail("mutating requires --repo to build issue URLs")
            rc, out = gh("project", "item-add", str(a.number), "--owner", a.owner, "--url", url)
            # exit status is deliberately ignored: the read-back below is the only verdict
            if rc != 0:
                print(f"  add #{n}: gh rc={rc} {out[:80]}")
        have, still = settle(a.owner, a.number, intended)
        print(f"  attempt {attempt}: observed {len(have)}, still missing {len(still)}")
        if not still:
            print("CONVERGED after retry — verified by read-back")
            return 0
        missing = still

    return fail(f"NOT CONVERGED — {len(missing)} still missing after retries: {missing}")


def fail(msg: str) -> int:
    print(f"FAIL — {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
