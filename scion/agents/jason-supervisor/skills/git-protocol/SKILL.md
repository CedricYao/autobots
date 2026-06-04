---
name: git-protocol
description: >-
  Git commit, tag, and release protocol for the Supervisor. The Supervisor is
  the ONLY agent allowed to commit. Every commit must be auditor-verified and
  user-approved. Includes conventional commit format, status checking, and
  release tagging.
---

# Git Protocol

## Core Rules

1. **Only the Supervisor commits.** No other agent runs `git commit`.
2. **Never commit unverified code.** The Auditor must pass before any commit.
3. **Never commit without user approval.** Always STOP and ask.
4. **Never commit broken code.** If tests fail, fix first.

## Commit Workflow

### Step 1: Status Check

After the Auditor verifies an Execution Group:

```bash
git status
git diff --stat
```

Review what changed. Confirm all changes are expected and related to the current group.

### Step 2: Draft Commit Message

Use conventional commit format:

```
<type>(<scope>): <short description>

<body — what was done and why>

Milestone: {moniker}
Group: {group number}
Tasks: {task list}
```

**Types:**
- `feat` — new feature
- `fix` — bug fix
- `refactor` — code restructuring
- `test` — adding or updating tests
- `docs` — documentation changes
- `chore` — maintenance tasks

**Examples:**
```
feat(auth): add OAuth2 login flow

Implements Google OAuth2 authentication with PKCE.
Adds login page, callback handler, and session management.

Milestone: oauth-login
Group: 1
Tasks: 1.1, 1.2, 1.3
```

```
fix(cart): prevent duplicate items on rapid add

Adds debounce and server-side idempotency check to cart add endpoint.
Includes regression test for the double-add scenario.

Milestone: cart-bugfix
Group: 1
Tasks: 1.1, 1.2
```

### Step 3: User Approval Gate

Present the commit to the user:

```
Group {N} is verified by the Auditor. Proposed commit:

  {type}({scope}): {description}

Files changed: {count}
Insertions: {count}
Deletions: {count}

OK to commit? (yes/no)
```

**Wait for explicit approval.** Do not proceed on silence or ambiguity.

### Step 4: Commit

Only after user says "yes", "approve", "ok", or equivalent:

```bash
git add -A
git commit -m "<message>"
```

### Step 5: Confirm

```bash
git log --oneline -1
```

Report the commit hash and message to the user.

## Release Tagging

### When to Tag

Tag when ALL milestones for a release version in `00-ROADMAP.md` are marked "Completed".

### Tagging Protocol

1. **Ask:** "All features for Release {version} are complete. Shall I create the tag?"
2. **Tag:** `git tag -a {version} -m "Release {version}"`
3. **Ask about push:** "Tag created. Shall I push tags to remote? (`git push --tags`)"
4. **Push only on approval:** `git push --tags`

### Version Format

Follow semantic versioning unless the project has an existing convention:
- `v1.0.0` — major release
- `v1.1.0` — minor feature release
- `v1.1.1` — patch/bugfix release

## Anti-Patterns

- **Committing without auditor verification** — always verify first
- **Batching multiple groups into one commit** — one commit per Execution Group
- **Amending commits after they're made** — create new commits instead
- **Force-pushing** — never force-push without explicit user instruction
- **Committing generated files** — check `.gitignore` before committing
