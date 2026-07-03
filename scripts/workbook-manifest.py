#!/usr/bin/env python3
"""
Produce a markdown checklist of what's in a Sigma workbook spec.

Usage:
    python3 scripts/workbook-manifest.py <spec.json> [--out manifest.md]

Goal: eyeball-validate that the code spec faithfully captures what the
workbook actually renders in the Sigma UI. Per-page checklist of elements
grouped by kind, with cross-cutting feature flags (dynamic titles,
conditional formatting, element styling, hidden pages, etc.).

The "unknown_keys" lines are the load-bearing part of the output. When a
harvested spec contains a field the recognized schema doesn't know about,
that field appears in unknown_keys — surfacing gaps in our extraction
immediately. As we encode each new capability into the skill, we extend
the recognized schema here so the field stops appearing as unknown.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


# Recognized top-level spec keys. Anything else flags as unknown.
# `layout` lives at the top level (one XML string containing one <Page> doc
# per workbook page, concatenated). GET-spec responses include the metadata
# block (createdAt..workbookId) that's stripped before POST.
SPEC_KEYS = {
    "name", "schemaVersion", "folderId", "pages", "controls", "description",
    "layout", "folders", "themeOverrides",
    # GET-spec metadata — present on round-trip, not part of authored spec.
    "createdAt", "createdBy", "documentVersion", "latestDocumentVersion",
    "ownerId", "updatedAt", "updatedBy", "url", "workbookId",
}

# Recognized page-level keys.
# `visibility: "hidden"` is the hidden-page field. `hidden` is the older alias
# we keep recognizing in case a spec uses it.
PAGE_KEYS = {"id", "name", "elements", "hidden", "visibility", "description"}

# Recognized keys per element kind. Each entry is a set of known top-level
# fields ON the element body. Unknown keys flag as gaps.
#
# COMMON_KEYS apply to every element kind; per-kind sets layer on top.
# `layout` here is the element-level layout OBJECT (e.g., {anchor: "middle"}),
# distinct from the top-level layout XML string.
COMMON_KEYS = {"id", "kind", "name", "source", "style", "description", "layout"}

# Cartesian-chart-specific keys (refMarks/trendlines/dataLabel/seriesDataLabel)
# verified 2026-05-21 from the upstream sigma-workbooks skill — applies to
# bar/line/area/combo/scatter.
CARTESIAN_EXTRAS = {
    "refMarks", "trendlines", "dataLabel", "seriesDataLabel",
}

ELEMENT_KEYS = {
    "kpi-chart": COMMON_KEYS | {
        "columns", "value", "filters", "format", "comparison",
        "trend", "sparkline", "legend",
    },
    "bar-chart": COMMON_KEYS | CARTESIAN_EXTRAS | {
        "columns", "xAxis", "yAxis", "color", "orientation",
        "stacking", "filters", "legend", "axis", "format",
        "gap",  # {width, betweenSets} — bar/set spacing
    },
    "line-chart": COMMON_KEYS | CARTESIAN_EXTRAS | {
        "columns", "xAxis", "yAxis", "color", "filters", "legend",
        "axis", "format", "gap",
    },
    "area-chart": COMMON_KEYS | CARTESIAN_EXTRAS | {
        "columns", "xAxis", "yAxis", "color", "stacking",
        "filters", "legend", "axis", "format", "gap",
    },
    "combo-chart": COMMON_KEYS | CARTESIAN_EXTRAS | {
        "columns", "xAxis", "yAxis", "color", "filters", "legend",
        "axis", "format", "gap",
    },
    "pie-chart": COMMON_KEYS | {
        "columns", "color", "value", "filters", "legend", "format",
    },
    "donut-chart": COMMON_KEYS | {
        "columns", "color", "value", "filters", "legend", "format",
        "holeValue",  # references a column by id for the donut hole label
        "dataLabel",  # labels/labelDisplay ("percent", etc.)
    },
    "scatter-chart": COMMON_KEYS | CARTESIAN_EXTRAS | {
        "columns", "xAxis", "yAxis", "color", "size",
        "filters", "legend", "axis", "format",
    },
    "pivot-table": COMMON_KEYS | {
        "columns", "rowsBy", "columnsBy", "values", "filters",
        "conditionalFormatting",  # legacy key
        "conditionalFormats",     # current key per upstream (4 variants)
        "totals", "format",
        "tableStyle", "tableComponents",
    },
    "table": COMMON_KEYS | {
        "columns", "groupings", "order", "filters",
        "conditionalFormatting",  # legacy key
        "conditionalFormats",     # current key per upstream (4 variants)
        "format",
        "visibleAsSource",        # bool — whether table is exposed as a source
        "summary",                # list[col-id] — summary-bar pattern
        "folders",                # list[{id, name, items?}] — column-folder groupings
        "noDataText",             # string — empty-state caption
        "tableStyle",             # {banding, preset, cellSpacing, textStyles}
        "tableComponents",        # {collapsedColumns: [...]}
    },
    "container": COMMON_KEYS | {
        "backgroundImage",        # object {url, style: {fit, align, tiling}}
        "backgroundColor",        # legacy — newer specs nest under `style`
    },
    "text": COMMON_KEYS | {
        "body", "verticalAlign", "horizontalAlign", "overflow", "format",
    },
    "control": COMMON_KEYS | {
        "controlId", "controlType", "filters", "mode", "selectionMode",
        "values", "value", "showOperators", "showClearLabel",
        "includeNulls", "case", "min", "max", "step", "defaultValue",
        "options", "label", "placeholder",
        # Date-range mode-specific fields:
        "startDate", "endDate", "date", "unit", "includeToday",
    },
    # Content elements (non-data-bound).
    "divider": COMMON_KEYS | {
        "direction",     # "horizontal" | "vertical"
        "align",         # e.g. "middle"
        # style set inherited via COMMON_KEYS ({color, width, strokeStyle})
    },
    "image":   COMMON_KEYS | {"url", "alt", "link"},  # url supports {{formula}}
    "embed":   COMMON_KEYS | {"url"},         # renders external URL inline

    # Map elements (verified 2026-07-02).
    "geography-map": COMMON_KEYS | {
        "columns", "geography", "color", "label", "tooltip",
        "filters", "legend", "mapStyle",
    },
    "point-map": COMMON_KEYS | {
        "columns", "latitude", "longitude", "size", "color",
        "label", "tooltip", "filters", "legend", "mapStyle",
    },
    "region-map": COMMON_KEYS | {
        "columns", "region", "color", "label", "tooltip",
        "filters", "legend", "mapStyle",
    },

    # Editable-table element (documented upstream; limited value without actions).
    "input-table": COMMON_KEYS | {
        "columns", "inputMode", "filters", "conditionalFormats",
        "sort", "summary", "noDataText",
    },

    # Theme reference — a directive element, not data-bound.
    "theme": {"kind", "ref"},
}

# Per-controlType recognized keys layered on top of the base "control" set.
# `text-area`, `toggle`, `checkbox`, `dropdown`, `radio` documented in the
# upstream sigma-workbooks skill 2026-05-21.
CONTROL_TYPE_KEYS = {
    "list":         {"selectionMode", "values", "mode", "source"},
    "date-range":   {"mode", "includeNulls", "startDate", "endDate",
                     "date", "unit", "value", "includeToday"},
    "date":         {"mode", "includeNulls", "date", "value"},
    "text":         {"mode", "value", "includeNulls", "case", "showOperators"},
    "text-area":    {"mode", "value", "includeNulls", "case", "showOperators"},
    "segmented":    {"showClearLabel", "source", "value"},
    "number":       {"mode", "value", "min", "max", "step", "includeNulls"},
    "number-range": {"mode", "min", "max", "step", "values"},
    "slider":       {"mode", "value", "min", "max", "step"},
    "range-slider": {"mode", "values", "min", "max", "step"},
    "toggle":       {"value"},
    "switch":       {"value"},
    "checkbox":     {"value"},
    "dropdown":     {"selectionMode", "values", "mode", "source"},
    "radio":        {"selectionMode", "values", "mode", "source"},
    "hierarchy":    {"selectionMode", "values", "mode", "source"},
}

CHART_KINDS = {
    "bar-chart", "line-chart", "area-chart", "combo-chart",
    "pie-chart", "donut-chart", "scatter-chart", "kpi-chart",
}

# Known kinds that produce a manifest entry; anything else is flagged.
KNOWN_KINDS = set(ELEMENT_KEYS.keys())


def is_formula_string(s: Any) -> bool:
    """Detect formula-looking strings inside name/title fields (signal of dynamic content)."""
    if not isinstance(s, str):
        return False
    return bool(re.search(r"=|\[|\$\{|Concat\(|Text\(", s))


def has_template_var(s: Any) -> bool:
    """Detect Sigma template syntax — the actual signal of dynamic text bodies."""
    if not isinstance(s, str):
        return False
    return bool(re.search(r"\{\{[^}]*\}\}|\$\{[^}]*\}", s))


def page_summary(page: dict, idx: int, layouts_by_pid: dict[str, str]) -> list[str]:
    lines: list[str] = []
    pid = page.get("id", "<no-id>")
    pname = page.get("name", "<unnamed>")
    hidden = page.get("hidden") or page.get("visibility") == "hidden"
    hidden_flag = " — **HIDDEN**" if hidden else ""
    lines.append(f"### Page {idx + 1}: {pname}  `{pid}`{hidden_flag}")

    desc = page.get("description")
    if desc:
        lines.append(f"- description: `{json.dumps(desc)[:120]}`")

    unknown_page_keys = sorted(set(page.keys()) - PAGE_KEYS)
    if unknown_page_keys:
        lines.append(f"- ⚠️  unknown page-level keys: `{unknown_page_keys}`")

    elements = page.get("elements", []) or []
    lines.append(f"- elements: {len(elements)}")

    by_kind: dict[str, int] = {}
    for el in elements:
        k = el.get("kind", "<no-kind>")
        by_kind[k] = by_kind.get(k, 0) + 1
    if by_kind:
        breakdown = ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items()))
        lines.append(f"- kind breakdown: {breakdown}")

    page_layout = layouts_by_pid.get(pid)
    if page_layout:
        lines.extend(summarize_layout(page_layout))

    lines.append("")
    lines.append("**Elements:**")
    lines.append("")
    for el in elements:
        lines.extend(element_summary(el))
    return lines


def summarize_layout(layout_xml: str) -> list[str]:
    """Parse layout XML and surface container styling + element count."""
    lines: list[str] = []
    try:
        root = ET.fromstring(layout_xml)
    except ET.ParseError as exc:
        lines.append(f"- ⚠️  layout XML parse error: {exc}")
        return lines

    # Top-level Page attrs (style hints would appear here).
    page_attrs = dict(root.attrib)
    interesting_page = {k: v for k, v in page_attrs.items()
                        if k not in ("type", "gridTemplateColumns",
                                     "gridTemplateRows", "id")}
    if interesting_page:
        lines.append(f"- 🎨 page-level layout attrs (non-grid): `{interesting_page}`")

    layout_elements = root.findall(".//LayoutElement")
    grid_containers = root.findall(".//GridContainer")
    lines.append(f"- layout: {len(layout_elements)} placed elements, "
                 f"{len(grid_containers)} grid containers")

    # Surface any container styling encoded in XML attributes.
    for gc in grid_containers:
        styling = {k: v for k, v in gc.attrib.items()
                   if k not in ("elementId", "gridColumn", "gridRow",
                                "gridTemplateColumns", "gridTemplateRows")}
        if styling:
            el_id = gc.attrib.get("elementId", "<no-id>")
            lines.append(f"  - 🎨 container `{el_id}` styling: `{styling}`")

    return lines


def element_summary(el: dict) -> list[str]:
    kind = el.get("kind", "<no-kind>")
    eid = el.get("id", "<no-id>")
    name_field = el.get("name")
    name_display = stringify_name(name_field)

    lines: list[str] = []
    header = f"- **{kind}** `{eid}`"
    if name_display:
        header += f" — {name_display}"
    lines.append(header)

    # Dynamic-title detector: name field is an object (styled) or contains formula.
    if isinstance(name_field, dict):
        lines.append("  - 🎨 styled `name` (object form — likely custom title styling)")
        # Recognized name-object keys per reference/specification/kpis.md
        # → "Title styling (styled-name object form)". `format`/`formula`/
        # `kind`/`value` are speculative future shapes; harmless to leave.
        unknown_name = sorted(set(name_field.keys()) - {
            "text", "color", "fontSize", "fontWeight", "visibility",
            "format", "formula", "kind", "value", "style",
        })
        if unknown_name:
            lines.append(f"    - ⚠️  unknown name-object keys: `{unknown_name}`")
    elif is_formula_string(name_field):
        lines.append("  - 🎨 dynamic title (formula detected in `name`)")

    # Element-level styling fields.
    if "style" in el:
        style = el.get("style") or {}
        style_keys = sorted(style.keys()) if isinstance(style, dict) else []
        lines.append(f"  - 🎨 `style` present: keys=`{style_keys}`")

    # Description (chart description styling lives here in newer specs).
    if "description" in el:
        d = el.get("description")
        if isinstance(d, dict):
            lines.append(f"  - 🎨 styled `description` (object form): keys=`{sorted(d.keys())}`")
        elif isinstance(d, str) and d:
            preview = d[:80] + ("..." if len(d) > 80 else "")
            lines.append(f"  - description: `{preview}`")

    # Kind-specific extraction.
    if kind == "kpi-chart":
        lines.extend(kpi_details(el))
    elif kind in CHART_KINDS:
        lines.extend(chart_details(el))
    elif kind == "pivot-table":
        lines.extend(pivot_details(el))
    elif kind == "table":
        lines.extend(table_details(el))
    elif kind == "container":
        lines.extend(container_details(el))
    elif kind == "text":
        lines.extend(text_details(el))
    elif kind == "control":
        lines.extend(control_details(el))
    elif kind not in KNOWN_KINDS:
        # NET-NEW kind — surface loudly.
        lines.append(f"  - ⚠️  **UNKNOWN ELEMENT KIND** `{kind}` — net-new capability candidate")
        lines.append(f"    - all keys: `{sorted(el.keys())}`")

    # Unknown keys at element top level (per recognized schema).
    recognized = ELEMENT_KEYS.get(kind, COMMON_KEYS)
    unknown = sorted(set(el.keys()) - recognized)
    if unknown:
        lines.append(f"  - ⚠️  unknown_keys: `{unknown}`")

    return lines


def stringify_name(name_field: Any) -> str:
    if name_field is None:
        return ""
    if isinstance(name_field, str):
        return name_field
    if isinstance(name_field, dict):
        # Common shapes: {text: "..."}, {formula: "..."}, {value: "..."}
        for key in ("text", "value", "formula"):
            if key in name_field and isinstance(name_field[key], str):
                return f"{name_field[key]} (styled)"
        return "(styled object)"
    return str(name_field)


def kpi_details(el: dict) -> list[str]:
    out: list[str] = []
    cols = el.get("columns") or []
    out.append(f"  - columns: {len(cols)}")
    val = el.get("value") or {}
    if val:
        # Verified 2026-07-02: the canonical KPI value field is `columnId`,
        # not `id`. Fall back to `id` so older exemplars still surface a
        # value here.
        col_ref = val.get("columnId") or val.get("id")
        out.append(f"  - value.columnId: `{col_ref}`")
    if "comparison" in el:
        out.append("  - 🎨 comparison/period-over-period present")
    if "trend" in el or "sparkline" in el:
        out.append("  - 🎨 trend/sparkline present")
    if "format" in el:
        out.append(f"  - format: `{el.get('format')}`")
    return out


def chart_details(el: dict) -> list[str]:
    out: list[str] = []
    cols = el.get("columns") or []
    out.append(f"  - columns: {len(cols)}")
    if "xAxis" in el:
        x = el["xAxis"] or {}
        x_keys = sorted(x.keys()) if isinstance(x, dict) else []
        out.append(f"  - xAxis keys: `{x_keys}`")
    if "yAxis" in el:
        y = el["yAxis"] or []
        if isinstance(y, list):
            out.append(f"  - yAxis: {len(y)} series, "
                       f"per-entry keys: `{sorted({k for s in y if isinstance(s, dict) for k in s.keys()})}`")
    if "color" in el:
        c = el["color"] or {}
        out.append(f"  - color: `{c}`")
    if "orientation" in el:
        out.append(f"  - orientation: `{el.get('orientation')}`")
    if "stacking" in el:
        out.append(f"  - stacking: `{el.get('stacking')}`")
    if "size" in el:
        out.append(f"  - size: `{el.get('size')}` (bubble)")
    if "legend" in el:
        legend = el.get("legend") or {}
        out.append(f"  - 🎨 legend: keys=`{sorted(legend.keys()) if isinstance(legend, dict) else legend}`")
    if "axis" in el:
        out.append(f"  - 🎨 axis customization present: keys=`{sorted((el.get('axis') or {}).keys())}`")
    if "format" in el:
        out.append(f"  - format: `{el.get('format')}`")
    return out


def pivot_details(el: dict) -> list[str]:
    out: list[str] = []
    rows = el.get("rowsBy") or []
    cols = el.get("columnsBy") or []
    vals = el.get("values") or []
    out.append(f"  - rowsBy: {len(rows)}, columnsBy: {len(cols)}, values: {len(vals)}")
    if "conditionalFormatting" in el:
        cf = el.get("conditionalFormatting") or []
        out.append(f"  - 🎨 **conditionalFormatting** present ({len(cf) if isinstance(cf, list) else 'object'} rules)")
    if "totals" in el:
        out.append("  - totals row/col present")
    return out


def table_details(el: dict) -> list[str]:
    out: list[str] = []
    cols = el.get("columns") or []
    out.append(f"  - columns: {len(cols)}")
    if "groupings" in el:
        g = el.get("groupings") or {}
        g_keys = sorted(g.keys()) if isinstance(g, dict) else "<list>"
        out.append(f"  - groupings keys: `{g_keys}`")
    if "order" in el:
        out.append(f"  - order keys present: {len(el.get('order') or [])}")
    if "conditionalFormatting" in el:
        cf = el.get("conditionalFormatting") or []
        out.append(f"  - 🎨 **conditionalFormatting** present ({len(cf) if isinstance(cf, list) else 'object'} rules)")
    return out


def container_details(el: dict) -> list[str]:
    out: list[str] = []
    if "backgroundImage" in el:
        out.append(f"  - 🎨 backgroundImage: `{el.get('backgroundImage')}`")
    if "backgroundColor" in el:
        out.append(f"  - 🎨 backgroundColor: `{el.get('backgroundColor')}`")
    return out


def text_details(el: dict) -> list[str]:
    out: list[str] = []
    body = el.get("body")
    if isinstance(body, str):
        preview = body[:100].replace("\n", " ") + ("..." if len(body) > 100 else "")
        out.append(f"  - body (str, {len(body)} chars): `{preview}`")
        # Inline `<span style="...">` HTML is the static-styling pattern, not
        # dynamic. Dynamic text uses Sigma template syntax (`{{...}}` etc).
        if has_template_var(body):
            out.append("  - 🎨 **dynamic text** (template variable detected in body)")
        elif "<span" in body or "<a " in body:
            out.append("  - inline HTML styling detected in body (static)")
    elif isinstance(body, dict):
        out.append(f"  - 🎨 body is object (likely dynamic): keys=`{sorted(body.keys())}`")
    elif isinstance(body, list):
        out.append(f"  - 🎨 body is list ({len(body)} entries — likely segmented/dynamic)")
    if "verticalAlign" in el:
        out.append(f"  - verticalAlign: `{el.get('verticalAlign')}`")
    if "horizontalAlign" in el:
        out.append(f"  - horizontalAlign: `{el.get('horizontalAlign')}`")
    return out


def control_details(el: dict) -> list[str]:
    out: list[str] = []
    ctype = el.get("controlType", "<none>")
    cid = el.get("controlId", "<no-controlId>")
    out.append(f"  - controlId: `{cid}`, controlType: `{ctype}`")
    src = el.get("source") or {}
    if isinstance(src, dict) and src.get("kind"):
        out.append(f"  - source.kind: `{src.get('kind')}`")
    filters = el.get("filters") or []
    out.append(f"  - filters: {len(filters)} (binds to {len({f.get('source', {}).get('elementId') for f in filters if isinstance(f, dict)})} element(s))")
    # Check for DM-inheritance markers — typically source.kind == 'data-model'
    # or a `source.dataModelId` field, plus possibly an `inherited` or
    # `parent` reference. We don't know the exact field name yet; flag any
    # source.kind != "source" / "table" / "warehouse-table" as candidate.
    if isinstance(src, dict):
        sk = src.get("kind")
        # `manual` is the documented source.kind for hand-authored segmented
        # control options — not a DM-inheritance signal. Anything outside the
        # known set is a candidate net-new feature.
        known_src_kinds = {"source", "table", "warehouse-table", "manual", "data-model"}
        if sk and sk not in known_src_kinds:
            out.append(f"  - 🎨 non-standard source kind `{sk}` (DM-inherited candidate)")
        if "dataModelId" in src:
            out.append("  - 🎨 source.dataModelId present (DM-inherited candidate)")
    return out


def top_level_summary(spec: dict) -> list[str]:
    lines: list[str] = []
    lines.append(f"# Workbook manifest — `{spec.get('name', '<unnamed>')}`")
    lines.append("")
    lines.append(f"- schemaVersion: `{spec.get('schemaVersion')}`")
    lines.append(f"- folderId: `{spec.get('folderId')}`")

    pages = spec.get("pages") or []
    hidden = sum(1 for p in pages if p.get("hidden"))
    lines.append(f"- pages: {len(pages)} ({hidden} hidden)")

    desc = spec.get("description")
    if desc:
        lines.append(f"- description: `{desc[:120]}`")

    # Model-level / workbook-level controls (outside pages).
    top_controls = spec.get("controls") or []
    if top_controls:
        lines.append(f"- 🎨 workbook-level controls (outside pages): {len(top_controls)}")
        for c in top_controls:
            lines.append(f"  - `{c.get('controlId') or c.get('id')}` ({c.get('controlType')})")

    unknown_top = sorted(set(spec.keys()) - SPEC_KEYS)
    if unknown_top:
        lines.append(f"- ⚠️  unknown top-level keys: `{unknown_top}`")

    # Cross-page kind tally.
    all_kinds: dict[str, int] = {}
    for p in pages:
        for el in (p.get("elements") or []):
            k = el.get("kind", "<no-kind>")
            all_kinds[k] = all_kinds.get(k, 0) + 1
    if all_kinds:
        lines.append("")
        lines.append("**Element kinds across all pages:**")
        for k, n in sorted(all_kinds.items()):
            marker = " ⚠️ UNKNOWN" if k not in KNOWN_KINDS else ""
            lines.append(f"- `{k}`: {n}{marker}")

    lines.append("")
    return lines


def collect_unknown_kinds(spec: dict) -> list[str]:
    """Net-new element kinds across the whole spec — surfaces at the top."""
    found: set[str] = set()
    for p in spec.get("pages") or []:
        for el in (p.get("elements") or []):
            k = el.get("kind")
            if k and k not in KNOWN_KINDS:
                found.add(k)
    return sorted(found)


def split_layout_xml(layout_xml: str) -> dict[str, str]:
    """Split the concatenated layout string into one XML doc per page id.

    Sigma stores the workbook's layout as one string containing one <Page>
    XML document per workbook page, each prefixed by its own <?xml ?>
    declaration. We split on the declarations to recover per-page chunks
    and key them by the Page element's `id` attribute (which matches the
    page's `id` in the spec).
    """
    parts = re.split(r"(?=<\?xml)", layout_xml.strip())
    by_pid: dict[str, str] = {}
    for chunk in parts:
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            root = ET.fromstring(chunk)
        except ET.ParseError:
            continue
        pid = root.attrib.get("id")
        if pid:
            by_pid[pid] = chunk
    return by_pid


def _load_spec(spec_path: Path) -> dict:
    """Load a workbook spec from JSON or YAML.

    Detects format by file extension. YAML loading requires PyYAML; if it's
    not installed the script emits a helpful install hint rather than a
    cryptic ImportError. JSON loading uses stdlib only.
    """
    text = spec_path.read_text()
    suffix = spec_path.suffix.lower()
    if suffix in (".yaml", ".yml"):
        try:
            import yaml
        except ImportError:
            sys.exit(
                "workbook-manifest: YAML input requires PyYAML. "
                "Install with `pip install PyYAML`, or convert the spec "
                "to JSON with `yq -o=json . spec.yaml > spec.json`."
            )
        return yaml.safe_load(text)
    return json.loads(text)


def manifest(spec_path: Path) -> str:
    spec = _load_spec(spec_path)
    lines: list[str] = []
    lines.extend(top_level_summary(spec))

    layouts_by_pid = split_layout_xml(spec.get("layout") or "")

    new_kinds = collect_unknown_kinds(spec)
    if new_kinds:
        lines.append("> ⚠️  **Net-new element kinds detected:** "
                     + ", ".join(f"`{k}`" for k in new_kinds))
        lines.append("")

    for idx, page in enumerate(spec.get("pages") or []):
        lines.extend(page_summary(page, idx, layouts_by_pid))
        lines.append("")

    lines.append("---")
    lines.append(f"_Manifest generated from `{spec_path.name}`. Eyeball "
                 f"unknown_keys / UNKNOWN ELEMENT KIND / 🎨 lines against "
                 f"the rendered workbook to validate extraction._")
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("spec", type=Path, help="Path to workbook spec (.json, .yaml, or .yml)")
    p.add_argument("--out", type=Path, help="Write to file instead of stdout")
    args = p.parse_args()

    if not args.spec.is_file():
        print(f"spec file not found: {args.spec}", file=sys.stderr)
        return 2

    out = manifest(args.spec)
    if args.out:
        args.out.write_text(out)
        print(f"Wrote {args.out}")
    else:
        sys.stdout.write(out)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
