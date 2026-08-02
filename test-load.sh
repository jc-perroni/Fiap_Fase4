#!/bin/bash
# Script de carga básico para testar a plataforma de feature flags
# Gera 20 requisições para múltiplos usuários e flags

set -e

# Carregar .env se existir
if [ -f .env ]; then
  export $(grep -v '^#' .env | grep -v '^$' | xargs)
fi

# Configuração
API_KEY="${API_KEY:-}"
MASTER_KEY="${MASTER_KEY:-}"

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Script de Carga - Feature Flag Platform${NC}\n"

# Verificar se API_KEY está definida
if [ -z "$API_KEY" ]; then
  echo -e "${RED}❌ Erro: API_KEY não está definida${NC}"
  echo -e "${YELLOW}💡 Como obter uma API Key:${NC}"
  echo ""
  echo "  1. Certifique-se de que os serviços estão rodando:"
  echo "     ./local.sh start"
  echo ""
  echo "  2. Crie uma API Key:"
  echo "     curl -X POST http://localhost:8001/admin/keys \\"
  echo "       -H \"Authorization: Bearer \${MASTER_KEY}\" \\"
  echo "       -H \"Content-Type: application/json\" \\"
  echo "       -d '{\"name\": \"test-key\"}'"
  echo ""
  echo "  3. Exporte a chave retornada:"
  echo "     export API_KEY=\"ff_xxxxxxxx\""
  echo ""
  echo "  4. Execute este script novamente"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓ API_KEY configurada${NC}"

# Verificar se os serviços estão rodando
echo -e "\n${YELLOW}🔍 Verificando serviços...${NC}"
if ! curl -s http://localhost:8004/health > /dev/null 2>&1; then
  echo -e "${RED}❌ Evaluation Service não está respondendo${NC}"
  echo -e "${YELLOW}💡 Execute: ./local.sh start${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Serviços online${NC}"

# Criar flags de teste se ainda não existirem
echo -e "\n${YELLOW}📝 Preparando flags de teste...${NC}"

FLAGS=(
  "nova-interface:Habilita a nova interface do usuário"
  "dark-mode:Habilita modo escuro"
  "beta-features:Funcionalidades experimentais"
  "premium-access:Acesso a recursos premium"
)

for flag_data in "${FLAGS[@]}"; do
  IFS=':' read -r name description <<< "$flag_data"
  
  # Tentar criar (ignora se já existir)
  curl -s -X POST http://localhost:8002/flags \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${name}\", \"description\": \"${description}\", \"is_enabled\": true}" \
    > /dev/null 2>&1 || true
done

echo -e "${GREEN}✓ Flags preparadas${NC}"

# Gerar carga de teste
echo -e "\n${YELLOW}⚡ Gerando carga de teste (20 usuários × 4 flags = 80 requisições)...${NC}\n"

TOTAL_REQUESTS=0
SUCCESSFUL_REQUESTS=0

for i in {1..20}; do
  USER_ID="user-$(printf "%03d" $i)"
  
  # Avaliar várias flags para cada usuário
  for flag in "nova-interface" "dark-mode" "beta-features" "premium-access"; do
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    
    RESULT=$(curl -s "http://localhost:8004/evaluate?user_id=${USER_ID}&flag_name=${flag}")
    
    if echo "$RESULT" | grep -q "result"; then
      SUCCESSFUL_REQUESTS=$((SUCCESSFUL_REQUESTS + 1))
      echo -e "${GREEN}✓${NC} ${USER_ID} → ${flag}"
    else
      echo -e "${RED}✗${NC} ${USER_ID} → ${flag} (falhou)"
    fi
  done
  
  sleep 0.2  # Pequeno delay para não sobrecarregar
done

# Resumo
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✨ Carga de teste concluída!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total de requisições: ${TOTAL_REQUESTS}"
echo -e "Requisições bem-sucedidas: ${SUCCESSFUL_REQUESTS}"
echo -e "Taxa de sucesso: $((SUCCESSFUL_REQUESTS * 100 / TOTAL_REQUESTS))%"
echo ""
echo -e "${YELLOW}📊 Visualize os dados no Grafana:${NC}"
echo -e "   http://localhost:3000 (admin/admin)"
echo ""
echo -e "${YELLOW}🔍 Veja traces no Jaeger:${NC}"
echo -e "   http://localhost:16686"
echo ""
