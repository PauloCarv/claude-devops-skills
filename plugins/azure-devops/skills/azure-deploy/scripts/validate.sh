#!/usr/bin/env bash
# =============================================================================
# validate.sh — Pré-requisitos e validação antes de deploy Azure
# Bundled com a skill azure-deploy
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "🔍 Validação pré-deploy Azure"
echo "=============================="

# 1. Ferramentas
echo -e "\n[1/4] Ferramentas"
command -v az      &>/dev/null && ok "Azure CLI instalado"      || fail "Azure CLI não encontrado. Instala: https://aka.ms/installazurecliwindows"
command -v docker  &>/dev/null && ok "Docker instalado"         || warn "Docker não encontrado (necessário para builds locais)"
command -v kubectl &>/dev/null && ok "kubectl instalado"        || warn "kubectl não encontrado (necessário para AKS)"
command -v bicep   &>/dev/null && ok "Bicep CLI instalado"      || warn "Bicep não encontrado. Instala: az bicep install"

# 2. Autenticação Azure
echo -e "\n[2/4] Autenticação Azure"
ACCOUNT=$(az account show --query "{name:name, id:id, user:user.name}" -o json 2>/dev/null) || fail "Não autenticado. Executa: az login"
SUBSCRIPTION=$(echo $ACCOUNT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['name'])")
SUB_ID=$(echo $ACCOUNT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])")
USER=$(echo $ACCOUNT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['user'])")
ok "Autenticado como: $USER"
ok "Subscription: $SUBSCRIPTION ($SUB_ID)"

# 3. Validar Bicep (se existir)
echo -e "\n[3/4] Validação Bicep"
if [ -f "infra/main.bicep" ]; then
    az bicep build --file infra/main.bicep --stdout > /dev/null 2>&1 \
        && ok "infra/main.bicep válido" \
        || fail "Erros no infra/main.bicep. Executa: az bicep build --file infra/main.bicep"
else
    warn "infra/main.bicep não encontrado — skipping"
fi

# 4. Verificar quotas básicas na região
echo -e "\n[4/4] Quotas (westeurope)"
LOCATION="${AZURE_LOCATION:-westeurope}"
CORES=$(az vm list-usage --location $LOCATION --query "[?name.value=='cores'].{limit:limit,current:currentValue}" -o json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d[0]['current']}/{d[0]['limit']}\") if d else print('N/A')")
ok "vCPUs utilizados/limite em $LOCATION: $CORES"

echo -e "\n${GREEN}✅ Validação concluída!${NC}"
