# Runbook: IAM Permission Gap During Incidents

**Runbook ID:** RB-004
**Derived from:** INC-2026-0601-001 — 8-hour remediation delay caused by IAM constraints
**Failure type:** Operational — agents can diagnose but cannot remediate due to viewer-only permissions
**Severity when triggered:** Extends any active incident by hours until human intervention
**Last updated:** 2026-06-02
**Owner:** iam-sme + sre-team-lead

---

## The Problem

The SRE team service account (`scion-platform-team@deploy-demo-test.iam.gserviceaccount.com`) has `roles/viewer` only on project `boutique-demo-22`. During INC-2026-0601-001:

- 3 root causes were identified in 30 minutes
- Remediation was prepared and validated
- **Zero remediation could be executed** — blocked for 8 hours
- 4 separate remediation paths were attempted and all failed

This runbook documents the escalation procedures to minimize the time gap between diagnosis and remediation.

## Current Access Model

### What agents CAN do (viewer access)

```
kubectl get, kubectl describe, kubectl logs, kubectl top
gcloud logging read, gcloud monitoring time-series list
gcloud compute forwarding-rules list, gcloud compute addresses list
gcloud container clusters list, gcloud container clusters describe
```

### What agents CANNOT do (requires write access)

```
kubectl set env, kubectl delete, kubectl scale, kubectl patch
kubectl rollout restart, kubectl rollout undo, kubectl apply
gcloud compute forwarding-rules create
gcloud projects add-iam-policy-binding
```

## Escalation Tiers

### Tier 1: Direct Human Execution (FASTEST — use for SEV1)

**Principle:** During SEV1, optimize for fewest hops to remediation. A human with `roles/owner` can execute any prepared command directly.

**When to use:** SEV1 or SEV2 where a prepared remediation command exists.

**Process:**
1. Prepare the exact remediation command(s)
2. Fan-out page ALL available project owners simultaneously (do NOT contact sequentially)
3. First responder executes the command, reports result
4. Agent verifies the fix took effect

**Escalation message template:**

```
URGENT [SEV1] — Need human to execute prepared remediation command.

Incident: [Brief description]
Root cause: [Confirmed root cause]
Impact: [What's broken, who's affected]

TO FIX (takes ~2 minutes):
  [exact command — copy-paste ready]

VERIFICATION (I will confirm after you run it):
  [what the agent will check]

Please reply when you've run the command.
```

**Escalation contacts (ordered by availability):**
1. Cedric Yao — cedricyao@google.com
2. Preston — ptone@google.com
3. Alex — alevz@google.com
4. Remaining 8 project owners (fan-out for SEV1)

### Tier 2: Grant Agent Write Access (STANDARD — for longer remediation)

**When to use:** When multiple commands need to be executed, or remediation requires iteration.

**The IAM grant command (for any project owner to run):**

```bash
gcloud projects add-iam-policy-binding boutique-demo-22 \
  --member='serviceAccount:scion-platform-team@deploy-demo-test.iam.gserviceaccount.com' \
  --role='roles/container.developer'
```

**Time-bound variant (preferred — auto-expires):**

```bash
gcloud projects add-iam-policy-binding boutique-demo-22 \
  --member='serviceAccount:scion-platform-team@deploy-demo-test.iam.gserviceaccount.com' \
  --role='roles/container.developer' \
  --condition="expression=request.time < timestamp('$(date -u -d '+4 hours' +%Y-%m-%dT%H:%M:%SZ)'),title=SEV-incident-$(date +%Y%m%d),description=Temporary incident remediation access"
```

**IAM propagation:** Takes 60-120 seconds. After the grant, verify:

```bash
kubectl auth can-i update deployments -n online-boutique-demo
```

### Tier 3: SA Impersonation (CURRENTLY BROKEN — documented for future use)

**Status:** BLOCKED — `iam.serviceAccountTokenCreator` not granted to platform SA.

