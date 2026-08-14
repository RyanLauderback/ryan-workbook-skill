# Column formats

Column-level `format` object + the d3-format / strftime conventions
Sigma uses.

```bash
jq '.components.schemas.Format' /tmp/sigma-api.json
```

`format` is optional on every column — omit it for raw values. This
file is mainly the cheat sheet of common format strings (currency,
percentages, dates) since the OpenAPI doesn't enumerate them.

## Number formats

```json
{
  "kind": "number",
  "formatString": "$,.0f"
}
```

Common format strings (d3-format conventions):

| String | Example output | Description |
|---|---|---|
| `"$,.0f"` | `$1,234` | Currency, no decimals |
| `"$,.2f"` | `$1,234.56` | Currency, 2 decimals |
| `",.0f"` | `1,234` | Integer with thousands separator |
| `",.2f"` | `1,234.56` | Number, 2 decimals |
| `",.2%"` | `12.34%` | Percentage, 2 decimals |
| `".3~e"` | `1.23e+3` | Scientific, 3 significant digits |
| `"$.2~S"` | `$1.2M` | D3 SI prefix (verified 2026-05-19) |

Format-string cheat sheet:

- `$` — currency prefix
- `,` — thousands separator
- `.<n>f` — fixed decimal places
- `.<n>%` — percent with decimals (value × 100)
- `.<n>~e` — scientific with trimmed trailing zeros
- `~S` — SI prefix (K/M/B abbreviation) with trimmed trailing zeros

### Currency-specific richer shape

For currency, Sigma's `format` object can carry additional siblings
discovered 2026-05-19:

```json
{
  "kind": "number",
  "formatString": "$.2~S",
  "decimalSymbol": ".",
  "digitGroupingSymbol": ",",
  "digitGroupingSize": 3,
  "currencySymbol": "$"
}
```

These sibling fields are optional; `formatString` alone is sufficient
for most cases. See `reference/history.md` → "2026-05-18 — Column
`format` shape discovered" for the verification history.

## Datetime formats

```json
{
  "kind": "datetime",
  "formatString": "%b %Y"
}
```

Common format strings (strftime conventions):

| String | Example output | Description |
|---|---|---|
| `"%Y-%m-%d"` | `2026-04-21` | ISO date |
| `"%b %Y"` | `Apr 2026` | Short month + year |
| `"%B %Y"` | `April 2026` | Full month + year |
| `"%Y-%m-%d %H:%M"` | `2026-04-21 14:30` | ISO datetime |
| `"%a, %b %-d"` | `Tue, Apr 21` | Short day + month + day (no zero pad) |

Tokens:

- `%Y` — 4-digit year · `%y` — 2-digit year
- `%m` — month number (01–12) · `%-m` — unpadded · `%b` — short
  name · `%B` — full name
- `%d` — day of month · `%-d` — unpadded
- `%H` / `%I` — 24h / 12h hour · `%M` — minutes · `%S` — seconds
- `%a` / `%A` — short / full weekday

## Where format goes

Inline on any column:

```json
{
  "id": "col-sales",
  "name": "Sales",
  "formula": "Sum([Master/Sales Amount])",
  "format": {
    "kind": "number",
    "formatString": "$,.0f"
  }
}
```

KPI tiles, table columns, axis labels, chart values — all honor the
`format` field on the column they reference.

## When format doesn't propagate

If a KPI inheriting `[Metrics/Revenue]` shows `12345.67` instead of
`$12,345.67`, the format didn't propagate from the data-model metric.
Two fixes:

1. **Add explicit `format` on the column** that wraps `[Metrics/Revenue]`.
2. **Update the data-model metric** to include the format (preferred
   when the metric should be formatted everywhere it's referenced).

See `reference/conventions.md` → "`[Metrics/<Name>]` resolution" for
when to rely on data-model metric formatting vs. column-level overrides.
