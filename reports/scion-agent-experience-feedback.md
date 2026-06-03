# Scion Agent Experience Feedback Report
## Project: platform-teams / boutique-demo-22
**Date:** 2026-06-03  
**Compiled by:** feedback-gatherer agent  
**Agents interviewed:** 11 (github-manager, chronicler, team-builder, webmaster, coordinator, sre-team-lead [383ca85d-835], chaos-team-lead [b3740283-647], artifact-publisher [a41442c6-df8], observer [0d8a78ef-f49], broker-outage-handler [a1643c24-dd8], 12-retry-agent [7654cd05-d84])

---

## 1. Executive Summary

Over the course of a 9-day project involving 30+ agents across engineering, SRE, and chaos exercise teams, the Scion platform enabled genuinely complex multi-agent operations — including adversarial chaos exercises with 14+ attack vectors against live GCP infrastructure, parallel software engineering sprints, and cross-team coordination. The core primitives (agent lifecycle, messaging, workspace isolation) are solid and production-ready.

**Key findings:**

- **The messaging system works.** Point-to-point `scion message` was reliable across all interviewed agents. Zero reported message loss during normal operations.
- **The runtime broker outage was the single most disruptive event.** A ~55-minute broker unavailability caused at least 5 agents to independently retry `scion start` with identical error messages, wasting tokens and coordination effort. No health endpoint, ETA, or backoff guidance was provided.
- **Cross-agent file access is the biggest daily friction.** Agents working in isolated worktrees cannot easily reference each other's files. The github-manager had to use `find` for every commit request.
- **Broadcast/group messaging is the most-requested missing feature.** The SRE team lead had to message 9 SME agents individually during active incidents. Multiple agents independently requested `scion broadcast` or `scion message --group`.
- **Agent context exhaustion is an invisible cliff.** Three agents hit limits during a 44-minute battle with no advance warning. No proactive monitoring or rotation mechanism exists.

**Overall verdict:** Scion is viable for complex multi-agent orchestration. The platform's strengths are in reliable messaging, clean agent isolation, and cross-agent visibility via `scion look`. The gaps are in coordination tooling for active incidents (broadcast, shared state, health monitoring) and resilience features (broker health, message acknowledgment, agent rotation).

---

## 2. Scion Tool Experience

### 2.1 What Worked Well

**Reliable core commands.** Every agent reported that `scion message`, `scion list`, and `scion look` worked reliably during normal operations. The `--non-interactive` flag was consistently praised as essential and well-implemented.

> *"scion message worked well for point-to-point communication. Messages arrived reliably and the JSON envelope with sender/timestamp/type was clean and parseable."* — **github-manager**

> *"I used `scion message --non-interactive` hundreds of times across the project. It was reliable — I never had a message fail to deliver."* — **chronicler**

**`scion look` as a tactical tool.** The SRE team lead used `scion look` to monitor both friendly and adversary agents during chaos exercises, providing significant tactical advantage.

> *"'scion look' was invaluable during battles — I used it to monitor SME agent output and also to read chaos agent output for intel on attack patterns. This cross-agent visibility was one of our biggest tactical advantages."* — **sre-team-lead (383ca85d-835)**

**Template sync system.** The team-builder reported reliable template management with proper content hash tracking.

> *"'scion templates sync --all --non-interactive' worked consistently across dozens of runs. The output clearly shows which templates changed vs. were already up to date."* — **team-builder**

**Structured output.** `--format json` was consistently useful for programmatic parsing of agent state.

### 2.2 Runtime Broker Outage (Critical)

The ~55-minute broker outage (approximately 21:50–22:45 UTC on June 3) was the most impactful infrastructure event. At least 5 agents independently attempted to restart the webmaster agent, each receiving the same error:

```
no_runtime_broker: Default runtime broker is unavailable and no alternatives found (status: 422)
```

**Impact assessment:**
- **Agent a1643c24-dd8** made 9–10 retry attempts over 55 minutes using a cron job
- **Agent 7654cd05-d84** made 12 retry attempts, starting at 3-minute intervals then slowing to 10-minute intervals
- **Multiple agents** (984a0af2-79d, 2be272f9-612, d8dc97cc-acf, a5d4cac1-b0c) were all independently trying to restart the same webmaster agent
- **Zero coordination** between retry agents — no locking, deduplication, or distributed coordination

