#!/usr/bin/env bash

set -euo pipefail

PROMETHEUS_VERSION="prometheus-2.54.0.linux-amd64.tar.gz"
PROMETHEUS_DIR="prometheus-2.54.0.linux-amd64"
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v2.54.0/${PROMETHEUS_VERSION}"

# You must be root
if [ "${EUID}" -ne 0 ]; then
    echo "ERROR: You are not super user" >&2
    exit 1
fi

# Install adduser if not present
if ! command -v adduser &> /dev/null; then
    apt update
    apt install -y adduser wget tar
fi

export PATH=$PATH:/usr/sbin

# Create Prometheus user (system user, no home)
id -u prometheus &>/dev/null || adduser --system --no-create-home --group prometheus

# Create directories
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus
chown -R prometheus:prometheus /etc/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

# Download and extract Prometheus
cd /tmp
wget -O "${PROMETHEUS_VERSION}" "${PROMETHEUS_URL}"
tar xvf "${PROMETHEUS_VERSION}"

# Copy binaries
cd "${PROMETHEUS_DIR}"
cp prometheus /usr/local/bin/
cp promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Copy consoles and libraries
cp -r consoles /etc/prometheus
cp -r console_libraries /etc/prometheus
chown -R prometheus:prometheus /etc/prometheus

# Create Prometheus config
cat <<EOF > /etc/prometheus/prometheus.yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - '192.168.100.10:9100'
          - '192.168.100.20:9100'
          - '192.168.100.21:9100'
          - '192.168.100.40:9283'
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yaml

# Create systemd service
cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yaml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.listen-address=:9090

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
systemctl daemon-reexec
systemctl enable --now prometheus
systemctl status prometheus

