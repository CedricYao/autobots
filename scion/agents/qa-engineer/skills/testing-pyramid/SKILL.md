---
name: testing-pyramid
description: >-
  Agent-native verification pyramid: OpenAPI spec at base, contract tests,
  CLI tests, integration tests, then UI tests at top. Ratios, what belongs
  where, anti-patterns (inverted pyramid, stub system).
---

# Verification Pyramid

## The Agent-Native Pyramid

The pyramid is reordered for agent-native development. The base is the spec, not unit tests. Contract tests replace mocked unit tests as the primary verification layer.

```
                    /\
                   /  \
                  / UI \          ← Playwright: "Does it look right?"
                 / Tests \            Few — deployment checkpoints only
                /----------\
               / CLI Tests  \     ← CLI verification: "Does the flow work?"
              /              \        After every merge batch
             /----------------\
            / Contract Tests   \  ← pytest + schemathesis: "Does the API match the spec?"
           /   (against real    \     On every merge — PRIMARY VERIFICATION
          /     infrastructure)  \
         /------------------------\
        / OpenAPI Spec + Types     \← Type checking: "Is the contract consistent?"
       /                            \   On every commit
      /------------------------------\
```

## Layer Details

### Base: OpenAPI Spec + Type Checking (Every Commit)

The spec is the foundation. If it doesn't compile and type-check, nothing above it matters.

- OpenAPI spec validates with `openapi-generator validate`
- Pydantic/Zod models match the spec schemas
- Generated TypeScript types compile

### Contract Tests (Every Merge — PRIMARY)

**This is the most important layer.** Contract tests hit the real deployed service and validate responses against the OpenAPI schema.

- Run via `pytest tests/contracts/` against `$API_URL`
- Response shapes validated with `jsonschema.validate()`
- Real-data assertions: `assert len(findings) > 0`
- Error cases: invalid input → 400, unauthorized → 403

**Ratio:** 40-50% of all tests should be contract tests.

### CLI Tests (Every Merge)

CLI commands exercise the same endpoints and verify output format.

- Happy path: command exits 0, output is valid
- Error path: command exits 1, stderr has clear message
- Consistency: CLI output matches API output

**Ratio:** 15-20% of tests.

### Integration Tests (Every Merge)

Component boundary tests — database queries, service-to-service calls.

- Hit real databases with test data
- No in-memory stubs at this layer

**Ratio:** 15-20% of tests.

### Unit Tests (Every Commit)

Pure logic tests — calculations, validators, formatters. Mocks are permitted here.

**Ratio:** 10-15% of tests.

### UI / Playwright Tests (Deployment Checkpoints)

Visual verification — routes render, forms submit, navigation works.

- Run against deployed URL with real data
- Happy path + error path per route
- Secondary to contract and CLI verification

**Ratio:** 5-10% of tests.

## Anti-Patterns

### The Stub System

2,600 tests pass. All use in-memory stores. The deployed service returns 502. Nobody notices for 10 hours.

**Fix:** Contract tests hit the real deployed service. `assert len(data["findings"]) > 0` catches stubs.

### The Inverted Pyramid

Most tests are Playwright. CI takes 30 minutes. Tests fail randomly. Teams avoid running tests locally.

**Fix:** Push 80% of assertions down to contract and CLI tests. Playwright catches only visual bugs.

### The Mock Boundary

Tests mock the exact boundary they should verify. `mock_gcp.return_value = fake_data` tests the mock, not the system.

**Fix:** At least one test per endpoint hits real infrastructure.

### Activity as Completion

"94/94 stories complete, 2,600 tests pass" — but nobody ran them against the deployed service.

**Fix:** "Done" = contract tests pass against the production URL.
