---
name: azure-deploy
description: |
  Skill para deploy completo de aplicações no Azure. Gera e valida:
  - Bicep templates para infraestrutura
  - Azure DevOps pipeline YAML (CI/CD multi-stage)
  - Container Apps / AKS manifests
  - Scripts de rollback
  Invoca automaticamente quando o utilizador pede deploy, pipeline, 
  infraestrutura Azure, Bicep, Container Apps ou AKS.
invocation: auto
---

# Azure Deploy Skill

Quando esta skill é invocada, segues um processo estruturado para gerar
artefactos de deploy prontos a usar no Azure.

## Processo obrigatório

### 1. Recolher contexto (se não fornecido)
Pergunta (apenas o que falta):
- Nome do projeto e ambiente (dev/staging/prod)?
- Tipo de deploy: Container Apps, AKS, App Service, Function App?
- Região Azure (default: `westeurope`)?
- Precisa de base de dados? (PostgreSQL Flexible, SQL, CosmosDB)
- Usa Azure DevOps ou GitHub Actions?

### 2. Gerar infraestrutura Bicep
Cria sempre `infra/main.bicep` com:
- Resource Group com tags
- Managed Identity para a aplicação
- Key Vault com access policies
- Container Registry (se aplicável)
- O recurso principal (Container App / AKS / etc.)
- Role assignments mínimos necessários

### 3. Gerar pipeline CI/CD

Para **Azure DevOps**, cria `.azure/pipelines/deploy.yml` com:
```yaml
# Estrutura obrigatória:
stages:
  - stage: Build      # build + push imagem
  - stage: Dev        # deploy automático
  - stage: Staging    # deploy com smoke tests
  - stage: Prod       # deploy com aprovação manual
```

Para **GitHub Actions**, cria `.github/workflows/deploy.yml` com
environments e required reviewers para prod.

### 4. Scripts de validação

Usa o script `scripts/validate.sh` (incluído nesta skill) para:
- Verificar pré-requisitos (az cli, docker, kubectl)
- Validar Bicep antes do deploy (`az bicep build`)
- Confirmar conectividade ao Azure
- Verificar quotas na subscription

### 5. Script de rollback

Gera sempre `scripts/rollback.sh` documentado com:
- Como reverter para a versão anterior
- Como restaurar secrets do Key Vault
- Como verificar que o rollback foi bem sucedido

## Templates de referência

Consulta `references/bicep-patterns.md` para padrões aprovados de Bicep.
Consulta `references/pipeline-patterns.md` para padrões de pipeline.

## Output esperado

Apresenta sempre um resumo no final:
```
✅ ARTEFACTOS GERADOS
====================
📁 infra/
   └── main.bicep          (infraestrutura completa)
   └── parameters.dev.json
   └── parameters.prod.json

📁 .azure/pipelines/
   └── deploy.yml          (pipeline multi-stage)

📁 scripts/
   └── validate.sh         (validação pré-deploy)
   └── rollback.sh         (procedimento de rollback)

PRÓXIMOS PASSOS:
  1. Rever e ajustar parâmetros em parameters.prod.json
  2. Configurar service connection no Azure DevOps
  3. Executar: bash scripts/validate.sh
  4. Criar PR e pipeline dispara automaticamente
```
