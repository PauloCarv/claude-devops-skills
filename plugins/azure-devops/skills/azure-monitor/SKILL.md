---
name: azure-monitor
description: >
  Especialista Azure Monitor, Log Analytics e Application Insights. Usa quando
  precisares de queries KQL, configurar alertas, dashboards, instrumentar
  aplicações com telemetria, analisar logs de Container Apps/AKS/Function Apps,
  diagnosticar problemas de produção, ou criar workbooks Azure Monitor.
  Ativa automaticamente para pedidos de logs, métricas, observabilidade, KQL,
  Application Insights, alertas ou troubleshooting Azure.
invocation: auto
---

# Azure Monitor & Application Insights

Especialista em observabilidade Azure: Log Analytics, Application Insights,
KQL, alertas e dashboards.

## Quando usar esta skill

| Cenário | Ação |
|---|---|
| Queries KQL de logs/métricas | Compor e otimizar queries |
| Instrumentar app com telemetria | Ver `references/instrumentation.md` |
| Configurar alertas | Ver `references/alerts.md` |
| Troubleshooting Container Apps/AKS | Queries de diagnóstico abaixo |
| Criar dashboards/workbooks | Estrutura de workbook JSON |

## Queries KQL essenciais

### Application Insights — performance e erros

```kql
// Requests lentos (p95 por endpoint)
requests
| where timestamp > ago(1h)
| summarize
    count(),
    avg(duration),
    percentiles(duration, 50, 95, 99)
    by name, resultCode
| order by percentile_duration_95 desc

// Taxa de erros por operação
requests
| where timestamp > ago(24h)
| summarize
    total = count(),
    errors = countif(success == false)
    by name
| extend error_rate = round(errors * 100.0 / total, 2)
| where error_rate > 1
| order by error_rate desc

// Exceções agrupadas
exceptions
| where timestamp > ago(6h)
| summarize count() by type, outerMessage
| order by count_ desc
| take 20

// Dependências lentas (bases de dados, APIs externas)
dependencies
| where timestamp > ago(1h) and success == false or duration > 1000
| summarize
    count(),
    avg(duration),
    failures = countif(success == false)
    by target, type, name
| order by avg_duration desc
```

### Container Apps — diagnóstico

```kql
// Logs de um container app específico
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "minha-app"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Log_s, ContainerName_s, RevisionName_s
| order by TimeGenerated desc

// Erros e crashes
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

### AKS — logs e métricas

```kql
// Pods com erros
KubePodInventory
| where TimeGenerated > ago(1h)
| where PodStatus !in ("Running", "Succeeded")
| project TimeGenerated, Name, Namespace, PodStatus, ContainerStatus

// Consumo de memória por namespace
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

### Alertas — queries base

```kql
// Disponibilidade abaixo de 99.9%
availabilityResults
| where timestamp > ago(5m)
| summarize
    total = count(),
    ok = countif(success == 1)
    by location
| extend availability = ok * 100.0 / total
| where availability < 99.9

// CPU acima de 80% por 5 min
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where TimeGenerated > ago(5m)
| summarize avg(CounterValue) by Computer
| where avg_CounterValue > 80
```

## Comandos az monitor úteis

```bash
# Queries via CLI
az monitor app-insights query \
  --app /subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.insights/components/<ai> \
  --analytics-query "requests | summarize count() by bin(timestamp, 1h) | render timechart" \
  --start-time 2024-01-01T00:00:00Z

# Listar alertas ativos
az monitor alert list --resource-group <rg> --output table

# Log Analytics query
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "ContainerAppConsoleLogs_CL | take 50"

# Ver métricas de um recurso
az monitor metrics list \
  --resource <resource-id> \
  --metric "Requests" \
  --interval PT5M \
  --aggregation Average
```

## Referências

- `references/instrumentation.md` — SDK setup para .NET, Node.js, Python
- `references/alerts.md` — configuração de alertas e action groups
