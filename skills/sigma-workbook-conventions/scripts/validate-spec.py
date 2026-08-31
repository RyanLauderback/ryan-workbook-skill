#!/usr/bin/env python3
"""Pre-POST static validation for a Sigma workbook spec.

The Sigma POST/PUT endpoints accept structurally broken specs and silently
rewrite the layout — most notably, per-page `pages[].layout` fields are
discarded, container children stack into a 1/13-wide single column when not
nested in their `<GridContainer>` in the layout XML, and `format` on columns
returns a misleading "Missing 'kind' field" error when the shape is wrong.

Also catches two regression modes from the 2026-05-19 test sessions:
- Drill-passthrough collapse on viz elements (chart/KPI cols < source table cols)
- Control/column ID collision (controlId matching a column name on the filtered element)

Run before every POST/PUT:

    python3 scripts/validate-spec.py workbooks/<name>/spec.json

Exits 0 on success, non-zero on any fail-level issue (one issue per line on stderr).
Warn-level issues print to stderr but do not change exit code.
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET


CHECKS = [
    "schema-version",
    "no-per-page-layout",
    "elements-placed-in-layout",
    "containers-have-children",
    "layoutelement-has-children",
    "column-format-shape",
    "control-id-unique",
    "passthrough-coverage",
    "controlid-collision",
    "bare-ref-resolution",
    "control-filter-column-exists",
    "action-refs-resolve",
    "kpi-value-references-aggregation",
    "summary-calc-collision",
    "description-object-on-kpi-and-table",
    "pivot-missing-rows-and-columns",
    "channel-exclusivity",
    "conditional-aggregate-antipattern",
]


# Chart-kind elements that should carry substantive passthrough columns
# from their source table. KPI charts are intentionally excluded — KPI
# col count is too variable across legitimate patterns (1-16 cols
# observed across canonical exemplars) to give a useful signal.
CHART_KINDS_WITH_PASSTHROUGH = {
    "bar-chart",
    "line-chart",
    "area-chart",
    "combo-chart",
    "pie-chart",
    "donut-chart",
    "scatter-chart",
}
PIVOT_KINDS = {"pivot-table"}


def issues_schema_version(spec: dict) -> list[tuple[str, str]]:
    """Warn when `schemaVersion` isn't the currently-known-good value.

    Verified 2026-08-03 via a live POST: `schemaVersion: 2` is rejected
    outright with `"schemaVersion: Invalid 1: number"` — every canonical
    exemplar and every successful POST this skill has made uses `1`.
    WARN, not FAIL: `reference/workflows/crud.md` already documents that
    this value isn't guaranteed stable long-term and recommends reading
    it from a reference GET rather than hardcoding — this check just
    catches the common case of an unverified non-1 value before POST.
    """
    issues = []
    sv = spec.get("schemaVersion")
    if sv is not None and sv != 1:
        issues.append((
            "warn",
            f"top-level `schemaVersion` is {sv!r}, not the currently-verified "
            "value `1`. Every canonical exemplar and every successful POST "
            "this skill has made uses `schemaVersion: 1`; `2` was live-tested "
            "2026-08-03 and rejected outright. If you have a specific reason "
            "to believe the value has changed, confirm via "
            "`scripts/api/publish-workbook.sh get-spec <reference-workbook-id>` "
            "first — see reference/workflows/crud.md → 'schemaVersion — don't hardcode'."
        ))
    return issues


def issues_per_page_layout(spec: dict) -> list[tuple[str, str]]:
    issues = []
    for i, p in enumerate(spec.get("pages", [])):
        if p.get("layout"):
            issues.append((
                "fail",
                f"pages[{i}] ({p.get('id')}): has a per-page `layout` field. "
                "Sigma silently discards it — move to the top-level `layout` "
                "string with all <Page> elements as siblings."
            ))
    return issues


def _parse_layout(layout: str) -> ET.Element | None:
    if not layout:
        return None
    cleaned = re.sub(r"<\?xml[^?]*\?>", "", layout).strip()
    wrapped = f"<root>{cleaned}</root>"
    try:
        return ET.fromstring(wrapped)
    except ET.ParseError as e:
        sys.stderr.write(f"validate-spec: layout XML failed to parse: {e}\n")
        return None


def issues_elements_placed(spec: dict, root: ET.Element | None) -> list[tuple[str, str]]:
    if root is None:
        return [("fail", "no top-level `layout` field — workbook will have an auto-generated layout")]
    # The layout XML grammar has 5 tags, not 2 — TabbedContainer is a valid
    # elementId-bearing placement tag alongside LayoutElement/GridContainer.
    # (Its child <Tab> tags carry no elementId — tabs bind positionally to
    # the element's own `tabs[]` array order, not by XML attribute.)
    # Verified 2026-08-03 against 2 harvested workbooks (Claims Command
    # Center, Bergey's Unified Insights) — both produced exactly one false
    # FAIL per tabbed-container element before this fix.
    placed_ids = {
        el.get("elementId")
        for el in root.iter()
        if el.tag in ("Element", "Container", "TabbedContainer", "LayoutElement", "GridContainer")
    }
    issues = []
    for ei, el in enumerate(spec.get("elements", [])):
        eid = el.get("id")
        if eid and eid not in placed_ids:
            issues.append((
                "fail",
                f"elements[{ei}] ({eid}, kind={el.get('kind')}): "
                "not placed in the layout XML — will render at the page bottom or not at all."
            ))
    return issues


def issues_layoutelement_has_children(root: ET.Element | None) -> list[tuple[str, str]]:
    """Forward case of the containers-have-children check.

    `<Element>` (formerly `<LayoutElement>`) is a leaf tag — it positions
    exactly one element and takes no children. `<Element type="grid">` with
    nested tags parses without error but the children are silently dropped
    (they never render). Use `<Container>` (formerly `<GridContainer>`)
    instead when a tag needs to wrap children.

    Ported 2026-08-03 from the real upstream `sigma-workbooks` skill's manual
    checklist (`reference/workflows/validate.md`) — the local skill's
    `containers-have-children` only caught the inverse (a container element
    with no matching nested children), not this direction. Updated
    2026-08-10 to accept both the current (`Element`/`Container`) and legacy
    (`LayoutElement`/`GridContainer`) tag names — see `issues_elements_placed`
    for the same accommodation.
    """
    if root is None:
        return []
    issues = []
    for el in root.iter():
        if el.tag not in ("Element", "LayoutElement"):
            continue
        children = list(el)
        if children:
            child_tags = ", ".join(c.tag for c in children)
            issues.append((
                "fail",
                f"<{el.tag} elementId=\"{el.get('elementId')}\"> has nested "
                f"child tag(s) ({child_tags}) — {el.tag} is a leaf; children "
                "nested inside it are silently dropped and never render. Use "
                "<Container> instead if this element needs to wrap children."
            ))
    return issues


def issues_containers_have_children(spec: dict, root: ET.Element | None) -> list[tuple[str, str]]:
    if root is None:
        return []
    container_ids = [
        el.get("id")
        for el in spec.get("elements", [])
        if el.get("kind") == "container"
    ]
    issues = []
    for cid in container_ids:
        gc = next(
            (el for el in root.iter() if el.tag in ("Container", "GridContainer") and el.get("elementId") == cid),
            None,
        )
        if gc is None:
            issues.append((
                "fail",
                f"container element `{cid}`: no matching <Container> in layout XML."
            ))
        elif len(list(gc)) == 0:
            issues.append((
                "fail",
                f"container element `{cid}`: <Container> has no nested children. "
                "Children must be nested INSIDE the <Container>, not flat siblings."
            ))
    return issues


def issues_column_format_shape(spec: dict) -> list[tuple[str, str]]:
    """Per Phase 6b: `format` IS spec-able, but only with `kind` + `formatString`.

    The UI-emitted shape `{type: "number", format: "currency"}` is rejected
    with "Missing 'kind' field". The verified shape is
    `{kind: "number", formatString: "$,.2f"}`.
    """
    issues = []
    for ei, el in enumerate(spec.get("elements", [])):
        for ci, col in enumerate(el.get("columns", []) or []):
            fmt = col.get("format")
            if fmt is None:
                continue
            if not isinstance(fmt, dict):
                issues.append((
                    "fail",
                    f"elements[{ei}].columns[{ci}] ({col.get('id')}): "
                    f"`format` must be an object, got {type(fmt).__name__}."
                ))
                continue
            if "kind" not in fmt:
                issues.append((
                    "fail",
                    f"elements[{ei}].columns[{ci}] ({col.get('id')}): "
                    "`format` is missing required `kind` field. "
                    "Verified shape: {kind: \"number\", formatString: \"$,.2f\"}. "
                    "If this came from a UI export ({type: ..., format: ...}), strip and re-spec."
                ))
    return issues


def issues_control_id_unique(spec: dict) -> list[tuple[str, str]]:
    """`controlId` is workbook-wide unique — EXCEPT for `controlType:"synced"`.

    `synced` is a first-class cross-page control-sync primitive: one page
    owns a full control definition (any controlType, `source`, `value`,
    etc.); every other page places a thin `controlType:"synced"` stub
    carrying only `id`+`controlId`+`kind`+`controlType`, deliberately
    reusing the primary's `controlId` so the two stay in sync. This is not
    tolerated duplication — it's how Sigma represents "the same control,
    placed on multiple pages."

    Verified 2026-08-03 against Bergey's Unified Insights: one `segmented`
    control on `Parts` plus four `synced` stubs (Service/Sales/Leasing/Body
    Shop) all sharing `controlId: "Business-Line-Nav"`.

    Only fail when a duplicate exists where **neither** side is `synced` —
    that's genuine accidental collision, still a real bug.
    """
    seen: dict[str, tuple[str, str]] = {}  # controlId -> (elementId, controlType)
    issues = []
    for el in spec.get("elements", []):
        if el.get("kind") != "control":
            continue
        cid = el.get("controlId")
        if not cid:
            continue
        ctype = el.get("controlType")
        if cid in seen:
            prev_eid, prev_ctype = seen[cid]
            if ctype == "synced" or prev_ctype == "synced":
                continue  # deliberate cross-page sync — not a collision
            issues.append((
                "fail",
                f"controlId `{cid}` duplicated on elements {prev_eid} and {el.get('id')}, "
                f"neither is `controlType:\"synced\"`. controlId is workbook-wide unique "
                "unless one side is a synced stub."
            ))
        else:
            seen[cid] = (el.get("id"), ctype)
    return issues


def _all_elements(spec: dict) -> list[tuple[int, dict]]:
    """Yield (index, element) for every top-level element.

    Elements moved from a per-page pages[].elements nesting to a single
    flat document.elements array 2026-08-10 — page membership now lives
    entirely in the layout XML, not in the JSON. The int this returns is
    the flat array index (for error-message locators), not a page index;
    nothing here ever used it for cross-element same-page comparisons —
    confirmed by reading every call site before this change.
    """
    return list(enumerate(spec.get("elements", [])))


def _source_table_for(viz: dict, all_elements: list[tuple[int, dict]]) -> dict | None:
    """Resolve a viz's source element if it's a workbook table.

    Searches all pages (per-page source-table architecture means the
    source table may live on a different page — typically a dedicated
    'Data Sources' page in multi-page workbooks).
    """
    src = viz.get("source") or {}
    if src.get("kind") != "table":
        # data-model-sourced vizs (kind: data-model) don't have a workbook
        # table to compare passthrough against — coverage check skipped.
        return None
    eid = src.get("elementId")
    if not eid:
        return None
    for _, el in all_elements:
        if el.get("id") == eid and el.get("kind") == "table":
            return el
    return None


def issues_passthrough_coverage(spec: dict) -> list[tuple[str, str]]:
    """Catch drill-passthrough collapse — the 2026-05-19 regression.

    Charts (bar/line/area/combo/pie/donut/scatter) sourced from a workbook
    table with non-trivial column count should carry meaningful passthrough.
    The collapse signature is a chart with only 2 columns (`x` + `y` axes
    and nothing else) sourced from a wide table.

    Calibrated against canonical exemplars: smallest legitimate chart has
    7-8 cols (scatter), smallest legitimate pivot has 3 cols (cohort).

    Levels:
    - fail  chart with <=2 cols, source has >=5 cols (collapse signature)
    - warn  chart with 3-4 cols, source has >=10 cols (suspicious thin)
    - warn  pivot with <=2 cols, source has >=5 cols

    KPI elements excluded — col count is too variable across legitimate
    patterns (1-16 cols observed) to give a useful signal.
    """
    issues = []
    all_elements = _all_elements(spec)
    for pi, el in all_elements:
        kind = el.get("kind")
        if kind not in CHART_KINDS_WITH_PASSTHROUGH and kind not in PIVOT_KINDS:
            continue
        src_table = _source_table_for(el, all_elements)
        if src_table is None:
            continue
        viz_cols = len(el.get("columns", []) or [])
        src_cols = len(src_table.get("columns", []) or [])
        if src_cols < 5:
            continue  # trivial source — no meaningful passthrough to compare

        if kind in CHART_KINDS_WITH_PASSTHROUGH:
            if viz_cols <= 2:
                issues.append((
                    "fail",
                    f"elements[{pi}] ({el.get('id')}, kind={kind}): "
                    f"only {viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). Likely passthrough collapse — "
                    "right-click drill will be crippled. Default is "
                    "passthrough-all; see SKILL.md → 'Load-bearing rules' → rule #1."
                ))
            elif viz_cols <= 4 and src_cols >= 10:
                issues.append((
                    "warn",
                    f"elements[{pi}] ({el.get('id')}, kind={kind}): "
                    f"{viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). May be thin passthrough — "
                    "intentional only if source has many irrelevant cols. "
                    "See SKILL.md → 'Load-bearing rules' → rule #1."
                ))
        elif kind in PIVOT_KINDS:
            if viz_cols <= 2:
                issues.append((
                    "warn",
                    f"elements[{pi}] ({el.get('id')}, kind={kind}): "
                    f"only {viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). Pivot may be missing dimension "
                    "or value cols. See SKILL.md → 'Load-bearing rules' → rule #1."
                ))
    return issues


def _display_name(el: dict) -> str | None:
    """Return an element's rendered display name, styled or plain."""
    name = el.get("name")
    if isinstance(name, dict):
        return name.get("text")
    return name


