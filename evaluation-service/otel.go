package main

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// InitOpenTelemetry configures and initializes OpenTelemetry tracing and metrics
func InitOpenTelemetry(serviceName, serviceVersion string) (func(context.Context) error, error) {
	ctx := context.Background()

	// Get OTEL collector endpoint from environment
	otelEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otelEndpoint == "" {
		otelEndpoint = "otel-collector.observability.svc.cluster.local:4317"
	}

	// Remove http:// or https:// prefix if present (gRPC doesn't accept it)
	otelEndpoint = strings.TrimPrefix(otelEndpoint, "http://")
	otelEndpoint = strings.TrimPrefix(otelEndpoint, "https://")

	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "production"
	}

	// Create resource
	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
			semconv.DeploymentEnvironment(environment),
			semconv.ServiceNamespace("feature-flag"),
		),
	)
	if err != nil {
		return nil, err
	}

	// Set up trace provider
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(
		ctx,
		otelEndpoint,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		log.Printf("Failed to create gRPC connection to collector: %v", err)
		return nil, err
	}

	traceExporter, err := otlptracegrpc.New(ctx, otlptracegrpc.WithGRPCConn(conn))
	if err != nil {
		return nil, err
	}

	bsp := trace.NewBatchSpanProcessor(traceExporter)
	tracerProvider := trace.NewTracerProvider(
		trace.WithSampler(trace.AlwaysSample()),
		trace.WithResource(res),
		trace.WithSpanProcessor(bsp),
	)
	otel.SetTracerProvider(tracerProvider)

	// Set up propagation
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Set up metric provider
	metricExporter, err := otlpmetricgrpc.New(
		ctx,
		otlpmetricgrpc.WithGRPCConn(conn),
	)
	if err != nil {
		return nil, err
	}

	meterProvider := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(
			metricExporter,
			metric.WithInterval(30*time.Second),
		)),
	)
	otel.SetMeterProvider(meterProvider)

	log.Printf("OpenTelemetry initialized for %s v%s", serviceName, serviceVersion)
	log.Printf("Sending telemetry to: %s", otelEndpoint)

	// Return cleanup function
	return func(ctx context.Context) error {
		ctxWithTimeout, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()

		if err := tracerProvider.Shutdown(ctxWithTimeout); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}

		if err := meterProvider.Shutdown(ctxWithTimeout); err != nil {
			log.Printf("Error shutting down meter provider: %v", err)
		}

		return nil
	}, nil
}