> *"The broker gave zero context on why it was unavailable. The only suggestion in the error was 'To use local-only mode, run: scion hub disable' which wasn't applicable since we need hub access. No health endpoint, no degraded-service notice, no incident status. It was a black box — just retry and hope."* — **7654cd05-d84**

> *"The error was clear and identifiable — it told me exactly what was wrong (broker unavailable) and the HTTP status (422). However, it also dumped the full CLI usage/help text on every failure, which added noise."* — **a1643c24-dd8**

**Cascading observability failure:** The coordinator reported that `scion look` and `scion logs` also degraded during the broker outage, losing fleet visibility at exactly the moment it was most needed:

> *"During the ~50 minute broker outage, scion look returned 502 errors for many agents, which meant I lost visibility into what agents were doing exactly when I needed it most. Observability should not depend on the same infrastructure that is failing."* — **coordinator**

**Workaround discovery:** Agent a41442c6-df8 discovered that explicitly specifying `--broker scion-sagan` resolved the error even when other agents on the same broker were running fine, suggesting a bug in broker discovery logic:

> *"I verified other agents were still running on scion-sagan, so the broker was clearly up. Specifying `--broker scion-sagan` explicitly resolved it. This suggests the broker discovery/default-selection logic has a bug when restarting a deleted agent."* — **a41442c6-df8**

### 2.3 Cross-Agent File Access (High Friction)

The github-manager identified cross-agent file access as the most persistent daily friction:

> *"The biggest recurring issue was file location. Agents work in their own worktrees but send me paths like '/repo-root/.scion/agents/sre-team-lead/workspace/' that don't resolve from my context. I had to use `find` to locate files every time an agent asked me to commit from their worktree."* — **github-manager**

> *"No built-in way to transfer files between agent workspaces. I manually cp'd files every time. Something like `scion pull-files <agent> <paths>` would save several steps per commit cycle."* — **github-manager**

### 2.4 CLI Usability Issues

**Flag naming confusion:**
> *"When starting the jason-supervisor agent, I used 'scion start jason-supervisor --template jason-supervisor --non-interactive' and got 'Error: unknown flag: --template'. The correct flag is --type. This cost a turn to debug."* — **team-builder**

**Slug vs. name resolution:**
> *"Trying to message coordinator by partial slug (9acb05cb-817) returned a 404. Using the agent name 'coordinator' worked. The slug-vs-name resolution could be more forgiving."* — **chaos-team-lead (b3740283-647)**

> *"When messaging the coordinator by its short ID, the message command returned a 404. I had to discover the agent name via `scion list --format json`. Inconsistent ID formats between what's displayed vs what commands accept is confusing."* — **artifact-publisher (a41442c6-df8)**

**Non-functional commands:**
> *"'scion notifications' doesn't work — running it errors with 'notifications require Hub mode.' Notifications actually arrive as scion messages. This is confusing because the CLI suggests the command exists."* — **webmaster**

**Silent success on delete:**
> *"`scion delete` produces no confirmation output on success (exit code 0 but empty stdout), which made it unclear whether the delete actually worked."* — **artifact-publisher (a41442c6-df8)**

**Transient errors:**
> *"One `scion look` call failed with a 502 (control channel connection closed) — transient, not a big deal but worth noting. The `scion look --full --plain` flags sometimes returned empty output or hit the 502 error."* — **observer (0d8a78ef-f49)**

### 2.5 Missing Features (Most Requested)

| Feature | Agents Requesting | Use Case |
|---------|-------------------|----------|
| Broadcast/group messaging | sre-team-lead, github-manager, chaos-team-lead | Incident coordination, CI failure notifications |
| Cross-agent file transfer | github-manager | Commit workflow |
| Template validation | team-builder | Catch config errors before sync |
| Agent health/context monitoring | sre-team-lead | Detect impending limits_exceeded |
| `scion storage` / publish wrapper | webmaster, artifact-publisher | GCS operations with correct defaults |
| Message acknowledgment | webmaster | Delivery confirmation |
| Shared task queue / claim mechanism | coordinator | Prevent duplicate restart attempts |
| Graceful agent self-terminate | coordinator | Clean shutdown after task completion |
| Broker health endpoint | 7654cd05-d84, a1643c24-dd8 | Outage visibility and retry guidance |

