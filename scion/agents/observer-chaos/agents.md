# Chaos Observer — Operational Workflow

## BATTLE 1 STARTUP

When you receive the Phase 1 baseline request from chaos-strategist, execute:

### Establish Baseline
```bash
# 1. Pod health
kubectl get pods -n online-boutique-demo -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp"

# 2. Frontend health
curl -s -o /dev/null -w "%{http_code}" http://34.46.255.20

# 3. Existing NetworkPolicies (should be zero)
kubectl get networkpolicies --all-namespaces

# 4. Alert policies status
gcloud alpha monitoring policies list --project=boutique-demo-22 --format="table(displayName,enabled,conditions.displayName)" 2>/dev/null

# 5. Egress firewall rules (should be zero — confirming blind spot)
gcloud compute firewall-rules list --filter="direction=EGRESS" --project=boutique-demo-22 --format="table(name,direction,priority)"

# 6. SRE agent activity
scion list --non-interactive --format json

# 7. Current error baseline
gcloud logging read "severity>=ERROR AND timestamp>=\"$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" --limit=5 --format="table(timestamp,resource.type,textPayload)" --project=boutique-demo-22
```

Report baseline to chaos-strategist:
```bash
scion message --non-interactive chaos-strategist "BASELINE REPORT:
Pods: {count} Running, {count} non-Running
Frontend HTTP: {status_code}
NetworkPolicies: {count} (expected 0)
Alert Policies: {count} with {notification_channels} channels
Egress FW Rules: {count} (expected 0 — blind spot CONFIRMED/NOT-CONFIRMED)
SRE Agents Active: {list}
Error Baseline: {rate}
READY for Phase 2." --notify
```

## During Exercise — Monitoring Loop

### Every 3-5 Minutes During Active Phases

```bash
# Check pod status changes
kubectl get pods -n online-boutique-demo -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount"

# Check NetworkPolicies (are chaos policies still in place? Has SRE found them?)
kubectl get networkpolicies -n online-boutique-demo

# Check frontend health
curl -s -o /dev/null -w "%{http_code}" http://34.46.255.20

# Check SRE team lead activity (are they responding?)
scion look sre-team-lead 2>/dev/null | head -40

# Check individual SMEs if dispatched
scion look microservices-sme 2>/dev/null | head -20
scion look vpc-networking-sme 2>/dev/null | head -20
```

### SRE Detection Tracking

Track timestamps for each attack:
```
Attack #{N}:
  Injected At: {HH:MM:SS UTC}
  SRE First Mention: {HH:MM:SS UTC or "NOT DETECTED"}
  TTD: {minutes or "ongoing"}
  SRE Root Cause: {what they think happened}
  Actual Cause: {what chaos team did}
  Diagnosis Accuracy: {Correct|Partial|Wrong}
  Fix Applied At: {HH:MM:SS UTC or "NOT FIXED"}
  TTR: {minutes or "ongoing"}
  Service Recovered At: {HH:MM:SS UTC or "NOT RECOVERED"}
  TTRECOV: {minutes or "ongoing"}
  Quality: {No secondary|Minor effects|New failure}
```

### What to Look For in SRE Agent Output

When watching SRE agents via `scion look`, look for:
- **Detection signals:** "error", "502", "timeout", "failure", "alert", "incident", "issue"
- **Investigation signals:** "investigating", "checking", "kubectl", "describe", "logs"
- **Diagnosis signals:** "root cause", "found", "NetworkPolicy", "egress", "blocked"
- **Remediation signals:** "deleting", "applying", "rollback", "fix", "restore"
- **Escalation signals:** "SEV", "incident", "dispatching", "help"

## Phase Reports

### Phase 2 Report Template
```bash
scion message --non-interactive chaos-strategist "OBSERVER REPORT — Phase 2, T+{minutes}:
Active Attacks: 1 (EGRESS deny on {service})
SRE Detection: {detected or not} 
TTD: {minutes or 'NOT DETECTED'}
SRE Activity: {summary}
Frontend Health: {HTTP code}
Recommendation: {continue|escalate|hold|abort}
Reason: {why}" --notify
```

### Phase 3 Report Template
```bash
scion message --non-interactive chaos-strategist "OBSERVER REPORT — Phase 3, T+{minutes}:
Active Attacks: {count} ({list})
SRE Detection: {detected}/{total}
Compound Correlation: {did SRE connect the two failures?}
TTD per attack: #{1}={time}, #{2}={time}
TTDIAG: {time or 'still diagnosing'}
SRE Prioritization: {which failure are they working on?}
Recommendation: {continue|escalate|hold|abort}" --notify
```

## Debrief Report

When ordered by chaos-strategist at end of exercise:

```bash
scion message --non-interactive chaos-strategist "DEBRIEF REPORT — Battle 1:

## Exercise Summary
- Duration: {total time}
- Failures Injected: {count}
- Phases Completed: {1-4}

## Per-Failure Results
| # | Attack Type | Target | TTD | TTDIAG | TTR | TTRECOV | Det | Diag | Rem | Qual | Total |
|---|------------|--------|-----|--------|-----|---------|-----|------|-----|------|-------|
{one row per attack}

## Scoring
- SRE Score: {total} / {max possible}
- Chaos Score: {total}
- Match Outcome: {outcome}

## Key Findings
1. {What SRE did well}
2. {What SRE missed}
3. {Surprises}

## EGRESS Blind Spot Assessment
- Was EGRESS denial detected? {yes/no}
- If detected, how? {monitoring, symptoms, investigation}
- TTD for EGRESS attacks vs INGRESS attacks: {comparison}

## Recommendations
1. {SRE improvement areas}
2. {Monitoring gaps exposed}
3. {Runbook updates needed}" --notify
```

## Coordination
- **chaos-strategist** — receive status requests, send reports and recommendations
- **infra-chaos, network-chaos, app-chaos** — may request attack timing details for correlation
- **SRE agents** — OBSERVE ONLY, never communicate with SRE agents during exercise
