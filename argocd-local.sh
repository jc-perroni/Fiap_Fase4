#!/bin/bash

# Script helper para gerenciar ArgoCD local com kind
# Uso: ./argocd-local.sh [install|start|stop|login|ui|apps|clean|help]

set -e

CLUSTER_NAME="feature-flag"
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="stable"

function check_dependencies() {
    local missing=()
    
    command -v kind >/dev/null 2>&1 || missing+=("kind")
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo "❌ Dependências faltando: ${missing[*]}"
        echo ""
        echo "Instale com Homebrew:"
        for dep in "${missing[@]}"; do
            echo "  brew install $dep"
        done
        exit 1
    fi
}

function install() {
    echo "🚀 Instalando ArgoCD em cluster Kubernetes local..."
    echo ""
    
    check_dependencies
    
    # Verificar se cluster já existe
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "✅ Cluster '${CLUSTER_NAME}' já existe"
    else
        echo "📦 Criando cluster kind '${CLUSTER_NAME}'..."
        
        cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
EOF
        
        echo "✅ Cluster criado!"
    fi
    
    # Criar namespace ArgoCD
    echo ""
    echo "📦 Instalando ArgoCD..."
    kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Instalar ArgoCD usando server-side apply (resolve problema de CRDs grandes)
    echo "📦 Baixando e aplicando manifesto ArgoCD..."
    kubectl apply --server-side -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    echo ""
    echo "⏳ Aguardando ArgoCD ficar pronto (isso pode levar 2-3 minutos)..."
    kubectl wait --for=condition=Ready pods --all -n ${ARGOCD_NAMESPACE} --timeout=300s
    
    echo ""
    echo "✅ ArgoCD instalado com sucesso!"
    echo ""
    echo "🔑 Obter senha do admin:"
    echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
    echo ""
    echo "🌐 Acessar UI:"
    echo "   ./argocd-local.sh ui"
    echo "   Depois acesse: https://localhost:8081"
}

function start() {
    check_dependencies
    
    if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "❌ Cluster '${CLUSTER_NAME}' não encontrado"
        echo ""
        echo "Execute primeiro:"
        echo "  ./argocd-local.sh install"
        exit 1
    fi
    
    echo "🚀 Iniciando port-forward para ArgoCD UI..."
    echo ""
    echo "🌐 Acesse: https://localhost:8081"
    echo "👤 Username: admin"
    echo "🔑 Password: Execute em outro terminal:"
    echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
    echo ""
    echo "⚠️  Pressione Ctrl+C para parar"
    echo ""
    
    kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8081:443
}

function ui() {
    start
}

function login() {
    check_dependencies
    
    if ! command -v argocd >/dev/null 2>&1; then
        echo "❌ ArgoCD CLI não instalado"
        echo ""
        echo "Instale com:"
        echo "  brew install argocd"
        exit 1
    fi
    
    echo "🔐 Obtendo senha do admin..."
    PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo ""
    echo "🔑 Senha: $PASSWORD"
    echo ""
    echo "🔐 Fazendo login no ArgoCD..."
    
    # Iniciar port-forward em background
    kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8081:443 >/dev/null 2>&1 &
    PF_PID=$!
    
    sleep 3
    
    argocd login localhost:8081 --username admin --password "$PASSWORD" --insecure
    
    # Parar port-forward
    kill $PF_PID 2>/dev/null || true
    
    echo ""
    echo "✅ Login realizado com sucesso!"
    echo ""
    echo "💡 Dica: Troque a senha com:"
    echo "   argocd account update-password"
}

