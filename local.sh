#!/bin/bash

# Script helper para gerenciar a stack local
# Uso: ./local.sh [start|stop|restart|logs|status|clean]

set -e

COMPOSE_FILES="-f docker-compose.yml -f docker-compose.observability.yml"

function start() {
    echo "🚀 Iniciando Feature Flag Platform + Observabilidade..."
    
    # Verificar se .env existe
    if [ ! -f .env ]; then
        echo "⚠️  Arquivo .env não encontrado!"
        echo "📝 Criando .env com valores padrão..."
        cat > .env << EOF
MASTER_KEY=$(openssl rand -hex 32)
SERVICE_API_KEY=$(openssl rand -hex 32)
AWS_DYNAMODB_TABLE=evaluation_events
EOF
        echo "✅ Arquivo .env criado!"
        echo ""
    fi
    
    # Subir todos os serviços
    docker-compose $COMPOSE_FILES up -d
    
    echo ""
    echo "⏳ Aguardando serviços ficarem prontos..."
    sleep 10
    
    echo ""
    echo "✅ Stack iniciada!"
    echo ""
    echo "📊 URLs disponíveis:"
    echo "  • Grafana:     http://localhost:3000 (admin/admin)"
    echo "  • Jaeger:      http://localhost:16686"
    echo "  • Prometheus:  http://localhost:9090"
    echo "  • Auth:        http://localhost:8001"
    echo "  • Flags:       http://localhost:8002"
    echo "  • Targeting:   http://localhost:8003"
    echo "  • Evaluation:  http://localhost:8004"
    echo "  • Analytics:   http://localhost:8005"
    echo ""
    echo "📖 Ver guia completo: LOCAL_TESTING.md"
}

function stop() {
    echo "⏸️  Parando todos os serviços..."
    docker-compose $COMPOSE_FILES stop
    echo "✅ Serviços parados!"
}

function restart() {
    echo "🔄 Reiniciando stack..."
    stop
    sleep 2
    start
}

function logs() {
    echo "📝 Exibindo logs (Ctrl+C para sair)..."
    docker-compose $COMPOSE_FILES logs -f
}

function status() {
    echo "📊 Status dos serviços:"
    echo ""
    docker-compose $COMPOSE_FILES ps
    echo ""
    echo "🔍 Health checks:"
    docker-compose $COMPOSE_FILES ps --format json | jq -r '.[] | "\(.Name): \(.Health)"' 2>/dev/null || echo "  (instale jq para ver health status detalhado)"
}

function clean() {
    echo "🧹 Limpando TUDO (containers, volumes, imagens)..."
    read -p "⚠️  Isso vai APAGAR TODOS OS DADOS. Continuar? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker-compose $COMPOSE_FILES down -v --remove-orphans
        echo "✅ Tudo limpo!"
    else
        echo "❌ Operação cancelada"
    fi
}

function help() {
    echo "Feature Flag Platform - Gerenciador Local"
    echo ""
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  start    - Inicia toda a stack (app + observabilidade)"
    echo "  stop     - Para todos os serviços"
    echo "  restart  - Reinicia toda a stack"
    echo "  logs     - Mostra logs em tempo real"
    echo "  status   - Mostra status de todos os serviços"
    echo "  clean    - Remove tudo (containers, volumes, dados)"
    echo "  help     - Mostra esta mensagem"
    echo ""
    echo "Exemplos:"
    echo "  $0 start           # Iniciar tudo"
    echo "  $0 logs            # Ver logs"
    echo "  $0 status          # Ver status"
    echo "  $0 clean           # Limpar tudo"
}

# Main
case "${1:-help}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    logs)
        logs
        ;;
    status)
        status
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
