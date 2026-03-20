# APIM via Terraform / Bicep

Padrões de infraestrutura como código para Azure API Management.

---

## Terraform — APIM completo

### Provider e versões

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}
```

### Instância APIM

```hcl
resource "azurerm_api_management" "this" {
  name                = "apim-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email

  # Developer para dev/staging, Standard/Premium para prod
  sku_name = var.environment == "prod" ? "Standard_1" : "Developer_1"

  # Managed Identity para aceder ao Key Vault e Azure OpenAI
  identity {
    type = "SystemAssigned"
  }

  # Application Insights para telemetria
  tags = local.common_tags
}

# Role: acesso ao Azure OpenAI
resource "azurerm_role_assignment" "apim_openai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# Role: acesso ao Key Vault (para certificados e secrets)
resource "azurerm_role_assignment" "apim_keyvault" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}
```

### Logger (Application Insights)

```hcl
resource "azurerm_api_management_logger" "this" {
  name                = "appinsights-logger"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  resource_id         = azurerm_application_insights.this.id

  application_insights {
    instrumentation_key = azurerm_application_insights.this.instrumentation_key
  }
}

# Diagnóstico global — log de todos os requests/responses
resource "azurerm_api_management_diagnostic" "this" {
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.this.name
  api_management_name      = azurerm_api_management.this.name
  api_management_logger_id = azurerm_api_management_logger.this.id

  sampling_percentage       = var.environment == "prod" ? 5 : 100
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 1024
    headers_to_log = ["Content-Type", "x-correlation-id"]
  }
  frontend_response {
    body_bytes = 1024
    headers_to_log = ["Content-Type", "x-ratelimit-remaining"]
  }
  backend_request {
    body_bytes = 1024
  }
  backend_response {
    body_bytes = 1024
  }
}
```

### Backend Azure OpenAI

```hcl
resource "azurerm_api_management_backend" "openai" {
  name                = "openai-backend"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "${azurerm_cognitive_account.openai.endpoint}openai"

  credentials {
    header = {
      "api-key" = "{{openai-api-key}}"  # Named value do APIM
    }
  }

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}
```

### API OpenAI importada

```hcl
resource "azurerm_api_management_api" "openai" {
  name                = "azure-openai-api"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  revision            = "1"
  display_name        = "Azure OpenAI API"
  path                = "openai"
  protocols           = ["https"]
  service_url         = azurerm_api_management_backend.openai.url

  import {
    content_format = "openapi+json-link"
    content_value  = "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-02-01/inference.json"
  }
}

# Policy global da API
resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name

  xml_content = file("${path.module}/policies/openai-policy.xml")
}
```

### Named Values (segredos via Key Vault)

```hcl
# Named Value ligado ao Key Vault (sem expor o valor no state)
resource "azurerm_api_management_named_value" "openai_key" {
  name                = "openai-api-key"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "openai-api-key"
  secret              = true

  value_from_key_vault {
    secret_id = azurerm_key_vault_secret.openai_key.id
  }
}
```

### Produto e Subscription

```hcl
resource "azurerm_api_management_product" "standard" {
  product_id            = "standard"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  display_name          = "Standard"
  description           = "Acesso padrão às APIs"
  subscription_required = true
  subscriptions_limit   = 5
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "openai_standard" {
  api_name            = azurerm_api_management_api.openai.name
  product_id          = azurerm_api_management_product.standard.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}
```

---

## Bicep — APIM com Managed Identity e AOAI

```bicep
param location string = resourceGroup().location
param project string
param environment string
param publisherEmail string
param publisherName string

var apimName = 'apim-${project}-${environment}'
var skuName = environment == 'prod' ? 'Standard' : 'Developer'

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: skuName
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
    }
  }
  tags: {
    environment: environment
    project: project
  }
}

// Role assignment para Azure OpenAI
resource apimOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(apim.id, openAi.id, 'Cognitive Services User')
  scope: openAi
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
```

---

## Outputs úteis

```hcl
output "apim_gateway_url" {
  description = "URL do gateway APIM"
  value       = azurerm_api_management.this.gateway_url
}

output "apim_portal_url" {
  description = "URL do portal de developers"
  value       = azurerm_api_management.this.developer_portal_url
}

output "apim_principal_id" {
  description = "Object ID da Managed Identity (para role assignments)"
  value       = azurerm_api_management.this.identity[0].principal_id
}
```

---

## Decisões de arquitetura

| Decisão | Recomendação | Justificação |
|---|---|---|
| SKU de dev/staging | Developer | Mais barato, sem SLA, suficiente para testes |
| SKU de prod | Standard ou Premium | SLA 99.95%, Premium para multi-region |
| Autenticação ao AOAI | Managed Identity | Sem chaves hardcoded no state |
| Secrets | Named Values via Key Vault | APIM faz lookup automático, sem exposição no Terraform state |
| Policies | Ficheiros `.xml` externos | Versionados em git, editáveis sem `terraform apply` |
| Logs | Application Insights + sampling | Sampling de 5% em prod reduz custos |
