# Padrões Bicep Aprovados

## Container App — padrão mínimo

```bicep
param projectName string
param environment string
param location string = resourceGroup().location
param containerImage string
param containerPort int = 8080

var tags = {
  environment: environment
  project: projectName
  owner: 'devops'
  'cost-center': 'engineering'
}

// Managed Identity (sempre — nunca usar connection strings diretas)
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${projectName}-${environment}-id'
  location: location
  tags: tags
}

// Container Apps Environment
resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${projectName}-${environment}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container App
resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${projectName}-${environment}-aca'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: {
        external: true
        targetPort: containerPort
      }
      secrets: []  // Usar Key Vault references, não valores diretos
    }
    template: {
      containers: [{
        name: projectName
        image: containerImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
      }]
      scale: {
        minReplicas: environment == 'prod' ? 2 : 0
        maxReplicas: environment == 'prod' ? 10 : 3
      }
    }
  }
}
```

## Key Vault — acesso via Managed Identity

```bicep
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${projectName}-${environment}-kv'
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true  // Usar RBAC, não access policies legacy
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
  }
}

// Role assignment: Key Vault Secrets User para a Managed Identity
resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, identity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

## Outputs obrigatórios

```bicep
output appUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
output identityClientId string = identity.properties.clientId
output keyVaultName string = kv.name
output acrLoginServer string = acr.properties.loginServer
```
