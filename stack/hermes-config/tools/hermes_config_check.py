#!/usr/bin/env python3
"""Render the hermes-config layer and prove its six invariants.

WHY THIS EXISTS
  A config layer that only describes a target is a wish. This tool renders the layer's templates
  into one complete config per profile and then checks the six invariants the layer promises. Every
  invariant has a negative control: a mutation of the layer that the check must REFUSE. A checker
  that only ever sees good input proves nothing, so `neg` runs the mutations and fails if any of
  them slips through.

WHY RENDER AT ALL
  Hermes has no config inheritance. A profile that omits a key resolves the SHIPPED default, not the
  root's value (measured: root agent.clarify_timeout=7200, a profile that omits it resolves 90). So
  "the root's value is inherited" is false on this harness, and the layer's own merge is what
  supplies the policy. Every profile therefore renders COMPLETE: root template first, role delta
  second, placeholders resolved from the lock.

USAGE
  hermes_config_check.py render --out DIR        # write one config + charter per profile
  hermes_config_check.py check [--json]          # run every invariant, exit 1 on any failure
  hermes_config_check.py neg                     # run every negative control, exit 1 if one slips
  hermes_config_check.py charter --role ROLE     # print one rendered charter

Exit codes: 0 = clean, 1 = a check failed, 2 = the layer cannot be read (missing file, bad YAML).
"""
from __future__ import annotations

import argparse
import copy
import json
import pathlib
import sys
from typing import Callable

import yaml

HERE = pathlib.Path(__file__).resolve().parent.parent
LOCK = HERE / "hermes-config.lock.yaml"
ROOT_TEMPLATE = HERE / "templates/root.config.yaml"
ROLE_DIR = HERE / "templates/roles"
DISPATCH_FILE = HERE / "templates/dispatch_profiles.yaml"
SOUL_TEMPLATE = HERE / "templates/soul/ROLE.md"

ROOT_PROFILE = "default"


class LayerError(Exception):
    """The layer cannot be read — not a failed invariant, a broken layer."""


# --------------------------------------------------------------------------- reading


def load_lock(path: pathlib.Path = LOCK) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001 - a broken layer must fail loudly, not traceback
        raise LayerError(f"{path.name}: {exc}") from exc
    if not isinstance(data, dict) or "pinned" not in data:
        raise LayerError(f"{path.name}: no `pinned:` block")
    return data


def pinned(lock: dict) -> dict:
    return lock["pinned"]


def _load_yaml(path: pathlib.Path) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001
        raise LayerError(f"{path.relative_to(HERE)}: {exc}") from exc
    return data if isinstance(data, dict) else {}


def deep_merge(base: dict, over: dict) -> dict:
    out = copy.deepcopy(base)
    for key, value in over.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


# --------------------------------------------------------------------------- rendering


def _sub(text: str, values: dict) -> str:
    """Resolve {{PLACEHOLDERS}}. A quoted placeholder takes a JSON value; a bare one takes text."""
    for key, value in values.items():
        quoted = '"{{%s}}"' % key
        if quoted in text:
            text = text.replace(quoted, json.dumps(value))
        bare = "{{%s}}" % key
        if bare in text:
            text = text.replace(bare, value if isinstance(value, str) else json.dumps(value))
    return text


def placeholders_in(text: str) -> list[str]:
    import re

    return sorted(set(re.findall(r"\{\{([A-Z_]+)\}\}", text)))


def _deny_globs(lock: dict, profile: dict) -> list[str]:
    """A profile names verbs; the layer owns the globs. Deny is the union of the named verbs."""
    verbs = pinned(lock).get("verbs") or {}
    globs: list[str] = []
    for verb in profile.get("approvals", {}).get("deny") or []:
        if verb not in verbs:
            raise LayerError(f"profile names an unknown verb {verb!r} (known: {sorted(verbs)})")
        for glob in verbs[verb]:
            if glob not in globs:
                globs.append(glob)
    return globs


