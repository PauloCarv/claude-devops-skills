---
name: azure-container-apps
description: >
  Azure Container Apps specialist. Use when configuring Container Apps,
  scaling rules (KEDA), Dapr, managed certificates, revisions, traffic splitting,
  jobs, secrets via Key Vault, Container Apps Environment, or diagnosing
  containerization issues on Azure. Activates automatically for requests
  about Container Apps, ACA, KEDA scaling, Dapr sidecars, or revisions.
invocation: auto
---

# Azure Container Apps

Container Apps specialist: scaling, Dapr, revisions, jobs, and diagnostics.

## Essential commands

```bash
# Show app status
az containerapp show \
  --name <app> --resource-group <rg> \
  --query "{fqdn:properties.configuration.ingress.fqdn, replicas:properties.template.scale, revision:properties.latestRevisionName}"

# List revisions
az containerapp revision list \
  --name <app> --resource-group <rg> \
  --query "[].{name:name, active:properties.active, traffic:properties.trafficWeight, replicas:properties.replicas}" \
  -o table

# Stream logs in real time
az containerapp logs show \
  --name <app> --resource-group <rg> \
  --follow --tail 50

# Force a new revision (redeploy)
az containerapp update \
  --name <app> --resource-group <rg> \
  --image <registry>/<image>:<new-tag>

# Scale manually for debugging
az containerapp update \
  --name <app> --resource-group <rg> \
  --min-replicas 1 --max-replicas 1
```

## Scaling Rules (KEDA)

```yaml
# HTTP scaling (most common)
scale:
  minReplicas: 0          # scale-to-zero in dev/staging
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
          messageCount: "5"       # replicas per 5 messages
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

## Dapr — basic configuration

```bash
# Enable Dapr on an app
az containerapp dapr enable \
  --name <app> --resource-group <rg> \
  --dapr-app-id my-service \
  --dapr-app-port 8080 \
  --dapr-app-protocol http

# Create a Dapr component (state store)
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
# Canary: 10% to new revision
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight \
    latest=10 \
    <previous-revision>=90

# Promote new revision to 100%
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight latest=100

# Rollback to previous revision
az containerapp revision activate \
  --name <app> --resource-group <rg> \
  --revision <revision-name>
az containerapp ingress traffic set \
  --name <app> --resource-group <rg> \
  --revision-weight <revision-name>=100
```

## Jobs — scheduled and event-driven tasks

```bash
# Create a scheduled job (cron)
az containerapp job create \
  --name my-job --resource-group <rg> \
  --environment <environment> \
  --trigger-type Schedule \
  --cron-expression "0 2 * * *" \
  --image <registry>/<job-image>:<tag> \
  --cpu 0.5 --memory 1Gi

# Event-driven job (Service Bus)
az containerapp job create \
  --name processor-job --resource-group <rg> \
  --environment <environment> \
  --trigger-type Event \
  --min-executions 0 \
  --max-executions 10 \
  --scale-rule-name servicebus-rule \
  --scale-rule-type azure-servicebus \
  --scale-rule-metadata "queueName=myqueue" "messageCount=1" \
  --scale-rule-auth "connection=servicebus-secret"
```

## Diagnosing common issues

```bash
# App not starting — check system logs
az containerapp logs show \
  --name <app> --resource-group <rg> \
  --type system

# Check scaling events
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "
    ContainerAppSystemLogs_CL
    | where ContainerAppName_s == '<app>'
    | where Reason_s in ('Scaling', 'BackOff', 'OOMKill')
    | order by TimeGenerated desc
    | take 20"

# Check health probes
az containerapp show \
  --name <app> --resource-group <rg> \
  --query "properties.template.containers[0].probes"

# Test internal connectivity (via Dapr or direct)
az containerapp exec \
  --name <app> --resource-group <rg> \
  --command "curl -f http://other-service/health"
```

## Managed Certificates (HTTPS custom domain)

```bash
# Add a custom domain
az containerapp hostname add \
  --name <app> --resource-group <rg> \
  --hostname my-app.mydomain.com

# Create a managed certificate (free)
az containerapp ssl upload \
  --name <app> --resource-group <rg> \
  --hostname my-app.mydomain.com \
  --certificate-type managed

# Check certificate status
az containerapp hostname list \
  --name <app> --resource-group <rg> \
  -o table
```
