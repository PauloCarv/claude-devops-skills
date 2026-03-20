# Azure Provider Patterns — Terraform

## Recommended authentication (OIDC / Managed Identity)

```hcl
# Azure DevOps — OIDC (no service principal passwords)
provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id   # app registration with federated credential
}

# Local / CI with az login
provider "azurerm" {
  features {}
  # uses az login credentials automatically
}
```

## Resource Group with mandatory tags

```hcl
locals {
  required_tags = {
    environment  = var.environment
    project      = var.project_name
    owner        = var.owner
    cost-center  = var.cost_center
    managed-by   = "terraform"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags     = local.required_tags
}
```

## Container Apps — modular pattern

```hcl
resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${var.project_name}-${var.environment}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = local.required_tags
}

resource "azurerm_container_app" "this" {
  name                         = "ca-${var.project_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = local.required_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = var.project_name
      image  = "${azurerm_container_registry.this.login_server}/${var.project_name}:${var.image_tag}"
      cpu    = var.environment == "prod" ? 1.0 : 0.5
      memory = var.environment == "prod" ? "2Gi" : "1Gi"

      env {
        name        = "AZURE_CLIENT_ID"
        value       = azurerm_user_assigned_identity.this.client_id
      }
    }

    min_replicas = var.environment == "prod" ? 2 : 0
    max_replicas = var.environment == "prod" ? 10 : 3
  }
}
```

## Key Vault with RBAC

```hcl
resource "azurerm_key_vault" "this" {
  name                     = "kv-${var.project_name}-${var.environment}"
  location                 = azurerm_resource_group.this.location
  resource_group_name      = azurerm_resource_group.this.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  enable_rbac_authorization = true   # RBAC instead of legacy access policies
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7
  purge_protection_enabled   = var.environment == "prod"
  tags                       = local.required_tags
}

# Managed Identity accesses Key Vault via RBAC
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
```

## AKS — base configuration

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "${var.project_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  tags                = local.required_tags

  default_node_pool {
    name                = "system"
    node_count          = var.environment == "prod" ? 3 : 1
    vm_size             = var.environment == "prod" ? "Standard_D4s_v3" : "Standard_B2s"
    os_disk_size_gb     = 128
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = var.environment == "prod" ? 3 : 1
    max_count           = var.environment == "prod" ? 10 : 3
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"   # NetworkPolicies
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  lifecycle {
    prevent_destroy = var.environment == "prod"
    ignore_changes  = [kubernetes_version]   # upgrades managed separately
  }
}
```

## Recommended provider versions

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```