def _values_for(lock: dict, name: str) -> dict:
    pin = pinned(lock)
    profiles = pin["profiles"]
    profile = profiles[name]
    policy = pin["model_policy"]
    providers = policy["providers"]
    provider = profile["model"]["provider"]
    if provider not in providers:
        raise LayerError(f"profile {name!r} uses undeclared provider {provider!r}")
    routing = pin.get("routing") or {}
    role = profile["role"]
    charter = (pin.get("charters") or {}).get(role) or {}
    client_ops = (routing.get("client_ops") or {}).get(name, "")
    # A bot's chat name is its profile id — the one name per thing rule. The root is the single
    # exception: its id cannot change, so its display name is presentation only and is declared in
    # identity.root rather than derived from the role.
    root = (pin.get("identity") or {}).get("root") or {}
    display_name = root.get("display_name") if name == ROOT_PROFILE else name
    return {
        "PROFILE": name,
        "ROLE": role,
        "MODEL_DEFAULT": profile["model"]["default"],
        "MODEL_PROVIDER": provider,
        "MODEL_BASE_URL": providers[provider]["base_url"],
        "MODEL_API_MODE": providers[provider].get("api_mode") or "",
        "DEEP_MODEL": policy["deep"]["model"],
        "DEEP_PROVIDER": policy["deep"]["provider"],
        "DEEP_EFFORT": policy["deep"]["reasoning_effort"],
        "APPROVALS_TIMEOUT": profile.get("approvals", {}).get("timeout", 300),
        "APPROVALS_DENY": _deny_globs(lock, profile),
        "PLUGINS": profile.get("plugins") or [],
        "MCP": _mcp_servers(lock, profile),
        "BWS_ENABLED": _bws_enabled(lock, name),
        "DISPATCH": _dispatch_list(lock),
        "ORCHESTRATOR": routing.get("orchestrator", ""),
        "DEFAULT_ASSIGNEE": routing.get("default_assignee", ""),
        "CLIENT_OPS_PROFILE": client_ops,
        "DISPLAY_NAME": display_name,
        "ONE_JOB": charter.get("one_job", ""),
        "MAY": charter.get("may", ""),
        "MAY_NOT": charter.get("may_not", ""),
        "ESCALATES_TO": charter.get("escalates_to", ""),
    }


def _mcp_servers(lock: dict, profile: dict) -> dict:
    """Render the profile's admitted MCP servers from the layer's single registry.

    Rendered as the dict Hermes expects (keyed by server name), not a list: a list would be a
    config shape Hermes silently ignores, which is the class of bug this layer exists to stop.
    """
    registry = pinned(lock).get("mcp_registry") or {}
    out: dict = {}
    for name in profile.get("mcp") or []:
        if name not in registry:
            raise LayerError(f"profile admits an unregistered MCP server {name!r}")
        out[name] = dict(registry[name])
    return out


def _bws_enabled(lock: dict, name: str) -> bool:
    secrets = pinned(lock).get("secrets") or {}
    sync = (secrets.get("bitwarden") or {}).get("sync_profiles") or []
    return name in sync


def _dispatch_list(lock: dict) -> list[str]:
    return list(pinned(lock).get("dispatch_profiles") or [])


def render_profile(lock: dict, name: str) -> dict:
    pin = pinned(lock)
    profile = pin["profiles"][name]
    role = profile["role"]
    role_path = ROLE_DIR / f"{role}.yaml"
    if not role_path.is_file():
        raise LayerError(f"role {role!r} has no template ({role_path.relative_to(HERE)})")
    values = _values_for(lock, name)
    text = _sub(ROOT_TEMPLATE.read_text(encoding="utf-8"), values)
    text = _sub(role_path.read_text(encoding="utf-8"), values)
    # role first would lose the merge; merge root + role in code, not in text order.
    base = yaml.safe_load(_sub(ROOT_TEMPLATE.read_text(encoding="utf-8"), values)) or {}
    delta = yaml.safe_load(text) or {}
    merged = deep_merge(base, delta)
    left = placeholders_in(yaml.safe_dump(merged))
    if left:
        raise LayerError(f"{name}: unrendered placeholders after merge: {left}")
    merged["role"] = role
    # A profile may declare its own deep tier; the checker refuses it unless it matches the policy.
    if profile.get("delegation"):
        merged["delegation"] = deep_merge(merged.get("delegation") or {}, profile["delegation"])
    # The model_map is a single definition: only the declared definer(s) render it, and it renders as
    # an inert one (backend stays `default`).
    model_map = (pin.get("model_policy") or {}).get("model_map") or {}
    definers = model_map.get("definer") or []
    if isinstance(definers, str):
        definers = [definers]
    if name in definers:
        delegation = merged.setdefault("delegation", {})
        backends = delegation.setdefault("backends", {})
        backends["backend"] = model_map.get("backend", "default")
        backends["model_map"] = copy.deepcopy(model_map.get("map") or {})
    return merged


