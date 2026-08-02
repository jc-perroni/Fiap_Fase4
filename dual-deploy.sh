#!/bin/bash

# dual-deploy.sh - Helper para gerenciar deployments local e AWS

set -e

CLUSTER_NAME="feature-flag"
ECR_REGISTRY="639645545526.dkr.ecr.us-east-1.amazonaws.com/pos2"
SERVICES="auth-service flag-service targeting-service evaluation-service analytics-service"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

function print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

function print_error() {
    echo -e "${RED}✗${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ──────────────────────────────────────────────────────────────────────────────
# LOCAL ENVIRONMENT
# ──────────────────────────────────────────────────────────────────────────────

function build_local() {
    print_header "Building local images"
    docker-compose build
    print_success "Images built successfully"
}

function load_to_kind() {
    print_header "Loading images to kind cluster"
    
    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        print_error "Kind cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
    
    for service in $SERVICES; do
        echo "Loading fase04-$service:latest..."
        kind load docker-image "fase04-$service:latest" --name "$CLUSTER_NAME"
    done
    
    print_success "All images loaded to kind"
}

function deploy_local() {
    print_header "Deploying to local kind cluster"
    
    # Subir infraestrutura no Docker Compose
    print_warning "NOTE: Banks run on Docker Compose, not in Kubernetes"
    echo "Starting infrastructure services..."
    docker-compose up -d postgres-auth postgres-apps redis localstack
    
    # Aplicar manifests
    echo "Applying manifests..."
    kubectl apply -k gitops/overlays/local/
    
    print_success "Local deployment applied"
    echo ""
    echo "Check status: kubectl get pods -n feature-flags"
    echo ""
    print_warning "Services may fail to connect to databases (see DUAL_ENVIRONMENT_SETUP.md)"
}

function local_full() {
    build_local
    load_to_kind
    deploy_local
}

# ──────────────────────────────────────────────────────────────────────────────
# AWS ENVIRONMENT
# ──────────────────────────────────────────────────────────────────────────────

function push_to_ecr() {
    print_header "Pushing images to AWS ECR"
    
    echo "Authenticating with ECR..."
    aws ecr get-login-password --region us-east-1 | \
        docker login --username AWS --password-stdin "$ECR_REGISTRY"
    
    for service in $SERVICES; do
        local_image="fase04-$service:latest"
        ecr_image="$ECR_REGISTRY/$service:latest"
        
        echo "Tagging $service..."
        docker tag "$local_image" "$ecr_image"
        
        echo "Pushing $service..."
        docker push "$ecr_image"
        
        print_success "$service pushed"
    done
    
    print_success "All images pushed to ECR"
}

function deploy_aws() {
    print_header "Deploying to AWS via ArgoCD"
    
    echo "Applying ArgoCD app-of-apps..."
    kubectl apply -f gitops/argocd/app-of-apps.yaml -n argocd
    
    print_success "ArgoCD application created"
    echo ""
    echo "Check status: kubectl get applications -n argocd"
    echo "ArgoCD UI: https://localhost:8081"
}

function deploy_aws_direct() {
    print_header "Deploying to AWS directly (without ArgoCD)"
    
    echo "Applying manifests..."
    kubectl apply -k gitops/overlays/aws/
    
    print_success "AWS deployment applied"
    echo ""
    echo "Check status: kubectl get pods -n feature-flags"
}

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY
# ──────────────────────────────────────────────────────────────────────────────

function status() {
    print_header "Deployment Status"
    
    echo "Kubernetes Pods:"
    kubectl get pods -n feature-flags 2>/dev/null || echo "  No pods found"
    
    echo ""
    echo "ArgoCD Applications:"
    kubectl get applications -n argocd 2>/dev/null || echo "  No applications found"
    
    echo ""
    echo "Docker Compose Services:"
    docker-compose ps
}

function clean_local() {
    print_header "Cleaning local deployment"
    
    echo "Deleting Kubernetes resources..."
    kubectl delete namespace feature-flags --ignore-not-found=true
    
    echo "Stopping Docker Compose services..."
    docker-compose down
    
    print_success "Local environment cleaned"
}

function show_help() {
    cat << EOF
Usage: ./dual-deploy.sh [COMMAND]

${BLUE}LOCAL ENVIRONMENT (Kind + Docker Compose)${NC}
  build-local       Build Docker images locally
  load-kind         Load images to kind cluster
  deploy-local      Deploy to local kind (with Docker Compose infra)
  local-full        Build + Load + Deploy local

${BLUE}AWS ENVIRONMENT (EKS + ECR)${NC}
  push-ecr          Push images to AWS ECR
  deploy-aws        Deploy via ArgoCD (app-of-apps)
  deploy-aws-direct Deploy directly without ArgoCD

${BLUE}UTILITY${NC}
  status            Show deployment status
  clean-local       Clean local deployment
  help              Show this help message

${YELLOW}Examples:${NC}
  # Setup local development
  ./dual-deploy.sh local-full

  # Deploy to AWS
  ./dual-deploy.sh push-ecr
  ./dual-deploy.sh deploy-aws

  # Check status
  ./dual-deploy.sh status

${YELLOW}See also:${NC} DUAL_ENVIRONMENT_SETUP.md
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
    build-local)
        build_local
        ;;
    load-kind)
        load_to_kind
        ;;
    deploy-local)
        deploy_local
        ;;
    local-full)
        local_full
        ;;
    push-ecr)
        push_to_ecr
        ;;
    deploy-aws)
        deploy_aws
        ;;
    deploy-aws-direct)
        deploy_aws_direct
        ;;
    status)
        status
        ;;
    clean-local)
        clean_local
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