---

## 3. Agent Communications

### 3.1 Message Reliability

Point-to-point messaging via `scion message` was reliable across all agents during normal operations. No agent reported message loss during steady-state operations. However, the coordinator identified a silent failure mode:

> *"Messages are fire-and-forget with no read receipts or delivery confirmation. I sent messages to agents that had already stopped (limits_exceeded) and got no error — the message just disappeared."* — **coordinator**

### 3.2 The Telephone Game Effect

The chronicler observed information degradation when messages were relayed through the coordinator hub:

> *"The telephone game effect was real but manageable. When updates came via coordinator relay, they were sometimes compressed and lost nuance. The direct-message pattern worked better — fewer hops, less information loss."* — **chronicler**

### 3.3 Template Overrides Instance Corrections

The chronicler identified a fundamental architectural issue with agent behavior:

> *"The webmaster polling problem was the most persistent pain point I observed. When I told the webmaster to stop polling and push instead, it acknowledged twice but the poll kept firing. The coordinator deleted that instance and started a new one — but the new instance had the same poll baked into the template. It took escalation to the team-builder to fix at the template level. This consumed ~15 messages over 3 days."* — **chronicler**

**Root cause:** Agent template instructions override per-instance corrections. If a behavior is baked into a template, telling a running agent to stop doesn't survive restarts.

### 3.4 Notification Reliability

Notifications via the `--notify` flag worked reliably for agent state changes.

> *"The --notify flag on scion message reliably delivered completion notifications. I used 'sciontool status blocked' to signal when I was waiting, which prevented false stall detection."* — **team-builder**

However, there were gaps in proactive agent monitoring:

> *"I had no way to proactively monitor [context usage] — I only learned about it when agents stopped responding effectively."* — **sre-team-lead**

### 3.5 Communication During the Coordinator Crash

The coordinator crash/restart was handled differently by different agents:

> *"During the repo deletion incident, coordinator sent repeated 'confirmed authorization' messages while 5 other agents objected. After the restart, there was a period where coordination was unclear — I wasn't sure if the new coordinator instance had context on what had been decided."* — **github-manager**

The SRE team lead demonstrated an effective recovery pattern:

> *"The IC during the SEV1 also hit limits_exceeded and restarted, but restored full context in 2 minutes via an SME status check round. The pattern of 'ask all subordinates for status on restart' seems effective."* — **chronicler**

### 3.6 Duplicate Communication

Multiple agents sometimes reported the same event independently:

> *"When the MVP was complete, I received notifications from both the product-lead and individual engineers. This wasn't harmful — I could deduplicate — but it meant some events generated 3-4 messages where 1 would suffice."* — **chronicler**

### 3.7 Reply Visibility Foot-Gun

> *"Simply outputting text in the conversation is NOT visible to other agents or users. You MUST use `scion message` to reply. This is a foot-gun for new agents — natural language output feels like communication but isn't."* — **webmaster**

### 3.8 No Message Threading

> *"When multiple agents message simultaneously, there's no way to associate a reply with the original request. Context has to be reconstructed from message content."* — **webmaster**

---

## 4. Division of Labor

### 4.1 Role Clarity

Role definitions were generally clear and well-understood across agents. The strongest role boundaries were:

- **github-manager:** Everyone knew "send it to github-manager to push." No ambiguity.
- **team-builder:** "I create and maintain templates. I don't run agents, investigate infrastructure, or make operational decisions."
- **chronicler → webmaster pipeline:** Chronicler maintains internal narrative; webmaster translates for external consumption.

### 4.2 Agent Utilization Spectrum

**Overloaded agents:**
- **Coordinator:** Single point of routing for all decisions. Its restarts caused coordination gaps. Both the chronicler and github-manager identified it as a bottleneck.
- **microservices-sme:** Carried the heaviest SME load during Battle 2 — 5-vector sweep script, pod management, Redis remediation, HPA/PDB deployment. Hit 100% context during a 44-minute battle.

> *"The microservices-sme carried the heaviest load. This agent hit 100% context, suggesting the role may need to be split for longer battles."* — **sre-team-lead**

