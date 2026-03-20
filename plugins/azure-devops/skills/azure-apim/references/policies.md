# APIM Policies — Exemplos Completos

Referência de políticas XML para Azure API Management. Usa em conjunto com a skill `azure-apim`.

---

## Estrutura base de uma policy

```xml
<policies>
  <inbound>
    <!-- Processamento do request antes de chegar ao backend -->
    <base />
  </inbound>
  <backend>
    <!-- Encaminhar para o backend -->
    <base />
  </backend>
  <outbound>
    <!-- Processar response antes de devolver ao cliente -->
    <base />
  </outbound>
  <on-error>
    <!-- Tratamento de erros -->
    <base />
  </on-error>
</policies>
```

---

## AI Gateway completo (Azure OpenAI)

```xml
<policies>
  <inbound>
    <base />

    <!-- 1. Autenticação ao Azure OpenAI via Managed Identity -->
    <authentication-managed-identity resource="https://cognitiveservices.azure.com"
      output-token-variable-name="msi-access-token" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
    </set-header>

    <!-- 2. Semantic Cache Lookup (reduz custos em 60-80%) -->
    <azure-openai-semantic-cache-lookup
      score-threshold="0.8"
      embeddings-backend-id="embeddings-backend"
      embeddings-backend-auth="system-assigned"
      embeddings-deployment-name="text-embedding-ada-002"
      ignore-system-messages="true"
      max-message-count="10" />

    <!-- 3. Token Rate Limiting por subscription -->
    <azure-openai-token-limit
      counter-key="@(context.Subscription.Id)"
      tokens-per-minute="10000"
      estimate-prompt-tokens="true"
      remaining-tokens-variable-name="remaining-tokens"
      remaining-tokens-header-name="x-ratelimit-remaining-tokens" />

    <!-- 4. Content Safety (jailbreak + groundedness) -->
    <llm-content-safety
      backend-id="content-safety-backend"
      shield-prompt="true"
      groundedness="true"
      groundedness-score-threshold="0.7" />

    <!-- 5. Load Balancing entre múltiplos backends -->
    <set-backend-service backend-id="@{
      string[] backends = { &quot;openai-westeurope&quot;, &quot;openai-northeurope&quot;, &quot;openai-eastus&quot; };
      int idx = new Random().Next(backends.Length);
      return backends[idx];
    }" />
  </inbound>

  <backend>
    <base />
    <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
      count="3" interval="2" delta="2" max-interval="10">
      <set-backend-service backend-id="@{
        string[] backends = { &quot;openai-westeurope&quot;, &quot;openai-northeurope&quot; };
        return backends[new Random().Next(backends.Length)];
      }" />
    </retry>
  </backend>

  <outbound>
    <base />

    <!-- 6. Guardar no Semantic Cache -->
    <azure-openai-semantic-cache-store duration="3600" />

    <!-- 7. Emitir métricas de tokens para Application Insights -->
    <azure-openai-emit-token-metric namespace="OpenAI">
      <dimension name="Subscription" value="@(context.Subscription.Id)" />
      <dimension name="API" value="@(context.Api.Name)" />
      <dimension name="Model" value="@(context.Request.Body.As<JObject>(preserveContent: true)["model"]?.ToString() ?? "unknown")" />
    </azure-openai-emit-token-metric>

    <!-- 8. Headers de debugging (remover em prod) -->
    <set-header name="x-remaining-tokens" exists-action="override">
      <value>@(context.Variables.GetValueOrDefault<int>("remaining-tokens", -1).ToString())</value>
    </set-header>
  </outbound>

  <on-error>
    <base />
    <return-response>
      <set-status code="@(context.Response.StatusCode)" reason="@(context.Response.StatusReason)" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>@{
        return new JObject(
          new JProperty("error", new JObject(
            new JProperty("code", context.Response.StatusCode),
            new JProperty("message", context.LastError.Message),
            new JProperty("requestId", context.RequestId)
          ))
        ).ToString();
      }</set-body>
    </return-response>
  </on-error>
</policies>
```

---

## JWT Validation (Entra ID / Azure AD)

