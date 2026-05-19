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
