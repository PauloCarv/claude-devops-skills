---
name: azure-container-apps
description: >
  Especialista Azure Container Apps. Usa quando configurares Container Apps,
  scaling rules (KEDA), Dapr, managed certificates, revisões, traffic splitting,
  jobs, secrets via Key Vault, Container Apps Environment, ou diagnosticar
  problemas de containerização no Azure. Ativa automaticamente para pedidos
  sobre Container Apps, ACA, KEDA scaling, Dapr sidecars, ou revisões.
invocation: auto
---

# Azure Container Apps

Especialista em Container Apps: scaling, Dapr, revisões, jobs e diagnóstico.

## Comandos essenciais

```bash
# Ver estado de uma app
az containerapp show \
  --name <app> --resource-group <rg> \
  --query "{fqdn:properties.configuration.ingress.fqdn, replicas:properties.template.scale, revision:properties.latestRevisionName}"

# Listar revisões
az containerapp revision list \
  --name <app> --resource-group <rg> \
  --query "[].{name:name, active:properties.active, traffic:properties.trafficWeight, replicas:properties.replicas}" \
  -o table

# Ver logs em tempo real
az containerapp logs show \
  --name <app> --resource-group <rg> \
  --follow --tail 50

# Forçar nova revisão (redeploy)
az containerapp update \
  --name <app> --resource-group <rg> \
  --image <registry>/<image>:<new-tag>

# Escalar manualmente para debug
az containerapp update \
  --name <app> --resource-group <rg> \
  --min-replicas 1 --max-replicas 1
```

## Scaling Rules (KEDA)

```yaml
# HTTP scaling (mais comum)
scale:
  minReplicas: 0          # scale-to-zero em dev/staging
  maxReplicas: 10
  rules:
    - name: http-scaling
      http:
        metadata:
          concurrentRequests: "10"

# Azure Service Bus scaling
scale:
  minReplicas: 0
  maxReplicas: 20
  rules:
    - name: servicebus-scaling
      custom:
        type: azure-servicebus
        metadata:
          queueName: my-queue
          messageCount: "5"       # réplicas por cada 5 mensagens
        auth:
          - secretRef: servicebus-connection
            triggerParameter: connection

# CPU/Memory scaling
scale:
  minReplicas: 1
  maxReplicas: 5
  rules:
    - name: cpu-scaling
      custom:
        type: cpu
        metadata:
          type: Utilization
          value: "70"
```

## Dapr — configuração básica

```bash
# Ativar Dapr numa app
az containerapp dapr enable \
  --name <app> --resource-group <rg> \
  --dapr-app-id meu-servico \
  --dapr-app-port 8080 \
  --dapr-app-protocol http

# Criar componente Dapr (state store)
az containerapp env dapr-component set \
  --name <environment> --resource-group <rg> \
  --dapr-component-name statestore \
  --yaml - <<EOF
componentType: state.azure.blobstorage
version: v1
metadata:
  - name: accountName
    value: mystorageaccount
  - name: containerName
    value: mycontainer
EOF
```

## Traffic Splitting (blue/green / canary)

```bash
# Canary: 10% para nova revisão
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight \
    latest=10 \
    <revision-anterior>=90

# Promover nova revisão para 100%
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight latest=100

# Rollback para revisão anterior
az containerapp revision activate \
  --name <app> --resource-group <rg> \
  --revision <revision-name>
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight <revision-name>=100
```

## Jobs — tarefas agendadas e event-driven

```bash
# Criar job agendado (cron)
az containerapp job create \
  --name meu-job --resource-group <rg> \
  --environment <environment> \
  --trigger-type Schedule \
  --cron-expression "0 2 * * *" \
  --image <registry>/<job-image>:<tag> \
  --cpu 0.5 --memory 1Gi

# Job event-driven (Service Bus)
az containerapp job create \
  --name processador-job --resource-group <rg> \
  --environment <environment> \
  --trigger-type Event \
  --min-executions 0 \
  --max-executions 10 \
  --scale-rule-name servicebus-rule \
  --scale-rule-type azure-servicebus \
  --scale-rule-metadata "queueName=myqueue" "messageCount=1" \
  --scale-rule-auth "connection=servicebus-secret"
```

## Diagnóstico de problemas comuns

```bash
# App não arranca — ver system logs
az containerapp logs show \
  --name <app> --resource-group <rg> \
  --type system

# Ver eventos de scaling
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "
    ContainerAppSystemLogs_CL
    | where ContainerAppName_s == '<app>'
    | where Reason_s in ('Scaling', 'BackOff', 'OOMKill')
    | order by TimeGenerated desc
    | take 20"

# Verificar health probes
az containerapp show \
  --name <app> --resource-group <rg> \
  --query "properties.template.containers[0].probes"

# Testar conectividade interna (via Dapr ou direct)
az containerapp exec \
  --name <app> --resource-group <rg> \
  --command "curl -f http://outro-servico/health"
```

## Managed Certificates (HTTPS custom domain)

```bash
# Adicionar domínio customizado
az containerapp hostname add \
  --name <app> --resource-group <rg> \
  --hostname minha-app.meudominio.com

# Criar managed certificate (gratuito)
az containerapp ssl upload \
  --name <app> --resource-group <rg> \
  --hostname minha-app.meudominio.com \
  --certificate-type managed

# Verificar estado do certificado
az containerapp hostname list \
  --name <app> --resource-group <rg> \
  -o table
```
