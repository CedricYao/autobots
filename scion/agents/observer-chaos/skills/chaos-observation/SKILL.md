---
name: chaos-observation
description: >-
  Monitoring and measurement commands for observing SRE team response during
  chaos exercises. Includes system health checks, SRE activity tracking,
  metric calculation, and report generation.
---

# Chaos Observation

## System Health Monitoring

### Cloud Run Service Health

```bash
# Quick health check on all services
for svc in $(gcloud run services list --format="value(metadata.name)" --project={project}); do
  URL=$(gcloud run services describe "$svc" --format="value(status.url)" --region={region} --project={project})
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null || echo "TIMEOUT")
  echo "$svc: $STATUS"
done
```

### GKE Workload Health

```bash
# Pod status overview
kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp" | sort -k3

# Non-running pods (immediate indicator of attack impact)
kubectl get pods --all-namespaces --field-selector=status.phase!=Running

# Recent events (errors and warnings)
kubectl get events --all-namespaces --sort-by=.lastTimestamp --field-selector type=Warning | tail -20

# Deployment rollout status
kubectl rollout status deployment --all-namespaces 2>&1 | grep -v "successfully rolled out"
```

### Error Rate Monitoring

```bash
# Recent errors in Cloud Logging
gcloud logging read "severity>=ERROR AND timestamp>=\"$(date -u -d '{N} minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" \
  --limit=20 \
  --format="table(timestamp,resource.type,resource.labels.service_name,textPayload)" \
  --project={project}

# Error count by service
gcloud logging read "severity>=ERROR AND timestamp>=\"$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" \
  --format="value(resource.labels.service_name)" \
  --project={project} | sort | uniq -c | sort -rn
```

### Alert Status

```bash
# Check which alerts are firing
gcloud alpha monitoring policies list --format="json" --project={project} 2>/dev/null | python3 -c "
import json, sys
try:
    policies = json.load(sys.stdin)
    for p in policies:
        name = p.get('displayName', 'unnamed')
        enabled = p.get('enabled', False)
        channels = len(p.get('notificationChannels', []))
        print(f'{name}: enabled={enabled}, channels={channels}')
except:
    print('Could not parse alert policies')
"
```

### Network Health

```bash
# NetworkPolicy count (detect injected policies)
kubectl get networkpolicy --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,LABELS:.metadata.labels" 2>/dev/null

# Firewall rules (detect injected rules)
gcloud compute firewall-rules list --filter="name~^chaos-" --format="table(name,direction,action)" --project={project} 2>/dev/null
```

## SRE Team Activity Tracking

### Agent Status

```bash
# List all running agents
scion list --non-interactive --format json

# Check SRE team lead
scion look sre-team-lead

# Check specific SME agents
scion look cloud-run-sme
scion look vpc-networking-sme
scion look iam-sme
scion look microservices-sme
scion look cloud-monitoring-sme
```

### Detection Indicators

Look for these signals in SRE agent output:

| Signal | Indicates |
|--------|-----------|
| SRE team lead dispatches an SME | Detection started |
| SME runs diagnostic commands | Active investigation |
| SME reports root cause to team lead | Diagnosis complete |
| Agent runs a remediation command | Remediation started |
| Service health restored | Recovery complete |

### Timestamp Recording

Record timestamps as ISO 8601 UTC:

```bash
# Current UTC timestamp
date -u +%Y-%m-%dT%H:%M:%SZ
```

Track per-failure:
```
Failure #{N}:
  Attack Type: {type}
  Target: {service}
  T_attack:    {when chaos agent executed}
  T_detect:    {when SRE first acknowledged}
  T_diagnose:  {when SRE identified root cause}
  T_remediate: {when SRE applied fix}
  T_recover:   {when service returned to healthy}
  TTD:         {T_detect - T_attack}
  TTDIAG:      {T_diagnose - T_detect}
  TTR:         {T_remediate - T_diagnose}
  TTRECOV:     {T_recover - T_attack}
  Diagnosis:   {correct | partial | wrong}
  Quality:     {clean | minor-side-effects | new-failure}
```

## Metric Calculation

### SRE Score Per Failure

```
Detection:   TTD <2min → 25pts | <5min → 20 | <10min → 15 | <15min → 10 | >15min → 0
Diagnosis:   Correct → 25pts | Partial → 15 | Wrong → 0
Remediation: TTR <5min → 25pts | <10min → 20 | <15min → 15 | <30min → 10 | >30min → 0
Quality:     Clean → 25pts | Minor side effects → 15 | New failure → 0

Total per failure: max 100 points
```

### Chaos Score Per Failure

```
Impact:   0-5 scale (0=no user impact, 5=total outage)
Duration: minutes from attack to remediation
Stealth:  1=detected <2min | 2=detected <10min | 3=undetected >10min

Score = Impact × Duration × Stealth
```

### Match Outcome Determination

```
SRE Decisive Win:  ALL failures — TTD <5min AND TTR <15min AND Quality=clean
SRE Win:           >75% of failures — TTD <10min AND TTR <30min
Draw:              50-75% of failures handled within targets
Chaos Win:         <50% of failures handled within targets
Chaos Decisive Win: ANY failure undetected >30min OR SRE introduced secondary failure
```

## Report Templates

### Phase Update (every 5 minutes)

```
OBSERVER REPORT — Phase {N}, T+{total_minutes}min
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Active Attacks:    {count} ({list with types})
SRE Detection:     {detected}/{total} failures detected
Undetected:        {list of undetected attacks with time since injection}
Latest TTD:        {most recent detection time}
SRE Activity:      {what they're doing right now}
System Impact:     {current error rate vs baseline}
Recommendation:    {continue | escalate | hold | abort}
Reason:            {specific justification}
```

### Final Debrief Report

```markdown
# Chaos Exercise Debrief
**Project:** {project-id}
**Date:** {date}
**Duration:** {total exercise time}
**Phases Completed:** {1-5}

## Summary
{One paragraph overview of the exercise and outcome}

## Per-Failure Results

| # | Phase | Attack Type | Target | TTD | TTDIAG | TTR | TTRECOV | Det. | Diag. | Rem. | Qual. | SRE Score | Chaos Score |
|---|-------|------------|--------|-----|--------|-----|---------|------|-------|------|-------|-----------|-------------|
| 1 | {ph} | {type} | {tgt} | {t} | {t} | {t} | {t} | {s}/25 | {s}/25 | {s}/25 | {s}/25 | {total}/100 | {score} |

## Scoring Summary
- **SRE Total Score:** {sum} / {max possible}
- **SRE Average Per Failure:** {avg} / 100
- **Chaos Total Score:** {sum}
- **Match Outcome:** {outcome}

## Key Findings

### What the SRE Team Did Well
1. {finding}

### What the SRE Team Missed or Struggled With
1. {finding}

### What Surprised Both Teams
1. {finding}

## Recommendations

### For the SRE Team
1. {recommendation with specific action}

### Monitoring Gaps Exposed
1. {gap with suggested fix}

### Runbook Updates Needed
1. {update needed}

## Attack Timeline
{Chronological log of all attacks and SRE responses}
```
