---
name: lean-startup
description: >-
  Lean Startup for agent-native development: hypothesis-driven product design,
  experiment definition via API contracts, validation via contract tests and
  CLI output, pivot triggers based on verification results.
---

# Lean Startup (Agent-Native)

## Hypothesis Canvas

Every feature starts with a hypothesis validated through API contracts and tests:

| Element | Description | Agent-Native Form |
|---------|-------------|-------------------|
| **Hypothesis** | What we believe is true | "SRE teams need automated GCP assessment" |
| **Experiment** | How we test it | Walking skeleton: one probe, one domain, real data |
| **Metric** | How we measure | Contract test results + CLI output + stakeholder CLI demo |
| **Threshold** | When we're right | Contract tests pass, CLI works, stakeholder confirms output is useful |

### From Hypothesis to Vertical Slice

```
Hypothesis: "SRE teams need to discover their logging posture automatically"

Experiment (as a vertical slice):
  1. OpenAPI spec: POST /api/v1/discovery/probe { project_id, domain: "logging" }
  2. Contract test: response contains score, findings, gaps from real GCP data
  3. CLI: sre-discover probe boutique-demo-22 --domain logging → real output
  4. Deploy: contract test passes against Cloud Run URL
  5. Checkpoint: stakeholder runs CLI, reviews output, confirms value

Validation:
  - Contract tests pass against deployed service? → Technically works
  - Stakeholder reviews CLI output and says "yes, these are real gaps"? → Validated
  - Stakeholder says "this isn't what I need"? → Pivot
```

## MVP Types (Reframed)

| MVP Type | What It Validates | Agent-Native Form |
|----------|-------------------|-------------------|
| **Walking skeleton** | End-to-end technical feasibility | One endpoint + one test + one CLI command |
| **Concierge** | Whether the solution solves the problem | Manually curated API response + stakeholder review |
| **Single feature** | Whether one capability is valuable | One complete vertical slice deployed and verified |
| **CLI-only** | Whether the core value proposition works without UI | CLI commands exercising the full API |
| **Scaffold UI** | Whether visual presentation adds value beyond CLI | Ugly-but-functional views rendering real data |

### The Walking Skeleton as MVP

The walking skeleton IS the first MVP:

```
MVP = {
  spec: openapi.yaml (one endpoint),
  test: pytest test_contract.py (passes against deployed service),
  cli: sre-discover probe boutique-demo-22 (produces real output),
  deploy: Cloud Run service (contract tests pass against it)
}
```

If this works and the stakeholder validates the output, the hypothesis is validated. Build breadth (more endpoints). If the stakeholder says the output is wrong, the hypothesis needs adjustment. Pivot the contract.

## Pivot Triggers

| Signal | Meaning | Action |
|--------|---------|--------|
| Contract tests pass but stakeholder says output is wrong | Right system, wrong data shape | Revise the OpenAPI spec |
| Contract tests pass but stakeholder says feature is not needed | Right execution, wrong hypothesis | Pivot to different capability |
| Contract tests fail because real GCP data doesn't match assumptions | Contract is wrong about reality | Update spec to match real data shapes |
| CLI works but stakeholder wants visual display | Core value validated, UI needed | Proceed to scaffold UI (Phase 4) |
| Nobody uses the CLI | The capability isn't valuable | Kill the feature |

## Innovation Accounting (Agent-Native)

Track progress by verification state, not activity:

| Metric | Old (Activity) | New (Verification) |
|--------|----------------|-------------------|
| Progress | "8/8 stories complete" | "Contract tests pass for 3/4 endpoints against production" |
| Quality | "2,600 tests pass" | "48/48 contract tests pass, 0 against stubs" |
| Velocity | "253 commits this sprint" | "3 vertical slices deployed and verified" |
| Readiness | "94/94 stories complete" | "CLI produces correct output for all commands, stakeholder confirmed at checkpoint" |

## The 0-to-1 Process

```
Phase 0: Contract (1 hour)
  → OpenAPI spec for the first slice
  GATE: Spec compiles, Pydantic models type-check

Phase 1: Proof (1-2 hours)
  → Contract test against real infrastructure
  GATE: pytest passes against deployed service

Phase 2: CLI (30 min)
  → CLI exercising the endpoint
  GATE: CLI produces correct real output

Phase 3: Deploy (30 min)
  → Contract tests pass against production URL
  GATE: Same test suite, different URL

CHECKPOINT: Stakeholder runs CLI, reviews output
  → "Yes, this is right" → Build breadth (more endpoints)
  → "No, this is wrong" → Pivot the contract

Phase 4: Scaffold UI (1-2 hours)
  → Types from spec, ugly views with real data
  GATE: Browser shows real data from real API

Phase 5: Polish (sprint duration)
  → Design refinement, breadth, editorial
  GATE: Full test suite passes, CUJs complete
```
