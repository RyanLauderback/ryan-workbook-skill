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

Embeds an external image by URL, or a reference to an image already
uploaded into Sigma. **Corrected 2026-08-04 (Wave 4 / C7) — the field
shape below was wrong.** Every prior version of this doc (and every
harvested workbook this skill had read) showed a flat top-level `url`
field, e.g. `{"id": "logo", "kind": "image", "url": "..."}`. **Live-POST
tested and rejected** with a misleading `Invalid kind: "image"` error
(reads like the element kind itself is unsupported; it's actually the
inner shape that's wrong — see `reference/workflows/validate.md` →
"Decoding cryptic validation errors"). The real shape, confirmed against
the live OpenAPI schema and then live-POST verified:

```json
{
  "id": "logo",
  "kind": "image",
  "source": { "kind": "url", "url": "https://cdn.example.com/team-logo.png" }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"image"` |
| `source` | yes | `{kind:"url", url}` (external image, supports `{{formula}}`) or `{kind:"upload", key}` (a reference to an image already uploaded into Sigma — `key` is an opaque storage handle emitted by GET/accepted by PUT; the spec **cannot upload a new image**, only reference an existing one) |
| `alt` | no | Alt text. Confirmed real via the OpenAPI (a sibling of `source`, not nested in it) — not independently probed this wave |
| `style` | no | Confirmed real via the OpenAPI, sibling of `source` — not independently probed this wave |

There is **no `link` field** — an earlier version of this doc listed one
alongside `alt`/`style` from an un-verified OpenAPI skim; the live schema
only has `alt` and `style` as siblings of `source`. Retracted.

Sizing is controlled by the layout grid placement, not element fields.

### Dynamic image URL via `{{formula}}`

For per-row icons, per-control logo swaps, or any image that needs to
vary based on workbook state, embed a formula in the URL. **Live-POST
verified** (Wave 4 / C7 probe, `b77b5b05-d1f5-40ba-96eb-00458726da29`) —
round-tripped byte-for-byte:

```json
{
  "id": "status-icon",
  "kind": "image",
  "source": { "kind": "url", "url": "https://cdn.example.com/icons/{{[Status] | lowercase}}.png" }
}
```

Same `{{ast | fmt}}` syntax used in element titles and the `text`
element body — see `text.md`. The formula is evaluated server-side
and substituted into the URL before fetch.

### Inline SVG via `data:image/svg+xml;base64,...`

**Live-POST verified** (Wave 4 / C7 probe) — a `source.url` set to a
base64-encoded inline SVG data URI round-tripped byte-for-byte. This
resolves a previously-open question in `reference/capability-ledger.md`
("Unresolved contradictions"): a third-party fork had claimed inline
SVG data URIs get WAF-403'd on POST. **Not observed here** — the exact
same `source.url` field that accepts a hosted HTTPS URL also accepts
`data:image/svg+xml;base64,...` with no rejection:

```json
{
  "id": "icon-inline",
  "kind": "image",
  "source": { "kind": "url", "url": "data:image/svg+xml;base64,PHN2ZyB4bWxucz0i..." }
}
```

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

**Retracted 2026-08-03 — this section previously claimed the opposite of
reality.** It said buttons, modals/popovers, tabbed containers, page
breaks, and action sequences were "not supported as standalone element
kinds" and that workbooks using them "break GET-spec." **All five are
fully spec-able.** Modal pages, tabbed containers, navigation, and page
breaks are now **live-POST verified** (authored from scratch and
POSTed, not just read via GET-spec) — see
`reference/specification/pages.md` for the shapes and
`reference/specification/layout.md` → "Five-tag grammar" for the layout
XML. Buttons and action sequences are **also now live-POST verified**
(Wave 2 / C3) — see `reference/specification/actions.md` for the
`button` element and all 9 effects, and
`reference/capability-ledger.md` for the full dated evidence table.

This claim likely originated the way the real upstream `sigma-workbooks`
skill's own docs warn against: a generic `Invalid kind` or a GET-spec 500
on one malformed or unrelated attempt, misread as "this kind is rejected"
rather than "the inner shape was wrong" or "a *different* feature on that
same workbook broke the serializer." See
`reference/workflows/validate.md` → "Decoding cryptic validation errors"
— `Invalid kind` almost always means the inner shape doesn't match the
`kind`/`controlType` claimed, not that the kind itself is unsupported.

**The retest protocol, before declaring anything unsupported again:**
pull the live shape via the `kind`-discriminator `jq` recipe against a
reference workbook that uses the feature (see `SKILL.md` → "Sources of
truth") before concluding a kind is rejected.
