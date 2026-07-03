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
    "no-per-page-layout",
    "elements-placed-in-layout",
    "containers-have-children",
    "column-format-shape",
    "control-id-unique",
    "passthrough-coverage",
    "controlid-collision",
    "bare-ref-resolution",
    "control-filter-column-exists",
    "kpi-value-references-aggregation",
    "summary-calc-collision",
    "description-object-on-kpi-and-table",
    "pivot-missing-rows-and-columns",
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
    placed_ids = {
        el.get("elementId")
        for el in root.iter()
        if el.tag in ("LayoutElement", "GridContainer")
    }
    issues = []
    for pi, p in enumerate(spec.get("pages", [])):
        for el in p.get("elements", []):
            eid = el.get("id")
            if eid and eid not in placed_ids:
                issues.append((
                    "fail",
                    f"pages[{pi}].elements ({eid}, kind={el.get('kind')}): "
                    "not placed in the layout XML — will render at the page bottom or not at all."
                ))
    return issues


def issues_containers_have_children(spec: dict, root: ET.Element | None) -> list[tuple[str, str]]:
    if root is None:
        return []
    container_ids = [
        el.get("id")
        for p in spec.get("pages", [])
        for el in p.get("elements", [])
        if el.get("kind") == "container"
    ]
    issues = []
    for cid in container_ids:
        gc = next((el for el in root.iter("GridContainer") if el.get("elementId") == cid), None)
        if gc is None:
            issues.append((
                "fail",
                f"container element `{cid}`: no matching <GridContainer> in layout XML."
            ))
        elif len(list(gc)) == 0:
            issues.append((
                "fail",
                f"container element `{cid}`: <GridContainer> has no nested children. "
                "Children must be nested INSIDE the <GridContainer>, not flat siblings."
            ))
    return issues


def issues_column_format_shape(spec: dict) -> list[tuple[str, str]]:
    """Per Phase 6b: `format` IS spec-able, but only with `kind` + `formatString`.

    The UI-emitted shape `{type: "number", format: "currency"}` is rejected
    with "Missing 'kind' field". The verified shape is
    `{kind: "number", formatString: "$,.2f"}`.
    """
    issues = []
    for pi, p in enumerate(spec.get("pages", [])):
        for ei, el in enumerate(p.get("elements", [])):
            for ci, col in enumerate(el.get("columns", []) or []):
                fmt = col.get("format")
                if fmt is None:
                    continue
                if not isinstance(fmt, dict):
                    issues.append((
                        "fail",
                        f"pages[{pi}].elements[{ei}].columns[{ci}] ({col.get('id')}): "
                        f"`format` must be an object, got {type(fmt).__name__}."
                    ))
                    continue
                if "kind" not in fmt:
                    issues.append((
                        "fail",
                        f"pages[{pi}].elements[{ei}].columns[{ci}] ({col.get('id')}): "
                        "`format` is missing required `kind` field. "
                        "Verified shape: {kind: \"number\", formatString: \"$,.2f\"}. "
                        "If this came from a UI export ({type: ..., format: ...}), strip and re-spec."
                    ))
    return issues


def issues_control_id_unique(spec: dict) -> list[tuple[str, str]]:
    seen: dict[str, str] = {}
    issues = []
    for p in spec.get("pages", []):
        for el in p.get("elements", []):
            if el.get("kind") != "control":
                continue
            cid = el.get("controlId")
            if not cid:
                continue
            if cid in seen:
                issues.append((
                    "fail",
                    f"controlId `{cid}` duplicated on elements {seen[cid]} and {el.get('id')}. "
                    "controlId is workbook-wide unique."
                ))
            else:
                seen[cid] = el.get("id")
    return issues


