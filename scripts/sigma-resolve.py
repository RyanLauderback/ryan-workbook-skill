#!/usr/bin/env python3
"""Resolve freeform Sigma source/target references to API identifiers.

The agent calls this once at the start of any workbook build, passing the user's
prompt verbatim. The script extracts URLs, URL slugs, and prose hints, then
resolves them to (connectionId, path, inodeId, folderId, etc.) via the Sigma
REST API. Ambiguity is returned as `candidates` for the agent to surface as a
human-friendly question — never as an endpoint error.

Usage:
  scripts/sigma-resolve.py "<freeform input>"

Output (stdout, JSON):
  {
    "sources":   [ ... resolved warehouse-schema / table / data-model / workbook entries ... ],
    "folder":    { id, urlId, name, path } | null,
    "candidates": { "folder": [...], "connection": [...], ... },
    "unresolved": [ ... entries the agent must ask the user to clarify ... ],
    "hints":     { db, schema, folder_name, connection },
    "input":     "<echo of the original prompt>"
  }

Env: SIGMA_BASE_URL, SIGMA_API_TOKEN required (run scripts/load-env.sh and
fetch a token via the sigma-api skill first).
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from typing import Any


# ---------- env / api ----------

def _bootstrap_env() -> None:
    """Self-bootstrap SIGMA_BASE_URL + SIGMA_API_TOKEN if missing, by sourcing
    scripts/api/_env.sh and reading back the resulting env.

    Why this exists: bash scripts under scripts/api/ already self-bootstrap by
    sourcing _env.sh. Python scripts (this one) historically required the user
    to run `eval "$(scripts/load-env.sh)"` first, which is easy to forget.
    Forgetting it produces a cryptic "missing env SIGMA_API_TOKEN" error mid-
    session. This helper closes that gap so the failure mode disappears: if
    the env vars aren't already set, source _env.sh once and pick them up.

    No-op if both vars are already exported (env var still wins — backward-
    compatible). Silent fallback if _env.sh isn't found (rare in this repo);
    the original _env() will surface the missing-var error in that case."""
    if os.environ.get("SIGMA_BASE_URL") and os.environ.get("SIGMA_API_TOKEN"):
        return
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    env_sh = os.path.join(repo_root, "scripts", "api", "_env.sh")
    if not os.path.exists(env_sh):
        return
    try:
        result = subprocess.run(
            ["bash", "-c",
             f"source {shlex.quote(env_sh)} && "
             "printf 'SIGMA_BASE_URL=%s\\nSIGMA_API_TOKEN=%s\\n' "
             "\"$SIGMA_BASE_URL\" \"$SIGMA_API_TOKEN\""],
            capture_output=True, text=True, check=True, timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return
    for line in result.stdout.strip().splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            if v and not os.environ.get(k):
                os.environ[k] = v


def _env(k: str) -> str:
    v = os.environ.get(k)
    if not v:
        sys.stderr.write(
            f"sigma-resolve: missing env {k}. "
            "Run `eval \"$(scripts/load-env.sh)\"` and fetch a token first.\n"
        )
        sys.exit(2)
    return v


def _api(path: str, method: str = "GET", body: Any = None) -> Any:
    base = _env("SIGMA_BASE_URL").rstrip("/")
    tok = _env("SIGMA_API_TOKEN")
    req = urllib.request.Request(
        base + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "Authorization": f"Bearer {tok}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return {"_error": e.code, "_body": json.loads(e.read())}
        except Exception:
            return {"_error": e.code}


# ---------- parsing ----------

URL_RE = re.compile(r"https?://[\w./\-_:%~?=&+#]+")
# Sigma URL path patterns. Each captures the slug segment that follows the
# kind-prefix; the slug is "<Name>-<urlId>" for most kinds (Sigma includes the
# human-readable name as a URL-safe prefix) or a bare "<urlId>" for workbooks
# with no friendly slug. _split_slug() below splits at the last hyphen.
URL_PATTERNS = [
    ("workbook",  re.compile(r"/workbook/([A-Za-z0-9_][\w-]*)")),
    ("datamodel", re.compile(r"/b/([A-Za-z0-9_][\w-]*)")),
    ("table",     re.compile(r"/t/([A-Za-z0-9_][\w-]*)")),
    ("schema",    re.compile(r"/s/([A-Za-z0-9_][\w-]*)")),
    ("folder",    re.compile(r"/f/([A-Za-z0-9_][\w-]*)")),
    # Bare slug after the org segment (older folder URL style with no /f/).
    ("slug",      re.compile(r"/[\w-]+/([A-Za-z][\w]*(?:-[A-Za-z0-9_]+)+)$")),
]
# Bare slug not embedded in a URL: BIKES-2jPgY5cxsfNZeeMcD2WLgi
SLUG_RE = re.compile(r"\b([A-Za-z][A-Za-z0-9_]*(?:[-_][A-Za-z0-9_]+)*)-([A-Za-z0-9_-]{18,28})\b")


def _split_slug(slug: str) -> tuple[str, str]:
    """Split '<Name>-<urlId>' at the last hyphen. If no hyphen, the slug IS the urlId."""
    if "-" in slug:
        name, _, url_id = slug.rpartition("-")
        return name, url_id
    return "", slug


def parse_input(text: str) -> tuple[list[tuple[str, str, str]], str]:
    """Return list of (kind, value, source_url) and the remaining prose."""
    entries: list[tuple[str, str, str]] = []
    rest = text

    for url in URL_RE.findall(text):
        matched = False
        for kind, rx in URL_PATTERNS:
            m = rx.search(url)
            if m:
                slug = m.group(1)
                name_part, url_id = _split_slug(slug)
                if kind == "slug":
                    # Older folder URL style — treat as bare-slug for lookup.
                    entries.append(("bare-slug", f"{name_part}|{url_id}", url))
                elif kind == "folder":
                    entries.append(("folder-url", f"{name_part}|{url_id}", url))
                else:
                    # workbook / datamodel / schema / table — store the urlId and
                    # the name part (if any) for use as a schema/table name hint.
                    entries.append((kind, f"{name_part}|{url_id}", url))
                matched = True
                break
        rest = rest.replace(url, " ")
        if not matched:
            continue

    for m in SLUG_RE.finditer(rest):
        entries.append(("bare-slug", f"{m.group(1)}|{m.group(2)}", m.group(0)))
    rest = SLUG_RE.sub(" ", rest)

    return entries, rest.strip()


# ---------- prose hint extraction ----------

HINT_PATTERNS = {
    "db":         [r"\b([A-Za-z][\w]*)\s+(?:db|database)\b",
                   r"\b(?:db|database)\s+([A-Za-z][\w]*)\b"],
    "schema":     [r"\b([A-Za-z][\w]*)\s+schema\b",
                   r"\bschema\s+([A-Za-z][\w]*)\b"],
    "connection": [r"\b([A-Za-z][\w \-]+?)\s+connection\b",
                   r"\bconnection\s+([A-Za-z][\w \-]+?)\b"],
    "folder_name": [r"\b([A-Za-z][\w \-]+?)\s+folder\b",
                    r"\bfolder\s+([A-Za-z][\w \-]+?)\b"],
}


def extract_hints(prose: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, pats in HINT_PATTERNS.items():
        for pat in pats:
            m = re.search(pat, prose, re.IGNORECASE)
            if m:
                val = m.group(1).strip()
                if key in ("db", "schema") and val.isidentifier():
                    out[key] = val.upper()
                else:
                    out[key] = val
                break
    # "X.Y" dotted form for db.schema
    m = re.search(r"\b([A-Z][A-Z0-9_]*)\.([A-Z][A-Z0-9_]*)\b", prose)
    if m:
        out.setdefault("db", m.group(1))
        out.setdefault("schema", m.group(2))
    return out


# ---------- resolvers ----------

def list_connections() -> list[dict]:
    r = _api("/v2/connections?limit=200")
    if isinstance(r, dict) and r.get("_error"):
        return []
    return [
        {"connectionId": c.get("connectionId"), "name": c.get("name"), "type": c.get("type")}
        for c in r.get("entries", [])
    ]


def find_path_by_urlid(url_id: str) -> dict | None:
    """Reverse-lookup a connection path entry (schema/table/db scope) by its urlId.
    Paginates /v2/connections/paths. Returns {connectionId, path} or None.
    Slow on first call; the OK pattern is to call it once per /s/ or /t/ URL."""
    page = None
    while True:
        qs = {"limit": "1000"}
        if page:
            qs["page"] = page
        r = _api("/v2/connections/paths?" + urllib.parse.urlencode(qs))
        if r.get("_error"):
            return None
        for e in r.get("entries", []):
            if e.get("urlId") == url_id:
                return {"connectionId": e.get("connectionId"), "path": e.get("path")}
        page = r.get("nextPage")
        if not page:
            return None


def find_file_by_urlid(url_id: str) -> dict | None:
    page = None
    while True:
        qs = {"limit": "1000"}
        if page:
            qs["page"] = page
        r = _api("/v2/files?" + urllib.parse.urlencode(qs))
        if r.get("_error"):
            return None
        for e in r.get("entries", []):
            if e.get("urlId") == url_id:
                return {k: e.get(k) for k in ("id", "urlId", "name", "type", "path")}
        page = r.get("nextPage")
        if not page:
            return None


def find_folders_by_name(name: str) -> list[dict]:
    """Bidirectional substring match — the hint may be longer than the folder
    name ('place in claude testing folder' → folder 'Claude Testing') or vice
    versa ('claude' → folder 'Claude Testing'). Match if either contains the
    other, or if all significant tokens (≥3 chars) of one appear in the other.
    """
    hint = name.lower().strip()
    hint_tokens = {t for t in re.split(r"\W+", hint) if len(t) >= 3}
    page, out = None, []
    while True:
        qs = {"typeFilters": "folder", "limit": "1000"}
        if page:
            qs["page"] = page
        r = _api("/v2/files?" + urllib.parse.urlencode(qs))
        if r.get("_error"):
            return out
        for e in r.get("entries", []):
            fname = (e.get("name") or "").lower()
            ftokens = {t for t in re.split(r"\W+", fname) if len(t) >= 3}
            if (
                hint in fname
                or fname in hint
                or (ftokens and ftokens.issubset(hint_tokens))
                or (hint_tokens and hint_tokens.issubset(ftokens))
            ):
                out.append({k: e.get(k) for k in ("id", "urlId", "name", "path", "type")})
        page = r.get("nextPage")
        if not page:
            return out


def lookup_path(conn_id: str, *path_parts: str) -> dict:
    return _api(f"/v2/connection/{conn_id}/lookup", method="POST", body={"path": list(path_parts)})


def list_table_columns(inode_id: str) -> list[dict]:
    r = _api(f"/v2/connections/tables/{inode_id}/columns?pageSize=200")
    if r.get("_error"):
        return []
    return [
        {"name": c.get("name"), "type": (c.get("type") or {}).get("type")}
        for c in r.get("entries", [])
    ]


DEFAULT_PROBE_NAMES = [
    "TRIP", "TRIPS", "STATION", "STATIONS", "WEATHER",
    "CUSTOMER", "CUSTOMERS", "USER", "USERS",
    "ORDER", "ORDERS", "PRODUCT", "PRODUCTS",
    "SALES", "TRANSACTIONS", "PAYMENTS", "RENTALS",
    "EVENT", "EVENTS", "SESSIONS", "RIDES", "BIKES",
    "ACCOUNTS", "ACCOUNT", "INVOICES", "INVOICE",
    "EMPLOYEE", "EMPLOYEES", "STORE", "STORES",
]


def probe_schema_tables(conn_id: str, db: str, schema: str,
                        names: list[str] | None = None) -> list[dict]:
    names = names or DEFAULT_PROBE_NAMES

    def _probe(n: str) -> dict | None:
        r = lookup_path(conn_id, db, schema, n)
        if r.get("_error") or r.get("kind") != "table":
            return None
        return {
            "name": n,
            "inodeId": r.get("inodeId"),
            "columns": list_table_columns(r.get("inodeId")),
        }

    with ThreadPoolExecutor(max_workers=8) as ex:
        return [t for t in ex.map(_probe, names) if t]


def fuzzy_match_connection(connections: list[dict], hint: str) -> list[dict]:
    h = hint.lower().strip()
    if not h:
        return []
    return [c for c in connections if h in (c.get("name") or "").lower()]


# ---------- main resolution ----------

def resolve_warehouse_schema(conn_id: str, db: str, schema: str) -> dict:
    res = lookup_path(conn_id, db, schema)
    if res.get("_error"):
        return {"_error": res.get("_error"), "_body": res.get("_body")}
    return {
        "kind": "warehouse-schema",
        "connectionId": conn_id,
        "path": [db, schema],
        "schemaInodeId": res.get("inodeId"),
        "tables": probe_schema_tables(conn_id, db, schema),
    }


def main() -> None:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: sigma-resolve.py <freeform-input>\n")
        sys.exit(2)
    _bootstrap_env()
    text = " ".join(sys.argv[1:])
    entries, prose = parse_input(text)
    hints = extract_hints(prose)

    out: dict[str, Any] = {
        "sources": [],
        "folder": None,
        "candidates": {},
        "unresolved": [],
        "hints": hints,
        "input": text,
    }

    # Lazy load — only fetch connection list when actually needed.
    _connections: list[dict] | None = None

    def conns() -> list[dict]:
        nonlocal _connections
        if _connections is None:
            _connections = list_connections()
        return _connections

    # ----- URL / slug entries first -----
    for kind, value, src in entries:
        if kind == "workbook":
            _, url_id = value.split("|", 1) if "|" in value else ("", value)
            out["sources"].append({"kind": "workbook", "urlId": url_id, "url": src})
        elif kind == "datamodel":
            _, url_id = value.split("|", 1) if "|" in value else ("", value)
            out["sources"].append({"kind": "datamodel", "urlId": url_id, "url": src})
        elif kind == "folder-url":
            name_part, url_id = value.split("|", 1) if "|" in value else ("", value)
            f = find_file_by_urlid(url_id)
            if f:
                if f.get("type") == "folder" and out["folder"] is None:
                    out["folder"] = f
                else:
                    out["sources"].append({"kind": f.get("type") or "file", **f})
            else:
                out["unresolved"].append({"kind": "folder-url", "urlId": url_id,
                                          "namePart": name_part, "url": src})
        elif kind in ("schema", "table"):
            name_part, url_id = value.split("|", 1) if "|" in value else ("", value)
            # First try the reverse lookup via /v2/connections/paths — works for
            # both /s/ (schema scope) and /t/ (table) URLs when the urlId is
            # the connection-path urlId.
            found = find_path_by_urlid(url_id)
            if found and found.get("path"):
                conn_id = found["connectionId"]
                path = found["path"]
                conn_name = next((c["name"] for c in conns()
                                  if c["connectionId"] == conn_id), None)
                if kind == "schema" and len(path) >= 2:
                    s = resolve_warehouse_schema(conn_id, path[0], path[1])
                    if not s.get("_error"):
                        s["connectionName"] = conn_name
                        s["source_url"] = src
                        out["sources"].append(s)
                        continue
                elif kind == "table" and len(path) == 3:
                    r = lookup_path(conn_id, *path)
                    if not r.get("_error") and r.get("kind") == "table":
                        out["sources"].append({
                            "kind": "warehouse-table",
                            "connectionId": conn_id,
                            "connectionName": conn_name,
                            "path": path,
                            "inodeId": r.get("inodeId"),
                            "columns": list_table_columns(r.get("inodeId")),
                            "source_url": src,
                        })
                        continue
            # Fallback: prose hints
            if hints.get("db") and hints.get("schema"):
                conn_hint = hints.get("connection", "")
                candidate_conns = fuzzy_match_connection(conns(), conn_hint) or conns()
                hits = []
                for c in candidate_conns:
                    s = resolve_warehouse_schema(c["connectionId"], hints["db"], hints["schema"])
                    if not s.get("_error"):
                        s["connectionName"] = c["name"]
                        s["source_url"] = src
                        hits.append(s)
                if len(hits) == 1:
                    out["sources"].append(hits[0])
                elif hits:
                    out["candidates"].setdefault("sources", []).extend(hits)
                else:
                    out["unresolved"].append({
                        "kind": kind, "urlId": url_id, "url": src,
                        "note": "Could not reverse-lookup; provide DB+schema (and connection) names.",
                    })
            else:
                out["unresolved"].append({
                    "kind": kind, "urlId": url_id, "url": src,
                    "namePart": name_part,
                    "note": "Reverse lookup found no match. Add 'in <DB> db' (and connection) to the prompt.",
                })
        elif kind == "bare-slug":
            name_part, url_id = value.split("|", 1)
            # First: is this a folder/workbook/dataset?
            f = find_file_by_urlid(url_id)
            if f:
                if (f.get("type") == "folder") and out["folder"] is None:
                    out["folder"] = f
                else:
                    out["sources"].append({"kind": f.get("type") or "file", **f})
                continue
            # Second: maybe it's a schema slug. Need db + schema hints — fall
            # back to using the slug's name part as the schema name if missing.
            if hints.get("db") and not hints.get("schema") and name_part.isidentifier():
                hints["schema"] = name_part.upper()
            if hints.get("db") and hints.get("schema"):
                conn_hint = hints.get("connection", "")
                candidate_conns = fuzzy_match_connection(conns(), conn_hint) or conns()
                hits = []
                for c in candidate_conns:
                    s = resolve_warehouse_schema(c["connectionId"], hints["db"], hints["schema"])
                    if not s.get("_error"):
                        s["connectionName"] = c["name"]
                        s["source_url_slug"] = name_part
                        hits.append(s)
                if len(hits) == 1:
                    out["sources"].append(hits[0])
                elif hits:
                    out["candidates"].setdefault("sources", []).extend(hits)
                else:
                    out["unresolved"].append({
                        "kind": "bare-slug", "namePart": name_part, "urlId": url_id,
                        "note": "Could not resolve; provide DB + schema (and connection) names.",
                    })
            else:
                out["unresolved"].append({
                    "kind": "bare-slug", "namePart": name_part, "urlId": url_id,
                    "note": "Bare slug — provide DB + schema (and connection) names if it's a warehouse path.",
                })

    # ----- Prose-only resolution (when no URL/slug supplied) -----
    if not entries:
        if hints.get("folder_name") and out["folder"] is None:
            matches = find_folders_by_name(hints["folder_name"])
            if len(matches) == 1:
                out["folder"] = matches[0]
            elif matches:
                out["candidates"]["folder"] = matches
        if hints.get("schema") and hints.get("db"):
            conn_hint = hints.get("connection", "")
            candidate_conns = fuzzy_match_connection(conns(), conn_hint) or conns()
            hits = []
            for c in candidate_conns:
                s = resolve_warehouse_schema(c["connectionId"], hints["db"], hints["schema"])
                if not s.get("_error"):
                    s["connectionName"] = c["name"]
                    hits.append(s)
            if len(hits) == 1:
                out["sources"].append(hits[0])
            elif hits:
                out["candidates"]["sources"] = hits

    # Also: prose mention of a folder when a slug-URL didn't already resolve one
    if (out["folder"] is None) and hints.get("folder_name"):
        matches = find_folders_by_name(hints["folder_name"])
        if len(matches) == 1:
            out["folder"] = matches[0]
        elif matches:
            out["candidates"]["folder"] = matches

    json.dump(out, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
