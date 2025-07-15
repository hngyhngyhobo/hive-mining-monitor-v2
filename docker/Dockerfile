# Dockerfile for Hive Mining Monitor - Multi-Architecture Compatible
FROM mcr.microsoft.com/powershell:latest

# Metadata labels
LABEL org.opencontainers.image.title="Hive Mining Monitor"
LABEL org.opencontainers.image.description="HiveOS mining rig monitoring with MQTT support for Unraid"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/hngyhngyhobo/hive-mining-monitor-v2"
LABEL org.opencontainers.image.licenses="MIT"

# Set environment variable to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies with better error handling
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        iputils-ping \
        netcat-openbsd \
        tzdata \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
        && rm -rf /tmp/* \
        && rm -rf /var/tmp/*

# Create non-root user for security (Unraid best practice)
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/bash -d /home/appuser -m appuser

# Set working directory
WORKDIR /app

# Copy application files
COPY src/mining-monitor.ps1 ./
COPY docker/entrypoint.sh ./
RUN chmod +x entrypoint.sh

# Create directories for volumes
RUN mkdir -p /config /logs && \
    chown -R appuser:appuser /app /config /logs

# Set default environment variables
ENV PUID=1000 \
    PGID=1000 \
    TZ=UTC \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    RUN_INTERVAL=300 \
    LOG_LEVEL=INFO \
    MQTT_PORT=1883

# Health check for container monitoring
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pwsh -Command "if (\$env:MQTT_BROKER) { try { \$null = Test-NetConnection -ComputerName \$env:MQTT_BROKER -Port \$env:MQTT_PORT -InformationLevel Quiet -WarningAction SilentlyContinue; exit 0 } catch { exit 1 } } else { exit 0 }"

# Expose ports (documentation only)
EXPOSE 1883

# Set up volumes
VOLUME ["/config", "/logs"]

# Switch to non-root user
USER appuser

# Use entrypoint script for Unraid compatibility
ENTRYPOINT ["./entrypoint.sh"]
CMD ["pwsh", "-File", "mining-monitor.ps1"]