```xml
<policies>
  <inbound>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
      failed-validation-error-message="Token inválido ou expirado" require-scheme="Bearer">
      <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>api://{app-id}</audience>
      </audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/{tenant-id}/v2.0</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any">
          <value>API.Read</value>
          <value>API.Write</value>
        </claim>
      </required-claims>
    </validate-jwt>

    <!-- Extrair claims úteis para headers de backend -->
    <set-header name="x-user-id" exists-action="override">
      <value>@(context.Request.Headers.GetValueOrDefault("Authorization","").Split(' ').Last()
        .Split('.').Skip(1).First()
        .Replace('-','+').Replace('_','/')
        |> Convert.FromBase64String
        |> System.Text.Encoding.UTF8.GetString
        |> JObject.Parse
        |> (obj) => obj["oid"]?.ToString() ?? "unknown")</value>
    </set-header>
  </inbound>
</policies>
```

---

## Rate Limiting por IP e por subscription

```xml
<policies>
  <inbound>
    <!-- Rate limit por subscription (100 calls/minuto) -->
    <rate-limit calls="100" renewal-period="60" />

    <!-- Rate limit por IP (para APIs públicas sem autenticação) -->
    <rate-limit-by-key calls="20" renewal-period="60"
      counter-key="@(context.Request.IpAddress)"
      remaining-calls-variable-name="remaining-calls"
      remaining-calls-header-name="x-ratelimit-remaining" />

    <!-- Quota mensal por subscription -->
    <quota calls="10000" bandwidth="40000" renewal-period="604800">
      <api name="minha-api" />
    </quota>
  </inbound>
  <outbound>
    <set-header name="x-ratelimit-remaining" exists-action="override">
      <value>@(context.Variables.GetValueOrDefault<int>("remaining-calls", -1).ToString())</value>
    </set-header>
  </outbound>
</policies>
```

---

## Request/Response Transformation

```xml
<policies>
  <inbound>
    <!-- Adicionar header de correlação -->
    <set-header name="x-correlation-id" exists-action="skip">
      <value>@(Guid.NewGuid().ToString())</value>
    </set-header>

    <!-- Remover headers sensíveis antes de enviar ao backend -->
    <set-header name="x-internal-key" exists-action="delete" />

    <!-- Reescrever URL (versioning) -->
    <rewrite-uri template="/v2/@(context.Request.Url.Path.TrimStart('/'))" />

    <!-- Validar body JSON contra schema -->
    <validate-content unspecified-content-type-action="prevent"
      max-size="102400" size-exceeded-action="prevent">
      <content type="application/json" validate-as="json" action="prevent" />
    </validate-content>
  </inbound>

  <outbound>
    <!-- Remover headers internos da resposta -->
    <set-header name="x-powered-by" exists-action="delete" />
    <set-header name="server" exists-action="delete" />

    <!-- Adicionar CORS headers -->
    <set-header name="Access-Control-Allow-Origin" exists-action="override">
      <value>https://minha-app.meudominio.com</value>
    </set-header>

    <!-- Cache de responses GET -->
    <cache-store duration="300" />
  </outbound>
</policies>
```

---

## Mock response (desenvolvimento / testes)

```xml
<policies>
  <inbound>
    <mock-response status-code="200" content-type="application/json">
      <value>
        {
          "id": "mock-123",
          "status": "ok",
          "message": "Mock response para desenvolvimento"
        }
      </value>
    </mock-response>
  </inbound>
</policies>
```

---

## Circuit Breaker (backend instável)

```xml
<policies>
  <backend>
    <!-- Retry com backoff exponencial -->
    <retry condition="@(context.Response.StatusCode == 503 || context.Response.StatusCode == 502)"
      count="3" interval="1" delta="2" max-interval="8" first-fast-retry="true">
      <forward-request />
    </retry>
  </backend>

  <on-error>
    <!-- Fallback estático quando backend está em baixo -->
    <choose>
      <when condition="@(context.LastError.Source == &quot;forward-request&quot;)">
        <return-response>
          <set-status code="503" reason="Service Unavailable" />
          <set-header name="Retry-After" exists-action="override">
            <value>30</value>
          </set-header>
          <set-body>{"error": "Serviço temporariamente indisponível. Tenta novamente em 30 segundos."}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
```

---

## Notas de segurança

| Risco | Mitigação |
|---|---|
| Tokens expostos em logs | Nunca logar `Authorization` header |
| SSRF via backend dinâmico | Validar backends contra lista allowlist |
| Injection em C# expressions | Sanitizar inputs antes de usar em expressões |
| Subscription keys em URLs | Usar header `Ocp-Apim-Subscription-Key` em vez de query param |