function apps() {
    check_dependencies
    
    echo "📦 Aplicando aplicações no ArgoCD..."
    echo ""
    
    # Criar namespaces
    echo "📂 Criando namespaces..."
    kubectl apply -f gitops/base/namespace.yaml
    kubectl apply -f gitops/base/observability-namespace.yaml
    
    # Aplicar configmaps
    echo "⚙️  Aplicando configmaps..."
    kubectl apply -f gitops/base/configmap.yaml
    
    # Aplicar App of Apps
    if [ -f gitops/argocd/app-of-apps.yaml ]; then
        echo "🌳 Aplicando App of Apps..."
        kubectl apply -f gitops/argocd/app-of-apps.yaml
    else
        echo "⚠️  app-of-apps.yaml não encontrado"
        echo ""
        echo "Aplicando aplicações individualmente..."
        
        # Aplicar cada aplicação
        for app in gitops/argocd/applications/*.yaml; do
            if [ -f "$app" ]; then
                echo "  📦 Aplicando $(basename $app)..."
                kubectl apply -f "$app"
            fi
        done
    fi
    
    echo ""
    echo "✅ Aplicações configuradas!"
    echo ""
    echo "🔍 Ver status das aplicações:"
    echo "   kubectl get applications -n argocd"
    echo ""
    echo "🌐 Ou acesse a UI:"
    echo "   ./argocd-local.sh ui"
}

function status() {
    check_dependencies
    
    echo "📊 Status do ArgoCD:"
    echo ""
    
    if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo "❌ Cluster '${CLUSTER_NAME}' não encontrado"
        exit 1
    fi
    
    echo "🔹 Pods do ArgoCD:"
    kubectl get pods -n ${ARGOCD_NAMESPACE}
    
    echo ""
    echo "🔹 Aplicações:"
    kubectl get applications -n ${ARGOCD_NAMESPACE} 2>/dev/null || echo "  Nenhuma aplicação encontrada"
    
    echo ""
    echo "🔹 Pods das aplicações:"
    kubectl get pods -n feature-flag 2>/dev/null || echo "  Namespace feature-flag não existe ainda"
}

function stop() {
    echo "⏸️  ArgoCD continua rodando no cluster"
    echo ""
    echo "Para parar o cluster kind completamente:"
    echo "  kind stop clusters ${CLUSTER_NAME}"
    echo ""
    echo "Para deletar tudo:"
    echo "  ./argocd-local.sh clean"
}

function clean() {
    echo "🧹 Limpando ambiente ArgoCD local..."
    read -p "⚠️  Isso vai DELETAR o cluster kind '${CLUSTER_NAME}'. Continuar? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
            kind delete cluster --name ${CLUSTER_NAME}
            echo "✅ Cluster '${CLUSTER_NAME}' deletado!"
        else
            echo "ℹ️  Cluster '${CLUSTER_NAME}' não encontrado"
        fi
    else
        echo "❌ Operação cancelada"
    fi
}

function help() {
    echo "ArgoCD Local - Gerenciador para testes Kubernetes"
    echo ""
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  install  - Cria cluster kind e instala ArgoCD"
    echo "  ui       - Abre port-forward para UI do ArgoCD (https://localhost:8081)"
    echo "  login    - Faz login no ArgoCD via CLI (requer argocd CLI)"
    echo "  apps     - Aplica as aplicações do projeto no ArgoCD"
    echo "  status   - Mostra status do cluster, ArgoCD e aplicações"
    echo "  stop     - Instruções para parar (ArgoCD roda no cluster)"
    echo "  clean    - Deleta o cluster kind completamente"
    echo "  help     - Mostra esta mensagem"
    echo ""
    echo "Workflow típico:"
    echo "  1. ./argocd-local.sh install    # Primeira vez"
    echo "  2. ./argocd-local.sh ui         # Acessar https://localhost:8081"
    echo "  3. ./argocd-local.sh apps       # Criar aplicações"
    echo "  4. ./argocd-local.sh status     # Ver status"
    echo ""
    echo "📖 Ver guia completo: ARGOCD_LOCAL.md"
}

# Main
case "${1:-help}" in
    install)
        install
        ;;
    start|ui)
        start
        ;;
    login)
        login
        ;;
    apps)
        apps
        ;;
    status)
        status
        ;;
    stop)
        stop
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        help
        ;;
    *)
        echo "❌ Comando desconhecido: $1"
        echo ""
        help
        exit 1
        ;;
esac