def render_charter(lock: dict, name: str) -> str:
    """One charter per PROFILE, not per role: a chat profile's charter must name that profile."""
    if name not in pinned(lock)["profiles"]:
        raise LayerError(f"no profile named {name!r}")
    return _sub(SOUL_TEMPLATE.read_text(encoding="utf-8"), _values_for(lock, name))


def render_all(lock: dict) -> dict:
    return {name: render_profile(lock, name) for name in pinned(lock)["profiles"]}


# --------------------------------------------------------------------------- invariants


def _has_path(node, dotted: str) -> bool:
    """True when a dotted key exists in the structure, whatever its value's type."""
    current = node
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            return False
        current = current[part]
    return True


def _flat(node, prefix=()) -> list[str]:
    keys: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            keys.extend(_flat(value, prefix + (str(key),)))
    else:
        keys.append(".".join(prefix))
    return keys


def inv_one_name_per_thing(lock: dict, rendered: dict) -> list[str]:
    """Every registry name resolves to a live profile id; only the root may split id and name."""
    pin = pinned(lock)
    problems: list[str] = []
    profiles = pin["profiles"]
    dispatch = pin.get("dispatch_profiles") or []

    for name in dispatch:
        if name not in profiles:
            problems.append(f"dispatch_profiles names {name!r}, which is not a profile in the layer")
    for name, profile in profiles.items():
        if profile.get("dispatch") and name not in dispatch:
            problems.append(f"profile {name!r} is dispatch:true but missing from dispatch_profiles")
        if not profile.get("dispatch") and name in dispatch:
            problems.append(f"profile {name!r} is dispatch:false but present in dispatch_profiles")

    file_list = _load_yaml(DISPATCH_FILE).get("dispatch_profiles") or []
    if file_list != dispatch:
        problems.append(
            f"templates/dispatch_profiles.yaml ({len(file_list)} names) disagrees with the lock "
            f"({len(dispatch)} names): {sorted(set(file_list) ^ set(dispatch))}"
        )

    for name, profile in profiles.items():
        role = profile.get("role")
        if not (ROLE_DIR / f"{role}.yaml").is_file():
            problems.append(f"profile {name!r} has role {role!r} with no template")
        if role not in (pin.get("charters") or {}):
            problems.append(f"profile {name!r} has role {role!r} with no charter")

    root = (pin.get("identity") or {}).get("root") or {}
    if not root.get("display_name"):
        problems.append("identity.root.display_name is empty — the root's chat name is undeclared")
    for name in profiles:
        # The charter is the bot's own name statement; if it introduces itself as something else,
        # the chat name and the profile id have split — the failure that made dispatch skip cards.
        charter = render_charter(lock, name)
        first = charter.splitlines()[0].lstrip("# ").strip() if charter.strip() else ""
        want = root.get("display_name") if name == ROOT_PROFILE else name
        if first != want:
            problems.append(
                f"profile {name!r} charter introduces itself as {first!r}, expected {want!r}"
            )
    return problems


