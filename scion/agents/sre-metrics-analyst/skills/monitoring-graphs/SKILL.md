---
name: monitoring-graphs
description: >-
  Generate annotated incident timeline graphs from Cloud Monitoring metrics data.
  Use when you need to create visual representations of metric anomalies for
  incident reports or to communicate findings.
---

# Monitoring Graphs

Create clear, annotated graphs from metrics data to visualize incidents.

## Data Integrity Rules

- **NEVER fabricate data.** Only plot real values from Cloud Monitoring.
- If data points are missing during a blackout, fill gaps with 0 — do not interpolate.
- Always use UTC timestamps.

## Graph Types

### Single Metric Timeline
Show one metric over the incident window with annotations for key events (incident start, detection, mitigation, resolution).

### Dual-Axis Correlation
Plot two related metrics (e.g., error rate + latency) on the same time axis to show correlation:

```python
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(15, 10), sharex=True)
ax1.plot(timestamps, error_rate, color='#d93025', label='Error Rate')
ax2.plot(timestamps, latency_p95, color='#1a73e8', label='p95 Latency')
```

### Sparklines
For compact metric summaries in text reports, generate ASCII sparklines from CSV data to show the shape of a metric over time.

## Annotation Colors

| Color | Hex | Meaning |
|-------|-----|---------|
| Red | `#d93025` | Incident start/end, breakage |
| Yellow | `#f9ab00` | Detection, alert triggered |
| Green | `#1e8e3e` | Mitigation applied, resolution |
| Blue | `#1a73e8` | Normal traffic/baseline |

## Best Practices

- Always label axes including units and timezone
- Include the time range in the graph title
- Never overwrite previous graph versions — use _rev1, _rev2 suffixes
- For time correlation across graphs, use a shared x-axis with consistent scale
