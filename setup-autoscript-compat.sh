#!/usr/bin/env bash
set -euo pipefail

# AutoScript kompatibel BotVPN/Potato
# Target OS: Debian 12+ / Ubuntu 22+
#
# Fitur:
# - SSH
# - VMess / VLESS / Trojan (Xray + Nginx + Let's Encrypt)
# - UDP/ZIVPN (jika binary zivpn tersedia)
# - HTTP API kompatibel endpoint /vps/* yang dipakai bot
# - Database kompatibel potato.db untuk summary API
#
# Env opsional:
#   DOMAIN=example.com
#   EMAIL=admin@example.com
#   API_AUTH_TOKEN=token-rahasia
#   UPDATE_SCRIPT_URL=https://raw.githubusercontent.com/harismy/sc1forcr/main/setup-autoscript-compat.sh
#   ZIVPN_BIN_URL=https://.../zivpn-linux-amd64   (opsional)
#   ZIVPN_RELEASE_TAG=udp-zivpn_1.4.9             (opsional, default dari repo zahidbd2/udp-zivpn)
#   ZIVPN_SERVICE_NAME=zivpn
#   ZIVPN_LISTEN_PORT=5667
#   ZIVPN_DNAT_RANGE=6000:19999
#   ZIVPN_DNAT_IFACE=eth0                          (opsional, default auto-detect)
#   UDPCUSTOM_BIN_URL=https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64
#   UDPCUSTOM_SERVICE_NAME=sc-1forcr-udpcustom
#   UDPCUSTOM_LISTEN_PORT=5667
#   UDPCUSTOM_DNAT_RANGE=                        (opsional, default kosong = tanpa DNAT range untuk performa)
#   UDPCUSTOM_DEFAULT_USER=freeudphc
#   ACTIVE_UDP_BACKEND=zivpn                       (pilihan: zivpn|udpcustom)
#   DROPBEAR_PORT=109
#   DROPBEAR_ALT_PORT=143
#   DROPBEAR_VERSION=2019.78
#   DB_PATH=/usr/sbin/potatonc/potato.db
#   APP_DIR=/opt/sc-1forcr

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
API_AUTH_TOKEN="${API_AUTH_TOKEN:-}"
SCRIPT_VERSION="${SCRIPT_VERSION:-2026.04.05-1}"
UPDATE_SCRIPT_URL="${UPDATE_SCRIPT_URL:-https://raw.githubusercontent.com/harismy/sc1forcr/main/setup-autoscript-compat.sh}"
DB_PATH="${DB_PATH:-/usr/sbin/potatonc/potato.db}"
APP_DIR="${APP_DIR:-/opt/sc-1forcr}"
API_PORT="${API_PORT:-8088}"
ZIVPN_BIN_URL="${ZIVPN_BIN_URL:-}"
ZIVPN_RELEASE_TAG="${ZIVPN_RELEASE_TAG:-udp-zivpn_1.4.9}"
ZIVPN_SERVICE_NAME="${ZIVPN_SERVICE_NAME:-zivpn}"
ZIVPN_LISTEN_PORT="${ZIVPN_LISTEN_PORT:-5667}"
ZIVPN_DNAT_RANGE="${ZIVPN_DNAT_RANGE:-6000:19999}"
ZIVPN_DNAT_IFACE="${ZIVPN_DNAT_IFACE:-}"
UDPCUSTOM_BIN_URL="${UDPCUSTOM_BIN_URL:-https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64}"
UDPCUSTOM_SERVICE_NAME="${UDPCUSTOM_SERVICE_NAME:-sc-1forcr-udpcustom}"
UDPCUSTOM_LISTEN_PORT="${UDPCUSTOM_LISTEN_PORT:-5667}"
UDPCUSTOM_DNAT_RANGE="${UDPCUSTOM_DNAT_RANGE:-}"
UDPCUSTOM_DEFAULT_USER="${UDPCUSTOM_DEFAULT_USER:-freeudphc}"
ACTIVE_UDP_BACKEND="${ACTIVE_UDP_BACKEND:-zivpn}"
DROPBEAR_PORT="${DROPBEAR_PORT:-109}"
DROPBEAR_ALT_PORT="${DROPBEAR_ALT_PORT:-143}"
DROPBEAR_VERSION="${DROPBEAR_VERSION:-2019.78}"

if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
  echo "setup-autoscript-compat ${SCRIPT_VERSION}"
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Jalankan sebagai root."
  exit 1
fi

if [[ -z "${DOMAIN}" ]]; then
  read -r -p "Masukkan domain server: " DOMAIN
fi

if [[ -z "${DOMAIN}" ]]; then
  echo "DOMAIN wajib diisi."
  exit 1
fi

if [[ -z "${EMAIL}" ]]; then
  read -r -p "Masukkan email Let's Encrypt [admin@${DOMAIN}]: " EMAIL
  EMAIL="${EMAIL:-admin@${DOMAIN}}"
fi

if [[ "${EMAIL}" == "admin@example.com" || "${EMAIL}" == *"@example.com" ]]; then
  echo "EMAIL default ${EMAIL} tidak valid untuk Let's Encrypt."
  echo "Gunakan email asli. Contoh: EMAIL=admin@${DOMAIN}"
  exit 1
fi

if [[ -z "${API_AUTH_TOKEN}" ]]; then
  API_AUTH_TOKEN="$(openssl rand -hex 24)"
fi

log() {
  echo "[autoscript-compat] $*"
}

install_base_packages() {
  log "Install paket dasar..."
  apt-get update -y
  apt-get install -y \
    curl wget jq sqlite3 openssl uuid-runtime ca-certificates \
    gnupg lsb-release socat cron unzip \
    haproxy \
    nginx certbot python3-certbot-nginx \
    openssh-server dropbear pwgen \
    build-essential python3 make g++ gcc libc6-dev pkg-config bzip2 zlib1g-dev
}

install_node20_if_missing() {
  if command -v node >/dev/null 2>&1; then
    log "Node sudah ada: $(node -v)"
    return
  fi
  log "Install Node.js 20..."
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}

