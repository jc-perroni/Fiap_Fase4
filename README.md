# Feature Flag Platform

Este projeto é uma plataforma de **feature flags** composta por 5 microserviços que se comunicam entre si para gerenciar, avaliar e registrar o uso de flags de funcionalidade por usuário.

## 🚀 Quick Start - Teste Local

**Quer testar tudo localmente antes de ir para AWS?**

```bash
# Método 1: Script helper (recomendado)
./local.sh start

# Método 2: Docker Compose direto
docker-compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

**Acesse:**

- 📊 **Grafana**: http://localhost:3000 (admin/admin)
- 🔍 **Jaeger**: http://localhost:16686
- 📈 **Prometheus**: http://localhost:9090

**📖 Guias de Teste:**

- [🧪 Testes com cURL - Comandos e Scripts](CURL_TESTING_GUIDE.md) ⭐ **NOVO**
- [🔧 Soluções Rápidas - Problemas Comuns](QUICK_FIXES.md) ⭐ **NOVO**
- [⚡ Scripts Helper - Comandos rápidos](SCRIPTS_HELPER.md)
- [🐳 Docker Compose - Testes locais completos](LOCAL_TESTING.md)
- [🚀 ArgoCD Local - Validar manifestos Kubernetes](ARGOCD_LOCAL.md)

**⚡ Scripts de Teste Rápido:**

```bash
# 1. Teste completo de todos os endpoints (cria API Key automaticamente)
./full-test.sh

# 2. Gerar carga de teste (80 requisições)
./test-load.sh

# 3. Simular tráfego contínuo
./continuous-load.sh
```

**🆘 Problemas?**

```bash
# Ver erros comuns e soluções
cat QUICK_FIXES.md

# Reset completo de emergência (se nada funcionar)
./emergency-reset.sh
```

./continuous-load.sh

````

---

## Executando o projeto localmente com Docker Compose

## Visão geral dos serviços

### auth-service (Go · porta 8001)

Responsável pela **autenticação via API Keys**. Gera chaves de acesso, armazena seus hashes no PostgreSQL e valida o token enviado pelos demais serviços no header `Authorization: Bearer <key>`. É o ponto central de segurança da plataforma.

### flag-service (Python · porta 8002)

**CRUD de feature flags**. Permite criar, listar, atualizar e deletar flags. Toda operação exige uma API Key válida, validada em tempo real contra o `auth-service`.

### targeting-service (Python · porta 8003)

Gerencia as **regras de segmentação** associadas a cada flag. As regras são objetos JSON flexíveis (ex.: porcentagem de usuários, lista de IDs, atributos) que determinam para quem uma flag estará ativa. Também autenticado via `auth-service`.

### evaluation-service (Go · porta 8004)

**Motor de avaliação** das flags. Recebe um `user_id` e um `flag_name`, consulta o `flag-service` e o `targeting-service` (com cache Redis), executa a lógica de targeting e retorna `true` ou `false`. Cada avaliação é enviada de forma assíncrona para uma fila SQS.

### analytics-service (Python · porta 8005)

**Worker de analytics**. Não é uma API REST convencional — roda em background consumindo eventos da fila SQS enviados pelo `evaluation-service` e persiste cada registro no DynamoDB para análise posterior. Expõe apenas um endpoint de health check.

---

## Endpoints

> Todos os endpoints (exceto `/health`, `/validate` e `/admin/keys`) exigem o header:
>
> ```
> Authorization: Bearer <sua-api-key>
> ```
>
> A API Key é obtida via `POST /admin/keys` no `auth-service`.

---

### auth-service — `http://localhost:8001`

| Método | Endpoint      | Autenticação | Descrição                   |
| ------ | ------------- | :----------: | --------------------------- |
| `GET`  | `/health`     |      —       | Health check                |
| `GET`  | `/validate`   | Bearer token | Valida se a API Key é ativa |
| `POST` | `/admin/keys` |  MASTER_KEY  | Cria uma nova API Key       |

**Criar uma API Key:**

```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "minha-chave"}'
````

---

### flag-service — `http://localhost:8002`

| Método   | Endpoint        | Descrição                    |
| -------- | --------------- | ---------------------------- |
| `GET`    | `/health`       | Health check                 |
| `POST`   | `/flags`        | Cria uma nova flag           |
| `GET`    | `/flags`        | Lista todas as flags         |
| `GET`    | `/flags/{name}` | Busca uma flag pelo nome     |
| `PUT`    | `/flags/{name}` | Atualiza descrição ou status |
| `DELETE` | `/flags/{name}` | Remove uma flag              |

**Criar uma flag:**

```bash
curl -X POST http://localhost:8002/flags \
  -H "Authorization: Bearer <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"name": "nova-funcionalidade", "description": "Teste A/B", "is_enabled": true}'
```