def issues_name_required_on_passthrough(spec: dict) -> list[tuple[str, str]]:
    """RETRACTED 2026-08-03 — NOT wired into CHECKS/main(). Kept here so the
    investigation isn't lost, and so nobody re-adds this naively without
    reading this note.

    `reference/conventions.md` -> "Explicit-`name` rule" claims a passthrough
    column whose formula is a single qualified ref `[<Source>/<Column>]`
    "works in a GET-back exemplar... but fails at POST" if referenced
    downstream via its inferred name before an explicit `name` is set. This
    function implements that claim literally. Calibrating it against the
    12 canonical `examples/` specs AND 5 live-harvested production
    workbooks (all currently rendering correctly in the Sigma UI) produced
    587 / 131 / 25 hits on claims / marketing / sales respectively, and 6+
    hits on 3 of the 12 "canonical, non-deprecated" examples — i.e. this
    exact pattern is pervasive in workbooks that demonstrably work.

    Conclusion: either the documented rule is a phantom limitation (an
    overclaim of the same shape as the buttons/modals "unsupported" claim
    this plan retired elsewhere), or its real trigger condition is far
    narrower than "any bare-inferred passthrough column referenced
    downstream" — e.g. maybe it only fails on the very first POST of a
    *freshly authored* spec before Sigma's resolver has ever seen the
    column, and round-tripped/established workbooks are unaffected. That
    distinction isn't recoverable from the JSON alone, so this check can't
    be made accurate without a live POST probe isolating the real trigger.
    Left un-wired pending that probe; see reference/history.md.
    """
    issues = []
    all_elements = _all_elements(spec)

    elements_by_name: dict[str, dict] = {}
    for _, el in all_elements:
        dn = _display_name(el)
        if dn:
            elements_by_name.setdefault(dn, el)

    qualified_refs: set[tuple[str, str]] = set()
    for _, el in all_elements:
        for col in el.get("columns", []) or []:
            formula = col.get("formula") or ""
            for m in re.finditer(r"\[([^/\]]+)/([^/\]]+)\]", formula):
                qualified_refs.add((m.group(1), m.group(2)))

    seen: set[tuple[str, str]] = set()
    for source_name, col_name in sorted(qualified_refs):
        source_el = elements_by_name.get(source_name)
        if not source_el:
            continue  # unresolved source name is a different failure mode
        for col in source_el.get("columns", []) or []:
            if col.get("name"):
                continue  # explicit name already present — fine
            if _inferred_column_name(col) != col_name:
                continue
            key = (source_el.get("id"), col.get("id"))
            if key in seen:
                continue
            seen.add(key)
            issues.append((
                "fail",
                f"element '{source_name}' / column '{col.get('id')}': referenced "
                f"downstream as `[{source_name}/{col_name}]` but has no explicit "
                "`name` field — only an inferred display name from its own "
                "passthrough formula. Works in a GET-back exemplar; POST/PUT "
                "rejects with 'dependency not found: formula reference ...'. "
                f'Add `"name": "{col_name}"` to this column. See '
                "reference/conventions.md -> 'Explicit-`name` rule'."
            ))
    return issues


