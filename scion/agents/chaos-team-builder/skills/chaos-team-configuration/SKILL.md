---
name: chaos-team-configuration
description: >-
  Configuration logic for building chaos agent templates from discovered
  infrastructure. Includes template generation rules, attack surface mapping,
  manifest generation, and deployment kit structure.
---

# Chaos Team Configuration

## Template Generation

### chaos-strategist

**scion-agent.yaml:**
```yaml
name: chaos-strategist
description: >-
  Chaos team lead for {project-id}. Plans attack sequences across 5 phases,
  coordinates 3 attack agents and 1 observer, targets known gaps and SPOFs.
max_turns: 200
max_duration: 4h
```

**system-prompt.md must include:**
- Full infrastructure inventory (from discovery)
- Prioritized attack surface list with P1-P4 classifications
- Cross-cutting risks and known gaps
- The 5-phase attack playbook structure
- Scoring criteria (chaos score formula + SRE score formula)
- Time-based thresholds (TTD, TTDIAG, TTR, TTRECOV)
- Match outcome criteria (decisive win → chaos decisive win)
- Coordination commands for dispatching attack agents

**agents.md must include:**
- Dispatch patterns using `scion message --non-interactive`
- Phase transition logic (when to escalate from Phase 2 to 3 to 4)
- Observer check-in protocol (request TTD/TTDIAG updates)
- Abort conditions and emergency rollback sequence
- Post-exercise debrief template

**skills/attack-planning/SKILL.md must include:**
- Target selection logic (P1 first, then SPOFs, then standard)
- Attack sequencing rules (single → compound → multi-vector)
- Timing calculations (stagger attacks based on expected SRE response)
- Escalation decision tree

### infra-chaos

**scion-agent.yaml:**
```yaml
name: infra-chaos
description: >-
  Infrastructure chaos agent for {project-id}. Executes resource exhaustion,
  SA manipulation, and compute disruption attacks against discovered targets.
max_turns: 100
max_duration: 2h
```

**system-prompt.md must include:**
- Compute targets (pods, services, instances with names and namespaces)
- SA targets (emails, current roles, manipulation vectors)
- Resource limits and quotas
- Abort conditions and rollback commands for every attack
- Safety constraints (what NOT to touch)

**agents.md must include:**
- Attack execution workflow (receive order → confirm target → execute → report)
- Rollback procedures for each attack type
- Status reporting format to chaos-strategist

**skills/infrastructure-attacks/SKILL.md must include:**
- Pod/instance termination commands (kubectl delete, gcloud compute instances stop)
- Resource exhaustion commands (CPU/memory stress)
- SA permission revocation commands
- Rollback commands for each attack

### network-chaos

**scion-agent.yaml:**
```yaml
name: network-chaos
description: >-
  Network chaos agent for {project-id}. Executes NetworkPolicy injection,
  VPC disruption, and latency attacks against discovered network topology.
max_turns: 100
max_duration: 2h
```

**system-prompt.md must include:**
- Network topology (VPCs, subnets, connectors, firewall rules)
- GKE service mesh details for NetworkPolicy targeting
- VIP/forwarding rule details
- Connectivity paths between services
- Abort conditions and rollback for every network attack

**agents.md must include:**
- NetworkPolicy injection workflow (craft → apply → monitor → rollback)
- Latency injection methods
- Status reporting format

**skills/network-attacks/SKILL.md must include:**
- NetworkPolicy YAML templates for service isolation
- Firewall rule manipulation commands
- VPC connector disruption methods
- Latency injection commands (tc, toxiproxy, or native)
- Rollback commands (delete policies, restore rules)

### app-chaos

**scion-agent.yaml:**
```yaml
name: app-chaos
description: >-
  Application chaos agent for {project-id}. Executes env var corruption,
  config drift, and deployment sabotage against discovered applications.
max_turns: 100
max_duration: 2h
```

**system-prompt.md must include:**
- Service configurations (env vars, config maps, deployment specs)
- Pipeline details (Cloud Deploy, triggers, approval gates)
- Dependency graph between services
- Artifact Registry repos and current images
- Abort/rollback for every app-level attack

**agents.md must include:**
- Config corruption workflow (identify target var → modify → monitor effect → rollback)
- Deployment sabotage methods
- Status reporting format

**skills/application-attacks/SKILL.md must include:**
- Env var manipulation commands (kubectl set env, gcloud run services update)
- Config map corruption commands
- Bad deployment commands (deploy known-bad image, break traffic split)
- Rollback commands for each attack type

### observer-chaos

