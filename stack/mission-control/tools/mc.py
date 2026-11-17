#!/usr/bin/env python3
"""Rio Labs mission control — read-only tooling over registry.yaml.

  mc.py validate [--registry FILE]             exit 0 = registry is well-formed
  mc.py status   [--registry FILE] [--offline] [--json]

Never writes, fetches, pushes or switches branches. GitHub is read with `gh api` (the
operator's own auth); --offline skips every network call.
"""
import argparse, json, os, pathlib, subprocess, sys
import yaml

LAYER = pathlib.Path(__file__).resolve().parents[1]          # stack/mission-control
STACK = LAYER.parent                                          # stack/
STATUSES = {"source", "onboarded", "candidate", "review", "exception"}
DOMAINS = {"rio", "business", "clients", "creator", "personal"}
REQUIRED = ["id", "repo", "local", "target", "domain", "status", "layers"]
MANIFEST = "rio.project.yaml"


def expand(p):
    return pathlib.Path(os.path.expanduser(p)) if p else None


def layer_versions():
    """layer -> version, read from every stack/<layer>/*lock*.yaml."""
    out = {}
    for lock in sorted(STACK.glob("*/*lock*.yaml")):
        d = yaml.safe_load(lock.read_text()) or {}
        if d.get("layer") and d.get("version"):
            out[d["layer"]] = str(d["version"])
    return out


def validate(reg, versions):
    errs = []
    if reg.get("schema") != "mission-control/v1":
        errs.append("schema must be mission-control/v1")
    projects = reg.get("projects") or []
    if not projects:
        errs.append("no projects")
    seen = set()
    for i, p in enumerate(projects):
        tag = p.get("id", f"#{i}")
        for k in REQUIRED:
            if k not in p:
                errs.append(f"{tag}: missing {k}")
        if tag in seen:
            errs.append(f"{tag}: duplicate id")
        seen.add(tag)
        if p.get("status") not in STATUSES:
            errs.append(f"{tag}: status {p.get('status')!r} not in {sorted(STATUSES)}")
        if p.get("domain") not in DOMAINS:
            errs.append(f"{tag}: domain {p.get('domain')!r} not in {sorted(DOMAINS)}")
        repo = p.get("repo")
        if repo is not None and (not isinstance(repo, str) or repo.count("/") != 1):
            errs.append(f"{tag}: repo must be owner/name or null")
        if repo is None and p.get("local") is None:
            errs.append(f"{tag}: neither repo nor local - nothing to administer")
        for layer, ver in (p.get("layers") or {}).items():
            if layer not in versions:
                errs.append(f"{tag}: unknown layer {layer}")
            elif str(ver) != versions[layer]:
                # older versions are fine once a layer has history; v1 only knows current locks
                errs.append(f"{tag}: {layer} {ver} is not a version any lock carries (have {versions[layer]})")
    return errs


