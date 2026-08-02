# Observability Stack - GitOps Configuration

Este diretório contém toda a configuração da stack de observabilidade do cluster Kubernetes.

## 🎯 Componentes Provisionados

### 1. **Prometheus** (Métricas)

- **Descrição**: Armazenamento e consulta de métricas de infraestrutura
- **Helm Chart**: `prometheus-community/kube-prometheus-stack`
- **Arquivos**: `prometheus-*.yaml`
- **Features**:
  - Retenção de 15 dias
  - Service Monitors automáticos
  - Scraping de pods com annotations
  - Integração com OTel Collector

### 2. **Loki** (Logs)

- **Descrição**: Centralização e indexação de logs
- **Arquivos**: `loki-*.yaml`, `promtail-*.yaml`
- **Features**:
  - Retenção de 14 dias
  - Promtail DaemonSet para coleta de logs
  - Integração com Grafana
  - Pipeline de parsing JSON

### 3. **Grafana** (Visualização)

- **Descrição**: Dashboard principal de visualização
- **Arquivos**: `grafana-*.yaml`
- **Features**:
  - Dashboards pré-configurados
  - Datasources: Prometheus, Loki
  - Ingress configurado

### 4. **OpenTelemetry Collector** (Hub Central)

- **Descrição**: Recebe, processa e exporta telemetria
- **Arquivos**: `otel-*.yaml`
- **Features**:
  - Recebe traces, métricas e logs
  - Suporte OTLP, Jaeger, Zipkin
  - Exporta para Prometheus, Loki e New Relic
  - Enrichment com atributos K8s

### 5. **New Relic** (APM & Observability)

- **Descrição**: Plataforma unificada de observabilidade
- **Integração**: Via OpenTelemetry Collector (OTLP nativo)
- **Features**:
  - APM automático para todos os serviços
  - Distributed tracing end-to-end
  - Infrastructure monitoring (Kubernetes)
  - Log management com correlation
  - Dashboards e alertas nativos
  - Free tier: 100 GB/mês

📖 **Guia completo**: Ver [NEW_RELIC_SETUP.md](NEW_RELIC_SETUP.md)

### 6. **Alerting & Self-Healing**

- **Arquivos**: `prometheus-alerts.yaml`, `alertmanager.yaml`, `self-healing.yaml`
- **Features**:
  - Alertas inteligentes (erro 5xx, downtime, resource usage)
  - Integração PagerDuty
  - Notificações Slack/Discord/Teams
  - Self-healing automático via webhook

## 📋 Pré-requisitos

1. **Cluster Kubernetes** com ArgoCD instalado
2. **Chaves de API**:
   - New Relic License Key: https://newrelic.com/signup (free tier disponível)
   - PagerDuty Service Key (opcional)
   - Slack Webhook URL (opcional)

## 🚀 Deploy

### Passo 1: Configurar Secrets

Edite os arquivos e substitua os placeholders:

```bash
# New Relic
# Em: otel-collector-deployment.yaml
YOUR_NEW_RELIC_LICENSE_KEY

# Alerting
# Em: alertmanager.yaml
YOUR_PAGERDUTY_SERVICE_KEY
YOUR_SLACK_WEBHOOK_URL

# Self-Healing
# Em: self-healing.yaml
YOUR_WEBHOOK_PASSWORD
YOUR_SLACK_WEBHOOK_URL
```

### Passo 2: Atualizar repositório Git

```bash
git add gitops/
git commit -m "feat: add observability stack"
git push origin main
```

### Passo 3: Criar namespace

```bash
kubectl apply -f gitops/base/observability-namespace.yaml
```

### Passo 4: Deploy via ArgoCD

```bash
# Deploy de toda a stack
kubectl apply -f gitops/argocd/applications/observability.yaml

# Ou deploy individual
kubectl apply -f gitops/argocd/applications/observability.yaml -l app.kubernetes.io/name=prometheus-stack
```

### Passo 5: Verificar status

```bash
# Ver todas as apps
kubectl get applications -n argocd | grep observability

# Ver pods
kubectl get pods -n observability

# Ver logs do OTel Collector
kubectl logs -n observability -l app=otel-collector -f
```

## 🔧 Instrumentação dos Serviços

### Serviços Python (analytics, flag, targeting)

Já instrumentados com OpenTelemetry. Variáveis de ambiente necessárias:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "otel-collector.observability.svc.cluster.local:4317"
  - name: ENVIRONMENT
    value: "production"
