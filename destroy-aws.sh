#!/bin/bash
# ============================================================================
# Destruir Infraestrutura AWS - Feature Flag Platform
# ============================================================================
# Remove todos os recursos AWS provisionados pelo Terraform
# Uso: ./destroy-aws.sh
# ============================================================================

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

AWS_REGION="us-east-1"
CLUSTER_NAME="feature-flags-eks"

echo -e "${BOLD}${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        ⚠️  DESTRUIR INFRAESTRUTURA AWS                         ║"
echo "║   Isso removerá TODOS os recursos provisionados               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}"
echo "Recursos que serão destruídos:"
echo "  - Cluster EKS (Kubernetes)"
echo "  - RDS PostgreSQL (3 instâncias)"
echo "  - ElastiCache Redis"
echo "  - DynamoDB table"
echo "  - SQS queue"
echo "  - VPC e subnets"
echo "  - ECR repositories (as imagens serão mantidas)"
echo ""
echo -e "${NC}"

read -p "Tem certeza que deseja continuar? Digite 'destroy' para confirmar: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
  echo -e "${GREEN}✅ Operação cancelada${NC}"
  exit 0
fi

echo ""
echo -e "${BOLD}${BLUE}🗑️  Iniciando destruição...${NC}"
echo ""

# ============================================================================
# Passo 1: Remover finalizers do ArgoCD (se existirem)
# ============================================================================
echo -e "${BOLD}1️⃣  Removendo finalizers do ArgoCD...${NC}"

if kubectl config current-context &> /dev/null; then
  # Remover finalizers das Applications
  kubectl patch application -n argocd feature-flags-apps -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  
  for app in auth-service flag-service targeting-service evaluation-service analytics-service observability-namespace prometheus-stack loki-stack grafana otel-collector alertmanager self-healing; do
    kubectl patch application -n argocd $app -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  done
  
  echo -e "${GREEN}✅ Finalizers removidos${NC}"
else
  echo -e "${YELLOW}⏭️  kubectl não configurado, pulando...${NC}"
fi

echo ""

# ============================================================================
# Passo 2: Destruir recursos Kubernetes manualmente (para acelerar)
# ============================================================================
echo -e "${BOLD}2️⃣  Removendo recursos Kubernetes...${NC}"

if kubectl config current-context &> /dev/null; then
  echo "Removendo namespaces..."
  kubectl delete namespace feature-flags --timeout=60s 2>/dev/null || true
  kubectl delete namespace observability --timeout=60s 2>/dev/null || true
  
  echo -e "${GREEN}✅ Namespaces removidos${NC}"
else
  echo -e "${YELLOW}⏭️  kubectl não configurado, pulando...${NC}"
fi

echo ""

# ============================================================================
# Passo 3: Terraform Destroy
# ============================================================================
echo -e "${BOLD}3️⃣  Executando Terraform Destroy...${NC}"
echo ""
echo "⏱️  Isso pode levar 10-15 minutos..."
echo ""

cd terraform/

if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
  echo -e "${YELLOW}⚠️  Terraform state não encontrado. Executando init...${NC}"
  terraform init
fi

terraform destroy -auto-approve

echo -e "${GREEN}✅ Terraform destroy concluído${NC}"

cd ..

echo ""

# ============================================================================
# Passo 4: Limpar configurações locais
# ============================================================================
echo -e "${BOLD}4️⃣  Limpando configurações locais...${NC}"

# Remover contexto do kubectl
kubectl config unset current-context 2>/dev/null || true
kubectl config delete-context arn:aws:eks:${AWS_REGION}:*:cluster/${CLUSTER_NAME} 2>/dev/null || true

echo -e "${GREEN}✅ Configurações locais limpas${NC}"

echo ""

# ============================================================================
# Resumo Final
# ============================================================================
echo -e "${BOLD}${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ INFRAESTRUTURA DESTRUÍDA                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BOLD}📝 Recursos Remanescentes (verificar manualmente):${NC}"
echo ""
echo "1️⃣  Bucket S3 do Terraform state (mantido para histórico):"
echo "   aws s3 ls | grep terraform-state"
echo ""
echo "2️⃣  Imagens no ECR (não são deletadas automaticamente):"
echo "   aws ecr describe-repositories --region ${AWS_REGION}"
echo ""
echo "3️⃣  Para remover o bucket S3 também:"
BUCKET_NAME="fiap-terraform-state-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'ACCOUNT_ID')"
echo "   aws s3 rb s3://${BUCKET_NAME} --force"
echo ""
echo "4️⃣  Para remover repositórios ECR:"
echo "   aws ecr delete-repository --repository-name pos2/auth-service --force --region ${AWS_REGION}"
echo "   # Repita para os outros 4 serviços"
echo ""
echo -e "${BOLD}${YELLOW}⚠️  Certifique-se de verificar o AWS Console para confirmar que todos os recursos foram removidos.${NC}"
echo ""
