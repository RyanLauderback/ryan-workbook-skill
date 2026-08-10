# `input-table-agent-scenario-planner.json` — design intent

Canonical **editable / writeback + agent surface** exemplar. Source: this
skill's own Wave 3 / C5+C6 probe (2026-08-04, `b7fead6d-504e-48e7-
b623-e41576ce8eb5`, "Claude Testing" folder) — every element shape here
is live-POST verified, not GET-spec-only. See
`reference/history.md` → "2026-08-04 — Wave 3 / C5+C6" for the full
probe narrative and `reference/capability-ledger.md` for the dated
evidence rows.

## When to clone this exemplar

Any build where the user wants to:
- Let users type/track structured data directly in the workbook
  (scenarios, forecasts, approvals, notes) rather than just view it.
- Let an AI agent write to that same editable state on the user's
  behalf, in addition to (not instead of) manual entry via buttons.

## What it demonstrates

- **All 6 input-table column shapes** in one table: system
  (`ID`/`CREATED_AT`/`CREATED_BY`/`UPDATED_AT`/`UPDATED_BY`), editable
  text/number/datetime/checkbox, dropdown (`values`+`pills`), and a
  formula column that references a sibling editable column by name.
- **Writeback via buttons** — `insert-rows` with constant values,
  `delete-rows` with a formula `whichRows` filter. This example itself
  only demonstrates those two; it predates `update-rows` being
  confirmed as a real effect (targeted single-row update by primary
  key — see `reference/specification/actions.md` →
  "`insert-rows` / `delete-rows` / `update-rows`"), so there's no
  "clear form" or "edit row" pattern here — "delete + re-add" is the
  only mutation primitive demonstrated beyond a fresh insert. **Future
  enhancement (not yet built):** add a tool step or button
  demonstrating `update-rows` directly on this exemplar's
  `input-tbl-scenarios` table (e.g. an approve/edit-in-place flow) so
  this becomes the canonical `update-rows` reference too, not just
  `insert-rows`/`delete-rows`.
- **Writeback via an agent tool** — the same input-table, written to
  by `agent-scenario`'s one tool, using `agent-input` values so the
  model supplies `scenarioName`/`forecastValue` from natural-language
  conversation instead of a fixed constant.
- **`{{formula}}` interpolation in agent instructions** — the agent's
  system prompt reflects the page's live control state
  (`{{[ctrl-region]}}`), so its answers can be region-aware without a
  second copy of the filter logic.

## Do NOT clone this if

- The ask is a read-only dashboard with no editable state — see
  `dashboard-department-scorecard.json` instead.
- The input table needs a `linked` source bound to an existing
  workbook table (this exemplar uses `empty` for simplicity) — see
  `reference/specification/input-tables.md` → "linked" for that shape;
  the probe workbook itself has a `linked` variant not carried into
  this exemplar to keep it focused.

## Placeholders to resolve before POSTing

- `folderId` — destination folder.
- `input-tbl-scenarios.source.connectionId` — any real connection ID
  works for an `empty`-source input table; it doesn't need to point at
  a table with existing data.
