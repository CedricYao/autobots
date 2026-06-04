---
name: gherkin
description: >-
  Contract-first story writing: API contracts as story definitions, executable
  acceptance criteria via CLI commands and pytest, and mapping stories to
  vertical slices. Gherkin format adapted for agent-native development.
---

# Contract-First Story Writing

## Stories Defined by API Contracts

In agent-native development, stories are defined by the API contract, not prose descriptions or UI mockups.

### Story Format

```markdown
## Story: [Capability Name]

**Hypothesis:** [What we believe users need and why]

### API Contract
- **Endpoint:** POST /api/v1/discovery/probe
- **Request:** { project_id: string, domain: enum[logging|monitoring|trace] }
- **Response:** { score: int, findings: Finding[], gaps: Gap[] }
- **Errors:** 400 (invalid domain), 403 (no permissions), 504 (timeout)
- **Full spec:** See openapi.yaml § paths./api/v1/discovery/probe

### CLI Usage
$ sre-discover probe boutique-demo-22 --domain logging
Score: 45/100 (Logging domain)
Findings: 5
Gaps: 3

$ sre-discover probe boutique-demo-22 --domain logging --format json | jq '.score'
45

### Acceptance (Executable)
- `pytest tests/contracts/test_probe.py::test_returns_200` — passes against deployed service
- `pytest tests/contracts/test_probe.py::test_returns_real_data` — findings.length > 0
- `pytest tests/contracts/test_probe.py::test_rejects_invalid_domain` — returns 400
- `sre-discover probe boutique-demo-22 --domain logging | jq '.score'` → integer 0-100
- `sre-discover probe INVALID --domain logging` → exit code 1

### "Done"
- [ ] Contract test passes against deployed service (not localhost)
- [ ] CLI produces correct output
- [ ] Real-data assertions pass
```

### Why Not Traditional Gherkin?

Traditional Gherkin is prose:
```gherkin
Scenario: User sees logging score
  Given a valid GCP project
  When the user runs a logging discovery
  Then the system shows a score between 0 and 100
```

This has multiple valid implementations. An agent might implement it with stub data, or with a different response shape, or with the wrong endpoint path. The contract-first format eliminates ambiguity:

```
Endpoint: POST /api/v1/discovery/probe
Request: { project_id: "boutique-demo-22", domain: "logging" }
Response: { score: 45, findings: [...], gaps: [...] }
Test: pytest tests/contracts/test_probe.py::test_returns_200
```

Zero ambiguity. The test IS the acceptance criterion.

## Story Ordering: Vertical Slices

Stories are ordered as vertical slices, not horizontal layers:

```
# Good: each story is end-to-end
Story 1: Probe endpoint (walking skeleton)
  → OpenAPI spec → contract test → implement → CLI → deploy → verify

Story 2: Interview endpoint
  → OpenAPI spec → contract test → implement → CLI → deploy → verify

Story 3: Report endpoint
  → OpenAPI spec → contract test → implement → CLI → deploy → verify

Story 4: Scaffold UI from API types
  → Generate types → build views → wire to API → Playwright smoke test

Story 5: Polish UI
  → Designer directs visual improvements on working scaffold

# Bad: horizontal layers
Story 1: Create all database schemas
Story 2: Build all API endpoints
Story 3: Write all tests
Story 4: Build all frontend components
Story 5: Wire up frontend
```

## Acceptance Criteria as Executable Commands

Every AC is a command that can be run by an agent:

| Prose AC (Old) | Executable AC (New) |
|----------------|---------------------|
| "Score should be valid" | `jq '.score' \| test(". >= 0 and . <= 100")` |
| "Should handle errors gracefully" | `curl -s -o /dev/null -w '%{http_code}' POST /probe -d '{"domain":"fake"}'` → `400` |
| "Should return findings" | `pytest test_probe::test_returns_real_data` → PASS |
| "Should work in production" | `API_URL=$PROD_URL pytest tests/contracts/` → all PASS |

## No Stories Without Contracts

**Rule:** If the API endpoint doesn't exist in the OpenAPI spec and have a contract test, don't write a story for its UI behavior. UI stories are premature without a proven backend.

Stories that violate this rule:
- "Display accordion drill-down for domain scores" (no API returns domain breakdown)
- "Show recommendation cards with priority badges" (no API returns recommendations with priorities)
- "Animate the mana score gauge" (no API returns a mana score)

## PRD Caps at 400 Lines

The PRD captures product intent. API behavior lives in the OpenAPI spec:

| Content | Where It Lives |
|---------|---------------|
| Problem statement, hypothesis, user needs | PRD (≤400 lines) |
| Endpoint paths, request/response schemas | openapi.yaml |
| Validation rules, error codes | openapi.yaml |
| CLI command interface | PRD CLI section |
| Data shapes, field types | openapi.yaml components |
| Visual design, UI layout | Designer handoff (Phase 5) |
