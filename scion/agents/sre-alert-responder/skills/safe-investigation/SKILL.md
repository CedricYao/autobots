---
name: safe-investigation
description: >-
  Safety guidelines for autonomous SRE investigation. Use to ensure all investigation
  and remediation actions follow the principle of least privilege and include proper
  risk assessment.
---

# Safe Investigation Guidelines

Safety framework for autonomous SRE agents operating in production environments.

## Principle of Least Privilege

- Use read-only operations for all investigation activities
- Only escalate to write operations for approved mitigations
- Prefer Cloud Logging/Monitoring APIs over kubectl for data gathering
- Never modify production state during investigation phase

## Read-Only Operations (always safe)

| Tool | Safe Commands |
|------|--------------|
| gcloud logging | `read` |
| gcloud monitoring | `time-series list`, `policies list`, `dashboards list` |
| gcloud trace | `traces list`, `traces describe` |
| gcloud deploy | `releases list`, `rollouts list` |
| kubectl | `get`, `describe`, `logs`, `top`, `events` |

## Write Operations (require approval)

| Tool | Commands | Risk Level |
|------|----------|-----------|
| kubectl | `rollout undo` | LOW |
| kubectl | `rollout restart` | LOW |
| kubectl | `scale` | LOW |
| kubectl | `set env` | MEDIUM |
| kubectl | `delete networkpolicy` | MEDIUM |
| kubectl | `delete pod` | MEDIUM |
| gcloud deploy | `releases promote` | MEDIUM |
| kubectl | `drain` | HIGH |

## Risk Assessment Format

Every write operation must include:

```
# Action: [What you're doing]
# Risk: [NONE/LOW/MEDIUM/HIGH]
# Justification: [Why this action is needed]
# Impact: [What will happen during execution]
# Rollback: [How to undo if it makes things worse]
# Verification: [How to confirm the action succeeded]
```

## Timeouts

Always use timeouts on API calls to prevent agent hangs:
- `timeout 60` for gcloud logging/monitoring commands
- `timeout 30` for kubectl commands
- `timeout 120` for long-running operations (rollouts, promotions)

## Context Window Protection

- Never read large log files or API responses directly into context
- Always pipe through `jq`, `head`, or summary scripts
- Use `--limit` flags on all list/read commands
- Delegate data-heavy analysis to worker agents to protect orchestrator context
