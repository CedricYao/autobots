---
name: anomaly-detection
description: >-
  Detect anomalies in time-series metrics data. Use when you need to identify
  unusual patterns, spikes, or deviations in Cloud Monitoring metrics during
  incident investigation.
---

# Anomaly Detection

Analyze time-series metrics to identify anomalous data points that correlate with incidents.

## Approach

### 1. Statistical Baseline
For each metric, establish a baseline using recent historical data:
- Calculate mean and standard deviation over a stable window (e.g., same hour yesterday, or 1-hour rolling average)
- Flag points exceeding 2-3 standard deviations as anomalous

### 2. Pattern Recognition
Look for these common incident patterns in metrics:

| Pattern | Signature | Likely Cause |
|---------|-----------|-------------|
| **Step change** | Metric jumps to new level and stays | Configuration change, deployment |
| **Spike** | Brief extreme value, returns to normal | Transient load, GC pause |
| **Ramp** | Gradual increase over time | Memory leak, connection leak |
| **Drop to zero** | Metric stops entirely | Service crash, network partition |
| **Oscillation** | Rapid up/down cycling | CrashLoopBackOff, flapping health check |

### 3. Noise Filtering
- If >5% of data points are flagged, the detection is too noisy — increase the threshold
- Apply smoothing (rolling average, window=5) for noisy metrics before analysis
- Focus on sustained anomalies, not individual outlier points

## Correlation

When analyzing multiple metrics:
- Align time axes precisely
- Look for temporal ordering: which metric deviated first?
- The first metric to deviate is closest to the root cause
- Downstream services typically show anomalies seconds to minutes after the source