def issues_controlid_collision(spec: dict) -> list[tuple[str, str]]:
    """Catch controlId shadowing a column name on the element it filters.

    When a control's controlId matches a column's `name` or `id` on the
    filtered element, Sigma resolves `[Date]`-style bare references to the
    control, not the column. Downstream formulas like `Month([Date])`
    silently break. See SKILL.md → 'Load-bearing rules' → rule #4.
    """
    issues = []
    all_elements = _all_elements(spec)
    elements_by_id = {el.get("id"): el for _, el in all_elements if el.get("id")}

    for pi, el in all_elements:
        if el.get("kind") != "control":
            continue
        cid = el.get("controlId")
        if not cid:
            continue
        for f in el.get("filters", []) or []:
            src = f.get("source") or {}
            target_eid = src.get("elementId")
            if not target_eid:
                continue
            target = elements_by_id.get(target_eid)
            if not target:
                continue
            for col in target.get("columns", []) or []:
                if col.get("name") == cid or col.get("id") == cid:
                    issues.append((
                        "fail",
                        f"elements[{pi}] ({el.get('id')}, control): "
                        f"controlId `{cid}` collides with column "
                        f"`{col.get('id')}` (name: `{col.get('name')}`) on filtered "
                        f"element `{target_eid}`. Formulas referencing `[{cid}]` "
                        "will resolve to the control, not the column. "
                        "Rename the control (e.g. `DateRange`, `StoreFilter`)."
                    ))
    return issues


CHANNEL_FIELDS_BY_KIND = {
    "bar-chart": ["xAxis", "yAxis", "color", "size"],
    "line-chart": ["xAxis", "yAxis", "color", "size"],
    "area-chart": ["xAxis", "yAxis", "color", "size"],
    "combo-chart": ["xAxis", "yAxis", "color", "size"],
    "scatter-chart": ["xAxis", "yAxis", "color", "size"],
    "pie-chart": ["value", "color"],
    "donut-chart": ["value", "color", "holeValue"],
    "region-map": ["region", "color", "label", "tooltip"],
    "point-map": ["latitude", "longitude", "size", "color", "label", "tooltip"],
    "geography-map": ["geography", "color", "label", "tooltip"],
    "kpi-chart": ["value"],
}


