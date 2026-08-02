#!/bin/bash
# query-loki.sh - Consultar logs do Loki facilmente
# Uso: ./query-loki.sh [service] [busca] [limite]
# Exemplos:
#   ./query-loki.sh fase04
#   ./query-loki.sh fase04 error
#   ./query-loki.sh fase04 OpenTelemetry 50

SERVICE="${1:-fase04}"
SEARCH="${2}"
LIMIT="${3:-20}"

if [ -z "$SEARCH" ]; then
  QUERY="{project=\"$SERVICE\"}"
else
  QUERY="{project=\"$SERVICE\"} |= \"$SEARCH\""
fi

echo "🔍 Consultando Loki: $QUERY (limit=$LIMIT)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

curl -s -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode "query=$QUERY" \
  --data-urlencode "limit=$LIMIT" | \
  python3 -c "
import sys, json
from datetime import datetime

try:
    data = json.load(sys.stdin)
    if data['status'] != 'success':
        print('❌ Erro na query')
        sys.exit(1)
    
    results = data['data']['result']
    if not results:
        print('⚠️  Nenhum log encontrado')
        sys.exit(0)
    
    total = 0
    for result in results:
        labels = result['stream']
        service = labels.get('service', 'unknown')
        container = labels.get('container', 'unknown')
        
        for line in result['values']:
            timestamp_ns = int(line[0])
            timestamp = datetime.fromtimestamp(timestamp_ns / 1e9)
            message = line[1]
            
            print(f'[{timestamp.strftime(\"%Y-%m-%d %H:%M:%S\")}] {service:20s} │ {message}')
            total += 1
    
    print('')
    print(f'📊 Total: {total} logs encontrados')
    
except json.JSONDecodeError:
    print('❌ Erro ao decodificar resposta JSON')
    sys.exit(1)
except Exception as e:
    print(f'❌ Erro: {e}')
    sys.exit(1)
"
