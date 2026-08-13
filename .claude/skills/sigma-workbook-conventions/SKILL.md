---
name: sigma-workbook-conventions
description: >-
  Use when authoring, editing, reviewing, or publishing any Sigma workbook
  or dashboard JSON spec in this repo — including whenever the user says
  "start build mode", mentions Sigma workbooks, dashboards, or specs, asks
  to build/edit/POST/PUT a workbook, references data models, KPIs, charts,
  tables, controls, layouts, filters, maps, or the `/v2/workbooks/spec`
  endpoint. Encodes project conventions on element naming, page/folder
  layout, ID semantics on POST/PUT, secret handling, and common pitfalls
  when generating Sigma JSON specs. Pair with `sigma-data-models` for
  field-level reference, and with a domain-specific workbook-pattern
  skill when one is available for the dashboard type being built.
---

# Sigma Workbook Conventions (this-repo pointer)

The full skill now lives at `skills/sigma-workbook-conventions/SKILL.md` — the
canonical, marketplace-publishable copy (see `.claude-plugin/plugin.json`).
This stub exists only so `.claude/skills/` auto-discovery keeps triggering
"start build mode" in this checkout.

**Read `skills/sigma-workbook-conventions/SKILL.md` now and follow it exactly.**
Wherever it says `${CLAUDE_PLUGIN_ROOT}`, use this repo's root — this checkout
is not an installed plugin, it *is* the plugin source.
