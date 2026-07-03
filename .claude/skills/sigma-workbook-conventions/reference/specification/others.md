# Other element kinds (divider, image, embed)

Recipes for the smaller polish elements.

```bash
jq '.components.schemas.Divider, .components.schemas.Image, .components.schemas.Embed' /tmp/sigma-api.json
```

## Divider

A rule for separating sections. Data-less, source-less.

```json
{
  "id": "section-rule",
  "kind": "divider",
  "direction": "horizontal",
  "align": "middle",
  "style": {
    "color": "#cccccc",
    "width": 2,
    "strokeStyle": "solid"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"divider"` |
| `direction` | no | `"horizontal"` (default) or `"vertical"` |
| `align` | no | e.g., `"middle"` |
| `style` | no | `{ color, width, strokeStyle }` |
| `style.color` | no | Hex color (`#cccccc`) |
| `style.width` | no | Pixel width (integer) |
| `style.strokeStyle` | no | `"solid"` observed; other d3-style values likely accepted |

Verified 2026-07-02 against harvested `element-showcase` workbook —
both horizontal and vertical dividers with full `style` blocks round-trip
cleanly through POST/GET.

Position via `<LayoutElement>` with a thin `gridRow` (horizontal) or
`gridColumn` (vertical) span.

## Image

Embeds an external image by URL. Hosted images only — uploads aren't
supported via the spec.

```json
{
  "id": "logo",
  "kind": "image",
  "url": "https://cdn.example.com/team-logo.png"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"image"` |
| `url` | yes | Public HTTPS URL. Supports `{{formula}}` references |

The OpenAPI schema also documents `alt`, `link`, and a `style` block on
image elements. Neither observed in harvested reference workbooks
(2026-07-02) — every image in the corpus used only `url`. If you need
them, inspect the schema via the jq recipe above before writing.

Sizing is controlled by the layout grid placement, not element fields.

### Dynamic image URL via `{{formula}}`

For per-row icons, per-control logo swaps, or any image that needs to
vary based on workbook state, embed a formula in the URL:

```json
{
  "id": "status-icon",
  "kind": "image",
  "url": "https://cdn.example.com/icons/{{[Status] | lowercase}}.png"
}
```

Same `{{ast | fmt}}` syntax used in element titles and the `text`
element body — see `text.md`. The formula is evaluated server-side
and substituted into the URL before fetch.

### Image element placement — layout

Images sit in the page grid like any other element. Common idioms:

**Logo + title side-by-side at the top of a page:**

```xml
<GridContainer elementId="header" type="grid"
               gridColumn="1 / 25" gridRow="1 / 6"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="logo"  gridColumn="1 / 6"  gridRow="1 / 6"/>
  <LayoutElement elementId="title" gridColumn="6 / 25" gridRow="1 / 6"/>
</GridContainer>
```

**Icon accent on a section header** — small image (1 column × 2 rows)
overlapping with a text element:

```xml
<LayoutElement elementId="icon"     gridColumn="1 / 2"   gridRow="1 / 3"/>
<LayoutElement elementId="section"  gridColumn="2 / 25"  gridRow="1 / 3"/>
```

### When to use an image vs. container `backgroundImage`

- **`image` element** — the image IS the content. Logos, icons,
  illustrations, photos that aren't backdrops.
- **`container.backgroundImage`** — the image is the backdrop with
  other elements (KPIs, text, charts) sitting on top. See
  `containers.md` → "backgroundImage" for the object shape.

## Embed

Renders an external URL inline — a hosted report, form, video, etc.

```json
{
  "id": "embed-report",
  "kind": "embed",
  "url": "https://example.com/report"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"embed"` |
| `url` | yes | Public URL. Supports `{{formula}}` references |

Documented by the upstream eng skill but not observed in harvested
reference workbooks yet. Inspect the OpenAPI shape before relying on
additional fields.

Positions via `<LayoutElement>` in layout XML like any other element.

## Maps

Map elements (`geography-map`, `point-map`, `region-map`) live in
their own reference file — see [`maps.md`](maps.md). Verified
round-trippable through the spec (2026-07-02) against the harvested
`element-showcase` workbook.

## What about buttons and modals?

Per Sigma's official workbooks-as-code limitations
(<https://help.sigmacomputing.com/docs/manage-workbooks-as-code>),
the following are **not supported** as standalone element kinds in
the spec:

- Buttons
- Modals / popovers
- Tabbed containers (multi-page navigation containers)
- Page breaks
- Action sequences (workflow buttons)

Workbooks that use these features render in the UI but **break
GET-spec** (the serializer returns `service_error`). See
`reference/scope-and-edge-cases.md` → "GET-spec can 500 when UI
features aren't representable." When the user asks for one of
these, surface the gap during the plan step and propose a
substitute (e.g., navigation via drill-through actions on a KPI, or
a separate page).
