---
name: github-operations
description: >-
  SSH key generation, git remote configuration with SSH URLs, push/pull
  operations, branch management, PR creation via gh CLI, and deploy key
  setup. Use for all GitHub remote operations.
---

# GitHub Operations

## SSH Key Setup

### Generate Deploy Key

```bash
# Generate Ed25519 key pair (no passphrase for agent use)
ssh-keygen -t ed25519 -C "scion-deploy-key" -f ~/.ssh/github_deploy_ed25519 -N ""

# Display the public key for the user to add to GitHub
cat ~/.ssh/github_deploy_ed25519.pub
```

### Configure SSH to Use the Deploy Key

```bash
# Add to ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_deploy_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF

chmod 600 ~/.ssh/config
```

### Add Deploy Key on GitHub

Instruct the user to:
1. Go to the repository on GitHub → Settings → Deploy keys
2. Click "Add deploy key"
3. Paste the public key
4. Check "Allow write access" (required for pushing)
5. Click "Add key"

### Test Connection

```bash
ssh -T git@github.com
# Expected: "Hi <user>! You've successfully authenticated..."
# For deploy keys: "Hi <user>/<repo>! You've successfully authenticated..."
```

### Configure Git Remote

```bash
# Set remote to SSH URL (if not already configured)
git remote add origin git@github.com:OWNER/REPO.git

# Or update existing remote from HTTPS to SSH
git remote set-url origin git@github.com:OWNER/REPO.git

# Verify
git remote -v
```

### Configure Git Identity

```bash
# Set identity for the repository (local, not global)
git config user.name "Scion Agent"
git config user.email "scion@example.com"
```

## Push Operations

### Standard Push

```bash
# Fetch current remote state first
git fetch origin

# Check if remote has diverged
git log HEAD..origin/main --oneline  # Shows commits on remote not in local

# Push current branch with tracking
git push -u origin HEAD

# Verify
git log --oneline -1  # Show pushed commit
git branch -vv        # Show tracking status
```

### Handling Divergence

```bash
# If remote has new commits, rebase local changes
git fetch origin
git rebase origin/main

# If rebase has conflicts:
# 1. Report the conflict to the requester
# 2. Do NOT force-push or resolve without approval
git rebase --abort  # If you can't resolve safely
```

### Push Safety Checks

Before every push:

```bash
# 1. Working tree must be clean
git status --porcelain  # Must be empty

# 2. All commits must have been intentional
git log origin/main..HEAD --oneline  # Review what will be pushed

# 3. Remote must be reachable
git ls-remote origin HEAD  # Must not fail

# 4. Branch must not be main/master (for direct pushes)
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "ERROR: Cannot push directly to $BRANCH"
  exit 1
fi
```

## Branch Management

### Create Feature Branch

```bash
# Always branch from latest main
git fetch origin
git checkout -b feature/<name> origin/main

# Push the new branch to remote
git push -u origin feature/<name>
```

### List Branches

```bash
# Remote branches
git branch -r

# Local branches with tracking info
git branch -vv

# Merged branches (safe to delete)
git branch --merged main
```

### Delete Merged Branch

```bash
# Delete remote branch (only after PR is merged)
git push origin --delete feature/<name>

# Delete local branch
git branch -d feature/<name>

# Prune stale remote tracking refs
git fetch --prune
```

## Pull Request Operations

### Create PR

```bash
# Create PR with structured description
gh pr create \
  --title "Add user authentication flow" \
  --body "$(cat <<'EOF'
## Summary
- Implement login/signup pages with form validation
- Add JWT-based session management
- Wire up auth middleware for protected routes

## Test plan
- [ ] Login with valid credentials → redirects to dashboard
- [ ] Login with invalid credentials → shows error message
- [ ] Signup with new email → creates account
- [ ] Access protected route without auth → redirects to login
EOF
)"
```

### Create PR with Options

```bash
# With reviewers, labels, and base branch
gh pr create \
  --title "Fix cart total calculation" \
  --body "..." \
  --base main \
  --reviewer alice,bob \
  --label "bug,priority:high"

# Draft PR (not ready for review)
gh pr create --title "WIP: Refactor auth" --body "..." --draft
```

### Check PR Status

```bash
# Status of current branch's PR
gh pr status

# View specific PR
gh pr view 42

# Check CI status on a PR
gh pr checks 42

# List open PRs
gh pr list --state open
```

### Merge PR

```bash
# Squash merge (preferred — clean history)
gh pr merge 42 --squash --delete-branch

# Regular merge
gh pr merge 42 --merge --delete-branch

# Rebase merge
gh pr merge 42 --rebase --delete-branch
```

### PR Comments

```bash
# Add a comment
gh pr comment 42 --body "CI is green, ready for review."

# View comments
gh api repos/OWNER/REPO/pulls/42/comments
```

## Repository Information

```bash
# View repo details
gh repo view

# Check current auth status
gh auth status

# List repo collaborators
gh api repos/OWNER/REPO/collaborators --jq '.[].login'
```

## Audit Logging

Log every operation with timestamp, type, and details:

```bash
# Append to audit log
log_operation() {
  local op_type="$1"
  local details="$2"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $op_type $details" >> /scion-volumes/scratchpad/github-audit.log
}

# Usage examples:
log_operation "PUSH" "branch:feature/login commits:3 (abc1234..def5678) → origin"
log_operation "PR_CREATE" "#42 'Add login flow' branch:feature/login → main"
log_operation "PR_MERGE" "#42 strategy:squash"
log_operation "BRANCH_DELETE" "feature/login (remote)"
log_operation "SSH_SETUP" "deploy key generated for github.com:owner/repo"
```

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| `Permission denied (publickey)` | SSH key not added or wrong key | Verify deploy key is added with write access |
| `rejected (non-fast-forward)` | Remote has commits not in local | Fetch and rebase, then retry |
| `rejected (protected branch)` | Branch has push restrictions | Use a feature branch and create a PR instead |
| `Could not resolve hostname` | Network issue | Check connectivity, retry after delay |
| `gh: command not found` | gh CLI not installed | Install via `apt install gh` or `brew install gh` |
