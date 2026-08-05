#!/bin/bash
# ============================================================================
# Deploy Completo na AWS - Feature Flag Platform
# ============================================================================
# Este script provisiona toda a infraestrutura e faz deploy das aplicações
# Uso: ./deploy-aws.sh
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
REPO_URL="https://github.com/jc-perroni/fiap-fase-3.git"  # ← ATUALIZE COM SEU REPO
AWS_REGION="us-east-1"
CLUSTER_NAME="feature-flags-eks"

echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Deploy Completo - Feature Flag Platform (AWS)          ║"
echo "║   Terraform + EKS + ArgoCD + Observability (New Relic)        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================================
# Função: verificar pré-requisitos
# ============================================================================
check_prerequisites() {
  echo -e "${BOLD}📋 Verificando pré-requisitos...${NC}"
  
  # Terraform
  if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform não encontrado. Instale: https://terraform.io${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Terraform: $(terraform version | head -1)${NC}"
  
  # AWS CLI
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI não encontrado. Instale: https://aws.amazon.com/cli/${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ AWS CLI: $(aws --version)${NC}"
  
  # kubectl
  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl não encontrado. Instale: https://kubernetes.io/docs/tasks/tools/${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
  
  # Verificar credenciais AWS
  if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ Credenciais AWS inválidas. Execute: aws configure${NC}"
    exit 1
  fi
  
  AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  echo -e "${GREEN}✅ AWS Account: ${AWS_ACCOUNT}${NC}"
  echo ""
}

# ============================================================================
# Passo 1: Criar bucket S3 para Terraform state (se não existir)
# ============================================================================
setup_terraform_backend() {
  echo -e "${BOLD}${BLUE}1️⃣  Configurando Terraform Backend (S3)${NC}"
  
  BUCKET_NAME="fiap-terraform-state-${AWS_ACCOUNT}"
  echo "Bucket: ${BUCKET_NAME}"
  
  if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Criando bucket..."
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region ${AWS_REGION}
    
    aws s3api put-bucket-versioning \
      --bucket "${BUCKET_NAME}" \
      --versioning-configuration Status=Enabled
    
    echo -e "${GREEN}✅ Bucket criado: ${BUCKET_NAME}${NC}"
  else
    echo -e "${YELLOW}⏭️  Bucket já existe: ${BUCKET_NAME}${NC}"
  fi
  
  # Atualizar backend.tf se necessário
  if grep -q "YOUR_BUCKET_NAME" terraform/backend.tf 2>/dev/null; then
    echo "Atualizando backend.tf..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s/YOUR_BUCKET_NAME/${BUCKET_NAME}/g" terraform/backend.tf
    else
      sed -i "s/YOUR_BUCKET_NAME/${BUCKET_NAME}/g" terraform/backend.tf
    fi
    echo -e "${GREEN}✅ backend.tf atualizado${NC}"
  fi
  echo ""
}

