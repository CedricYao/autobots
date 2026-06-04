---
name: project-lifecycle
description: >-
  The 6-phase project lifecycle state machine: Strategic Research, Product
  Discovery, Tactical Planning, Human Review Gate, Construction Loop, and
  Release & Tag Protocol. Includes artifact templates, phase transitions,
  and agent dispatch patterns.
---

# Project Lifecycle State Machine

## Phase 0: Strategic Research

**Goal:** Understand the codebase context before making any decisions.

**Trigger:** User makes a new request (feature, bug fix, refactor).

**Steps:**
1. Acknowledge the user's request
2. State why investigation is needed: "Before planning, I need to understand the current codebase in the affected area."
3. Ensure `plans/research/` directory exists
4. Dispatch investigator agent with instruction to save a Context Report

**Context Report Template:**
```markdown
# Context Report: {Topic}

## Request Summary
{What the user asked for}

## Affected Domain
{Which parts of the codebase are involved}

## Existing Patterns
{How similar functionality is currently implemented}

## Dependencies
{External services, libraries, APIs involved}

## Constraints
{Technical limitations, compatibility requirements}

## Risks
{What could go wrong, edge cases to consider}
```

**Transition:** When Context Report is saved → Phase 1.

## Phase 1: Product Discovery

**Goal:** Clarify requirements and produce a spec.

**Trigger:** Context Report ready in `plans/research/`.

**Steps:**
1. Dispatch product_owner to read the Context Report
2. If request is trivial: update `00-ROADMAP.md` directly, create simple spec
3. If request is complex: product_owner engages user in "Grill Loop" — asking probing questions to uncover edge cases, acceptance criteria, and scope
4. Create milestone directory: `plans/active_milestones/{moniker}/`
5. Move Context Report to `plans/active_milestones/{moniker}/context.md`
6. Product owner generates `spec.md`

**Spec Template:**
```markdown
# Spec: {Milestone Name}

## Objective
{What we're building and why}

## Acceptance Criteria
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Edge Cases
- {Edge case 1: how to handle}
- {Edge case 2: how to handle}

## Out of Scope
- {What we're NOT doing}

## Dependencies
- {What must exist before this work}
```

**Transition:** When `spec.md` is saved → Phase 2.

## Phase 2: Tactical Planning

**Goal:** Produce a technical implementation plan with Execution Groups.

**Trigger:** `spec.md` ready in milestone directory.

**Steps:**
1. Dispatch architect to read `spec.md`
2. Architect generates `plan.md` with Execution Groups
3. If data model changes needed, architect also generates `data-model.md`

**Plan Template:**
```markdown
# Technical Plan: {Milestone Name}

## Architecture Decisions
- {Decision 1: rationale}
- {Decision 2: rationale}

## Execution Groups

### Group 1: {Foundation}
- Task 1.1: {Description} — {file(s) affected}
- Task 1.2: {Description} — {file(s) affected}

### Group 2: {Core Logic}
- Task 2.1: {Description} — {file(s) affected}
- Task 2.2: {Description} — {file(s) affected}

### Group 3: {Integration & Tests}
- Task 3.1: {Description} — {file(s) affected}
- Task 3.2: {Description} — {file(s) affected}

## Testing Strategy
- {What tests are needed}
- {How to verify acceptance criteria}
```

**Transition:** When `plan.md` is saved → Phase 3.

## Phase 3: Human Review Gate

**Goal:** Get explicit human approval before any code changes.

**THIS IS A MANDATORY STOP.**

**Steps:**
1. Present the spec and plan to the user
2. Summarize: milestone name, number of Execution Groups, estimated scope
3. Ask: "Please review `spec.md` and `plan.md`. Type 'approve' to proceed."
4. Wait. Do NOT proceed without explicit approval.
5. If user requests changes: dispatch architect or product_owner to revise, then re-gate

**Transition:** When user says "approve" or "proceed" → Phase 4.

## Phase 4: Construction Loop

**Goal:** Implement the plan group by group with verification and git commits.

**Trigger:** User approval received.

**For each Execution Group:**

1. **Implement:** Dispatch up to 4 engineer agents concurrently for tasks in the group
2. **Wait:** All engineers must complete before proceeding
3. **Verify:** Dispatch auditor to check: tests pass, SOLID compliance, acceptance criteria met
4. **Fork:**
   - Tests fail → dispatch engineer to fix, re-verify
   - Plan impossible → dispatch architect to revise, re-gate with user
   - All pass → proceed to git commit
5. **Commit:** Run git protocol (see git-protocol skill)
6. **Next group:** Move to next Execution Group

**Transition:** When all groups committed → check if all release milestones complete → Phase 5.

## Phase 5: Release & Tag

**Goal:** Tag the release and update the roadmap.

**Trigger:** All milestones for a release version are completed.

**Steps:**
1. Ask user: "All features for Release [Version] are complete. Shall I finalize?"
2. On approval: `git tag -a [Version] -m "Release [Version]"`
3. Ask if tags should be pushed: `git push --tags`
4. Dispatch product_owner to mark release as "Shipped" in `00-ROADMAP.md`
5. Product_owner activates next release in roadmap

**Transition:** New user request → Phase 0.