```

### Serviços Go (auth, evaluation)

Já possuem arquivo `otel.go`. Para ativar, adicione ao `main.go`:

```go
import "context"

func main() {
    // ... código existente ...

    // Inicializar OpenTelemetry
    cleanup, err := InitOpenTelemetry("auth-service", "1.0.0")
    if err != nil {
        log.Fatalf("Failed to initialize OpenTelemetry: %v", err)
    }
    defer cleanup(context.Background())

    // Wrap HTTP handlers com otelhttp
    import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

    mux := http.NewServeMux()
    handler := otelhttp.NewHandler(mux, "auth-service")
    http.ListenAndServe(":"+port, handler)
}
```

Não esqueça de executar:

```bash
cd auth-service
go mod tidy
```

## 📊 Acessar Dashboards

### Grafana

```bash
kubectl port-forward -n observability svc/grafana 3000:80
```

Acesse: http://localhost:3000

- User: `admin`
- Password: `admin123` (altere em `grafana-deployment.yaml`)

### Prometheus

```bash
kubectl port-forward -n observability svc/prometheus-operated 9090:9090
```

Acesse: http://localhost:9090

### Datadog

Acesse: https://app.datadoghq.com

- **APM**: APM > Services
- **Service Map**: APM > Service Map
- **Traces**: APM > Traces
- **Logs**: Logs > Search
- **Metrics**: Metrics > Explorer

## 🔔 Alertas Configurados

| Alerta                   | Threshold          | Ação Self-Healing  |
| ------------------------ | ------------------ | ------------------ |
| AuthServiceHighErrorRate | 5xx > 5%           | Restart deployment |
| ServiceDown              | Up = 0             | Restart deployment |
| HighMemoryUsage          | Memory > 90%       | Restart deployment |
| HighCPUUsage             | CPU > 80%          | Alert only         |
| PodRestartLoop           | Restarts > 0.1/min | Scale 0 → 2        |
| SlowResponseTime         | P95 > 1s           | Alert only         |

## 🧪 Testar Observabilidade

### 1. Testar Traces

```bash
# Fazer requisições aos serviços
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://auth-service.feature-flag.svc.cluster.local:8001/health

# Ver traces no Datadog APM
```

### 2. Testar Logs

```bash
# Ver logs no Grafana
# Datasource: Loki
# Query: {namespace="feature-flag"}
```

### 3. Testar Métricas

```bash
# Ver métricas no Grafana
# Datasource: Prometheus
# Query: rate(http_requests_total[5m])
```

### 4. Testar Alertas

```bash
# Simular alta taxa de erro (adicione temporariamente ao código)
# Espere 2 minutos e veja o alerta disparar

# Ver alertas
kubectl port-forward -n observability svc/alertmanager 9093:9093
# Acesse: http://localhost:9093
```

### 5. Testar Self-Healing

```bash
# Disparar alerta manualmente
kubectl scale deployment/auth-service -n feature-flag --replicas=0

# Aguarde o alerta "ServiceDown" disparar
# O self-healing deve reiniciar automaticamente
```

## 🔐 Segurança

1. **Secrets**: Todos os secrets devem ser armazenados usando ferramentas como:
   - Sealed Secrets
   - External Secrets Operator
   - AWS Secrets Manager / Azure Key Vault

2. **RBAC**: O ServiceAccount `self-healing-sa` tem permissões para restart deployments

3. **Network Policies**: Considere adicionar políticas de rede para isolar o namespace `observability`

## 📚 Documentação

- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [Datadog Kubernetes](https://docs.datadoghq.com/containers/kubernetes/)

## 🆘 Troubleshooting

### OTel Collector não recebe dados

```bash
kubectl logs -n observability -l app=otel-collector
# Verificar se serviços estão enviando para o endpoint correto
```

### Datadog não mostra traces

```bash
# Verificar se API key está correta
kubectl get secret -n observability datadog-agent -o yaml

# Ver logs do agent
kubectl logs -n observability -l app=datadog-agent
```

### Alertas não disparam

```bash
# Verificar regras
kubectl get prometheusrules -n observability

# Ver alertas ativos
kubectl port-forward -n observability svc/prometheus-operated 9090:9090
# Acesse: http://localhost:9090/alerts
```

## 🎓 Próximos Passos

1. ✅ Configurar Retention Policies no Prometheus/Loki
2. ✅ Adicionar mais dashboards personalizados no Grafana
3. ✅ Configurar SLOs e SLIs
4. ✅ Implementar Chaos Engineering com Litmus
5. ✅ Adicionar métricas de negócio (feature flag usage, etc.)
