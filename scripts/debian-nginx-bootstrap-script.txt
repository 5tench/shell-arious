#!/bin/bash
set -euo pipefail

# === LOGGING SETUP ===
LOG_FILE="/var/log/bootstrap.log"
MARKER_FILE="/var/log/bootstrap_complete"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" | tee -a "$LOG_FILE"
}

log "=== BOOTSTRAP STARTED ==="

# === EXIT IF ALREADY COMPLETED ===
if [[ -f "$MARKER_FILE" ]]; then
    log "Bootstrap already completed"
    exit 0
fi

# === OS CHECK ===
if [[ ! -f /etc/os-release ]]; then
    log "ERROR: No OS release file"
    exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    log "ERROR: Unsupported OS: $ID"
    exit 1
fi
log "OS: $ID $VERSION_ID"

# === SYSTEM UPDATE ===
export DEBIAN_FRONTEND=noninteractive

log "Updating APT..."
apt-get update -y >>"$LOG_FILE" 2>&1 || log "APT update FAILED"

log "Upgrading packages..."
apt-get upgrade -y >>"$LOG_FILE" 2>&1 || log "APT upgrade FAILED"

# === INSTALL PACKAGES ===
PACKAGES=(nginx curl git unattended-upgrades jq ufw)
log "Installing packages: ${PACKAGES[*]}"
apt-get install -y "${PACKAGES[@]}" >>"$LOG_FILE" 2>&1 || log "Install FAILED"

# === CONFIGURE NGINX ===
log "Configuring NGINX default site..."
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location = /health.html {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
NGINX

log "Restarting NGINX..."
systemctl restart nginx

# === ENABLE FIREWALL ===
log "Configuring UFW firewall..."
ufw allow 'Nginx Full'
ufw --force enable

# === MARK COMPLETION ===
touch "$MARKER_FILE"
log "=== BOOTSTRAP COMPLETE ==="