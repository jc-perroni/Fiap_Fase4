#!/bin/bash
# ============================================================================
# Script de Configuração - New Relic + PagerDuty + Slack
# ============================================================================
# Este script facilita a configuração das integrações de observabilidade
# Uso: ./configure-observability.sh

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Configuração de Observabilidade - Feature Flag Platform     ║"
echo "║   New Relic + PagerDuty + Slack + Self-Healing                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# Verificações Iniciais
# ============================================================================
echo -e "${BOLD}📋 Verificando pré-requisitos...${NC}"

if [ ! -f "gitops/apps/observability/alertmanager.yaml" ]; then
  echo -e "${RED}❌ Erro: Arquivo alertmanager.yaml não encontrado${NC}"
  exit 1
fi

if [ ! -f "gitops/apps/observability/self-healing.yaml" ]; then
  echo -e "${RED}❌ Erro: Arquivo self-healing.yaml não encontrado${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Arquivos encontrados${NC}\n"

# ============================================================================
# 1. New Relic
# ============================================================================
echo -e "${BOLD}${BLUE}1️⃣  New Relic Configuration${NC}"
echo -e "${YELLOW}Status: JÁ CONFIGURADO ✅${NC}"
echo ""
echo "License Key já está configurada em:"
echo "  - .env"
echo "  - gitops/apps/observability/otel-collector-deployment.yaml"
echo ""
read -p "Pressione ENTER para continuar..."
echo ""

# ============================================================================
# 2. PagerDuty
# ============================================================================
echo -e "${BOLD}${BLUE}2️⃣  PagerDuty Configuration${NC}"
echo ""
echo "📖 Para obter sua PagerDuty Integration Key:"
echo "   1. Acesse: https://app.pagerduty.com"
echo "   2. Services → Service Directory → + New Service"
echo "   3. Name: 'Feature Flag Platform - Production'"
echo "   4. Integration Type: Events API v2"
echo "   5. Copie a Integration Key (32 caracteres)"
echo ""
read -p "Digite sua PagerDuty Integration Key (ou deixe em branco para pular): " PAGERDUTY_KEY

