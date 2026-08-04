# Theming (`themeOverrides` + theme color references)

New 2026-08-04 (Wave 4 / C7 — merged with the visual-media capability
in `others.md`/`containers.md` since both answer "how does a value
become pixels without touching the data graph"). Covers the top-level
`themeOverrides` field and the reusable `{kind:"theme", ref}` color
form. Carries one correction over prior versions of this reference —
see "Theme color reference" below.

```bash
jq '.components.schemas.WorkbookSpec.allOf[1].allOf[1].properties.themeOverrides' /tmp/sigma-api.json
```

## Top-level `themeOverrides` field

Optional. Controls workbook-wide visual defaults — page width/spacing,
element chrome, and color schemes.

```json
"themeOverrides": {
  "pageWidth": "large",
  "space": { "unit": "small" }
}
```

**Live-POST verified** (Wave 4 / C7 probe,
`b77b5b05-d1f5-40ba-96eb-00458726da29`, and originally harvested against
`sales-mbr-sentinel` 2026-07-02) — `pageWidth`/`space` round-tripped
byte-for-byte.

Fields confirmed via the live OpenAPI schema (2026-08-04) — type/enum
only, not all individually live-POST tested this wave:

| Field | Type | Notes |
|---|---|---|
| `pageWidth` | enum | `"full"` \| `"large"` \| `"medium"` \| `"custom"` — resolves a prior "other values likely accepted" uncertainty; all 4 now confirmed from the schema itself, only `"large"` live-POST verified |
| `maxPageWidth` | number | Max page width in pixels when `pageWidth: "custom"` (minimum 600) |
| `space` | object | `{unit: ...}` — confirmed `"small"` live-POST |
| `borderRadius` | enum | `"square"` \| `"round"` \| `"pill"` — workbook-wide default, distinct from a per-element `style.borderRadius` |
| `hasCards` | enum | `"shown"` \| `"hidden"` — card-style element chrome |
| `invertTooltipColors` | enum | `"shown"` \| `"hidden"` |
| `categoricalScheme` | string or array | Named categorical palette, or a custom hex array |
| `sequentialScheme` | string | Named sequential color scheme |
| `divergingScheme` | string | Named diverging color scheme |
| `colors` | object | Not detailed this wave — inspect via the `jq` recipe above |
| `colorOverrides` | object | Per-token layout color overrides (hex); keys match the in-app theme color inspector |
| `layoutColors` | object | Not detailed this wave |
| `elementBorder` | object | Not detailed this wave — likely a default border style/color for elements workbook-wide |
| `tableStyles` | object | Workbook-wide table defaults — `bandingColor`, `headerDividerColor`, `textStyles.{header,cell,columnHeader,rowHeader}.{color,backgroundColor}`. Same shape family as a per-table `tableStyle` (see `tables.md`), but workbook-wide default rather than per-element override |
| `fonts` | object | Not detailed this wave |
| `titleFont` | object | Not detailed this wave |

Only `pageWidth` and `space` have been independently authored from
scratch and POSTed by this skill. The rest are confirmed to exist and
their top-level type from the live schema, but not yet probed for
accepted values or round-trip fidelity — inspect the `jq` recipe above
before authoring any of them into a build where they're load-bearing.

## Theme color reference — `{kind:"theme", ref}`

**Correction (2026-08-04).** An earlier version of this reference (and
of `reference/specification/schema.md`) described `{kind:"theme",
ref:"colors-textNeutral"}` as a **standalone element kind** that could
appear directly in `pages[].elements[]`. This was wrong — **live-POST
tested and rejected** with `Invalid kind: "theme"` when placed as a
page element. The corrected understanding, from the live OpenAPI
schema: `{kind:"theme", ref}` is a **reusable color-value form**,
structurally identical to how a chart's `color` channel can be a plain
hex string OR this theme-reference object. It appears as a `oneOf`
alternative inside color-typed fields across many element kinds —
`style.color`, `style.borderColor`, `style.backgroundColor`,
`name.color`, `description.color`, `sparkline.color`,
`tableStyle`/`themeOverrides.tableStyles`'s various color fields, and
likely others.

```json
{
  "id": "hero",
  "kind": "container",
  "style": {
    "borderColor": { "kind": "theme", "ref": "colors-fillPrimary" }
  }
}
```

**Live-POST verified** (Wave 4 / C7 probe) — used as a container's
`style.borderColor`, round-tripped byte-for-byte. `ref` accepts a
theme color token name (e.g. `colors-fillPrimary`, `colors-textNeutral`
— both observed, one in harvest, one live-POSTed); the full enum of
valid `ref` values isn't documented anywhere this skill has found —
inspect a real theme's tokens via the Sigma UI's theme editor, or trial
a candidate token name and check the POST response.

## `themeName` — reference to a saved/shared theme

Documented only via harvest evidence (a top-level UUID field pointing
at a named theme saved elsewhere in the org). **Not independently
verified this wave** — no REST endpoint for listing available themes
was found in either the current public OpenAPI bundles or the cached
workbook-spec schema (see `reference/specification/schema.md` →
"OpenAPI reference — known-dead URL" for why the schema situation is
unusually murky right now), so there was no real theme ID available to
trial. Treat as unconfirmed until probed against a real org's saved
theme.

## Cross-references

- `reference/specification/others.md` → "Image" — the image element,
  including the `data:image/svg+xml;base64,...` inline-SVG pattern
  (also live-POST verified this wave).
- `reference/specification/containers.md` → "backgroundImage" — shares
  the same `source: {kind:"url"|"upload"}` shape as the `image` element.
- `reference/specification/tables.md` — per-element `tableStyle`, the
  same shape family as `themeOverrides.tableStyles`.
