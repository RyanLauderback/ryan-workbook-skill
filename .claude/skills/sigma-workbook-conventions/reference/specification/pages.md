# Multi-surface page elements (tabbed containers, modal pages, navigation, page breaks)

New 2026-08-03. `reference/specification/others.md` (still current for
`divider`/`image`/`embed`) previously carried a section titled "What
about buttons and modals?" declaring the element kinds documented here
"not supported" — that claim was retracted; see
`reference/capability-ledger.md`. Every shape below is **live-POST
verified** (not just observed via GET-spec), authored from scratch
against a scratch probe workbook on 2026-08-03, not merely read back
from a pre-existing production workbook.

```bash
jq '.components.schemas.TabbedContainer, .components.schemas.Navigation, .components.schemas.PageBreak' /tmp/sigma-api.json
```

## Tabbed container

`kind: "tabbed-container"` groups several tabs' worth of content into
one region. The element itself only carries tab **labels** — the
content elements for each tab are declared as ordinary flat elements on
the same page, and the layout XML's `<Tab>` tags (positional, no
`elementId`) determine which elements belong to which tab. See
`reference/specification/layout.md` → "Five-tag grammar" for the XML
side; this section covers only the JSON element shape.

```json
{
  "id": "tabs-1",
  "kind": "tabbed-container",
  "tabs": [
    { "name": "Tab A" },
    { "name": "Tab B" }
  ],
  "tabBar": {
    "style": "box",
    "alignment": "justify",
    "size": "medium"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"tabbed-container"` |
| `tabs` | yes | Array of `{ name }` — **labels only**, in display order. Order is load-bearing: it's the same order the layout XML's `<Tab>` tags must appear in. |
| `tabBar` | no | `{ style, alignment, size }` |
| `tabBar.style` | no | `"box"` observed |
| `tabBar.alignment` | no | `"justify"` observed; `"start"` likely supported (unverified) |
| `tabBar.size` | no | `"medium"` observed |

**The content-elements-are-flat-siblings rule is the one thing worth
getting wrong exactly once.** There is no `tabs[].elements` array and no
nested JSON container for a tab's content — an author instinct to nest
content under each tab object will silently fail (the field doesn't
exist, so it's dropped, and the tab renders empty). Declare tab content
as ordinary elements on the page's flat `elements[]` array, then wire
each one into the correct `<Tab>` block in the layout XML.

Tabbed containers can nest (a `<Tab>` containing another
`<TabbedContainer>`) per a harvested production workbook — this
specific case has not yet been independently authored-and-POSTed by
this skill; treat it as probably-fine, not confirmed.

## Modal pages

A modal is a **page**, not an element — set `type: "modal"` and a
`modal` object on the page itself, alongside its normal `elements[]`.

```json
{
  "id": "page-modal",
  "name": "Modal Test",
  "type": "modal",
  "modal": {
    "width": "small",
    "header": {
      "title": "Probe modal",
      "showCloseIcon": "hidden"
    },
    "footer": {
      "primaryCta": { "visible": "hidden" },
      "secondaryCta": { "visible": "hidden" }
    }
  },
  "elements": [
    { "id": "txt-modal-body", "kind": "text", "body": "Modal body text." }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `type` | yes (for a modal page) | `"modal"` |
| `modal.width` | no | `"small"` observed. A `"large"` value has been mentioned in passing but is unverified — not documented or confirmed anywhere else in this skill. Probe before relying on it. |
| `modal.header.title` | no | Accepts `{{formula}}` interpolation (e.g. `{{CurrentUserFirstName()}}`) per a harvested production workbook — not yet independently re-verified by this skill's own probe |
| `modal.header.showCloseIcon` | no | `"hidden"` observed |
| `modal.footer.primaryCta.visible` | no | `"hidden"` observed |
| `modal.footer.secondaryCta.visible` | no | `"hidden"` observed |

**Modal pages get a 12-column layout grid, not the standard 24** — see
`reference/specification/layout.md` → "Modal pages get a 12-column
grid, not 24." Author modal-page `<LayoutElement>` `gridColumn` values
against 12 columns.

**The modal page's layout `<Page>` tag keeps `type="grid"` — never
`type="modal"`.** The JSON `pages[].type: "modal"` field is the only
place that distinction is expressed; copying it into the layout XML's
`<Page type=...>` attribute is a wrong, easy-to-make mistake (verified
2026-08-03 — see `layout.md` → "Modal pages get a 12-column grid, not
24" for the corrected tag and the incident that surfaced it, and
`reference/history.md` for the full write-up).

Opening/closing a modal (`open-overlay`/`close-overlay` effects) is an
action/effect concern, not a page-structure one — documented once the
actions chunk exists; this section covers only the modal page's own
shape.

## Navigation

`kind: "navigation"` — an automatic page-navigation widget (tabs/menu
between the workbook's own pages). Self-contained; no data source.

```json
{
  "id": "nav-1",
  "kind": "navigation",
  "mode": "auto"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"navigation"` |
| `mode` | no | `"auto"` observed and verified via this skill's own POST probe. Other modes likely exist (inspect the OpenAPI) but are unverified. |

## Page break

`kind: "page-break"` — a print/export page-break marker. No other
fields observed.

```json
{
  "id": "brk-1",
  "kind": "page-break"
}
```

Verified via this skill's own POST probe: round-trips with no
additional fields beyond `id`/`kind`.

## What's still unverified from this capability wave

- `plugin` element (`kind: "plugin"`, `pluginId`, `config`) — observed
  via GET-spec against harvested production workbooks (see
  `reference/capability-ledger.md`), but not yet authored from scratch
  and POSTed by this skill. Two third-party forks disagree on whether
  `config` column bindings are bare `columnId` strings or `{kind:
  "column", columnId, source}` objects — do not guess; probe before
  documenting a shape as canonical.
- `open-overlay`/`close-overlay`/`select-tab` effects that target the
  surfaces on this page (modal, tabbed-container) — these are
  action/effect concerns, covered once that chunk lands.
