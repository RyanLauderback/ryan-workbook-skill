# Layout

Top-level `layout` XML — when to write it, the **five-tag grammar**
(corrected 2026-08-03 — see below), and the silent-failure traps the
OpenAPI doesn't surface.

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
`pages[i]`. Per-page layout placed under `pages[i]` is silently discarded —
verified 2026-05-11. See `reference/history.md`.

**Correction (2026-08-03) — exactly ONE `<?xml ?>` declaration for the
whole string, not one per page.** This file previously said multi-page
workbooks "concatenate per-page XML documents... each with its own `<?xml
?>` declaration." **That's wrong.** A real, live-POST-verified spec
(`b9e4bc48-afa8-4085-b94d-fdd61c06bf0d`, the Wave 1 probe workbook) shows
a single declaration followed by every `<Page>` as a bare sibling:

```json
{
  "name": "Multi-page Dashboard",
  "pages": [...],
  "layout": "<?xml version=\"1.0\" encoding=\"utf-8\"?><Page id=\"page-1\" ...>...</Page><Page id=\"page-2\" ...>...</Page>"
}
```

**NOT** `<?xml ?><Page id="page-1">...</Page><?xml ?><Page id="page-2">...</Page>`
(a declaration repeated per page). A repeated-declaration layout string is
rejected by the live API — but with a **generic, unhelpful 400** that gives
no field-level hint at all:

```
HTTP 400 {"code":"invalid_request","message":"An error has occurred. Please try again later (incident-id=...)"}
```

This doesn't match any of the other cryptic-error patterns in
`reference/workflows/validate.md` (`Invalid kind`, `Cannot resolve
columns`, etc.) — it's a distinct, worse failure mode: no path, no field
name, nothing to grep for. Verified 2026-08-03 during a real build-mode
session (not a probe) via bisection: a spec with one `<?xml ?>` per page
(the natural thing to write from this file's old, wrong prose) 400'd
every time; collapsing to a single leading declaration fixed it
immediately with no other change. Each `<Page id="...">` still matches a
`pages[].id`. See `reference/history.md` → "2026-08-03 — Multi-page
`<?xml ?>` declaration bug" for the full incident.

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

## Five-tag grammar

**Corrected 2026-08-03.** Previously documented as a "two-tag grammar"
with a "closed" attribute set — both claims were wrong. Live-POST
verified (not just observed via GET-spec) against a scratch probe
workbook: the grammar has **five** tags, and two of them
(`TabbedContainer`, `Tab`) exist specifically to represent the
`tabbed-container` element kind — see `pages.md` for that element's
JSON shape.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">
  <GridContainer elementId="<containerId>" type="grid" gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="<childId>" gridColumn="1 / 13" gridRow="1 / 4"/>
  </GridContainer>
  <LayoutElement elementId="<elementId>" gridColumn="1 / 25" gridRow="4 / 16"/>
  <TabbedContainer elementId="<tabsElementId>" type="tabbed-container" gridColumn="1 / 25" gridRow="16 / 40">
    <Tab gridTemplateColumns="repeat(12, 1fr)" gridTemplateRows="auto">
      <LayoutElement elementId="<tabAContentId>" gridColumn="1 / 13" gridRow="1 / 6"/>
    </Tab>
    <Tab gridTemplateColumns="repeat(12, 1fr)" gridTemplateRows="auto">
      <LayoutElement elementId="<tabBContentId>" gridColumn="1 / 13" gridRow="1 / 6"/>
    </Tab>
  </TabbedContainer>
</Page>
```

Each `<Page id>` matches a `pages[].id`. Each `elementId` matches an
element on that page. `gridColumn` / `gridRow` use standard CSS grid
line syntax (`start / end`); the default grid is **24 columns wide**.

### `<TabbedContainer>` / `<Tab>` — the two tags the old grammar missed

- **`<TabbedContainer elementId="X" type="tabbed-container" ...>`** —
  positioned exactly like a `<GridContainer>` (same `gridColumn`/
  `gridRow` attributes), but appears as a **direct child of `<Page>`**
  in every observed case, not nested inside a `<GridContainer>`.
  `elementId` matches the workbook's `kind:"tabbed-container"` element.
  Verified: the whole tag round-trips byte-for-byte through POST → GET
  when authored as shown above.
