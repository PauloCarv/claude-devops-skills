# CI/CD Workflows — Terraform

## Azure DevOps Pipeline

```yaml
# .azure/pipelines/terraform.yml
trigger:
  branches:
    include: [main]
  paths:
    include: ['infra/**']

variables:
  - group: terraform-azure-credentials
  - name: TF_VERSION
    value: '1.7.0'
  - name: WORKING_DIR
    value: 'infra/environments/$(ENVIRONMENT)'

stages:

# ── VALIDATE & PLAN ────────────────────────────────────────────────────────
- stage: Plan
  displayName: '📋 Validate & Plan'
  jobs:
  - job: TerraformPlan
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: TerraformInstaller@1
      inputs:
        terraformVersion: $(TF_VERSION)

    - task: AzureCLI@2
      displayName: 'Terraform Init'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: bash
        workingDirectory: $(WORKING_DIR)
        scriptLocation: inlineScript
        inlineScript: |
          terraform init \
            -backend-config="resource_group_name=$(TF_STATE_RG)" \
            -backend-config="storage_account_name=$(TF_STATE_SA)" \
            -backend-config="container_name=tfstate" \
            -backend-config="key=$(ENVIRONMENT)/terraform.tfstate"

    - task: AzureCLI@2
      displayName: 'Terraform Validate & Format Check'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: bash
        workingDirectory: $(WORKING_DIR)
        scriptLocation: inlineScript
        inlineScript: |
          terraform validate
          terraform fmt -check -recursive

    - task: AzureCLI@2
      displayName: 'Security Scan (trivy)'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: bash
        workingDirectory: $(WORKING_DIR)
        scriptLocation: inlineScript
        inlineScript: |
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
          ./bin/trivy config --severity HIGH,CRITICAL .

    - task: AzureCLI@2
      displayName: 'Terraform Plan'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: bash
        workingDirectory: $(WORKING_DIR)
        scriptLocation: inlineScript
        inlineScript: |
          terraform plan \
            -var="environment=$(ENVIRONMENT)" \
            -out=tfplan \
            -detailed-exitcode
          
          # Guardar o plano como artefacto
          terraform show -json tfplan > tfplan.json

    - task: PublishPipelineArtifact@1
      inputs:
        targetPath: '$(WORKING_DIR)/tfplan'
        artifact: 'tfplan-$(ENVIRONMENT)'

# ── APPLY ──────────────────────────────────────────────────────────────────
- stage: Apply
  displayName: '🚀 Apply'
  dependsOn: Plan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: TerraformApply
    environment: '$(ENVIRONMENT)'   # approvals manuais para prod no UI
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - task: DownloadPipelineArtifact@2
            inputs:
              artifact: 'tfplan-$(ENVIRONMENT)'
              path: '$(WORKING_DIR)'

          - task: AzureCLI@2
            displayName: 'Terraform Apply'
            inputs:
              azureSubscription: 'azure-service-connection'
              scriptType: bash
              workingDirectory: $(WORKING_DIR)
              scriptLocation: inlineScript
              inlineScript: |
                terraform init  # re-init no agent de apply
                terraform apply tfplan
```

## GitHub Actions

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  push:
    branches: [main]
    paths: ['infra/**']
  pull_request:
    paths: ['infra/**']

permissions:
  id-token: write   # OIDC
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      TF_VERSION: "1.7.0"
      WORKING_DIR: infra/environments/${{ matrix.environment }}
    strategy:
      matrix:
        environment: [dev, staging, prod]

    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: ${{ env.TF_VERSION }}

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Terraform Init
      working-directory: ${{ env.WORKING_DIR }}
      run: terraform init

    - name: Terraform Plan
      id: plan
      working-directory: ${{ env.WORKING_DIR }}
      run: terraform plan -no-color -out=tfplan
      continue-on-error: true

    - name: Comment PR with Plan
      uses: actions/github-script@v7
      if: github.event_name == 'pull_request'
      with:
        script: |
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: '## Terraform Plan (${{ matrix.environment }})\n```\n${{ steps.plan.outputs.stdout }}\n```'
          })

  apply:
    needs: plan
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: ${{ matrix.environment }}   # required reviewers para prod
    strategy:
      matrix:
        environment: [dev, staging, prod]
      max-parallel: 1   # sequencial: dev → staging → prod

    steps:
    - uses: actions/checkout@v4
    - uses: hashicorp/setup-terraform@v3
    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    - run: terraform init && terraform apply tfplan
      working-directory: infra/environments/${{ matrix.environment }}
```