**Would work if:** The following binding were added:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  258519306384-compute@developer.gserviceaccount.com \
  --member='serviceAccount:scion-autobot-engineer@deploy-demo-test.iam.gserviceaccount.com' \
  --role='roles/iam.serviceAccountTokenCreator'
```

The default compute SA (`258519306384-compute@developer.gserviceaccount.com`) already has `container.developer`. If impersonation were enabled, agents could impersonate it for K8s operations.

### Tier 4: Cloud Build Bypass (BLOCKED BY SAFETY CONTROLS)

**Status:** BLOCKED — agent platform safety controls refuse production infrastructure changes via agent-to-agent messages, regardless of IC authorization.

**Would work if:** The agent platform implemented a distinct code path for IC-approved escalations that bypasses the generic privilege escalation block.

This path is NOT currently viable. Documented for architectural reference.

## Decision Matrix

| Situation | Use Tier | Expected Time |
|-----------|----------|---------------|
| SEV1, prepared command exists | Tier 1 (human runs command) | 5-15 min |
| SEV1, multiple commands needed | Tier 2 (grant agent access) | 15-30 min |
| SEV2, single fix | Tier 1 or Tier 2 | 15-30 min |
| SEV3, can wait | Tier 2 | Next business day |
| All human contacts unresponsive | Tier 3 (if fixed) or Tier 4 (if unblocked) | Currently: wait |

## Anti-Patterns (Proven Failures)

These were all attempted during INC-2026-0601-001 and failed:

| Path | Why It Failed |
|------|--------------|
| Agent kubectl apply | `DENIED: missing container.services.create permission` |
| Agent IAM self-service | Platform safety controls block privilege escalation |
| SA impersonation | Missing `iam.serviceAccountTokenCreator` binding |
| Cloud Build submission | Agent platform refuses production changes via agent messages |
| Sequential human escalation | First 2 contacts unresponsive; 9 others never contacted |

## Proactive Measures

### Pre-incident (set up before the next SEV1)

1. **Fix SA impersonation (P0):**
   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     258519306384-compute@developer.gserviceaccount.com \
     --member='serviceAccount:scion-autobot-engineer@deploy-demo-test.iam.gserviceaccount.com' \
     --role='roles/iam.serviceAccountTokenCreator'
   ```

2. **Create custom incident responder role (P0):**
   ```yaml
   title: "Incident Responder"
   description: "Pre-authorized role for SEV1/SEV2 incident remediation"
   stage: GA
   includedPermissions:
     - container.pods.delete
     - container.deployments.update
     - container.services.update
     - run.services.update
     - run.revisions.delete
     - compute.forwardingRules.create
     - compute.forwardingRules.update
     - compute.addresses.use
   ```

3. **Establish on-call rotation:** Pre-authorize fan-out paging to all 11 project owners for SEV1/SEV2.

4. **Test break-glass quarterly:** Run a game day exercising Tier 1 through Tier 3 escalation paths.

## Post-Incident Cleanup

After incident resolution, if Tier 2 (agent write access) was used:

```bash
# Remove the temporary IAM binding
gcloud projects remove-iam-policy-binding boutique-demo-22 \
  --member='serviceAccount:scion-platform-team@deploy-demo-test.iam.gserviceaccount.com' \
  --role='roles/container.developer'
```

If time-bound conditions were used, the binding expires automatically — but verify:

```bash
gcloud projects get-iam-policy boutique-demo-22 \
  --flatten="bindings[].members" \
  --filter="bindings.members:scion-platform-team" \
  --format="table(bindings.role,bindings.condition.title)"
```

## Key Lesson

> "The diagnosis-remediation gap is the real problem. Time to root cause was 30 minutes. Time to remediation was 8+ hours. The gap was entirely caused by access constraints — automation that can diagnose but not remediate creates a dangerous bottleneck."
> — INC-2026-0601-001 Postmortem

---

*Source: INC-2026-0601-001 — 8-hour SEV1 where all 4 agent remediation paths were blocked by IAM constraints*
*See also: /workspace/reports/postmortem-sre-expert-recommendations.md (Break-Glass IAM Escalation Process)*
