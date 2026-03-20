---
name: terraform
description: >
  Especialista Terraform e OpenTofu para IaC production-ready. Usa quando
  criares módulos, configurares backends de estado, escrever testes nativos
  ou Terratest, pipelines CI/CD, Azure provider, segurança com trivy/checkov,
  ou tomares decisões de arquitetura IaC. Ativa automaticamente para ficheiros
  .tf, tfvars, ou qualquer pedido de infraestrutura como código.
invocation: auto
---

# Terraform Skill

Guia completo para Terraform e OpenTofu — módulos, testes, CI/CD e padrões
de produção. Baseado em terraform-best-practices.com e experiência enterprise.

## Workflow base (sempre seguir esta ordem)

```bash
terraform init
terraform fmt -recursive        # formatar antes de qualquer coisa
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## Estrutura de projeto recomendada

```
infra/
├── environments/               # configurações por ambiente
│   ├── prod/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   └── dev/
├── modules/                    # módulos reutilizáveis
│   ├── networking/
│   ├── compute/
│   └── data/
└── examples/                   # exemplos de uso (servem também como testes)
    ├── complete/
    └── minimal/
```

## Decisões de arquitetura

### State remoto — obrigatório em equipa

```hcl
# Azure Backend (para projetos Azure)
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate${var.project}${var.environment}"
    container_name       = "tfstate"
    key                  = "${var.project}/${var.environment}/terraform.tfstate"
    use_oidc             = true   # federação — sem chaves de acesso
  }
}
```

### count vs for_each

```hcl
# ❌ Evitar count para recursos com identidade própria
resource "azurerm_resource_group" "this" {
  count = length(var.locations)
  name  = "rg-${var.locations[count.index]}"
}

# ✅ Usar for_each — chaves estáveis, sem recreação acidental
resource "azurerm_resource_group" "this" {
  for_each = toset(var.locations)
  name     = "rg-${each.key}"
  location = each.key
}
```

### Nomenclatura de recursos

```hcl
# ✅ Descritivo e contextual
resource "azurerm_container_app" "api_gateway" { }
resource "azurerm_postgresql_flexible_server" "orders_db" { }

# ✅ "this" para recursos singleton (só um desse tipo no módulo)
resource "azurerm_resource_group" "this" { }
resource "azurerm_virtual_network" "this" { }

# ❌ Evitar redundância no nome
resource "azurerm_virtual_network" "virtual_network" { }
```

## Módulos — boas práticas

```hcl
# Variáveis: tipos explícitos + validações
variable "environment" {
  type        = string
  description = "Ambiente de deployment"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment deve ser dev, staging ou prod."
  }
}

# Outputs: sempre expor o id e atributos úteis
output "id" {
  description = "ID do Container App"
  value       = azurerm_container_app.this.id
}

output "fqdn" {
  description = "FQDN público do Container App"
  value       = azurerm_container_app.this.latest_revision_fqdn
}

# prevent_destroy em recursos críticos de produção
resource "azurerm_postgresql_flexible_server" "this" {
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [administrator_password]
  }
}
```

## Testes

### Quando usar cada abordagem

| Cenário | Ferramenta |
|---|---|
| Validação sintática rápida | `terraform validate` |
| Testes unitários de módulos (sem cloud) | Terraform native tests + mock providers |
| Testes de integração completos | Terratest (Go) |
| Scan de segurança | trivy / checkov |
| Análise estática avançada | tflint |

### Terraform native tests (1.6+)

```hcl
# tests/unit.tftest.hcl
mock_provider "azurerm" {}

run "validates_environment" {
  variables {
    environment = "invalid"
  }
  expect_failures = [var.environment]
}

run "creates_resources_with_correct_tags" {
  variables {
    environment  = "dev"
    project_name = "myapp"
  }
  assert {
    condition     = azurerm_resource_group.this.tags["environment"] == "dev"
    error_message = "Tag environment incorreta"
  }
}
```

## Segurança

```bash
# trivy — scan de configurações IaC
trivy config --severity HIGH,CRITICAL .

# checkov — políticas de compliance
checkov -d . --framework terraform

# tflint — linting avançado com regras Azure
tflint --init
tflint --enable-plugin=azurerm
```

## Referências (carregar conforme necessário)

- `references/azure-patterns.md` — padrões Azure provider, AzureRM resources
- `references/cicd-workflows.md` — pipelines GitHub Actions e Azure DevOps
- `references/state-management.md` — backends, locking, workspaces vs separate state

## MUST DO / MUST NOT DO

### MUST DO
- Remote backend com state locking sempre em equipa
- `terraform fmt` antes de qualquer commit
- `prevent_destroy = true` em bases de dados e recursos críticos de prod
- Versões fixas para providers (`~> 3.0`, não `>= 3.0`)
- Separar ambientes em directorias distintas (não workspaces para isolamento crítico)
- Outputs documentados em todos os módulos
- Validações em variáveis com tipos explícitos

### MUST NOT DO
- State local em projetos de equipa
- Credenciais hardcoded (usar OIDC/Managed Identity)
- `terraform apply` direto sem `plan` em produção
- Módulos gigantes (>500 linhas) — dividir em módulos menores
- `depends_on` excessivo — usar referências implícitas sempre que possível
- Ignorar warnings do `terraform plan`