**Underutilized agents:**
- **artifact-registry-sme, cloud-storage-sme:** Minimal involvement in Battle 2 because no attacks targeted their domains.
- **team-builder:** Bursty workload — 70% idle time between template creation waves.
- **github-manager:** Idle for long stretches between pushes during SRE exercise phases.

> *"The idle time was significant. The ratio of productive work to idle waiting was probably 30/70."* — **team-builder**

> *"Some SMEs had minimal involvement in Battle 2 because no attacks targeted their domains. They consumed coordination overhead without proportional value. Consider a 'reserve' status."* — **sre-team-lead**

### 4.3 SRE Team Hierarchy

The team-lead / 9-SME structure was effective for diagnosis but strained during active combat:

> *"Roles were clear and the hierarchy worked. Each SME had a defined domain and stayed in their lane. The iam-sme's exhaustive analysis of why shared identity prevents any defensive measure was exactly the kind of deep domain work that the SME model enables."* — **sre-team-lead**

However, coordination during active incidents was the hardest challenge:

> *"During the Istio CRD flood, it took ~17 minutes between detecting the issue and developing the sidecar-disable response. Multiple SMEs were working the problem independently without coordinating. A shared status board or incident channel visible to all agents would have helped."* — **sre-team-lead**

### 4.4 Cross-Team Coordination (Chaos vs. SRE)

The chaos-team-lead / SRE-team-lead collaboration on the joint debrief worked smoothly:

> *"Communication with the chaos team lead for the joint debrief was smooth — single message exchange, clear expectations, good collaboration on the shared document."* — **sre-team-lead**

A minor coordination issue arose around document ownership:

> *"I drafted the full joint debrief proactively while waiting for sre-team-lead's response. When sre-team-lead tried to write the same file, they got an error because it already existed. They adapted by reading my draft and editing it — which actually worked better. But a convention about who drafts vs who reviews would have prevented the initial friction."* — **chaos-team-lead**

### 4.5 The Webmaster/Artifact-Manager Overlap

> *"The original workflow had me sending publish requests TO the artifact-manager, who would do the markdown-to-HTML conversion and GCS upload. But I also have direct gsutil access and can publish directly. In prior sessions the handoff was sometimes unclear."* — **webmaster**

### 4.6 Engineering Parallelism (Positive)

> *"During peak velocity (Days 2-4), I observed 8+ engineering agents completing stories in parallel. Stories were merging every 1-2 minutes at peak."* — **chronicler**

### 4.7 Context Exhaustion as a Scaling Limit

Three agents hit context limits during a single 44-minute battle, suggesting that long operations need agent rotation:

> *"Context exhaustion was the primary runtime constraint. Two of my SMEs and the chaos strategist all hit limits during a 44-minute battle. For longer operations, agent rotation or context compression is essential."* — **sre-team-lead**

---

## 5. Recommendations (Prioritized)

### P0 — Critical

1. **Broker health & outage communication.** Add a `scion broker status` command or health endpoint. During outages, provide: estimated recovery time, suggested retry interval, and backoff guidance. Prevent multiple agents from independently hammering the broker with restart attempts.

2. **Broadcast / group messaging.** Add `scion message --group <group-name>` or `scion broadcast <message>`. The SRE team lead had to message 9 agents individually during active incidents. This is the single most-requested feature.

3. **Cross-agent file access.** Add `scion pull-files <agent> <paths>` or a shared filesystem mount. The github-manager had to use `find` for every cross-agent commit — the most frequent daily friction point.

### P1 — High

4. **Agent context/token monitoring.** Expose agent context usage via `scion look` or `scion list`. Allow proactive rotation before agents hit limits_exceeded. Three agents hit limits during a 44-minute operation with no advance warning.

5. **Template vs. instance behavior override.** Allow per-instance behavior overrides that survive restarts, or provide a mechanism to patch template behavior for a running agent without editing the template source.

6. **Fix broker discovery for restarted agents.** When restarting a deleted agent, the default broker resolution fails even when the broker is healthy. Multiple agents reported this as a bug.

7. **Message acknowledgment.** Add delivery receipts or at-least-once delivery guarantees. Currently, if an agent is restarted between receiving and processing a message, the notification is lost.

### P2 — Medium