def _extract_channel_column_ids(value) -> list[str]:
    """Return the column-id string(s) a single channel's value references.

    Channel value shapes observed across element kinds are inconsistent
    (`{"id": ...}` for donut value/holeValue and map region/lat/lon/size,
    `{"columnId": ...}` for KPI value and chart xAxis, `{"columnIds": [...]}`
    for chart yAxis, `{"by", "column": ...}` for color, and arrays of
    `{"id": ...}` for map label/tooltip) — this walks all of them generically
    rather than special-casing per element kind.
    """
    ids: list[str] = []
    if value is None:
        return ids
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        col_ids = value.get("columnIds")
        if isinstance(col_ids, list):
            ids.extend(x for x in col_ids if isinstance(x, str))
        for key in ("id", "columnId", "column"):
            v = value.get(key)
            if isinstance(v, str):
                ids.append(v)
        return ids
    if isinstance(value, list):
        for item in value:
            ids.extend(_extract_channel_column_ids(item))
        return ids
    return ids


def issues_channel_exclusivity(spec: dict) -> list[tuple[str, str]]:
    """Catch a column id reused across two+ binding channels on one element.

    Per `reference/conventions.md` -> "Channel exclusivity": a single column
    id may appear on at most one binding channel per element (e.g. a
    region-map's `color.column` and `label[].id` can't both be the same id).
    Sigma rejects this at POST with a 400: "Column '<id>' is referenced from
    both 'X' and 'Y'; a column can only be on one channel at a time" — a hard
    rejection, not a rendering quirk.

    This check was flagged in `conventions.md` as "planned; not yet
    implemented" pending a second real-session confirmation of the failure
    mode beyond the original 2026-07-02 `exec-scorecard-v2` incident.
    Confirmed again 2026-08-04 (Wave 3 test session, live POST rejection on
    `map-profit-by-state`'s `color`/`label` both referencing the same
    column) — implementing now.

    fail: any column id bound to 2+ distinct channels on the same element.
    """
    issues = []
    for _pi, el in _all_elements(spec):
        channel_fields = CHANNEL_FIELDS_BY_KIND.get(el.get("kind"))
        if not channel_fields:
            continue
        id_to_channels: dict[str, set[str]] = {}
        for field in channel_fields:
            if field not in el:
                continue
            for cid in _extract_channel_column_ids(el.get(field)):
                id_to_channels.setdefault(cid, set()).add(field)
        for cid, channels in sorted(id_to_channels.items()):
            if len(channels) > 1:
                issues.append((
                    "fail",
                    f"element '{el.get('id')}' ({el.get('kind')}): column "
                    f"'{cid}' is bound to {len(channels)} channels "
                    f"({', '.join(sorted(channels))}) — a column can only be "
                    "on one channel at a time. Duplicate the column (same "
                    "formula, a distinct id) and bind one id per channel."
                ))
    return issues


def _inferred_column_name(col: dict) -> str | None:
    """Return the display name Sigma's resolver uses for a column.

    Explicit `name` wins. Otherwise, when the formula is a single qualified
    ref `[<Source>/<Column>]`, Sigma auto-infers `<Column>` as the display
    name. (`reference/conventions.md` → "Explicit-`name` rule" recommends
    setting `name` explicitly to avoid resolver lookups failing for
    downstream sibling references — but most exemplars omit it on
    passthrough columns and Sigma's auto-inference fills the gap.)
    """
    if col.get("name"):
        return col["name"]
    formula = (col.get("formula") or "").strip()
    m = re.fullmatch(r"\[([^/\]]+)/([^/\]]+)\]", formula)
    if m:
        return m.group(2)
    return None


def _collect_control_ids(spec: dict) -> set[str]:
    """Every `controlId` on the spec — valid bare-ref targets for formulas."""
    ids: set[str] = set()
    for el in spec.get("elements", []):
        cid = el.get("controlId")
        if cid:
            ids.add(cid)
    return ids


def issues_bare_ref_resolution(spec: dict) -> list[tuple[str, str]]:
    """Flag bare bracketed refs that don't resolve to a sibling column or control.

    Catches the #1 Sigma spec error: `[column_name]` without a `/` inside a
    formula when the referenced column actually lives on the source element,
    not the current one, and therefore needs the source prefix (e.g.
    `[<SourceName>/column_name]`).

    A bare `[X]` is valid when `X` matches one of:
    - The explicit `name` of a sibling column in this element's `columns[]`.
    - The column auto-inferred from a sibling's single qualified
      `[<Source>/<Column>]` formula.
    - A `controlId` anywhere on the spec.

    Limitations:
    - Regex-based; can false-positive on bracketed text inside string
      literals (e.g. `DateFormat([Date], "[MM] %Y")` — the `[MM]` is a
      strftime token, not a column ref).
    - Sigma's auto-disambiguator can create phantom column names like
      `Store Region (1)` for cross-element references; bare refs to those
      will false-positive too. Inspect flagged cases before fixing.

    Ported from the upstream sigma-workbooks skill's `validate-spec.sh`
    2026-05-21.
    """
    control_ids = _collect_control_ids(spec)
    issues = []
    for element in spec.get("elements", []):
        cols = element.get("columns") or []
        sibling_names = {n for n in (_inferred_column_name(c) for c in cols) if n}
        valid_targets = sibling_names | control_ids
        for col in cols:
            formula = col.get("formula") or ""
            if not formula:
                continue
            # Find all bare [name] refs (no slash inside the brackets).
            bare_refs = re.findall(r"\[([^/\]]+)\]", formula)
            unresolved = [r for r in bare_refs if r not in valid_targets]
            if unresolved:
                el_label = element.get("name") or element.get("id") or "(unnamed)"
                col_label = col.get("name") or col.get("id") or "(unnamed)"
                refs_str = ", ".join(repr(r) for r in unresolved)
                # WARN-level (not fail) because Sigma auto-infers some
                # column names this check can't predict — e.g.
                # `DateTrunc("week", [Date])` becomes "Week of Date",
                # and cross-element references can produce phantom
                # `(N)`-suffix names. Inspect each flagged case; if it's
                # a real bare ref to a non-sibling, add the source
                # prefix. If it's an auto-inferred name, the flag is
                # noise.
                issues.append((
                    "warn",
                    f"element '{el_label}' / column '{col_label}': "
                    f"bare bracketed refs don't match any sibling column or controlId: {refs_str}. "
                    f"Add the source prefix (e.g. [<source-name>/{unresolved[0]}]) "
                    f"or rename a sibling. Formula: {formula}"
                ))
    return issues


