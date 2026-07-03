# Text elements

The `text` element renders a free-form Markdown block — dashboard
titles, descriptions, section headers, callouts, prose alongside
charts and tables.

```bash
jq '.components.schemas.Text' /tmp/sigma-api.json
```

## Shape

```json
{
  "id": "text-header",
  "kind": "text",
  "body": "## **Sales Overview**\n\nA weekly view of revenue and growth.",
  "verticalAlign": "middle",
  "overflow": "clip"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"text"` |
| `body` | yes | Markdown string (subset — see below) |
| `verticalAlign` | no | `"start"` (top, default), `"middle"`, `"end"` (bottom) |
| `overflow` | no | `"clip"` (default) or `"scroll"` |

**Note:** `text` elements have no `name` or `source` field, unlike most
other element kinds. The body itself IS the content; the element has no
title bar to style.

## Markdown subset

The `body` field supports a subset of Markdown plus inline HTML for
styling:

- Paragraphs and soft / hard line breaks
- Headings: `#`, `##`, `###`
- Bullet and ordered lists
- `**bold**`, `*italic*`, `~~strikethrough~~`
- `[links](https://example.com)`
- Inline HTML: `<u>`, `<sub>`, `<sup>`
- Inline color: `<span style="color: #hex">…</span>` and
  `<span style="background-color: #hex">…</span>` (hex only — `#rgb`
  or `#rrggbb`)
- Font size: `<span style="font-size: 24px">…</span>`
- Font family: `<span style="font-family: Georgia">…</span>` — a
  **single family name only** (letters, digits, spaces, underscores,
  or dashes). Comma-separated fallback lists like
  `"Georgia, serif"` are rejected by the API.
- Paragraph block classes: `<p class="p-large">…</p>` and
  `<p class="p-small">…</p>`
- Paragraph alignment: `<p style="text-align: center">…</p>` (also
  `left` / `right`)
- Embedded formulas in `{{double curly braces}}` with optional d3
  formatting via pipe — see "Dynamic text" below

A single `<span>` can combine properties (e.g. color + font-size). If a
value violates its rule (e.g. a comma-list font family), the API
rejects the whole `body` with an error naming the field.

Font-size, font-family, and paragraph-alignment shapes documented by
upstream eng skill (2026-06-11); not exercised in this skill's
harvested exemplars yet. Verify with a small round-trip before relying
on them in a production build.

## Inline color + bold ordering

A common pattern is bold + color text. Markdown bold and inline `<span>`
color are both supported, but Sigma normalizes the **ordering** on
round-trip: a `**<span>...</span>**` that you submit reads back as
`<span>**...**</span>`. The rendered output is the same; just don't be
surprised by the diff.

```markdown
# **<span style="color: #8B0000">Deployments Dashboard</span>**

Filter by **<span style="color: #1E90FF">Created at</span>** to narrow
the time window.
```

`examples/styled-card-dashboard.json` uses this pattern extensively for
section dividers with terracotta-accent characters:

```markdown
### <span style="color: #CC785C">━━</span>   <span style="color: #3A2E26">**Performance at a glance**</span>
```

## Dynamic text — `{{formula}}` embeds

The `body` field supports embedded Sigma formulas in `{{double curly
braces}}` with optional d3-format suffix via pipe:

```markdown
## **Revenue this quarter: {{Sum([Revenue]) | $,.0f}}**

Up **{{([Revenue]/[Prior Revenue] - 1) | ,.1%}}** from last quarter.
```

The `{{ast | fmt}}` syntax is shared with image URLs (`others.md`) and
chart/element titles. The expression is evaluated server-side and
substituted into the rendered text.

Use this for:

- KPI-style live values inside narrative text
- Dynamic page titles ("Q4 Sales — last updated {{Max([Updated At]) | %b %-d}}")
- Conditional callouts (`{{If([Revenue] > [Target], "✓ On track", "⚠ Below target")}}`)

## Layout placement — common idioms

Text elements participate in the page grid like any other element.

**Page-level title row above a `<GridContainer>`:**

```xml
<LayoutElement elementId="text-header" gridColumn="1 / 25" gridRow="1 / 4"/>
<GridContainer elementId="header-row" type="grid" ...>
  ...
</GridContainer>
```

**Inside a container, on its own row above the chart row** (see
`layout.md` → "Stacking children inside a container"):

```xml
<GridContainer elementId="header-row" type="grid" gridColumn="1 / 25" gridRow="1 / 12" ...>
  <LayoutElement elementId="text-header" gridColumn="1 / 25" gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-1"       gridColumn="1 / 9"  gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-2"       gridColumn="9 / 17" gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-3"       gridColumn="17 / 25" gridRow="4 / 12"/>
</GridContainer>
```

**Side-by-side with a control on the same row:**

```xml
<GridContainer elementId="header-row" type="grid" ...>
  <LayoutElement elementId="text-header"     gridColumn="1 / 18"  gridRow="1 / 4"/>
  <LayoutElement elementId="ctrl-date-range" gridColumn="18 / 25" gridRow="1 / 4"/>
</GridContainer>
```

## Text elements do not carry `style`

Unlike viz / container / control elements, text elements **do not have
a top-level `style` object** in the verified exemplars. Inline HTML in
the `body` (e.g. `<span style="color: #RRGGBB">`) handles all text
styling. The text element renders without a frame; the visual effect of
a "framed text block" comes from placing the text inside a container
that carries `backgroundColor` + `border` styling.

See `containers.md` → "Common style recipes" for the container patterns
that wrap text elements.

## Hidden text elements

Text elements don't have a `visibility` field on the element itself.
To hide a text block conditionally, either:

1. Place it on a hidden page (`visibility: "hidden"` on the page —
   see `schema.md` → "Pages").
2. Use a `{{If(...)}}` formula in the body to emit empty string under
   the hide condition.
