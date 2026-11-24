#!/bin/sh
# Ground truth for realm-npm: every figure this realm reports, re-read from npm and deps.dev
# directly, required to agree EXACTLY, plus what a narrow question costs. Exits nonzero on any
# failure; the last line on success is `ALL CHECKS PASS`.
#
#   APPLIANCE=http://127.0.0.1:11043 AUTH=user:pass sh tests/verify.sh
#
# Environment: APPLIANCE (the appliance base URL) and AUTH (user:pass). The sources are open and
# keyless — api.npmjs.org, registry.npmjs.org, api.deps.dev — so no source key is needed. The
# GitHub producers are not exercised (no view reads them, and GitHub's keyless limit is 60/hour).
#
#   L0  seed: the tracked packages exist as NpmPackage (created through the code door if absent,
#       exactly as the README tells a user to), so the unpinned views have something to read.
#   L1  every view answers BY NAME on its defaults, without an error.
#   L2  figures against the sources: last-week downloads, the latest version (a scoped name
#       included, which only works when the key is not split on its slash), the direct dependency
#       set of one resolved version, and one package's publishers.
#   L3  cost: a single package read FRESH is one source call; the same read warm is none; a name
#       npm does not know is asked once and then remembered (negativeTtlSeconds).
set -e
: "${APPLIANCE:?set APPLIANCE (the appliance base URL)}"
: "${AUTH:?set AUTH (user:pass)}"
export APPLIANCE AUTH
python3 - <<'PY'
import base64, json, os, sys, urllib.error, urllib.parse, urllib.request

APP = os.environ["APPLIANCE"].rstrip("/")
BASIC = "Basic " + base64.b64encode(os.environ["AUTH"].encode()).decode()
fails = []

def http(url, body=None, headers=None, timeout=300):
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=h,
                                 method="GET" if body is None else "POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.headers, r.read().decode()

def src(url):
    try:
        return json.loads(http(url, headers={"Accept": "application/json"})[2])
    except urllib.error.HTTPError as e:
        return {"__status": e.code}

def kg(cypher):
    return json.loads(http(APP + "/api/v1/admin/kg/execute", {"cypher": cypher}, {"Authorization": BASIC})[2])

def view(name, args=None):
    try:
        return json.loads(http(APP + f"/api/v1/views/{name}/invoke", {"args": args or {}}, {"Authorization": BASIC})[2])
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code} {e.read()[:200]!r}"}

def check(what, expected, actual):
    if expected == actual: print(f"  ok   {what} = {actual}")
    else: print(f"  FAIL {what}: expected {expected!r}, got {actual!r}"); fails.append(what)

def at_most(what, bound, calls):
    if not isinstance(calls, int): print(f"  FAIL {what}: no call count ({calls!r})"); fails.append(what)
    elif calls <= bound: print(f"  ok   {what}: {calls} source call(s), bound {bound}")
    else: print(f"  FAIL {what}: {calls} source calls, bound {bound}"); fails.append(what)

def rows(res):
    if res.get("error"): return "REFUSED: " + str(res["error"])[:200]
    return res.get("rows") if "rows" in res else res.get("data")

def one(cypher, col="n"):
    r = rows(kg(cypher))
    return r if isinstance(r, str) else (r[0].get(col) if r else None)

