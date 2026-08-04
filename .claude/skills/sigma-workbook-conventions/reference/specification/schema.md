# Workbook spec — top-level schema

The overall shape of the workbook spec passed to `POST /v2/workbooks/spec`.

## Consulting the OpenAPI

The Sigma OpenAPI is the canonical schema for every request/response
shape. When this skill and the OpenAPI disagree, the OpenAPI wins. Fetch
once per session and inspect with `jq`:

```bash
curl -sf https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json > /tmp/sigma-api.json

# Workbook spec POST request body
jq '.paths."/v2/workbooks/spec".post.requestBody.content."application/json".schema' /tmp/sigma-api.json

# A specific element kind's full shape
jq '.components.schemas.BarChart' /tmp/sigma-api.json
jq '.components.schemas.KpiChart' /tmp/sigma-api.json

# List every schema name (when you don't know the right one)
jq -r '.components.schemas | keys[]' /tmp/sigma-api.json | grep -i <hint>
```

Every per-element file in this directory opens with the relevant `jq`
recipe. Use it whenever a field shape has changed or the skill's coverage
doesn't include a feature you need.

### Schema-drift signal

If a POST/PUT fails with `invalid argument`, `unknown field`,
`unexpected property`, `missing required field`, `unrecognized parameter`,
or a 400 about request *shape* rather than data — the API has evolved
since this skill was written. Fallback in `reference/workflows/crud.md` →
"Schema drift."

This file covers what the OpenAPI alone won't tell you: which fields are
response-only, the ID-preservation guarantee on CREATE, and a minimal
working example. For per-element shapes, see the per-element files in
this directory.

## Top-level object

```json
{
  "name": "My Workbook",
  "folderId": "<folder-uuid>",
  "description": "Optional description",
  "schemaVersion": 1,
  "pages": [...],
  "layout": "<?xml version=\"1.0\" encoding=\"utf-8\"?>...</Page>..."
}
```

**Required:** `name`, `folderId`, `schemaVersion`, `pages`.
**Optional:** `description`, `layout`.

See `reference/workflows/crud.md` → "schemaVersion — don't hardcode"
for the rule on `schemaVersion`. Existing exemplars use `1`; future
versions will require reading from a reference GET.

## Wire format — the live API wraps the document under a `document` key

**This section is about transport, not authoring.** Every shape
described in this file and the rest of `reference/specification/` is
the **flat authoring shape** — `schemaVersion`/`pages`/`layout`/etc. as
top-level siblings of `name`/`folderId`. Keep authoring that shape.
This section explains what happens between writing that JSON and it
reaching the live API.

