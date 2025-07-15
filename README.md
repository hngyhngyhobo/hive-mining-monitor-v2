# Hive Mining Monitor for Unraid

[![Docker Pulls](https://img.shields.io/docker/pulls/sirsnowman/hive-mining-monitor?style=flat-square)](https://hub.docker.com/r/sirsnowman/hive-mining-monitor)
[![GitHub release](https://img.shields.io/github/v/release/hngyhngyhobo/hive-mining-monitor-v2?style=flat-square)](https://github.com/hngyhngyhobo/hive-mining-monitor-v2/releases)
[![Docker Image Size](https://img.shields.io/docker/image-size/sirsnowman/hive-mining-monitor/latest?style=flat-square)](https://hub.docker.com/r/sirsnowman/hive-mining-monitor)
[![License](https://img.shields.io/github/license/hngyhngyhobo/hive-mining-monitor-v2?style=flat-square)](LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/hngyhngyhobo/hive-mining-monitor-v2/docker-publish.yml?style=flat-square)](https://github.com/hngyhngyhobo/hive-mining-monitor-v2/actions)

> **Real-time HiveOS mining rig monitoring with MQTT integration for Unraid and home automation systems.**

Transform your mining operation monitoring with this powerful, lightweight container that bridges HiveOS data to your home automation setup through MQTT. Perfect for Unraid users who want seamless integration with Home Assistant, Node-RED, or any MQTT-enabled system.

## ✨ Features

- 🔄 **Real-time monitoring** of all your HiveOS mining workers
- 📡 **MQTT integration** for seamless home automation connectivity
- 🐳 **Unraid optimized** with full Community Applications support
- 🔒 **Secure API communication** using official HiveOS APIs
- ⚙️ **Highly configurable** monitoring intervals and logging levels
- 🌡️ **Comprehensive metrics** including hashrates, temperatures, and uptime
- 📊 **Multi-worker support** with individual and farm-wide statistics
- 🏥 **Health monitoring** with automatic restarts and error recovery
- 🔧 **Easy deployment** via Docker with environment variable configuration
- 🏗️ **Multi-architecture** support (x86_64 and ARM64)

## 📊 Monitored Metrics

### Farm-Level Statistics
- Total worker count (online/offline)
- Combined hashrate across all workers
- Farm efficiency percentage
- Average CPU temperature across workers
- Farm status and heartbeat

### Individual Worker Metrics
- Hashrate (KH/s with precision)
- CPU temperature monitoring
- Uptime tracking (both seconds and human-readable)
- Online/offline status
- Active flight sheet configuration
- Power consumption (when available)
- Last seen timestamp

## 🚀 Quick Start

### Unraid Installation (Recommended)

1. **Install via Community Applications:**
   - Open Unraid WebGUI → Apps tab
   - Search for "Hive Mining Monitor"
   - Click Install and configure your settings
   - Apply and start monitoring!

2. **Manual Docker Installation:**
   ```bash
   docker run -d \
     --name=hive-mining-monitor \
     --restart=unless-stopped \
     -v /mnt/user/appdata/hive-mining-monitor:/config \
     -v /mnt/user/appdata/hive-mining-monitor/logs:/logs \
     -e HIVE_API_TOKEN=your_hive_api_token \
     -e HIVE_FARM_ID=your_farm_id \
     -e MQTT_BROKER=your_mqtt_broker_ip \
     -e PUID=99 \
     -e PGID=100 \
     -e TZ=America/New_York \
     sirsnowman/hive-mining-monitor:latest