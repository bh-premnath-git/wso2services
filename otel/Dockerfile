FROM otel/opentelemetry-collector-contrib:0.113.0 AS collector

FROM alpine:3.19
# Temporarily use HTTP to install ca-certificates, then switch back to HTTPS
RUN sed -i 's/https/http/g' /etc/apk/repositories && \
    apk add --no-cache ca-certificates && \
    sed -i 's/http:/https:/g' /etc/apk/repositories && \
    apk add --no-cache curl tzdata
COPY --from=collector /otelcol-contrib /otelcol-contrib
ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config=/etc/otelcol/config.yaml"]