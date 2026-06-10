#!/usr/bin/env python3
"""OrbGuard client <-> server API contract gate.

Cross-checks every endpoint the Flutter app can call against every route the
orbguard.lab backend actually registers.

App-side sources (the only places endpoint paths are defined):
  * lib/services/api/api_config.dart   - ApiEndpoints constants and
    path-builder functions. The HTTP verb is taken from the doc comment
    ("/// GET /api/v1/...") directly above each declaration.
  * lib/services/api/orbguard_api_client.dart - literal paths passed to
    _dio.get/post/put/delete/patch (including string interpolations such as
    '${ApiConfig.apiVersion}/vpn/status' and '${ApiEndpoints.forensics}/...').
    The verb of the dio call wins over the doc-comment verb.

Backend-side source:
  * orbguard.lab/internal/api/router.go - chi Route/Group nesting plus
    Get/Post/Put/Delete/Patch registrations, and the ScamDetection
    RegisterRoutes(api) block in handlers/scam_detection.go.

String-interpolation segments ($id / ${...}) and chi path params ({id}) are
both normalized to "{param}" before comparison.

Output:
  (a) app calls with no matching backend route  -> FAIL (exit 1) unless the
      call is in the WAVE4_PENDING allowlist below.
  (b) backend routes the app never calls        -> informational only.

Usage:
  python3 tools/check_api_contract.py [--lab-root PATH]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LAB_ROOT = Path("/Users/nima/Developments/orbguard.lab")

API_CONFIG = APP_ROOT / "lib" / "services" / "api" / "api_config.dart"
API_CLIENT = APP_ROOT / "lib" / "services" / "api" / "orbguard_api_client.dart"

HTTP_VERBS = ("GET", "POST", "PUT", "DELETE", "PATCH")

# ---------------------------------------------------------------------------
# WAVE4_PENDING: app calls that are known to have no backend route yet.
# Wave 4 ("Missing endpoints + routing") either adds the route or retires the
# client method. Entries are "<VERB> <normalized path>" with path params
# written as {param}. Remove entries here as Wave 4 lands them so the gate
# starts enforcing them.
# ---------------------------------------------------------------------------
WAVE4_PENDING = {
    # =======================================================================
    # Wave-6 reconciliation status:
    #   - LAB landed live routes for GET mitre/navigator/export,
    #     GET enterprise/policies and GET enterprise/compliance/controls,
    #     so those entries were pruned (the gate now enforces them).
    #   - LAB declared the remaining 11 enterprise calls below as
    #     intentionally unregistered ("client must retire"); the consuming
    #     UI (enterprise screens/providers/policy_management_service) is
    #     still in place, so the entries stay allowlisted until the
    #     enterprise UI retirement lands. Retire the client methods and
    #     these entries together.
    # =======================================================================
    # --- enterprise routes LAB declared client-must-retire ---
    "GET /api/v1/enterprise/events",
    "GET /api/v1/enterprise/devices",
    "POST /api/v1/enterprise/policies/{param}/assign-groups",
    "POST /api/v1/enterprise/policies/{param}/assign-devices",
    "POST /api/v1/enterprise/policies/{param}/unassign",
    "POST /api/v1/enterprise/devices/{param}/evaluate-compliance",
    "POST /api/v1/enterprise/byod/enroll",
    "GET /api/v1/enterprise/byod/{param}/status",
    "POST /api/v1/enterprise/byod/{param}/unenroll",
    "GET /api/v1/enterprise/devices/{param}/ownership",
    "POST /api/v1/enterprise/devices/{param}/ownership",
}

# Constants in ApiEndpoints that are base paths used only for composing
# longer paths (never called on their own). 'forensics'/'privacy'/'scam' are
# auto-detected from '${ApiEndpoints.x}' usage in the client; 'devices'
# ('/api/v1/device') is a base path with no direct route (real routes nest
# under it: /device/register, /device/{id}/..., etc.).
BASE_PATH_CONSTANTS = {"devices"}


def normalize(path: str) -> str:
    """Normalize a path for comparison: collapse params, strip trailing /."""
    if len(path) > 1 and path.endswith("/"):
        path = path.rstrip("/")
    segments = path.split("/")
    out = []
    for seg in segments:
        if "{" in seg or "}" in seg:
            out.append("{param}")
        else:
            out.append(seg)
    return "/".join(out)


def dart_path_to_template(raw: str) -> str:
    """Convert a Dart string (with interpolation) to a path template."""
    raw = raw.replace("$_v1", "/api/v1")
    raw = raw.replace("${ApiConfig.apiVersion}", "/api/v1")
    raw = re.sub(r"\$\{[^}]*\}", "{param}", raw)
    raw = re.sub(r"\$[A-Za-z_]\w*", "{param}", raw)
    return normalize(raw)


# ---------------------------------------------------------------------------
# App side: api_config.dart
# ---------------------------------------------------------------------------

def parse_api_config(text: str):
    """Returns (entries, const_values).

    entries: list of (name, verbs:set[str], template). verbs may be empty
             when no doc-comment verb was found (matches any method).
    const_values: name -> raw path string (for resolving ${ApiEndpoints.x}
                  interpolation in the client).
    """
    # Only the ApiEndpoints class declares endpoints; ApiConfig holds the
    # base URL / version prefix, which is not itself a callable endpoint.
    class_start = text.index("class ApiEndpoints")
    lines = text.splitlines()
    entries = []
    const_values = {}

    decl_re = re.compile(
        r"static\s+(?:const\s+String|String)\s+(\w+)\s*(?:\([^)]*\))?\s*(?:=>?|=)\s*'([^']+)';"
    )
    # Anchored so prose like "NOTE: live route is POST /x" never matches.
    verb_re = re.compile(
        r"^\s*///\s*((?:GET|POST|PUT|DELETE|PATCH)(?:/(?:GET|POST|PUT|DELETE|PATCH))*)\s+/"
    )

    # Map character offset -> line index for doc-comment lookup.
    offsets = []
    pos = 0
    for i, line in enumerate(lines):
        offsets.append(pos)
        pos += len(line) + 1

    def line_of(offset: int) -> int:
        lo, hi = 0, len(offsets) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if offsets[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo

    for m in decl_re.finditer(text):
        if m.start() < class_start:
            continue
        name, raw = m.group(1), m.group(2)
        if not raw.startswith(("$_v1", "/", "${ApiConfig.apiVersion}")):
            continue  # not an endpoint path (e.g. baseUrl fragments)
        is_function = "(" in text[m.start(): text.index(name, m.start()) + len(name) + 30] and \
            re.match(r"static\s+String\s+\w+\s*\(", m.group(0)) is not None
        template = dart_path_to_template(raw)
        if not is_function:
            const_values[name] = raw

        # Collect verbs from the doc comment block immediately above.
        verbs: set[str] = set()
        li = line_of(m.start()) - 1
        while li >= 0 and lines[li].lstrip().startswith("///"):
            vm = verb_re.match(lines[li])
            if vm:
                verbs.update(vm.group(1).split("/"))
            li -= 1

        entries.append((name, verbs, template))

    return entries, const_values


# ---------------------------------------------------------------------------
# App side: orbguard_api_client.dart
# ---------------------------------------------------------------------------

def extract_first_arg(text: str, start: int) -> str:
    """Extract the first argument of a call whose '(' is at text[start]."""
    depth = 0
    i = start
    in_str = False
    arg_start = start + 1
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "'" and text[i - 1] != "\\":
                in_str = False
        elif c == "'":
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[arg_start:i].strip()
        elif c == "," and depth == 1:
            return text[arg_start:i].strip()
        i += 1
    raise ValueError("unbalanced call expression in client file")


def parse_client_calls(text: str, const_values: dict, function_templates: dict):
    """Returns (calls, interpolation_bases, skipped).

    calls: set of (verb, normalized template)
    interpolation_bases: ApiEndpoints constant names used as '${ApiEndpoints.x}'
    skipped: count of dio calls whose path is a plain variable (the generic
             get/post helpers) - these are covered by the api_config entries.
    """
    calls = set()
    skipped = 0
    bases = set(re.findall(r"\$\{ApiEndpoints\.(\w+)\}", text))

    for m in re.finditer(r"_dio\s*\.\s*(get|post|put|delete|patch)\b", text):
        verb = m.group(1).upper()
        paren = text.find("(", m.end())
        if paren == -1:
            continue
        # Skip generic type args: _dio.get<Map<String, dynamic>>(
        between = text[m.end():paren]
        if between.strip() and not re.fullmatch(r"\s*<[^(]*>\s*", between):
            continue
        arg = extract_first_arg(text, paren)

        if arg.startswith("'"):
            raw = arg.strip("'")
            for cname, cval in const_values.items():
                raw = raw.replace("${ApiEndpoints.%s}" % cname, cval)
            calls.add((verb, dart_path_to_template(raw)))
        else:
            fm = re.match(r"ApiEndpoints\.(\w+)\s*\(", arg)
            cm = re.fullmatch(r"ApiEndpoints\.(\w+)", arg)
            if fm and fm.group(1) in function_templates:
                calls.add((verb, function_templates[fm.group(1)]))
            elif cm and cm.group(1) in const_values:
                calls.add((verb, dart_path_to_template(const_values[cm.group(1)])))
            else:
                skipped += 1  # variable path (generic helper) or unknown expr
    return calls, bases, skipped


# ---------------------------------------------------------------------------
# Backend side: chi router parsing
# ---------------------------------------------------------------------------

ROUTE_RE = re.compile(r'(\w+)\.Route\(\s*"([^"]*)"\s*,\s*func\(\s*(\w+)\s+chi\.Router\s*\)')
GROUP_RE = re.compile(r'(\w+)\.Group\(\s*func\(\s*(\w+)\s+chi\.Router\s*\)')
METHOD_RE = re.compile(r'(\w+)\.(Get|Post|Put|Delete|Patch)\(\s*"([^"]*)"')
REGISTER_RE = re.compile(r'\.RegisterRoutes\(\s*(\w+)\s*\)')


def parse_chi(lines, initial_vars, lab_root: Path, follow_registers=True):
    """Parse chi route registrations from Go source lines.

    initial_vars: dict varname -> path prefix for top-level router vars.
    Returns set of (VERB, normalized path).
    """
    routes = set()
    depth = 0
    stack = []  # (varname, prefix, open_depth)

    def resolve(var: str):
        for name, prefix, _ in reversed(stack):
            if name == var:
                return prefix
        return initial_vars.get(var)

    for line in lines:
        stripped = line.split("//")[0]

        mm = METHOD_RE.search(stripped)
        if mm:
            prefix = resolve(mm.group(1))
            if prefix is not None:
                routes.add((mm.group(2).upper(), normalize(prefix + mm.group(3))))

        rm = ROUTE_RE.search(stripped)
        if rm:
            prefix = resolve(rm.group(1))
            if prefix is not None:
                stack.append((rm.group(3), prefix + rm.group(2), depth))

        gm = GROUP_RE.search(stripped)
        if gm:
            prefix = resolve(gm.group(1))
            if prefix is not None:
                stack.append((gm.group(2), prefix, depth))

        if follow_registers:
            regm = REGISTER_RE.search(stripped)
            if regm:
                prefix = resolve(regm.group(1))
                if prefix is not None:
                    routes |= parse_register_routes(lab_root, prefix)

        depth += stripped.count("{") - stripped.count("}")
        while stack and depth <= stack[-1][2]:
            stack.pop()

    return routes


def parse_register_routes(lab_root: Path, prefix: str):
    """Parse handler-owned RegisterRoutes(r chi.Router) blocks.

    Today only ScamDetectionHandler defines one (mounted on the /api/v1
    router); scan all handler files for RegisterRoutes definitions so new
    ones are picked up automatically.
    """
    routes = set()
    handlers_dir = lab_root / "internal" / "api" / "handlers"
    for go_file in sorted(handlers_dir.glob("*.go")):
        text = go_file.read_text()
        m = re.search(r"func \(\w+ \*\w+\) RegisterRoutes\(\s*(\w+)\s+chi\.Router\s*\)\s*\{", text)
        if not m:
            continue
        # Take the function body (balanced braces from the opening brace).
        start = text.index("{", m.start())
        depth = 0
        end = start
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = text[start: end + 1]
        routes |= parse_chi(body.splitlines(), {m.group(1): prefix}, lab_root,
                            follow_registers=False)
    return routes


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

def path_matches(app_path: str, route_path: str) -> bool:
    """App segment matching: a literal matches a literal or a route param; an
    app param matches only a route param (an arbitrary client value would 404
    against a literal route segment)."""
    a, b = app_path.split("/"), route_path.split("/")
    if len(a) != len(b):
        return False
    for sa, sb in zip(a, b):
        if sb == "{param}":
            continue
        if sa == "{param}" or sa != sb:
            return False
    return True


def call_matched(verb: str, path: str, routes) -> bool:
    for rverb, rpath in routes:
        if path_matches(path, rpath) and (verb == "ANY" or verb == rverb):
            return True
    return False


def route_called(rverb: str, rpath: str, app_calls) -> bool:
    for verb, path in app_calls:
        if path_matches(path, rpath) and (verb == "ANY" or verb == rverb):
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--lab-root", type=Path, default=DEFAULT_LAB_ROOT,
                    help="Path to the orbguard.lab repository")
    args = ap.parse_args()

    router_go = args.lab_root / "internal" / "api" / "router.go"
    for f in (API_CONFIG, API_CLIENT, router_go):
        if not f.exists():
            print(f"ERROR: required file not found: {f}", file=sys.stderr)
            return 2

    config_text = API_CONFIG.read_text()
    client_text = API_CLIENT.read_text()

    entries, const_values = parse_api_config(config_text)
    function_templates = {
        name: template for (name, _verbs, template) in entries
        if name not in const_values
    }
    client_calls, bases, skipped = parse_client_calls(
        client_text, const_values, function_templates)

    # Build the full app-call inventory.
    app_calls = set(client_calls)
    excluded_bases = bases | BASE_PATH_CONSTANTS
    for name, verbs, template in entries:
        if name in excluded_bases:
            continue
        if verbs:
            for v in verbs:
                app_calls.add((v, template))
        else:
            app_calls.add(("ANY", template))

    backend_routes = parse_chi(
        router_go.read_text().splitlines(), {"router": ""}, args.lab_root)

    # (a) app calls with no backend route
    missing = sorted(
        (verb, path) for (verb, path) in app_calls
        if not call_matched(verb, path, backend_routes)
    )
    allowlisted = [(v, p) for (v, p) in missing if f"{v} {p}" in WAVE4_PENDING]
    failures = [(v, p) for (v, p) in missing if f"{v} {p}" not in WAVE4_PENDING]

    # (b) backend routes never called (informational)
    uncalled = sorted(
        (rv, rp) for (rv, rp) in backend_routes
        if not route_called(rv, rp, app_calls)
    )

    unused_allowlist = sorted(
        e for e in WAVE4_PENDING
        if e not in {f"{v} {p}" for (v, p) in missing}
    )

    print(f"App endpoint inventory : {len(app_calls)} calls "
          f"({len(entries)} api_config entries, {len(client_calls)} client "
          f"literals, {skipped} variable-path dio calls skipped)")
    print(f"Backend routes         : {len(backend_routes)}")
    print()

    print(f"== (a) App calls with NO backend route: {len(missing)} "
          f"({len(allowlisted)} allowlisted WAVE4_PENDING, "
          f"{len(failures)} FAILURES) ==")
    for v, p in allowlisted:
        print(f"  PENDING  {v:7s} {p}")
    for v, p in failures:
        print(f"  FAILURE  {v:7s} {p}")
    print()

    print(f"== (b) Backend routes never called by the app (informational): "
          f"{len(uncalled)} ==")
    for v, p in uncalled:
        print(f"  unused   {v:7s} {p}")
    print()

    if unused_allowlist:
        print("== WAVE4_PENDING entries that no longer appear as mismatches "
              "(candidates for removal): ==")
        for e in unused_allowlist:
            print(f"  stale    {e}")
        print()

    if failures:
        print(f"CONTRACT GATE: FAIL ({len(failures)} unallowlisted mismatches)")
        return 1
    print("CONTRACT GATE: PASS (all mismatches are documented WAVE4_PENDING)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