def issues_control_filter_column_exists(spec: dict) -> list[tuple[str, str]]:
    """Verify each control.filters[].columnId exists on the target element.

    A typo in a control's filter columnId (e.g. `col-cus-date` when the
    actual column ID is `col-cus-tx-date`) passes POST validation but
    silently breaks every downstream query on the filtered page. The
    control renders, the user can select values, but nothing filters.

    Also verifies the target element (source.elementId) exists — a
    typo in the elementId reference produces the same silent failure.

    Added 2026-07-02 after a fresh-agent build test surfaced this
    class of bug — validate-spec passed, POST succeeded, and the entire
    Customer 360 page returned empty until a subsequent PUT fixed the
    columnId. See history.md → "2026-07-02 — Sales Command Center
    fresh-agent test" if that section exists.
    """
    issues = []
    all_elements = _all_elements(spec)
    elements_by_id = {el.get("id"): el for _, el in all_elements if el.get("id")}

    for pi, el in all_elements:
        if el.get("kind") != "control":
            continue
        ctrl_id = el.get("id") or "(unnamed)"
        ctrl_label = el.get("controlId") or ctrl_id
        for fi, f in enumerate(el.get("filters", []) or []):
            src = f.get("source") or {}
            target_eid = src.get("elementId")
            column_id = f.get("columnId")
            if not target_eid or not column_id:
                continue  # Malformed filter; other checks catch that.
            target = elements_by_id.get(target_eid)
            if target is None:
                issues.append((
                    "fail",
                    f"elements[{pi}] ({ctrl_id}, control '{ctrl_label}'): "
                    f"filters[{fi}].source.elementId `{target_eid}` does not "
                    f"exist on the workbook. The filter will silently no-op. "
                    "Check for typos or a stale reference to a deleted element."
                ))
                continue
            target_col_ids = {
                c.get("id") for c in (target.get("columns") or [])
                if c.get("id")
            }
            if column_id not in target_col_ids:
                # Format a suggestion — nearest column id by simple substring.
                near = [
                    c for c in sorted(target_col_ids)
                    if column_id in c or c in column_id
                ][:3]
                near_hint = f" Did you mean: {', '.join(repr(n) for n in near)}?" if near else ""
                issues.append((
                    "fail",
                    f"elements[{pi}] ({ctrl_id}, control '{ctrl_label}'): "
                    f"filters[{fi}].columnId `{column_id}` does not exist on "
                    f"target element `{target_eid}`. The control will render "
                    f"but no downstream element will filter.{near_hint}"
                ))
    return issues


def issues_action_refs_resolve(spec: dict) -> list[tuple[str, str]]:
    """Verify every action/effect reference resolves to something real.

    Added 2026-08-03 (Wave 2 / C3) — a dangling `overlayId`, `control`,
    `table`, `tabbedContainer`, or `navigate.target.page` fails silently
    at runtime: POST succeeds, nothing renders or fires when clicked.
    This is the referential-integrity gap flagged as a known omission
    when the effect vocabulary shipped (see `reference/history.md`).

    Extended 2026-08-04 (Wave 3 / C5+C6) to also walk
    `agents[].tools[].steps[]` — confirmed via a live POST probe
    (`reference/specification/agents.md`) to reuse this exact same
    effect vocabulary, just with an added `kind:"effect"` sibling key
    on each step — and to check `chat.agentId` against `agents[].id`.
    Previously this check only covered `actions[].effects[]` on page
    elements; a dangling reference from an agent tool step failed just
    as silently and was unchecked.

    Checks, per effect (shapes verified via a live POST probe,
    `reference/specification/actions.md`):
    - `set-control-value`: `control` (target) and `value.control` (if
      `value.type == "control"`) are known controlIds.
    - `clear-control`: `scope.control` is a known controlId.
    - `open-overlay`: `overlayId` matches a `document.overlays[].id`
      (modals moved out of `pages[]` into a top-level `overlays` array
      2026-08-10 -- `document.pages[].type:"modal"` is no longer valid).
    - `navigate`: `target.page` matches any page `id`.
    - `select-tab`: `tabbedContainer` matches a `kind:"tabbed-container"`
      element `id`, and `selectedTab.index` is in range of that
      element's `tabs[]` array.
    - `insert-rows`/`delete-rows`: `table` matches a `kind:"input-table"`
      element `id`; `insert-rows.values` keys match that table's column
      `id`s, and any nested `{type:"control"}` value's `control` is a
      known controlId.
    - `chat.agentId` matches a known `agents[].id`.
    """
    issues = []
    all_elements = _all_elements(spec)
    control_ids = _collect_control_ids(spec)
    elements_by_id = {el.get("id"): el for _, el in all_elements if el.get("id")}
    modal_page_ids = {o.get("id") for o in (spec.get("overlays") or []) if o.get("id")}
    all_page_ids = {p.get("id") for p in spec.get("pages", [])}
    agent_ids = {a.get("id") for a in (spec.get("agents") or []) if a.get("id")}

    def _check_control(label: str, cid: str | None, loc: str):
        if cid and cid not in control_ids:
            issues.append((
                "fail",
                f"{loc}: {label} `{cid}` does not match any `controlId` in the spec. "
                "The effect will silently no-op."
            ))

    def _check_effect(fx: dict, loc: str):
        effect = fx.get("effect")
        loc = f"{loc} ({effect})"

        if effect == "set-control-value":
            _check_control("target control", fx.get("control"), loc)
            value = fx.get("value") or {}
            if value.get("type") == "control":
                _check_control("source control", value.get("control"), loc)

        elif effect == "clear-control":
            scope = fx.get("scope") or {}
            if scope.get("type") == "control":
                _check_control("scope control", scope.get("control"), loc)

        elif effect == "open-overlay":
            overlay_id = fx.get("overlayId")
            if overlay_id and overlay_id not in modal_page_ids:
                issues.append((
                    "fail",
                    f"{loc}: overlayId `{overlay_id}` does not match any "
                    "`document.overlays[].id`. The overlay will silently fail to open."
                ))

        elif effect == "navigate":
            target = fx.get("target") or {}
            page_id = target.get("page")
            if page_id and page_id not in all_page_ids:
                issues.append((
                    "fail",
                    f"{loc}: target.page `{page_id}` does not match any page `id`. "
                    "The navigation will silently no-op."
                ))

        elif effect == "select-tab":
            tc_id = fx.get("tabbedContainer")
            tc_el = elements_by_id.get(tc_id)
            if tc_id and (tc_el is None or tc_el.get("kind") != "tabbed-container"):
                issues.append((
                    "fail",
                    f"{loc}: tabbedContainer `{tc_id}` does not match any "
                    "`kind:\"tabbed-container\"` element. The tab switch will silently no-op."
                ))
            elif tc_el is not None:
                idx = (fx.get("selectedTab") or {}).get("index")
                n_tabs = len(tc_el.get("tabs") or [])
                if isinstance(idx, int) and not (0 <= idx < n_tabs):
                    issues.append((
                        "fail",
                        f"{loc}: selectedTab.index {idx} is out of range for "
                        f"`{tc_id}`, which has {n_tabs} tab(s) (valid: 0-{n_tabs - 1})."
                    ))

        elif effect in ("insert-rows", "delete-rows"):
            table_id = fx.get("table")
            table_el = elements_by_id.get(table_id)
            if table_id and (table_el is None or table_el.get("kind") != "input-table"):
                issues.append((
                    "fail",
                    f"{loc}: table `{table_id}` does not match any "
                    "`kind:\"input-table\"` element. The write will silently no-op."
                ))
            elif table_el is not None and effect == "insert-rows":
                table_col_ids = {
                    c.get("id") for c in (table_el.get("columns") or []) if c.get("id")
                }
                for col_id, val in (fx.get("values") or {}).items():
                    if col_id not in table_col_ids:
                        issues.append((
                            "fail",
                            f"{loc}: values key `{col_id}` does not match any column "
                            f"`id` on input-table `{table_id}`."
                        ))
                    if isinstance(val, dict) and val.get("type") == "control":
                        _check_control(
                            f"values[{col_id!r}] control", val.get("control"), loc
                        )

    for pi, el in all_elements:
        el_label = el.get("id") or "(unnamed)"
        for ai, action in enumerate(el.get("actions", []) or []):
            for fi, fx in enumerate(action.get("effects", []) or []):
                loc = f"elements[{pi}] ({el_label}).actions[{ai}].effects[{fi}]"
                _check_effect(fx, loc)

        if el.get("kind") == "chat":
            agent_id = el.get("agentId")
            if agent_id and agent_id not in agent_ids:
                issues.append((
                    "fail",
                    f"elements[{pi}] ({el_label}): agentId `{agent_id}` does not "
                    "match any `agents[].id` in the spec. The chat element will render "
                    "with no agent attached."
                ))

    for gi, agent in enumerate(spec.get("agents") or []):
        agent_label = agent.get("id") or "(unnamed)"
        for ti, tool in enumerate(agent.get("tools", []) or []):
            tool_label = tool.get("toolId") or "(unnamed)"
            for si, step in enumerate(tool.get("steps", []) or []):
                loc = f"agents[{gi}] ({agent_label}).tools[{ti}] ({tool_label}).steps[{si}]"
                _check_effect(step, loc)

    return issues


