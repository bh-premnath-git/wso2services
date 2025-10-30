FROM otel/opentelemetry-collector-contrib:latest AS collector

FROM alpine:3.19
RUN apk add --no-cache ca-certificates curl
COPY --from=collector /otelcol-contrib /otelcol-contrib
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config=/etc/otelcol/config.yaml"]