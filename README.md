# claude-devops-skills

Marketplace privado de agents e skills Claude Code para DevOps Azure.

## Instalação

```bash
# 1. Adicionar o marketplace (uma vez por máquina)
/plugin marketplace add https://github.com/PauloCarv/claude-devops-skills

# 2. Instalar o plugin
/plugin install azure-devops@claude-devops-skills

# 3. Atualizar quando houver novidades
/plugin marketplace update
```

> **Repo privado?** Garante que tens `gh auth login` feito antes de instalar.

## Conteúdo

### Agente
- **azure-devops** — especialista Azure, aplica convenções de nomenclatura, boas práticas e coordena as skills

### Skills (ativação automática)

| Skill | Ativa quando... |
|---|---|
| `azure-deploy` | deploy, Bicep, pipeline, infraestrutura Azure |
| `azure-monitor` | KQL, logs, métricas, Application Insights, alertas |
| `azure-apim` | APIM, API gateway, políticas, rate limiting, OpenAI gateway |
| `azure-container-apps` | Container Apps, KEDA, Dapr, scaling, jobs |
| `terraform` | ficheiros .tf, IaC, módulos, state, testes |
| `kubernetes-specialist` | deployments K8s, RBAC, Helm, probes |
| `k8s-security-policies` | hardening K8s, PSS, OPA, NetworkPolicies, mTLS |

## Atualizar uma skill

Edita o ficheiro `SKILL.md` correspondente e faz `git push`. Na próxima sessão do Claude Code o plugin é atualizado automaticamente.

## Adicionar uma nova skill

```bash
mkdir -p plugins/azure-devops/skills/nova-skill
# Cria SKILL.md com frontmatter (name, description, invocation: auto)
git add . && git commit -m "feat: add nova-skill" && git push
```