def inv_no_secrets_in_harness_env(lock: dict, rendered: dict) -> list[str]:
    """No worker profile syncs a secret store; a DATABASE_URL canary is refused, not merely absent."""
    pin = pinned(lock)
    problems: list[str] = []
    secrets = pin.get("secrets") or {}
    bws = secrets.get("bitwarden") or {}
    sync = bws.get("sync_profiles") or []
    refuse = bws.get("refuse_always") or []

    for name in sync:
        if name not in pin["profiles"]:
            problems.append(f"secrets sync_profiles names {name!r}, which is not a profile")
    for name in pin["profiles"]:
        enabled = _bws_enabled(lock, name)
        if enabled and name not in sync:
            problems.append(f"profile {name!r} would sync secrets but is not in sync_profiles")
        if not enabled and name in sync:
            problems.append(f"profile {name!r} is in sync_profiles but renders bitwarden disabled")
        if enabled and pin["profiles"][name].get("role") in ("client", "client-ops", "github", "infra"):
            problems.append(
                f"profile {name!r} ({pin['profiles'][name]['role']}) syncs secrets — a worker profile "
                "must never inject a repo's runtime config"
            )

    canary = bws.get("canary")
    if not canary:
        problems.append("secrets.bitwarden.canary is empty — the refusal control is not declared")
    elif canary not in [r for r in refuse if r == canary]:
        problems.append(f"canary {canary!r} is not in refuse_always — nothing would refuse it")
    for pattern in refuse:
        if pattern == ".*" or pattern == "*":
            problems.append(f"refuse_always carries a match-everything pattern {pattern!r}")

    for name, config in rendered.items():
        flag = ((config.get("secrets") or {}).get("bitwarden") or {}).get("enabled")
        if flag is True and name not in sync:
            problems.append(f"rendered {name}: secrets.bitwarden.enabled is true")
        if flag is None:
            problems.append(f"rendered {name}: secrets.bitwarden.enabled is absent, not false")
    return problems


def inv_closable_cards(lock: dict, rendered: dict) -> list[str]:
    """A merge card has an assignee that holds the verb; a tag is still not a card outcome."""
    pin = pinned(lock)
    problems: list[str] = []
    profiles = pin["profiles"]
    verbs = pin.get("verbs") or {}
    merge_globs = verbs.get("merge") or []
    if not merge_globs:
        problems.append("verbs.merge is empty — the merge verb has no globs to hold or deny")

    capable = [n for n, p in profiles.items() if p.get("merge_capable")]
    if not capable:
        problems.append("no profile is merge_capable — a merge card can never be closed by its assignee")
    for name in capable:
        if not profiles[name].get("dispatch"):
            problems.append(f"merge_capable profile {name!r} is not dispatchable, so no card can reach it")
        deny = _deny_globs(lock, profiles[name])
        hit = [g for g in merge_globs if g in deny]
        if hit:
            problems.append(f"merge_capable profile {name!r} denies its own merge verb: {hit}")
    for name, profile in profiles.items():
        if profile.get("merge_capable"):
            continue
        deny = _deny_globs(lock, profile)
        if not all(g in deny for g in merge_globs):
            problems.append(
                f"profile {name!r} ({profile.get('role')}) is not merge_capable but does not deny "
                "the merge verb — a merge card could be assigned to it and could never close"
            )

    verification = pin.get("verification") or {}
    if verification.get("tag_is_not_a_card_outcome") is not True:
        problems.append("verification.tag_is_not_a_card_outcome is not true — a tag would be a card outcome")

    for name, config in rendered.items():
        if name == "release":
            continue
        allow = ((config.get("verification") or {}).get("contract")) or []
        if "tag" in allow:
            problems.append(f"rendered {name}: a tag is listed as a completion contract")
    return problems


def inv_verification_is_measurable(lock: dict, rendered: dict) -> list[str]:
    """Contracts verify on PR + tests + CI; a 403 rules read is not a failure."""
    pin = pinned(lock)
    problems: list[str] = []
    verification = pin.get("verification") or {}
    contract = verification.get("contract") or []
    want = {"pr_state", "tests", "ci_exact_head"}
    missing = want - set(contract)
    if missing:
        problems.append(f"verification.contract is missing {sorted(missing)}")
    for entry in contract:
        if "rule" in str(entry).lower() or "branch" in str(entry).lower():
            problems.append(f"verification.contract lists {entry!r} — a branch-rules read is identity-fragile")
    if verification.get("rules_read") != "not_a_failure":
        problems.append(
            "verification.rules_read is not 'not_a_failure' — a 403 on a private repo would fail a "
            "technically-correct card"
        )
    if not verification.get("rules_read_reason"):
        problems.append("verification.rules_read_reason is empty — the policy has no stated reason")
    return problems