install_go_if_missing() {
  if command -v go >/dev/null 2>&1; then
    log "Go sudah ada: $(go version)"
    return
  fi
  log "Install Go..."
  apt-get update -y
  apt-get install -y golang-go
  log "Go installed: $(go version)"
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then
    log "Xray sudah ada: $(xray version | head -n1)"
    return
  fi
  log "Install Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}
setup_dropbear() {
  log "Setup Dropbear..."

  local main_port alt_port
  main_port="$(echo "${DROPBEAR_PORT}" | tr -cd '0-9')"
  alt_port="$(echo "${DROPBEAR_ALT_PORT}" | tr -cd '0-9')"
  [[ -z "${main_port}" ]] && main_port="109"
  [[ -z "${alt_port}" ]] && alt_port="143"
  if [[ "${main_port}" -lt 1 || "${main_port}" -gt 65535 ]]; then main_port="109"; fi
  if [[ "${alt_port}" -lt 1 || "${alt_port}" -gt 65535 ]]; then alt_port="143"; fi

  cat > /etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=${main_port}
DROPBEAR_EXTRA_ARGS="-p ${alt_port}"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

  local src_dir archive_url archive_path build_dir custom_bin
  src_dir="/usr/local/src"
  archive_url="https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
  archive_path="${src_dir}/dropbear-${DROPBEAR_VERSION}.tar.bz2"
  build_dir="${src_dir}/dropbear-${DROPBEAR_VERSION}"
  custom_bin="/usr/local/sbin/dropbear-${DROPBEAR_VERSION}"

  if [[ ! -x "${custom_bin}" ]]; then
    log "Build Dropbear ${DROPBEAR_VERSION} from source..."
    mkdir -p "${src_dir}"
    rm -rf "${build_dir}"
    curl -fL --retry 5 --retry-delay 2 "${archive_url}" -o "${archive_path}"
    tar -xjf "${archive_path}" -C "${src_dir}"
    (
      cd "${build_dir}"
      ./configure --prefix=/usr/local --sysconfdir=/etc/dropbear
      make -j"$(nproc || echo 1)"
      cp -f dropbear "${custom_bin}"
      if [[ -x ./dropbearkey ]]; then
        cp -f ./dropbearkey /usr/local/bin/dropbearkey-sc1
      fi
    )
    chmod 755 "${custom_bin}"
  fi

  mkdir -p /etc/dropbear
  if [[ -x /usr/local/bin/dropbearkey-sc1 ]]; then
    [[ -s /etc/dropbear/dropbear_rsa_host_key ]] || /usr/local/bin/dropbearkey-sc1 -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
    [[ -s /etc/dropbear/dropbear_ecdsa_host_key ]] || /usr/local/bin/dropbearkey-sc1 -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
    [[ -s /etc/dropbear/dropbear_ed25519_host_key ]] || /usr/local/bin/dropbearkey-sc1 -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
  fi

  mkdir -p /etc/systemd/system/dropbear.service.d
  cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=${custom_bin} -R -E -F -p ${main_port} -p ${alt_port}
EOF

  systemctl daemon-reload
  systemctl enable dropbear >/dev/null 2>&1 || true
  systemctl restart dropbear >/dev/null 2>&1 || true
}

init_db() {
  log "Inisialisasi DB: ${DB_PATH}"
  mkdir -p "$(dirname "${DB_PATH}")"

  sqlite3 "${DB_PATH}" <<SQL
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS servers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS account_sshs (
  username TEXT PRIMARY KEY,
  password TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS account_vmesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS account_vlesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS account_trojans (
  username TEXT PRIMARY KEY,
  password TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS temp_ip_locks (
  account_type TEXT NOT NULL,
  username TEXT NOT NULL,
  locked_until INTEGER NOT NULL,
  zivpn_removed INTEGER DEFAULT 0,
  created_at INTEGER DEFAULT (strftime('%s','now')),
  PRIMARY KEY (account_type, username)
);

INSERT OR IGNORE INTO servers("key") VALUES('${API_AUTH_TOKEN}');
SQL
}

apply_system_optimizations() {
  log "Apply basic optimization (1GB RAM friendly)..."

  if ! swapon --show | grep -q .; then
    if [[ ! -f /swapfile ]]; then
      fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
    fi
    swapon /swapfile || true
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  cat > /etc/sysctl.d/99-sc-1forcr.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
net.core.somaxconn=1024
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=4096
EOF
  sysctl --system >/dev/null 2>&1 || true

  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/limit.conf <<'EOF'
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
EOF
  systemctl restart systemd-journald || true
}

setup_logrotate_optimizations() {
  log "Setup logrotate ringkas..."
  cat > /etc/logrotate.d/sc-1forcr <<'EOF'
/var/log/xray/*.log /var/log/nginx/*.log {
  daily
  rotate 7
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF
}

setup_nginx_and_cert() {
  log "Setup Nginx vhost (80 only)..."
  mkdir -p /var/www/html
  cat > /etc/nginx/sites-available/sc-1forcr.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    keepalive_timeout 30;

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location = /cdn-cgi/trace {
        access_log off;
        default_type text/plain;
        return 200 "fl=29f200\nh=\$host\nip=\$remote_addr\nts=\$msec\n";
    }

    location /vps/ {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /vmess {
        access_log off;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location /vless {
        access_log off;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location /trojan {
        access_log off;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location / {
        access_log off;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/sc-1forcr.conf /etc/nginx/sites-enabled/sc-1forcr.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx
  systemctl restart nginx

  log "Issue cert Let's Encrypt (webroot)..."
  if ! certbot certonly --webroot -w /var/www/html -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}"; then
    log "Let's Encrypt gagal. Lanjut tanpa TLS 443 (haproxy belum diaktifkan)."
  fi
}

setup_haproxy_tls_mux() {
  local fullchain privkey pem
  fullchain="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  privkey="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
  pem="/etc/haproxy/certs/${DOMAIN}.pem"

  if [[ ! -s "${fullchain}" || ! -s "${privkey}" ]]; then
    log "Sertifikat tidak ditemukan untuk ${DOMAIN}, skip setup haproxy 443."
    return 0
  fi

  log "Setup HAProxy TLS mux di 443..."
  mkdir -p /etc/haproxy/certs
  cat "${fullchain}" "${privkey}" > "${pem}"
  chmod 600 "${pem}"

  cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 20000
    nbthread 1

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 10s
    timeout client  2m
    timeout server  2m

frontend ft_443
    bind *:443 ssl crt ${pem} alpn h2,http/1.1
    default_backend bk_mux

backend bk_mux
    mode tcp
    server mux_local 127.0.0.1:2082 check
EOF

  haproxy -c -f /etc/haproxy/haproxy.cfg
  systemctl disable stunnel4 >/dev/null 2>&1 || true
  systemctl stop stunnel4 >/dev/null 2>&1 || true
  systemctl enable haproxy >/dev/null 2>&1 || true
  systemctl restart haproxy >/dev/null 2>&1 || true
}

resolve_zivpn_bin_url() {
  if [[ -n "${ZIVPN_BIN_URL}" ]]; then
    echo "${ZIVPN_BIN_URL}"
    return 0
  fi

  local arch raw_arch
  raw_arch="$(uname -m)"
  case "${raw_arch}" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo ""
      return 0
      ;;
  esac

  echo "https://github.com/zahidbd2/udp-zivpn/releases/download/${ZIVPN_RELEASE_TAG}/udp-zivpn-linux-${arch}"
  return 0
}

setup_zivpn_service_if_possible() {
  mkdir -p /etc/zivpn
  if [[ ! -f /etc/zivpn/config.json ]]; then
    cat > /etc/zivpn/config.json <<EOF
{
  "auth": {
    "mode": "passwords",
    "config": []
  },
  "network": {
    "tcp": true,
    "udp": true
  },
  "listen": ":${ZIVPN_LISTEN_PORT}"
}
EOF
  fi

  if command -v zivpn >/dev/null 2>&1; then
    log "Binary zivpn sudah ada."
  else
    local resolved_url
    resolved_url="$(resolve_zivpn_bin_url)"
    if [[ -z "${resolved_url}" ]]; then
      log "Arsitektur $(uname -m) belum didukung auto-download ZIVPN. Isi ZIVPN_BIN_URL manual."
    else
      log "Download binary zivpn: ${resolved_url}"
      if curl -fL --retry 5 --retry-delay 2 "${resolved_url}" -o /usr/local/bin/zivpn; then
        chmod +x /usr/local/bin/zivpn
      else
        log "Gagal download binary zivpn. Lanjut tanpa service ZIVPN."
      fi
    fi
  fi

  if command -v zivpn >/dev/null 2>&1; then
    if ! /usr/local/bin/zivpn --help >/dev/null 2>&1; then
      log "Peringatan: binary /usr/local/bin/zivpn terdeteksi tapi tidak bisa dijalankan normal."
    fi
  else
    log "Binary zivpn belum ada. Service ZIVPN tidak diaktifkan."
  fi

  if command -v zivpn >/dev/null 2>&1; then
    cat > /etc/systemd/system/${ZIVPN_SERVICE_NAME}.service <<EOF
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${ZIVPN_SERVICE_NAME}" || true
    systemctl restart "${ZIVPN_SERVICE_NAME}" || true
  fi
}

setup_zivpn_udp_nat_rules() {
  if ! command -v zivpn >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v iptables >/dev/null 2>&1; then
    log "iptables tidak ditemukan. Skip rule DNAT ZIVPN."
    return 0
  fi

  local listen_port
  listen_port="$(jq -r '.listen // empty' /etc/zivpn/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  if [[ -z "${listen_port}" ]]; then
    listen_port="$(echo "${ZIVPN_LISTEN_PORT}" | tr -cd '0-9')"
  fi
  if [[ -z "${listen_port}" ]]; then
    listen_port="5667"
  fi

  log "Set rule UDP ZIVPN: listen=${listen_port}, dnat_range=${ZIVPN_DNAT_RANGE}"

  iptables -C INPUT -p udp --dport "${listen_port}" -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p udp --dport "${listen_port}" -j ACCEPT

  # Cleanup rule lama yang terikat interface tertentu (sering tidak match setelah rename NIC).
  while IFS= read -r rule; do
    [[ -z "${rule}" ]] && continue
    iptables -t nat ${rule/-A/-D} >/dev/null 2>&1 || true
  done < <(iptables -t nat -S PREROUTING | \
    grep -F -- "--dport ${ZIVPN_DNAT_RANGE} -j DNAT --to-destination :${listen_port}" | \
    grep -F -- "-i " || true)

  iptables -t nat -C PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${listen_port}" >/dev/null 2>&1 || \
    iptables -t nat -I PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${listen_port}"

  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Install netfilter-persistent agar rule iptables tidak hilang saat reboot..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent >/dev/null 2>&1 || true
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  fi
}

setup_udpcustom_service_if_possible() {
  mkdir -p /root/udp

  if [[ ! -x /root/udp/udp-custom ]]; then
    log "Download binary udp-custom: ${UDPCUSTOM_BIN_URL}"
    if curl -fL --retry 5 --retry-delay 2 "${UDPCUSTOM_BIN_URL}" -o /root/udp/udp-custom; then
      chmod +x /root/udp/udp-custom
    else
      log "Gagal download udp-custom. Lanjut tanpa service UDP Custom."
      return 0
    fi
  fi

  if [[ ! -f /root/udp/config.json ]]; then
    cat > /root/udp/config.json <<EOF
{
  "listen": ":${UDPCUSTOM_LISTEN_PORT}",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords",
    "config": [
      "${UDPCUSTOM_DEFAULT_USER}"
    ]
  }
}
EOF
  fi

  cat > /etc/systemd/system/${UDPCUSTOM_SERVICE_NAME}.service <<EOF
[Unit]
Description=SC 1FORCR UDP Custom Core
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
}

setup_udpcustom_udp_nat_rules() {
  if [[ ! -x /root/udp/udp-custom ]]; then
    return 0
  fi
  if ! command -v iptables >/dev/null 2>&1; then
    log "iptables tidak ditemukan. Skip rule DNAT UDP Custom."
    return 0
  fi

  local listen_port backend
  backend="$(echo "${ACTIVE_UDP_BACKEND:-}" | tr '[:upper:]' '[:lower:]')"
  listen_port="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  if [[ -z "${listen_port}" ]]; then
    listen_port="$(echo "${UDPCUSTOM_LISTEN_PORT}" | tr -cd '0-9')"
  fi
  if [[ -z "${listen_port}" ]]; then
    listen_port="5667"
  fi

  log "Set rule UDP UDPHC: listen=${listen_port}, dnat_range=${UDPCUSTOM_DNAT_RANGE:-none}"

  iptables -C INPUT -p udp --dport "${listen_port}" -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p udp --dport "${listen_port}" -j ACCEPT

  if [[ -n "${UDPCUSTOM_DNAT_RANGE}" ]]; then
    # Cleanup rule lama yang terikat interface tertentu.
    while IFS= read -r rule; do
      [[ -z "${rule}" ]] && continue
      iptables -t nat ${rule/-A/-D} >/dev/null 2>&1 || true
    done < <(iptables -t nat -S PREROUTING | \
      grep -F -- "--dport ${UDPCUSTOM_DNAT_RANGE} -j DNAT --to-destination :${listen_port}" | \
      grep -F -- "-i " || true)

    iptables -t nat -C PREROUTING -p udp --dport "${UDPCUSTOM_DNAT_RANGE}" -j DNAT --to-destination ":${listen_port}" >/dev/null 2>&1 || \
      iptables -t nat -I PREROUTING -p udp --dport "${UDPCUSTOM_DNAT_RANGE}" -j DNAT --to-destination ":${listen_port}"
  else
    log "UDPHC tanpa DNAT range (default performa). Isi UDPCUSTOM_DNAT_RANGE jika perlu mode tembak port."
    # Jangan hapus DNAT backend lain (contoh ZIVPN) saat mode aktif bukan UDPHC.
    if [[ "${backend}" == "udpcustom" || "${backend}" == "udp-custom" || "${backend}" == "udphc" ]]; then
      # Bersihkan rule DNAT lama ke port UDPHC agar tidak jadi bottleneck.
      while IFS= read -r rule; do
        [[ -z "${rule}" ]] && continue
        iptables -t nat ${rule/-A/-D} >/dev/null 2>&1 || true
      done < <(iptables -t nat -S PREROUTING | grep -F -- "-j DNAT --to-destination :${listen_port}" || true)
    else
      log "ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND}, cleanup DNAT UDPHC dilewati agar rule backend lain tetap aman."
    fi
  fi

  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Install netfilter-persistent agar rule iptables tidak hilang saat reboot..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent >/dev/null 2>&1 || true
  fi
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  fi
}

enforce_single_udp_backend() {
  local backend
  backend="$(echo "${ACTIVE_UDP_BACKEND}" | tr '[:upper:]' '[:lower:]')"
  case "${backend}" in
    udpcustom|udp-custom|udphc)
      systemctl disable --now "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl enable "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl restart "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      log "Backend UDP aktif: UDP Custom (${UDPCUSTOM_SERVICE_NAME})"
      ;;
    zivpn|*)
      systemctl disable --now "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl enable "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl restart "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      log "Backend UDP aktif: ZIVPN (${ZIVPN_SERVICE_NAME})"
      ;;
  esac
}

write_api_files() {
  log "Menulis API kompatibilitas..."
  mkdir -p "${APP_DIR}"

  cat > "${APP_DIR}/package.json" <<'EOF'
{
  "name": "sc-1forcr-api",
  "version": "1.0.0",
  "private": true,
  "main": "api.js",
  "dependencies": {
    "dotenv": "^16.4.7",
    "express": "^4.21.2",
    "sqlite3": "^5.1.7",
    "ws": "^8.18.1"
  }
}
EOF

  cat > "${APP_DIR}/.env" <<EOF
PORT=${API_PORT}
DB_PATH=${DB_PATH}
DOMAIN=${DOMAIN}
AUTH_TOKEN=${API_AUTH_TOKEN}
ZIVPN_CONFIG=/etc/zivpn/config.json
ZIVPN_SERVICE=${ZIVPN_SERVICE_NAME}
SSH_WS_PORT=2082
SSH_WS_TARGET_PORT=22
SSH_HTTP_BACKEND_HOST=127.0.0.1
SSH_HTTP_BACKEND_PORT=80
EOF

  cat > "${APP_DIR}/api.js" <<'EOF'
const express = require('express');
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();
const { execFileSync } = require('child_process');
const crypto = require('crypto');
try { require('dotenv').config(); } catch (_) {}

const app = express();
app.use(express.json({ limit: '1mb' }));

const PORT = Number(process.env.PORT || 8088);
const DB_PATH = process.env.DB_PATH || '/usr/sbin/potatonc/potato.db';
const DOMAIN = String(process.env.DOMAIN || '').trim();
const AUTH_TOKEN = String(process.env.AUTH_TOKEN || '').trim();
const ZIVPN_CONFIG = process.env.ZIVPN_CONFIG || '/etc/zivpn/config.json';
const ZIVPN_SERVICE = process.env.ZIVPN_SERVICE || 'zivpn';

const db = new sqlite3.Database(DB_PATH);

function ok(res, data, message = 'success') {
  return res.json({ meta: { code: 200, message }, data });
}
function fail(res, code, message) {
  return res.status(code).json({ meta: { code, message }, message });
}
function auth(req, res, next) {
  const token = String(req.headers.authorization || '').trim();
  if (!token || token !== AUTH_TOKEN) return fail(res, 401, 'unauthorized');
  next();
}
function ymdPlusDays(days) {
  const d = new Date();
  d.setDate(d.getDate() + Number(days || 0));
  return d.toISOString().slice(0, 10);
}
function nowTime() {
  return new Date().toTimeString().slice(0, 8);
}
function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(err) {
      if (err) return reject(err);
      resolve(this);
    });
  });
}
function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => (err ? reject(err) : resolve(row)));
  });
}
function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
  });
}

function safeExec(cmd, args, input) {
  try {
    const opts = { stdio: ['pipe', 'ignore', 'ignore'] };
    if (input) opts.input = input;
    execFileSync(cmd, args, opts);
    return true;
  } catch (_) {
    return false;
  }
}

function ensureLinuxUser(username, password, expDate) {
  const exists = safeExec('id', ['-u', username]);
  if (!exists) safeExec('useradd', ['-m', '-d', `/home/${username}`, '-s', '/bin/bash', username]);
  safeExec('chpasswd', [], `${username}:${password}\n`);
  safeExec('usermod', ['-s', '/bin/bash', username]);
  if (expDate) safeExec('chage', ['-E', expDate, username]);
}

function deleteLinuxUser(username) {
  safeExec('userdel', ['-r', username]);
}

function lockLinuxUser(username) {
  safeExec('passwd', ['-l', username]);
}

function unlockLinuxUser(username) {
  safeExec('passwd', ['-u', username]);
}

function zivpnReload() {
  if (!safeExec('systemctl', ['restart', ZIVPN_SERVICE])) {
    safeExec('service', [ZIVPN_SERVICE, 'restart']);
  }
}

let zivpnReloadTimer = null;
function scheduleZivpnReload(delayMs = 8000) {
  if (zivpnReloadTimer) clearTimeout(zivpnReloadTimer);
  zivpnReloadTimer = setTimeout(() => {
    zivpnReloadTimer = null;
    zivpnReload();
  }, Number(delayMs) || 8000);
}

function syncZivpnUser(username, addMode) {
  try {
    let root = { auth: { mode: 'passwords', config: [] } };
    if (fs.existsSync(ZIVPN_CONFIG)) root = JSON.parse(fs.readFileSync(ZIVPN_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') root.auth = {};
    if (!Array.isArray(root.auth.config)) root.auth.config = [];
    const beforeSet = new Set(root.auth.config.map((v) => String(v || '').trim().toLowerCase()).filter(Boolean));
    const set = new Set(beforeSet);
    const key = String(username || '').trim().toLowerCase();
    if (!key) return;
    if (addMode) set.add(key);
    else set.delete(key);
    let changed = false;
    if (set.size !== beforeSet.size) changed = true;
    if (!changed) {
      for (const item of set) {
        if (!beforeSet.has(item)) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;
    root.auth.config = Array.from(set);
    fs.writeFileSync(ZIVPN_CONFIG, JSON.stringify(root, null, 2));
    scheduleZivpnReload();
  } catch (_) {}
}

function vmessLink(host, id, tls) {
  const payload = {
    v: '2', ps: `vmess-${host}`, add: host, port: tls ? '443' : '80', id, aid: '0',
    net: 'ws', type: 'none', host, path: '/vmess', tls: tls ? 'tls' : 'none', sni: host
  };
  return `vmess://${Buffer.from(JSON.stringify(payload)).toString('base64')}`;
}
function vlessLink(host, id, tls) {
  return `vless://${id}@${host}:${tls ? '443' : '80'}?type=ws&path=%2Fvless&security=${tls ? 'tls' : 'none'}&sni=${host}#vless-${host}`;
}
function trojanLink(host, pass, tls) {
  return `trojan://${pass}@${host}:${tls ? '443' : '80'}?type=ws&path=%2Ftrojan&security=${tls ? 'tls' : 'none'}&sni=${host}#trojan-${host}`;
}

async function renderAndReloadXray() {
  const vmessRows = await all("SELECT username, uuid FROM account_vmesses WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");
  const vlessRows = await all("SELECT username, uuid FROM account_vlesses WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");
  const trojanRows = await all("SELECT username, password FROM account_trojans WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");

  const cfg = {
    log: {
      access: '/var/log/xray/access.log',
      error: '/var/log/xray/error.log',
      loglevel: 'warning'
    },
    inbounds: [
      {
        port: 10001, listen: '127.0.0.1', protocol: 'vmess',
        settings: { clients: vmessRows.map((r) => ({ id: String(r.uuid || ''), alterId: 0, email: String(r.username || '') })) },
        streamSettings: { network: 'ws', wsSettings: { path: '/vmess' } }
      },
      {
        port: 10002, listen: '127.0.0.1', protocol: 'vless',
        settings: { clients: vlessRows.map((r) => ({ id: String(r.uuid || ''), email: String(r.username || '') })), decryption: 'none' },
        streamSettings: { network: 'ws', security: 'none', wsSettings: { path: '/vless' } }
      },
      {
        port: 10003, listen: '127.0.0.1', protocol: 'trojan',
        settings: { clients: trojanRows.map((r) => ({ password: String(r.password || ''), email: String(r.username || '') })) },
        streamSettings: { network: 'ws', security: 'none', wsSettings: { path: '/trojan' } }
      }
    ],
    outbounds: [{ protocol: 'freedom', tag: 'direct' }]
  };
  fs.mkdirSync('/usr/local/etc/xray', { recursive: true });
  fs.writeFileSync('/usr/local/etc/xray/config.json', JSON.stringify(cfg, null, 2));
  safeExec('systemctl', ['restart', 'xray']);
}

app.get('/vps/health', (_req, res) => ok(res, { ok: true, domain: DOMAIN }));
app.use('/vps', auth);

function sshPayload(username, password, expDate, limitip) {
  return {
    hostname: DOMAIN,
    username,
    password,
    exp: expDate,
    time: nowTime(),
    port: { tls: '443', none: '80', ovpntcp: '1194', ovpnudp: '2200', sshohp: '8181', udpcustom: '1-65535' },
    ws_path: '/ssh-ws',
    ws_alt_path: '/ws',
    limitip: String(limitip || 0)
  };
}

async function ensureUsernameNotExists(table, username) {
  const row = await get(`SELECT 1 AS ok FROM ${table} WHERE LOWER(username)=LOWER(?)`, [username]);
  if (row) {
    const e = new Error(`username ${username} already exists`);
    e.statusCode = 409;
    throw e;
  }
}

async function createOrUpdateSshFromBody(body, forcedDays = null) {
  const username = String(body?.username || '').trim();
  const password = String(body?.password || username || '').trim() || username;
  const expDays = forcedDays === null ? Number(body?.expired || 30) : Number(forcedDays || 1);
  const quota = Number(body?.kuota || 0);
  const limitip = Number(body?.limitip || 0);
  if (!username) throw new Error('username required');
  await ensureUsernameNotExists('account_sshs', username);
  const expDate = ymdPlusDays(expDays);
  ensureLinuxUser(username, password, expDate);
  await run(
    "INSERT INTO account_sshs(username,password,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)",
    [username, password, expDate, 'AKTIF', quota, limitip]
  );
  syncZivpnUser(username, true);
  return sshPayload(username, password, expDate, limitip);
}

app.post('/vps/sshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req.body, null));
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});

app.post('/vps/trialsshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req.body, 1));
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});

app.delete('/vps/deletesshvpn/:username', async (req, res) => {
  try {
    const username = String(req.params.username || '').trim();
    deleteLinuxUser(username);
    await run("DELETE FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]);
    syncZivpnUser(username, false);
    return ok(res, { username });
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

async function renewSsh(req, res) {
  try {
    const username = String(req.params.username || '').trim();
    const exp = Number(req.params.exp || 30);
    const expDate = ymdPlusDays(exp);
    const row = await get("SELECT password,limitip,quota,date_exp FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]);
    const pass = String(row?.password || username);
    const currentQuota = Number(row?.quota || 0);
    const bodyQuota = Number(req.body?.kuota);
    const nextQuota = Number.isFinite(bodyQuota) ? bodyQuota : currentQuota;
    const fromExp = String(row?.date_exp || '-');
    ensureLinuxUser(username, pass, expDate);
    await run("UPDATE account_sshs SET date_exp=?, quota=?, status='AKTIF' WHERE LOWER(username)=LOWER(?)", [expDate, nextQuota, username]);
    return ok(res, {
      username,
      from: fromExp,
      to: expDate,
      exp: expDate,
      quota: String(nextQuota),
      limitip: String(row?.limitip || 0),
      time: nowTime()
    });
  } catch (e) {
    return fail(res, 500, e.message);
  }
}
app.post('/vps/renewsshvpn/:username/:exp', renewSsh);
app.patch('/vps/renewsshvpn/:username/:exp', renewSsh);

app.patch('/vps/locksshvpn/:username', async (req, res) => {
  const username = String(req.params.username || '').trim();
  lockLinuxUser(username);
  await run("UPDATE account_sshs SET status='LOCK' WHERE LOWER(username)=LOWER(?)", [username]).catch(() => {});
  return ok(res, { username });
});

app.patch('/vps/unlocksshvpn/:username', async (req, res) => {
  const username = String(req.params.username || '').trim();
  unlockLinuxUser(username);
  await run("UPDATE account_sshs SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [username]).catch(() => {});
  return ok(res, { username });
});
app.patch('/vps/unlocksshvpn/:username/pw', async (req, res) => {
  const username = String(req.params.username || '').trim();
  unlockLinuxUser(username);
  await run("UPDATE account_sshs SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [username]).catch(() => {});
  return ok(res, { username });
});

async function createXray(protocol, username, expDays, quota, limitip, trial) {
  if (!username) throw new Error('username required');
  const expDate = ymdPlusDays(trial ? 1 : expDays);
  let data = null;
  if (protocol === 'vmess') {
    await ensureUsernameNotExists('account_vmesses', username);
    const uuid = crypto.randomUUID();
    await run("INSERT INTO account_vmesses(username,uuid,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, uuid, expDate, 'AKTIF', quota, limitip]);
    data = {
      hostname: DOMAIN, username, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vmess', stn: '/vmess', upgrade: '/upvmess' },
      serviceName: 'vmess-grpc',
      link: { tls: vmessLink(DOMAIN, uuid, true), none: vmessLink(DOMAIN, uuid, false), grpc: vmessLink(DOMAIN, uuid, true), uptls: vmessLink(DOMAIN, uuid, true), upntls: vmessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'vless') {
    await ensureUsernameNotExists('account_vlesses', username);
    const uuid = crypto.randomUUID();
    await run("INSERT INTO account_vlesses(username,uuid,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, uuid, expDate, 'AKTIF', quota, limitip]);
    data = {
      hostname: DOMAIN, username, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vless', stn: '/vless', upgrade: '/upvless' },
      serviceName: 'vless-grpc',
      link: { tls: vlessLink(DOMAIN, uuid, true), none: vlessLink(DOMAIN, uuid, false), grpc: vlessLink(DOMAIN, uuid, true), uptls: vlessLink(DOMAIN, uuid, true), upntls: vlessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'trojan') {
    await ensureUsernameNotExists('account_trojans', username);
    const pass = crypto.randomUUID();
    await run("INSERT INTO account_trojans(username,password,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, pass, expDate, 'AKTIF', quota, limitip]);
    data = {
      hostname: DOMAIN, username, password: pass, uuid: pass, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/trojan', stn: '/trojan', upgrade: '/uptrojan' },
      serviceName: 'trojan-grpc',
      link: { tls: trojanLink(DOMAIN, pass, true), none: trojanLink(DOMAIN, pass, false), grpc: trojanLink(DOMAIN, pass, true), uptls: trojanLink(DOMAIN, pass, true), upntls: trojanLink(DOMAIN, pass, false) }
    };
  }
  await renderAndReloadXray();
  return data;
}

app.post('/vps/vmessall', async (req, res) => {
  try {
    const data = await createXray('vmess', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialvmessall', async (req, res) => {
  try {
    const data = await createXray('vmess', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/vlessall', async (req, res) => {
  try {
    const data = await createXray('vless', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialvlessall', async (req, res) => {
  try {
    const data = await createXray('vless', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trojanall', async (req, res) => {
  try {
    const data = await createXray('trojan', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialtrojanall', async (req, res) => {
  try {
    const data = await createXray('trojan', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});

async function renewXray(table, username, exp, body) {
  const row = await get(`SELECT date_exp,quota,limitip FROM ${table} WHERE LOWER(username)=LOWER(?)`, [username]);
  const currentQuota = Number(row?.quota || 0);
  const bodyQuota = Number(body?.kuota);
  const nextQuota = Number.isFinite(bodyQuota) ? bodyQuota : currentQuota;
  const expDate = ymdPlusDays(exp);
  await run(`UPDATE ${table} SET date_exp=?, quota=?, status='AKTIF' WHERE LOWER(username)=LOWER(?)`, [expDate, nextQuota, username]);
  await renderAndReloadXray();
  return {
    username,
    from: String(row?.date_exp || '-'),
    to: expDate,
    exp: expDate,
    quota: String(nextQuota),
    limitip: String(row?.limitip || 0),
    time: nowTime()
  };
}
async function delXray(table, username) {
  await run(`DELETE FROM ${table} WHERE LOWER(username)=LOWER(?)`, [username]);
  await renderAndReloadXray();
  return { username };
}
async function setStatusXray(table, username, status) {
  await run(`UPDATE ${table} SET status=? WHERE LOWER(username)=LOWER(?)`, [status, username]);
  await renderAndReloadXray();
  return { username };
}

const renewXrayHandler = (table) => async (req, res) => {
  try {
    return ok(res, await renewXray(table, String(req.params.username || '').trim(), Number(req.params.exp || 30), req.body));
  } catch (e) {
    return fail(res, 500, e.message);
  }
};
app.post('/vps/renewvmess/:username/:exp', renewXrayHandler('account_vmesses'));
app.patch('/vps/renewvmess/:username/:exp', renewXrayHandler('account_vmesses'));
app.post('/vps/renewvless/:username/:exp', renewXrayHandler('account_vlesses'));
app.patch('/vps/renewvless/:username/:exp', renewXrayHandler('account_vlesses'));
app.post('/vps/renewtrojan/:username/:exp', renewXrayHandler('account_trojans'));
app.patch('/vps/renewtrojan/:username/:exp', renewXrayHandler('account_trojans'));

app.delete('/vps/deletevmess/:username', async (req, res) => ok(res, await delXray('account_vmesses', String(req.params.username || '').trim())));
app.delete('/vps/deletevless/:username', async (req, res) => ok(res, await delXray('account_vlesses', String(req.params.username || '').trim())));
app.delete('/vps/deletetrojan/:username', async (req, res) => ok(res, await delXray('account_trojans', String(req.params.username || '').trim())));

app.patch('/vps/lockvmess/:username', async (req, res) => ok(res, await setStatusXray('account_vmesses', String(req.params.username || '').trim(), 'LOCK')));
app.patch('/vps/lockvless/:username', async (req, res) => ok(res, await setStatusXray('account_vlesses', String(req.params.username || '').trim(), 'LOCK')));
app.patch('/vps/locktrojan/:username', async (req, res) => ok(res, await setStatusXray('account_trojans', String(req.params.username || '').trim(), 'LOCK')));
app.patch('/vps/unlockvmess/:username', async (req, res) => ok(res, await setStatusXray('account_vmesses', String(req.params.username || '').trim(), 'AKTIF')));
app.patch('/vps/unlockvless/:username', async (req, res) => ok(res, await setStatusXray('account_vlesses', String(req.params.username || '').trim(), 'AKTIF')));
app.patch('/vps/unlocktrojan/:username', async (req, res) => ok(res, await setStatusXray('account_trojans', String(req.params.username || '').trim(), 'AKTIF')));

app.use((err, _req, res, _next) => {
  return fail(res, 500, err?.message || 'internal error');
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`sc-1forcr-api on 127.0.0.1:${PORT}`);
});
EOF

  cat > "${APP_DIR}/ssh-ws.js" <<'EOF'
const net = require('net');
try { require('dotenv').config(); } catch (_) {}

const PORT = Number(process.env.SSH_WS_PORT || 2082);
const SSH_HOST = process.env.SSH_WS_TARGET_HOST || '127.0.0.1';
const SSH_PORT = Number(process.env.SSH_WS_TARGET_PORT || 109);
const HTTP_BACKEND_HOST = process.env.SSH_HTTP_BACKEND_HOST || '127.0.0.1';
const HTTP_BACKEND_PORT = Number(process.env.SSH_HTTP_BACKEND_PORT || 80);

function firstLine(head) {
  const i = head.indexOf('\r\n');
  return (i >= 0 ? head.slice(0, i) : head).trim();
}

const server = net.createServer((client) => {
  let upstream = null;
  let closed = false;
  let stage = 'first';
  let stash = Buffer.alloc(0);

  const closeAll = () => {
    if (closed) return;
    closed = true;
    try { client.destroy(); } catch (_) {}
    try { if (upstream) upstream.destroy(); } catch (_) {}
  };

  const startPipeTo = (host, port, firstPayload, firstResponse) => {
    upstream = net.connect({ host, port }, () => {
      if (firstResponse) client.write(firstResponse);
      if (firstPayload && firstPayload.length > 0) upstream.write(firstPayload);
      client.pipe(upstream);
      upstream.pipe(client);
      stage = 'tunnel';
    });
    upstream.on('error', closeAll);
    upstream.on('close', closeAll);
    upstream.setTimeout(0);
  };

  const startRawSshTunnel = (firstPayload) => {
    startPipeTo(SSH_HOST, SSH_PORT, firstPayload, null);
  };

  const startWsSshTunnel = (leftover) => {
    startPipeTo(
      SSH_HOST,
      SSH_PORT,
      leftover,
      'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n'
    );
  };

  const startHttpProxy = (firstPayload) => {
    startPipeTo(HTTP_BACKEND_HOST, HTTP_BACKEND_PORT, firstPayload, null);
  };

  const handleHttpLike = (chunk) => {
    stash = Buffer.concat([stash, chunk]);
    const idx = stash.indexOf('\r\n\r\n');
    if (idx < 0) {
      if (stash.length > 65536) {
        // Payload terlalu random, fallback sebagai raw SSH.
        startRawSshTunnel(stash);
        stash = Buffer.alloc(0);
      }
      return;
    }

    const headRaw = stash.slice(0, idx).toString('utf8');
    const head = headRaw.toLowerCase();
    const line = firstLine(headRaw).toLowerCase();
    const parts = line.split(/\s+/);
    const method = parts[0] || '';
    const path = parts[1] || '';
    const rest = stash.slice(idx + 4);
    stash = Buffer.alloc(0);

    if (stage === 'first' && method === 'connect') {
      client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      stage = 'wait-upgrade';
      if (rest.length > 0) handleHttpLike(rest);
      return;
    }

    if (head.includes('upgrade: websocket') || (head.includes('upgrade:') && head.includes('host:'))) {
      startWsSshTunnel(rest);
      return;
    }

    if (path.startsWith('/vps/') || path.startsWith('/vmess') || path.startsWith('/vless') || path.startsWith('/trojan')) {
      const req = Buffer.concat([Buffer.from(headRaw + '\r\n\r\n', 'utf8'), rest]);
      startHttpProxy(req);
      return;
    }

    if (method && (method.startsWith('get') || method.startsWith('post') || method.startsWith('head') || method.startsWith('options'))) {
      client.write('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n');
      stage = 'wait-upgrade';
      if (rest.length > 0) handleHttpLike(rest);
      return;
    }

    // Fallback: raw SSH.
    startRawSshTunnel(Buffer.concat([Buffer.from(headRaw + '\r\n\r\n', 'utf8'), rest]));
  };

  client.on('data', (chunk) => {
    if (stage === 'tunnel') return;

    if ((stage === 'first' || stage === 'wait-upgrade') && chunk.length >= 4 && chunk.slice(0, 4).toString() === 'SSH-') {
      startRawSshTunnel(chunk);
      return;
    }

    handleHttpLike(chunk);
  });

  client.on('error', closeAll);
  client.on('close', closeAll);
  client.setTimeout(0);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`ssh-ws mux on 127.0.0.1:${PORT} -> ssh ${SSH_HOST}:${SSH_PORT}, http ${HTTP_BACKEND_HOST}:${HTTP_BACKEND_PORT}`);
});
EOF

  cd "${APP_DIR}"
  export npm_config_build_from_source=true
  export npm_config_fallback_to_build=true
  export npm_config_update_binary=false

  local need_npm_install="0"
  if [[ ! -d node_modules ]]; then
    need_npm_install="1"
    log "node_modules belum ada, install dependency..."
  elif ! node -e "require('sqlite3'); require('express'); require('dotenv'); require('ws')" >/dev/null 2>&1; then
    need_npm_install="1"
    log "Dependency Node terdeteksi rusak/kurang, reinstall dependency..."
  else
    log "Dependency Node sudah OK, skip reinstall sqlite."
  fi

  if [[ "${need_npm_install}" == "1" ]]; then
    if ! npm install --omit=dev --foreground-scripts >/tmp/sc-1forcr-npm-install.log 2>&1; then
      log "Install npm dependency gagal. Cek log: /tmp/sc-1forcr-npm-install.log"
      tail -n 80 /tmp/sc-1forcr-npm-install.log || true
      exit 1
    fi
  fi

  node -e "require('sqlite3'); console.log('sqlite3 load ok')"
}

write_go_mux_files() {
  log "Menulis Go SSH mux..."
  mkdir -p "${APP_DIR}/go"
  cat > "${APP_DIR}/go/ssh_mux.go" <<'EOF'
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

func envOr(key, fallback string) string {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	return v
}

func envInt(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

func writeAll(conn net.Conn, data []byte) error {
	remaining := data
	for len(remaining) > 0 {
		n, err := conn.Write(remaining)
		if err != nil {
			return err
		}
		remaining = remaining[n:]
	}
	return nil
}

func tunnelBoth(a, b net.Conn) {
	defer a.Close()
	defer b.Close()
	done := make(chan struct{}, 2)
	go func() {
		_, _ = io.Copy(a, b)
		done <- struct{}{}
	}()
	go func() {
		_, _ = io.Copy(b, a)
		done <- struct{}{}
	}()
	<-done
}

func flushReaderBufferedTo(reader *bufio.Reader, dst net.Conn) error {
	n := reader.Buffered()
	if n <= 0 {
		return nil
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(reader, buf); err != nil {
		return err
	}
	return writeAll(dst, buf)
}

func handleConn(client net.Conn, sshHost string, sshPort int, httpHost string, httpPort int) {
	defer client.Close()
	reader := bufio.NewReaderSize(client, 64*1024)

	peek, err := reader.Peek(4)
	if err == nil && string(peek) == "SSH-" {
		sshUp, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", sshHost, sshPort), 10*time.Second)
		if err != nil {
			return
		}
		if err := flushReaderBufferedTo(reader, sshUp); err != nil {
			_ = sshUp.Close()
			return
		}
		tunnelBoth(client, sshUp)
		return
	}

	var raw bytes.Buffer
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			return
		}
		raw.Write(line)
		if raw.Len() > 128*1024 {
			return
		}
		if bytes.HasSuffix(raw.Bytes(), []byte("\r\n\r\n")) {
			break
		}
	}

	header := strings.ToLower(raw.String())
	first := strings.ToLower(strings.TrimSpace(strings.SplitN(raw.String(), "\r\n", 2)[0]))

	// CONNECT mode from payload apps.
	if strings.HasPrefix(first, "connect ") {
		_, _ = client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
		raw.Reset()

		// CONNECT clients may still send HTTP payload lines before SSH banner.
		// Discard those lines until we see SSH- and then start raw SSH tunnel.
		_ = client.SetReadDeadline(time.Now().Add(5 * time.Second))
		for i := 0; i < 64; i++ {
			nextPeek, nextErr := reader.Peek(4)
			if nextErr != nil {
				_ = client.SetReadDeadline(time.Time{})
				return
			}
			if string(nextPeek) == "SSH-" {
				_ = client.SetReadDeadline(time.Time{})
				sshUp, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", sshHost, sshPort), 10*time.Second)
				if err != nil {
					return
				}
				if err := flushReaderBufferedTo(reader, sshUp); err != nil {
					_ = sshUp.Close()
					return
				}
				tunnelBoth(client, sshUp)
				return
			}
			// Drop one line of HTTP payload and keep scanning.
			if _, err := reader.ReadBytes('\n'); err != nil {
				_ = client.SetReadDeadline(time.Time{})
				return
			}
		}
		_ = client.SetReadDeadline(time.Time{})
		return
	}

	if strings.Contains(header, "upgrade: websocket") || strings.Contains(header, "upgrade:") {
		sshUp, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", sshHost, sshPort), 10*time.Second)
		if err != nil {
			return
		}
		_, _ = client.Write([]byte("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n"))
		if err := flushReaderBufferedTo(reader, sshUp); err != nil {
			_ = sshUp.Close()
			return
		}
		tunnelBoth(client, sshUp)
		return
	}

	// keep API and xray ws paths reachable through the same mux.
	if strings.Contains(first, " /vps/") || strings.Contains(first, " /vmess") || strings.Contains(first, " /vless") || strings.Contains(first, " /trojan") {
		httpUp, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", httpHost, httpPort), 10*time.Second)
		if err != nil {
			return
		}
		if err := writeAll(httpUp, raw.Bytes()); err != nil {
			_ = httpUp.Close()
			return
		}
		if err := flushReaderBufferedTo(reader, httpUp); err != nil {
			_ = httpUp.Close()
			return
		}
		tunnelBoth(client, httpUp)
		return
	}

	// fallback to raw SSH.
	sshUp, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", sshHost, sshPort), 10*time.Second)
	if err != nil {
		return
	}
	if err := writeAll(sshUp, raw.Bytes()); err != nil {
		_ = sshUp.Close()
		return
	}
	if err := flushReaderBufferedTo(reader, sshUp); err != nil {
		_ = sshUp.Close()
		return
	}
	tunnelBoth(client, sshUp)
}

func main() {
	port := envInt("SSH_WS_PORT", 2082)
	sshHost := envOr("SSH_WS_TARGET_HOST", "127.0.0.1")
	sshPort := envInt("SSH_WS_TARGET_PORT", 109)
	httpHost := envOr("SSH_HTTP_BACKEND_HOST", "127.0.0.1")
	httpPort := envInt("SSH_HTTP_BACKEND_PORT", 80)

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		fmt.Printf("listen error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("ssh-ws go mux on 127.0.0.1:%d -> ssh %s:%d, http %s:%d\n", port, sshHost, sshPort, httpHost, httpPort)

	for {
		conn, err := ln.Accept()
		if err != nil {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		go handleConn(conn, sshHost, sshPort, httpHost, httpPort)
	}
}
EOF
}

build_go_files() {
  log "Build Go binaries..."
  mkdir -p "${APP_DIR}/bin"
  (
    cd "${APP_DIR}/go"
    GO111MODULE=off go build -ldflags "-s -w" -o "${APP_DIR}/bin/ssh-mux" ssh_mux.go
  )
  chmod +x "${APP_DIR}/bin/ssh-mux"
}

write_iplimit_checker() {
  log "Menulis checker limit IP otomatis..."
  cat > "${APP_DIR}/iplimit-checker.js" <<'EOF'
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();
const { execFileSync } = require('child_process');

const DB_PATH = process.env.DB_PATH || '/usr/sbin/potatonc/potato.db';
const ZIVPN_CONFIG = process.env.ZIVPN_CONFIG || '/etc/zivpn/config.json';
const ZIVPN_SERVICE = process.env.ZIVPN_SERVICE || 'zivpn';
const LOCK_SECONDS = 15 * 60;

const db = new sqlite3.Database(DB_PATH);

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(err) {
      if (err) return reject(err);
      resolve(this);
    });
  });
}
function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
  });
}
function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => (err ? reject(err) : resolve(row)));
  });
}
function safeExec(cmd, args) {
  try {
    execFileSync(cmd, args, { stdio: 'ignore' });
    return true;
  } catch (_) {
    return false;
  }
}

function addIpToUserMap(map, username, ip) {
  const u = String(username || '').trim().toLowerCase();
  const v = String(ip || '').trim();
  if (!u || !v || u === 'root') return;
  if (!map.has(u)) map.set(u, new Set());
  map.get(u).add(v);
}

function extractIp(raw) {
  let v = String(raw || '').trim();
  if (!v) return '';
  v = v.replace(/^\[/, '').replace(/\]$/, '');
  v = v.replace(/:[0-9]+$/, '');
  return v;
}

function parseSshAndUdpIpMap() {
  const map = new Map();

  // SSH/Dropbear realtime: established sockets + sshd PID owner -> username.
  const pidIpMap = new Map();
  let ssOut = '';
  try {
    ssOut = execFileSync('ss', ['-Htnp', 'state', 'established'], { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  } catch (_) {}
  for (const lineRaw of String(ssOut || '').split('\n')) {
    const line = String(lineRaw || '').trim();
    if (!line) continue;
    const cols = line.split(/\s+/);
    const local = String(cols[3] || '');
    const remote = String(cols[4] || '');
    const lport = (local.match(/:([0-9]+)$/) || [])[1] || '';
    if (lport !== '22' && lport !== '109' && lport !== '143') continue;
    const ip = extractIp(remote);
    if (!ip) continue;
    const pids = Array.from(line.matchAll(/pid=(\d+)/g)).map((m) => Number(m[1])).filter((n) => Number.isInteger(n) && n > 0);
    for (const pid of new Set(pids)) {
      if (!pidIpMap.has(pid)) pidIpMap.set(pid, new Set());
      pidIpMap.get(pid).add(ip);
    }
  }

  if (pidIpMap.size > 0) {
    let psOut = '';
    const pids = Array.from(pidIpMap.keys()).join(',');
    try {
      psOut = execFileSync('ps', ['-o', 'pid=,args=', '-p', pids], { encoding: 'utf8' });
    } catch (_) {}
    for (const lineRaw of String(psOut || '').split('\n')) {
      const m = String(lineRaw || '').match(/^\s*(\d+)\s+(.*)$/);
      if (!m) continue;
      const pid = Number(m[1]);
      const args = String(m[2] || '').trim();
      if (!args.startsWith('sshd:')) continue;
      let user = args.replace(/^sshd:\s*/, '').split(/\s+/)[0] || '';
      user = user.replace(/@.*$/, '').replace(/\[.*$/, '');
      for (const ip of (pidIpMap.get(pid) || [])) addIpToUserMap(map, user, ip);
    }
  }

  // Fallback: who entries (TTY login).
  let out = '';
  try {
    out = execFileSync('who', [], { encoding: 'utf8' });
  } catch (_) {}
  for (const line of String(out || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const parts = t.split(/\s+/);
    const user = String(parts[0] || '').trim();
    const hostMatch = t.match(/\(([^\)]+)\)/);
    const host = extractIp(hostMatch?.[1] || '');
    addIpToUserMap(map, user, host);
  }

  // UDP Custom realtime (short window) from journal.
  let jOut = '';
  try {
    jOut = execFileSync(
      'journalctl',
      ['-u', 'sc-1forcr-udpcustom', '-u', 'udp-custom', '--since', '-20 min', '-n', '300', '--no-pager'],
      { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }
    );
  } catch (_) {}
  for (const lineRaw of String(jOut || '').split('\n')) {
    const line = String(lineRaw || '');
    let user = '';
    let src = '';
    let m = line.match(/\[src:([^\]]+)\]\s+\[user:([^\]]+)\]\s+Client connected/i);
    if (m) {
      src = m[1];
      user = m[2];
    } else {
      m = line.match(/user[=: ]([^\s,]+).*src[=: ]([^\s,]+)/i);
      if (m) {
        user = m[1];
        src = m[2];
      } else {
        m = line.match(/src[=: ]([^\s,]+).*user[=: ]([^\s,]+)/i);
        if (m) {
          src = m[1];
          user = m[2];
        }
      }
    }
    addIpToUserMap(map, user, extractIp(src));
  }
  return map;
}