if [ ! -z "$PAGERDUTY_KEY" ]; then
  # Validar formato básico
  if [ ${#PAGERDUTY_KEY} -ne 32 ]; then
    echo -e "${YELLOW}⚠️  Aviso: PagerDuty key normalmente tem 32 caracteres. Continuando...${NC}"
  fi
  
  # Substituir no alertmanager.yaml
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'/service_key: '$PAGERDUTY_KEY'/g" \
      gitops/apps/observability/alertmanager.yaml
  else
    # Linux
    sed -i "s/service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'/service_key: '$PAGERDUTY_KEY'/g" \
      gitops/apps/observability/alertmanager.yaml
  fi
  
  echo -e "${GREEN}✅ PagerDuty configurado em alertmanager.yaml${NC}"
else
  echo -e "${YELLOW}⏭️  PagerDuty pulado (pode configurar manualmente depois)${NC}"
fi
echo ""

# ============================================================================
# 3. Slack
# ============================================================================
echo -e "${BOLD}${BLUE}3️⃣  Slack Configuration${NC}"
echo ""
echo "📖 Para obter sua Slack Webhook URL:"
echo "   1. Acesse: https://api.slack.com/apps"
echo "   2. Create New App → From scratch"
echo "   3. Features → Incoming Webhooks → Activate"
echo "   4. Add New Webhook to Workspace"
echo "   5. Copie a URL (https://hooks.slack.com/services/...)"
echo ""
read -p "Digite sua Slack Webhook URL (ou deixe em branco para pular): " SLACK_WEBHOOK

if [ ! -z "$SLACK_WEBHOOK" ]; then
  # Validar formato básico
  if [[ ! "$SLACK_WEBHOOK" =~ ^https://hooks.slack.com/services/ ]]; then
    echo -e "${YELLOW}⚠️  Aviso: URL do Slack não parece válida. Continuando...${NC}"
  fi
  
  # Substituir em ambos os arquivos
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|api_url: 'YOUR_SLACK_WEBHOOK_URL'|api_url: '$SLACK_WEBHOOK'|g" \
      gitops/apps/observability/alertmanager.yaml
    sed -i '' "s|slack-webhook-url: \"YOUR_SLACK_WEBHOOK_URL\"|slack-webhook-url: \"$SLACK_WEBHOOK\"|g" \
      gitops/apps/observability/self-healing.yaml
  else
    # Linux
    sed -i "s|api_url: 'YOUR_SLACK_WEBHOOK_URL'|api_url: '$SLACK_WEBHOOK'|g" \
      gitops/apps/observability/alertmanager.yaml
    sed -i "s|slack-webhook-url: \"YOUR_SLACK_WEBHOOK_URL\"|slack-webhook-url: \"$SLACK_WEBHOOK\"|g" \
      gitops/apps/observability/self-healing.yaml
  fi
  
  echo -e "${GREEN}✅ Slack configurado em alertmanager.yaml e self-healing.yaml${NC}"
else
  echo -e "${YELLOW}⏭️  Slack pulado (pode configurar manualmente depois)${NC}"
fi
echo ""

# ============================================================================
# 4. Self-Healing Webhook Password
# ============================================================================
echo -e "${BOLD}${BLUE}4️⃣  Self-Healing Webhook Password${NC}"
echo ""
echo "Gerando senha segura para o webhook de self-healing..."

# Gerar senha aleatória (funciona em macOS e Linux)
if command -v openssl &> /dev/null; then
  WEBHOOK_PASSWORD=$(openssl rand -hex 32)
elif command -v head &> /dev/null && [ -f /dev/urandom ]; then
  WEBHOOK_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 64)
else
  # Fallback simples
  WEBHOOK_PASSWORD=$(date +%s | sha256sum | base64 | head -c 64)
fi

# Substituir no self-healing.yaml
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|webhook-password: \"YOUR_WEBHOOK_PASSWORD\"|webhook-password: \"$WEBHOOK_PASSWORD\"|g" \
    gitops/apps/observability/self-healing.yaml
else
  # Linux
  sed -i "s|webhook-password: \"YOUR_WEBHOOK_PASSWORD\"|webhook-password: \"$WEBHOOK_PASSWORD\"|g" \
    gitops/apps/observability/self-healing.yaml
fi

echo -e "${GREEN}✅ Senha gerada e configurada em self-healing.yaml${NC}"
echo -e "${YELLOW}🔐 Senha gerada: ${WEBHOOK_PASSWORD}${NC}"
echo -e "${YELLOW}   (Guarde esta senha caso precise debug do webhook)${NC}"
echo ""

# ============================================================================
# Resumo
# ============================================================================
echo -e "${BOLD}${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ CONFIGURAÇÃO COMPLETA                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo "📋 Resumo das configurações:"
echo ""
echo "  ✅ New Relic:     Já configurado anteriormente"
if [ ! -z "$PAGERDUTY_KEY" ]; then
  echo "  ✅ PagerDuty:     Configurado (${PAGERDUTY_KEY:0:8}...)"
else
  echo "  ⏭️  PagerDuty:     Pulado (configure manualmente se necessário)"
fi

if [ ! -z "$SLACK_WEBHOOK" ]; then
  echo "  ✅ Slack:         Configurado"
else
  echo "  ⏭️  Slack:         Pulado (configure manualmente se necessário)"
fi

echo "  ✅ Self-Healing:  Senha gerada automaticamente"
echo ""

# ============================================================================
# Próximos Passos
# ============================================================================
echo -e "${BOLD}${BLUE}📌 Próximos Passos:${NC}"
echo ""
echo "1️⃣  Verificar alterações:"
echo "   git diff gitops/apps/observability/"
echo ""
echo "2️⃣  Commit e push:"
echo "   git add gitops/apps/observability/"
echo "   git commit -m \"feat(observability): configure PagerDuty, Slack and self-healing\""
echo "   git push origin main"
echo ""
echo "3️⃣  Deploy (se não usar ArgoCD):"
echo "   kubectl apply -f gitops/apps/observability/alertmanager.yaml"
echo "   kubectl apply -f gitops/apps/observability/self-healing.yaml"
echo ""
echo "4️⃣  Validar:"
echo "   kubectl get pods -n observability"
echo "   kubectl logs -n observability -l app=alertmanager --tail=50"
echo ""
echo "5️⃣  Acessar New Relic:"
echo "   https://one.newrelic.com"
echo ""
echo -e "${BOLD}${GREEN}✨ Configuração concluída! Boa sorte com o deploy! 🚀${NC}"
echo ""

# Perguntar se quer fazer commit automaticamente
read -p "Deseja fazer commit automaticamente agora? (s/N): " AUTO_COMMIT

if [[ "$AUTO_COMMIT" =~ ^[Ss]$ ]]; then
  echo ""
  echo "📦 Fazendo commit..."
  git add gitops/apps/observability/
  git commit -m "feat(observability): configure PagerDuty, Slack and self-healing" || true
  echo ""
  echo -e "${GREEN}✅ Commit realizado!${NC}"
  echo ""
  echo "Para enviar para o repositório remoto, execute:"
  echo "   git push origin main"
  echo ""
fi
