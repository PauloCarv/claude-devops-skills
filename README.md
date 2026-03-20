# claude-devops-skills

Claude Code agent and skills for Azure DevOps operations.

## Installation

```bash
# 1. Add the marketplace (once per machine)
/plugin marketplace add https://github.com/PauloCarv/claude-devops-skills

# 2. Install the plugin
/plugin install azure-devops@claude-devops-skills

# 3. Update when new versions are available
/plugin marketplace update
```

> **Private repo?** Make sure you have `gh auth login` done before installing.

## Contents

### Agent

- **azure-devops** — Senior Azure DevOps engineer. Applies naming conventions, enforces best practices, and coordinates the skills below.

### Skills (auto-activated)

| Skill | Activates when... |
|---|---|
| `azure-deploy` | deploy, Bicep, CI/CD pipeline, Azure infrastructure |
| `azure-monitor` | KQL, logs, metrics, Application Insights, alerts |
| `azure-apim` | APIM, API gateway, XML policies, rate limiting, OpenAI gateway |
| `azure-container-apps` | Container Apps, KEDA, Dapr, scaling, jobs |
| `terraform` | .tf files, IaC, modules, state, tests |
| `kubernetes-specialist` | K8s deployments, RBAC, Helm, probes |
| `k8s-security-policies` | K8s hardening, PSS, OPA, NetworkPolicies, mTLS |

## Updating a skill

Edit the corresponding `SKILL.md` file and push. Claude Code will pick up the changes automatically on the next session.

## Adding a new skill

```bash
mkdir -p plugins/azure-devops/skills/new-skill
# Create SKILL.md with frontmatter (name, description, invocation: auto)
git add . && git commit -m "feat: add new-skill" && git push
```
