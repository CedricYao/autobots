# Runbook: RB-007 — Shared Service Account Attack Response
## Trigger: Hostile actions detected from scion-platform-team@deploy-demo-test SA

### Overview
The SRE team and chaos team share the same SA. This runbook documents how to respond to attacks that use our own identity, since we cannot restrict the SA without breaking ourselves.

### The Problem
- Both teams authenticate as: `scion-platform-team@deploy-demo-test.iam.gserviceaccount.com`
- SA has `roles/editor` which grants `run.services.update`, `iam.serviceAccounts.actAs`, and broad write access
- Delegation chain: `scion-sagan-sa -> compute-system -> scion-platform-team`
- Cannot downgrade to `roles/viewer` without losing our own remediation capability

### Detection Strategy (Detective Controls Only)
Since prevention is not possible with shared identity:

1. **Audit log monitoring** (2-min cadence):
   ```bash
   gcloud logging read "protoPayload.methodName=~'run.services' AND \
     protoPayload.authenticationInfo.principalEmail='scion-platform-team@deploy-demo-test.iam.gserviceaccount.com'" \
     --project=boutique-demo-22 --freshness=5m --format=json
   ```

2. **Differentiating friend from foe:**
   - Our IP: Check current agent's egress IP
   - Chaos IP: 34.28.203.100 (observed in Battle 1)
   - `from-script/True` in user-agent indicates scripted attack
   - Timing correlation with known SRE operations

3. **Config state verification** (independent of audit logs):
   ```bash
   gcloud run services describe frontend-alt-prod \
     --project=boutique-demo-22 --region=us-west1 \
     --format='value(metadata.generation)'
   ```

### Response
1. Pin traffic to known-good revision (see RB-006)
2. Verify env vars and startup probe on active revision
3. Catalog attack actions from audit logs
4. Continue monitoring at elevated cadence (60s for targeted service)

### Long-Term Fix
**Identity separation** (requires coordinator/admin action):
1. Create `scion-sre-defender@deploy-demo-test` with `roles/editor`
2. Re-authenticate all SRE agents with new SA
3. Downgrade `scion-platform-team` to `roles/viewer`
4. This permanently closes the shared-credential attack vector

### Anti-Forensic Techniques Observed
- Chaos team deleted 2/3 attack-created revisions after the attack
- GCP protects the latest revision from deletion
- **Audit logs are the authoritative forensic record** — always check logs, not just current resource state