# ---- L0: seed ------------------------------------------------------------------------------------
TRACKED = ["express", "lodash", "eslint", "react", "@babel/core"]
print("== L0: tracked packages ==")
have = {r["name"] for r in (rows(kg("MATCH (p:NpmPackage) RETURN p.name AS name")) or []) if isinstance(r, dict)}
missing = [p for p in TRACKED if p not in have]
if missing:
    # The code door is the documented way to write a stored anchor (README, "Getting an answer").
    def mcp(payload, sid=None):
        h = {"Authorization": BASIC, "Accept": "application/json, text/event-stream"}
        if sid: h["Mcp-Session-Id"] = sid
        st, hd, body = http(APP + "/mcp/code", payload, h)
        data = [l[5:] for l in body.splitlines() if l.startswith("data:")]
        return hd.get("Mcp-Session-Id"), (json.loads(data[-1]) if data else (json.loads(body) if body.strip() else {}))
    sid, _ = mcp({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "realm-npm-verify", "version": "1"}}})
    mcp({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    script = "return await gateway.repository.createEntries(" + json.dumps(
        [{"type": "NpmPackage", "data": {"name": p, "notes": "seeded by realm-npm tests/verify.sh"}} for p in missing]) + ");"
    _, res = mcp({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": {"name": "code_mode", "arguments": {"script": script}}}, sid)
    if (res.get("result") or {}).get("isError") or "error" in res:
        print("  FAIL seeding NpmPackage:", json.dumps(res)[:300]); fails.append("seed")
have = {r["name"] for r in (rows(kg("MATCH (p:NpmPackage) RETURN p.name AS name")) or []) if isinstance(r, dict)}
check("tracked packages present", True, all(p in have for p in TRACKED))

# ---- L1: every view by name, on its defaults -------------------------------------------------------
print("== L1: every view answers by name ==")
# Empty is a legitimate answer only where the realm says so: a release with no dependency the model
# could judge, or a world with no model configured for the reading.
MAY_BE_EMPTY = {"ProportionReading": "needs a model on the world's vc_execution role"}
VIEWS = ["PackagePopularity", "AdoptionRanking", "LicenceSpread", "TrustSurface", "PackageMaintainers",
         "PublishAuthority", "SinglePublisherDependencies", "DirectDependencies", "SurfaceContributors",
         "LicenceExposure", "ProportionReading", "BuildProvenance"]
results = {}
for v in VIEWS:
    res = view(v); r = rows(res); results[v] = r
    if isinstance(r, str) or r is None:
        print(f"  FAIL {v}: {r or res}"[:300]); fails.append(v)
    elif not r and v not in MAY_BE_EMPTY:
        print(f"  FAIL {v}: zero rows"); fails.append(v)
    else:
        print(f"  ok   {v}: {len(r)} rows" + (f"  ({MAY_BE_EMPTY[v]})" if not r else ""))

# ---- L2: figures against the sources ----------------------------------------------------------------
print("== L2: the realm against npm and deps.dev ==")
dl = src("https://api.npmjs.org/downloads/point/last-week/express")
check("express last-week downloads",
      dl.get("downloads"),
      one("MATCH (p:NpmPackage {name: 'express'})-[:HAS_WEEKLY_DOWNLOADS {ai: {fresh: true}}]->(d:NpmDownloads) RETURN d.count AS n"))
check("express download window end", dl.get("end"),
      one("MATCH (p:NpmPackage {name: 'express'})-[:HAS_WEEKLY_DOWNLOADS]->(d:NpmDownloads) RETURN d.periodEnd AS n"))
pop = {r["package"]: r["weeklyDownloads"] for r in results["PackagePopularity"] or [] if isinstance(r, dict)}
check("PackagePopularity agrees for express", dl.get("downloads"), pop.get("express"))
for pkg in ["express", "@babel/core"]:
    latest = src("https://registry.npmjs.org/" + urllib.parse.quote(pkg, safe="@") + "/latest")
    check(f"{pkg} latest version", latest.get("version"),
          one(f"MATCH (p:NpmPackage {{name: '{pkg}'}})-[:HAS_LATEST_RELEASE {{ai: {{fresh: true}}}}]->(r:NpmRelease) RETURN r.version AS n"))
ver = src("https://registry.npmjs.org/express/latest").get("version")
deps = src(f"https://api.deps.dev/v3/systems/NPM/packages/express/versions/{ver}:dependencies")
truth = sorted({n["versionKey"]["name"] for n in deps.get("nodes", []) if n.get("relation") == "DIRECT"})
got = sorted(r["package"] for r in results["DirectDependencies"] or [] if isinstance(r, dict))
check(f"express@{ver} direct dependencies (deps.dev)", truth, got)
maint = sorted(m["name"] for m in src("https://registry.npmjs.org/lodash/latest").get("maintainers", []))
got = sorted(r["account"] for r in results["PackageMaintainers"] or [] if isinstance(r, dict))
check("lodash publishers (registry)", maint, got)

# ---- L3: cost -------------------------------------------------------------------------------------
print("== L3: what a narrow question costs ==")
q = "MATCH (p:NpmPackage {name: 'react'})-[:HAS_WEEKLY_DOWNLOADS%s]->(d:NpmDownloads) RETURN d.count AS n"
at_most("one package's downloads, read fresh", 1, kg(q % " {ai: {fresh: true}}").get("apiCalls"))
at_most("the same read, warm", 0, kg(q % "").get("apiCalls"))
q = "MATCH (p:NpmPackage {name: 'react'})-[:HAS_LATEST_RELEASE%s]->(r:NpmRelease) RETURN r.version AS n"
at_most("one package's latest release, read fresh", 1, kg(q % " {ai: {fresh: true}}").get("apiCalls"))
q = ("MATCH (p:NpmPackage {name: 'react'})-[:HAS_LATEST_RELEASE]->(r:NpmRelease)"
     "-[:HAS_DEPENDENCY%s]->(d:NpmDependency) RETURN count(d) AS n")
at_most("one release's direct dependencies, read fresh", 1, kg(q % " {ai: {fresh: true}}").get("apiCalls"))
# A name npm has never heard of: asked once, then the clean miss is remembered.
ghost = "realm-npm-verify-no-such-package-7f3a"
q = f"MATCH (p:NpmPackage {{name: '{ghost}'}}) OPTIONAL MATCH (p)-[:HAS_WEEKLY_DOWNLOADS]->(d:NpmDownloads) RETURN count(d) AS n"
kg(q)
at_most("an unknown package, asked again (negative cache)", 0, kg(q).get("apiCalls"))

if fails:
    print(f"FAILED: {len(fails)} check(s): {', '.join(fails)}")
    sys.exit(1)
print("ALL CHECKS PASS")
PY