def sh(*cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def remote_state(repo, offline):
    if repo is None:
        return {"state": "none"}
    if offline:
        return {"state": "skipped"}
    rc, out = sh("gh", "api", f"repos/{repo}")
    if rc != 0:
        return {"state": "missing"}
    d = json.loads(out)
    return {"state": "ok", "visibility": d.get("visibility"), "fork": d.get("fork"),
            "archived": d.get("archived"), "default_branch": d.get("default_branch"),
            "pushed_at": (d.get("pushed_at") or "")[:10], "size_kb": d.get("size", 0)}


def norm_remote(url):
    u = (url or "").removesuffix(".git")
    for pre in ("https://github.com/", "git@github.com:", "ssh://git@github.com/"):
        if u.startswith(pre):
            return u[len(pre):]
    return u


def local_state(p, versions):
    path = expand(p.get("local"))
    if path is None:
        return {"state": "none"}
    if not path.exists():
        return {"state": "missing", "path": str(path)}
    rc, top = sh("git", "rev-parse", "--show-toplevel", cwd=path)
    if rc != 0 or pathlib.Path(top) != path.resolve():
        return {"state": "not-git", "path": str(path)}
    _, url = sh("git", "remote", "get-url", "origin", cwd=path)
    _, branch = sh("git", "branch", "--show-current", cwd=path)
    _, porcelain = sh("git", "status", "--porcelain", cwd=path)
    _, last = sh("git", "log", "-1", "--format=%cs", cwd=path)
    st = {"state": "ok", "path": str(path), "origin": norm_remote(url), "branch": branch,
          "dirty": len([l for l in porcelain.splitlines() if l]), "last_commit": last}
    st["origin_matches"] = p.get("repo") is None or st["origin"].lower() == p["repo"].lower()
    man = path / MANIFEST
    if man.exists():
        m = yaml.safe_load(man.read_text()) or {}
        have = (m.get("stack") or {}).get("layers") or {}
        st["manifest"] = True
        st["drift"] = {l: f"{v} -> {versions[l]}" for l, v in have.items()
                       if l in versions and str(v) != versions[l]}
        st["exceptions"] = len(m.get("exceptions") or [])
    else:
        st["manifest"] = False
    return st


def coverage(reg, offline):
    claimed_repos = {(p.get("repo") or "").lower() for p in reg["projects"]}
    claimed_paths = {str(expand(p[k]).resolve()) for p in reg["projects"]
                     for k in ("local", "target") if p.get(k)}
    out = {"unregistered_repos": [], "unclaimed_folders": []}
    if not offline:
        for owner in reg.get("watch_owners") or []:
            rc, o = sh("gh", "repo", "list", owner, "--source", "--limit", "500",
                       "--json", "nameWithOwner", "--jq", ".[].nameWithOwner")
            if rc == 0:
                out["unregistered_repos"] += [r for r in o.splitlines() if r.lower() not in claimed_repos]
    root = expand(reg.get("workspace_root"))
    if root and root.exists():
        buckets = {"rio", "business", "clients", "creator"}
        for d in sorted(root.iterdir()):
            if not d.is_dir() or d.name.startswith("."):
                continue
            kids = [d] if d.name not in buckets else [k for k in d.iterdir() if k.is_dir()]
            for k in kids:
                if str(k.resolve()) not in claimed_paths:
                    out["unclaimed_folders"].append(str(k))
    return out


def load(path):
    return yaml.safe_load(pathlib.Path(path).read_text()) or {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["validate", "status"])
    ap.add_argument("--registry", default=str(LAYER / "registry.yaml"))
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    reg, versions = load(a.registry), layer_versions()
    errs = validate(reg, versions)
    if errs:
        for e in errs:
            print(f"  FAIL  {e}", file=sys.stderr)
        return 2
    if a.cmd == "validate":
        print(f"  ok    registry valid: {len(reg['projects'])} projects, layers {versions}")
        return 0

    rows = []
    for p in reg["projects"]:
        rows.append({"id": p["id"], "repo": p["repo"], "domain": p["domain"], "status": p["status"],
                     "remote": remote_state(p["repo"], a.offline), "local": local_state(p, versions)})
    cov = coverage(reg, a.offline)
    if a.json:
        print(json.dumps({"layers": versions, "projects": rows, "coverage": cov}, indent=2))
        return 0

    print(f"mission control — {len(rows)} projects · layers: "
          + ", ".join(f"{k} {v}" for k, v in versions.items()))
    fmt = "{:<22} {:<9} {:<10} {:<32} {:<40} {}"
    print(fmt.format("ID", "DOMAIN", "STATUS", "REMOTE", "LOCAL", "FLAGS"))
    for r in rows:
        rm, lc, flags = r["remote"], r["local"], []
        if rm["state"] == "ok":
            rtxt = f"{rm['visibility'][:4]} {rm['default_branch'] or '-'} {rm['pushed_at']}"
            if rm["archived"]: flags.append("archived")
            if rm["fork"]: flags.append("fork")
            if not rm["size_kb"]: flags.append("empty-repo")
        else:
            rtxt = rm["state"]
            if rm["state"] == "missing": flags.append("remote-missing")
        if lc["state"] == "ok":
            ltxt = f"{lc['branch']} {'dirty:' + str(lc['dirty']) if lc['dirty'] else 'clean'} {lc['last_commit']}"
            if not lc["origin_matches"]: flags.append(f"origin={lc['origin']}")
            if rm.get("default_branch") and lc["branch"] != rm["default_branch"]:
                flags.append("off-default-branch")
            if lc.get("manifest"):
                flags += [f"drift:{k} {v}" for k, v in lc["drift"].items()]
                if lc["exceptions"]: flags.append(f"exceptions:{lc['exceptions']}")
            elif r["status"] not in ("exception", "source"):
                flags.append("no-manifest")
        else:
            ltxt = lc["state"]
            if lc["state"] == "not-git": flags.append("local-not-a-clone")
            if lc["state"] == "none" and r["repo"]: flags.append("remote-only")
        if r["repo"] is None: flags.append("local-only")
        print(fmt.format(r["id"], r["domain"], r["status"], rtxt, ltxt, " ".join(flags)))
    print()
    if not a.offline:
        print(f"unregistered source repos in {', '.join(reg.get('watch_owners') or [])}: "
              + (", ".join(cov["unregistered_repos"]) or "none"))
    print("unclaimed folders under workspace root: " + (", ".join(cov["unclaimed_folders"]) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