function parseXrayRecentIpMap() {
  const map = new Map();
  const path = '/var/log/xray/access.log';
  if (!fs.existsSync(path)) return map;
  let tailOut = '';
  try {
    tailOut = execFileSync('tail', ['-n', '5000', path], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  } catch (_) {
    return map;
  }
  const lines = String(tailOut || '').split('\n');
  for (const lineRaw of lines) {
    const line = String(lineRaw || '').trim();
    if (!line) continue;
    const emailJson = line.match(/"email":"([^"]+)"/);
    const emailTxt = line.match(/\bemail:\s*([^\s]+)/i);
    const email = String(emailJson?.[1] || emailTxt?.[1] || '').trim().toLowerCase();
    if (!email) continue;
    const srcJson = line.match(/"source":"([^"]+)"/);
    const srcTxt = line.match(/\bfrom\s+([0-9a-fA-F\.:]+)/i);
    const src = String(srcJson?.[1] || srcTxt?.[1] || '').trim();
    const ip = extractIp(src);
    if (!ip) continue;
    if (!map.has(email)) map.set(email, new Set());
    map.get(email).add(ip);
  }
  return map;
}

function removeZivpnUser(username) {
  try {
    if (!fs.existsSync(ZIVPN_CONFIG)) return false;
    const root = JSON.parse(fs.readFileSync(ZIVPN_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') return false;
    if (!Array.isArray(root.auth.config)) return false;
    const before = root.auth.config.length;
    root.auth.config = root.auth.config.filter((u) => String(u || '').trim().toLowerCase() !== String(username || '').trim().toLowerCase());
    const changed = root.auth.config.length !== before;
    if (changed) fs.writeFileSync(ZIVPN_CONFIG, JSON.stringify(root, null, 2));
    return changed;
  } catch (_) {
    return false;
  }
}

function addZivpnUser(username) {
  try {
    let root = { auth: { mode: 'passwords', config: [] } };
    if (fs.existsSync(ZIVPN_CONFIG)) root = JSON.parse(fs.readFileSync(ZIVPN_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') root.auth = {};
    if (!Array.isArray(root.auth.config)) root.auth.config = [];
    const key = String(username || '').trim().toLowerCase();
    const set = new Set(root.auth.config.map((u) => String(u || '').trim().toLowerCase()).filter(Boolean));
    set.add(key);
    root.auth.config = Array.from(set);
    fs.writeFileSync(ZIVPN_CONFIG, JSON.stringify(root, null, 2));
    return true;
  } catch (_) {
    return false;
  }
}

function restartService(service) {
  if (!service) return;
  if (!safeExec('systemctl', ['restart', service])) safeExec('service', [service, 'restart']);
}

async function ensureTables() {
  await run(`CREATE TABLE IF NOT EXISTS temp_ip_locks (
    account_type TEXT NOT NULL,
    username TEXT NOT NULL,
    locked_until INTEGER NOT NULL,
    zivpn_removed INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s','now')),
    PRIMARY KEY (account_type, username)
  )`);
}

async function unlockExpired(nowTs) {
  const rows = await all("SELECT account_type, username, zivpn_removed FROM temp_ip_locks WHERE locked_until <= ?", [nowTs]);
  if (rows.length === 0) return { xrayChanged: false, zivpnChanged: false };

  let xrayChanged = false;
  let zivpnChanged = false;
  for (const row of rows) {
    const t = String(row.account_type || '');
    const u = String(row.username || '');
    if (t === 'ssh') {
      safeExec('passwd', ['-u', u]);
      await run("UPDATE account_sshs SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [u]).catch(() => {});
      if (Number(row.zivpn_removed || 0) === 1) {
        if (addZivpnUser(u)) zivpnChanged = true;
      }
    } else if (t === 'vmess') {
      await run("UPDATE account_vmesses SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [u]).catch(() => {});
      xrayChanged = true;
    } else if (t === 'vless') {
      await run("UPDATE account_vlesses SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [u]).catch(() => {});
      xrayChanged = true;
    } else if (t === 'trojan') {
      await run("UPDATE account_trojans SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [u]).catch(() => {});
      xrayChanged = true;
    }
    await run("DELETE FROM temp_ip_locks WHERE account_type=? AND username=?", [t, u]).catch(() => {});
  }
  return { xrayChanged, zivpnChanged };
}

async function lockIfExceeded(nowTs) {
  const sshMap = parseSshAndUdpIpMap();
  const xrayMap = parseXrayRecentIpMap();
  let xrayChanged = false;
  let zivpnChanged = false;

  const sshRows = await all("SELECT username, limitip FROM account_sshs WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' AND CAST(COALESCE(limitip,0) AS INTEGER) > 0");
  for (const r of sshRows) {
    const user = String(r.username || '').trim();
    const userKey = user.toLowerCase();
    const lim = Number(r.limitip || 0);
    const cnt = sshMap.has(userKey) ? sshMap.get(userKey).size : 0;
    if (cnt <= lim) continue;
    const exists = await get("SELECT 1 AS ok FROM temp_ip_locks WHERE account_type='ssh' AND username=?", [user]);
    if (exists) continue;
    safeExec('passwd', ['-l', user]);
    const removed = removeZivpnUser(user) ? 1 : 0;
    if (removed) zivpnChanged = true;
    await run("UPDATE account_sshs SET status='LOCK_TMP' WHERE LOWER(username)=LOWER(?)", [user]).catch(() => {});
    await run("INSERT OR REPLACE INTO temp_ip_locks(account_type, username, locked_until, zivpn_removed) VALUES('ssh', ?, ?, ?)", [user, nowTs + LOCK_SECONDS, removed]).catch(() => {});
  }

  const scan = [
    { type: 'vmess', table: 'account_vmesses' },
    { type: 'vless', table: 'account_vlesses' },
    { type: 'trojan', table: 'account_trojans' }
  ];
  for (const item of scan) {
    const rows = await all(`SELECT username, limitip FROM ${item.table} WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' AND CAST(COALESCE(limitip,0) AS INTEGER) > 0`);
    for (const r of rows) {
      const user = String(r.username || '').trim();
      const userKey = user.toLowerCase();
      const lim = Number(r.limitip || 0);
      const cnt = xrayMap.has(userKey) ? xrayMap.get(userKey).size : 0;
      if (cnt <= lim) continue;
      const exists = await get("SELECT 1 AS ok FROM temp_ip_locks WHERE account_type=? AND username=?", [item.type, user]);
      if (exists) continue;
      await run(`UPDATE ${item.table} SET status='LOCK_TMP' WHERE LOWER(username)=LOWER(?)`, [user]).catch(() => {});
      await run("INSERT OR REPLACE INTO temp_ip_locks(account_type, username, locked_until, zivpn_removed) VALUES(?, ?, ?, 0)", [item.type, user, nowTs + LOCK_SECONDS]).catch(() => {});
      xrayChanged = true;
    }
  }
  return { xrayChanged, zivpnChanged };
}

async function rebuildXrayFromDb() {
  const vmessRows = await all("SELECT username, uuid FROM account_vmesses WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");
  const vlessRows = await all("SELECT username, uuid FROM account_vlesses WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");
  const trojanRows = await all("SELECT username, password FROM account_trojans WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF'");

  const cfg = {
    log: {
      access: '/var/log/xray/access.log',
      error: '/var/log/xray/error.log',
      loglevel: 'warning'
    },
    inbounds: [
      {
        port: 10001, listen: '127.0.0.1', protocol: 'vmess',
        settings: { clients: vmessRows.map((r) => ({ id: String(r.uuid || ''), alterId: 0, email: String(r.username || '') })) },
        streamSettings: { network: 'ws', wsSettings: { path: '/vmess' } }
      },
      {
        port: 10002, listen: '127.0.0.1', protocol: 'vless',
        settings: { clients: vlessRows.map((r) => ({ id: String(r.uuid || ''), email: String(r.username || '') })), decryption: 'none' },
        streamSettings: { network: 'ws', security: 'none', wsSettings: { path: '/vless' } }
      },
      {
        port: 10003, listen: '127.0.0.1', protocol: 'trojan',
        settings: { clients: trojanRows.map((r) => ({ password: String(r.password || ''), email: String(r.username || '') })) },
        streamSettings: { network: 'ws', security: 'none', wsSettings: { path: '/trojan' } }
      }
    ],
    outbounds: [{ protocol: 'freedom', tag: 'direct' }]
  };
  fs.mkdirSync('/usr/local/etc/xray', { recursive: true });
  fs.writeFileSync('/usr/local/etc/xray/config.json', JSON.stringify(cfg, null, 2));
  restartService('xray');
}

async function main() {
  const now = Math.floor(Date.now() / 1000);
  await ensureTables();
  const u = await unlockExpired(now);
  const l = await lockIfExceeded(now);

  if (u.xrayChanged || l.xrayChanged) await rebuildXrayFromDb();
  if (u.zivpnChanged || l.zivpnChanged) restartService(ZIVPN_SERVICE);
  db.close();
}

main().catch((e) => {
  try { db.close(); } catch (_) {}
  console.error('[iplimit-checker] error:', e?.message || e);
  process.exit(1);
});
EOF
}

setup_services() {
  log "Setup service sc-1forcr-api..."
  cat > /etc/systemd/system/sc-1forcr-api.service <<EOF
[Unit]
Description=SC 1FORCR API
After=network.target xray.service nginx.service

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Environment=NODE_ENV=production
Environment=UV_THREADPOOL_SIZE=2
ExecStart=/usr/bin/node ${APP_DIR}/api.js
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
TasksMax=256
MemoryMax=350M

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/sc-1forcr-sshws.service <<EOF
[Unit]
Description=SC 1FORCR SSH WebSocket Bridge
After=network.target ssh.service dropbear.service

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/bin/ssh-mux
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
TasksMax=256
MemoryMax=128M

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sc-1forcr-api
  systemctl restart sc-1forcr-api
  systemctl enable sc-1forcr-sshws
  systemctl restart sc-1forcr-sshws

  cat > /etc/systemd/system/sc-1forcr-iplimit.service <<EOF
[Unit]
Description=SC 1FORCR IP Limit Checker
After=network.target sc-1forcr-api.service

[Service]
Type=oneshot
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node ${APP_DIR}/iplimit-checker.js
NoNewPrivileges=true
PrivateTmp=true
EOF

  cat > /etc/systemd/system/sc-1forcr-iplimit.timer <<'EOF'
[Unit]
Description=Run SC 1FORCR IP Limit Checker every 15 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Unit=sc-1forcr-iplimit.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now sc-1forcr-iplimit.timer

  systemctl enable ssh || true
  systemctl restart ssh || true
  systemctl enable dropbear || true
  systemctl restart dropbear || true
}

write_cli_menu() {
  log "Menulis CLI menu..."

  cat > /etc/sc-1forcr.env <<EOF
SCRIPT_VERSION=${SCRIPT_VERSION}
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
API_PORT=${API_PORT}
AUTH_TOKEN=${API_AUTH_TOKEN}
UPDATE_SCRIPT_URL=${UPDATE_SCRIPT_URL}
DB_PATH=${DB_PATH}
ZIVPN_SERVICE=${ZIVPN_SERVICE_NAME}
UDPCUSTOM_SERVICE=${UDPCUSTOM_SERVICE_NAME}
DROPBEAR_PORT=${DROPBEAR_PORT}
DROPBEAR_ALT_PORT=${DROPBEAR_ALT_PORT}
EOF
  chmod 600 /etc/sc-1forcr.env

  cat > /usr/local/sbin/menu-sc-1forcr <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Jalankan sebagai root."
  exit 1
fi

source /etc/sc-1forcr.env
API_BASE="http://127.0.0.1:${API_PORT}/vps"

api_call() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "${data}" ]]; then
    curl -sS -X "${method}" "${API_BASE}${path}" \
      -H "Authorization: ${AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${data}"
  else
    curl -sS -X "${method}" "${API_BASE}${path}" \
      -H "Authorization: ${AUTH_TOKEN}"
  fi
}

cancelled() {
  echo
  echo "Dibatalkan. Kembali ke menu sebelumnya."
}

prompt_input() {
  local var_name="$1" prompt="$2"
  if ! read -rp "${prompt}" "${var_name}" </dev/tty; then
    cancelled
    return 130
  fi
  return 0
}

pick_type() {
  echo "Pilih tipe:" >&2
  echo "1) ssh" >&2
  echo "2) vmess" >&2
  echo "3) vless" >&2
  echo "4) trojan" >&2
  echo "5) zivpn" >&2
  if ! prompt_input t "Input [1-5]: "; then
    echo ""
    return 0
  fi
  case "$t" in
    1) echo "ssh" ;;
    2) echo "vmess" ;;
    3) echo "vless" ;;
    4) echo "trojan" ;;
    5) echo "zivpn" ;;
    *) echo "" ;;
  esac
}