# Sigma aggregation function names that make a column an "aggregation column"
# — i.e. the column has no per-row value, so bare refs from a KPI value
# formula resolve to null.
#
# `Percentile` (no Cont/Disc suffix) and `GetPercentile` were removed
# 2026-08-30 — both confirmed NOT to exist in Sigma (see
# `reference/specification/formulas.md` → the Percentile retraction
# warning, and `reference/history.md` → "2026-08-04" for `Percentile`;
# `GetPercentile` was an additional, previously-undetected fake name
# found independently while auditing this list against Sigma's own
# aggregate-functions catalog — it was never caught failing at render,
# unlike `Percentile`/`DivideSafe`, so there's no incident entry for it).
# The `*If` conditional-aggregate family was added the same day so this
# classifier still recognizes the native form after a `Sum(If(...))` →
# `SumIf(...)` rewrite (see "Conditional aggregates" in formulas.md).
#
# Also added the same day: `PercentileCont`/`PercentileDisc` explicitly.
# The bare `Percentile` alternative previously in this list never
# actually matched either of these real function names — `\bPercentile`
# matches, but the following `\s*\(` then fails against the literal
# `Cont(`/`Disc(` suffix, so the whole alternative fails and (since none
# of the other alternatives match either) the search fails outright.
# This was a real, pre-existing classifier gap independent of the
# `Percentile` retraction itself; fixed here while already auditing this
# pattern rather than filed separately.
_AGG_FN_PATTERN = re.compile(
    r"\b("
    r"Sum|SumIf|Avg|AvgIf|Count|CountIf|CountDistinct|CountDistinctIf|"
    r"CountNonNull|Min|MinIf|Max|MaxIf|Median|"
    r"PercentileCont|PercentileDisc|"
    r"StdDev|StdDevP|Variance|VarianceP|Mode|First|Last|"
    r"Any"
    r")\s*\(",
    re.IGNORECASE,
)


def _formula_contains_aggregation(formula: str) -> bool:
    """True if the formula uses any Sigma aggregation function.

    Regex-based — a bracketed reference like `[Sum]` that isn't a function
    call won't match because of the required `(`. False positives possible
    when an aggregation function appears inside a string literal.
    """
    if not formula:
        return False
    return bool(_AGG_FN_PATTERN.search(formula))


def issues_kpi_value_references_aggregation(spec: dict) -> list[tuple[str, str]]:
    """Warn when a KPI value column's formula bare-refs a sibling aggregation.

    Bare `[Sibling]` refs on a KPI evaluate per-row of the source table
    first, then aggregate. If the sibling column contains `Sum(...)`,
    `Avg(...)`, or another aggregation function, the bare ref has no
    per-row value and the whole expression resolves to `null` — the KPI
    tile renders "null" silently.

    Added 2026-07-02 after `Marketing-and-Promotions-Performance` had a
    Promo Lift KPI render null: value column's formula referenced two
    sibling aggregation columns via `[Promo AOV]` and `[Non-Promo AOV]`.

    Warn-level, not fail — the pattern could theoretically work if the
    sibling's aggregation resolves to a single scalar the parser
    accepts. Inspect flagged cases; the fix is usually to inline the
    aggregation into the value formula.
    """
    issues = []
    for pi, el in _all_elements(spec):
        if el.get("kind") != "kpi-chart":
            continue
        value = el.get("value") or {}
        value_col_id = value.get("columnId") or value.get("id")
        if not value_col_id:
            continue

        cols = el.get("columns") or []
        cols_by_id = {c.get("id"): c for c in cols if c.get("id")}
        # Map sibling `name` → whether its formula contains an aggregation.
        agg_siblings_by_name: dict[str, str] = {}  # name → sibling id
        for c in cols:
            cname = _inferred_column_name(c)
            if cname and _formula_contains_aggregation(c.get("formula") or ""):
                agg_siblings_by_name[cname] = c.get("id") or "(no-id)"

        value_col = cols_by_id.get(value_col_id)
        if not value_col:
            continue
        value_formula = value_col.get("formula") or ""
        if not value_formula:
            continue

        bare_refs = re.findall(r"\[([^/\]]+)\]", value_formula)
        offending = [(r, agg_siblings_by_name[r]) for r in bare_refs
                     if r in agg_siblings_by_name]
        if not offending:
            continue

        kpi_label = (el.get("name") or {}).get("text") if isinstance(el.get("name"), dict) else el.get("name")
        kpi_label = kpi_label or el.get("id")
        refs_str = ", ".join(f"`[{name}]` (sibling `{sid}`)" for name, sid in offending)
        issues.append((
            "warn",
            f"elements[{pi}] ({el.get('id')}, kpi-chart '{kpi_label}'): "
            f"value formula bare-refs sibling column(s) whose formulas contain "
            f"aggregation functions: {refs_str}. Aggregation refs have no "
            f"per-row value, so the KPI will render 'null'. Inline the "
            f"aggregations into the value column's own formula, or promote the "
            f"expression to a data-model metric. Formula: {value_formula}"
        ))
    return issues


