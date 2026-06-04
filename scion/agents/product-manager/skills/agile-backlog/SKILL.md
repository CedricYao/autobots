---
name: agile-backlog
description: >-
  Agile backlog management for agent-native development: contract-first stories,
  vertical slice ordering, sign-off by test results, and sprint planning based
  on verification state rather than activity metrics.
---

# Agile Backlog (Agent-Native)

## Story Format

```markdown
## Story: [Verb] [capability]

**Hypothesis:** [What we believe and why]

### Contract
- Endpoint: [HTTP method + path]
- Spec: openapi.yaml § [path reference]

### CLI
$ [command] → [expected output]

### Tests
- [pytest path::test_name] — [what it proves]
- [CLI command] → [expected result]

### Done When
- [ ] Contract test passes against deployed service
- [ ] CLI produces correct output
- [ ] Real-data assertions pass
```

## INVEST Criteria (Updated)

| Criterion | Agent-Native Meaning |
|-----------|---------------------|
| **Independent** | Each story is a self-contained vertical slice |
| **Negotiable** | Contract shape is negotiable; that it has a contract is not |
| **Valuable** | Story delivers a working endpoint + CLI, not just a layer |
| **Estimable** | Estimate based on contract complexity, not UI complexity |
| **Small** | One endpoint, one contract test, one CLI command |
| **Testable** | Has executable acceptance criteria (pytest + CLI) |

## Backlog Structure

```markdown
## Current Sprint (Vertical Slices)
- [ ] Story 1: Probe endpoint (walking skeleton) — spec → test → implement → CLI → deploy
- [ ] Story 2: Interview endpoint — spec → test → implement → CLI → deploy

## Next Sprint
- [ ] Story 3: Report endpoint
- [ ] Story 4: Scaffold UI from generated types
- [ ] Story 5: Polish UI with design

## Unprioritized
- [ ] Additional probe domains
- [ ] Export to PDF

## Icebox (YAGNI until validated)
- [ ] Multi-project comparison
- [ ] Historical trend analysis
```

## Sprint Planning

### Capacity

Sprint capacity is measured in vertical slices, not story points:

- **Full slice (spec → test → implement → CLI → deploy):** ~2 hours
- **Expand slice (add more endpoints to proven pattern):** ~1 hour per endpoint
- **UI scaffold (from generated types):** ~2 hours
- **UI polish (design refinement):** ~2-4 hours

### Sprint Goal

The sprint goal is a verification statement:

```
Sprint Goal: "Contract tests pass for probe and interview endpoints
against the deployed service. CLI produces correct output for both."
```

Not: "Complete 15 story points across 8 stories."

## Definition of Done

- [ ] OpenAPI spec entry exists for the endpoint
- [ ] Contract test passes against deployed service (not localhost, not stubs)
- [ ] CLI command exercises the endpoint and produces correct output
- [ ] Real-data assertions confirm data is from real infrastructure
- [ ] Error cases return proper status codes
- [ ] (If UI exists) Playwright smoke test passes

## Sign-Off

| Signal | Meaningful? |
|--------|-------------|
| "8/8 stories complete" | **No** |
| "All tests pass" (against stubs) | **No** |
| **"Contract tests pass against production"** | **Yes** |
| **"CLI produces correct output"** | **Yes** |
| **"Stakeholder ran the CLI and confirmed output"** | **Yes** |