---

### targeting-service — `http://localhost:8003`

| Método   | Endpoint             | Descrição                                 |
| -------- | -------------------- | ----------------------------------------- |
| `GET`    | `/health`            | Health check                              |
| `POST`   | `/rules`             | Cria uma regra de targeting para uma flag |
| `GET`    | `/rules/{flag_name}` | Busca as regras de uma flag               |
| `PUT`    | `/rules/{flag_name}` | Atualiza as regras de uma flag            |
| `DELETE` | `/rules/{flag_name}` | Remove as regras de uma flag              |

**Criar regras de targeting:**

```bash
curl -X POST http://localhost:8003/rules \
  -H "Authorization: Bearer <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "nova-funcionalidade", "rules": {"percentage": 50}}'
```

---

### evaluation-service — `http://localhost:8004`

| Método | Endpoint                                  | Descrição                                  |
| ------ | ----------------------------------------- | ------------------------------------------ |
| `GET`  | `/health`                                 | Health check                               |
| `GET`  | `/evaluate?user_id=<id>&flag_name=<name>` | Avalia se a flag está ativa para o usuário |

**Avaliar uma flag para um usuário:**

```bash
curl "http://localhost:8004/evaluate?user_id=user-123&flag_name=nova-funcionalidade" \
  -H "Authorization: Bearer <api-key>"
```

**Resposta:**

```json
{ "flag_name": "nova-funcionalidade", "user_id": "user-123", "result": true }
```

---

### analytics-service — `http://localhost:8005`

| Método | Endpoint  | Descrição    |
| ------ | --------- | ------------ |
| `GET`  | `/health` | Health check |

> Este serviço não expõe endpoints de negócio — opera como worker de background consumindo a fila SQS e persistindo eventos no DynamoDB.

---

Este documento descreve todas as alterações realizadas para viabilizar a execução local dos 5 microserviços e suas dependências via Docker Compose.