def issues_summary_calc_collision(spec: dict) -> list[tuple[str, str]]:
    """Catch column IDs that appear in both `summary` and a grouping's
    `calculations` list on the same table.

    Sigma rejects the POST with `Duplicate column or folder reference:
    '<col-id>'`. The fix is to define two separate columns with distinct
    ids (same formula is fine) and put one in each list.

    Added 2026-07-02 after `exec-scorecard` v1 hit this mid-build.
    """
    issues = []
    for pi, el in _all_elements(spec):
        summary_ids = set(el.get("summary") or [])
        if not summary_ids:
            continue
        for gi, grouping in enumerate(el.get("groupings") or []):
            calc_ids = set(grouping.get("calculations") or [])
            collision = summary_ids & calc_ids
            if collision:
                cols = ", ".join(f"`{c}`" for c in sorted(collision))
                el_label = el.get("id") or "(unnamed)"
                issues.append((
                    "fail",
                    f"elements[{pi}] ({el_label}, {el.get('kind')}): "
                    f"column ID(s) {cols} appear in both `summary` and "
                    f"`groupings[{gi}].calculations`. Sigma rejects this "
                    f"as a duplicate reference. Split into two column "
                    f"definitions with distinct ids (same formula OK) — "
                    f"one in `summary`, one in `calculations`."
                ))
    return issues


def issues_description_object_on_kpi_and_table(spec: dict) -> list[tuple[str, str]]:
    """Catch string-form `description` fields on KPI / table / pivot-table
    elements — the API rejects with `Invalid object: string`.

    Description must be an object (`{text: "..."}` or
    `{visibility: "hidden"}`). Chart elements accept the string form
    fine; only KPIs, tables, and pivot-tables enforce the object form.

    Added 2026-07-02 after `inventory-health` build hit this on a KPI
    with a plain-string description.
    """
    OBJECT_ONLY = {"kpi-chart", "table", "pivot-table", "input-table"}
    issues = []
    for pi, el in _all_elements(spec):
        if el.get("kind") not in OBJECT_ONLY:
            continue
        desc = el.get("description")
        if desc is None:
            continue
        if isinstance(desc, str):
            el_label = el.get("id") or "(unnamed)"
            preview = desc[:60] + "..." if len(desc) > 60 else desc
            issues.append((
                "fail",
                f"elements[{pi}] ({el_label}, {el.get('kind')}): "
                f"`description` is a string ({preview!r}); on this "
                f"element kind it must be an object. POST will reject "
                f"with `Invalid object: string`. Wrap as "
                f'`{{"text": "..."}}` or `{{"visibility": "hidden"}}`.'
            ))
    return issues


def issues_pivot_missing_rows_and_columns(spec: dict) -> list[tuple[str, str]]:
    """Fail-level: a pivot-table with `values` but neither `rowsBy` nor
    `columnsBy` renders as a single grand-total row — the pivot compiles
    cleanly (passes validate + verify) but visibly renders no rows or
    columns in the UI, only the summed measure.

    Fires when: `kind == "pivot-table"`, `values` non-empty, AND both
    `rowsBy` and `columnsBy` are missing/empty.

    A pivot with only one of rowsBy/columnsBy is a valid single-axis
    pivot (e.g., grouped list view) — not flagged.

    Added 2026-07-02 after `Product-and-Basket-Performance` shipped
    two pivots that rendered as grand-total-only in the UI.
    """
    issues = []
    for pi, el in _all_elements(spec):
        if el.get("kind") != "pivot-table":
            continue
        values = el.get("values") or []
        if not values:
            continue
        rows = el.get("rowsBy") or []
        cols = el.get("columnsBy") or []
        if not rows and not cols:
            el_label = el.get("id") or "(unnamed)"
            name = el.get("name")
            title = name.get("text") if isinstance(name, dict) else name
            issues.append((
                "fail",
                f"elements[{pi}] ({el_label}, pivot-table"
                + (f" '{title}'" if title else "")
                + f"): has `values` ({', '.join(values)}) but neither "
                f"`rowsBy` nor `columnsBy` — the pivot will render as a "
                f"single grand-total row. Add at least one dimension "
                f"binding: `\"rowsBy\": [{{\"id\": \"<dim-col-id>\"}}]` "
                f"and/or `\"columnsBy\": [{{\"id\": \"<dim-col-id>\"}}]`."
            ))
    return issues


# Maps the plain-aggregate function name used in the `<Fn>(If(...))`
# anti-pattern to its native `*If` replacement + a null-behavior note.
# Only `Sum`→`SumIf` actually changes null-vs-zero behavior on rewrite
# (see formulas.md → "Conditional aggregates" for why): the anti-pattern
# is only sensibly written with a `0` else-branch for `Sum` (a `0`
# else-branch on `Min`/`Max`/`Avg` would corrupt the result), so those
# four already return NULL on an empty match today, same as their `*If`
# counterparts. `CountDistinctIf`'s empty-match behavior isn't
# explicitly documented by Sigma either way — flagged defensively.
_CONDITIONAL_AGG_NATIVE_FORM = {
    "sum": (
        "SumIf(<value>, <condition>)",
        "returns NULL (not 0) on an empty match — if the original used "
        "a `0` else-branch, wrap the rewrite: Zn(SumIf(<value>, <condition>))",
    ),
    "count": (
        "CountIf(<condition>)",
        "returns 0 on an empty match, same as the composed form — no "
        "null-behavior change",
    ),
    "countdistinct": (
        "CountDistinctIf(<value>, <condition>)",
        "empty-match behavior isn't explicitly documented by Sigma; "
        "verify before assuming parity, and wrap in Coalesce(..., 0) "
        "defensively if a non-null result is required",
    ),
    "avg": (
        "AvgIf(<value>, <condition>)",
        "returns NULL on an empty match, same as the composed form "
        "(assuming a Null, not 0, else-branch) — no null-behavior change",
    ),
    "min": (
        "MinIf(<value>, <condition>)",
        "returns NULL on an empty match, same as the composed form "
        "(assuming a Null, not 0, else-branch) — no null-behavior change",
    ),
    "max": (
        "MaxIf(<value>, <condition>)",
        "returns NULL on an empty match, same as the composed form "
        "(assuming a Null, not 0, else-branch) — no null-behavior change",
    ),
}