def inv_one_model_policy(lock: dict, rendered: dict) -> list[str]:
    """One model_map at the root; a profile that restates a root key fails the checker."""
    pin = pinned(lock)
    problems: list[str] = []
    policy = pin.get("model_policy") or {}
    keys = policy.get("policy_keys") or []
    if policy.get("source") != ROOT_PROFILE:
        problems.append(f"model_policy.source is {policy.get('source')!r}, not the root profile")
    if not keys:
        problems.append("model_policy.policy_keys is empty")

    definer = (policy.get("model_map") or {}).get("definer")
    definers = [definer] if isinstance(definer, str) else list(definer or [])
    if not definers:
        problems.append("model_policy.model_map.definer is empty — a second definer would go undetected")
    elif len(definers) > 1:
        problems.append(f"model_map has {len(definers)} definers {definers} — one definition only")
    for name in definers:
        if name not in pin["profiles"]:
            problems.append(f"model_map.definer {name!r} is not a profile")

    managed = [n for n in pin["profiles"] if n not in (policy.get("unmanaged") or [])]
    for name in managed:
        config = rendered.get(name) or {}
        maps = _find_model_maps(config)
        if name in definers:
            if not maps:
                problems.append(f"declared model_map definer {name!r} renders no model_map")
        elif maps:
            problems.append(f"profile {name!r} restates a model_map at {maps} — only {definers} may")

    deep = policy.get("deep") or {}
    for name in managed:
        config = rendered.get(name) or {}
        if name in (policy.get("exempt") or []):
            continue
        delegation = config.get("delegation") or {}
        for key in ("model", "provider", "reasoning_effort"):
            if delegation.get(key) != deep.get(key):
                problems.append(
                    f"profile {name!r} delegation.{key} is {delegation.get(key)!r}, not the root's "
                    f"{deep.get(key)!r}"
                )
    return problems


def _find_model_maps(node, prefix=()) -> list[str]:
    found: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "model_map":
                found.append(".".join(prefix + (str(key),)))
            else:
                found.extend(_find_model_maps(value, prefix + (str(key),)))
    return found


def inv_nothing_inherited_by_accident(lock: dict, rendered: dict) -> list[str]:
    """Hermes has no config inheritance, so every profile must render complete."""
    pin = pinned(lock)
    problems: list[str] = []
    base_keys = set(_flat(yaml.safe_load(ROOT_TEMPLATE.read_text(encoding="utf-8")) or {}))
    if not base_keys:
        problems.append("templates/root.config.yaml renders no keys")

    # The pin is the baseline, not the template: a template that loses a key would otherwise lose it
    # from both sides of the comparison and pass. Comparing against the pin catches the loss.
    pinned_keys = set(pin.get("root_keys") or [])
    if not pinned_keys:
        problems.append("pinned.root_keys is empty — nothing pins the completeness baseline")
    dropped = sorted(pinned_keys - base_keys)
    added = sorted(base_keys - pinned_keys)
    if dropped:
        problems.append(f"templates/root.config.yaml no longer defines pinned key(s): {dropped}")
    if added:
        problems.append(f"templates/root.config.yaml defines unpinned key(s): {added} — re-pin root_keys")

    for name in pin["profiles"]:
        config = rendered.get(name)
        if config is None:
            problems.append(f"profile {name!r} renders nothing")
            continue
        # Path presence, not leaf enumeration: a pinned key whose value is a dict (mcp_servers) has no
        # leaf of its own name, so a flat-set comparison would report a complete profile as short.
        missing = sorted(key for key in pinned_keys if not _has_path(config, key))
        if missing:
            problems.append(f"profile {name!r} renders {len(missing)} key(s) short: {missing}")

    facts = [d.get("id") for d in (lock.get("depends_on") or [])]
    if "no-config-inheritance" not in facts:
        problems.append("depends_on does not declare the no-config-inheritance measurement")
    for fact in lock.get("depends_on") or []:
        if fact.get("id") == "no-config-inheritance":
            if not fact.get("measured"):
                problems.append("no-config-inheritance has no measured value")
            if not fact.get("check"):
                problems.append("no-config-inheritance has no reproducible check")
    return problems