---

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado e em execução
- Arquivo `.env` na raiz do projeto (veja a seção [Variáveis de Ambiente](#variáveis-de-ambiente))

---

## Estrutura do projeto

```
.
├── analytics-service/      # Python — consumidor SQS / gravador DynamoDB
├── auth-service/           # Go   — autenticação JWT + PostgreSQL
├── evaluation-service/     # Go   — motor de avaliação de feature flags
├── flag-service/           # Python — CRUD de feature flags + PostgreSQL
├── targeting-service/      # Python — regras de targeting + PostgreSQL
├── docker/
│   ├── init-postgres-apps.sh   # cria targeting_db e inicializa schemas
│   └── init-localstack.sh      # cria fila SQS e tabela DynamoDB no LocalStack
├── docker-compose.yml
└── .env
```

---

## Como subir o ambiente

```bash
# Na raiz do projeto
docker compose up --build -d

# Acompanhar logs em tempo real
docker compose logs -f

# Derrubar tudo
docker compose down
```

---

## Serviços e portas

| Serviço              | Porta local | Descrição                                   |
| -------------------- | ----------- | ------------------------------------------- |
| `auth-service`       | `8001`      | Geração e validação de JWT                  |
| `flag-service`       | `8002`      | CRUD de feature flags                       |
| `targeting-service`  | `8003`      | Regras de targeting por usuário             |
| `evaluation-service` | `8004`      | Avalia se uma flag é ativa para um ID       |
| `analytics-service`  | `8005`      | Consome eventos da fila e grava no DB       |
| `postgres-auth`      | —           | PostgreSQL para `auth_db`                   |
| `postgres-apps`      | —           | PostgreSQL para `flags_db` + `targeting_db` |
| `redis`              | —           | Cache do `evaluation-service`               |
| `localstack`         | `4566`      | Emula AWS SQS e DynamoDB localmente         |

---

## Variáveis de Ambiente

O arquivo `.env` na raiz é compartilhado entre todos os serviços quando executado fora do Docker Compose (ex.: `docker run --env-file .env`). No Compose, cada serviço recebe apenas as variáveis necessárias declaradas no `docker-compose.yml`.

Crie o arquivo `.env` com o seguinte conteúdo:

```dotenv
# AWS (analytics-service e evaluation-service)
AWS_REGION=us-east-1
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/123456789/minha-fila
AWS_DYNAMODB_TABLE=nome-da-tabela

# Banco de dados PostgreSQL
DATABASE_URL=postgres://usuario:senha@localhost:5432/nome-do-banco

# auth-service
MASTER_KEY=12345

# evaluation-service
REDIS_URL=redis://localhost:6379
FLAG_SERVICE_URL=http://localhost:8002
TARGETING_SERVICE_URL=http://localhost:8003
SERVICE_API_KEY=12345

# flag-service e targeting-service
AUTH_SERVICE_URL=http://localhost:8001
```

> **Atenção:** Os valores de `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_ENDPOINT_URL` são injetados diretamente no `docker-compose.yml` com valores fictícios (`test`) para uso com o LocalStack. Não é necessário credencial AWS real para rodar localmente.

---

## Alterações realizadas

### 1. Dockerfiles criados (multistage build)

Nenhum serviço possuía Dockerfile. Foram criados Dockerfiles multistage para todos os 5 serviços seguindo o padrão:

**Serviços Python** (`analytics-service`, `flag-service`, `targeting-service`):

- Estágio `builder`: `python:3.11-slim` + dependências de compilação + virtualenv em `/opt/venv`
- Estágio `runtime`: `python:3.11-slim` limpo, copia apenas `/opt/venv`, executa como usuário não-root
- `flag-service` e `targeting-service` incluem `libpq-dev` (builder) e `libpq5` (runtime) para o driver `psycopg2`

**Serviços Go** (`auth-service`, `evaluation-service`):

- Estágio `builder`: `golang:1.21-alpine` — compila binário estático (`CGO_ENABLED=0`)
- Estágio `runtime`: `alpine:3.19` — apenas o binário + `ca-certificates`, executa como usuário não-root

### 2. Werkzeug fixado em todos os serviços Python

Flask 2.2.2 é incompatível com Werkzeug >= 2.4 (remove `werkzeug.urls.url_quote`). A versão foi fixada em todos os `requirements.txt` Python:

```
# analytics-service/requirements.txt
# flag-service/requirements.txt
# targeting-service/requirements.txt
Werkzeug==2.3.8
```

### 3. Correções de imports nos serviços Go

O compilador Go não aceita imports não utilizados nem variáveis indefinidas.

**`auth-service`:**

- `handlers.go` — removidos imports não usados: `crypto/sha256`, `encoding/hex`
- `key.go` — removido import não usado: `fmt`
- `main.go` — removido import não usado: `fmt`; driver `pgx/v4/stdlib` alterado para import blank (`_ "github.com/jackc/pgx/v4/stdlib"`) para registro como side-effect

**`auth-service/go.mod`:**

- Removida entrada inválida `github.com/jackc/pgx/v4/stdlib v4.18.3` — `stdlib` é um sub-pacote de `pgx/v4`, não um módulo independente

**`evaluation-service/evaluator.go`:**

- Removido import não usado: `"context"`
- Adicionado import ausente: `"os"` (necessário para `os.Getenv`)

### 4. Suporte ao LocalStack (emulação AWS)

Para evitar necessidade de credenciais AWS reais, os serviços que consomem AWS foram adaptados para aceitar um endpoint customizável via variável de ambiente `AWS_ENDPOINT_URL`.

**`analytics-service/app.py`:**

```python
_endpoint_url = os.getenv("AWS_ENDPOINT_URL")
sqs = boto3.client("sqs", endpoint_url=_endpoint_url, ...)
dynamodb = boto3.resource("dynamodb", endpoint_url=_endpoint_url, ...)
```

**`evaluation-service/main.go`:**

```go
awsConfig := aws.NewConfig().WithRegion(os.Getenv("AWS_REGION"))
if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
    awsConfig = awsConfig.WithEndpoint(endpoint)
}
```

### 5. docker-compose.yml criado

Arquivo criado com 9 containers:

- **2 instâncias PostgreSQL:**
  - `postgres-auth`: banco `auth_db` para o `auth-service`
  - `postgres-apps`: banco `flags_db` (default) + `targeting_db` (criado via script de init)

- **Redis 7** para cache do `evaluation-service`

- **LocalStack 3** emulando SQS e DynamoDB, com script de inicialização automática

- **5 microserviços** com `depends_on` e `condition: service_healthy` para garantir a ordem correta de inicialização

### 6. Scripts de inicialização de banco de dados

**`docker/init-postgres-apps.sh`** — executado automaticamente pelo PostgreSQL na primeira inicialização:

1. Cria o banco `targeting_db`
2. Aplica o schema do `flag-service` em `flags_db`
3. Aplica o schema do `targeting-service` em `targeting_db`

**`docker/init-localstack.sh`** — executado automaticamente pelo LocalStack após estar pronto:

1. Cria a fila SQS `minha-fila`
2. Cria a tabela DynamoDB `nome-da-tabela` com chave de partição `event_id`

### 7. Ordem de inicialização (depends_on)

```
postgres-auth ──► auth-service ──► flag-service ──┐
postgres-apps ──► auth-service ──► targeting-service ──┤──► evaluation-service
redis ──────────────────────────────────────────────────┘
localstack ──► evaluation-service
localstack ──► analytics-service
```

---

## Deploy na AWS (EKS)

### Pré-requisitos

- `docker`, `kubectl`, `helm` e `aws` CLI configurados
- Cluster EKS com Nginx Ingress Controller instalado
- KEDA instalado: `helm install keda kedacore/keda --namespace keda --create-namespace`

### Passo a passo

**1. Login no ECR e build + push das imagens (Mac M1/M2/M3 — `linux/amd64`):**

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 653509254250.dkr.ecr.us-east-1.amazonaws.com

docker build --platform linux/amd64 -t 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/auth-service:latest ./auth-service && \
  docker push 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/auth-service:latest

docker build --platform linux/amd64 -t 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/flag-service:latest ./flag-service && \
  docker push 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/flag-service:latest

docker build --platform linux/amd64 -t 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/targeting-service:latest ./targeting-service && \
  docker push 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/targeting-service:latest

docker build --platform linux/amd64 -t 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/valuation-service:latest ./evaluation-service && \
  docker push 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/valuation-service:latest

docker build --platform linux/amd64 -t 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/analytics-service:latest ./analytics-service && \
  docker push 653509254250.dkr.ecr.us-east-1.amazonaws.com/pos2/analytics-service:latest
```

**2. Aplicar os manifestos Kubernetes:**

```bash
kubectl apply -f k8s/
```

**3. Verificar status dos pods:**

```bash
kubectl get all -n feature-flags
kubectl get ingress -n feature-flags
```

**4. Obter o endereço público do Ingress:**

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

> Guarde esse hostname — ele é a base de todas as chamadas abaixo (referido como `<INGRESS_HOST>`).

---

## Testando os serviços na AWS (curl / Insomnia)

> Substitua `<INGRESS_HOST>` pelo hostname obtido acima e `<API_KEY>` pela chave gerada no passo 1 abaixo.

### 1. Criar uma API Key (auth-service)

```bash
curl -X POST http://<INGRESS_HOST>/auth/admin/keys \
  -H "Authorization: Bearer 12345" \
  -H "Content-Type: application/json" \
  -d '{"name": "minha-chave"}'
```

Resposta:

```json
{ "key": "abc123...", "name": "minha-chave" }
```

> Use o valor de `"key"` como `<API_KEY>` nos próximos comandos.

---

### 2. Validar a API Key (auth-service)

```bash
curl http://<INGRESS_HOST>/auth/validate \
  -H "Authorization: Bearer <API_KEY>"
```

---

### 3. Criar uma feature flag (flag-service)

```bash
curl -X POST http://<INGRESS_HOST>/flags/flags \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "nova-funcionalidade", "description": "Teste A/B", "is_enabled": true}'
```

---

### 4. Listar as flags (flag-service)

```bash
curl http://<INGRESS_HOST>/flags/flags \
  -H "Authorization: Bearer <API_KEY>"
```

---

### 5. Criar regra de targeting (targeting-service)

```bash
curl -X POST http://<INGRESS_HOST>/targeting/rules \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "nova-funcionalidade", "rules": {"percentage": 50}}'
```

---

### 6. Avaliar uma flag para um usuário (evaluation-service)

```bash
curl "http://<INGRESS_HOST>/evaluation/evaluate?user_id=user-123&flag_name=nova-funcionalidade" \
  -H "Authorization: Bearer <API_KEY>"
```

Resposta:

```json
{ "flag_name": "nova-funcionalidade", "user_id": "user-123", "result": true }
```

---

### 7. Health checks de todos os serviços

```bash
curl http://<INGRESS_HOST>/auth/health
curl http://<INGRESS_HOST>/flags/health
curl http://<INGRESS_HOST>/targeting/health
curl http://<INGRESS_HOST>/evaluation/health
curl http://<INGRESS_HOST>/analytics/health
```

---

### Insomnia — importar como coleção

Crie um **Environment** no Insomnia com as variáveis:

| Variável     | Valor                   |
| ------------ | ----------------------- |
| `base_url`   | `http://<INGRESS_HOST>` |
| `api_key`    | `<API_KEY>`             |
| `master_key` | `12345`                 |

E use `{{ base_url }}/auth/admin/keys`, `{{ _.api_key }}` nos headers, etc.

---

## Verificando se tudo está saudável

```bash
docker compose ps
```

Todos os containers devem aparecer com status `Up`. Os bancos de dados, Redis e LocalStack terão `(healthy)` na coluna de status.

```bash
# Testar auth-service
curl http://localhost:8001/health

# Testar flag-service
curl http://localhost:8002/health

# Testar targeting-service
curl http://localhost:8003/health

# Testar evaluation-service
curl http://localhost:8004/health
```
