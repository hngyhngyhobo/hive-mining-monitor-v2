#!/bin/sh
# entrypoint.sh - Unraid-compatible entrypoint script

set -e

echo "=============================================="
echo "Hive Mining Monitor Container Starting..."
echo "=============================================="
echo "Container Version: 1.0.0"
echo "PowerShell Version: $(pwsh -Command '$PSVersionTable.PSVersion')"
echo "Current Time: $(date)"
echo ""

# Set timezone if provided
if [ -n "$TZ" ]; then
    echo "🕐 Setting timezone to: $TZ"
    if [ -f "/usr/share/zoneinfo/$TZ" ]; then
        # Try to set timezone, but don't fail if we can't (non-root user)
        if ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null; then
            echo "$TZ" > /etc/timezone 2>/dev/null || true
            echo "✓ Timezone set successfully"
        else
            echo "⚠ Warning: Cannot set timezone (running as non-root), using default"
        fi
    else
        echo "⚠ Warning: Timezone $TZ not found, using default"
    fi
    echo ""
fi

# Handle PUID/PGID for Unraid compatibility
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    echo "👤 Unraid User Configuration:"
    echo "   PUID: $PUID"
    echo "   PGID: $PGID"
    echo "   Current UID: $(id -u)"
    echo "   Current GID: $(id -g)"
    echo ""
fi

# Set umask for file permissions
if [ -n "$UMASK" ]; then
    echo "🔒 Setting umask to: $UMASK"
    umask "$UMASK"
fi

# Validate required environment variables
echo "🔍 Validating configuration..."

if [ -z "$HIVE_API_TOKEN" ]; then
    echo "❌ ERROR: HIVE_API_TOKEN environment variable is required"
    echo "   Get your token from: https://hiveos.farm -> Account Settings -> API"
    exit 1
fi

if [ -z "$HIVE_FARM_ID" ]; then
    echo "❌ ERROR: HIVE_FARM_ID environment variable is required"
    echo "   Find your Farm ID in the HiveOS dashboard URL"
    exit 1
fi

if [ -z "$MQTT_BROKER" ]; then
    echo "❌ ERROR: MQTT_BROKER environment variable is required"
    echo "   Set this to your MQTT broker IP address or hostname"
    exit 1
fi

echo "✓ Required environment variables are set"
echo ""

# Display configuration
echo "📋 Configuration Summary:"
echo "   Farm ID: $HIVE_FARM_ID"
echo "   MQTT Broker: $MQTT_BROKER:${MQTT_PORT:-1883}"
echo "   Update Interval: ${RUN_INTERVAL:-300} seconds"
echo "   Log Level: ${LOG_LEVEL:-INFO}"
echo "   Timezone: ${TZ:-UTC}"
if [ -n "$MQTT_USERNAME" ]; then
    echo "   MQTT Auth: Enabled (username: $MQTT_USERNAME)"
else
    echo "   MQTT Auth: Disabled"
fi
echo ""

# Test network connectivity
echo "🌐 Testing network connectivity..."

# Test internet connectivity
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ Internet connectivity OK"
else
    echo "⚠ Warning: No internet connectivity detected"
fi

# Test HiveOS API
echo "🔗 Testing HiveOS API connectivity..."
if nc -z api2.hiveos.farm 443 2>/dev/null; then
    echo "✓ HiveOS API reachable"
else
    echo "⚠ Warning: HiveOS API not reachable"
fi

# Test MQTT broker connectivity
if [ -n "$MQTT_BROKER" ]; then
    echo "📡 Testing MQTT broker connectivity to $MQTT_BROKER:${MQTT_PORT:-1883}..."
    if nc -z "$MQTT_BROKER" "${MQTT_PORT:-1883}" 2>/dev/null; then
        echo "✓ MQTT broker reachable"
    else
        echo "⚠ Warning: MQTT broker not reachable (will retry during operation)"
    fi
fi

echo ""

# Create directories and set permissions
echo "📁 Setting up directories..."
mkdir -p /config /logs
touch /logs/mining-monitor.log

# Ensure proper permissions
if [ "$(id -u)" = "0" ]; then
    chown -R appuser:appuser /config /logs /app 2>/dev/null || true
fi

echo "✓ Directory setup complete"
echo ""

echo "🚀 Starting Hive Mining Monitor..."
echo "   Press Ctrl+C to stop"
echo "=============================================="
echo ""

# Execute the command passed to the container
exec "$@"