endpoint_create() {
  case "$1" in
    ssh|zivpn) echo "/sshvpn" ;;
    vmess) echo "/vmessall" ;;
    vless) echo "/vlessall" ;;
    trojan) echo "/trojanall" ;;
    *) echo "" ;;
  esac
}
endpoint_renew() {
  case "$1" in
    ssh|zivpn) echo "/renewsshvpn" ;;
    vmess) echo "/renewvmess" ;;
    vless) echo "/renewvless" ;;
    trojan) echo "/renewtrojan" ;;
    *) echo "" ;;
  esac
}
endpoint_delete() {
  case "$1" in
    ssh|zivpn) echo "/deletesshvpn" ;;
    vmess) echo "/deletevmess" ;;
    vless) echo "/deletevless" ;;
    trojan) echo "/deletetrojan" ;;
    *) echo "" ;;
  esac
}

print_created_account() {
  local type="$1" raw="$2"
  local code
  code="$(echo "${raw}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
  if [[ "${code}" != "200" ]]; then
    echo "${raw}" | jq . 2>/dev/null || echo "${raw}"
    return
  fi

  case "${type}" in
    ssh)
      local host user pass exp lim
      host="$(echo "${raw}" | jq -r '.data.hostname // "-"' )"
      user="$(echo "${raw}" | jq -r '.data.username // "-"' )"
      pass="$(echo "${raw}" | jq -r '.data.password // "-"' )"
      exp="$(echo "${raw}" | jq -r '.data.exp // .data.expired // "-"' )"
      lim="$(echo "${raw}" | jq -r '.data.limitip // "0"' )"
      cat <<EOT_SSH
