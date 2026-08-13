# AI agents (`agents[]` + `chat` element)

New 2026-08-04 (Wave 3 / C6). `agents` is a **top-level sibling of
`pages`**, not an element — different ID lifecycle, different
round-trip behavior than anything in `specification/` so far, and the
only **non-deterministic execution path in the spec**: an LLM chooses
which tool fires at runtime, not the author.

**Every shape below is live-POST verified** (`workbookId:
b7fead6d-504e-48e7-b623-e41576ce8eb5`, "Claude Testing" folder) — a
correction over the prior status, where `agents[]` + `chat` were
GET-spec (read) confirmation only across 4 harvested production
workbooks. Authored from scratch and round-tripped byte-for-byte
through POST → GET, including a full agent-tool write to a real
input-table.

```bash
jq '.components.schemas.Agent, .components.schemas.AgentTool' /tmp/sigma-api.json
```

## Top-level `agents[]`

```json
{
  "agents": [
    {
      "id": "agent-scenario",
      "name": "Scenario Assistant",
      "instructions": "Help the user manage revenue scenarios. Current region filter: {{[ctrl-region]}}",
      "dataSources": [
        { "kind": "table", "elementId": "input-tbl-scenarios" }
      ],
      "tools": [ /* see below */ ]
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique across the spec — referenced by `chat.agentId` |
| `name` | yes | Display name |
| `instructions` | yes | System-prompt-style text. Supports `{{formula}}` string interpolation — see `dynamic-values.md`. **Live-POST verified**: a bare `{{[controlId]}}` reference round-tripped unchanged. |
| `dataSources` | yes (for the agent to see any data) | Array of `{kind:"table", elementId}` — the tables the agent can query. **Live-POST verified.** |
| `tools` | no | Array — see "Tools" below. An agent with no `tools` is a read-only conversational analyst. |

## `chat` element

Surfaces an agent as a conversational UI element on a page:

```json
{
  "id": "chat-scenario-agent",
  "kind": "chat",
  "agentId": "agent-scenario"
}
```

`agentId` references an `agents[].id`. **Live-POST verified** — placed
via ordinary `<Element>` like any other element.
`validate-spec.py`'s `action-refs-resolve` check verifies `agentId`
resolves to a real agent (added this wave — a dangling `agentId`
previously failed silently: POST succeeds, the chat element renders
with no agent attached).

## Tools — agent tools reuse the C3 effect vocabulary

```json
{
  "toolId": "tool-add-scenario",
  "kind": "action",
  "name": "Add Scenario",
  "description": "Adds a new scenario row with a model-supplied name and forecast value.",
  "steps": [
    {
      "kind": "effect",
      "effect": "insert-rows",
      "table": "input-tbl-scenarios",
      "values": {
        "col-name": { "type": "agent-input", "inputName": "scenarioName" },
        "col-forecast": { "type": "agent-input", "inputName": "forecastValue" },
        "col-status": { "type": "constant", "value": { "type": "text", "value": "Draft" } }
      }
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `toolId` | yes | Unique within the agent's `tools[]` |
| `kind` | yes | Always `"action"` |
| `name` | yes | Shown to the model as the tool name |
| `description` | yes | Shown to the model — this is what it reads to decide when to call the tool |
| `steps` | yes | Array of effect objects |

**Each step is shaped exactly like a button's effect object, with one
added sibling key: `kind:"effect"`.** Confirmed live-POST: the
`insert-rows` step above round-tripped with the identical `effect`/
`table`/`values` fields a button's action would carry, plus `kind`.
This means every effect in `actions.md` (`set-control-value`,
`clear-control`, `open-overlay`, `navigate`, `select-tab`,
`insert-rows`, `delete-rows`, `open-url`, `close-overlay`) is a
candidate tool step — only `insert-rows`/`delete-rows` were
independently probed this wave, but the shape symmetry with buttons is
now proven, not assumed. `validate-spec.py`'s `action-refs-resolve`
check walks `agents[].tools[].steps[]` with the same referential checks
it applies to `actions[].effects[]` (added this wave).

### `agent-input` — the model-supplied dynamic value

`{type: "agent-input", inputName: "<name>"}` is a dynamic-value form
scoped to agent tool steps — the model supplies the actual value at
call time, based on `inputName` and the tool's `description`. **Live-
POST verified this wave** (previously GET-spec/harvest evidence only —
see `dynamic-values.md`). Used above for `col-name`/`col-forecast` so
the model decides what to write; `col-status` uses an ordinary
`{type:"constant"}` value instead, since that field's value shouldn't
vary per call.

## `{{formula}}` interpolation in `instructions`

Same string-interpolation mechanism as element titles, `text` element
bodies, and image URLs (see `dynamic-values.md`) — embeds a live
control value or formula result inside otherwise-static instruction
text: `"Current region filter: {{[ctrl-region]}}"`. **Live-POST
verified** — round-tripped byte-for-byte, same as the Wave 2 modal-
header-title probe.

## What's still unverified

- `inputMode: "edit"`, `type: "file"` editable columns, and the
  `linked` input-table's full end-to-end writeback (this wave probed
  `linked` as a data source, not writeback into a linked table) —
  see `input-tables.md`.
- Whether tool steps support the full 9-effect vocabulary or only the
  writeback pair — only `insert-rows` was independently probed as a
  tool step this wave.
- Multiple tools on one agent, and multi-step tools (`steps` with more
  than one entry) — the probe used one tool with one step.
- Whether a `chat` element can appear more than once per agent, or an
  agent can be referenced by more than one `chat` element.

## Cross-references

- `input-tables.md` — the writeback target for agent tools.
- `actions.md` — the full effect vocabulary agent tool steps reuse.
- `dynamic-values.md` — the `agent-input` form and `{{formula}}`
  interpolation.