_CONDITIONAL_AGG_ANTIPATTERN = re.compile(
    r"\b(Sum|CountDistinct|Count|Avg|Min|Max)\s*\(\s*If\s*\(",
    re.IGNORECASE,
)


def issues_conditional_aggregate_antipattern(spec: dict) -> list[tuple[str, str]]:
    """Warn on the `Sum(If(...))`-style composition where a native
    Sigma `*If` conditional-aggregate function exists instead.

    Until 2026-08-30, this skill's own formula reference never
    documented Sigma's native conditional-aggregate family (`SumIf`,
    `CountIf`, `CountDistinctIf`, `AvgIf`, `MinIf`, `MaxIf`) — so the
    only way this skill ever taught expressing a conditional aggregate
    was composing a plain aggregate around a nested `If(...)`:
    `Sum(If(<cond>, <x>, 0))`, `Count(If(<cond>, ...))`,
    `CountDistinct(If(<cond>, <x>, Null))`, and the `Avg`/`Min`/`Max`
    equivalents. That composition compiles and renders — this is not a
    validity problem — but it's non-idiomatic now that the native form
    is documented, and (for `Sum` specifically) the two forms have
    different null behavior on an empty match. See
    `reference/specification/formulas.md` → "Conditional aggregates —
    the `*If` family" for the full mapping this warning references.

    WARN-level, not FAIL: flags working, non-idiomatic output, not a
    broken spec.
    """
    issues = []
    for pi, el in _all_elements(spec):
        for col in el.get("columns") or []:
            formula = col.get("formula") or ""
            if not formula:
                continue
            seen = set()
            for m in _CONDITIONAL_AGG_ANTIPATTERN.finditer(formula):
                plain_fn = m.group(1)
                key = plain_fn.lower()
                if key in seen:
                    continue
                seen.add(key)
                native, null_note = _CONDITIONAL_AGG_NATIVE_FORM.get(
                    key, (f"{plain_fn}If(...)", "verify null behavior before relying on it")
                )
                col_label = col.get("name") or col.get("id") or "(unnamed)"
                issues.append((
                    "warn",
                    f"elements[{pi}] ({el.get('id')}) / column '{col_label}': "
                    f"formula uses the `{plain_fn}(If(...))` composition — "
                    f"Sigma has a native conditional-aggregate form for this, "
                    f"`{native}`. Prefer the native form ({null_note}). See "
                    f"reference/specification/formulas.md → 'Conditional "
                    f"aggregates — the *If family'. Formula: {formula}"
                ))
    return issues


def _load_spec(path: str) -> dict:
    """Load a spec from JSON or YAML.

    YAML support ported 2026-08-03 from the real upstream `sigma-workbooks`
    skill's `validate-spec.sh`, which handles `.yaml`/`.yml` via a
    PyYAML-or-`yq` fallback chain. `SKILL.md` already documents that YAML
    specs arrive from users; the validator was JSON-only until now.
    """
    if not path.endswith((".yaml", ".yml")):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    try:
        import yaml  # type: ignore
    except ImportError:
        pass
    else:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f)
    import subprocess
    for cmd in (["yq", "-o=json", path], ["yq", ".", path]):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return json.loads(result.stdout)
        except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError):
            continue
    sys.stderr.write(
        "validate-spec: YAML input requires PyYAML (`pip install pyyaml`) "
        "or `yq` on PATH (either mikefarah/yq or the Python yq wrapper — "
        "both read the same via `yq .`).\n"
    )
    sys.exit(2)


def main() -> None:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: validate-spec.py <spec.json|spec.yaml>\n")
        sys.exit(2)
    spec = _load_spec(sys.argv[1])

    root = _parse_layout(spec.get("layout", ""))

    all_issues: list[tuple[str, str, str]] = []
    for tag, fn in [
        ("schema-version",            lambda: issues_schema_version(spec)),
        ("no-per-page-layout",        lambda: issues_per_page_layout(spec)),
        ("elements-placed-in-layout", lambda: issues_elements_placed(spec, root)),
        ("containers-have-children",  lambda: issues_containers_have_children(spec, root)),
        ("layoutelement-has-children", lambda: issues_layoutelement_has_children(root)),
        ("column-format-shape",       lambda: issues_column_format_shape(spec)),
        ("control-id-unique",         lambda: issues_control_id_unique(spec)),
        ("passthrough-coverage",      lambda: issues_passthrough_coverage(spec)),
        ("controlid-collision",       lambda: issues_controlid_collision(spec)),
        ("bare-ref-resolution",       lambda: issues_bare_ref_resolution(spec)),
        ("control-filter-column-exists", lambda: issues_control_filter_column_exists(spec)),
        ("action-refs-resolve",       lambda: issues_action_refs_resolve(spec)),
        ("kpi-value-references-aggregation", lambda: issues_kpi_value_references_aggregation(spec)),
        ("summary-calc-collision",     lambda: issues_summary_calc_collision(spec)),
        ("description-object-on-kpi-and-table", lambda: issues_description_object_on_kpi_and_table(spec)),
        ("pivot-missing-rows-and-columns", lambda: issues_pivot_missing_rows_and_columns(spec)),
        ("channel-exclusivity",       lambda: issues_channel_exclusivity(spec)),
        ("conditional-aggregate-antipattern", lambda: issues_conditional_aggregate_antipattern(spec)),
    ]:
        for level, msg in fn():
            all_issues.append((level, tag, msg))

    fail_count = sum(1 for level, _, _ in all_issues if level == "fail")
    warn_count = sum(1 for level, _, _ in all_issues if level == "warn")

    limitations = (
        "Note: these checks catch known failure signatures from past sessions "
        "— a clean run does not guarantee the spec renders correctly. "
        "`bare-ref-resolution` only catches bare (unqualified) refs; qualified "
        "refs are not verified here (the server checks those on publish). "
        "`action-refs-resolve` verifies overlayId/control/table/tabbedContainer/"
        "agentId references, including inside agents[].tools[].steps[] — always "
        "visually verify after publish."
    )

    if not all_issues:
        print(f"validate-spec: {sys.argv[1]} — all {len(CHECKS)} checks passed")
        print(limitations)
        sys.exit(0)

    for level, tag, msg in all_issues:
        prefix = "FAIL" if level == "fail" else "WARN"
        sys.stderr.write(f"[{prefix}][{tag}] {msg}\n")

    summary = f"validate-spec: {fail_count} fail, {warn_count} warn in {sys.argv[1]}"
    sys.stderr.write(f"\n{summary}\n{limitations}\n")
    sys.exit(1 if fail_count else 0)


if __name__ == "__main__":
    main()
