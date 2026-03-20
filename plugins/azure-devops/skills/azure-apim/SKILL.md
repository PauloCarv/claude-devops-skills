---
name: azure-apim
description: >
  Azure API Management (APIM) specialist. Use when configuring APIM as an
  AI Gateway, rate limiting policies, semantic caching, content safety,
  OpenAI model load balancing, REST/OpenAPI API management, backends,
  products and subscriptions. Automatically activated for requests about APIM,
  API gateway, XML policies, OpenAI through a gateway, or Azure API management.
invocation: auto
---

# Azure API Management

Configure APIM as an API gateway and AI Gateway for models, MCP servers and agents.

## When to use

| Category | Triggers |
|---|---|
| **AI Gateway** | "semantic caching", "token limits", "load balance OpenAI", "token usage" |
| **API Management** | "create API", "import OpenAPI", "products and subscriptions" |
| **Security** | "rate limiting", "content safety", "jailbreak detection", "JWT validation" |
| **Observability** | "monitor tokens", "APIM logs", "Application Insights APIM" |

## Essential az apim commands

```bash
# Show gateway URL
az apim show --name <apim-name> --resource-group <rg> \
  --query "gatewayUrl" -o tsv

# List APIs
az apim api list --service-name <apim-name> --resource-group <rg> \
  --query "[].{name:name, path:path, protocols:protocols}" -o table

# List backends (AI models)
az apim backend list --service-name <apim-name> --resource-group <rg> \
  --query "[].{id:name, url:url}" -o table

# Get subscription key
az apim subscription keys list \
  --service-name <apim-name> --resource-group <rg> \
  --subscription-id <sub-id>

# Test AI endpoint via gateway
GATEWAY_URL=$(az apim show --name <apim> -g <rg> --query "gatewayUrl" -o tsv)
curl -X POST "${GATEWAY_URL}/openai/deployments/<deployment>/chat/completions?api-version=2024-02-01" \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: <key>" \
  -d '{"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'
```

## Configure Azure OpenAI backend

```bash
# 1. Discover OpenAI resources
az cognitiveservices account list --query "[?kind=='OpenAI']" -o table

# 2. Create backend
az apim backend create \
  --service-name <apim> --resource-group <rg> \
  --backend-id openai-backend \
  --protocol http \
  --url "https://<aoai>.openai.azure.com/openai"

# 3. Grant access via Managed Identity
az role assignment create \
  --assignee <apim-principal-id> \
  --role "Cognitive Services User" \
  --scope <aoai-resource-id>
```

## XML Policies — recommended order in `<inbound>`

```xml
<policies>
  <inbound>
    <!-- 1. Backend authentication via Managed Identity -->
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />

    <!-- 2. Semantic Cache Lookup (60-80% cost savings) -->
    <azure-openai-semantic-cache-lookup
      score-threshold="0.8"
      embeddings-backend-id="embeddings-backend"
      embeddings-backend-auth="system-assigned"
      embeddings-deployment-name="text-embedding-ada-002" />

    <!-- 3. Token Rate Limiting (cost control) -->
    <azure-openai-token-limit
      counter-key="@(context.Subscription.Id)"
      tokens-per-minute="10000"
      estimate-prompt-tokens="true" />

    <!-- 4. Content Safety (agents/LLMs) -->
    <llm-content-safety
      backend-id="content-safety-backend"
      shield-prompt="true"
      groundedness="true" />

    <!-- 5. Load Balancing across multiple backends -->
    <set-backend-service backend-id="@{
      var backends = new[] { 'openai-eastus', 'openai-westeurope' };
      return backends[new Random().Next(backends.Length)];
    }" />
  </inbound>

  <outbound>
    <!-- 6. Store in semantic cache -->
    <azure-openai-semantic-cache-store duration="3600" />

    <!-- 7. Emit token metrics -->
    <azure-openai-emit-token-metric
      namespace="OpenAI"
      stream-as-chunk-content="true">
      <dimension name="Subscription" value="@(context.Subscription.Id)" />
      <dimension name="API" value="@(context.Api.Name)" />
    </azure-openai-emit-token-metric>
  </outbound>
</policies>
```

## Import OpenAPI API

```bash
# Import OpenAPI spec
az apim api import \
  --service-name <apim> --resource-group <rg> \
  --path /my-api \
  --specification-format OpenApiJson \
  --specification-url https://my-service/swagger/v1/swagger.json \
  --api-id my-api \
  --display-name "My API" \
  --protocols https

# Add API to product
az apim product api add \
  --service-name <apim> --resource-group <rg> \
  --product-id standard \
  --api-id my-api
```

## Quick troubleshooting

| Problem | Likely cause | Solution |
|---|---|---|
| 429 Token limit | TPM limit reached | Increase `tokens-per-minute` or add load balancing |
| Cache with no hits | Score threshold too high | Lower `score-threshold` to 0.7 |
| Content safety false positives | Low thresholds | Increase thresholds to 5-6 |
| 401 on backend | APIM lacks permission | Grant "Cognitive Services User" role to APIM |
| High latency | No cache / single backend | Enable semantic cache + load balancing |

## References

- `references/policies.md` — complete XML policy examples
- `references/terraform.md` — APIM via Terraform/Bicep
