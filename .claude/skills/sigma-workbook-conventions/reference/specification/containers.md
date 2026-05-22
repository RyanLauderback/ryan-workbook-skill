# Containers

`kind: "container"` elements — placeholders that group other elements via
layout XML.

```bash
jq '.components.schemas.Container' /tmp/sigma-api.json
```

A container is the visual grouping primitive: a labeled section, a
branded header strip, a row of KPIs treated as a unit. It pairs with a
matching `<GridContainer elementId="...">` in the layout XML (see
`layout.md`) — the spec declares the container exists; the XML
positions it and its children.

## Minimal shape

```json
{ "id": "header-row", "kind": "container" }
```

The container declared in the page's `elements` array does nothing on
its own. You **must** also reference it from layout XML or it doesn't
render. This pairing is the whole reason `kind: "container"` exists.

## Styling fields

Containers accept three optional styling fields:

### `style` — solid colors, borders, corner radius

```json
{
  "id": "ctr-header",
  "kind": "container",
  "style": {
    "backgroundColor": "#FFFFFF",
    "borderRadius":    "round",
    "borderColor":     "#ce785c",
    "borderWidth":     3
  }
}
```

Verified fields:

- `backgroundColor` — hex color string.
- `borderRadius` — observed: `"round"`, `"pill"`. Absence renders
  sharp corners.
- `borderColor` — hex color string.
- `borderWidth` — integer pixels (observed: `1` for cards, `3` for
  accent headers).

**Partial styling is accepted.** Any subset of the four keys is
valid; spacer containers omit `borderRadius` (sharp corners); some
containers omit `backgroundColor` for transparency.

### `backgroundImage` — image filling the container

```json
{
  "id": "hero",
  "kind": "container",
  "backgroundImage": {
    "url": "https://cdn.example.com/hero.jpg",
    "style": {
      "fit": "cover",
      "horizontalAlign": "middle",
      "verticalAlign": "middle",
      "tiling": "none"
    }
  }
}
```

`backgroundImage` is an **object**, not a string. `url` is the only
required field. The optional inner `style`:

- `fit`: `contain` | `cover` | `none` | `scale-down` | `stretch`
- `horizontalAlign`: `start` | `middle` | `end`
- `verticalAlign`: `start` | `middle` | `end`
- `tiling`: `none` | `repeat`

The full shape round-trips through GET unchanged; PUT-based edits
are stable. URL supports `{{formula}}` references if you need the
image to switch based on a control value — same syntax as the
image element (`others.md`) and text body (`text.md`).

### Combining `style` + `backgroundImage`

Both can appear on the same container; they're independent:

```json
{
  "id": "hero",
  "kind": "container",
  "backgroundImage": { "url": "..." },
  "style": { "borderRadius": "round", "borderWidth": 0 }
}
```

## What `style` does NOT capture (UI-only)

These styling controls appear in the Sigma UI but **do not appear in
the code spec** on GET-back:

- `padding` / "padding enabled" toggle
- `ContainerSpacing` / inter-element gap
- `gap` between grid cells

Verified 2026-05-21 against the retail-sales harvest — its design
spec mentions all three but none survive into the JSON. Do not
promise these in plans; do not template them in code specs. Layout
XML attributes are limited to `gridColumn`, `gridRow`,
`gridTemplateColumns`, `gridTemplateRows`, `elementId`, `type`, `id`.

## Common `style` recipes

Clone the recipe whose purpose matches the container. All extracted
from `examples/styled-card-dashboard.json`.

**Card style — default for viz + tables wrapped in a section
container:**

```json
"style": {"backgroundColor": "#FFFFFF", "borderRadius": "round", "borderColor": "#E8DFD3", "borderWidth": 1}
```

**Accent header / control-panel container** — signals "interactive
zone" (filter bar, page header):

```json
"style": {"backgroundColor": "#FFFFFF", "borderRadius": "round", "borderColor": "#ce785c", "borderWidth": 3}
```

**Section title container** — tinted background behind a section
heading, sharp corners for clean alignment:

```json
"style": {"backgroundColor": "#f5f0e8", "borderColor": "#cd785c", "borderWidth": 3}
```

**Spacer / divider container** — visible band between sections:

```json
"style": {"backgroundColor": "#B4B4B4", "borderColor": "#FFFFFF", "borderWidth": 3}
```

**Layout placement for spacer containers.** A spacer container must
have a matching `<GridContainer>` (with children) in the layout XML
— placing it as a `<LayoutElement>` leaf fails `validate-spec`'s
`containers-have-children` check. Two valid patterns:

1. **Wrap pattern** — nest the next section's container inside the
   spacer's `<GridContainer>`. The spacer's `gridRow` spans both
   the visible band region AND the nested section, giving a
   concentric two-color frame. `examples/styled-card-dashboard.json`
   uses this for every section break on page 1.

2. **Drop pattern** — skip the spacer container element entirely.
   Rely on a small `gridRow` gap between adjacent sections for
   whitespace.

Pick wrap when you want a visible colored band; pick drop when grid
whitespace is enough.

**Transparent grouping** — invisible container for layout-only
grouping (no visual frame):

```json
{ "id": "kpi-group", "kind": "container" }
```

(omit `style` entirely)

## Recipes — branded section header

A top strip with a logo image on the left, a Markdown title on the
right, sitting on a colored background:

```json
{
  "elements": [
    {
      "id": "header",
      "kind": "container",
      "style": { "backgroundColor": "#0B3D91", "borderRadius": "round" }
    },
    {
      "id": "logo",
      "kind": "image",
      "url": "https://cdn.example.com/logo.png"
    },
    {
      "id": "title",
      "kind": "text",
      "body": "# Q4 Sales\nWeekly snapshot of revenue and growth"
    }
  ]
}
```

Paired layout XML places logo and title side-by-side inside the
header container:

```xml
<GridContainer elementId="header" type="grid"
               gridColumn="1 / 25" gridRow="1 / 6"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="logo"  gridColumn="1 / 6"  gridRow="1 / 6"/>
  <LayoutElement elementId="title" gridColumn="6 / 25" gridRow="1 / 6"/>
</GridContainer>
```

## Recipe — KPI on top of a background image

```json
{
  "elements": [
    {
      "id": "hero",
      "kind": "container",
      "backgroundImage": { "url": "https://picsum.photos/1200/300",
                           "style": { "fit": "cover" } }
    },
    {
      "id": "revenue-kpi",
      "kind": "kpi-chart"
    }
  ]
}
```

```xml
<GridContainer elementId="hero" type="grid"
               gridColumn="1 / 25" gridRow="1 / 8"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="revenue-kpi" gridColumn="1 / 25" gridRow="1 / 8"/>
</GridContainer>
```

**Note:** overlapping `gridRow` ranges between siblings inside one
container don't compose into a z-axis stack — the server normalizes
overlapping rows into adjacent rows on readback. For "element on
top of image" semantics, put the KPI **inside** the container that
owns the background image; the background spans the container's
full extent and the child element sits on top of it naturally.

## When to skip containers

If you don't need a visual grouping (no shared background, no
logical section), put elements directly on the page and position
them with `<LayoutElement>` in the page-level layout XML. A
container that holds a single element is usually overkill — unless
you specifically need the background image or styled frame.

## Cross-references

- `layout.md` — the XML grammar for positioning containers + their
  children.
- `reference/conventions.md` → "Passthrough mandate" — the
  cross-cutting rules that affect every container's child elements.
- `examples/styled-card-dashboard.json` — canonical reference for
  the 5-recipe styling system.