# ============================================================================
# Passo 2: Provisionar infraestrutura com Terraform
# ============================================================================
provision_infrastructure() {
  echo -e "${BOLD}${BLUE}2️⃣  Provisionando Infraestrutura AWS (Terraform)${NC}"
  echo ""
  echo "⏱️  Isso pode levar 15-20 minutos..."
  echo ""
  
  cd terraform/
  
  # Solicitar senha do banco (se não estiver definida)
  if [ -z "$TF_VAR_db_password" ]; then
    read -sp "Digite a senha do PostgreSQL (será usada para auth/flag/targeting DBs): " DB_PASSWORD
    echo ""
    export TF_VAR_db_password="$DB_PASSWORD"
  fi
  
  # Inicializar
  echo "Executando: terraform init"
  terraform init
  
  # ──────────────────────────────────────────────────────────────────────────
  # ETAPA 1: Criar infraestrutura base (networking, databases, EKS)
  # ──────────────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}📦 ETAPA 1: Criando infraestrutura base (EKS, RDS, Redis, etc.)${NC}"
  echo ""
  
  terraform plan \
    -target=module.networking \
    -target=module.ecr \
    -target=module.databases \
    -target=module.messaging \
    -target=module.eks \
    -out=tfplan-stage1
  
  echo ""
  read -p "Continuar com terraform apply (Etapa 1)? (s/N): " APPLY_CONFIRM
  if [[ ! "$APPLY_CONFIRM" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}⏭️  Deploy cancelado pelo usuário${NC}"
    exit 0
  fi
  
  terraform apply tfplan-stage1
  
  echo -e "${GREEN}✅ Etapa 1 concluída (EKS cluster criado)${NC}"
  echo ""
  
  # ──────────────────────────────────────────────────────────────────────────
  # ETAPA 2: Instalar ArgoCD (requer cluster EKS existente)
  # ──────────────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}📦 ETAPA 2: Instalando ArgoCD no cluster${NC}"
  echo ""
  
  # Plan para ArgoCD
  terraform plan -target=module.argocd -out=tfplan-stage2
  
  echo ""
  read -p "Continuar com terraform apply (Etapa 2 - ArgoCD)? (s/N): " APPLY_CONFIRM2
  if [[ ! "$APPLY_CONFIRM2" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}⚠️  ArgoCD não instalado. Execute manualmente depois:${NC}"
    echo "   cd terraform/ && terraform apply -target=module.argocd"
  else
    terraform apply tfplan-stage2
    echo -e "${GREEN}✅ Etapa 2 concluída (ArgoCD instalado)${NC}"
  fi
  
  echo ""
  echo -e "${GREEN}✅ Infraestrutura provisionada${NC}"
  cd ..
  echo ""
}

# ============================================================================
# Passo 3: Configurar kubectl
# ============================================================================
configure_kubectl() {
  echo -e "${BOLD}${BLUE}3️⃣  Configurando kubectl para EKS${NC}"
  
  aws eks update-kubeconfig \
    --region ${AWS_REGION} \
    --name ${CLUSTER_NAME}
  
  echo "Aguardando cluster ficar pronto..."
  sleep 10
  
  if kubectl get nodes &> /dev/null; then
    echo -e "${GREEN}✅ kubectl configurado${NC}"
    kubectl get nodes
  else
    echo -e "${RED}❌ Erro ao conectar no cluster EKS${NC}"
    exit 1
  fi
  echo ""
}

# ============================================================================
# Passo 4: Atualizar URLs do repositório nos manifestos ArgoCD
# ============================================================================
update_gitops_urls() {
  echo -e "${BOLD}${BLUE}4️⃣  Atualizando URLs do GitOps${NC}"
  
  # Detectar URL do repositório remoto
  CURRENT_REPO=$(git remote get-url origin 2>/dev/null || echo "")
  
  if [ -z "$CURRENT_REPO" ]; then
    echo -e "${YELLOW}⚠️  Não foi possível detectar o repositório remoto${NC}"
    read -p "Digite a URL do seu repositório GitHub (https://github.com/...): " CURRENT_REPO
  fi
  
  echo "URL do repositório: ${CURRENT_REPO}"
  
  # Atualizar app-of-apps.yaml
  if grep -q "YOUR_USERNAME\|YOUR_REPO" gitops/argocd/app-of-apps.yaml 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|repoURL:.*|repoURL: ${CURRENT_REPO}|g" gitops/argocd/app-of-apps.yaml
    else
      sed -i "s|repoURL:.*|repoURL: ${CURRENT_REPO}|g" gitops/argocd/app-of-apps.yaml
    fi
    echo -e "${GREEN}✅ app-of-apps.yaml atualizado${NC}"
  fi
  
  # Atualizar observability.yaml
  if grep -q "YOUR_USERNAME\|YOUR_REPO" gitops/argocd/applications/observability.yaml 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|repoURL:.*github.com.*|repoURL: ${CURRENT_REPO}|g" gitops/argocd/applications/observability.yaml
    else
      sed -i "s|repoURL:.*github.com.*|repoURL: ${CURRENT_REPO}|g" gitops/argocd/applications/observability.yaml
    fi
    echo -e "${GREEN}✅ observability.yaml atualizado${NC}"
  fi
  echo ""
}

# ============================================================================
# Passo 5: Deploy do ArgoCD App of Apps
# ============================================================================
deploy_argocd() {
  echo -e "${BOLD}${BLUE}5️⃣  Fazendo Deploy do ArgoCD App of Apps${NC}"
  
  # Aguardar ArgoCD estar pronto (instalado pelo Terraform)
  echo "Aguardando ArgoCD ficar pronto..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd 2>/dev/null || true
  
  # Aplicar App of Apps
  kubectl apply -f gitops/argocd/app-of-apps.yaml
  
  echo -e "${GREEN}✅ ArgoCD configurado${NC}"
  echo ""
  echo "📊 Para acessar o ArgoCD UI:"
  echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "   URL: https://localhost:8080"
  echo ""
  echo "   Usuário: admin"
  echo "   Senha: \$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath=\"{.data.password}\" | base64 -d)"
  echo ""
}

# ============================================================================
# Passo 6: Aguardar sincronização das aplicações
# ============================================================================
wait_for_apps() {
  echo -e "${BOLD}${BLUE}6️⃣  Aguardando sincronização das aplicações...${NC}"
  echo ""
  echo "⏱️  Isso pode levar 5-10 minutos..."
  echo ""
  
  # Aguardar namespaces
  echo "Aguardando namespace feature-flags..."
  kubectl wait --for=jsonpath='{.status.phase}'=Active \
    namespace/feature-flags --timeout=300s 2>/dev/null || kubectl create namespace feature-flags
  
  echo "Aguardando namespace observability..."
  kubectl wait --for=jsonpath='{.status.phase}'=Active \
    namespace/observability --timeout=300s 2>/dev/null || kubectl create namespace observability
  
  # Aguardar deployments dos serviços
  echo ""
  echo "Aguardando deployments ficarem prontos..."
  for service in auth-service flag-service targeting-service evaluation-service analytics-service; do
    kubectl wait --for=condition=available --timeout=600s \
      deployment/${service} -n feature-flags 2>/dev/null && \
      echo -e "${GREEN}✅ ${service}${NC}" || \
      echo -e "${YELLOW}⏭️  ${service} (pode não estar sincronizado ainda)${NC}"
  done
  
  echo ""
  echo -e "${GREEN}✅ Deploy concluído${NC}"
  echo ""
}

# ============================================================================
# Passo 7: Validar e exibir informações
# ============================================================================
display_info() {
  echo -e "${BOLD}${GREEN}"
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                  ✅ DEPLOY CONCLUÍDO COM SUCESSO                ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  echo -e "${BOLD}📊 Recursos Provisionados:${NC}"
  echo ""
  
  # Outputs do Terraform
  cd terraform/
  echo "🗄️  Databases:"
  terraform output -json | jq -r '.rds_endpoints.value | to_entries[] | "   \(.key): \(.value)"' 2>/dev/null || true
  
  echo ""
  echo "🔴 Redis:"
  terraform output redis_endpoint 2>/dev/null | tr -d '"' | sed 's/^/   /' || echo "   (ver terraform output)"
  
  echo ""
  echo "📬 SQS:"
  terraform output sqs_queue_url 2>/dev/null | tr -d '"' | sed 's/^/   /' || echo "   (ver terraform output)"
  
  echo ""
  echo "🗃️  DynamoDB:"
  terraform output dynamodb_table_name 2>/dev/null | tr -d '"' | sed 's/^/   /' || echo "   (ver terraform output)"
  
  cd ..
  
  echo ""
  echo -e "${BOLD}🚀 Aplicações no Kubernetes:${NC}"
  kubectl get pods -n feature-flags
  
  echo ""
  echo -e "${BOLD}🔭 Observability Stack:${NC}"
  kubectl get pods -n observability
  
  echo ""
  echo -e "${BOLD}📝 Próximos Passos:${NC}"
  echo ""
  echo "1️⃣  Verificar New Relic:"
  echo "   → Acesse: https://one.newrelic.com"
  echo "   → Menu: APM & Services (aguarde ~5min para dados aparecerem)"
  echo ""
  echo "2️⃣  Verificar PagerDuty:"
  echo "   → Acesse: https://app.pagerduty.com"
  echo "   → Service: Feature Flag Platform - Production"
  echo ""
  echo "3️⃣  Testar aplicação:"
  echo "   → Obter URL do Ingress: kubectl get ingress -n feature-flags"
  echo "   → Criar API Key: curl -X POST http://\$INGRESS_URL/admin/keys"
  echo ""
  echo "4️⃣  Acessar Grafana (opcional):"
  echo "   → kubectl port-forward svc/grafana -n observability 3000:80"
  echo "   → URL: http://localhost:3000 (admin/admin)"
  echo ""
  echo -e "${BOLD}${GREEN}✨ Deploy finalizado com sucesso! 🎉${NC}"
  echo ""
}

# ============================================================================
# Função: cleanup (em caso de erro)
# ============================================================================
cleanup_on_error() {
  echo ""
  echo -e "${RED}❌ Erro durante o deploy!${NC}"
  echo ""
  echo "Para destruir os recursos e tentar novamente:"
  echo "   cd terraform/"
  echo "   terraform destroy"
  echo ""
  exit 1
}

trap cleanup_on_error ERR

# ============================================================================
# MAIN
# ============================================================================
main() {
  check_prerequisites
  setup_terraform_backend
  provision_infrastructure
  configure_kubectl
  update_gitops_urls
  deploy_argocd
  wait_for_apps
  display_info
}

# Executar
main