=============================
 SSH ACCOUNT CREATED
=============================

[ SSH PREMIUM DETAILS ]
-----------------------------
SSH WS       : ${host}:80@${user}:${pass}
SSH SSL      : ${host}:443@${user}:${pass}
DNS SELOW    : ${host}:5300@${user}:${pass}

[ HOST INFORMATION ]
-----------------------------
Hostname     : ${host}
Username     : ${user}
Password     : ${pass}
Expiry Date  : ${exp}
IP Limit     : ${lim}
EOT_SSH
      ;;
    zivpn)
      local host pass exp lim
      host="$(echo "${raw}" | jq -r '.data.hostname // "-"' )"
      pass="$(echo "${raw}" | jq -r '.data.password // .data.username // "-"' )"
      exp="$(echo "${raw}" | jq -r '.data.exp // .data.expired // "-"' )"
      lim="$(echo "${raw}" | jq -r '.data.limitip // "0"' )"
      cat <<EOT_ZIVPN
=============================
 ZIVPN SSH ACCOUNT
=============================
udp password : ${pass}
Hostname     : ${host}
Expired      : ${exp}
IP Limit     : ${lim} device
EOT_ZIVPN
      ;;
    vmess|vless|trojan)
      local host user exp tls none linktls linknone
      host="$(echo "${raw}" | jq -r '.data.hostname // "-"' )"
      user="$(echo "${raw}" | jq -r '.data.username // "-"' )"
      exp="$(echo "${raw}" | jq -r '.data.exp // .data.expired // "-"' )"
      tls="$(echo "${raw}" | jq -r '.data.port.tls // "443"' )"
      none="$(echo "${raw}" | jq -r '.data.port.none // "80"' )"
      linktls="$(echo "${raw}" | jq -r '.data.link.tls // "-"' )"
      linknone="$(echo "${raw}" | jq -r '.data.link.none // "-"' )"
      cat <<EOT_XRAY
