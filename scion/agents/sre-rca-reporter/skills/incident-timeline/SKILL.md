---
name: incident-timeline
description: >-
  Build and format incident timelines from multiple data sources. Use when constructing
  the chronological sequence of events during an incident from log, metric, trace,
  and deployment evidence.
---

# Incident Timeline Construction

Build accurate incident timelines by merging evidence from multiple investigation agents.

## Data Source Priority

When timestamps conflict between sources, use this priority order:
1. **Metrics timestamps** — Cloud Monitoring has the most precise time alignment
2. **Log timestamps** — Cloud Logging preserves the original event time
3. **Trace timestamps** — Cloud Trace span start/end times
4. **Audit log timestamps** — For deployment/configuration changes
5. **Human-reported times** — Least precise, use as approximate bounds only

## Timeline Construction Steps

1. **Collect all timestamped events** from each investigation agent's findings
2. **Normalize to UTC** — convert all timestamps to UTC
3. **Merge and deduplicate** — combine events from all sources, removing duplicates
4. **Sort chronologically** — order all events by timestamp
5. **Identify milestones** — mark the 4 required milestones:
   - Start of Incident (first anomalous signal)
   - Incident Detected (first alert or human awareness)
   - Mitigation Applied (first remediation action)
   - End of Incident (metrics return to baseline)
6. **Fill gaps** — if there are unexplained gaps >5 minutes, note them explicitly

## Deriving Key Metrics

From the timeline, calculate:
- **Time to Detect (TTD):** Detected - Start
- **Time to Mitigate (TTM):** Mitigated - Detected
- **Total Duration:** End - Start
- **Time to Resolve (TTR):** End - Detected

## Format

```markdown
Day: **YYYY-MM-DD** TZ=UTC
* `HH:MM:SS`: First anomalous metric detected in SERVICE <== <span style="color:red">Start of Incident</span>
* `HH:MM:SS`: Error logs begin appearing in SERVICE
* `HH:MM:SS`: Alert policy fires (but no notification channel)
* `HH:MM:SS`: Investigation agent spawned <== <span style="color:red">Incident Detected</span>
* `HH:MM:SS`: Root cause identified as X
* `HH:MM:SS`: Remediation command executed <== <span style="color:red">Mitigation Applied</span>
* `HH:MM:SS`: Metrics return to baseline <== <span style="color:red">End of Incident</span>
```
