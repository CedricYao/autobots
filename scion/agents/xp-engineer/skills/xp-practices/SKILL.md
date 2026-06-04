---
name: xp-practices
description: >-
  XP practices for agent-native development: YAGNI, refactoring catalog, code
  smells, CI discipline, collective ownership, pair programming, and the
  spec→test→CLI→deploy→UI development sequence.
---

# XP Engineering Practices

## The Agent-Native Development Sequence

The fundamental ordering for every feature: **spec → test → CLI → deploy → UI**.

| Phase | Artifact | Agent Can Verify? | Time |
|-------|----------|-------------------|------|
| 0. Contract | OpenAPI spec + Pydantic models | Type-check: yes | 10 min |
| 1. Proof | Contract test against real infra | pytest: yes | 20 min |
| 2. CLI | CLI command exercising the endpoint | Run + check output: yes | 30 min |
| 3. Deploy | Service on Cloud Run | Contract test against URL: yes | 30 min |
| 4. UI | Scaffold from generated types | Playwright smoke: yes | 1-2 hr |

Each phase produces an executable artifact. Each artifact is verifiable in seconds. The UI comes last because it depends on everything before it.

## YAGNI — You Aren't Gonna Need It

Build only what is needed right now.

| Temptation | YAGNI Response |
|-----------|---------------|
| "Let's add a plugin system in case we need it" | Build the concrete thing. Extract the plugin system when you have 3 plugins. |
| "We should use an interface here for flexibility" | Use the concrete type. Introduce the interface when you have 2 implementations. |
| "Let's build the UI first so we can demo it" | Build the API + CLI first. Demo the CLI output. UI comes in Phase 4. |
| "Let's mock the GCP API so we can develop offline" | Connect to real GCP from day 1. If you can't reach GCP, fix that first. |
| "Let's write an in-memory store for faster development" | In-memory stores become the product. Use real infrastructure. |

### When YAGNI Does NOT Apply

- **Security:** Don't skip auth because "it's internal"
- **Tests against real infrastructure:** Don't mock boundaries for speed
- **Error handling at system boundaries:** Don't ignore API errors
- **The OpenAPI contract:** Don't skip the spec to "move faster"

## Refactoring Catalog

Refactor after making a contract test pass, not as a separate phase.

### Rename
The most powerful refactoring. If you have to think about what something means, rename it.

### Extract Method
When a function does two things, or a block needs a comment to explain it.

### Inline
When an abstraction isn't earning its keep — the function name doesn't add clarity.

### Move
When a method uses more data from another class than its own (feature envy).

### Introduce Parameter Object
When a function takes 5+ related parameters.

### Replace Conditional with Polymorphism
When you see repeated if/elif chains switching on a type.

## Code Smells

| Smell | Symptom | Refactoring |
|-------|---------|-------------|
| **Long method** | Function > 20 lines | Extract method |
| **Long parameter list** | Function takes 5+ params | Introduce parameter object |
| **Duplicate code** | Same logic in 3+ places | Extract method/class |
| **Feature envy** | Method uses another object's data more than its own | Move method |
| **Primitive obsession** | Business concepts as raw strings/ints | Introduce value object |
| **Stubbed system** | In-memory stores deployed as production | Connect to real infrastructure |
| **Mock boundary** | Tests mock the boundary they should verify | Write contract tests against real services |
| **Dead code** | Code that's never called | Delete it |
| **Speculative generality** | Abstractions for changes that haven't happened | Inline/remove |

## CI Discipline

### Rules

1. **Main is always green.** A broken build is the team's top priority.
2. **Contract tests run on every merge.** Not just unit tests — the full contract suite.
3. **Merge at least daily.** Branches that live longer than a day create merge pain.
4. **"Deploy succeeded" means contract tests pass against the deployed URL.** Not just "containers started."
5. **No commented-out code in commits.** Delete it. Git remembers.

### The Verification Pyramid

```
                    /\
                   /  \
                  / UI \          ← Playwright: "Does it look right?"
                 / Tests \            Runs at deployment checkpoints
                /----------\
               / CLI Tests  \     ← CLI verification: "Does the flow work?"
              /              \        Runs after every merge batch
             /----------------\
            / Contract Tests   \  ← pytest: "Does the API match the spec?"
           /                    \     Runs on every merge
          /----------------------\
         / OpenAPI Spec + Types   \← Type checking: "Is the contract consistent?"
        /                          \   Runs on every commit
       /----------------------------\
```

## Collective Code Ownership

- **Anyone can change any code.** No gatekeepers.
- **Write code for the reader, not the writer.**
- **No clever tricks.** If it requires a comment to explain, rewrite it.
- **Follow the conventions of the codebase,** not your personal preferences.
- **Leave it better.** Fix the bad name, remove the dead code, add the missing contract test.

## Pair Programming Patterns

### Driver/Navigator
- **Driver:** Types the code. Focuses on current implementation.
- **Navigator:** Thinks ahead. Watches for contract violations, considers edge cases.
- **Switch roles** every 15-30 minutes or after each Red-Green-Refactor cycle.

### Ping-Pong TDD
1. Person A writes a failing contract test
2. Person B makes it pass and writes the next failing test
3. Repeat

### When to Pair

| Pair | Solo |
|------|------|
| Implementing a new contract endpoint | Routine tasks you've done before |
| Onboarding a new team member | Exploratory research |
| Critical path code (auth, payments) | Configuration changes |
| When you're stuck | When you need focused flow time |
