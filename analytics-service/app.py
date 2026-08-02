import os
import sys
import threading
import json
import uuid
import time
import logging
import boto3
from botocore.exceptions import NoCredentialsError, ClientError
from flask import Flask, jsonify
from dotenv import load_dotenv

# OpenTelemetry imports
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor

# Configura o logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

# Carrega .env para desenvolvimento local
load_dotenv()

# --- OpenTelemetry Setup ---
OTEL_EXPORTER_OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.observability.svc.cluster.local:4317")
SERVICE_NAME_VALUE = "analytics-service"
SERVICE_VERSION_VALUE = "1.0.0"

resource = Resource(attributes={
    SERVICE_NAME: SERVICE_NAME_VALUE,
    SERVICE_VERSION: SERVICE_VERSION_VALUE,
    "deployment.environment": os.getenv("ENVIRONMENT", "production"),
    "service.namespace": "feature-flag",
})

# Configure tracing
trace_provider = TracerProvider(resource=resource)
otlp_trace_exporter = OTLPSpanExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
trace_provider.add_span_processor(BatchSpanProcessor(otlp_trace_exporter))
trace.set_tracer_provider(trace_provider)

# Configure metrics
otlp_metric_exporter = OTLPMetricExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
metric_reader = PeriodicExportingMetricReader(otlp_metric_exporter, export_interval_millis=30000)
metrics_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(metrics_provider)

# Get tracer and meter
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Create custom metrics
messages_processed_counter = meter.create_counter(
    name="sqs.messages.processed",
    description="Number of SQS messages processed",
    unit="1"
)

messages_failed_counter = meter.create_counter(
    name="sqs.messages.failed",
    description="Number of SQS messages that failed processing",
    unit="1"
)

dynamodb_write_duration = meter.create_histogram(
    name="dynamodb.write.duration",
    description="Duration of DynamoDB write operations",
    unit="ms"
)

log.info(f"OpenTelemetry initialized for {SERVICE_NAME_VALUE}")

# --- Configuração ---
AWS_REGION = os.getenv("AWS_REGION")
SQS_QUEUE_URL = os.getenv("AWS_SQS_URL")
DYNAMODB_TABLE_NAME = os.getenv("AWS_DYNAMODB_TABLE")

if not all([AWS_REGION, SQS_QUEUE_URL, DYNAMODB_TABLE_NAME]):
    log.critical("Erro: AWS_REGION, AWS_SQS_URL, e AWS_DYNAMODB_TABLE devem ser definidos.")
    sys.exit(1)

# --- Clientes Boto3 ---
# Criamos a sessão uma vez
try:
    _endpoint_url = os.getenv("AWS_ENDPOINT_URL")
    session = boto3.Session(region_name=AWS_REGION)
    sqs_client = session.client("sqs", endpoint_url=_endpoint_url)
    dynamodb_client = session.client("dynamodb", endpoint_url=_endpoint_url)
    log.info(f"Clientes Boto3 inicializados na região {AWS_REGION}")
    
    # Instrument Botocore for automatic tracing
    BotocoreInstrumentor().instrument()
    
except NoCredentialsError:
    log.critical("Credenciais da AWS não encontradas. Verifique seu ambiente.")
    sys.exit(1)
except Exception as e:
    log.critical(f"Erro ao inicializar o Boto3: {e}")
    sys.exit(1)


def process_message(message):
    """ Processa uma mensagem individual do SQS """
    with tracer.start_as_current_span("process_message") as span:
        try:
            message_id = message['MessageId']
            span.set_attribute("messaging.message_id", message_id)
            log.info(f"Processando mensagem ID: {message_id}")
            
            body = json.loads(message['Body'])
            
            # Add trace attributes
            span.set_attribute("user_id", body['user_id'])
            span.set_attribute("flag_name", body['flag_name'])
            span.set_attribute("result", body['result'])
            
            # Gera um ID único para o item no DynamoDB
            event_id = str(uuid.uuid4())
            span.set_attribute("event_id", event_id)
            
            # Constrói o item no formato do DynamoDB
            item = {
                'event_id': {'S': event_id},
                'user_id': {'S': body['user_id']},
                'flag_name': {'S': body['flag_name']},
                'result': {'BOOL': body['result']},
                'timestamp': {'S': body['timestamp']}
            }
            
            # Insere no DynamoDB
            start_time = time.time()
            with tracer.start_as_current_span("dynamodb_put_item"):
                dynamodb_client.put_item(
                    TableName=DYNAMODB_TABLE_NAME,
                    Item=item
                )
            duration_ms = (time.time() - start_time) * 1000
            dynamodb_write_duration.record(duration_ms, {"operation": "put_item"})
            
            log.info(f"Evento {event_id} (Flag: {body['flag_name']}) salvo no DynamoDB.")
            
            # Se tudo deu certo, deleta a mensagem da fila
            with tracer.start_as_current_span("sqs_delete_message"):
                sqs_client.delete_message(
                    QueueUrl=SQS_QUEUE_URL,
                    ReceiptHandle=message['ReceiptHandle']
                )
            
            messages_processed_counter.add(1, {"status": "success"})
            span.set_status(trace.Status(trace.StatusCode.OK))
            
        except json.JSONDecodeError as e:
            log.error(f"Erro ao decodificar JSON da mensagem ID: {message['MessageId']}")
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR, "JSON decode error"))
            messages_failed_counter.add(1, {"error_type": "json_decode"})
            # Não deleta a mensagem, pode ser uma "poison pill"
        except ClientError as e:
            log.error(f"Erro do Boto3 (DynamoDB ou SQS) ao processar {message['MessageId']}: {e}")
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR, "Boto3 client error"))
            messages_failed_counter.add(1, {"error_type": "boto3_client"})
            # Não deleta a mensagem, tenta novamente
        except Exception as e:
            log.error(f"Erro inesperado ao processar {message['MessageId']}: {e}")
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR, "Unexpected error"))
            messages_failed_counter.add(1, {"error_type": "unexpected"})

def sqs_worker_loop():
    """ Loop principal do worker que ouve a fila SQS """
    log.info("Iniciando o worker SQS...")
    while True:
        try:
            # Long-polling: espera até 20s por mensagens
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,  # Processa em lotes de até 10
                WaitTimeSeconds=20
            )
            
            messages = response.get('Messages', [])
            if not messages:
                # Nenhuma mensagem, continua o loop
                continue
                
            log.info(f"Recebidas {len(messages)} mensagens.")
            
            for message in messages:
                process_message(message)
                
        except ClientError as e:
            log.error(f"Erro do Boto3 no loop principal do SQS: {e}")
            time.sleep(10) # Pausa antes de tentar novamente
        except Exception as e:
            log.error(f"Erro inesperado no loop principal do SQS: {e}")
            time.sleep(10)

# --- Servidor Flask (Apenas para Health Check) ---

app = Flask(__name__)

# Instrument Flask for automatic tracing
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

@app.route('/health')
def health():
    # Uma verificação de saúde real poderia checar a conexão com o DynamoDB/SQS
    return jsonify({"status": "ok"})

# --- Inicialização ---

def start_worker():
    """ Inicia o worker SQS em uma thread separada """
    worker_thread = threading.Thread(target=sqs_worker_loop, daemon=True)
    worker_thread.start()

# Inicia o worker SQS em uma thread de background
# Isso garante que ele inicie tanto com 'flask run' quanto com 'gunicorn'
start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    app.run(host='0.0.0.0', port=port, debug=False)