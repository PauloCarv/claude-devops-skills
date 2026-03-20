---
name: azure-apim
description: >
  Especialista Azure API Management (APIM). Usa quando configurares APIM como
  AI Gateway, políticas de rate limiting, semantic caching, content safety,
  load balancing de modelos OpenAI, gestão de APIs REST/OpenAPI, backends,
  produtos e subscriptions. Ativa automaticamente para pedidos de APIM,
  API gateway, políticas XML, OpenAI através de gateway, ou gestão de APIs Azure.
invocation: auto
---

# Azure API Management

Configura APIM como gateway de APIs e AI Gateway para modelos, MCP servers e agentes.

## Quando usar

| Categoria | Triggers |
|---|---|
| **AI Gateway** | "semantic caching", "token limits", "load balance OpenAI", "token usage" |
| **API Management** | "criar API", "importar OpenAPI", "produtos e subscriptions" |
| **Segurança** | "rate limiting", "content safety", "jailbreak detection", "JWT validation" |
| **Observabilidade** | "monitorizar tokens", "logs APIM", "Application Insights APIM" |

## Comandos az apim essenciais

```bash
# Ver gateway URL
az apim show --name <apim-name> --resource-group <rg> \
  --query "gatewayUrl" -o tsv

# Listar APIs
az apim api list --service-name <apim-name> --resource-group <rg> \
  --query "[].{name:name, path:path, protocols:protocols}" -o table

# Listar backends (modelos AI)
az apim backend list --service-name <apim-name> --resource-group <rg> \
  --query "[].{id:name, url:url}" -o table

# Obter subscription key
az apim subscription keys list \
  --service-name <apim-name> --resource-group <rg> \
  --subscription-id <sub-id>

# Testar endpoint AI via gateway
GATEWAY_URL=$(az apim show --name <apim> -g <rg> --query "gatewayUrl" -o tsv)
curl -X POST "${GATEWAY_URL}/openai/deployments/<deployment>/chat/completions?api-version=2024-02-01" \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: <key>" \
  -d '{"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'
```

## Configurar backend Azure OpenAI

```bash
# 1. Descobrir recursos OpenAI
az cognitiveservices account list --query "[?kind=='OpenAI']" -o table

# 2. Criar backend
az apim backend create \
  --service-name <apim> --resource-group <rg> \
  --backend-id openai-backend \
  --protocol http \
  --url "https://<aoai>.openai.azure.com/openai"

# 3. Dar acesso via Managed Identity
az role assignment create \
  --assignee <apim-principal-id> \
  --role "Cognitive Services User" \
  --scope <aoai-resource-id>
```

## Políticas XML — ordem recomendada em `<inbound>`

```xml
<policies>
  <inbound>
    <!-- 1. Autenticação ao backend via Managed Identity -->
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />

    <!-- 2. Semantic Cache Lookup (60-80% de poupança em custos) -->
    <azure-openai-semantic-cache-lookup
      score-threshold="0.8"
      embeddings-backend-id="embeddings-backend"
      embeddings-backend-auth="system-assigned"
      embeddings-deployment-name="text-embedding-ada-002" />

    <!-- 3. Token Rate Limiting (controlo de custos) -->
    <azure-openai-token-limit
      counter-key="@(context.Subscription.Id)"
      tokens-per-minute="10000"
      estimate-prompt-tokens="true" />

    <!-- 4. Content Safety (agentes/LLMs) -->
    <llm-content-safety
      backend-id="content-safety-backend"
      shield-prompt="true"
      groundedness="true" />

    <!-- 5. Load Balancing entre múltiplos backends -->
    <set-backend-service backend-id="@{
      var backends = new[] { 'openai-eastus', 'openai-westeurope' };
      return backends[new Random().Next(backends.Length)];
    }" />
  </inbound>

  <outbound>
    <!-- 6. Guardar no cache semântico -->
    <azure-openai-semantic-cache-store duration="3600" />

    <!-- 7. Emitir métricas de tokens -->
    <azure-openai-emit-token-metric
      namespace="OpenAI"
      stream-as-chunk-content="true">
      <dimension name="Subscription" value="@(context.Subscription.Id)" />
      <dimension name="API" value="@(context.Api.Name)" />
    </azure-openai-emit-token-metric>
  </outbound>
</policies>
```

## Importar API OpenAPI

```bash
# Importar spec OpenAPI
az apim api import \
  --service-name <apim> --resource-group <rg> \
  --path /minha-api \
  --specification-format OpenApiJson \
  --specification-url https://meu-servico/swagger/v1/swagger.json \
  --api-id minha-api \
  --display-name "Minha API" \
  --protocols https

# Adicionar API a produto
az apim product api add \
  --service-name <apim> --resource-group <rg> \
  --product-id standard \
  --api-id minha-api
```

## Troubleshooting rápido

| Problema | Causa provável | Solução |
|---|---|---|
| 429 Token limit | Limite de TPM atingido | Aumentar `tokens-per-minute` ou adicionar load balancing |
| Cache sem hits | Score threshold muito alto | Baixar `score-threshold` para 0.7 |
| Content safety falsos positivos | Thresholds baixos | Aumentar thresholds para 5-6 |
| 401 no backend | APIM sem permissão | Dar role "Cognitive Services User" ao APIM |
| Latência elevada | Sem cache / backend único | Ativar semantic cache + load balancing |

## Referências

- `references/policies.md` — exemplos completos de políticas XML
- `references/terraform.md` — APIM via Terraform/Bicep