=============================
 ${type^^} ACCOUNT CREATED
=============================
Hostname     : ${host}
Username     : ${user}
Expired      : ${exp}
TLS Port     : ${tls}
NON TLS Port : ${none}

Link TLS:
${linktls}

Link NON TLS:
${linknone}
EOT_XRAY
      ;;
    *)
      echo "${raw}" | jq . 2>/dev/null || echo "${raw}"
      ;;
  esac
}

create_account() {
  local type ep username password exp limitip quota
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_create "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint create tidak ada."; return; }

  prompt_input username "Username: " || return
  prompt_input exp "Expired (hari) [30]: " || return
  exp="${exp:-30}"
  prompt_input limitip "Limit IP [2]: " || return
  limitip="${limitip:-2}"
  prompt_input quota "Quota GB [0]: " || return
  quota="${quota:-0}"
  if [[ "$type" == "ssh" || "$type" == "zivpn" ]]; then
    prompt_input password "Password [default=username]: " || return
    password="${password:-$username}"
  else
    password=""
  fi

  local payload
  if [[ -n "$password" ]]; then
    payload="$(jq -nc --arg u "$username" --arg p "$password" --argjson e "$exp" --arg l "$limitip" --arg q "$quota" \
      '{username:$u,password:$p,expired:$e,limitip:$l,kuota:$q}')"
  else
    payload="$(jq -nc --arg u "$username" --argjson e "$exp" --arg l "$limitip" --arg q "$quota" \
      '{username:$u,expired:$e,limitip:$l,kuota:$q}')"
  fi
  local resp
  resp="$(api_call "POST" "$ep" "$payload")"
  print_created_account "$type" "${resp}"
}

account_table_by_type() {
  case "$1" in
    ssh|zivpn) echo "account_sshs" ;;
    vmess) echo "account_vmesses" ;;
    vless) echo "account_vlesses" ;;
    trojan) echo "account_trojans" ;;
    *) echo "" ;;
  esac
}

pick_existing_username() {
  local type="$1" table rows input username
  table="$(account_table_by_type "${type}")"
  [[ -z "${table}" ]] && return 1

  rows="$(sqlite3 "$DB_PATH" "SELECT username FROM ${table} ORDER BY username;" 2>/dev/null || true)"
  if [[ -z "${rows}" ]]; then
    echo "Tidak ada akun ${type} di DB." >&2
    return 1
  fi

  echo "Daftar akun ${type^^}:" >&2
  echo "${rows}" | nl -w1 -s') ' >&2
  prompt_input input "Pilih nomor atau isi username: " || return 1
  input="$(echo "${input}" | tr -d '[:space:]')"
  [[ -z "${input}" ]] && { echo "Input kosong." >&2; return 1; }

  if [[ "${input}" =~ ^[0-9]+$ ]]; then
    username="$(echo "${rows}" | sed -n "${input}p")"
    [[ -z "${username}" ]] && { echo "Nomor tidak valid." >&2; return 1; }
  else
    username="$(echo "${rows}" | grep -Fxi "${input}" | head -n1 || true)"
    [[ -z "${username}" ]] && { echo "Username tidak ditemukan." >&2; return 1; }
  fi

  echo "${username}"
  return 0
}

renew_account() {
  local type ep username exp
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_renew "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint renew tidak ada."; return; }
  username="$(pick_existing_username "$type")" || return
  echo "Dipilih: ${username}"
  prompt_input exp "Tambah expired (hari) [30]: " || return
  exp="${exp:-30}"
  api_call "POST" "${ep}/${username}/${exp}" | jq .
}

delete_account() {
  local type ep username
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_delete "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint delete tidak ada."; return; }
  username="$(pick_existing_username "$type")" || return
  echo "Dipilih: ${username}"
  api_call "DELETE" "${ep}/${username}" | jq .
}

list_accounts() {
  echo "Pilih list akun:"
  echo "1) SSH/ZIVPN (DB)"
  echo "2) VMESS (DB)"
  echo "3) VLESS (DB)"
  echo "4) TROJAN (DB)"
  echo "5) ZIVPN auth.config"
  echo "6) Semua"
  prompt_input l "Input [1-6]: " || return
  clear

  case "${l}" in
    1)
      echo "=== SSH/ZIVPN (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_sshs ORDER BY username;"
      ;;
    2)
      echo "=== VMESS (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_vmesses ORDER BY username;"
      ;;
    3)
      echo "=== VLESS (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_vlesses ORDER BY username;"
      ;;
    4)
      echo "=== TROJAN (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_trojans ORDER BY username;"
      ;;
    5)
      echo "=== ZIVPN auth.config ==="
      if [[ -f /etc/zivpn/config.json ]]; then
        jq -r '.auth.config[]?' /etc/zivpn/config.json || true
      else
        echo "File /etc/zivpn/config.json tidak ditemukan."
      fi
      ;;
    6)
      echo "=== SSH/ZIVPN (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_sshs ORDER BY username;"
      echo
      echo "=== VMESS (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_vmesses ORDER BY username;"
      echo
      echo "=== VLESS (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_vlesses ORDER BY username;"
      echo
      echo "=== TROJAN (DB) ==="
      sqlite3 "$DB_PATH" "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)) AS sisa_hari, status FROM account_trojans ORDER BY username;"
      echo
      echo "=== ZIVPN auth.config ==="
      if [[ -f /etc/zivpn/config.json ]]; then
        jq -r '.auth.config[]?' /etc/zivpn/config.json || true
      else
        echo "File /etc/zivpn/config.json tidak ditemukan."
      fi
      ;;
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

udp_backend_status() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  echo "UDP backend:"
  echo "- ZIVPN (${ZIVPN_SERVICE}): $(service_onoff "${ZIVPN_SERVICE}")"
  echo "- UDPHC (${udpcustom}): $(service_onoff "${udpcustom}")"
}

service_onoff() {
  local svc="$1"
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    echo "ON"
  else
    echo "OFF"
  fi
}

show_core_services_onoff() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  echo "Service status (ON/OFF):"
  echo "- ssh: $(service_onoff ssh)"
  echo "- dropbear: $(service_onoff dropbear)"
  echo "- nginx: $(service_onoff nginx)"
  echo "- haproxy: $(service_onoff haproxy)"
  echo "- xray: $(service_onoff xray)"
  echo "- sc-1forcr-api: $(service_onoff sc-1forcr-api)"
  echo "- sc-1forcr-sshws: $(service_onoff sc-1forcr-sshws)"
  echo "- ${ZIVPN_SERVICE}: $(service_onoff "${ZIVPN_SERVICE}")"
  echo "- ${udpcustom}: $(service_onoff "${udpcustom}")"
}

switch_udp_to_zivpn() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  systemctl disable --now "${udpcustom}" >/dev/null 2>&1 || true
  systemctl enable "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  echo "Mode UDP aktif: ZIVPN (UDPHC dimatikan)."
}

switch_udp_to_udpcustom() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  systemctl disable --now "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  systemctl enable "${udpcustom}" >/dev/null 2>&1 || true
  systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
  echo "Mode UDP aktif: UDPHC (ZIVPN dimatikan)."
}

restart_active_udp_backend() {
  local udpcustom zstat ustat
  udpcustom="$(detect_udpcustom_service)"
  zstat="$(systemctl is-active "${ZIVPN_SERVICE}" 2>/dev/null || true)"
  ustat="$(systemctl is-active "${udpcustom}" 2>/dev/null || true)"
  if [[ "${zstat}" == "active" && "${ustat}" == "active" ]]; then
    systemctl disable --now "${udpcustom}" >/dev/null 2>&1 || true
    systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    echo "Keduanya aktif, dipaksa single backend: ZIVPN aktif, UDPHC dimatikan."
    return
  fi
  if [[ "${zstat}" == "active" ]]; then
    systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    echo "Restart backend aktif: ZIVPN."
    return
  fi
  if [[ "${ustat}" == "active" ]]; then
    systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
    echo "Restart backend aktif: UDPHC."
    return
  fi
  echo "Tidak ada backend UDP yang aktif."
}

service_menu() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  echo "1) status semua"
  echo "2) restart semua"
  echo "3) restart backend UDP aktif"
  echo "4) aktifkan ZIVPN (matikan UDPHC)"
  echo "5) aktifkan UDPHC (matikan ZIVPN)"
  echo "6) status backend UDP"
  prompt_input s "Pilih [1-6]: " || return
  clear
  case "$s" in
    1)
      show_core_services_onoff
      ;;
    2)
      systemctl restart ssh dropbear nginx haproxy xray sc-1forcr-api sc-1forcr-sshws
      restart_active_udp_backend
      echo "Restart selesai."
      ;;
    3)
      restart_active_udp_backend
      ;;
    4)
      switch_udp_to_zivpn
      ;;
    5)
      switch_udp_to_udpcustom
      ;;
    6)
      udp_backend_status
      ;;
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

backup_restore_menu() {
  local bdir ts db_backup cfg_zivpn cfg_udphc
  bdir="/root/backup-sc-1forcr"
  ts="$(date +%Y%m%d-%H%M%S)"
  db_backup="${bdir}/accounts-${ts}.db"
  cfg_zivpn="${bdir}/zivpn-config-${ts}.json"
  cfg_udphc="${bdir}/udphc-config-${ts}.json"

  mkdir -p "${bdir}"

  echo "1) Backup config ZIVPN ke /root/config.json.zivpn"
  echo "2) Restore config ZIVPN dari /root/config.json.zivpn"
  echo "3) Backup akun (SSH/VMESS/VLESS/TROJAN) + config ZIVPN + config UDPHC"
  echo "4) Restore akun + config dari backup terbaru"
  prompt_input b "Pilih [1-4]: " || return
  clear
  case "$b" in
    1)
      cp -f /etc/zivpn/config.json /root/config.json.zivpn
      echo "Backup selesai: /root/config.json.zivpn"
      ;;
    2)
      cp -f /root/config.json.zivpn /etc/zivpn/config.json
      systemctl restart "${ZIVPN_SERVICE}" || true
      echo "Restore selesai."
      ;;
    3)
      if [[ -f "${DB_PATH}" ]]; then
        sqlite3 "${DB_PATH}" ".backup '${db_backup}'"
        cp -f "${db_backup}" "${bdir}/accounts-latest.db"
      fi
      if [[ -f /etc/zivpn/config.json ]]; then
        cp -f /etc/zivpn/config.json "${cfg_zivpn}"
        cp -f /etc/zivpn/config.json "${bdir}/zivpn-config-latest.json"
      fi
      if [[ -f /root/udp/config.json ]]; then
        cp -f /root/udp/config.json "${cfg_udphc}"
        cp -f /root/udp/config.json "${bdir}/udphc-config-latest.json"
      fi
      echo "Backup selesai di: ${bdir}"
      ls -lh "${bdir}" | sed -n '1,12p'
      ;;
    4)
      if [[ -f "${bdir}/accounts-latest.db" ]]; then
        systemctl stop sc-1forcr-api >/dev/null 2>&1 || true
        cp -f "${bdir}/accounts-latest.db" "${DB_PATH}"
        chown root:root "${DB_PATH}" >/dev/null 2>&1 || true
        chmod 600 "${DB_PATH}" >/dev/null 2>&1 || true
        systemctl start sc-1forcr-api >/dev/null 2>&1 || true
      fi
      if [[ -f "${bdir}/zivpn-config-latest.json" ]]; then
        cp -f "${bdir}/zivpn-config-latest.json" /etc/zivpn/config.json
      fi
      if [[ -f "${bdir}/udphc-config-latest.json" ]]; then
        mkdir -p /root/udp
        cp -f "${bdir}/udphc-config-latest.json" /root/udp/config.json
      fi
      systemctl restart xray >/dev/null 2>&1 || true
      systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
      if systemctl list-unit-files | grep -q '^sc-1forcr-udpcustom\.service'; then
        systemctl restart sc-1forcr-udpcustom >/dev/null 2>&1 || true
      elif systemctl list-unit-files | grep -q '^udp-custom\.service'; then
        systemctl restart udp-custom >/dev/null 2>&1 || true
      fi
      echo "Restore dari backup terbaru selesai."
      ;;
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

