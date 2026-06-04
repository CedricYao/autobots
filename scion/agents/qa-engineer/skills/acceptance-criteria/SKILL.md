---
name: acceptance-criteria
description: >-
  Acceptance criteria as executable tests and CLI commands, not prose.
  Contract-first AC writing, testability via API specs, and how ACs
  map to contract tests and CLI verification commands.
---

# Acceptance Criteria

## The Agent-Native Shift

Acceptance criteria are executable commands, not prose descriptions. The story IS the test.

### Old (Prose ACs)

```gherkin
Scenario: Successful discovery probe
  Given a valid GCP project "boutique-demo-22"
  When the user runs a logging discovery probe
  Then the system returns a score between 0 and 100
  And the system lists at least one finding
```

### New (Executable ACs)

```bash
# AC 1: Contract test passes against deployed service
$ pytest test_contracts/test_probe.py::test_logging_probe_returns_valid_response -v
PASSED

# AC 2: CLI produces correct output
$ sre-discover probe boutique-demo-22 --domain logging --format json | jq '.score'
45

# AC 3: Error handling works
$ sre-discover probe INVALID_PROJECT --domain logging 2>&1
Error: Project "INVALID_PROJECT" not found or insufficient permissions (exit code 1)

# AC 4: Response matches OpenAPI contract
$ schemathesis run openapi.yaml --base-url $API_URL --endpoint /api/v1/discovery/probe
All checks passed!
```

## Writing Executable ACs

### For Every Story, Define:

1. **The contract test** — what pytest assertion proves this story works?
2. **The CLI command** — what command can a human or agent run to verify?
3. **The error cases** — what happens with bad input, missing auth, timeout?

### Format

```markdown
## Story: Run a discovery probe against a GCP project

### Contract Tests (pytest)
- `test_probe_returns_200_with_valid_project` — POST /probe with real project → 200
- `test_probe_returns_real_gcp_data` — response contains findings from real GCP APIs
- `test_probe_returns_400_for_invalid_project` — POST /probe with bad project → 400
- `test_probe_response_matches_openapi_schema` — response validates against ProbeResult schema

### CLI Verification
- `sre-discover probe boutique-demo-22 --domain logging` → exits 0, shows score and findings
- `sre-discover probe boutique-demo-22 --domain logging --format json` → valid JSON matching ProbeResult
- `sre-discover probe INVALID --domain logging` → exits 1, shows error message

### "Done" Criteria
- All contract tests pass against the deployed service URL (not localhost)
- CLI produces correct output for all commands above
- UI rendering (if applicable) shows the same data the CLI shows
```

## Testability Checklist

Before accepting a story as ready for development:

- [ ] **Has an API contract:** OpenAPI spec defines the endpoint, request/response schemas, and error codes
- [ ] **Has contract tests:** Failing pytest tests exist that will pass when the endpoint is implemented
- [ ] **Has CLI verification:** A CLI command that exercises the endpoint is defined
- [ ] **Has real-data assertions:** At least one test asserts the data comes from real infrastructure
- [ ] **Has error cases:** Invalid input, missing auth, and timeout scenarios are specified

If any answer is "no," the story is not ready for development.

## AC Anti-Patterns

### The Prose Story

```
AC: The system should display results in a user-friendly manner
```
Fix: What CLI command produces the output? What does the JSON look like?

### The UI-First AC

```
AC: The sidebar shows a drill-down accordion with domain scores
```
Fix: What API endpoint returns the domain scores? Write that contract test first. The sidebar is Phase 4.

### The Stub-Accepting AC

```
AC: The endpoint returns a score (any value is acceptable for MVP)
```
Fix: The score must come from real GCP data. `assert data["score"] > 0` and `assert len(data["findings"]) > 0`.

### The Activity AC

```
AC: 94/94 stories complete, all tests pass
```
Fix: "All contract tests pass against the deployed production URL."
