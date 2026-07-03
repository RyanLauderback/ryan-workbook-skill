# Sigma formula reference

The largest source of spec errors and the OpenAPI doesn't fully describe
the formula language semantics. Treat this as the source of truth for
the **formula language itself** (syntax, qualification, operator
behavior). Field-level shape (where formulas appear in the spec) is in
the OpenAPI per-element schemas.

## Table of contents

Load-bearing gotchas (read first):

- [⚠️ READ FIRST — The #1 formula mistake](#-read-first--the-1-formula-mistake)
- [⚠️ READ SECOND — Raw vs. friendly column names](#-read-second--raw-vs-friendly-column-names)
- [⚠️ READ THIRD — Boolean operators are NOT function calls](#-read-third--boolean-operators-are-not-function-calls)

Reference rules:

- [Column reference rules](#column-reference-rules) (inside vs outside the element)
- [Data-model metrics — `[Metrics/<Name>]`](#data-model-metrics--metricsname)
- [Formula namespaces summary](#formula-namespaces-summary)
- [Common mistakes](#common-mistakes)

Language:

- [Operators](#operators) (arithmetic, boolean, string concat)
- [Aggregation functions](#aggregation-functions)
- [Date functions](#date-functions)
- [Conditional](#conditional)
- [Text functions](#text-functions)
- [JSON / struct field access](#json--struct-field-access)

Advanced patterns:

- [Cross-element joins via `Lookup()`](#cross-element-joins-via-lookup) (with verified dimension-passthrough example)
- [Per-row windowed aggregations — `Rollup`](#per-row-windowed-aggregations--rollup)
- [Window functions](#window-functions) (`Rank`, `Lead`, `Lag`, `RunningSum`, etc.)
- [Numeric guards](#numeric-guards) (safe division, `Zn`, DivideSafe hallucination warning)

Troubleshooting:

- [Looking up Sigma functions](#looking-up-sigma-functions) (via Sigma_Docs MCP)
- [When the formula fails at render](#when-the-formula-fails-at-render)

---

## ⚠️ READ FIRST — The #1 formula mistake

When an element sources another element (e.g., a KPI or chart
sourcing a table), **every column reference inside aggregations must
include the source element's name as a prefix.** Forgetting the
prefix is the single most common Sigma spec error.

**Wrong:**

```json
{
  "kind": "kpi-chart",
  "source": { "kind": "table", "elementId": "usage-table" },
  "columns": [
    { "name": "Total", "formula": "Count([Question ID])" }
  ]
}
```

**Right:**

```json
{
  "kind": "kpi-chart",
  "source": { "kind": "table", "elementId": "usage-table" },
  "columns": [
    { "name": "Total", "formula": "Count([AI Usage Data/Question ID])" }
  ]
}
```

**Why:** a bare `[column_name]` means *defined in THIS element's own
`columns[]` array* — not *visible through the source*. SQL intuition
leaks here: `Count([col])` feels local because the source "is" the
table, but Sigma's formula language requires you to name the source
explicitly.

**Rule of thumb:** if your element's `source` points at another
element (or a warehouse table, or a join), 90%+ of your formulas
will start with `[<SourceName>/...]`. Bare refs are only for columns
you literally defined a line or two above in the same `columns[]`
array.

`scripts/validate-spec.py`'s `bare-ref-resolution` check catches
this pre-POST.

## ⚠️ READ SECOND — Raw vs. friendly column names

Sigma's formula DSL references columns by their **friendly name**,
not their raw warehouse name. See `sources-warehouse.md` →
"Friendly vs. raw column names" for the normalization rules.

The trap: `GET /v2/connections/tables/{inodeId}/columns` returns
raw warehouse names; formulas need friendly names. Sigma is
permissive at POST and normalizes casing for many simple cases, but
the auto-fix doesn't cover everything.

**Don't guess the normalization rules** — Sigma's are more
aggressive than they look. When verify fails, ask the readback:
`scripts/api/publish-workbook.sh get-spec <wb-id>` shows Sigma's
canonical friendly names.

## ⚠️ READ THIRD — Boolean operators are NOT function calls

`and`, `or`, `not` are **prefix/infix operators**, not function
calls. **Always put a space before the operand.**

```
Wrong: Not(Contains([Deployment], "staging"))   // parses, but every row is null
Right: Not (Contains([Deployment], "staging"))  // space after Not

Wrong: And([Active], [Paid])                    // not a function
Right: [Active] And [Paid]                      // infix

Wrong: Or([Trial], [Free])                      // not a function
Right: [Trial] Or [Free]                        // infix

Right: Not [Active]
Right: [A] And Not [B]
Right: ([Status] = "Active") And ([Plan] = "Pro")
```

**The trap:** `Not(...)` parses successfully (the parens become
grouping), so the failure is silent — null rows, no error. Easy to
get wrong by analogy with `Sum([X])` / `If(...)`.

### Null tests — `IsNull()` function, not `Is Null` operator

Sigma does NOT accept SQL-style `[Col] Is Null` or `Is Not Null`
operators. Use the `IsNull()` function form instead:

```
Wrong: If([Historical Avg] Is Null, Null, ...)          // API rejects: Invalid formula
Wrong: If([Historical Avg] Is Not Null, ..., Null)

Right: If(IsNull([Historical Avg]), Null, ...)
Right: If(Not IsNull([Historical Avg]), ..., Null)
```

Verified 2026-07-02 against `exec-scorecard-v2` PUT rejection.
Reads naturally to SQL/Python authors; wrong for Sigma.

## Column reference rules

Every column formula references either a column **outside** the
element or a column **inside** the same element.

### Outside the element — `[SourceName/column_name]`

The prefix depends on the source type:

- **Warehouse table:** `SourceName` = last segment of the `path` array.
  - Path `["DB", "SCHEMA", "ORDERS"]` → `[ORDERS/revenue]`
  - Path `["ANALYTICS", "PUBLIC", "USERS"]` → `[USERS/email]`

- **Another workbook element:** `SourceName` = that element's `name`
  field.
  - Element named "Sales Table" → `[Sales Table/Revenue]`

- **Join source:** `SourceName` = the `name` field on a specific
  join leg, or the top-level `name` on the join object (for
  `primarySource` columns).
  - Join with `primarySource` tied to top-level `name: "Sales Star"`
    → `[Sales Star/Order Number]` for primary columns.
  - Join leg with `name: "Sales"` → `[Sales/Cust Key]` for that
    joined table's columns.
  - Warehouse path segments do **not** become the prefix inside a
    join — use the join leg's `name`.

- **Union source:** `SourceName` = the union's `name` field.
  References resolve against the union's `matches[].outputColumnName`.
  - Union with `name: "All Sales"` → `[All Sales/Order Number]`.
  - **If you omit `name`,** Sigma assigns `"Union of N Sources"`;
    bare references can become circular self-references. Set `name`
    explicitly.

- **Data-model element:** `SourceName` = the DM element's `name`
  field (returned by `mcp-describe.sh datamodel-element`).
  - DM element named "Transactions with Details" →
    `[Transactions with Details/Date]`.
  - **Special characters in the name are safe.** `&`, `(`, `)`, and
    spaces all parse correctly inside the brackets — verified against
    `[Transactions with Details & Relationships (5M)/...]`. The
    bracket scopes the whole name; the `/` between source and column
    is the only parse hazard (see "Data-model metrics" → slash-in-name
    caveat).

- Column names must match exactly what the describe endpoint
  returns. **Never invent column names.**

### Inside the same element — `[column_name]` (no prefix)

References a column already defined in this element by its `name`
field.

```
// Given columns: "Revenue" (formula: [ORDERS/revenue]), "Cost" (formula: [ORDERS/cost])
// A third column can reference them:
[Revenue] - [Cost]       // valid — references sibling columns by name
Sum([Revenue])           // valid — aggregation over a sibling column
```

**A column cannot reference itself** — circular reference error.
This trips up copy-paste: if a column's `name` field matches any
bracketed reference inside its own `formula`, the server treats it
as circular even when you meant to reference a different column.
Rename one side to break the cycle.

**On KPIs specifically:** the value column's formula can't
reference sibling columns whose formulas contain aggregation
functions (`Sum`, `Avg`, `Count*`, `Median`, etc.). The bare ref
resolves per-row, an aggregation has no per-row value, and the KPI
renders `null`. See `kpis.md` → "Value formula pitfall: can't
reference sibling aggregation columns" for the correct patterns.

## Data-model metrics — `[Metrics/<Name>]`

Workbook elements sourcing from a data-model element can reference
metrics defined on the DM via the `[Metrics/<Name>]` namespace:

```json
{
  "id": "kpi-revenue",
  "source": { "kind": "table", "elementId": "tbl-sales" },
  "columns": [
    { "id": "val", "formula": "[Metrics/Total Revenue]" }
  ]
}
```

`tbl-sales` is sourced from a DM element via `kind: data-model`. The
DM defines metrics like "Total Revenue" with their formulas + format.
The workbook references the metric by name; resolution happens at
render against the DM's metric catalog.

**Discover available metrics** via `mcp-describe.sh datamodel-element
<dm> <el>` — the response includes a `metrics` array.

**The slash-in-name caveat:** metric names containing `/` (e.g.,
`Cost/Member/Month`) are not safely addressable as
`[Metrics/Cost/Member/Month]` — the `/` is the namespace delimiter
and parsing of multi-slash names is undefined. Either rename the
metric in the data model, or fall back to a hand-derived formula.

**DM-switch hard rule.** On any data-model switch mid-session,
re-derive every `[Metrics/...]` reference from the new recon. Never
carry metric names forward from a previous DM's plan. Full rule in
`reference/conventions.md` → "`[Metrics/<Name>]` resolution +
DM-switch hard rule."

## Formula namespaces summary

| Element | Source kind | Reference syntax for upstream columns |
|---|---|---|
| Table fed by warehouse | `warehouse-table` | `[<last-path-segment>/<column>]` |
| Table fed by DM element | `data-model` | `[<dm-element-name>/<column>]` or `[Metrics/<metric-name>]` |
| Bar chart fed by sibling table | `table` | `[<sibling-element-display-name>/<column>]` |
| Chart fed by join | `join` | `[<join-leg-name>/<column>]` or `[<top-level-join-name>/<column>]` for `primarySource` |
| Calc on the element itself | (any) | `[<sibling-column-name>]` |

Note that when the table's `name` differs from the data-model
element's name, the chart's reference uses the **table's display
name**, not the upstream data-model element's name.

## Common mistakes

| Wrong | Correct | Why |
|---|---|---|
| `[revenue]` | `[ORDERS/revenue]` | Missing table prefix for warehouse column |
| `[ORDERS/Total Revenue]` | `[Total Revenue]` | "Total Revenue" is a sibling column, not a warehouse column |
| `[Revenue]` in the "Revenue" column | Rename one side | A column cannot reference itself |
| `Count([Question ID])` on a sourced element | `Count([AI Usage Data/Question ID])` | Aggregation argument needs the source prefix |
| `Not(Contains(...))` | `Not (Contains(...))` | `Not` is a prefix operator, not a function |
| `Concat([First], [Last])` | `[First] & [Last]` | Use `&` for string concat, not `Concat()` |
| `Power([X], 2)` | `[X] ^ 2` | Use `^` for power, not `Power()` |
| `Mod([X], 7)` | `[X] % 7` | Use `%` for modulo, not `Mod()` |
| `Case WHEN ... THEN ...` | `If(<cond>, <then>, <else>)` | Sigma has no `Case`; use chained `If` |

## Operators

### Arithmetic

`+`, `-`, `*`, `/`, `%` (modulo), `^` (power)

**Do not use** `Power()` or `Mod()` — use `^` and `%`.

### Boolean

`and`, `or`, `not` — prefix/infix operators. Always put a space
before the operand. See "Boolean operators are NOT function calls"
above.

### String concatenation

`&` (not `+`, not `Concat()`).

```
[First Name] & " " & [Last Name]
```

## Aggregation functions

| Function | Description |
|---|---|
| `Sum([col])` | Sum of values |
| `Avg([col])` | Average of values |
| `Count([col])` | Count of non-null values |
| `CountDistinct([col])` | Count of distinct values |
| `Min([col])` | Minimum value |
| `Max([col])` | Maximum value |
| `Median([col])` | Median value |
| `Percentile([col], 0.95)` | Nth percentile |
| `Mode([col])` | Most frequent value |

## Date functions

| Function | Example |
|---|---|
| `DateTrunc(<part>, <date>)` | `DateTrunc("month", [Date])` |
| `DateDiff(<part>, <start>, <end>)` | `DateDiff("day", [Start], [End])` |
| `DateAdd(<part>, <units>, <date>)` | `DateAdd("month", 3, [Date])` |
| `DateFormat(<date>, <fmt>)` | `DateFormat([Date], "%Y-%m-%d")` |
| `Now()` | Current timestamp |
| `Today()` | Current date |

Date parts (must be quoted strings): `"year"`, `"quarter"`,
`"month"`, `"week"`, `"day"`, `"hour"`, `"minute"`, `"second"`.

## Conditional

```
If(<condition>, <then>, <else>)
```

Supports multiple conditions (chained):

```
If([Status] = "Active",  "Active",
   [Status] = "Pending", "Pending",
   "Other")
```

**Do not use** `Case` — use `If`.

## Text functions

| Function | Description |
|---|---|
| `Contains(<text>, <search>)` | True if text contains search |
| `Left(<text>, <n>)` | First n characters |
| `Right(<text>, <n>)` | Last n characters |
| `Upper(<text>)` | Uppercase |
| `Lower(<text>)` | Lowercase |
| `Trim(<text>)` | Remove leading/trailing whitespace |
| `Length(<text>)` | Character count |
| `Replace(<text>, <old>, <new>)` | Replace occurrences |

## JSON / struct field access

Columns containing JSON or struct data (common for event payload /
metadata columns) support **field access via dot notation** on the
bracketed column reference. The extracted value is untyped — wrap
it in the appropriate type constructor (`Text`, `Number`, `Date`) to
coerce before passing it to downstream functions.

```
Text([Langfuse Metadata].agentId)           // extracts agentId as text
Text([Event Payload].user.id)               // nested access
Number([Event Payload].latency_ms)          // numeric cast
Text([Organizations].users[0])              // array index — first element
Text([Organizations].users[0].email)        // index + nested field
```

Without the wrapping cast, comparisons (`=`, `<`), aggregations
(`Count`, `CountDistinct`), and text ops (`Contains`, `&`) will
often behave unexpectedly or fail silently — the extracted value
keeps its variant/untyped flavor.

Dot notation goes directly on the `]` — no space: `[Col].field`,
not `[Col] .field`.

## Cross-element joins via `Lookup()`

To join two workbook elements without modifying the underlying data
model, use `Lookup()` formulas on the target element. The target
needs:

- The local key column (e.g. `Cust Key`) declared with an explicit
  `name`, so it can be referenced as `[Cust Key]` from formulas on
  the same element.
- A sibling element on the same page sourcing the lookup table —
  Lookup needs a workbook element to resolve against, not a raw
  data-model reference.

Then each looked-up column is one passthrough formula:

```
Lookup([<Target Element Display Name>/<Target Column>], [<Local Key>], [<Target Element Display Name>/<Target Key>])
```

Example — bringing customer demographics from a `Customer Details`
sibling table into `Plugs Transaction Details` joined on `Cust Key`:

```json
{
  "id": "col-cust-region",
  "name": "Cust Region",
  "formula": "Lookup([Customer Details/Cust Region], [Cust Key], [Customer Details/Cust Key])"
}
```

The lookup-source element doesn't have to be the visual focus of
the page, but it must exist on the page and be placed in the layout
XML.

### Verified pattern — dimension-passthrough for drill-through

The most common `Lookup()` use is broadcasting a dimension table's
attributes onto a fact table for drill-through and control targets.
Verified 2026-07-02 against a 7-column customer-demographics pull
from `Customers` into `Cust Tx` on `Cust Key`:

```json
{
  "id": "tbl-cust-tx",
  "kind": "table",
  "name": "Cust Tx",
  "source": { "kind": "table", "elementId": "tbl-transactions" },
  "columns": [
    { "id": "col-cus-key",       "name": "Cust Key",       "formula": "[Transactions/Cust Key]" },
    { "id": "col-cus-tx-date",   "name": "Date",           "formula": "[Transactions/Date]" },
    { "id": "col-cus-tx-amt",    "name": "Sales Amount",   "formula": "[Transactions/Sales Amount]" },

    { "id": "col-cus-region",    "name": "Cust Region",    "formula": "Lookup([Customers/Cust Region], [Cust Key], [Customers/Cust Key])" },
    { "id": "col-cus-state",     "name": "Cust State",     "formula": "Lookup([Customers/Cust State], [Cust Key], [Customers/Cust Key])" },
    { "id": "col-cus-type",      "name": "Cust Type",      "formula": "Lookup([Customers/Cust Type], [Cust Key], [Customers/Cust Key])" },
    { "id": "col-cus-gender",    "name": "Cust Gender",    "formula": "Lookup([Customers/Cust Gender], [Cust Key], [Customers/Cust Key])" },
    { "id": "col-cus-age-group", "name": "Age Group",      "formula": "Lookup([Customers/Age Group], [Cust Key], [Customers/Cust Key])" },
    { "id": "col-cus-civil",     "name": "Civil Status",   "formula": "Lookup([Customers/Civil Status], [Cust Key], [Customers/Civil Status])" },
    { "id": "col-cus-loyalty",   "name": "Loyalty Program","formula": "Lookup([Customers/Loyalty Program], [Cust Key], [Customers/Cust Key])" }
  ]
}
```

Rules of thumb from the verified build:

- **Same-page requirement.** The lookup-source element (`Customers`)
  and the lookup-target element (`Cust Tx`) must live on the same
  page. Cross-page `Lookup()` fails silently at render.
- **Local key must be declared with `name`.** The `[Cust Key]` bare
  reference in the second argument resolves to a sibling column on
  the target element — so that column needs an explicit `name` field
  (or an auto-inferable single-qualified-ref formula).
- **Target key must be qualified.** The third argument uses
  `[<Source Element Name>/<Key Column>]` — a bare `[Cust Key]` here
  would resolve to the local key on the same element (infinite loop).
- **All downstream elements can source from the fact table.** Any
  chart, KPI, or control filter on the same page can reference the
  looked-up columns just like native fact columns — no additional
  `Lookup()` needed downstream.
- **Passthrough coverage still applies.** Include enough columns on
  the fact table so charts sourced from it don't fail
  `validate-spec.py`'s `passthrough-coverage` check.

## Per-row windowed aggregations — `Rollup`

`Rollup(<aggregate>, <partition-col>, <order-col>)` computes a
windowed aggregate that's broadcast to every row in the partition.

```
Rollup(Min([Date]), [Cust Key], [Date])
```

Returns the earliest `Date` per customer (the first-purchase date).
Canonical example: `examples/data-model-sourced-cohort-pivot.json`.

### Two Rollup traps

**Third argument must be a column reference, not a literal.**

```
Wrong: Rollup(Sum([Sales]), [Store Key], 1)     // literal → renders null
Right: Rollup(Sum([Sales]), [Store Key], [Row Month])
```

The order argument is used when the aggregation is order-dependent
(`RunningSum`, `Lead`, `Lag`). Even for order-independent aggregations
(`Sum`, `Avg`), pass any partition-relevant column — a literal is
rejected semantically and the value comes back null.

**Do NOT combine `Rollup()` with `groupings` on the same table.**

`groupings` already partitions the table at the group grain. Adding
`Rollup(..., <partition>, ...)` on top double-partitions and the
values collapse to null. Pattern to use instead — plain conditional
aggregation under `groupings.calculations`:

```json
"columns": [
  { "id": "current-rev",
    "formula": "Sum(If(DateTrunc(\"month\", [Date]) = DateTrunc(\"month\", Today()), [Sales], 0))" },
  { "id": "hist-total",
    "formula": "Sum(If(DateTrunc(\"month\", [Date]) < DateTrunc(\"month\", Today()), [Sales], 0))" },
  { "id": "hist-avg",
    "formula": "If([Historical Months] > 0, [Historical Total] / [Historical Months], Null)" }
],
"groupings": [{
  "id": "g-by-store",
  "groupBy": ["store-name", "store-region"],
  "calculations": ["current-rev", "hist-total", "hist-avg"]
}]
```

Sibling references between calculation columns (`[Historical Total] /
[Historical Months]`) work at the post-groupings grain — each group
has scalar values for both. Verified 2026-07-02 against
`exec-scorecard-v2` post-fix. Full pattern lives in the
`data-model-sourced-exec-kpi-scorecard.json` exemplar.

### Vs-historical-average recipe (anomaly detection)

To find stores/products whose recent behavior deviates from their own
historical average, use the pattern from
`data-model-sourced-exec-kpi-scorecard.json` (page 3, Store Monthly
derived table):

1. Two-tier source: raw fact table → per-dimension derived table with
   `groupings`.
2. Split "current" vs "historical" via `Sum(If(<date-partition>, ...))`
   pairs, plus a `Historical Months` count for the denominator.
3. Post-aggregation sibling refs for `Historical Avg`, `Deviation $`,
   `Deviation %`, `Abs Deviation %`.
4. Consumer table (chart, scatter) sources from the derived table and
   applies a `top-n` filter on `Abs Deviation %`.

`Rollup(Avg([Metric]), [Store], [Date])` is the ungrouped-table
alternative when the base table has no `groupings`, but you'll end up
with per-row broadcast values (one row per input) — usually messier
than the `groupings` pattern above.

## Window functions

| Function | Description |
|---|---|
| `Rank()` | Rank within partition |
| `RowNumber()` | Row number within partition |
| `Lead(<col>)` | Next row's value |
| `Lag(<col>)` | Previous row's value |
| `RunningSum(<col>)` | Cumulative sum |
| `RunningAvg(<col>)` | Cumulative average |

Window functions require pre-materialized columns in many cases —
see `examples/data-model-sourced-multi-level-aggregated-table.json`
for the pattern.

## Numeric guards

| Function | Description |
|---|---|
| `Coalesce(<a>, <b>, ...)` | First non-null value |
| `IsNull([col])` | True if null |
| `Zn(<x>)` | Returns 0 if `<x>` is null (safe-division companion) |
| `Null` | Null literal |
| `In([col], "a", "b", "c")` | True if value is in the list |

**Safe division pattern:**

```
If([denom] = 0, Null, [num] / [denom])
Zn([num] / [denom])
```

> ⚠️ `DivideSafe(<num>, <denom>)` does NOT exist in Sigma. This
> was a hallucination caught 2026-05-15 and removed from prior
> skill content. Use one of the patterns above. See
> `reference/history.md` → "2026-05-15."

## Looking up Sigma functions

When the function you need isn't in the table above, use the native
Sigma Docs MCP:

```
mcp__claude_ai_Sigma_Docs__search("<function name or topic>")
mcp__claude_ai_Sigma_Docs__fetch(<page-id>)
```

The search returns the Sigma help docs page for the function, which
includes the signature, parameter types, and examples. Faster than
`WebFetch` against `help.sigmacomputing.com`.

Fallback: `WebFetch` against `https://help.sigmacomputing.com/`
(function references) and
`https://help.sigmacomputing.com/reference/` (REST API endpoints).

## When the formula fails at render

If `scripts/api/verify-workbook.sh <wb-id>` reports `[FAIL]` on an
element:

1. **Bare warehouse ref** — `Sum([ORDER_TOTAL])` instead of
   `Sum([ORDERS/ORDER_TOTAL])`.
2. **Friendly-name mismatch** — formula uses raw warehouse name
   that Sigma normalized differently.
3. **Circular reference** — column references itself via name
   collision.
4. **Missing source element on page** — `Lookup()` target isn't
   placed in layout XML, so it doesn't exist at render.
5. **Boolean operator as function call** — `Not(...)` instead of
   `Not (...)`.

See `reference/workflows/validate.md` → "Post-create — verify-workbook.sh"
for the triage flow.