change_domain_menu() {
  local new_domain email app_env pem
  prompt_input new_domain "Masukkan domain baru: " || return
  if [[ -z "${new_domain}" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi
  prompt_input email "Masukkan email Let's Encrypt [admin@${new_domain}]: " || return
  email="${email:-admin@${new_domain}}"

  DOMAIN="${new_domain}"
  EMAIL="${email}"
  setup_nginx_and_cert
  setup_haproxy_tls_mux

  pem="/etc/haproxy/certs/${new_domain}.pem"
  if [[ ! -s "${pem}" ]]; then
    echo "Gagal issue cert untuk domain ${new_domain}."
    echo "Pastikan A record domain mengarah ke VPS, lalu ulangi."
    return
  fi

  if [[ -f /etc/sc-1forcr.env ]]; then
    if grep -q '^DOMAIN=' /etc/sc-1forcr.env; then
      sed -i "s/^DOMAIN=.*/DOMAIN=${new_domain}/" /etc/sc-1forcr.env
    else
      echo "DOMAIN=${new_domain}" >> /etc/sc-1forcr.env
    fi
  fi

  app_env="/opt/sc-1forcr/.env"
  if [[ ! -f "${app_env}" ]]; then
    app_env="/opt/potato-compat/.env"
  fi
  if [[ -f "${app_env}" ]]; then
    if grep -q '^DOMAIN=' "${app_env}"; then
      sed -i "s/^DOMAIN=.*/DOMAIN=${new_domain}/" "${app_env}"
    else
      echo "DOMAIN=${new_domain}" >> "${app_env}"
    fi
  fi

  systemctl restart sc-1forcr-api sc-1forcr-sshws haproxy nginx
  echo "Domain berhasil diubah ke ${new_domain}"
}

monitor_temp_lock_menu() {
  echo "=== AKUN LOCK SEMENTARA (IP LIMIT) ==="
  if [[ ! -f "${DB_PATH}" ]]; then
    echo "DB tidak ditemukan: ${DB_PATH}"
    return
  fi

  local count
  count="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='temp_ip_locks';" 2>/dev/null || echo 0)"
  if [[ "${count}" != "1" ]]; then
    echo "Tabel temp_ip_locks belum ada."
    return
  fi

  sqlite3 -header -column "${DB_PATH}" "
    SELECT
      account_type AS type,
      username,
      datetime(locked_until, 'unixepoch', 'localtime') AS unlock_at,
      CASE
        WHEN (locked_until - strftime('%s','now')) > 0
          THEN CAST((locked_until - strftime('%s','now')) AS INTEGER)
        ELSE 0
      END AS remain_sec
    FROM temp_ip_locks
    ORDER BY locked_until ASC;
  " || true
}

detect_udpcustom_service() {
  if systemctl list-unit-files | grep -q '^sc-1forcr-udpcustom\.service'; then
    echo "sc-1forcr-udpcustom"
    return
  fi
  if systemctl list-unit-files | grep -q '^udp-custom\.service'; then
    echo "udp-custom"
    return
  fi
  echo "${UDPCUSTOM_SERVICE:-sc-1forcr-udpcustom}"
}

onoff_word() {
  local svc="$1"
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    echo "ON"
  else
    echo "OFF"
  fi
}

bytes_human() {
  local bytes="${1:-0}"
  if [[ -z "${bytes}" || ! "${bytes}" =~ ^[0-9]+$ ]]; then
    echo "-"
    return
  fi
  numfmt --to=iec-i --suffix=B "${bytes}" 2>/dev/null || echo "${bytes}B"
}

read_vnstat_stats() {
  VNSTAT_MONTH_RX="-"
  VNSTAT_MONTH_TX="-"
  VNSTAT_DAY_RX="-"
  VNSTAT_DAY_TX="-"
  VNSTAT_IFACE="-"
  if ! command -v vnstat >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return
  fi

  local js rx tx drx dtx iface
  js="$(vnstat --json 2>/dev/null || true)"
  [[ -z "${js}" ]] && return

  iface="$(echo "${js}" | jq -r '.interfaces[0].name // "-"' 2>/dev/null || echo "-")"
  rx="$(echo "${js}" | jq -r '(.interfaces[0].traffic.month // [] | last | .rx // 0)' 2>/dev/null || echo 0)"
  tx="$(echo "${js}" | jq -r '(.interfaces[0].traffic.month // [] | last | .tx // 0)' 2>/dev/null || echo 0)"
  drx="$(echo "${js}" | jq -r '(.interfaces[0].traffic.day // [] | last | .rx // 0)' 2>/dev/null || echo 0)"
  dtx="$(echo "${js}" | jq -r '(.interfaces[0].traffic.day // [] | last | .tx // 0)' 2>/dev/null || echo 0)"

  VNSTAT_IFACE="${iface}"
  VNSTAT_MONTH_RX="$(bytes_human "${rx}")"
  VNSTAT_MONTH_TX="$(bytes_human "${tx}")"
  VNSTAT_DAY_RX="$(bytes_human "${drx}")"
  VNSTAT_DAY_TX="$(bytes_human "${dtx}")"
}

draw_dashboard() {
  local os_name ram_mb swap_mb uptime_s uptime_h uptime_m
  local ip city isp udpcustom
  local ssh_on nginx_on xray_on api_on ws_on
  local c_ssh c_vmess c_vless c_trojan
  local month_total day_total
  local C0 CC CG CY CR CD

  os_name="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Unknown}")"
  ram_mb="$(free -m 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2 " MB"}')"
  swap_mb="$(free -m 2>/dev/null | awk '/^Swap:/ {print $3 "/" $2 " MB"}')"
  uptime_s="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
  uptime_h="$((uptime_s / 3600))"
  uptime_m="$(((uptime_s % 3600) / 60))"

  ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  ip="${ip:-unknown}"
  city="$(curl -fsS --max-time 3 https://ipinfo.io/city 2>/dev/null || echo "-")"
  isp="$(curl -fsS --max-time 3 https://ipinfo.io/org 2>/dev/null || echo "-")"

  udpcustom="$(detect_udpcustom_service)"
  ssh_on="$(onoff_word ssh)"
  nginx_on="$(onoff_word nginx)"
  xray_on="$(onoff_word xray)"
  api_on="$(onoff_word sc-1forcr-api)"
  ws_on="$(onoff_word sc-1forcr-sshws)"

  c_ssh="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_sshs;" 2>/dev/null || echo 0)"
  c_vmess="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_vmesses;" 2>/dev/null || echo 0)"
  c_vless="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_vlesses;" 2>/dev/null || echo 0)"
  c_trojan="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_trojans;" 2>/dev/null || echo 0)"

  read_vnstat_stats
  month_total="-"
  day_total="-"
  if [[ "${VNSTAT_MONTH_RX}" != "-" && "${VNSTAT_MONTH_TX}" != "-" ]]; then
    month_total="${VNSTAT_MONTH_RX} + ${VNSTAT_MONTH_TX}"
  fi
  if [[ "${VNSTAT_DAY_RX}" != "-" && "${VNSTAT_DAY_TX}" != "-" ]]; then
    day_total="${VNSTAT_DAY_RX} + ${VNSTAT_DAY_TX}"
  fi

  C0=""
  CC=""
  CG=""
  CY=""
  CR=""
  CD=""
  if [[ -t 1 ]]; then
    C0=$'\033[0m'
    CC=$'\033[1;36m'
    CG=$'\033[1;32m'
    CY=$'\033[1;33m'
    CR=$'\033[1;31m'
    CD=$'\033[2m'
  fi

  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b|                       SC 1FORCR NEXUS PANEL                     |%b\n" "${CC}" "${C0}"
  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b|%b OS      : %-54s %b|%b\n" "${CC}" "${C0}" "${os_name}" "${CC}" "${C0}"
  printf "%b|%b RAM     : %-54s %b|%b\n" "${CC}" "${C0}" "${ram_mb:-"-"}" "${CC}" "${C0}"
  printf "%b|%b SWAP    : %-54s %b|%b\n" "${CC}" "${C0}" "${swap_mb:-"-"}" "${CC}" "${C0}"
  printf "%b|%b CITY    : %-54s %b|%b\n" "${CC}" "${C0}" "${city}" "${CC}" "${C0}"
  printf "%b|%b ISP     : %-54s %b|%b\n" "${CC}" "${C0}" "${isp}" "${CC}" "${C0}"
  printf "%b|%b IP      : %-54s %b|%b\n" "${CC}" "${C0}" "${ip}" "${CC}" "${C0}"
  printf "%b|%b DOMAIN  : %-54s %b|%b\n" "${CC}" "${C0}" "${DOMAIN}" "${CC}" "${C0}"
  printf "%b|%b UPTIME  : %-54s %b|%b\n" "${CC}" "${C0}" "${uptime_h}h ${uptime_m}m" "${CC}" "${C0}"
  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b|%b TRAFFIC : IFACE %-13s RX %-12s TX %-12s %b|%b\n" "${CC}" "${C0}" "${VNSTAT_IFACE}" "${VNSTAT_DAY_RX}" "${VNSTAT_DAY_TX}" "${CC}" "${C0}"
  printf "%b|%b MONTH   : %-54s %b|%b\n" "${CC}" "${C0}" "${month_total}" "${CC}" "${C0}"
  printf "%b|%b TODAY   : %-54s %b|%b\n" "${CC}" "${C0}" "${day_total}" "${CC}" "${C0}"
  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b|%b CORE    : SSH[%s%s%b] NGINX[%s%s%b] XRAY[%s%s%b] API[%s%s%b] WS[%s%s%b] %b|%b\n" \
    "${CC}" "${C0}" \
    "$([[ "${ssh_on}" == "ON" ]] && echo "${CG}" || echo "${CR}")" "${ssh_on}" "${C0}" \
    "$([[ "${nginx_on}" == "ON" ]] && echo "${CG}" || echo "${CR}")" "${nginx_on}" "${C0}" \
    "$([[ "${xray_on}" == "ON" ]] && echo "${CG}" || echo "${CR}")" "${xray_on}" "${C0}" \
    "$([[ "${api_on}" == "ON" ]] && echo "${CG}" || echo "${CR}")" "${api_on}" "${C0}" \
    "$([[ "${ws_on}" == "ON" ]] && echo "${CG}" || echo "${CR}")" "${ws_on}" "${C0}" \
    "${CC}" "${C0}"
  printf "%b|%b UDP     : ZIVPN[%s%s%b] UDPHC[%s%s%b]%29s%b|%b\n" \
    "${CC}" "${C0}" \
    "$([[ "$(onoff_word "${ZIVPN_SERVICE}")" == "ON" ]] && echo "${CG}" || echo "${CR}")" "$(onoff_word "${ZIVPN_SERVICE}")" "${C0}" \
    "$([[ "$(onoff_word "${udpcustom}")" == "ON" ]] && echo "${CG}" || echo "${CR}")" "$(onoff_word "${udpcustom}")" "${C0}" \
    "" "${CC}" "${C0}"
  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b|%b ACCOUNTS: SSH %-6s VMESS %-6s VLESS %-6s TROJAN %-6s        %b|%b\n" "${CC}" "${C0}" "${c_ssh}" "${c_vmess}" "${c_vless}" "${c_trojan}" "${CC}" "${C0}"
  printf "%b|%b VERSION : %b%-54s%b %b|%b\n" "${CC}" "${C0}" "${CY}" "${SCRIPT_VERSION:-unknown}" "${C0}" "${CC}" "${C0}"
  printf "%b+------------------------------------------------------------------+%b\n" "${CC}" "${C0}"
  printf "%b%s%b\n" "${CD}" "hint: akses menu tetap sama, tampilannya aja dibuat beda dari potato." "${C0}"
}

show_combined_online() {
  local mode ip isp tmp_users tmp_count udpcustom
  mode="${1:-realtime}"
  ip="$(curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  ip="${ip:-unknown}"
  isp="$(curl -fsS --max-time 4 "https://ipinfo.io/${ip}/org" 2>/dev/null || echo unknown)"
  udpcustom="$(detect_udpcustom_service)"

  tmp_users="$(mktemp)"
  tmp_count="$(mktemp)"
  trap 'rm -f "${tmp_users:-}" "${tmp_count:-}"' RETURN

  # SSH/Dropbear user aktif dari process sshd + who (tanpa awk kompleks agar kompatibel)
  ps -eo args= 2>/dev/null | \
    sed -n 's/^sshd:[[:space:]]*//p' | \
    sed -E 's/[[:space:]].*$//' | \
    sed -E 's/@.*$//' | \
    sed -E 's/\[.*$//' | \
    tr '[:upper:]' '[:lower:]' | \
    grep -E '^[a-z0-9._-]+$' | \
    grep -v '^root$' >> "${tmp_users}" || true

  who 2>/dev/null | \
    cut -d' ' -f1 | \
    tr '[:upper:]' '[:lower:]' | \
    grep -E '^[a-z0-9._-]+$' | \
    grep -v '^root$' >> "${tmp_users}" || true

  # UDP Custom user dari log (realtime ringan: 5 menit terakhir, history: lebih panjang)
  if [[ "${mode}" == "history" ]]; then
    journalctl -u "${udpcustom}" -u sc-1forcr-udpcustom -u udp-custom -n 1200 --no-pager 2>/dev/null
  else
    journalctl -u "${udpcustom}" -u sc-1forcr-udpcustom -u udp-custom --since "-5 min" -n 250 --no-pager 2>/dev/null
  fi | \
    sed -nE '
      s/.*\[src:[^]]+\][[:space:]]+\[user:([^]]+)\][[:space:]]+Client connected.*/\1/p;
      s/.*\[user:([^]]+)\].*/\1/p;
      s/.*user[=: ]([^ ,]+).*src[=: ][^ ,]+.*/\1/p;
    ' | tr '[:upper:]' '[:lower:]' >> "${tmp_users}"

  grep -E '^[a-z0-9._-]+$' "${tmp_users}" | sort | uniq -c | \
    sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+(.+)$/\2 \1/' > "${tmp_count}" || true

  echo "IP     : ${ip}"
  echo "DOMAIN : ${DOMAIN}"
  echo "ISP    : ${isp}"
  echo "Users Login SSH/Dropbear + UDP Custom"

  if [[ ! -s "${tmp_count}" ]]; then
    echo "Tidak ada user online terdeteksi."
    echo
    echo "Total User : 0"
    echo "Total PID  : 0"
    return
  fi

  while read -r u n; do
    [[ -z "${u:-}" || -z "${n:-}" ]] && continue
    echo "${u} ${n} PID"
  done < "${tmp_count}"
  local total_user total_pid n
  total_user="$(wc -l < "${tmp_count}" | tr -d ' ')"
  total_pid=0
  while read -r _ n; do
    [[ -n "${n:-}" ]] || continue
    total_pid=$((total_pid + n))
  done < "${tmp_count}"
  echo
  echo "Total User : ${total_user}"
  echo "Total PID  : ${total_pid}"
}

