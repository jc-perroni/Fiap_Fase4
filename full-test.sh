#!/bin/bash
# Script completo de testes - verifica todos os endpoints e funcionalidades

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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para verificar se jq está instalado
check_jq() {
  if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq não está instalado. Saída será em JSON bruto.${NC}"
    echo -e "${BLUE}   Instale com: brew install jq${NC}\n"
    return 1
  fi
  return 0
}

# Função para formatar JSON (usa jq se disponível)
format_json() {
  if check_jq > /dev/null 2>&1; then
    jq .
  else
    cat
  fi
}

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🧪 Teste Completo - Feature Flag Platform${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 1. Health Checks
echo -e "${BLUE}1️⃣  Health Checks${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

SERVICES=("8001:Auth Service" "8002:Flag Service" "8003:Targeting Service" "8004:Evaluation Service" "8005:Analytics Service")

for service in "${SERVICES[@]}"; do
  IFS=':' read -r port name <<< "$service"
  
  if curl -s "http://localhost:${port}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} ${name} (${port})"
  else
    echo -e "${RED}✗${NC} ${name} (${port}) - OFFLINE"
  fi
done

# 2. Autenticação
echo -e "\n${BLUE}2️⃣  Teste de Autenticação${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Verificar se MASTER_KEY está configurada
if [ -z "$MASTER_KEY" ]; then
  echo -e "${RED}❌ MASTER_KEY não está configurada!${NC}\n"
  echo -e "${YELLOW}💡 Para configurar, faça uma das opções:${NC}\n"
  echo -e "   ${GREEN}Opção 1:${NC} Exportar no terminal (temporário)"
  echo -e "   export MASTER_KEY=\"12345\""
  echo ""
  echo -e "   ${GREEN}Opção 2:${NC} Editar o arquivo .env (permanente)"
  echo -e "   echo 'MASTER_KEY=12345' >> .env"
  echo ""
  echo -e "${BLUE}ℹ️  A MASTER_KEY padrão no .env é: 12345${NC}"
  echo -e "${BLUE}   (para produção, use: openssl rand -hex 32)${NC}\n"
  exit 1
fi

echo -e "${GREEN}✓ MASTER_KEY configurada: ${MASTER_KEY:0:3}...${MASTER_KEY: -2}${NC}"

# Validar se API_KEY existe
if [ -z "$API_KEY" ]; then
  echo -e "${YELLOW}⚠️  API_KEY não está definida. Tentando criar uma nova...${NC}\n"
  
  CREATE_RESULT=$(curl -s -X POST http://localhost:8001/admin/keys \
    -H "Authorization: Bearer ${MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-key-auto"}')
  
  if echo "$CREATE_RESULT" | grep -q "key"; then
    echo -e "${GREEN}✓ Nova API Key criada:${NC}"
    echo "$CREATE_RESULT" | format_json
    
    # Tentar extrair a chave
    if check_jq > /dev/null 2>&1; then
      API_KEY=$(echo "$CREATE_RESULT" | jq -r '.key')
      echo -e "\n${YELLOW}💡 Exporte esta chave para usar nos outros scripts:${NC}"
      echo -e "   ${GREEN}export API_KEY=\"${API_KEY}\"${NC}\n"
    else
      echo -e "\n${YELLOW}⚠️  Extraia manualmente o valor do campo 'key' e execute:${NC}"
      echo -e "   export API_KEY=\"ff_xxxxxxxx\"\n"
    fi
  else
    echo -e "${RED}✗ Falha ao criar API Key${NC}"
    echo "$CREATE_RESULT"
    exit 1
  fi
else
  echo -e "${GREEN}✓ API_KEY configurada: ${API_KEY:0:10}...${NC}"
  
  # Validar a chave
  echo -e "\n${YELLOW}Validando chave...${NC}"
  VALIDATE_RESULT=$(curl -s http://localhost:8001/validate \
    -H "Authorization: Bearer ${API_KEY}")
  
  if echo "$VALIDATE_RESULT" | grep -q "válida"; then
    echo -e "${GREEN}✓ Chave válida${NC}"
  else
    echo -e "${RED}✗ Chave inválida${NC}"
    echo "$VALIDATE_RESULT" | format_json
  fi
fi

# Se não temos API_KEY válida, parar aqui
if [ -z "$API_KEY" ]; then
  echo -e "\n${RED}❌ Não é possível continuar sem uma API Key válida${NC}"
  exit 1
fi

# 3. Flag Service
echo -e "\n${BLUE}3️⃣  Flag Service${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Criar uma flag de teste
echo -e "${YELLOW}Criando flag de teste...${NC}"
CREATE_FLAG_RESULT=$(curl -s -X POST http://localhost:8002/flags \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-flag-'$(date +%s)'",
    "description": "Flag de teste criada pelo full-test.sh",
    "is_enabled": true
  }')

if echo "$CREATE_FLAG_RESULT" | grep -q "name"; then
  echo -e "${GREEN}✓ Flag criada com sucesso${NC}"
  echo "$CREATE_FLAG_RESULT" | format_json
else
  echo -e "${YELLOW}⚠️  Flag pode já existir${NC}"
fi

# Listar flags
echo -e "\n${YELLOW}Listando todas as flags...${NC}"
LIST_FLAGS_RESULT=$(curl -s http://localhost:8002/flags \
  -H "Authorization: Bearer ${API_KEY}")

if check_jq > /dev/null 2>&1; then
  FLAG_COUNT=$(echo "$LIST_FLAGS_RESULT" | jq '. | length')
  echo -e "${GREEN}✓ Total de flags: ${FLAG_COUNT}${NC}"
  echo "$LIST_FLAGS_RESULT" | jq '.[] | {name: .name, enabled: .is_enabled}'
else
  echo "$LIST_FLAGS_RESULT"
fi

# 4. Targeting Service
echo -e "\n${BLUE}4️⃣  Targeting Service${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${YELLOW}Criando regra de targeting...${NC}"
CREATE_RULE_RESULT=$(curl -s -X POST http://localhost:8003/rules \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "flag_name": "test-flag-'$(date +%s)'",
    "is_enabled": true,
    "rules": {
      "type": "percentage",
      "value": 100
    }
  }')

if echo "$CREATE_RULE_RESULT" | grep -q "flag_name"; then
  echo -e "${GREEN}✓ Regra criada com sucesso${NC}"
  echo "$CREATE_RULE_RESULT" | format_json
else
  echo -e "${YELLOW}⚠️  Regra pode já existir${NC}"
fi

# 5. Evaluation Service
echo -e "\n${BLUE}5️⃣  Evaluation Service${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${YELLOW}Avaliando flags para diferentes usuários...${NC}\n"

for i in {1..5}; do
  USER_ID="test-user-${i}"
  EVAL_RESULT=$(curl -s "http://localhost:8004/evaluate?user_id=${USER_ID}&flag_name=nova-interface")
  
  if echo "$EVAL_RESULT" | grep -q "result"; then
    RESULT_VALUE=$(echo "$EVAL_RESULT" | grep -o '"result":[^,}]*' | cut -d':' -f2)
    
    if [ "$RESULT_VALUE" = "true" ]; then
      echo -e "${GREEN}✓${NC} ${USER_ID} → nova-interface = true"
    else
      echo -e "${BLUE}○${NC} ${USER_ID} → nova-interface = false"
    fi
  else
    echo -e "${RED}✗${NC} ${USER_ID} → erro ao avaliar"
  fi
done

# 6. Observabilidade
echo -e "\n${BLUE}6️⃣  Links de Observabilidade${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${GREEN}📊 Grafana:${NC}       http://localhost:3000 (admin/admin)"
echo -e "${GREEN}🔍 Jaeger:${NC}        http://localhost:16686"
echo -e "${GREEN}📈 Prometheus:${NC}    http://localhost:9090"

# Resumo final
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✨ Teste completo finalizado!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${BLUE}💡 Próximos passos:${NC}"
echo -e "   • Execute ${GREEN}./test-load.sh${NC} para gerar carga de teste"
echo -e "   • Execute ${GREEN}./continuous-load.sh${NC} para tráfego contínuo"
echo -e "   • Acesse o Grafana para visualizar as métricas"
echo ""
