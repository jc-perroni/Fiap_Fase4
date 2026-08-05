#!/bin/bash
# ============================================================================
# Build e Push de Imagens Docker para ECR
# ============================================================================
# Este script constrói as imagens Docker dos microserviços e envia para o ECR
# Uso: ./build-and-push.sh
# ============================================================================

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

# ============================================================================
# Configurações
# ============================================================================
AWS_REGION="us-east-1"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Lista de serviços (pasta:nome-ecr)
SERVICES=(
  "auth-service:pos2/auth-service"
  "flag-service:pos2/flag-service"
  "targeting-service:pos2/targeting-service"
  "evaluation-service:pos2/evaluation-service"
  "analytics-service:pos2/analytics-service"
)

echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          Build & Push Docker Images para ECR                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "AWS Account: ${AWS_ACCOUNT}"
echo "ECR Registry: ${ECR_BASE}"
echo ""

# ============================================================================
# Login no ECR
# ============================================================================
echo -e "${BOLD}${BLUE}🔐 Fazendo login no ECR...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_BASE}
echo -e "${GREEN}✅ Login no ECR realizado${NC}"
echo ""

# ============================================================================
# Build e Push de cada serviço
# ============================================================================
for service_def in "${SERVICES[@]}"; do
  IFS=':' read -r SERVICE_DIR ECR_REPO <<< "$service_def"
  IMAGE_TAG="${ECR_BASE}/${ECR_REPO}:latest"
  
  echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}📦 Processando: ${SERVICE_DIR}${NC}"
  echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Verificar se o diretório existe
  if [ ! -d "${SERVICE_DIR}" ]; then
    echo -e "${RED}❌ Diretório não encontrado: ${SERVICE_DIR}${NC}"
    continue
  fi
  
  # Build da imagem
  echo -e "${YELLOW}🔨 Building Docker image...${NC}"
  docker build -t ${IMAGE_TAG} ${SERVICE_DIR}/
  echo -e "${GREEN}✅ Build concluído: ${IMAGE_TAG}${NC}"
  
  # Push para ECR
  echo -e "${YELLOW}⬆️  Pushing para ECR...${NC}"
  docker push ${IMAGE_TAG}
  echo -e "${GREEN}✅ Push concluído: ${IMAGE_TAG}${NC}"
  echo ""
done

# ============================================================================
# Resumo Final
# ============================================================================
echo -e "${BOLD}${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ BUILD CONCLUÍDO                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BOLD}📋 Próximos passos:${NC}"
echo "1. Aguarde os pods reiniciarem no Kubernetes (1-3 minutos)"
echo "2. Verifique os pods: kubectl get pods -n feature-flags"
echo "3. Verifique as apps ArgoCD: kubectl get applications -n argocd"
echo ""
echo -e "${BOLD}🔍 Para forçar restart dos deployments:${NC}"
echo "   kubectl rollout restart deployment -n feature-flags"
echo ""
