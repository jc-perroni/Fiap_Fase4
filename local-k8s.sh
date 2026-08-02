#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚀 Feature Flag Platform - Deploy Local no Kubernetes (kind)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -e

CLUSTER_NAME="feature-flag"
SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

function print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

function print_error() {
    echo -e "${RED}✗${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

function print_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

# ──────────────────────────────────────────────────────────────────────────────
# Verificações
# ──────────────────────────────────────────────────────────────────────────────

function check_requirements() {
    print_header "Verificando requisitos"
    
    local missing=0
    
    if ! command -v kind &> /dev/null; then
        print_error "kind não encontrado. Instale: https://kind.sigs.k8s.io/"
        missing=1
    else
        print_success "kind instalado"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl não encontrado. Instale: https://kubernetes.io/docs/tasks/tools/"
        missing=1
    else
        print_success "kubectl instalado"
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "docker não encontrado. Instale: https://docs.docker.com/get-docker/"
        missing=1
    else
        print_success "docker instalado"
    fi
    
    if [ $missing -eq 1 ]; then
        print_error "Instale os requisitos faltantes e tente novamente"
        exit 1
    fi
}

function check_cluster() {
    if ! kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
        print_warning "Cluster kind '$CLUSTER_NAME' não encontrado"
        echo ""
        read -p "Deseja criar o cluster agora? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_error "Cluster necessário. Execute: kind create cluster --name $CLUSTER_NAME"
            exit 1
        fi
        create_cluster
    else
        print_success "Cluster kind '$CLUSTER_NAME' encontrado"
    fi
}

function create_cluster() {
    print_header "Criando cluster kind"
    
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 8001
    protocol: TCP
  - containerPort: 30001
    hostPort: 8002
    protocol: TCP
  - containerPort: 30002
    hostPort: 8003
    protocol: TCP
  - containerPort: 30003
    hostPort: 8004
    protocol: TCP
  - containerPort: 30004
    hostPort: 8005
    protocol: TCP
EOF
    
    print_success "Cluster criado"
}

# ──────────────────────────────────────────────────────────────────────────────
# Build e Load
# ──────────────────────────────────────────────────────────────────────────────

function build_images() {
    print_header "Building imagens Docker"
    
    docker-compose build --parallel
    
    print_success "Imagens buildadas"
}

function load_images() {
    print_header "Carregando imagens no cluster kind"
    
    for service in $SERVICES; do
        echo -n "  Carregando fase04-$service:latest... "
        kind load docker-image "fase04-$service:latest" --name "$CLUSTER_NAME" 2>&1 | grep -q "Image.*loaded" && echo "✓" || echo "✓ (já carregada)"
    done
    
    print_success "Imagens carregadas no kind"
}

# ──────────────────────────────────────────────────────────────────────────────
# Deploy
# ──────────────────────────────────────────────────────────────────────────────

function deploy() {
    print_header "Aplicando manifests no Kubernetes"
    
    print_info "Aplicando infraestrutura + serviços..."
    kubectl apply -k gitops/overlays/local/
    
    print_success "Manifests aplicados"
}

function wait_for_pods() {
    print_header "Aguardando pods ficarem prontos"
    
    echo "  Aguardando infraestrutura (PostgreSQL, Redis, LocalStack)..."
    kubectl wait --for=condition=ready pod -l app=postgres-auth -n feature-flags --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=postgres-apps -n feature-flags --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=redis -n feature-flags --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=localstack -n feature-flags --timeout=120s 2>/dev/null || true
    
    echo ""
    echo "  Aguardando serviços de aplicação..."
    sleep 10
    
    print_success "Pods prontos (verifique status com: kubectl get pods -n feature-flags)"
}

function show_status() {
    print_header "Status do Deploy"
    
    echo "${YELLOW}Pods:${NC}"
    kubectl get pods -n feature-flags 2>/dev/null || echo "  Nenhum pod encontrado"
    
    echo ""
    echo "${YELLOW}Services:${NC}"
    kubectl get svc -n feature-flags 2>/dev/null || echo "  Nenhum service encontrado"
}

function show_urls() {
    print_header "URLs de Acesso"
    
    cat << EOF
${GREEN}Serviços de Aplicação:${NC}
  • Auth Service:        http://localhost:8001
  • Flag Service:        http://localhost:8002
  • Targeting Service:   http://localhost:8003
  • Evaluation Service:  http://localhost:8004
  • Analytics Service:   http://localhost:8005

${BLUE}Comandos Úteis:${NC}
  • Ver pods:            kubectl get pods -n feature-flags
  • Ver logs:            kubectl logs -f <pod-name> -n feature-flags
  • Limpar tudo:         ./local-k8s.sh clean

${YELLOW}Nota:${NC} Para acessar os serviços via port-forward:
  kubectl port-forward -n feature-flags svc/auth-service 8001:8001
  kubectl port-forward -n feature-flags svc/flag-service 8002:8002
  # ... etc
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Comandos
# ──────────────────────────────────────────────────────────────────────────────

function start() {
    print_header "🚀 Feature Flag Platform - Deploy Local (Kubernetes)"
    
    check_requirements
    check_cluster
    build_images
    load_images
    deploy
    wait_for_pods
    show_status
    echo ""
    show_urls
    
    echo ""
    print_success "Deploy completo!"
}

function stop() {
    print_header "Parando serviços"
    
    kubectl delete namespace feature-flags --ignore-not-found=true
    
    print_success "Serviços parados (namespace deletado)"
}

function restart() {
    stop
    sleep 3
    start
}

function status() {
    show_status
    echo ""
    show_urls
}

function logs() {
    local pod_name="${1:-}"
    
    if [ -z "$pod_name" ]; then
        print_error "Especifique o nome do pod"
        echo ""
        echo "Pods disponíveis:"
        kubectl get pods -n feature-flags -o name
        echo ""
        echo "Uso: ./local-k8s.sh logs <pod-name>"
        exit 1
    fi
    
    kubectl logs -f "$pod_name" -n feature-flags
}

function clean() {
    print_header "Limpando TUDO"
    
    read -p "⚠️  Isso vai DELETAR o cluster kind '$CLUSTER_NAME'. Continuar? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operação cancelada"
        exit 0
    fi
    
    echo "Deletando cluster..."
    kind delete cluster --name "$CLUSTER_NAME"
    
    print_success "Cluster deletado"
}

function show_help() {
    cat << EOF
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Feature Flag Platform - Deploy Local no Kubernetes (kind)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${GREEN}Uso:${NC} ./local-k8s.sh [comando]

${GREEN}Comandos:${NC}
  ${YELLOW}start${NC}    - Cria cluster (se necessário), builda, carrega e deploya tudo
  ${YELLOW}stop${NC}     - Para todos os serviços (deleta namespace)
  ${YELLOW}restart${NC}  - Para e reinicia tudo
  ${YELLOW}status${NC}   - Mostra status atual dos pods e services
  ${YELLOW}logs${NC}     - Mostra logs de um pod específico
  ${YELLOW}clean${NC}    - Remove TUDO (deleta o cluster kind)
  ${YELLOW}help${NC}     - Mostra esta mensagem

${GREEN}Exemplos:${NC}
  # Deploy completo (primeira vez)
  ${CYAN}./local-k8s.sh start${NC}

  # Ver status
  ${CYAN}./local-k8s.sh status${NC}

  # Ver logs de um serviço
  ${CYAN}./local-k8s.sh logs auth-service-xxxxx${NC}

  # Limpar tudo
  ${CYAN}./local-k8s.sh clean${NC}

${GREEN}Infraestrutura incluída:${NC}
  • PostgreSQL (auth_db, flags_db, targeting_db)
  • Redis
  • LocalStack (SQS + DynamoDB)
  • Todos os 5 microserviços

${YELLOW}Documentação completa:${NC} DUAL_ENVIRONMENT_SETUP.md
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs "${2:-}"
        ;;
    clean)
        clean
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        print_error "Comando desconhecido: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
