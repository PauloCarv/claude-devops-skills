# claude-devops-skills

Marketplace of Claude Code plugins for DevOps operations.

## Installation

```bash
# 1. Add the marketplace (once per machine)
/plugin marketplace add https://github.com/PauloCarv/claude-devops-skills

# 2. Install the plugin(s) you need
/plugin install azure-devops@claude-devops-skills

# 3. Update when new versions are available
/plugin marketplace update
```

> **Private repo?** Make sure you have `gh auth login` done before installing.

## Plugins

| Plugin | Description | Docs |
|---|---|---|
| `azure-devops` | Agent and skills for Azure DevOps: Container Apps, APIM, Monitor, Terraform, Kubernetes | [README](plugins/azure-devops/README.md) |
