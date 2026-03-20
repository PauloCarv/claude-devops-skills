---
name: azure-monitor
description: >
  Azure Monitor, Log Analytics, and Application Insights specialist. Use when
  you need KQL queries, alert configuration, dashboards, instrumenting
  applications with telemetry, analyzing Container Apps/AKS/Function Apps logs,
  diagnosing production issues, or creating Azure Monitor workbooks.
  Activates automatically for requests about logs, metrics, observability, KQL,
  Application Insights, alerts, or Azure troubleshooting.
invocation: auto
---

# Azure Monitor & Application Insights

Azure observability specialist: Log Analytics, Application Insights,
KQL, alerts, and dashboards.

## When to use this skill

| Scenario | Action |
|---|---|
| KQL queries for logs/metrics | Compose and optimize queries |
| Instrument app with telemetry | See `references/instrumentation.md` |
| Configure alerts | See `references/alerts.md` |
| Troubleshoot Container Apps/AKS | Diagnostic queries below |
| Create dashboards/workbooks | Workbook JSON structure |

## Essential KQL queries

### Application Insights — performance and errors

```kql
// Slow requests (p95 per endpoint)
requests
| where timestamp > ago(1h)
| summarize
    count(),
    avg(duration),
    percentiles(duration, 50, 95, 99)
    by name, resultCode
| order by percentile_duration_95 desc

// Error rate per operation
requests
| where timestamp > ago(24h)
| summarize
    total = count(),
    errors = countif(success == false)
    by name
| extend error_rate = round(errors * 100.0 / total, 2)
| where error_rate > 1
| order by error_rate desc

// Grouped exceptions
exceptions
| where timestamp > ago(6h)
| summarize count() by type, outerMessage
| order by count_ desc
| take 20

// Slow dependencies (databases, external APIs)
dependencies
| where timestamp > ago(1h) and success == false or duration > 1000
| summarize
    count(),
    avg(duration),
    failures = countif(success == false)
    by target, type, name
| order by avg_duration desc
```

### Container Apps — diagnostics

```kql
// Logs from a specific container app
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "minha-app"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Log_s, ContainerName_s, RevisionName_s
| order by TimeGenerated desc

// Errors and crashes
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(6h)
| where Reason_s in ("BackOff", "OOMKill", "Error")
| project TimeGenerated, Reason_s, Log_s, ContainerAppName_s
| order by TimeGenerated desc

// Scaling events
ContainerAppSystemLogs_CL
| where Reason_s == "Scaling"
| summarize count() by bin(TimeGenerated, 5m), ContainerAppName_s
| render timechart
```

### AKS — logs and metrics

```kql
// Pods with errors
KubePodInventory
| where TimeGenerated > ago(1h)
| where PodStatus !in ("Running", "Succeeded")
| project TimeGenerated, Name, Namespace, PodStatus, ContainerStatus

// Memory consumption per namespace
KubeNodeInventory
| join KubePodInventory on Computer
| summarize
    avg_memory = avg(MemoryRss),
    max_memory = max(MemoryRss)
    by Namespace1
| order by avg_memory desc

// OOMKill events
KubeEvents
| where Reason == "OOMKilling"
| project TimeGenerated, Name, Message, Namespace
```

### Alerts — base queries

```kql
// Availability below 99.9%
availabilityResults
| where timestamp > ago(5m)
| summarize
    total = count(),
    ok = countif(success == 1)
    by location
| extend availability = ok * 100.0 / total
| where availability < 99.9

// CPU above 80% for 5 min
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where TimeGenerated > ago(5m)
| summarize avg(CounterValue) by Computer
| where avg_CounterValue > 80
```

## Useful az monitor commands

```bash
# Queries via CLI
az monitor app-insights query \
  --app /subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.insights/components/<ai> \
  --analytics-query "requests | summarize count() by bin(timestamp, 1h) | render timechart" \
  --start-time 2024-01-01T00:00:00Z

# List active alerts
az monitor alert list --resource-group <rg> --output table

# Log Analytics query
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "ContainerAppConsoleLogs_CL | take 50"

# View metrics for a resource
az monitor metrics list \
  --resource <resource-id> \
  --metric "Requests" \
  --interval PT5M \
  --aggregation Average
```

## References

- `references/instrumentation.md` — SDK setup for .NET, Node.js, Python
- `references/alerts.md` — alert configuration and action groups
