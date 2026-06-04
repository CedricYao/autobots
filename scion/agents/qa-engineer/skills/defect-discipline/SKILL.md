---
name: defect-discipline
description: >-
  Defect reproduction test protocol, post-merge bug analysis, test gap
  identification, and process improvement mindset. Use when handling bugs
  found after merge.
---

# Defect Discipline

A bug found after merge is not just a code problem — it's a test coverage gap. Fix the gap first, then fix the bug.

## The Protocol

When a bug is reported after code has been merged:

### Step 1: Reproduce — Confirm the Bug

Before anything else, reproduce the bug in the current codebase.

```
1. Read the bug report carefully
2. Identify the exact steps to reproduce
3. Reproduce locally — confirm the bug exists
4. Note the actual behavior vs. expected behavior
5. If you can't reproduce: gather more information, check environment differences
```

### Step 2: Write a Failing Test — BEFORE Fixing

This is the most important step. Write a test that fails because of the bug.

```python
# The bug: applying a 100% discount results in a negative total
# instead of zero, because the discount is calculated as (total * discount / 100)
# and a rounding error makes it -0.01

# FIRST: write the test that fails
def test_full_discount_results_in_zero_total():
    order = Order(items=[Item(price=Decimal("29.99"))])
    order.apply_discount(percent=100)
    assert order.total == Decimal("0.00")  # FAILS: returns Decimal("-0.01")

# THEN: fix the code
# THEN: watch the test pass
```

**Why write the test first?**
- It proves the bug exists in a reproducible way
- It proves your fix actually addresses the bug
- It prevents the bug from recurring
- It documents the exact scenario that was broken

### Step 3: Fix the Bug — Make the Test Pass

Write the minimal code change that makes the failing test pass. Keep all other tests green.

### Step 4: Analyze the Gap

Ask these questions:

| Question | What It Reveals |
|----------|----------------|
| **Which pyramid layer should have caught this?** | Was it a logic bug (unit test), a boundary bug (integration test), or a UI bug (Playwright test)? |
| **Did we have a test near this code?** | If yes: was the test too narrow? Missing an edge case? |
| **Was this scenario in the acceptance criteria?** | If no: our AC process missed it. Improve AC writing. |
| **Is this a class of bug we've seen before?** | If yes: we have a systemic gap. |
| **Could static analysis have caught this?** | If yes: add a linting rule. |

### Step 5: Strengthen Coverage

Don't just add the one reproducing test. Add coverage for the class of bug:

```python
# The original bug was 100% discount → negative total
# Strengthen: test the boundary conditions around discounts

def test_full_discount_results_in_zero_total():        # the bug
    ...

def test_zero_discount_leaves_total_unchanged():       # related boundary
    ...

def test_discount_over_100_is_rejected():              # related boundary
    ...

def test_negative_discount_is_rejected():              # related boundary
    ...

def test_discount_on_zero_total_stays_zero():          # related edge case
    ...
```

### Step 6: Document

Record what happened so the team learns:

```markdown
## Bug: Full discount produces negative total

**Root cause:** Floating-point rounding in discount calculation
**Test gap:** No unit test for 100% discount edge case
**Pyramid layer:** Unit test — this was pure logic
**Coverage added:** 5 new unit tests for discount boundary conditions
**Process improvement:** Add "boundary conditions" prompt to AC template
```

## Bug Classification

| Class | Example | Typical Gap | Prevention |
|-------|---------|-------------|------------|
| **Logic error** | Wrong calculation, off-by-one | Missing unit test for edge case | Better boundary testing |
| **State error** | Wrong state transition allowed | Missing state machine test | Enumerate valid transitions |
| **Integration error** | API returns unexpected format | Missing integration test | Contract tests at boundaries |
| **UI error** | Button doesn't disable after click | Missing Playwright test | Happy + error path coverage |
| **Race condition** | Double-submit creates duplicate | Missing concurrency test | Idempotency tests |
| **Data error** | Null field causes crash | Missing null/empty test | Defensive data tests |

## Process Improvement Mindset

### The Five Whys

For significant bugs, trace back to the process failure:

```
Bug: User can submit form with invalid email
Why? → The email validation regex was wrong
Why? → The regex wasn't tested with edge cases
Why? → The AC only said "validate email" without specifying cases
Why? → We didn't have an AC checklist prompting for edge cases
Why? → Our AC process doesn't include a "boundary conditions" check

Action: Add "List boundary conditions and edge cases" to AC template
```

### Systemic vs. One-Off

| Signal | One-Off | Systemic |
|--------|---------|----------|
| Seen before? | No | Yes — similar class of bug |
| Other code has same pattern? | No | Yes — same risk exists elsewhere |
| Test suite has similar gaps? | No | Yes — whole areas lack coverage |

**One-off:** Add the reproducing test, fix the bug, move on.

**Systemic:** Add the reproducing test, fix the bug, AND audit related code for the same pattern. Add a linting rule or architecture test if possible.

## What You Never Do

- Fix a post-merge bug without first writing a failing test
- Mark a bug as fixed without verifying the test passes
- Blame the developer — bugs are process failures, not personal failures
- Accept "it works on my machine" — if it broke in production, the test suite has a gap
- Skip the gap analysis — the fix prevents this exact bug, the analysis prevents the class of bugs