- **`<Tab gridTemplateColumns="..." gridTemplateRows="...">`** — **no
  `elementId` at all.** Tabs bind to the element's own `tabs[]` JSON
  array **positionally** — the first `<Tab>` is `tabs[0]`, the second
  is `tabs[1]`, and so on. This is a silent-failure class identical in
  shape to the `<GridContainer>` vs `<LayoutElement>` trap below: get
  the `<Tab>` order wrong (or add/remove one without updating both the
  XML and the `tabs[]` array in lockstep) and content lands on the
  wrong tab with no error. Each `<Tab>` carries its **own**
  `gridTemplateColumns`/`gridTemplateRows` (independent of the parent
  page's), and its children are ordinary `<LayoutElement>`/
  `<GridContainer>` tags — tab content elements are declared as **flat
  siblings on the same page** in the JSON (never nested inside the
  tabbed-container element itself); only the layout XML expresses which
  tab they belong to.
- **TabbedContainers nest.** A `<Tab>` may contain another
  `<TabbedContainer>` (observed in a harvested production workbook, not
  yet independently POST-verified by this skill).

### Modal pages get a 12-column grid, not 24

**Live-POST discovery, 2026-08-03:** a page with `type:"modal"` in its
JSON authored with `gridTemplateColumns="repeat(24, 1fr)"` (matching a
normal page) round-tripped with that attribute **silently rewritten to
`repeat(12, 1fr)`** on GET-back — Sigma normalizes modal pages to a
12-column grid regardless of what's authored. `gridColumn` values
written for a 24-column span (e.g. `"1 / 25"`) were still accepted and
stored without a clamp/error, but author modal-page content against a
**12-column** grid (e.g. `"1 / 13"` for full width) to avoid relying on
this normalization. See `pages.md` for the modal page's JSON shape.

**The modal page's `<Page>` tag itself still says `type="grid"`, never
`type="modal"`.** Verified 2026-08-03 against the same probe workbook and
independently reproduced during a later real build-mode session: the
modal/non-modal distinction lives *only* in the JSON `pages[].type`
field. Mirroring it into the layout XML (`<Page type="modal" ...>`) is a
natural mistake to make and is wrong — combined with the repeated-`<?xml
?>`-declaration bug above, it produces the same generic, field-less 400.
Correct modal-page layout tag: `<Page type="grid"
gridTemplateColumns="repeat(12, 1fr)" gridTemplateRows="auto"
id="<modalPageId>">`.

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

> ⚠️ **Both examples below happen to use a container whose own `gridRow`
> starts at page-row 1** (`"1 / 4"`), which makes each child's `gridRow`
> look like it "matches the parent." That's a coincidence of these
> specific examples, not the rule — see "GridContainer children use
> LOCAL row coordinates" further down for the real rule (children are
> always local to their own container, starting at row 1, regardless of
> where the container itself sits on the page) and the bug that resulted
> from missing this distinction.

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

### GridContainer children use LOCAL row coordinates — not the page's absolute numbering

**This is the single most consequential layout rule in this file, and
every prior version of this section (through 2026-08-03) had it wrong.**
A `<GridContainer>`'s children's `gridRow`/`gridColumn` values are
**local to that container** — the container's own top edge is row 1,
regardless of where that container's own `gridRow` sits in the page's
absolute numbering. They are **not** page-absolute coordinates, and they
do **not** need to match the parent's own `gridRow` attribute.

**Proof, from a real canonical exemplar**
(`examples/dashboard-department-scorecard.json`, a known-good, clone-safe
spec): its `ctr-kpi-row` container sits at page-absolute `gridRow="4 / 12"`,
but its three KPI children all carry `gridRow="1 / 9"` — starting at row 1,
not row 4. The header container immediately above it happens to sit at
`gridRow="1 / 4"` (page-absolute row 1), so its children *also* read
`gridRow="1 / 4"` — which looks like "children match the parent" only by
coincidence, because that particular container's local and absolute
numbering happen to coincide (both start at row 1). Every illustrative
example earlier in this file (the "Five-tag grammar" snippet, "Side-by-side",
"Stacked rows") made the same mistake of only ever showing containers that
start at page-row 1 — hiding the local/absolute distinction entirely.

**The bug this caused, concretely (2026-08-03, a real build-mode session):**
authoring children with *absolute* page-matching coordinates (matching
what the parent's own `gridRow` said) caused Sigma to keep silently
re-expanding the container on every subsequent PUT — because a child
`gridRow` of, say, `"26 / 58"` was being interpreted as *local* row 26
through 58 within a container whose local space was never meant to be
that large, forcing the container to keep growing to accommodate it. Each
follow-up fix that re-matched the *new*, larger absolute numbers made the
problem visibly worse, not better, because the underlying misunderstanding
compounded with every round-trip. No error anywhere in the pipeline
(POST/validate/verify all passed) — this is a pure layout consequence,
and it reads to a user as "the dashboard is poorly laid out."

**The fix, confirmed stable across a PUT → GET-back round-trip with zero
drift:** give every `<GridContainer>`'s children `gridRow`/`gridColumn`
values relative to that container's own top-left (starting at `1`),
independent of the container's own page-absolute position. Only the
container's *own* `gridRow`/`gridColumn` (on the `<GridContainer>` tag
itself) uses page-absolute coordinates to position it relative to
siblings. `<Tab>` children already worked this way correctly (tab content
uses local coordinates starting at 1, as documented in "Five-tag grammar"
above) — this rule generalizes that same local-coordinate model to every
`<GridContainer>`, not just `<Tab>`.

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

Layout XML attributes observed so far: `gridColumn`, `gridRow`,
`gridTemplateColumns`, `gridTemplateRows`, `elementId`, `type`, `id`.
**Correction (2026-08-03):** this was previously called a closed set —
it isn't. `<Tab>` carries no `elementId` at all (positional binding —
see "Five-tag grammar" above), and the set may not be exhaustive beyond
that; treat it as "observed," not "closed." See `containers.md` → "What
style does NOT capture."
