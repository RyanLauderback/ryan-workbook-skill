# `styled-card-dashboard.json` — design intent

Canonical reference exemplar for **element styling** (Capability 1
of the 2026-05-21 training enrichment). Source: GET-spec harvest of
`Sales-Performance-Eval-1-oGZFP7xYXAdzeMdL6EvLv` against the
`<DATA_MODEL_ELEMENT_NAME>` table on `<DATA_MODEL_ID>`. Design intent
captured below from the paired training spec
(`prompts/library/train_format_retail_sales_performance.md`).

## When to clone this exemplar

Any "professional", "clean", "card-style", or "modern" sales/operations
dashboard request where the user expects visual hierarchy through
container styling rather than heavy chrome on individual viz elements.

## Templated placeholders

Replace before POST:

- `<DESTINATION_FOLDER_ID>` — Sigma folder for the new workbook.
- `<DATA_MODEL_ID>` — UUID of the data model the base table sources from.
- `<DATA_MODEL_ELEMENT_ID>` — node id of the data-model element to source.
- `<DATA_MODEL_ELEMENT_NAME>` — display name used in `[<name>/Column]`
  formula references (the data-model element's `name`, not the workbook
  table's `name`).

Everything else — element IDs, control IDs, column IDs, layout XML — is
internally consistent and POSTs cleanly via
`scripts/api/publish-workbook.sh post` after the four placeholders are
swapped.

## Layout architecture

Single page (`page-overview`), 24-column grid, sectional top-to-bottom
flow. The container hierarchy is the load-bearing piece:

```
ctr-header           — accent-bordered control panel (filters + title)
  ├── txt-title
  ├── ctrl-date / ctrl-region / ctrl-product-type
T5H6LQqM8J           — border-only spacer (gray)
ctr-kpi              — accent-bordered KPI row
  └── 4 KPI tiles (card style, no bg — container bg shows through)
DMvNTBriJJ → HRz_VAxGJc   — spacer + section title pair
  └── combo-chart trend (card style)
eV7mOr4Nwp → zZU8fg9HJM   — spacer + section title pair
  └── bar-chart + donut-chart (card style)
rLXycHSALM → Kf3pyEFi5s   — spacer + section title pair
  └── 2 tables (card style)
Gz0XAGf8qp → EmC2ag0V2J   — spacer + section title pair
  └── scatter-chart + store-economics table (card style)
(no spacer)               — section title only
  └── tbl-tx full-width transactions table (card style)
```

Each non-final analytical section follows the same three-step
shape: **spacer container** (visual gap) → **section title container**
(tinted background + section heading text) → **viz cards** (white card
style).

## Element-styling rules (Capability 1 demo)

The exemplar is built around five `style` recipes — all documented in
`reference/specification/containers.md` § "Common style recipes":

| Recipe | `style` body | Used by |
|---|---|---|
| **Card** (default) | `{backgroundColor: #FFFFFF, borderRadius: round, borderColor: #E8DFD3, borderWidth: 1}` | All charts + tables |
| **Accent header** | `{backgroundColor: #FFFFFF, borderRadius: round, borderColor: #ce785c, borderWidth: 3}` | `ctr-header`, `ctr-kpi` |
| **Section title** | `{backgroundColor: #f5f0e8, borderColor: #cd785c, borderWidth: 3}` | `HRz_VAxGJc`, `zZU8fg9HJM`, `Kf3pyEFi5s`, `EmC2ag0V2J` |
| **Spacer** | `{backgroundColor: #B4B4B4, borderColor: #FFFFFF, borderWidth: 3}` | `T5H6LQqM8J`, `DMvNTBriJJ`, `eV7mOr4Nwp`, `rLXycHSALM`, `Gz0XAGf8qp` |
| **Subtle control** | `{backgroundColor: #FAF7F2, borderRadius: round}` | All three controls (no border) |
| **KPI tile** | `{borderRadius: round, borderColor: #E8DFD3, borderWidth: 1}` (no fill) | The 4 KPIs — container fill shows through |

**Rule of thumb:** if the user asks for a "card-style" or "professional"
dashboard, the card recipe + spacer/section-title scaffold gives them
80% of the visual feel. Pick a single accent color (e.g. `#ce785c`)
and reuse it across header + section titles + spacers.

## What this exemplar does NOT cover

Reserved for later capability passes — do not clone this exemplar
expecting to find:

- **Dividers, images, background images** (Capability 2).
- **Dynamic titles with formulas** (Capability 3). The KPI titles here
  use the styled-name object form `{text, color, fontSize, fontWeight}`
  (already documented 2026-05-19), not formula-driven titles.
- **Hidden pages, dynamic text** (Capability 4). Text bodies use static
  inline HTML (`<span style="...">`).
- **Table/pivot conditional formatting** (Capability 5).
- **DM-inherited controls** (Capability 6). Controls here are workbook-
  level.
- **Net-new chart-type fields** (Capability 7). The chart axis shape
  uses `xAxis: {columnId: "..."}` / `yAxis: {columnIds: [...]}` — the
  canonical form documented in `reference/specification/charts.md`
  → "Axis shape — canonical." This exemplar surfaces it via harvest.
- **Maps** (Capability 8 — and currently documented as unsupported in
  workbooks-as-code).

## Why no `.prompt.md` for the data inputs themselves

The base table sources from a data model element that already provides
the metrics (`Total Revenue`, `Total Profit`, `Profit Margin`, `AOV`,
`Units Sold`) via the `[Metrics/<Name>]` reference. The exemplar
assumes you've identified an analogous element on `<DATA_MODEL_ID>`
before cloning. See `SKILL.md` → "Workflow: resolve user input before
planning."
