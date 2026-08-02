#!/bin/bash

# =============================================================================
# Script de Acesso Rápido ao Dashboard
# =============================================================================
# Abre o dashboard de observabilidade no navegador padrão
#
# Uso: ./open-dashboard.sh
# =============================================================================

set -e

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Dashboard de Observabilidade - Feature Flag Platform${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Verifica se Grafana está rodando
echo -n "🔍 Verificando Grafana... "
if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Online"
else
    echo -e "${RED}✗${NC} Offline"
    echo ""
    echo -e "${YELLOW}⚠️  Grafana não está rodando!${NC}"
    echo ""
    echo "Inicie os serviços com:"
    echo "  docker-compose -f docker-compose.yml -f docker-compose.observability.yml up -d"
    echo ""
    exit 1
fi

# Verifica containers
echo -n "🐳 Verificando containers... "
RUNNING=$(docker ps --filter "name=fase04" --format "{{.Names}}" | wc -l)
echo -e "${GREEN}✓${NC} $RUNNING containers ativos"

echo ""
echo -e "${GREEN}📊 Dashboards Disponíveis:${NC}"
echo ""
echo "1. Dashboard Completo (RECOMENDADO)"
echo "   URL: http://localhost:3000/d/feature-flag-complete"
echo "   → Saúde do ecossistema"
echo "   → Uso de recursos (CPU, memória, rede)"
echo "   → Taxa de requisições"
echo "   → Logs em tempo real"
echo ""
echo "2. Dashboard Original"
echo "   URL: http://localhost:3000/d/feature-flag-overview"
echo ""

# Abre no navegador (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -ne "${YELLOW}🌐 Abrindo dashboard completo no navegador... ${NC}"
    open "http://localhost:3000/d/feature-flag-complete/feature-flag-platform-observabilidade-completa?orgId=1&refresh=5s"
    echo -e "${GREEN}✓${NC}"
# Linux
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -ne "${YELLOW}🌐 Abrindo dashboard completo no navegador... ${NC}"
    xdg-open "http://localhost:3000/d/feature-flag-complete/feature-flag-platform-observabilidade-completa?orgId=1&refresh=5s" 2>/dev/null
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠️  Não foi possível abrir o navegador automaticamente${NC}"
    echo "   Acesse manualmente: http://localhost:3000/d/feature-flag-complete"
fi

echo ""
echo -e "${BLUE}🔐 Credenciais:${NC}"
echo "   Usuário: admin"
echo "   Senha: admin"
echo ""

echo -e "${BLUE}🔗 Outros Componentes:${NC}"
echo "   • Prometheus: http://localhost:9090"
echo "   • Jaeger: http://localhost:16686"
echo "   • Loki: http://localhost:3100"
echo "   • cAdvisor: http://localhost:8080"
echo ""

echo -e "${BLUE}🧪 Gerar Dados de Teste:${NC}"
echo "   ./test-load.sh       # 80 requisições de teste"
echo "   ./full-test.sh       # Teste completo do sistema"
echo ""

echo -e "${GREEN}✨ Dashboard aberto com sucesso!${NC}"
echo ""
