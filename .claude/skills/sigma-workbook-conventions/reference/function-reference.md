# Function reference

Common formula functions, namespace conventions, and how to discover Sigma functions not listed here. Load when authoring or reviewing formulas.

## Table of contents

- [Function quick reference](#function-quick-reference)
- [Looking up Sigma functions](#looking-up-sigma-functions)
- [Formula namespaces](#formula-namespaces)
- [Use data-model metrics before hand-deriving](#use-data-model-metrics-before-hand-deriving)

---

## Function quick reference

Common patterns. **Verify unfamiliar entries against `mcp__claude_ai_Sigma_Docs__*`
before relying — past versions have included Claude-fabricated signatures**
(see `reference/history.md`). Starting point, not a guarantee.

### Date / time

| Signature | Returns | Example |
|---|---|---|
| `DateTrunc("<unit>", <date>)` | date | `DateTrunc("week", [Date])` |
| `DateDiff("<unit>", <start>, <end>)` | integer | `DateDiff("week", [First Date], [Date])` |
| `DateAdd("<unit>", <n>, <date>)` | date | `DateAdd("day", -30, Today())` |
| `DateLookback("<unit>", <n>, <date>, <metric>)` | scalar | `DateLookback("week", 1, [Date], Sum([Revenue]))` |
| `Today()` / `Now()` | date / datetime | — |

`<unit>` is one of `"year"`, `"quarter"`, `"month"`, `"week"`, `"day"`, `"hour"`, `"minute"`. **Always quote** the unit literal.

### Aggregates (use inside a formula or as a column expression)

| Signature | Notes |
|---|---|
| `Sum(<expr>)` / `Min(<expr>)` / `Max(<expr>)` / `Avg(<expr>)` | Standard. |
| `Count(<expr>)` / `CountDistinct(<expr>)` | Count non-null rows / distinct values. |
| `Median(<expr>)` / `Percentile(<expr>, <p>)` | `<p>` in 0..1. |

**Aggregate-of-aggregate rule:** you cannot wrap an already-aggregated metric in another aggregate inline. Materialize the inner aggregate as a column first, then aggregate. See "Window functions require pre-materialized columns."

### Cross-element / per-row windowed aggregates

| Signature | What it does |
|---|---|
| `Lookup(<lookup-table.col>, <local-key>, <lookup-table-key>)` | Pull a value from a **sibling workbook element**, joined on a key. The lookup target must be a workbook element on the same page — `[D_DATAMODEL_ELEMENT/...]` raw refs are not allowed. |
| `Rollup(<aggregate-expr>, <local-group-col>, <source-group-col>)` | Pre-aggregate a metric over a grouping defined by a sibling element. The canonical "first purchase date per customer" pattern: `Rollup(Min([Source/Date]), [Cust Key], [Source/Cust Key])`. |

### Scalar conditionals

| Signature | Notes |
|---|---|
| `If(<cond>, <then>, <else>)` | Single conditional. |
| `Switch(<expr>, <v1>, <r1>, <v2>, <r2>, ..., <default>)` | Multi-branch. |
| `Coalesce(<a>, <b>, ...)` | First non-null. |
| `IsNull(<expr>)` / `IsNotNull(<expr>)` | Boolean. |

### Numeric guards

| Signature | Notes |
|---|---|
| `Greatest(<a>, <b>, ...)` | Returns max of arguments. Use to clamp `>= 0`: `Greatest(DateDiff(...), 0)`. |
| `Least(<a>, <b>, ...)` | Returns min. |
| `Abs(<n>)` | Absolute value. |
| `Round(<n>, <digits>)` / `Ceiling(<n>)` / `Floor(<n>)` | Rounding. |

**Safe division:** `If([denom] = 0, Null, [num]/[denom])` or `Zn([num]/[denom])`. (No `DivideSafe()` — see `reference/history.md`.)

### Strings

| Signature | Notes |
|---|---|
| `Concat(<a>, <b>, ...)` | String concatenation. |
| `Contains(<haystack>, <needle>)` | Boolean. |
| `Left(<s>, <n>)` / `Right(<s>, <n>)` / `Substring(<s>, <start>, <len>)` | Slicing. |
| `Lower(<s>)` / `Upper(<s>)` / `Trim(<s>)` | Case + whitespace. |
| `Replace(<s>, <find>, <repl>)` | String replace. |

### Type / casting

| Signature | Notes |
|---|---|
| `Number(<s>)` / `Text(<n>)` / `Date(<s>)` | Type coercion. |
| `Boolean(<expr>)` | Cast to truthy/falsy. |

### Column-reference syntax (not functions, but reference)

| Form | Meaning |
|---|---|
| `[Column Name]` | Bare reference within the same element's namespace. |
| `[Source Element Display Name/Column Name]` | Cross-element reference to a sibling on the same page. |
| `[Metrics/Metric Name]` | Reference a data-model metric (only available on data-model-sourced elements). |
| `[ControlId]` | Reference a control's current value (see "Controls as formula values"). |

**Argument order traps that are easy to misremember:** `DateDiff` is `(unit, start, end)` not `(start, end, unit)`; `Rollup` is `(aggregate, local-key, source-key)` not `(aggregate, source-key, local-key)`; `Lookup` is `(target.col, local-key, target-key)` not `(target.col, target-key, local-key)`. The skill enforces these — if you can't remember, copy from this table.

For functions not listed here (statistical, trig, advanced string, JSON, etc.), use `mcp__claude_ai_Sigma_Docs__search` → `mcp__claude_ai_Sigma_Docs__fetch`.

## Looking up Sigma functions

This skill documents **patterns** (Lookup, Rollup, multi-level
groupings, materialize-then-window) and verified spec shapes. It does
NOT enumerate every Sigma formula function — that lives in Sigma's
official docs.

Retrieve current function documentation via the native
`mcp__claude_ai_Sigma_Docs__*` MCP integration (no auth, no bash, no
`WebFetch`):

- `mcp__claude_ai_Sigma_Docs__search` — keyword search for a function
  by name or topic ("is there a function that does X"). Returns
  `{id, title, url}` for top matches.
- `mcp__claude_ai_Sigma_Docs__fetch` — pull the full docs page for a
  specific function by id (returned by `search`).

Schemas load via `ToolSearch` on first use
(`select:mcp__claude_ai_Sigma_Docs__search,mcp__claude_ai_Sigma_Docs__fetch`).
Allowlisted in `.claude/settings.json` so calls run silent.

For Sigma's REST API endpoint reference (request/response shapes,
parameters, paths), the same MCP server exposes:

- `mcp__claude_ai_Sigma_Docs__list-endpoints` — full path/method index
- `mcp__claude_ai_Sigma_Docs__search-endpoints` — keyword search
- `mcp__claude_ai_Sigma_Docs__get-endpoint` — fetch a specific endpoint

Practical convention: when authoring a spec and you need a function
beyond the ones already documented in this skill, do a `search` →
`fetch` round-trip rather than guessing the signature from training
data. Sigma's function semantics (e.g. argument order on `Rollup`,
`DateLookback`, `DateAdd`) are too easy to misremember, and the cost
of a malformed formula is a silent NULL or an `iff(equal_null, …)`
defensive wrap in the SQL, not a POST error.

What this skill does cover natively (no need to look up):

- `Lookup`, `Rollup`, `DateLookback` — full sections with shape + when
  to use which.
- `[Metrics/<Name>]` reference syntax for data-model metrics.
- `[<sibling-element-display-name>/<column-name>]` cross-element refs.
- The materialize-then-window rule (you can't put `Min`, `Max`, `Sum`,
  `Rank` etc. directly on top of an unmaterialized expression).

Everything else — date math, string ops, conditional, statistical,
trig, type conversion — defer to `Sigma_Docs` MCP lookups.


## Formula namespaces

Formulas inside an element resolve column references against:

1. The element's **own** `columns` (bare names like `[Price]`, `[Revenue]`).
2. The **source element's** namespace, addressed as
   `[<Source Element Display Name>/<Column Name>]`.
3. The **data-model metric** namespace: `[Metrics/<Metric Name>]`.

| Element | Source kind | Formula style for upstream columns |
|---------|-------------|-------------------------------------|
| Table fed by data-model element `Plugs Transaction Details - Relationships` | `data-model` | `[Plugs Transaction Details - Relationships/Date]` |
| Bar chart fed by sibling table named `Plugs Transaction Details` | `table` | `[Plugs Transaction Details/Date]` |
| Calc on the table itself | (own namespace) | `[Price] * [Quantity]` |

Note that when the table's `name` differs from the data-model element's name,
the chart's reference uses the **table's display name**, not the upstream
data-model element's name.


## Use data-model metrics before hand-deriving

If the data model defines a metric that matches what you want to compute,
reference it via `[Metrics/<Metric Name>]`. Do not redo the math in the
workbook. Reasons:

- The metric carries formatting (currency, percent, decimals).
- Single source of truth — if the metric formula changes, the workbook tracks
  automatically.
- Less spec churn when the warehouse columns rename or restructure.

Discover available metrics with `jq '.. | objects | select(.metrics) | .metrics'`
on `GET /v2/dataModels/{id}/spec`. They live on the node element's `metrics`
array. Always check this BEFORE writing a custom calc.

