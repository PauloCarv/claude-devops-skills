# Azure Monitor — Alertas e Action Groups

Referência para configurar alertas, action groups e runbooks de resposta.

---

## Tipos de alerta

| Tipo | Quando usar | Latência |
|---|---|---|
| **Metric alert** | CPU, memória, requests, latência | ~1 min |
| **Log alert (KQL)** | Padrões em logs, erros específicos | ~5 min |
| **Activity log alert** | Alterações de recursos, falhas de deploy | ~5 min |
| **Smart detection** | Anomalias automáticas (App Insights) | Automático |
| **Availability test** | Uptime de endpoints HTTP | 1-5 min |

---

## Action Groups

```bash
# Criar action group com email + webhook
az monitor action-group create \
  --name ag-ops-${PROJECT} \
  --resource-group ${RG} \
  --action email ops-email paulo@carvalho.ws \
  --action webhook teams-webhook https://outlook.office.com/webhook/...

# Listar action groups
az monitor action-group list --resource-group ${RG} -o table

# Testar action group
az monitor action-group test \
  --name ag-ops-${PROJECT} \
  --resource-group ${RG} \
  --alert-type serviceUri
```

### Action group via Terraform

```hcl
resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-ops-${var.project}"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "ops"

  email_receiver {
    name                    = "ops-team"
    email_address           = "ops@empresa.com"
    use_common_alert_schema = true
  }

  webhook_receiver {
    name                    = "teams-webhook"
    service_uri             = var.teams_webhook_url
    use_common_alert_schema = true
  }

  azure_function_receiver {
    name                     = "auto-remediation"
    function_app_resource_id = azurerm_linux_function_app.remediation.id
    function_name            = "HandleAlert"
    http_trigger_url         = "https://${azurerm_linux_function_app.remediation.default_hostname}/api/HandleAlert"
    use_common_alert_schema  = true
  }
}
```

---

## Alertas de métricas — padrões essenciais

### Container Apps

```bash
# Alerta: CPU acima de 80% por 5 min
az monitor metrics alert create \
  --name "aca-cpu-high-${APP}" \
  --resource-group ${RG} \
  --scopes $(az containerapp show -n ${APP} -g ${RG} --query id -o tsv) \
  --condition "avg CpuPercentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action $(az monitor action-group show -n ag-ops-${PROJECT} -g ${RG} --query id -o tsv)

# Alerta: réplicas em zero (scale-to-zero inesperado em prod)
az monitor metrics alert create \
  --name "aca-replicas-zero-${APP}" \
  --resource-group ${RG} \
  --scopes $(az containerapp show -n ${APP} -g ${RG} --query id -o tsv) \
  --condition "avg Replicas < 1" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1
```

### AKS

```bash
# Alerta: Node CPU acima de 85%
az monitor metrics alert create \
  --name "aks-node-cpu-high" \
  --resource-group ${RG} \
  --scopes $(az aks show -n ${CLUSTER} -g ${RG} --query id -o tsv) \
  --condition "avg node_cpu_usage_percentage > 85" \
  --window-size 10m \
  --evaluation-frequency 5m \
  --severity 2 \
  --action $(az monitor action-group show -n ag-ops-${PROJECT} -g ${RG} --query id -o tsv)

# Alerta: Pods não-prontos
az monitor metrics alert create \
  --name "aks-pods-not-ready" \
  --resource-group ${RG} \
  --scopes $(az aks show -n ${CLUSTER} -g ${RG} --query id -o tsv) \
  --condition "avg kube_pod_status_ready < 1" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1
```

---

## Alertas de log (KQL) — padrões essenciais

### Taxa de erros HTTP > 5%

```bash
az monitor scheduled-query create \
  --name "alert-error-rate-high" \
  --resource-group ${RG} \
  --scopes $(az monitor app-insights component show --app ${AI_NAME} -g ${RG} --query id -o tsv) \
  --condition-query "
    requests
    | where timestamp > ago(5m)
    | summarize total = count(), errors = countif(success == false)
    | extend error_rate = errors * 100.0 / total
    | where error_rate > 5
  " \
  --condition-threshold 0 \
  --condition-operator GreaterThan \
  --condition-time-aggregation Count \
  --window-duration PT5M \
  --evaluation-frequency PT1M \
  --severity 2 \
  --action $(az monitor action-group show -n ag-ops-${PROJECT} -g ${RG} --query id -o tsv)
```