def _all_elements(spec: dict) -> list[tuple[int, dict]]:
    """Yield (page_index, element) for every element in every page."""
    out = []
    for pi, p in enumerate(spec.get("pages", [])):
        for el in p.get("elements", []):
            out.append((pi, el))
    return out


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
                    f"pages[{pi}].elements ({el.get('id')}, kind={kind}): "
                    f"only {viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). Likely passthrough collapse — "
                    "right-click drill will be crippled. Default is "
                    "passthrough-all; see SKILL.md → 'Load-bearing rules' → rule #1."
                ))
            elif viz_cols <= 4 and src_cols >= 10:
                issues.append((
                    "warn",
                    f"pages[{pi}].elements ({el.get('id')}, kind={kind}): "
                    f"{viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). May be thin passthrough — "
                    "intentional only if source has many irrelevant cols. "
                    "See SKILL.md → 'Load-bearing rules' → rule #1."
                ))
        elif kind in PIVOT_KINDS:
            if viz_cols <= 2:
                issues.append((
                    "warn",
                    f"pages[{pi}].elements ({el.get('id')}, kind={kind}): "
                    f"only {viz_cols} columns vs {src_cols} on source table "
                    f"({src_table.get('id')}). Pivot may be missing dimension "
                    "or value cols. See SKILL.md → 'Load-bearing rules' → rule #1."
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
                        f"pages[{pi}].elements ({el.get('id')}, control): "
                        f"controlId `{cid}` collides with column "
                        f"`{col.get('id')}` (name: `{col.get('name')}`) on filtered "
                        f"element `{target_eid}`. Formulas referencing `[{cid}]` "
                        "will resolve to the control, not the column. "
                        "Rename the control (e.g. `DateRange`, `StoreFilter`)."
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
    for page in spec.get("pages", []):
        for el in page.get("elements", []):
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
    for page in spec.get("pages", []):
        for element in page.get("elements", []):
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
                    f"pages[{pi}].elements ({ctrl_id}, control '{ctrl_label}'): "
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
                    f"pages[{pi}].elements ({ctrl_id}, control '{ctrl_label}'): "
                    f"filters[{fi}].columnId `{column_id}` does not exist on "
                    f"target element `{target_eid}`. The control will render "
                    f"but no downstream element will filter.{near_hint}"
                ))
    return issues


# Sigma aggregation function names that make a column an "aggregation column"
# — i.e. the column has no per-row value, so bare refs from a KPI value
# formula resolve to null.
_AGG_FN_PATTERN = re.compile(
    r"\b("
    r"Sum|Avg|Count|CountDistinct|CountNonNull|Min|Max|Median|"
    r"Percentile|StdDev|StdDevP|Variance|VarianceP|Mode|First|Last|"
    r"Any|GetPercentile"
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
            f"pages[{pi}].elements ({el.get('id')}, kpi-chart '{kpi_label}'): "
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
                    f"pages[{pi}].elements ({el_label}, {el.get('kind')}): "
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
                f"pages[{pi}].elements ({el_label}, {el.get('kind')}): "
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
                f"pages[{pi}].elements ({el_label}, pivot-table"
                + (f" '{title}'" if title else "")
                + f"): has `values` ({', '.join(values)}) but neither "
                f"`rowsBy` nor `columnsBy` — the pivot will render as a "
                f"single grand-total row. Add at least one dimension "
                f"binding: `\"rowsBy\": [{{\"id\": \"<dim-col-id>\"}}]` "
                f"and/or `\"columnsBy\": [{{\"id\": \"<dim-col-id>\"}}]`."
            ))
    return issues


def main() -> None:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: validate-spec.py <spec.json>\n")
        sys.exit(2)
    with open(sys.argv[1]) as f:
        spec = json.load(f)

    root = _parse_layout(spec.get("layout", ""))

    all_issues: list[tuple[str, str, str]] = []
    for tag, fn in [
        ("no-per-page-layout",        lambda: issues_per_page_layout(spec)),
        ("elements-placed-in-layout", lambda: issues_elements_placed(spec, root)),
        ("containers-have-children",  lambda: issues_containers_have_children(spec, root)),
        ("column-format-shape",       lambda: issues_column_format_shape(spec)),
        ("control-id-unique",         lambda: issues_control_id_unique(spec)),
        ("passthrough-coverage",      lambda: issues_passthrough_coverage(spec)),
        ("controlid-collision",       lambda: issues_controlid_collision(spec)),
        ("bare-ref-resolution",       lambda: issues_bare_ref_resolution(spec)),
        ("control-filter-column-exists", lambda: issues_control_filter_column_exists(spec)),
        ("kpi-value-references-aggregation", lambda: issues_kpi_value_references_aggregation(spec)),
        ("summary-calc-collision",     lambda: issues_summary_calc_collision(spec)),
        ("description-object-on-kpi-and-table", lambda: issues_description_object_on_kpi_and_table(spec)),
        ("pivot-missing-rows-and-columns", lambda: issues_pivot_missing_rows_and_columns(spec)),
    ]:
        for level, msg in fn():
            all_issues.append((level, tag, msg))

    fail_count = sum(1 for level, _, _ in all_issues if level == "fail")
    warn_count = sum(1 for level, _, _ in all_issues if level == "warn")

    if not all_issues:
        print(f"validate-spec: {sys.argv[1]} — all {len(CHECKS)} checks passed")
        sys.exit(0)

    for level, tag, msg in all_issues:
        prefix = "FAIL" if level == "fail" else "WARN"
        sys.stderr.write(f"[{prefix}][{tag}] {msg}\n")

    summary = f"validate-spec: {fail_count} fail, {warn_count} warn in {sys.argv[1]}"
    sys.stderr.write(f"\n{summary}\n")
    sys.exit(1 if fail_count else 0)


if __name__ == "__main__":
    main()
