---
name: project-communication
description: >-
  Write clear progress summaries and stakeholder updates. Use when sending project
  status updates via scion message, composing milestone announcements, or framing
  project work for external audiences.
---

# Project Communication

Write progress summaries that make the team's work legible to stakeholders.

## Progress Summary Structure

```
[PROJECT UPDATE] — [Date]

**Headline:** [One sentence: the most important thing that happened]

**Accomplished:**
[2-3 paragraphs describing what was built/completed, framed as capabilities gained, not tasks checked off]

**Key Artifacts:**
- [Artifact name](link) — one-line description
- [Artifact name](link) — one-line description

**Current Status:** [One paragraph: where the project stands right now]

**Next:** [One paragraph: what's coming next]
```

## Writing Principles

### Lead with outcomes
Bad: "Created 8 YAML configuration files for agent templates."
Good: "The SRE team is operational — 8 specialized agents can now autonomously detect, diagnose, and remediate three classes of production failure."

### Be concrete and specific
Bad: "Made good progress on the infrastructure."
Good: "Published an SRE capability assessment scoring the environment at 310/700 mana (Silver tier), with metrics and logging as strengths and deployment automation as the critical gap."

### Frame as capability, not activity
Bad: "The designer agent was created and tested."
Good: "The team can now generate functional HTML/CSS prototypes directly from product requirements — no design tools needed."

### Acknowledge gaps honestly
Bad: (omit problems)
Good: "Alert notification channels remain unconfigured. The SRE agents can diagnose incidents but must be triggered manually until Pub/Sub or webhook channels are set up."

### Keep it brief
- Headline: 1 sentence
- Accomplished: 2-3 paragraphs
- Artifacts: 3-5 items maximum (highlight the most important)
- Status + Next: 1 paragraph each
- Total: fits on one screen

## What to Include

- **Milestones reached** — new capabilities, templates deployed, systems operational
- **Artifacts published** — with links so stakeholders can go look
- **Team wins** — clever solutions, surprising discoveries, things that went well
- **Blockers and gaps** — honest status on what's not working yet
- **Direction** — where the project is heading next

## What to Skip

- Internal implementation details (template file structures, YAML config, CLI commands)
- Agent-to-agent communication details
- Debugging sessions or false starts (unless the discovery was significant)
- Exhaustive lists — curate the top 3-5, not all 20
- Technical jargon without translation

## Stakeholder Update Delivery

Send updates via scion message to the coordinator:

```bash
scion message coordinator --non-interactive "[PROJECT UPDATE] — YYYY-MM-DD

**Headline:** ...

**Accomplished:**
...

**Key Artifacts:**
- ...

**Current Status:** ...

**Next:** ..."
```

The coordinator relays to the appropriate stakeholders. Do not message stakeholders directly unless explicitly instructed to.

## Milestone Announcements

For particularly significant events (major feature complete, first incident response, public demo ready), send a shorter, punchier announcement:

```
[MILESTONE] — [Date]

[2-3 sentences: what was achieved and why it matters]

See: [link to artifact or index page]
```