**Confirmed 2026-08-04 via direct live-POST/PUT/GET testing** (not
GET-spec-only — a bare flat-shape spec was actively POSTed and
rejected, confirming this isn't a passive artifact): the real Sigma
REST API nests `schemaVersion`, `kind`, `pages`, `layout`,
`themeOverrides`, `folders`, and `agents` under a top-level `document`
key. Only `name`, `folderId`, and `description` remain true top-level
siblings on the request (plus response-only metadata — see below —
which also lives outside `document`). `document.kind` is **required**
and is always the literal string `"workbook"`:

```json
{
  "name": "My Workbook",
  "folderId": "<folder-uuid>",
  "document": {
    "schemaVersion": 1,
    "kind": "workbook",
    "pages": [...],
    "layout": "<?xml version=\"1.0\" ...?>...</Page>..."
  }
}
```

POSTing the flat shape as-is against the live API is rejected with a
large union-type validation error naming paths like `0.document.0.0.0`
— easy to misread as unrelated schema drift rather than "wrap this in
a `document` key." A GET on an existing workbook's spec confirms the
same nesting comes back on read: `{"workbookId": ..., "document":
{"schemaVersion": 1, "kind": "workbook", "pages": [...], ...}}`.

**You do not need to hand-wrap this.** `scripts/api/publish-workbook.sh`
wraps flat → wire on `post`/`put` and unwraps wire → flat on
`get-spec`, transparently, so the flat shape stays the one authoring
convention across this skill's tooling, examples, and docs. This only
matters to you if you POST/PUT/GET directly via raw `curl` instead of
through that script (e.g. ad-hoc schema investigation) — in that case
wrap/unwrap by hand per the shape above.

A separate claim from the same investigation — that successful
POST/PUT responses come back as plain `key: value` text instead of
JSON — was checked and is **not real** for this skill's actual call
path: `scripts/api/_env.sh`'s `sigma_curl` helper already sends
`Accept: application/json` (every script in `scripts/api/` goes
through it), and the API honors that header on both GET and POST/PUT.
The plain-text response only appears when that header is omitted
(e.g. a raw `curl` call made outside `sigma_curl` during ad-hoc
bisection). No dual-format response parsing was added anywhere in this
skill's tooling — it wasn't needed.

See `reference/history.md` → "2026-08-04 — document wrapper" for the
full incident and verification trail, and
`reference/capability-ledger.md` for how this affects the dating of
earlier POST evidence in that ledger.

## Response-only fields

`GET /v2/workbooks/<id>/spec` also returns these. **Correction
(2026-08-03):** previously stated they "must be stripped... sending
unknown top-level fields is rejected" — the real upstream `sigma-workbooks`
skill states the opposite: these fields are **ignored on write**
(POST/PUT), so a GET response can be re-submitted without stripping them
first, though doing so is cleaner and is still the recommended practice
below:

- `workbookId`
- `url`
- `documentVersion`
- `latestDocumentVersion`
- `ownerId`
- `createdBy`
- `updatedBy`
- `createdAt`
- `updatedAt`

`scripts/workbook-manifest.py` recognizes these and won't flag them
as unknown. `scripts/validate-spec.py` warns when they're present on
a file being POSTed.

## Pages

`pages` is the core of the spec. Each page:

```json
{
  "id": "page-overview",
  "name": "Overview",
  "elements": [...]
}
```

Optional page-level keys:

- `visibility: "hidden"` — hides the page from the workbook's tab bar.
  See `reference/specification/text.md` and the iteration pattern in
  `reference/workflows/plan.md`.
- `description` — page-level description string.

The `elements` array holds tables, charts, KPIs, controls, containers,
text, dividers, and images. See the per-element reference files.

## ID rules

- Element IDs and column IDs must be **unique within their scope**
  (the same `id` on different pages is allowed; the same `id` twice
  in one page is not).
- Use descriptive kebab-case or short random-looking IDs — both are
  fine. IDs are internal identifiers, not displayed to users.
- **IDs are preserved verbatim on `POST`.** Pages, elements, and
  columns keep the `id` values you sent. Layout `elementId`
  references stay valid across POST/PUT round-trips. You can save a
  spec, edit it, and `PUT` it back directly using the same IDs.
- Layout `elementId` references must match an element `id` on that
  page exactly (case-sensitive).

Verified 2026-07-02 against harvested exemplars: skill-authored
workbooks (`plugs-geography-yoy`, `store-performance-pop`) retained
100% of their kebab-case IDs after POST/GET round-trip.

## Layout

`layout` is a top-level XML string carrying one `<Page>` element per
workbook page. Multi-page workbooks concatenate the per-page XML docs
(each with its own `<?xml ?>` declaration). See
`reference/specification/layout.md`.

## Top-level `folders` field

Optional. Carries column-folder groupings for the workbook. Most
workbooks omit it. When present, looks like:

```json
"folders": [
  { "id": "ejtrqOFhcK", "name": "Store Fields", "items": [...] }
]
```

The `items` are column IDs grouped under the folder name. UI-side
organization; doesn't affect render. Inspect via `mcp-describe.sh
workbook <wb-id>` if you need the structure.

## Top-level `themeOverrides` field

Optional. Controls workbook-wide page width and spacing:

```json
"themeOverrides": {
  "pageWidth": "large",
  "space": { "unit": "small" }
}
```

Observed values: `pageWidth: "large"`, `space.unit: "small"`. Other
enum values (`medium`, `full`, etc.) likely accepted — inspect via
the OpenAPI. Verified 2026-07-02 against `sales-mbr-sentinel`.

## `theme` element kind

A named theme reference that can appear inside `pages[].elements[]`
alongside data-viz elements:

```json
{
  "kind": "theme",
  "ref": "colors-textNeutral"
}
```

Observed in `sales-mbr-sentinel` (2 instances). Applies theme-level
styling by reference. Inspect the OpenAPI for the enum of valid `ref`
values before authoring. Kept minimal here until a fuller pattern
emerges.

## Minimal working example

The smallest spec that creates a workable workbook:

```json
{
  "name": "Sales Dashboard",
  "folderId": "<folder-uuid>",
  "schemaVersion": 1,
  "pages": [
    {
      "id": "page-1",
      "name": "Overview",
      "elements": [
        {
          "id": "sales-table",
          "kind": "table",
          "name": "Sales Data",
          "source": {
            "kind": "warehouse-table",
            "connectionId": "<conn-uuid>",
            "path": ["SALES_DB", "PUBLIC", "ORDERS"]
          },
          "columns": [
            { "id": "col-order-id", "name": "Order ID", "formula": "[ORDERS/order_id]" },
            { "id": "col-amount",   "name": "Amount",   "formula": "[ORDERS/amount]" },
            { "id": "col-total",    "name": "Total",    "formula": "Sum([Amount])" }
          ]
        }
      ]
    }
  ]
}
```

Notes:

- `[ORDERS/order_id]` references a warehouse column (table prefix required).
- `Sum([Amount])` references the "Amount" column defined in the same
  element (no prefix).

For a realistic multi-page reference, see
`examples/data-model-sourced-multi-page-profitability-attrition.json`.
For a full official multi-page example, see `example-full.yaml` in
this directory.