### Alertas via Terraform (log alerts)

```hcl
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "error_rate" {
  name                = "alert-error-rate-${var.project}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  scopes              = [azurerm_application_insights.this.id]
  severity            = 2
  description         = "Taxa de erros HTTP acima de 5%"

  window_duration      = "PT5M"
  evaluation_frequency = "PT1M"

  criteria {
    query = <<-QUERY
      requests
      | where timestamp > ago(5m)
      | summarize total = count(), errors = countif(success == false)
      | extend error_rate = errors * 100.0 / total
      | where error_rate > 5
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "p99_latency" {
  name                = "alert-p99-latency-${var.project}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  scopes              = [azurerm_application_insights.this.id]
  severity            = 3
  description         = "Latência P99 acima de 2000ms"

  window_duration      = "PT5M"
  evaluation_frequency = "PT1M"

  criteria {
    query = <<-QUERY
      requests
      | where timestamp > ago(5m)
      | summarize p99 = percentile(duration, 99)
      | where p99 > 2000
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops.id]
  }
}
```

---

## Availability Tests (uptime)

```hcl
# Ping test a endpoint público
resource "azurerm_application_insights_web_test" "api_health" {
  name                    = "webtest-${var.project}-api"
  location                = var.location
  resource_group_name     = azurerm_resource_group.this.name
  application_insights_id = azurerm_application_insights.this.id
  kind                    = "ping"
  frequency               = 300   # segundos (5 min)
  timeout                 = 30
  enabled                 = true
  geo_locations           = [
    "emea-nl-ams-azr",    # West Europe
    "emea-gb-db3-azr",    # North Europe
    "us-ca-sjc-azr",      # West US
  ]

  configuration = <<XML
  <WebTest Name="API Health Check" Enabled="True" Timeout="30" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
    <Items>
      <Request Method="GET" Url="https://${var.api_fqdn}/health" Version="1.1" FollowRedirects="true" RecordResult="true" Cache="false" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="200" />
    </Items>
  </WebTest>
  XML
}

# Alerta de disponibilidade < 99.9%
resource "azurerm_monitor_metric_alert" "availability" {
  name                = "alert-availability-${var.project}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_application_insights.this.id]
  severity            = 1
  description         = "Disponibilidade abaixo de 99.9%"

  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99.9
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}
```

---

## Severidades e resposta esperada

| Severidade | Descrição | Resposta |
|---|---|---|
| **0 — Critical** | Serviço completamente em baixo | Resposta imediata, on-call acordado |
| **1 — Error** | Funcionalidade major afetada | Resposta em < 15 min |
| **2 — Warning** | Degradação de performance | Resposta em < 1 hora |
| **3 — Informational** | Anomalia minor, tendência preocupante | Investigar no próximo dia útil |
| **4 — Verbose** | Diagnóstico, sem impacto | Apenas para context |

---

## Runbook de resposta a alertas

### Alta taxa de erros

```bash
# 1. Ver requests com erro nos últimos 30 min
az monitor app-insights query \
  --app ${AI_NAME} -g ${RG} \
  --analytics-query "
    requests
    | where timestamp > ago(30m) and success == false
    | project timestamp, name, url, resultCode, duration
    | order by timestamp desc
    | take 50"

# 2. Ver exceções relacionadas
az monitor app-insights query \
  --app ${AI_NAME} -g ${RG} \
  --analytics-query "
    exceptions
    | where timestamp > ago(30m)
    | summarize count() by type, outerMessage
    | order by count_ desc"

# 3. Ver se houve deploy recente
az containerapp revision list -n ${APP} -g ${RG} \
  --query "sort_by([].{revision:name, created:properties.createdTime, active:properties.active}, &created) | reverse(@)" \
  -o table

# 4. Se necessário, rollback
az containerapp ingress traffic set -n ${APP} -g ${RG} \
  --revision-weight <revision-anterior>=100
```
