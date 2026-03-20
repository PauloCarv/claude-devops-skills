---
name: terraform
description: >
  Terraform and OpenTofu specialist for production-ready IaC. Use when
  creating modules, configuring state backends, writing native tests
  or Terratest, CI/CD pipelines, Azure provider, security with trivy/checkov,
  or making IaC architecture decisions. Activates automatically for
  .tf, tfvars files, or any infrastructure-as-code request.
invocation: auto
---

# Terraform Skill

Complete guide for Terraform and OpenTofu — modules, tests, CI/CD and production
patterns. Based on terraform-best-practices.com and enterprise experience.

## Base workflow (always follow this order)

```bash
terraform init
terraform fmt -recursive        # format before anything else
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## Recommended project structure

```
infra/
├── environments/               # per-environment configurations
│   ├── prod/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   └── dev/
├── modules/                    # reusable modules
│   ├── networking/
│   ├── compute/
│   └── data/
└── examples/                   # usage examples (also serve as tests)
    ├── complete/
    └── minimal/
```

## Architecture decisions

### Remote state — mandatory in a team

```hcl
# Azure Backend (for Azure projects)
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate${var.project}${var.environment}"
    container_name       = "tfstate"
    key                  = "${var.project}/${var.environment}/terraform.tfstate"
    use_oidc             = true   # federation — no access keys
  }
}
```

### count vs for_each

```hcl
# ❌ Avoid count for resources with their own identity
resource "azurerm_resource_group" "this" {
  count = length(var.locations)
  name  = "rg-${var.locations[count.index]}"
}

# ✅ Use for_each — stable keys, no accidental recreation
resource "azurerm_resource_group" "this" {
  for_each = toset(var.locations)
  name     = "rg-${each.key}"
  location = each.key
}
```

### Resource naming

```hcl
# ✅ Descriptive and contextual
resource "azurerm_container_app" "api_gateway" { }
resource "azurerm_postgresql_flexible_server" "orders_db" { }

# ✅ "this" for singleton resources (only one of that type in the module)
resource "azurerm_resource_group" "this" { }
resource "azurerm_virtual_network" "this" { }

# ❌ Avoid redundancy in the name
resource "azurerm_virtual_network" "virtual_network" { }
```

## Modules — best practices

```hcl
# Variables: explicit types + validations
variable "environment" {
  type        = string
  description = "Deployment environment"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

# Outputs: always expose the id and useful attributes
output "id" {
  description = "Container App ID"
  value       = azurerm_container_app.this.id
}

output "fqdn" {
  description = "Public FQDN of the Container App"
  value       = azurerm_container_app.this.latest_revision_fqdn
}

# prevent_destroy on critical production resources
resource "azurerm_postgresql_flexible_server" "this" {
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [administrator_password]
  }
}
```

## Tests

### When to use each approach

| Scenario | Tool |
|---|---|
| Quick syntax validation | `terraform validate` |
| Module unit tests (no cloud) | Terraform native tests + mock providers |
| Full integration tests | Terratest (Go) |
| Security scan | trivy / checkov |
| Advanced static analysis | tflint |

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
    error_message = "Incorrect environment tag"
  }
}
```

## Security

```bash
# trivy — IaC configuration scan
trivy config --severity HIGH,CRITICAL .

# checkov — compliance policies
checkov -d . --framework terraform

# tflint — advanced linting with Azure rules
tflint --init
tflint --enable-plugin=azurerm
```

## References (load as needed)

- `references/azure-patterns.md` — Azure provider patterns, AzureRM resources
- `references/cicd-workflows.md` — GitHub Actions and Azure DevOps pipelines
- `references/state-management.md` — backends, locking, workspaces vs separate state

## MUST DO / MUST NOT DO

### MUST DO
- Remote backend with state locking always in a team
- `terraform fmt` before any commit
- `prevent_destroy = true` on databases and critical prod resources
- Fixed versions for providers (`~> 3.0`, not `>= 3.0`)
- Separate environments into distinct directories (not workspaces for critical isolation)
- Documented outputs in all modules
- Validations on variables with explicit types

### MUST NOT DO
- Local state in team projects
- Hardcoded credentials (use OIDC/Managed Identity)
- `terraform apply` directly without `plan` in production
- Giant modules (>500 lines) — split into smaller modules
- Excessive `depends_on` — use implicit references whenever possible
- Ignore warnings from `terraform plan`
