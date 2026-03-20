---
name: azure-deploy
description: |
  Skill for complete application deployment on Azure. Generates and validates:
  - Bicep templates for infrastructure
  - Azure DevOps pipeline YAML (multi-stage CI/CD)
  - Container Apps / AKS manifests
  - Rollback scripts
  Invoked automatically when the user asks about deploy, pipeline,
  Azure infrastructure, Bicep, Container Apps, or AKS.
invocation: auto
---

# Azure Deploy Skill

When this skill is invoked, you follow a structured process to generate
deploy artifacts ready to use on Azure.

## Mandatory process

### 1. Gather context (if not provided)
Ask (only what is missing):
- Project name and environment (dev/staging/prod)?
- Deploy type: Container Apps, AKS, App Service, Function App?
- Azure region (default: `westeurope`)?
- Needs a database? (PostgreSQL Flexible, SQL, CosmosDB)
- Using Azure DevOps or GitHub Actions?

### 2. Generate Bicep infrastructure
Always create `infra/main.bicep` with:
- Resource Group with tags
- Managed Identity for the application
- Key Vault with access policies
- Container Registry (if applicable)
- The main resource (Container App / AKS / etc.)
- Minimum required role assignments

### 3. Generate CI/CD pipeline

For **Azure DevOps**, create `.azure/pipelines/deploy.yml` with:
```yaml
# Mandatory structure:
stages:
  - stage: Build      # build + push image
  - stage: Dev        # automatic deploy
  - stage: Staging    # deploy with smoke tests
  - stage: Prod       # deploy with manual approval
```

For **GitHub Actions**, create `.github/workflows/deploy.yml` with
environments and required reviewers for prod.

### 4. Validation scripts

Use the `scripts/validate.sh` script (included in this skill) to:
- Check prerequisites (az cli, docker, kubectl)
- Validate Bicep before deploy (`az bicep build`)
- Confirm Azure connectivity
- Check quotas in the subscription

### 5. Rollback script

Always generate a documented `scripts/rollback.sh` with:
- How to revert to the previous version
- How to restore secrets from Key Vault
- How to verify the rollback was successful

## Reference templates

Refer to `references/bicep-patterns.md` for approved Bicep patterns.
Refer to `references/pipeline-patterns.md` for pipeline patterns.

## Expected output

Always present a summary at the end:
```
✅ GENERATED ARTIFACTS
====================
📁 infra/
   └── main.bicep          (complete infrastructure)
   └── parameters.dev.json
   └── parameters.prod.json

📁 .azure/pipelines/
   └── deploy.yml          (multi-stage pipeline)

📁 scripts/
   └── validate.sh         (pre-deploy validation)
   └── rollback.sh         (rollback procedure)

NEXT STEPS:
  1. Review and adjust parameters in parameters.prod.json
  2. Configure service connection in Azure DevOps
  3. Run: bash scripts/validate.sh
  4. Create PR and the pipeline triggers automatically
```
