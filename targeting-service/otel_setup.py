"""
OpenTelemetry setup module for Python services
This module provides common configuration for tracing, metrics, and logging.
"""
import os
import logging
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
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor

log = logging.getLogger(__name__)


def setup_opentelemetry(service_name: str, service_version: str = "1.0.0"):
    """
    Setup OpenTelemetry for a Python service.
    
    Args:
        service_name: Name of the service
        service_version: Version of the service
    
    Returns:
        tuple: (tracer, meter) instances
    """
    # Get configuration from environment
    otel_endpoint = os.getenv(
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "otel-collector.observability.svc.cluster.local:4317"
    )
    
    # Remove http:// or https:// prefix if present (gRPC doesn't accept it)
    if otel_endpoint.startswith("http://"):
        otel_endpoint = otel_endpoint.replace("http://", "", 1)
    elif otel_endpoint.startswith("https://"):
        otel_endpoint = otel_endpoint.replace("https://", "", 1)
    
    environment = os.getenv("ENVIRONMENT", "production")
    
    # Create resource
    resource = Resource(attributes={
        SERVICE_NAME: service_name,
        SERVICE_VERSION: service_version,
        "deployment.environment": environment,
        "service.namespace": "feature-flag",
    })
    
    # Configure tracing
    trace_provider = TracerProvider(resource=resource)
    otlp_trace_exporter = OTLPSpanExporter(
        endpoint=otel_endpoint,
        insecure=True
    )
    trace_provider.add_span_processor(BatchSpanProcessor(otlp_trace_exporter))
    trace.set_tracer_provider(trace_provider)
    
    # Configure metrics
    otlp_metric_exporter = OTLPMetricExporter(
        endpoint=otel_endpoint,
        insecure=True
    )
    metric_reader = PeriodicExportingMetricReader(
        otlp_metric_exporter,
        export_interval_millis=30000
    )
    metrics_provider = MeterProvider(
        resource=resource,
        metric_readers=[metric_reader]
    )
    metrics.set_meter_provider(metrics_provider)
    
    # Get tracer and meter
    tracer = trace.get_tracer(__name__)
    meter = metrics.get_meter(__name__)
    
    log.info(f"OpenTelemetry initialized for {service_name} v{service_version}")
    log.info(f"Sending telemetry to: {otel_endpoint}")
    
    return tracer, meter


def instrument_flask_app(app):
    """
    Instrument a Flask application with OpenTelemetry.
    
    Args:
        app: Flask application instance
    """
    FlaskInstrumentor().instrument_app(app)
    RequestsInstrumentor().instrument()
    log.info("Flask app instrumented with OpenTelemetry")


def instrument_psycopg2():
    """
    Instrument psycopg2 connections with OpenTelemetry.
    """
    Psycopg2Instrumentor().instrument()
    log.info("psycopg2 instrumented with OpenTelemetry")
