---
name: attack-planning
description: >-
  Target selection, attack sequencing, escalation logic, and timing calculations
  for chaos exercise planning. Includes composite attack scenarios and
  exploitation of known infrastructure gaps.
---

# Attack Planning

## Target Selection Logic

### Priority Order

1. **P1 — Known Gaps**: Infrastructure with documented cross-cutting risks or prior incident history
2. **P2 — SPOFs**: Single points of failure in the architecture
3. **P3 — Standard Surfaces**: Normal infrastructure that should be resilient
4. **P4 — Hardened Targets**: Infrastructure with known protections

### Selection Rules

```
Phase 2 (Initial): Select a P3 or P4 target
  → Purpose: calibrate SRE response speed without exploiting known weaknesses
  → Choose something that should be easily detected and remediated
  → The SRE team's response time here becomes the baseline

Phase 3 (Escalation): Select one P1 or P2 target + one P3 target
  → Purpose: test response to a known gap while creating distraction
  → The P3 attack draws attention; the P1/P2 attack tests real weakness
  → Use different domains for the two attacks

Phase 4 (Advanced): Select 2-3 targets across all domains
  → Purpose: overwhelm with simultaneous multi-domain failures
  → Include at least one attack that targets the remediation path
  → Sequence attacks to exploit the SRE team's response pattern
```

## Attack Sequencing

### Single-Vector (Phase 2)

```
T+0:00  [selected-agent]  Execute single attack
T+0:01  [observer-chaos]   Begin tracking TTD
T+0:05  [observer-chaos]   Report: detected or not?
T+0:10  [strategist]       Decision: advance to Phase 3 or extend Phase 2
```

### Compound (Phase 3)

```
T+0:00  [agent-1]          Execute primary attack (the real test)
T+0:03  [agent-2]          Execute secondary attack (distraction or amplifier)
T+0:05  [observer-chaos]   Report: which was detected first?
T+0:10  [observer-chaos]   Report: did SRE correlate the two failures?
T+0:15  [strategist]       Decision: advance to Phase 4 or extend Phase 3
```

### Multi-Vector (Phase 4)

```
T+0:00  [agent-1]          Execute attack 1 (infrastructure disruption)
T+0:03  [agent-2]          Execute attack 2 (network isolation)
T+0:05  [observer-chaos]   Report: SRE response so far
T+0:06  [agent-3]          Execute attack 3 (application corruption)
T+0:10  [observer-chaos]   Report: prioritization and diagnosis accuracy
T+0:12  [strategist]       If SRE is remediating attack 1, disrupt the fix path
T+0:15  [observer-chaos]   Full status report
T+0:20  [strategist]       Begin wind-down, order rollbacks
```

## Composite Attack Scenarios

### Scenario A: Silent Alert Exploitation

If the target has alert policies with zero notification channels:

```
T+0:00  [infra-chaos]      Kill a non-critical pod (should trigger alert)
T+0:05  [observer-chaos]   Check: did alert fire? Was it delivered?
T+0:05  [network-chaos]    If alert was NOT delivered: inject NetworkPolicy
         → SRE team is blind + isolated; clock runs on two undetected failures
T+0:10  [app-chaos]        Corrupt a config var on the isolated service
         → Three-layer attack, all exploiting the silent alerting gap
```

### Scenario B: Diagnosis-Remediation Gap

If the SRE team has limited permissions:

```
T+0:00  [network-chaos]    Apply NetworkPolicy to critical-path service
T+0:05  [observer-chaos]   Wait for SRE detection (should be quick — visible outage)
T+0:05  [observer-chaos]   Track: can they diagnose it? (do they find the policy?)
T+0:10  [observer-chaos]   Track: can they fix it? (do they have kubectl permissions?)
         → If blocked on permissions, the clock keeps running
T+0:15  [app-chaos]        If SRE is stuck, add a second failure elsewhere
         → Forces the team to triage while still blocked on the first issue
```

### Scenario C: SPOF Cascade

If the architecture has single points of failure:

```
T+0:00  [network-chaos]    Disrupt the VPC connector (SPOF for Cloud Run → GKE)
T+0:05  [observer-chaos]   Track: does SRE identify the connector as root cause?
T+0:08  [infra-chaos]      If SRE is focused on connector, disrupt a GKE service directly
         → SRE now has two independent failure sources to distinguish
T+0:12  [app-chaos]        Corrupt a config on a Cloud Run service
         → Three failures, all looking like "backend unreachable" but with different causes
```

### Scenario D: Recovery Sabotage

```
T+0:00  [infra-chaos]      Kill a pod (simple, detectable)
T+0:05  [observer-chaos]   Wait for SRE to start remediating
T+0:06  [network-chaos]    Once SRE is applying fix: inject NetworkPolicy on the same service
         → The fix appears to not work because the network is now also blocked
T+0:10  [observer-chaos]   Track: does SRE realize there are TWO issues, not one?
```

## Timing Calculations

### Expected SRE Response Times (from research)

| Metric | Target | Stretch | Critical |
|--------|--------|---------|----------|
| TTD | <5 min | <2 min | >15 min = auto-loss |
| TTDIAG | <10 min | <5 min | >30 min = significant penalty |
| TTR | <15 min | <10 min | >60 min = auto-loss |
| TTRECOV | <20 min | <15 min | >90 min = auto-loss |

### Attack Spacing

- Minimum gap between attacks in the same domain: 3 minutes
- Minimum gap between phases: 5 minutes (allow observer to report)
- Maximum simultaneous active attacks: 3 (beyond this, exercise becomes chaotic not chaotic-engineering)

## Escalation Decision Tree

```
After each observer report:

IF SRE detected in <2 min AND diagnosed correctly:
  → They're strong in this domain
  → Next attack: different domain OR same domain but subtle
  → Consider advancing to next phase early

IF SRE detected in 5-10 min:
  → Normal response; proceed as planned
  → No change to timeline

IF SRE NOT detected after 10 min:
  → Stealth is working; HOLD current phase
  → Do NOT escalate — let the undetected failure accumulate score
  → Add a subtle second vector if available

IF SRE misdiagnosed:
  → Diagnosis is weak; exploit this
  → Next attack: create misleading symptoms
  → Stack failures that look related but aren't

IF SRE remediated but introduced new failure:
  → Quality is weak; this is very valuable data
  → Observer should track the secondary failure carefully
  → May trigger Chaos Decisive Win condition
```
