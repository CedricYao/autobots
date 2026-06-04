---
name: chronicling
description: >-
  How to write effective project diary entries that capture decisions, discoveries,
  patterns, and artifacts in narrative prose. Use when appending to the project diary
  or synthesizing recent events into a larger narrative.
---

# Chronicling

Write diary entries that serve as the project's institutional memory.

## Entry Structure

Every diary entry has these parts:

### Timestamp and Title
```markdown
## [YYYY-MM-DD HH:MM UTC] — [Title]
```
The title should be descriptive and evocative — not "Update" or "Progress", but "The SRE Team Takes Shape" or "A Surprise in the Trace Data." Titles should make someone scanning the diary want to read the entry.

### Narrative Body
2-5 paragraphs of prose. Start with what happened, then explain why it matters, then connect it to the broader project arc.

Good structure for a single entry:
1. **The event:** What happened, in concrete terms
2. **The context:** Why this work was being done, what prompted it
3. **The interesting part:** What was surprising, clever, challenging, or revealing
4. **The connection:** How this relates to other work, what it enables next

### Artifacts (optional)
List any files, documents, templates, or outputs that were produced:
```markdown
**Artifacts:**
- `/path/to/file.md` — what this artifact is
- `.scion/templates/agent-name/` — what this template does
```

### Key Insight (optional)
A single sentence distilling the most important takeaway — the thing a skimmer should not miss:
```markdown
**Key insight:** The environment's strongest asset is its logging (85/85 mana) but its Achilles' heel is the complete absence of alert notification channels.
```

## What to Chronicle

### Always capture:
- **Decisions and their rationale** — "We chose X over Y because Z." Future readers will wonder why.
- **Discoveries** — unexpected findings, things that changed the team's understanding
- **New capabilities** — agent templates created, skills added, tools configured
- **Artifacts published** — reports, prototypes, specs, data exports
- **Patterns noticed** — recurring themes, emergent structures, connections between separate workstreams
- **Pivots** — when the direction changed and why
- **Constraints encountered** — blockers, limitations, workarounds

### Skip:
- Routine status updates with no insight ("Agent X completed task Y")
- Mechanical details of how commands were run
- Verbatim reproduction of agent output — summarize and cite instead
- Speculation without basis — only chronicle what actually happened or was decided

## Writing Style

### Do:
- Write in past tense for events, present tense for ongoing states
- Use active voice: "The metrics analyst discovered" not "It was discovered by"
- Be specific: name agents, templates, files, services, metrics
- Vary sentence length — mix short declarative sentences with longer explanatory ones
- Use paragraph breaks generously — dense blocks of text discourage reading

### Don't:
- Use bullet lists as the primary format — those belong in reports, not diaries
- Write in the second person ("you should note that...")
- Use jargon without context — the diary should be readable by someone new to the project
- Pad entries to seem substantial — a short, sharp entry is better than a long, diluted one

## Synthesis Entries

Every 3-5 regular entries, write a synthesis entry. This is a step-back reflection that weaves recent events into a larger narrative:

```markdown
## [YYYY-MM-DD HH:MM UTC] — Synthesis: [Theme]

[2-3 paragraphs connecting recent entries into a coherent arc. What patterns are emerging? What's the project's trajectory? What questions remain open?]
```

Synthesis entries are where the chronicler adds the most value — they surface connections that no individual agent would notice because each only sees its own work.

## Diary Maintenance

- The diary file grows over the life of the project — never delete or overwrite entries
- If an earlier entry turns out to be wrong, add a correction in a new entry rather than editing the old one
- If the diary exceeds ~200 entries, consider splitting into volumes: `project-diary-vol1.md`, `project-diary-vol2.md`
- The diary lives at `/scion-volumes/scratchpad/project-diary.md` — this is a shared volume accessible to all agents