**scion-agent.yaml:**
```yaml
name: observer-chaos
description: >-
  Chaos observer for {project-id}. Read-only monitoring of SRE team response.
  Tracks TTD, TTDIAG, TTR metrics. Recommends attack escalation to strategist.
max_turns: 200
max_duration: 4h
```

**system-prompt.md must include:**
- Monitoring inventory (alert policies, dashboards, channels)
- Baseline metrics for steady-state
- Known monitoring gaps
- Scoring rubric (both chaos and SRE formulas)
- Time thresholds per metric

**agents.md must include:**
- Observation workflow (watch dashboards → track timestamps → calculate metrics)
- Escalation recommendation format to chaos-strategist
- Debrief report template

**skills/chaos-observation/SKILL.md must include:**
- Monitoring commands (gcloud monitoring, kubectl top, log queries)
- Metric calculation formulas
- SRE team activity tracking commands (scion look, scion list)
- Report templates for each phase

## Manifest Generation

### chaos-team-manifest.yaml Structure

```yaml
manifest_version: "1.0"
project: {project-id}
generated_at: {timestamp}
generated_by: chaos-team-builder

team:
  - name: chaos-strategist
    template: chaos-strategist
    role: team_lead
    domain: coordination
  - name: infra-chaos
    template: infra-chaos
    role: attacker
    domain: infrastructure
  - name: network-chaos
    template: network-chaos
    role: attacker
    domain: network
  - name: app-chaos
    template: app-chaos
    role: attacker
    domain: application
  - name: observer-chaos
    template: observer-chaos
    role: observer
    domain: observation

attack_surfaces:
  infrastructure:
    - target: {target-name}
      type: {compute|sa|storage}
      priority: {P1-P4}
      attacks: [{list of applicable attack types}]
      rollback: {rollback command}
  network:
    - target: {target-name}
      type: {firewall|connector|policy|vip}
      priority: {P1-P4}
      attacks: [{list}]
      rollback: {rollback command}
  application:
    - target: {target-name}
      type: {config|deploy|image|dependency}
      priority: {P1-P4}
      attacks: [{list}]
      rollback: {rollback command}

playbook:
  phase_1_reconnaissance:
    duration_minutes: 5
    objectives:
      - Survey current system state
      - Identify targets from attack_surfaces
      - Assess SRE monitoring coverage
      - Identify known gaps
    agents: [chaos-strategist, observer-chaos]

  phase_2_initial_attack:
    duration_minutes: 10
    objectives:
      - Single-vector failure against P3/P4 target
      - Measure TTD and response quality
    agents: [chaos-strategist, {selected-attacker}, observer-chaos]

  phase_3_escalation:
    duration_minutes: 15
    objectives:
      - Compound failure (2 vectors)
      - Target gap identified in Phase 1 or 2
    agents: [chaos-strategist, {attacker-1}, {attacker-2}, observer-chaos]

  phase_4_advanced_attack:
    duration_minutes: 20
    objectives:
      - Multi-vector, multi-service failure
      - Target remediation capabilities
      - Exploit time pressure
    agents: [chaos-strategist, infra-chaos, network-chaos, app-chaos, observer-chaos]

  phase_5_debrief:
    duration_minutes: 30
    objectives:
      - What was detected vs missed
      - What was diagnosed correctly vs misdiagnosed
      - What was remediated vs required escalation
      - Scoring and match outcome
    agents: [chaos-strategist, observer-chaos]

scoring:
  chaos_score:
    formula: "sum(Impact * Duration * Stealth)"
    impact: "0-5 scale of user-facing impact"
    duration: "minutes before remediation"
    stealth: "1=immediate detection, 2=<10min, 3=>10min undetected"

  sre_score:
    formula: "sum(Detection + Diagnosis + Remediation + Quality)"
    detection: "0-25 points by speed"
    diagnosis: "0-25 points by accuracy"
    remediation: "0-25 points by speed"
    quality: "0-25 points, no secondary issues"

  thresholds:
    ttd_target: "5 min"
    ttd_stretch: "2 min"
    ttd_critical: "15 min (auto-loss)"
    ttdiag_target: "10 min"
    ttdiag_stretch: "5 min"
    ttdiag_critical: "30 min"
    ttr_target: "15 min"
    ttr_stretch: "10 min"
    ttr_critical: "60 min (auto-loss)"

  outcomes:
    sre_decisive_win: "All failures detected <5min AND remediated <15min, no secondary issues"
    sre_win: ">75% detected <10min AND remediated <30min"
    draw: "50-75% handled within targets"
    chaos_win: "<50% handled within targets"
    chaos_decisive_win: "Any failure >30min undetected OR SRE introduces secondary failure"
```