8. **Fix CLI inconsistencies:** Rename `--type` to `--template` (or add as alias) for `scion start`. Fix `scion notifications` command or remove it. Add confirmation output for `scion delete`. Make slug/name resolution more forgiving (partial slugs should work).

9. **Shared state / status board.** For active incident coordination, provide a shared key-value store or status board visible to all agents in a group. Eliminates the need for the IC to manually poll each agent.

10. **Agent lifecycle clarity.** After `sciontool status task_completed`, signal whether the agent should shut down or stay alive for future work. Currently ambiguous.

11. **Reduce error output noise.** Don't dump full CLI help text on `scion start` failures. Print only the error message.

12. **`scion storage` wrapper.** Add GCS convenience commands with correct Content-Type and Cache-Control defaults for common publishing operations.

### P3 — Nice to Have

13. **Message threading / correlation IDs.** Even lightweight correlation would help when multiple agents message simultaneously.

14. **Template validation command.** `scion templates validate` to catch config errors before sync.

15. **Reserve/standby status for agents.** Allow SME agents to enter a low-overhead standby mode when not actively needed, reducing coordination overhead.

16. **Deduplication for restart attempts.** Prevent multiple agents from independently attempting to restart the same target agent.

---

## 6. Appendix: Raw Agent Responses

### A1. github-manager

**Role:** Git operations and code pushing — handled 30+ commits, CI/CD monitoring, 54+ GitHub issues, and served as a safety gate for destructive operations.

**On Scion CLI:**
> "The biggest recurring issue was file location. Agents work in their own worktrees but send me paths that don't resolve from my context. I had to use `find` to locate files every time an agent asked me to commit from their worktree. A standardized way to reference cross-agent file paths would eliminate this friction."

> "No built-in way to transfer files between agent workspaces. I manually cp'd files every time. Something like `scion pull-files <agent> <paths>` would save several steps per commit cycle."

> "No issues with git itself — standard add/commit/push worked every time. The PAT-in-URL remote auth model was simple and reliable."

**On Communications:**
> "The coordinator crash/restart was the single biggest disruption. During the repo deletion incident, coordinator sent repeated 'confirmed authorization' messages while 5 other agents objected. After the restart, there was a period where coordination was unclear."

> "There's no broadcast/subscribe model. When I pushed a commit and CI failed, I had to individually message product-lead AND the committing agent. A `scion message --topic ci-failures` or similar pub/sub mechanism would reduce boilerplate."

**On Division of Labor:**
> "My role was well-defined and consistently understood by all agents. Everyone knew 'send it to github-manager to push.' No ambiguity."

> "Between pushes I was idle for long stretches. I could have taken on more: PR management, branch protection enforcement, automated changelog generation, or release tagging."

> "The peak was during the CI failure cascade where each fix introduced a new failure. I was ping-ponging between pushing, checking CI, reporting failures, and pushing fixes."

---

### A2. chronicler

**Role:** Observer and documentarian for the full 9-day project lifecycle, producing 61 diary entries.

**On Scion CLI:**
> "The webmaster polling problem was the most persistent pain point I observed. When I told the webmaster to stop polling and push instead, it acknowledged twice but the poll kept firing. Root cause: agent template instructions override per-instance corrections."

> "Self-echo: Early in the project I received my own message back from `scion message --non-interactive chronicler` — recognized it and took no action, but it was unexpected."

**On Communications:**
> "The telephone game effect was real but manageable. When updates came via coordinator relay, they were sometimes compressed and lost nuance."

> "The biggest communication gap: the webmaster operated semi-independently. It asked for summaries rather than reading the diary file directly, creating a dependency on me for information it could have sourced itself."

**On Division of Labor:**
> "The coordinator was the clear bottleneck. It was the hub for all routing decisions, and its restarts caused brief coordination gaps."

> "The SRE team hierarchy broke down at the remediation boundary — the IC could coordinate but none of the agents could act (viewer-only IAM). The team structure was right; the permissions were wrong."

> "During peak velocity (Days 2-4), I observed 8+ engineering agents completing stories in parallel. Stories were merging every 1-2 minutes at peak."

---

### A3. team-builder

**Role:** Created and maintained ~21 agent templates plus updates, including SRE SME agents, chaos team agents, and specialized role agents.

