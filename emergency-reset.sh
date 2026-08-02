#!/bin/bash
# Script de reset completo de emergência
# Use apenas se nada mais funcionar

# Cores
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}🚨 RESET COMPLETO DE EMERGÊNCIA${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${YELLOW}⚠️  ATENÇÃO: Esta operação irá:${NC}"
echo -e "   • Parar todos os containers"
echo -e "   • Remover todos os volumes (DADOS SERÃO PERDIDOS)"
echo -e "   • Remover imagens locais"
echo -e "   • Limpar cache do Docker"
echo -e "   • Reconstruir e subir tudo novamente"
echo ""

read -p "$(echo -e ${YELLOW}Tem certeza? Digite '"'yes'"' para confirmar: ${NC})" confirm

if [ "$confirm" != "yes" ]; then
  echo -e "\n${GREEN}✓ Operação cancelada${NC}"
  exit 0
fi

echo -e "\n${YELLOW}🛑 Parando todos os containers...${NC}"
docker-compose -f docker-compose.yml -f docker-compose.observability.yml down -v 2>/dev/null || true

echo -e "${YELLOW}🗑️  Removendo imagens locais...${NC}"
docker-compose down --rmi local 2>/dev/null || true

echo -e "${YELLOW}🧹 Limpando sistema Docker...${NC}"
docker system prune -f

echo -e "\n${YELLOW}🏗️  Reconstruindo e subindo tudo...${NC}"
./local.sh start

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Reset completo concluído!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${YELLOW}⏳ Aguarde ~60 segundos para todos os serviços ficarem prontos${NC}"
echo ""
echo -e "${YELLOW}📊 Então acesse:${NC}"
echo -e "   • Grafana:    http://localhost:3000 (admin/admin)"
echo -e "   • Jaeger:     http://localhost:16686"
echo -e "   • Prometheus: http://localhost:9090"
echo ""
echo -e "${YELLOW}🧪 E execute os testes:${NC}"
echo -e "   ./full-test.sh"
echo ""
