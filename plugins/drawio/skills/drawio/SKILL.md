---
name: drawio
description: Use when the user asks to create or edit diagrams, flowcharts, architecture diagrams, sequence diagrams, ER diagrams, org charts, or mentions draw.io/diagrams.net.
---

# draw.io Skill

Use draw.io MCP tools to open diagrams directly in draw.io:

1. Use `open_drawio_mermaid` when the request is naturally Mermaid.
2. Use `open_drawio_csv` for org charts or tabular diagram definitions.
3. Use `open_drawio_xml` for detailed, custom draw.io XML diagrams.

Prefer the MCP tools over plain text diagram output when draw.io editing is expected.