show_ssh_online() {
  show_combined_online "realtime"
}

show_ssh_online_history() {
  show_combined_online "history"
}

xray_log_snapshot() {
  local dst="$1"
  if [[ ! -f /var/log/xray/access.log ]]; then
    : > "${dst}"
    return
  fi
  tail -n 25000 /var/log/xray/access.log | awk '
    {
      email=""; src="";
      if (match($0, /"email":"[^"]+"/)) {
        email=substr($0, RSTART+9, RLENGTH-10);
      } else if (match($0, /email:[[:space:]]*[^[:space:]]+/)) {
        t=substr($0, RSTART, RLENGTH); sub(/email:[[:space:]]*/, "", t); email=t;
      }

      if (match($0, /"source":"[^"]+"/)) {
        src=substr($0, RSTART+10, RLENGTH-11);
      } else if (match($0, /from[[:space:]]+[0-9a-fA-F\.:]+/)) {
        t=substr($0, RSTART, RLENGTH); sub(/from[[:space:]]+/, "", t); src=t;
      }

      if (email == "") next;
      gsub(/[[:space:]]/, "", email);
      email=tolower(email);

      ip=src;
      sub(/:[0-9]+$/, "", ip);

      seen[email]=1;
      if (ip != "") lastip[email]=ip;
    }
    END {
      for (u in seen) {
        printf "%s|%s\n", u, lastip[u];
      }
    }' > "${dst}"
}

show_xray_online_by_table() {
  local table="$1" label="$2"
  local t_users t_seen
  t_users="$(mktemp)"
  t_seen="$(mktemp)"
  trap 'rm -f "${t_users:-}" "${t_seen:-}"' RETURN

  sqlite3 "${DB_PATH}" "SELECT LOWER(username) FROM ${table} WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' ORDER BY LOWER(username);" > "${t_users}" 2>/dev/null || true
  if [[ ! -s "${t_users}" ]]; then
    echo "=== ${label} ONLINE ==="
    echo "Tidak ada akun ${label} aktif di DB."
    return
  fi

  xray_log_snapshot "${t_seen}"

  echo "=== ${label} ONLINE (berdasarkan log xray terbaru) ==="
  awk -F'|' '
    NR==FNR { ip[$1]=$2; next }
    {
      u=$1;
      if (u in ip) {
        seen=1;
        printf "%-20s %s\n", u, (ip[u] == "" ? "-" : ip[u]);
      }
    }
    END {
      if (!seen) print "Tidak ada aktivitas terbaru.";
    }' "${t_seen}" "${t_users}" | sort
}

show_udpcustom_online() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  echo "=== UDP CUSTOM ONLINE (log terbaru) ==="
  journalctl -u "${udpcustom}" -u sc-1forcr-udpcustom -u udp-custom -n 1200 --no-pager 2>/dev/null | \
    sed -nE '
      s/.*\[src:([^]]+)\][[:space:]]+\[user:([^]]+)\][[:space:]]+Client connected.*/\2|\1/p;
      s/.*user[=: ]([^ ,]+).*src[=: ]([^ ,]+).*/\1|\2/p;
      s/.*src[=: ]([^ ,]+).*user[=: ]([^ ,]+).*/\2|\1/p;
    ' | \
    awk -F'|' '
      {
        user=$1; src=$2;
        cnt[user]++; last[user]=src;
      }
      END {
        if (length(cnt) == 0) {
          print "Tidak ada koneksi terbaru.";
          exit;
        }
        printf "%-20s %-24s %s\n", "username", "last_src", "hits";
        for (u in cnt) {
          printf "%-20s %-24s %d\n", u, last[u], cnt[u];
        }
      }' | sort
}

update_script_from_repo() {
  local url tmp active_backend
  url="${UPDATE_SCRIPT_URL:-}"
  if [[ -z "${url}" ]]; then
    echo "UPDATE_SCRIPT_URL belum diisi di /etc/sc-1forcr.env"
    echo "Contoh:"
    echo "UPDATE_SCRIPT_URL=https://raw.githubusercontent.com/<user>/<repo>/main/scripts/setup-autoscript-compat.sh"
    return
  fi

  tmp="/tmp/setup-autoscript-compat.sh"
  echo "Download update script dari: ${url}"
  if ! curl -fsSL "${url}" -o "${tmp}"; then
    echo "Gagal download update script."
    return
  fi
  chmod +x "${tmp}"
  if ! bash -n "${tmp}"; then
    echo "Update script gagal validasi syntax (bash -n)."
    return
  fi

  active_backend="zivpn"
  if systemctl is-active --quiet "${UDPCUSTOM_SERVICE:-sc-1forcr-udpcustom}"; then
    active_backend="udpcustom"
  fi

  echo "Menjalankan update installer..."
  DOMAIN="${DOMAIN}" \
  EMAIL="${EMAIL:-admin@${DOMAIN}}" \
  API_AUTH_TOKEN="${AUTH_TOKEN}" \
  UPDATE_SCRIPT_URL="${UPDATE_SCRIPT_URL}" \
  DB_PATH="${DB_PATH}" \
  APP_DIR="/opt/sc-1forcr" \
  ZIVPN_SERVICE_NAME="${ZIVPN_SERVICE}" \
  UDPCUSTOM_SERVICE_NAME="${UDPCUSTOM_SERVICE}" \
  DROPBEAR_PORT="${DROPBEAR_PORT}" \
  DROPBEAR_ALT_PORT="${DROPBEAR_ALT_PORT}" \
  ACTIVE_UDP_BACKEND="${active_backend}" \
  bash "${tmp}"
}

monitor_online_menu() {
  while true; do
    clear
    echo "===================================="
    echo "      MONITOR USER ONLINE"
    echo "===================================="
    echo "1) SSH + UDP CUSTOM (Realtime ringan)"
    echo "2) SSH + UDP CUSTOM (Histori log)"
    echo "3) VMESS"
    echo "4) VLESS"
    echo "5) TROJAN"
    echo "6) UDP CUSTOM"
    echo "0) Kembali"
    echo
    if ! prompt_input o "Pilih menu: "; then
      return
    fi
    clear
    case "${o}" in
      1) show_ssh_online ;;
      2) show_ssh_online_history ;;
      3) show_xray_online_by_table "account_vmesses" "VMESS" ;;
      4) show_xray_online_by_table "account_vlesses" "VLESS" ;;
      5) show_xray_online_by_table "account_trojans" "TROJAN" ;;
      6) show_udpcustom_online ;;
      0) return ;;
      *) echo "Pilihan tidak valid." ;;
    esac
    echo
    read -rp "Enter untuk lanjut..." _ || true
  done
}

while true; do
  clear
  draw_dashboard
  echo
  echo "1) Add Account"
  echo "2) Renew Account"
  echo "3) Delete Account"
  echo "4) List Account"
  echo "5) Service Menu"
  echo "6) Backup/Restore Config + Akun"
  echo "7) Ganti Domain + Renew SSL"
  echo "8) Monitor Lock Sementara (IP Limit)"
  echo "9) Monitor User Online"
  echo "10) Uninstall SC 1FORCR"
  echo "11) Update Script dari Repo"
  echo "x) Exit"
  echo
  if ! prompt_input m "Pilih menu: "; then
    continue
  fi
  clear
  case "$m" in
    1) create_account ;;
    2) renew_account ;;
    3) delete_account ;;
    4) list_accounts ;;
    5) service_menu ;;
    6) backup_restore_menu ;;
    7) change_domain_menu ;;
    8) monitor_temp_lock_menu ;;
    9) monitor_online_menu ;;
    10) /usr/local/sbin/uninstall-sc-1forcr ;;
    11) update_script_from_repo ;;
    x|X) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
  echo
  read -rp "Enter untuk lanjut..." _ || true
done
EOF

  chmod +x /usr/local/sbin/menu-sc-1forcr
  ln -sf /usr/local/sbin/menu-sc-1forcr /usr/local/sbin/menu

  cat > /usr/local/sbin/uninstall-sc-1forcr <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Jalankan sebagai root."
  exit 1
fi

read -r -p "Yakin uninstall SC 1FORCR? [y/N]: " ans
if [[ "${ans:-}" != "y" && "${ans:-}" != "Y" ]]; then
  echo "Batal uninstall."
  exit 0
fi

systemctl stop sc-1forcr-api >/dev/null 2>&1 || true
systemctl disable sc-1forcr-api >/dev/null 2>&1 || true
systemctl stop sc-1forcr-sshws >/dev/null 2>&1 || true
systemctl disable sc-1forcr-sshws >/dev/null 2>&1 || true
systemctl stop haproxy >/dev/null 2>&1 || true
systemctl disable haproxy >/dev/null 2>&1 || true
systemctl stop sc-1forcr-iplimit.timer >/dev/null 2>&1 || true
systemctl disable sc-1forcr-iplimit.timer >/dev/null 2>&1 || true
systemctl stop sc-1forcr-iplimit.service >/dev/null 2>&1 || true
systemctl disable sc-1forcr-iplimit.service >/dev/null 2>&1 || true
systemctl stop sc-1forcr-udpcustom >/dev/null 2>&1 || true
systemctl disable sc-1forcr-udpcustom >/dev/null 2>&1 || true
systemctl stop udp-custom >/dev/null 2>&1 || true
systemctl disable udp-custom >/dev/null 2>&1 || true
rm -f /etc/systemd/system/sc-1forcr-api.service
rm -f /etc/systemd/system/sc-1forcr-sshws.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.timer
rm -f /etc/systemd/system/sc-1forcr-udpcustom.service
rm -f /etc/systemd/system/potato-compat-api.service
systemctl daemon-reload

rm -rf /opt/sc-1forcr
rm -rf /opt/potato-compat
rm -f /etc/sc-1forcr.env
rm -f /etc/potato-compat.env
rm -f /usr/local/sbin/menu-sc-1forcr
rm -f /usr/local/sbin/menu-potato
rm -f /usr/local/sbin/menu
rm -f /usr/local/sbin/uninstall-sc-1forcr
rm -f /usr/local/sbin/uninstall-potato-compat

echo "Uninstall SC 1FORCR selesai."
echo "Catatan: layanan inti (ssh/nginx/xray/zivpn) tidak dihapus otomatis."
EOF
  chmod +x /usr/local/sbin/uninstall-sc-1forcr
}

write_version_marker() {
  mkdir -p "${APP_DIR}"
  printf '%s\n' "${SCRIPT_VERSION}" > "${APP_DIR}/VERSION"
  chmod 644 "${APP_DIR}/VERSION"
  printf 'SCRIPT_VERSION=%s\n' "${SCRIPT_VERSION}" > /etc/sc-1forcr-version
  chmod 644 /etc/sc-1forcr-version
}

main() {
  install_base_packages
  apply_system_optimizations
  setup_logrotate_optimizations
  install_node20_if_missing
  install_go_if_missing
  install_xray
  setup_dropbear
  init_db
  setup_nginx_and_cert
  setup_haproxy_tls_mux
  setup_zivpn_service_if_possible
  setup_zivpn_udp_nat_rules
  setup_udpcustom_service_if_possible
  setup_udpcustom_udp_nat_rules
  enforce_single_udp_backend
  write_api_files
  write_go_mux_files
  build_go_files
  write_iplimit_checker
  setup_services
  write_cli_menu
  write_version_marker

  cat <<EOF

=========================================
SELESAI - SC 1FORCR TERPASANG
=========================================
Script Version : ${SCRIPT_VERSION}
Domain         : ${DOMAIN}
Email LE       : ${EMAIL}
DB Path        : ${DB_PATH}
API Token      : ${API_AUTH_TOKEN}
API Base       : https://${DOMAIN}/vps
Summary DB key : tabel servers kolom key = token di atas

Contoh test:
curl -s -X POST "https://${DOMAIN}/vps/sshvpn" \\
  -H "Authorization: ${API_AUTH_TOKEN}" \\
  -H "Content-Type: application/json" \\
  -d '{"username":"test123","password":"test123","expired":3,"limitip":"2","kuota":"0"}'

Catatan:
- Endpoint /vps/* sudah kompatibel pola bot kamu (create/trial/renew/delete/lock/unlock).
- WS paths aktif: /ssh-ws, /ws, /vmess, /vless, /trojan (port 80 & 443)
- Dropbear aktif di port ${DROPBEAR_PORT} dan ${DROPBEAR_ALT_PORT}; ssh-ws bridge default ke ${DROPBEAR_PORT}
- SSH mux runtime sudah pakai Go binary: ${APP_DIR}/bin/ssh-mux
- Untuk summary API, tinggal pakai scripts/setup-summary-api.sh di repo ini.
- Jika binary zivpn belum ada, isi ZIVPN_BIN_URL lalu jalankan ulang script.
- Rule UDP ZIVPN otomatis dipasang: INPUT udp ${ZIVPN_LISTEN_PORT}, DNAT ${ZIVPN_DNAT_RANGE} -> ${ZIVPN_LISTEN_PORT}.
- UDP Custom juga otomatis disiapkan di service ${UDPCUSTOM_SERVICE_NAME} (config: /root/udp/config.json).
- UDP Custom default tanpa DNAT range (lebih stabil/cepat). Jika perlu mode tembak port, isi UDPCUSTOM_DNAT_RANGE.
- Hanya 1 backend UDP aktif sesuai ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND} (zivpn|udpcustom).
- Menu VPS: jalankan perintah menu atau menu-sc-1forcr
- Update sekali klik dari menu: isi UPDATE_SCRIPT_URL lalu pilih menu 11 (Update Script dari Repo)
- Uninstall helper: uninstall-sc-1forcr
- Auto lock IP limit: timer systemd sc-1forcr-iplimit.timer (cek tiap 15 menit, lock sementara 15 menit)
EOF
}

main "$@"