INVARIANTS = [
    ("one-name-per-thing", inv_one_name_per_thing),
    ("no-secrets-in-harness-env", inv_no_secrets_in_harness_env),
    ("closable-cards", inv_closable_cards),
    ("verification-is-measurable", inv_verification_is_measurable),
    ("one-model-policy", inv_one_model_policy),
    ("nothing-inherited-by-accident", inv_nothing_inherited_by_accident),
]


def run_checks(lock: dict | None = None) -> list[tuple[str, list[str]]]:
    lock = lock or load_lock()
    rendered = render_all(lock)
    return [(name, fn(lock, rendered)) for name, fn in INVARIANTS]


# --------------------------------------------------------------------------- negative controls
# Each mutation is a small, plausible mistake. The check must REFUSE it. A control that passes means
# the invariant is decorative, which is worse than absent — it reads as a guarantee.
def _mutations(lock: dict) -> list[tuple[str, str, Callable[[dict], None]]]:
    out: list[tuple[str, str, Callable[[dict], None]]] = []
    return out + [
        (
            "one-name-per-thing",
            "a dispatch entry names a profile that does not exist",
            lambda L: pinned(L)["dispatch_profiles"].append("rio"),
        ),
        (
            "one-name-per-thing",
            "a profile is added to the layer but not to the dispatch allow-list",
            lambda L: pinned(L)["profiles"].update(
                ghost=dict(pinned(L)["profiles"]["kestrel"], dispatch=True)
            ),
        ),
        (
            "no-secrets-in-harness-env",
            "a worker profile is added to the secret sync",
            lambda L: pinned(L)["secrets"]["bitwarden"]["sync_profiles"].append("alignsynch-ops"),
        ),
        (
            "no-secrets-in-harness-env",
            "the DATABASE_URL canary is dropped from the refuse list",
            lambda L: pinned(L)["secrets"]["bitwarden"]["refuse_always"].remove("DATABASE_URL"),
        ),
        (
            "closable-cards",
            "no profile holds the merge verb",
            lambda L: [p.update(merge_capable=False) for p in pinned(L)["profiles"].values()],
        ),
        (
            "closable-cards",
            "a worker profile stops denying the merge verb",
            lambda L: pinned(L)["profiles"]["ase-github"]["approvals"].update(deny=[]),
        ),
        (
            "verification-is-measurable",
            "the contract falls back to a branch-rules read",
            lambda L: pinned(L)["verification"].update(contract=["pr_state", "branch_rules"]),
        ),
        (
            "verification-is-measurable",
            "a rules read is treated as a failure",
            lambda L: pinned(L)["verification"].update(rules_read="fails"),
        ),
        (
            "one-model-policy",
            "a second profile is declared as a model_map definer",
            lambda L: pinned(L)["model_policy"]["model_map"].update(definer=["rio-hps", "infra"]),
        ),
        (
            "one-model-policy",
            "a managed profile drifts its deep tier",
            lambda L: pinned(L)["profiles"]["infra"].update(delegation={"model": "gpt-x"}),
        ),
        (
            "nothing-inherited-by-accident",
            "the root template drops a key a profile would then inherit by accident",
            lambda L: None,  # handled by the template mutation below
        ),
    ]  # type: ignore[return-value]


