---
name: contract-tests
description: >-
  OpenAPI contract design, schemathesis/pytest validation against deployed
  services, walking skeleton pattern (spec + test + CLI), vertical slice
  verification, and real-data assertions. The architect's primary deliverable.
---

# Contract-First Architecture

## The Walking Skeleton

The architect's first deliverable. One OpenAPI spec → one passing contract test → one working CLI command → deployed service.

### Layer 1: The Spec (10 minutes)

```yaml
# openapi.yaml — the walking skeleton contract
openapi: 3.1.0
info:
  title: My Service API
  version: 0.1.0

paths:
  /api/v1/discovery/probe:
    post:
      operationId: runProbe
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [project_id, domain]
              properties:
                project_id:
                  type: string
                domain:
                  type: string
                  enum: [logging, monitoring, trace]
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ProbeResult'
        '400':
          description: Invalid request
        '403':
          description: Insufficient permissions

components:
  schemas:
    ProbeResult:
      type: object
      required: [domain, score, findings, gaps]
      properties:
        domain: { type: string }
        score: { type: integer, minimum: 0, maximum: 100 }
        findings:
          type: array
          items:
            $ref: '#/components/schemas/Finding'
        gaps:
          type: array
          items:
            $ref: '#/components/schemas/Gap'
```

~80 lines replaces hundreds of lines of PRD prose. Directly executable.

### Layer 2: The Contract Test (20 minutes)

```python
def test_probe_returns_valid_response(api_url, openapi_spec):
    response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
        "project_id": "boutique-demo-22", "domain": "logging"
    })
    assert response.status_code == 200
    data = response.json()
    schema = openapi_spec["components"]["schemas"]["ProbeResult"]
    jsonschema.validate(data, schema)
    assert data["score"] > 0, "Score is 0 — likely stub data"
    assert len(data["findings"]) > 0, "No findings — likely stub data"
```

### Layer 3: The CLI (30 minutes)

```bash
$ sre-discover probe boutique-demo-22 --domain logging
Score: 45/100
Findings: 5
Gaps: 3
```

### Layer 4: The Deployed Service

Same contract test, different URL. `API_URL=https://my-service.run.app pytest test_contract.py`

### "Walking" Criteria

1. OpenAPI spec compiles and type-checks
2. Contract test passes against the real deployed service
3. CLI command produces correct output
4. All three run in under 60 seconds with zero human intervention

The UI is optional for the skeleton.

## Vertical Slice Verification

Each feature is a vertical slice through all layers. Each slice has tests at every layer:

```
┌──────────────────────────────────┐
│ Playwright (if UI exists)        │  Route renders real data
├──────────────────────────────────┤
│ CLI Verification                 │  Command produces correct output
├──────────────────────────────────┤
│ Contract Tests                   │  Response matches OpenAPI spec
├──────────────────────────────────┤
│ Integration Tests                │  Real infrastructure works
├──────────────────────────────────┤
│ Unit Tests                       │  Pure logic correct
└──────────────────────────────────┘
```

### Vertical Slice Definition of Done

- [ ] OpenAPI spec entry for the endpoint
- [ ] Pydantic/Zod models matching the spec
- [ ] Contract test passing against deployed service
- [ ] Real-data assertions (not stubs)
- [ ] CLI command exercising the endpoint
- [ ] CLI output matches API output
- [ ] (If UI exists) Playwright smoke test passes

## Schemathesis — Automated Fuzz Testing

```bash
# Generate requests from OpenAPI spec and validate responses
schemathesis run openapi.yaml \
  --base-url https://my-service.run.app \
  --checks all \
  --hypothesis-max-examples 100
```

Catches:
- Response shapes that don't match the spec
- Missing required fields
- Wrong status codes for error cases
- Edge cases in input validation

## Contract Drift Prevention

```
When OpenAPI spec changes → contract tests fail → force implementation update
When implementation changes → contract tests fail → force spec update
When either changes → CI blocks merge until both aligned
```

## The Specification Hierarchy

| Representation | Ambiguity | Agent Effectiveness |
|---|---|---|
| **Executable test suite** | None | Agents run red→green with zero interpretation |
| **OpenAPI / Pydantic schema** | Very low | Agents generate clients, stubs, validators |
| **CLI command spec** | Very low | Agents implement AND self-verify |
| **Structured decision table** | Low | Less executable but unambiguous |
| **Prose PRD / user story** | High | Necessary for humans, ambiguous for agents |
| **Visual mockup** | Very high | Agents reproduce appearance, invent behavior |

Start at the top. Work downward only when needed.
