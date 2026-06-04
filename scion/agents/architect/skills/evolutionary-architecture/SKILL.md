---
name: evolutionary-architecture
description: >-
  Evolutionary architecture patterns: fitness functions, ADR format, modularity
  assessment, coupling analysis, and migration strategies. Use when designing
  systems for incremental change or documenting architectural decisions.
---

# Evolutionary Architecture

Design systems that support incremental, guided change over time.

## Architecture Decision Records (ADRs)

Document every significant architectural decision. An ADR is immutable — if the decision changes, write a new ADR that supersedes the old one.

### ADR Template

```markdown
# ADR-NNN: [Decision Title]

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-NNN
**Deciders:** [who was involved]

## Context

[What is the issue? What forces are at play? What constraints exist?
This section describes the situation that motivates the decision.]

## Decision

[What is the change that we're proposing and/or doing?
State the decision in active voice: "We will use X for Y."]

## Options Considered

### Option A: [Name]
- **Pros:** [advantages]
- **Cons:** [disadvantages]
- **Cost:** [rough cost estimate]
- **Fitness:** [how well it supports key quality attributes]

### Option B: [Name]
- **Pros:** ...
- **Cons:** ...

### Option C: [Name] (if applicable)
- ...

## Consequences

### Positive
- [What becomes easier or better]

### Negative
- [What becomes harder or worse — be honest]

### Risks
- [What could go wrong with this decision]

## Fitness Functions

[Automated checks that verify this decision continues to hold:]
- [Fitness function 1: what it checks, how it's measured, what threshold triggers review]
- [Fitness function 2: ...]
```

### ADR Rules
- Number sequentially: ADR-001, ADR-002, ...
- Never edit the body of an accepted ADR — write a new one that supersedes
- Include rejected options — future readers need to know what was considered
- Keep them short: 1-2 pages maximum
- Link to related ADRs when decisions build on each other

## Fitness Functions

Automated architectural tests that continuously verify the system maintains desired qualities.

### Categories

| Category | Examples | How to Implement |
|----------|---------|-----------------|
| **Performance** | p95 latency < 200ms, throughput > 1000 req/s | Load test in CI, Cloud Monitoring alert |
| **Reliability** | Availability > 99.9%, recovery time < 5 min | Uptime check, chaos test, SLO in Cloud Monitoring |
| **Security** | No public endpoints without auth, no secrets in code | Security scanner in CI, git-secrets pre-commit hook |
| **Coupling** | No circular dependencies, max fan-out of 5 | Dependency analysis tool in CI |
| **Cost** | Monthly bill < $X, cost per request < $0.001 | Billing alert, cost attribution labels |
| **Modularity** | Module boundary violations = 0 | ArchUnit / dependency-cruiser in CI |
| **Data** | No PII in logs, retention policies enforced | Log scanner, DLP API check |

### Fitness Function Principles
- **Automated:** If it requires a human to check, it will be forgotten
- **Continuous:** Run in CI/CD and production monitoring, not quarterly
- **Threshold-based:** Pass/fail, not subjective assessment
- **Evolutionary:** Update thresholds as the system matures

## Coupling Assessment

### Coupling Types (from acceptable to dangerous)

| Type | Description | Acceptable? |
|------|------------|-------------|
| **Data coupling** | Modules share simple data via well-defined interfaces | Yes |
| **Stamp coupling** | Modules share composite data structures | Usually — watch for unnecessary fields |
| **Control coupling** | One module controls another's behavior via flags | Caution — consider polymorphism |
| **Common coupling** | Modules share global state | Rarely — use explicit dependencies |
| **Content coupling** | One module reaches into another's internals | Never — refactor immediately |

### Reducing Coupling
- **Events over calls:** Pub/Sub decouples producer from consumer
- **Contracts over implementations:** Define interfaces/schemas at boundaries
- **Data duplication over sharing:** Each service owns its data; sync via events
- **Strangler fig over rewrite:** Gradually route traffic to new implementation

## Migration Strategies

### Strangler Fig Pattern
1. Identify a seam in the monolith (a bounded context with clear inputs/outputs)
2. Build the replacement service alongside the monolith
3. Route traffic for that context to the new service (using a router/proxy)
4. Verify the new service works correctly (shadow traffic, canary)
5. Remove the old code path from the monolith
6. Repeat for the next seam

### Branch by Abstraction
1. Create an abstraction layer over the code you want to replace
2. Migrate all callers to use the abstraction
3. Create a new implementation behind the abstraction
4. Switch the abstraction to use the new implementation
5. Remove the old implementation

### Parallel Run
1. Run old and new implementations simultaneously
2. Compare outputs for every request
3. Log discrepancies
4. Switch to new when discrepancy rate drops to acceptable level

## Conway's Law

> "Organizations which design systems are constrained to produce designs which are copies of the communication structures of these organizations."

**Practical implications:**
- A 3-person team should not build 12 microservices
- Service boundaries should align with team boundaries
- If two teams must coordinate to deploy, their services are coupled regardless of the architecture diagram
- "Inverse Conway maneuver": structure teams to match the desired architecture