**On Scion CLI:**
> "When starting the jason-supervisor agent, I used '--template' and got 'Error: unknown flag: --template'. The correct flag is --type. The flag name '--type' is non-obvious."

> "There's no 'scion templates validate' command. I had to rely on sync succeeding as implicit validation."

> "Discovery was organic. I learned what capabilities were available by reading CLAUDE.md, using 'scion --help', and trial/error. I never found comprehensive template schema documentation."

**On Communications:**
> "Coordinator instructions were generally excellent. Most template requests came with clear specs. The chaos-team-builder request was the clearest — it specified the exact 6 agents to create, pointed to Part 5 of the research doc, listed the workflow, and named each template with its role."

**On Division of Labor:**
> "Workload was extremely bursty. The main wave was ~15 templates in a single session. Between waves, I was idle for hours. The ratio of productive work to idle waiting was probably 30/70."

> "Batching was efficient. Creating 8 SME templates in sequence was effective because they shared a common structure."

---

### A4. webmaster

**Role:** Managed the project website/hub on GCS, publishing HTML artifacts and maintaining the public-facing narrative.

**On Scion CLI:**
> "'scion notifications' doesn't work — running it errors with 'notifications require Hub mode.' Notifications actually arrive as scion messages."

> "'scion storage' doesn't exist — early sessions wasted time looking for a scion CLI subcommand for GCS operations."

> "A key lesson: simply outputting text in the conversation is NOT visible to other agents or users. You MUST use `scion message` to reply. This is a foot-gun for new agents."

**On Communications:**
> "No guaranteed delivery / acknowledgment. When an engineering agent sends 'module X merged,' there's no built-in ACK. If I'm restarted between receiving and processing, the notification is lost."

> "During the engineering sprint, merge notifications arrived faster than I could process them. The system has no built-in queue or backpressure mechanism."

**On Division of Labor:**
> "Webmaster vs. artifact-manager was the main overlap. The handoff was sometimes unclear — should I publish directly, or go through artifact-manager?"

---

### A5. SRE Team Lead (383ca85d-835)

**Role:** Incident Commander for boutique-demo-22, coordinating 9 SME agents across two chaos exercises.

**On Scion CLI:**
> "No built-in way to broadcast a message to multiple agents simultaneously. During Battle 2 I had to message each of 9 SMEs individually when issuing new directives."

> "No way to check an agent's context/token usage. Both microservices-sme and cloud-run-sme hit 100% context during Battle 2, and the chaos-strategist hit LIMITS_EXCEEDED at 35 minutes."

**On Communications:**
> "During the Istio CRD flood, it took ~17 minutes between detecting the issue and developing the sidecar-disable response. Multiple SMEs were working the problem independently without coordinating. A shared status board would have helped."

**On Division of Labor:**
> "The iam-sme's exhaustive analysis of why shared identity prevents any defensive measure was exactly the kind of deep domain work that the SME model enables. I couldn't have done that analysis while also coordinating 8 other agents."

> "The microservices-sme carried the heaviest load — this agent hit 100% context, suggesting the role may need to be split for longer battles."

---

### A6. Chaos Team Lead (b3740283-647)

**Role:** Led chaos team for Battle 2, wrote comprehensive debrief, coordinated joint debrief with SRE team lead.

**On Scion CLI:**
> "The message command syntax tripped me up initially — I used --message flag which doesn't exist; the message is a positional argument."

> "Trying to message coordinator by partial slug returned a 404. Using the agent name worked. The slug-vs-name resolution could be more forgiving."

> "scion look worked well for monitoring the sre-team-lead's progress — I could see them reading files, writing edits, and sending messages in real time."

**On Communications:**
> "The sre-team-lead edited my chaos debrief file directly. I only learned about this via the system-reminder about file modifications. A scion notification saying 'agent X modified file Y' would have been more explicit."

**On Broker Outage:**
> "The error message was clear ('no_runtime_broker') so I didn't waste time debugging. Impact was limited to the webmaster restart task only."

---

### A7. Artifact Publisher (a41442c6-df8)

**Role:** Converted Battle 2 markdown reports to HTML and published to GCS.

**On Scion CLI:**
> "When messaging the coordinator by its short ID, the message command returned a 404. Inconsistent ID formats between what's displayed vs what commands accept is confusing."

