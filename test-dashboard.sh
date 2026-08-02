#!/bin/bash
# Script para testar o dashboard do Grafana

echo "🔍 Verificando Dashboard do Grafana..."
echo ""

# 1. Verificar se o exporter está funcionando
echo "1️⃣ Verificando docker-stats-exporter..."
CONTAINERS_RUNNING=$(curl -s http://localhost:9417/metrics | grep "^containers_running " | awk '{print $2}')
echo "   Containers ativos (exporter): $CONTAINERS_RUNNING"
echo ""

# 2. Verificar se o Prometheus está coletando
echo "2️⃣ Verificando Prometheus..."
PROM_CONTAINERS=$(curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=containers_running' | jq -r '.data.result[0].value[1]')
echo "   Containers ativos (Prometheus): $PROM_CONTAINERS"
echo ""

# 3. Verificar se o Grafana consegue consultar
echo "3️⃣ Verificando Grafana..."
NOW=$(date +%s)000
FROM=$(($(date +%s) - 3600))000

GRAFANA_RESULT=$(curl -s -X POST 'http://admin:admin@localhost:3000/api/ds/query' \
  -H 'Content-Type: application/json' \
  --data-raw "{
    \"from\": \"$FROM\",
    \"to\": \"$NOW\",
    \"queries\": [
      {
        \"datasource\": {\"type\": \"prometheus\", \"uid\": \"prometheus\"},
        \"expr\": \"containers_running\",
        \"refId\": \"A\",
        \"instant\": true
      }
    ]
  }" | jq -r '.results.A.frames[0].data.values[1][0]')

echo "   Containers ativos (Grafana): $GRAFANA_RESULT"
echo ""

# 4. Verificar métricas de CPU e memória
echo "4️⃣ Verificando métricas de serviços..."
SERVICE_COUNT=$(curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=count(container_cpu_usage_percent{exported_service=~".*-service"})' | jq -r '.data.result[0].value[1]')
MEMORY_COUNT=$(curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=count(container_memory_usage_bytes{exported_service=~".*-service"} > 0)' | jq -r '.data.result[0].value[1]')
echo "   Serviços com métricas de CPU: $SERVICE_COUNT"
echo "   Serviços com métricas de Memória: $MEMORY_COUNT"
echo ""

# 5. Verificar se há logs no Loki
echo "5️⃣ Verificando Loki..."
LOKI_LOGS=$(curl -s 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={project="fase04"}' --data-urlencode 'limit=1' | jq -r '.data.result | length')
echo "   Streams de logs encontrados: $LOKI_LOGS"
echo ""

# Resumo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RESUMO:"
if [ "$CONTAINERS_RUNNING" == "$PROM_CONTAINERS" ] && [ "$PROM_CONTAINERS" == "$GRAFANA_RESULT" ]; then
    echo "   ✅ Pipeline de métricas funcionando!"
    echo "   ✅ $CONTAINERS_RUNNING containers sendo monitorados"
else
    echo "   ⚠️ Inconsistência detectada:"
    echo "      Exporter: $CONTAINERS_RUNNING"
    echo "      Prometheus: $PROM_CONTAINERS"
    echo "      Grafana: $GRAFANA_RESULT"
fi

if [ "$SERVICE_COUNT" -ge 5 ]; then
    echo "   ✅ Métricas de CPU coletadas ($SERVICE_COUNT serviços)"
else
    echo "   ⚠️ Apenas $SERVICE_COUNT serviços com métricas de CPU"
fi

if [ "$MEMORY_COUNT" -ge 5 ]; then
    echo "   ✅ Métricas de Memória coletadas ($MEMORY_COUNT serviços)"
else
    echo "   ⚠️ Apenas $MEMORY_COUNT serviços com métricas de Memória"
fi

if [ "$LOKI_LOGS" -gt 0 ]; then
    echo "   ✅ Logs sendo coletados"
else
    echo "   ⚠️ Nenhum log encontrado no Loki"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌐 Dashboard disponível em: http://localhost:3000/d/feature-flag-complete-v2"
