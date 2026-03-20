# azure-devops

Claude Code agent and skills for Azure DevOps operations.

## Installation

```bash
/plugin install azure-devops@claude-devops-skills
```

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

## Recommended Global Hooks

These hooks run across all projects and add safety guards for Azure CLI and Terraform. Set them up once per machine.

### 1. Create the hook scripts

```bash
mkdir -p ~/.claude/hooks
```

**`~/.claude/hooks/azure-guard.sh`** — blocks destructive Azure CLI commands:

```bash
#!/usr/bin/env bash
input=$(cat)
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null)

DESTRUCTIVE_PATTERNS=(
  "az group delete" "az vm delete" "az aks delete"
  "az containerapp delete" "az acr delete" "az keyvault delete"
  "az storage account delete" "az sql server delete"
  "az cosmosdb delete" "az network vnet delete"
)

for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$command" | grep -q "$pattern"; then
    echo "BLOCKED: Destructive Azure command detected: '$pattern'" >&2
    echo "Run the command manually in your terminal if you are sure." >&2
    exit 1
  fi
done
exit 0
```

**`~/.claude/hooks/tf-fmt.sh`** — auto-formats `.tf` files on save:

```bash
#!/usr/bin/env bash
input=$(cat)
file_path=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

if [[ "$file_path" == *.tf ]]; then
  if command -v terraform &>/dev/null; then
    terraform fmt "$file_path" 2>/dev/null
  fi
fi
exit 0
```

```bash
chmod +x ~/.claude/hooks/azure-guard.sh ~/.claude/hooks/tf-fmt.sh
```

### 2. Register in `~/.claude/settings.json`

Add the following `hooks` block to your global settings:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/<your-user>/.claude/hooks/azure-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/<your-user>/.claude/hooks/tf-fmt.sh"
          }
        ]
      }
    ]
  }
}
```

> Replace `<your-user>` with your macOS username (e.g. `paucarv`).

| Hook | Trigger | Effect |
|---|---|---|
| `azure-guard` | Every `Bash` call | Blocks 10 destructive `az` commands; requires manual confirmation |
| `tf-fmt` | Every `Write` or `Edit` on a `.tf` file | Runs `terraform fmt` automatically |

---

## Updating a skill

Edit the corresponding `SKILL.md` file and push. Claude Code will pick up the changes automatically on the next session.

## Adding a new skill

```bash
mkdir -p plugins/azure-devops/skills/new-skill
# Create SKILL.md with frontmatter (name, description, invocation: auto)
git add . && git commit -m "feat: add new-skill" && git push
```
