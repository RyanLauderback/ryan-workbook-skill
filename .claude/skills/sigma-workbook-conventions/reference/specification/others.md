# Other element kinds (divider, image)

Recipes for the smaller polish elements.

```bash
jq '.components.schemas.Divider, .components.schemas.Image' /tmp/sigma-api.json
```

Both elements take very little spec; this file documents the
`{{formula}}`-in-URL pattern for image elements and how they pair with
layout XML.

## Divider

A horizontal rule. No data, no source, no styling fields.

```json
{ "id": "section-rule", "kind": "divider" }
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"divider"` |

Use a divider in the layout to separate sections within a page or
container. Position it like any other element via `<LayoutElement>`
with a thin `gridRow` span (e.g., `gridRow="6 / 7"`).

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

`url` is the only data field — there's no `alt`, `width`, or `height`
in the public spec. Sizing is controlled by the layout grid placement.

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

## What about maps?

Per the official skill's `from-image.md`, `geography-map` is listed
as a valid kind for visual interpretation. Whether it's currently
round-trippable through the spec is **untested** — every workbook
with maps observed in training mode through 2026-05-21 has returned
`service_error` on GET-spec. Treat maps as unsupported unless a
GET-spec round-trip succeeds on a map-bearing workbook in your org.

See `reference/scope-and-edge-cases.md` → "Map element status" for
the running observation log.