def run_negative_controls() -> list[tuple[str, str, bool]]:
    """Return (invariant, mutation, refused). A False means the check let the mutation through."""
    results: list[tuple[str, str, bool]] = []
    base = load_lock()
    for invariant, label, mutate in _mutations(base):
        if label.startswith("the root template drops"):
            continue
        trial = copy.deepcopy(base)
        mutate(trial)
        try:
            problems = dict(run_checks(trial)).get(invariant) or []
        except LayerError as exc:
            problems = [f"layer refused to render: {exc}"]
        results.append((invariant, label, bool(problems)))

    # Invariant 6's control cannot live in the lock: the failure mode is a TEMPLATE that renders
    # short. Drop a key from the root template in a scratch copy and prove the completeness check
    # catches it.
    trial = copy.deepcopy(base)
    global ROOT_TEMPLATE  # noqa: PLW0603 - the control must exercise the real renderer
    original = ROOT_TEMPLATE
    scratch: pathlib.Path | None = None
    try:
        scratch = pathlib.Path(original).with_suffix(".neg.yaml")
        text = original.read_text(encoding="utf-8")
        text = text.replace("  nudge_interval: 10\n", "")
        scratch.write_text(text, encoding="utf-8")
        ROOT_TEMPLATE = scratch
        problems = dict(run_checks(trial)).get("nothing-inherited-by-accident") or []
        results.append(
            ("nothing-inherited-by-accident", "the root template drops a key profiles rely on", bool(problems))
        )
    finally:
        ROOT_TEMPLATE = original
        if scratch is not None:
            try:
                scratch.unlink()
            except OSError:
                pass

    # Invariant 1's name control: the charter template hardcodes a name instead of the profile's.
    # A bot that introduces itself as "Lead" on every profile is exactly the display-name/id split.
    trial = copy.deepcopy(base)
    global SOUL_TEMPLATE  # noqa: PLW0603 - the control must exercise the real renderer
    original_soul = SOUL_TEMPLATE
    soul_scratch: pathlib.Path | None = None
    try:
        soul_scratch = pathlib.Path(original_soul).with_suffix(".neg.md")
        soul_scratch.write_text(
            original_soul.read_text(encoding="utf-8").replace("{{DISPLAY_NAME}}", "Lead"),
            encoding="utf-8",
        )
        SOUL_TEMPLATE = soul_scratch
        problems = dict(run_checks(trial)).get("one-name-per-thing") or []
        results.append(("one-name-per-thing", "the charter template hardcodes a bot name", bool(problems)))
    finally:
        SOUL_TEMPLATE = original_soul
        if soul_scratch is not None:
            try:
                soul_scratch.unlink()
            except OSError:
                pass
    return results


# --------------------------------------------------------------------------- cli


def cmd_render(args) -> int:
    lock = load_lock()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    written = 0
    for name in pinned(lock)["profiles"]:
        config = render_profile(lock, name)
        target = out / f"{name}.config.yaml"
        target.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
        written += 1
    for name in pinned(lock)["profiles"]:
        (out / f"{name}.SOUL.md").write_text(render_charter(lock, name), encoding="utf-8")
    print(f"render: {written} config(s) + {written} charter(s) -> {out}")
    return 0


def cmd_check(args) -> int:
    try:
        results = run_checks()
    except LayerError as exc:
        print(f"check: layer unreadable: {exc}", file=sys.stderr)
        return 2
    failed = 0
    for name, problems in results:
        if problems:
            failed += 1
            print(f"  FAIL  {name}")
            for problem in problems:
                print(f"          {problem}")
        else:
            print(f"  ok    {name}")
    if args.json:
        print(json.dumps({"invariants": [{"id": n, "problems": p} for n, p in results]}, indent=2))
    return 1 if failed else 0


def cmd_neg(args) -> int:
    try:
        results = run_negative_controls()
    except LayerError as exc:
        print(f"neg: layer unreadable: {exc}", file=sys.stderr)
        return 2
    slipped = 0
    for invariant, label, refused in results:
        if refused:
            print(f"  ok    {invariant}: refused — {label}")
        else:
            slipped += 1
            print(f"  FAIL  {invariant}: ACCEPTED — {label}")
    if slipped:
        print(f"neg: {slipped} mutation(s) slipped through", file=sys.stderr)
    return 1 if slipped else 0


def cmd_charter(args) -> int:
    print(render_charter(load_lock(), args.profile), end="")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__ and "render and verify the hermes-config layer")
    sub = ap.add_subparsers(dest="command", required=True)
    p_render = sub.add_parser("render", help="render one config and charter per profile")
    p_render.add_argument("--out", required=True)
    p_render.set_defaults(func=cmd_render)
    p_check = sub.add_parser("check", help="run every invariant")
    p_check.add_argument("--json", action="store_true")
    p_check.set_defaults(func=cmd_check)
    p_neg = sub.add_parser("neg", help="run every negative control")
    p_neg.set_defaults(func=cmd_neg)
    p_charter = sub.add_parser("charter", help="print one rendered charter")
    p_charter.add_argument("--profile", required=True)
    p_charter.set_defaults(func=cmd_charter)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
