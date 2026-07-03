# Layout

Top-level `layout` XML — when to write it, the two-tag grammar, and
the silent-failure traps the OpenAPI doesn't surface.

**Default to writing explicit `layout` XML for multi-element workbooks.**

For container element bodies (the `kind: "container"` JSON placeholders
that pair with `<GridContainer>` in this XML), see `containers.md`.

## When to write layout vs. let Sigma auto-arrange

Write explicit `layout` when **any** of these apply:

- The page has **mixed element kinds** (charts + KPIs, controls +
  charts, text/image/divider polish). Auto-arrange treats them as a
  vertical stack and gives every element the same height — KPIs end
  up the size of charts, dividers get huge gutters around them.
- The user asked for specific positioning ("logo on left, title on
  right", "KPIs across the top", side-by-side charts).
- There's a `kind: "container"` element on the page. Containers
  without a matching `<GridContainer>` are functionally no-ops.
- The workbook has more than ~4 elements on a page. Auto-arrange
  becomes a long scroll.

Auto-arrange (omit `layout`) is fine when:

- The page has a single element.
- The page is a uniform stack of tables — auto-arrange produces a
  reasonable list view.
- The user explicitly says default layout is fine.

If unsure, write the layout. Writing one is cheap (the patterns
below are copy-paste); a visually broken dashboard is expensive.

## Layout is top-level (NOT per-page)

`layout` lives on the **top-level workbook spec**, not nested under
`pages[i]`. Multi-page workbooks concatenate per-page XML documents:

```json
{
  "name": "Multi-page Dashboard",
  "pages": [...],
  "layout": "<?xml ...?><Page id=\"page-1\" ...>...</Page><?xml ...?><Page id=\"page-2\" ...>...</Page>"
}
```

Each `<Page id="...">` matches a `pages[].id`. Per-page layout
placed under `pages[i]` is silently discarded — verified
2026-05-11. See `reference/history.md`.

## Two flavors: XML layout vs. element-level `layout` object

The top-level `layout` field discussed here is an **XML string** that
positions elements on the page grid.

Individual elements can **also** carry a `layout` **object** (not
XML) that controls in-element positioning:

```json
{
  "kind": "kpi-chart",
  "id": "kpi-revenue",
  "layout": { "anchor": "middle" },
  ...
}
```

Observed values: `anchor: "middle"` on KPIs (verified 2026-07-02
against `sales-mbr-sentinel`). Presumably `"start"` / `"end"`
supported too — inspect the OpenAPI to enumerate.

These are two different things using the same key name:

| Where | Value type | Purpose |
|---|---|---|
| Top of spec (`spec.layout`) | XML string | Places elements on the page grid |
| On each element (`element.layout`) | JSON object | Positions content within the element's box |

Both can coexist — the XML places the KPI on the grid; the object
sets the KPI content's vertical anchor within its allocated cell.

## Two-tag grammar

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">
  <GridContainer elementId="<containerId>" type="grid" gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="<childId>" gridColumn="1 / 13" gridRow="1 / 4"/>
  </GridContainer>
  <LayoutElement elementId="<elementId>" gridColumn="1 / 25" gridRow="4 / 16"/>
</Page>
```

Each `<Page id>` matches a `pages[].id`. Each `elementId` matches an
element on that page. `gridColumn` / `gridRow` use standard CSS grid
line syntax (`start / end`); the default grid is **24 columns wide**.

## `<GridContainer>` vs `<LayoutElement>` — silent failure

> ⚠️ Use `<GridContainer>` for any tag that has children nested
> inside it. `<LayoutElement type="grid">` with children parses
> successfully **as a leaf** and the children are silently dropped —
> no error, the child elements just disappear from the page.

- `<LayoutElement elementId="X" .../>` — **leaf**. Positions a single
  element. No children.
- `<GridContainer elementId="X" ...>...</GridContainer>` — **container**.
  Wraps child `<LayoutElement>`s inside its own inner grid.

`scripts/validate-spec.py`'s `layout-element-ids` check catches some
layout-XML issues pre-POST but does NOT detect `<LayoutElement>`-
with-children. The manual layout pass in `validate.md` does.

## `gridTemplateRows`: keep it `"auto"`

> Silent normalization: `gridTemplateRows` is accepted on PUT with
> any value but normalizes back to `"auto"` on GET. Writing `"1fr"`,
> `"100px"`, `"repeat(3, 1fr)"` etc. doesn't error — the server drops
> your value and treats the row track as `"auto"`. Always write
> `"auto"` explicitly so the round-trip is stable.

Because row tracks collapse to `"auto"`, height comes from children,
not from the container's `gridTemplateRows`. Two patterns work:

### Side-by-side

Children share the container's row range, differ by `gridColumn`:

```xml
<GridContainer elementId="kpi-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 4"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="kpi-1" gridColumn="1 / 9"   gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-2" gridColumn="9 / 17"  gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-3" gridColumn="17 / 25" gridRow="1 / 4"/>
</GridContainer>
```

### Stacked rows inside a container

Children have disjoint `gridRow` spans. The server normalizes the
container's outer `gridRow` to encompass its children — declare
generously and let normalization clamp:

```xml
<GridContainer elementId="header-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 12"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="title"  gridColumn="1 / 25" gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-1"  gridColumn="1 / 9"  gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-2"  gridColumn="9 / 17" gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-3"  gridColumn="17 / 25" gridRow="4 / 12"/>
</GridContainer>
```

Use stacked rows when you want a section header above a row of
charts inside the same container, instead of moving those elements
out to the page level.

## After CREATE: IDs are preserved

IDs you `POST` are preserved verbatim — pages, elements, columns keep
the `id` values you sent. You can save the spec, edit it, and `PUT`
it back directly. Layout `elementId` references stay valid across
POST/PUT.

Layout `elementId` references must match an element `id` on that
page exactly (case-sensitive) — a mismatch silently drops the
element from the page.

Verified 2026-07-02 against harvested skill-authored workbooks:
kebab-case IDs survived POST → GET round-trip unchanged.

## Page-structure pattern (apply by default)

Every page should follow a recognizable visual structure. The
canonical pattern (used by every templated exemplar):

```
Page 1: <Page Title>
  Container 1 — header (page title + filter controls)
  Container 2 — KPI row (4 KPI tiles, equal width)
  Container 3+ — content (charts, tables, in side-by-side or
                          full-width sections)
```

For multi-section pages, nest containers:

- Outer container per logical section (24-col span).
- Inner container per side-by-side pair (each 12-col span inside the outer).
- Section-header text element above each section.

See `examples/data-model-sourced-kpi-overview-with-containers.json`
for a canonical page-structure exemplar.

## Cross-cutting rules

For the per-element layout rules that affect every spec — column
declaration mandate, drill-down corollary, rename-cascade
corollary, summary-bar pattern — see `reference/conventions.md`.

## What `layout` does NOT capture

- `padding` / "padding enabled" toggle — UI-only.
- `ContainerSpacing` / inter-element gap — UI-only.
- `gap` between grid cells — UI-only.

Layout XML attributes are limited to `gridColumn`, `gridRow`,
`gridTemplateColumns`, `gridTemplateRows`, `elementId`, `type`, `id`.
See `containers.md` → "What style does NOT capture."
