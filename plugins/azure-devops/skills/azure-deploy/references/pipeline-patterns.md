# Azure DevOps Pipeline Patterns

## Multi-stage pipeline (approved pattern)

```yaml
# .azure/pipelines/deploy.yml
trigger:
  branches:
    include: [main]
  paths:
    exclude: ['**.md', 'docs/**']

variables:
  - group: azure-credentials        # Service principal / federation
  - name: ACR_NAME
    value: 'myprojprodacr'
  - name: IMAGE_NAME
    value: '$(ACR_NAME).azurecr.io/$(Build.Repository.Name)'

stages:

# ── BUILD ──────────────────────────────────────────────────────────────────
- stage: Build
  displayName: '🔨 Build & Push'
  jobs:
  - job: BuildImage
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: AzureCLI@2
      displayName: 'Build & push to ACR'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          az acr build \
            --registry $(ACR_NAME) \
            --image $(IMAGE_NAME):$(Build.BuildId) \
            --image $(IMAGE_NAME):latest \
            .

# ── DEV ────────────────────────────────────────────────────────────────────
- stage: Dev
  displayName: '🔵 Deploy Dev'
  dependsOn: Build
  variables:
    - group: env-dev
  jobs:
  - deployment: DeployDev
    environment: 'dev'             # No approvals
    strategy:
      runOnce:
        deploy:
          steps:
          - template: templates/deploy-container-app.yml
            parameters:
              environment: dev
              imageTag: $(Build.BuildId)

# ── STAGING ────────────────────────────────────────────────────────────────
- stage: Staging
  displayName: '🟡 Deploy Staging'
  dependsOn: Dev
  variables:
    - group: env-staging
  jobs:
  - deployment: DeployStaging
    environment: 'staging'
    strategy:
      runOnce:
        deploy:
          steps:
          - template: templates/deploy-container-app.yml
            parameters:
              environment: staging
              imageTag: $(Build.BuildId)
          - task: AzureCLI@2
            displayName: 'Smoke tests'
            inputs:
              azureSubscription: 'azure-service-connection'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                APP_URL=$(az containerapp show \
                  -n myapp-staging-aca -g myapp-staging-rg \
                  --query 'properties.configuration.ingress.fqdn' -o tsv)
                curl -f "https://$APP_URL/health" || exit 1

# ── PROD ───────────────────────────────────────────────────────────────────
- stage: Prod
  displayName: '🟢 Deploy Prod'
  dependsOn: Staging
  variables:
    - group: env-prod
  jobs:
  - deployment: DeployProd
    environment: 'prod'            # Configure approvals in Azure DevOps UI
    strategy:
      runOnce:
        deploy:
          steps:
          - template: templates/deploy-container-app.yml
            parameters:
              environment: prod
              imageTag: $(Build.BuildId)
```

## Reusable template: deploy-container-app.yml

```yaml
# .azure/pipelines/templates/deploy-container-app.yml
parameters:
  - name: environment
    type: string
  - name: imageTag
    type: string

steps:
- task: AzureCLI@2
  displayName: 'Deploy Container App (${{ parameters.environment }})'
  inputs:
    azureSubscription: 'azure-service-connection'
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az containerapp update \
        --name myapp-${{ parameters.environment }}-aca \
        --resource-group myapp-${{ parameters.environment }}-rg \
        --image $(IMAGE_NAME):${{ parameters.imageTag }} \
        --set-env-vars \
          ENVIRONMENT=${{ parameters.environment }} \
          VERSION=${{ parameters.imageTag }}

      # Verify deployment
      az containerapp revision list \
        --name myapp-${{ parameters.environment }}-aca \
        --resource-group myapp-${{ parameters.environment }}-rg \
        --query "[0].{name:name,active:properties.active,replicas:properties.replicas}" \
        -o table
```