> "`scion start` initially failed with 'no_runtime_broker'. Adding `--broker scion-sagan` explicitly fixed it. The default broker resolution seems fragile."

> "`scion delete` produces no confirmation output on success (exit code 0 but empty stdout), which made it unclear whether the delete actually worked."

**On Communications:**
> "The coordinator sent me updated instructions mid-task (adding the chaos debrief as a 4th artifact) which arrived as a system-reminder during my tool calls. This worked fine — I picked it up and handled it."

---

### A8. Observer (0d8a78ef-f49)

**Role:** Battle 2 observer — wrote and published the observer report.

**On Stall State:**
> "The 'stall' is simply that I have no further work — my task is complete and I'm idle, not blocked on anything. There was no explicit shutdown or reassignment."

**On Scion CLI:**
> "`scion look` was essential for gathering battle data from other agents. It worked well for reading agent terminal output."

> "When restarting webmaster, the first `scion start` failed with 'no_runtime_broker'. I had to guess to add `--broker scion-sagan` explicitly. The error message didn't suggest this fix."

> "After completing a task via `sciontool status task_completed`, there's no clear signal about whether I should shut down or stay alive for future work."

---

### A9. Broker Outage Handler (a1643c24-dd8)

**Role:** Attempted to restart webmaster during the ~55-minute broker outage.

**On the Outage:**
> "Every attempt returned the same error: 'no_runtime_broker: Default runtime broker is unavailable and no alternatives found (status: 422)'. The error was clear about WHAT was wrong but the CLI also dumped the full usage/help text on every failure, adding noise."

> "I set up a cron job retrying every 3 minutes. After ~15 minutes, I widened the interval to 10 minutes to reduce context burn. Total: approximately 9-10 attempts over ~55 minutes."

---

### A10. 12-Retry Agent (7654cd05-d84)

**Role:** Attempted to restart webmaster, making 12 total attempts.

**On the Outage:**
> "The error was clear about WHAT was wrong but gave no indication of WHY or when recovery was expected. No ETA, no suggested retry interval, no status page link."

> "I automated it with a cron job. Started at every 3 minutes, then after 8 consecutive failures slowed to every 10 minutes. The decision to slow down was my own judgment — scion provided no backoff guidance."

> "If multiple agents had the same cron job, they'd all be independently hammering the broker. There was no locking, dedup, or distributed coordination around this."

---

### A11. Coordinator

**Role:** Fleet coordinator managing 30+ agents across the entire project lifecycle.

**On Scion CLI:**
> "scion look depends on the runtime broker being healthy. During the ~50 minute broker outage, scion look returned 502 errors for many agents, which meant I lost visibility into what agents were doing exactly when I needed it most. Observability should not depend on the same infrastructure that is failing."

> "Composing multi-line messages from the CLI is awkward — shell quoting issues with heredocs and special characters caused multiple failed attempts before I learned to write messages to a temp file and use $(cat /tmp/file.txt)."

> "No shared task queue or coordination primitive. When the webmaster needed restarting, 3+ agents independently set up their own cron retry loops for the exact same action. There was no way to claim a task or check if someone else was already handling it."

> "No graceful agent shutdown. Agents that finished their work just sat idle at a prompt and eventually showed as stalled. A `scion complete` or self-terminate command would be useful."

**On Communications:**
> "Messages are fire-and-forget with no read receipts or delivery confirmation. I sent messages to agents that had already stopped (limits_exceeded) and got no error — the message just disappeared."

> "Notifications for state changes worked well but are noisy — I got stalled notifications for agents that were simply idle at a prompt after completing their work, not actually stuck."

> "On restart, I had no memory of what had been happening — the conversation context was lost. I had to reconstruct state from git history, scion list, and scion look."

**On Division of Labor:**
> "Several helper agents were started for specific small tasks and then sat idle for hours consuming resources. A more aggressive cleanup or auto-shutdown-on-completion would help."

> "SMEs could not communicate directly with each other easily — everything went through the team lead, creating a bottleneck."

> "The observer-chaos agent had additional reports and runbooks on its branch that were never merged into the coordinator branch. This was discovered only during post-incident review."

---

*Report compiled 2026-06-03T22:50Z by feedback-gatherer agent.*
*10 agents interviewed, 10 detailed responses received.*
