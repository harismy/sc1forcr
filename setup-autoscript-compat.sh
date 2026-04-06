#!/usr/bin/env bash
set -euo pipefail

# AutoScript kompatibel BotVPN/Potato
# Target OS: Debian 10+ / Ubuntu 20+
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

check_supported_os() {
  local id ver major
  if [[ ! -f /etc/os-release ]]; then
    echo "OS tidak dikenali (/etc/os-release tidak ditemukan)."
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  id="${ID:-}"
  ver="${VERSION_ID:-0}"
  major="${ver%%.*}"

  case "${id}" in
    debian)
      if [[ "${major}" -lt 10 ]]; then
        echo "Debian ${ver} tidak didukung. Minimal Debian 10."
        exit 1
      fi
      ;;
    ubuntu)
      if [[ "${major}" -lt 20 ]]; then
        echo "Ubuntu ${ver} tidak didukung. Minimal Ubuntu 20.04."
        exit 1
      fi
      ;;
    *)
      echo "OS ${id:-unknown} belum didukung script ini."
      echo "Gunakan Debian 10+ atau Ubuntu 20+."
      exit 1
      ;;
  esac
  log "OS terdeteksi: ${PRETTY_NAME:-${id} ${ver}}"
}

install_optional_pkg_if_available() {
  local pkg="$1"
  if apt-cache show "${pkg}" >/dev/null 2>&1; then
    apt-get install -y "${pkg}"
    return 0
  fi
  log "Paket opsional '${pkg}' tidak tersedia di repo, skip."
  return 1
}

install_base_packages() {
  log "Install paket dasar..."
  apt-get update -y
  apt-get install -y \
    curl wget jq sqlite3 openssl uuid-runtime ca-certificates \
    gnupg lsb-release socat cron unzip \
    haproxy \
    nginx certbot \
    openssh-server dropbear pwgen \
    build-essential python3 make g++ gcc libc6-dev pkg-config bzip2 zlib1g-dev

  # Paket opsional (beberapa distro/repo lama tidak selalu menyediakan).
  install_optional_pkg_if_available python3-certbot-nginx || true
  install_optional_pkg_if_available vnstat || true
  install_optional_pkg_if_available speedtest-cli || true
}

install_node_if_missing() {
  if command -v node >/dev/null 2>&1; then
    log "Node sudah ada: $(node -v)"
    return
  fi
  log "Install Node.js (prioritas 20, fallback 18)..."
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg
  if curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs; then
    log "Node terpasang: $(node -v)"
    return
  fi

  log "Node 20 gagal/kurang kompatibel, fallback ke Node 18..."
  apt-get purge -y nodejs >/dev/null 2>&1 || true
  rm -f /etc/apt/sources.list.d/nodesource.list
  if curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs; then
    log "Node terpasang: $(node -v)"
    return
  fi

  echo "Gagal install Node.js dari NodeSource (20/18)."
  exit 1
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

setup_vnstat() {
  if ! command -v vnstat >/dev/null 2>&1; then
    return
  fi
  log "Setup vnStat..."
  systemctl enable vnstat >/dev/null 2>&1 || true
  systemctl restart vnstat >/dev/null 2>&1 || true
  local iface
  iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
  if [[ -n "${iface}" ]]; then
    vnstat --add -i "${iface}" >/dev/null 2>&1 || true
  fi
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

ensure_zivpn_tls_assets() {
  local cert key
  cert="/etc/zivpn/zivpn.crt"
  key="/etc/zivpn/zivpn.key"
  mkdir -p /etc/zivpn

  if [[ -s "${cert}" && -s "${key}" ]]; then
    chmod 644 "${cert}" >/dev/null 2>&1 || true
    chmod 600 "${key}" >/dev/null 2>&1 || true
    return 0
  fi

  log "Generate self-signed TLS untuk ZIVPN..."
  openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 \
    -subj "/CN=${DOMAIN}" \
    -keyout "${key}" \
    -out "${cert}" >/dev/null 2>&1
  chmod 644 "${cert}" >/dev/null 2>&1 || true
  chmod 600 "${key}" >/dev/null 2>&1 || true
}

ensure_zivpn_config_schema() {
  local cfg listen cert key tmp
  cfg="/etc/zivpn/config.json"
  cert="/etc/zivpn/zivpn.crt"
  key="/etc/zivpn/zivpn.key"
  listen=":${ZIVPN_LISTEN_PORT}"

  if [[ ! -f "${cfg}" ]]; then
    cat > "${cfg}" <<EOF
{
  "listen": "${listen}",
  "cert": "${cert}",
  "key": "${key}",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log "jq tidak tersedia, skip auto-patch schema config ZIVPN."
    return 0
  fi

  tmp="$(mktemp)"
  if jq \
    --arg listen "${listen}" \
    --arg cert "${cert}" \
    --arg key "${key}" \
    '
      .auth = (.auth // {"mode":"passwords","config":[]}) |
      .auth.mode = (.auth.mode // "passwords") |
      .auth.config = (if (.auth.config | type) == "array" then .auth.config else [] end) |
      .listen = (if ((.listen | type) == "string" and .listen != "") then .listen else $listen end) |
      .cert = $cert |
      .key = $key |
      .obfs = (if ((.obfs | type) == "string" and .obfs != "") then .obfs else "zivpn" end) |
      del(.zivpn_udp)
    ' "${cfg}" > "${tmp}" 2>/dev/null; then
    mv -f "${tmp}" "${cfg}"
  else
    rm -f "${tmp}" >/dev/null 2>&1 || true
    log "Gagal patch schema config ZIVPN via jq, gunakan config lama."
  fi
}

setup_zivpn_service_if_possible() {
  mkdir -p /etc/zivpn
  ensure_zivpn_tls_assets
  ensure_zivpn_config_schema

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

fw_backend_kind() {
  if command -v iptables >/dev/null 2>&1; then
    echo "iptables"
    return 0
  fi
  if command -v nft >/dev/null 2>&1; then
    echo "nft"
    return 0
  fi
  echo "none"
}

fw_allow_udp_input() {
  local port="$1" fw
  fw="$(fw_backend_kind)"
  case "${fw}" in
    iptables)
      iptables -C INPUT -p udp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT -p udp --dport "${port}" -j ACCEPT
      ;;
    nft)
      if nft list chain inet filter input >/dev/null 2>&1; then
        nft list chain inet filter input | grep -F -- "udp dport ${port} accept" >/dev/null 2>&1 || \
          nft add rule inet filter input udp dport "${port}" accept
      elif nft list chain ip filter input >/dev/null 2>&1; then
        nft list chain ip filter input | grep -F -- "udp dport ${port} accept" >/dev/null 2>&1 || \
          nft add rule ip filter input udp dport "${port}" accept
      else
        log "Chain filter input tidak ditemukan di nftables. Rule allow UDP ${port} dilewati."
      fi
      ;;
  esac
}

fw_add_udp_dnat_range() {
  local range="$1" to_port="$2" fw
  fw="$(fw_backend_kind)"
  case "${fw}" in
    iptables)
      iptables -t nat -C PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1 || \
        iptables -t nat -I PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}"
      ;;
    nft)
      nft add table ip nat >/dev/null 2>&1 || true
      nft 'add chain ip nat prerouting { type nat hook prerouting priority dstnat; }' >/dev/null 2>&1 || true
      nft list chain ip nat prerouting 2>/dev/null | grep -F -- "udp dport ${range} dnat to :${to_port}" >/dev/null 2>&1 || \
        nft add rule ip nat prerouting udp dport "${range}" dnat to ":${to_port}"
      ;;
  esac
}

fw_delete_udp_dnat_range() {
  local range="$1" to_port="$2" fw range_nft handle
  fw="$(fw_backend_kind)"
  case "${fw}" in
    iptables)
      while iptables -t nat -C PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1 || break
      done
      ;;
    nft)
      range_nft="${range/:/-}"
      while IFS= read -r handle; do
        [[ -z "${handle}" ]] && continue
        nft delete rule ip nat prerouting handle "${handle}" >/dev/null 2>&1 || true
      done < <(
        nft -a list chain ip nat prerouting 2>/dev/null | \
          awk -v sig="udp dport ${range_nft} dnat to :${to_port}" '$0 ~ sig {for (i=1;i<=NF;i++) if ($i=="handle") print $(i+1)}'
      )
      ;;
  esac
}

fw_persist_rules() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
    return 0
  fi
  if command -v nft >/dev/null 2>&1 && systemctl is-enabled --quiet nftables 2>/dev/null; then
    nft list ruleset >/etc/nftables.conf 2>/dev/null || true
  fi
  return 0
}

setup_zivpn_udp_nat_rules() {
  if ! command -v zivpn >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$(fw_backend_kind)" == "none" ]]; then
    log "iptables/nft tidak ditemukan. Skip rule DNAT ZIVPN."
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

  fw_allow_udp_input "${listen_port}"
  fw_add_udp_dnat_range "${ZIVPN_DNAT_RANGE}" "${listen_port}"

  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Install netfilter-persistent agar rule iptables tidak hilang saat reboot..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent >/dev/null 2>&1 || true
  fi
  fw_persist_rules
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
  if [[ "$(fw_backend_kind)" == "none" ]]; then
    log "iptables/nft tidak ditemukan. Skip rule DNAT UDP Custom."
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

  fw_allow_udp_input "${listen_port}"

  if [[ -n "${UDPCUSTOM_DNAT_RANGE}" ]]; then
    fw_add_udp_dnat_range "${UDPCUSTOM_DNAT_RANGE}" "${listen_port}"
  else
    log "UDPHC tanpa DNAT range (default performa). Isi UDPCUSTOM_DNAT_RANGE jika perlu mode tembak port."
    if [[ "${backend}" == "udpcustom" || "${backend}" == "udp-custom" || "${backend}" == "udphc" ]]; then
      # Saat UDPHC aktif tanpa range, bersihkan DNAT range ZIVPN agar tidak membingungkan jalur trafik.
      fw_delete_udp_dnat_range "${ZIVPN_DNAT_RANGE}" "${listen_port}"
      log "DNAT range ZIVPN ${ZIVPN_DNAT_RANGE} dibersihkan (backend UDPHC aktif)."
    else
      log "DNAT UDPHC tidak diubah karena UDPCUSTOM_DNAT_RANGE kosong."
    fi
  fi

  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Install netfilter-persistent agar rule iptables tidak hilang saat reboot..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent >/dev/null 2>&1 || true
  fi
  fw_persist_rules
}

enforce_single_udp_backend() {
  local backend
  backend="$(echo "${ACTIVE_UDP_BACKEND}" | tr '[:upper:]' '[:lower:]')"
  case "${backend}" in
    udpcustom|udp-custom|udphc)
      systemctl disable --now "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl enable "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl restart "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      setup_udpcustom_udp_nat_rules
      log "Backend UDP aktif: UDP Custom (${UDPCUSTOM_SERVICE_NAME})"
      ;;
    zivpn|*)
      systemctl disable --now "${UDPCUSTOM_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl enable "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      systemctl restart "${ZIVPN_SERVICE_NAME}" >/dev/null 2>&1 || true
      setup_zivpn_udp_nat_rules
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
UDPCUSTOM_CONFIG=/root/udp/config.json
UDPCUSTOM_LISTEN_PORT=${UDPCUSTOM_LISTEN_PORT}
UDPCUSTOM_SERVICE=${UDPCUSTOM_SERVICE_NAME}
ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND}
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
const UDPCUSTOM_CONFIG = process.env.UDPCUSTOM_CONFIG || '/root/udp/config.json';
const UDPCUSTOM_LISTEN_PORT = Number(process.env.UDPCUSTOM_LISTEN_PORT || 5667);
const UDPCUSTOM_SERVICE = String(process.env.UDPCUSTOM_SERVICE || 'sc-1forcr-udpcustom').trim() || 'sc-1forcr-udpcustom';
const ACTIVE_UDP_BACKEND = String(process.env.ACTIVE_UDP_BACKEND || '').trim().toLowerCase();
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
function readExec(cmd, args) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 2 * 1024 * 1024 });
  } catch (_) {
    return '';
  }
}

function addIpToUserMap(map, username, ip) {
  const u = String(username || '').trim().toLowerCase();
  const v = String(ip || '').trim();
  if (!u || !v || u === 'root') return;
  if (!map.has(u)) map.set(u, new Set());
  map.get(u).add(v);
}

function addSessionKeyToUserMap(map, username, key) {
  const u = String(username || '').trim().toLowerCase();
  const k = String(key || '').trim().toLowerCase();
  if (!u || !k || u === 'root') return;
  if (!map.has(u)) map.set(u, new Set());
  map.get(u).add(k);
}

function extractIp(raw) {
  let v = String(raw || '').trim();
  if (!v) return '';
  v = v.replace(/^\[/, '').replace(/\]$/, '');
  v = v.replace(/:[0-9]+$/, '');
  return v;
}

function parseSshAndUdpUsage() {
  const ipMap = new Map();
  const sessionMap = new Map();

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
      addSessionKeyToUserMap(sessionMap, user, `sshd-pid:${pid}`);
      for (const ip of (pidIpMap.get(pid) || [])) {
        addIpToUserMap(ipMap, user, ip);
        addSessionKeyToUserMap(sessionMap, user, `sshd-ip:${ip}`);
      }
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
    addIpToUserMap(ipMap, user, host);
    addSessionKeyToUserMap(sessionMap, user, `who:${host || 'local'}`);
  }

  // UDP Custom realtime (short window) from journal.
  let jOut = '';
  try {
    jOut = execFileSync(
      'journalctl',
      ['-u', UDPCUSTOM_SERVICE, '--since', '-20 min', '-n', '300', '--no-pager'],
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
    const ip = extractIp(src);
    addIpToUserMap(ipMap, user, ip);
    // Count UDP sessions by source IP (not src port) to avoid false multi-login on reconnect.
    if (ip) addSessionKeyToUserMap(sessionMap, user, `udp-ip:${ip}`);
  }
  return { ipMap, sessionMap };
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

function shouldRestartZivpn() {
  if (ACTIVE_UDP_BACKEND === 'udpcustom' || ACTIVE_UDP_BACKEND === 'udp-custom' || ACTIVE_UDP_BACKEND === 'udphc') {
    return false;
  }
  if (ACTIVE_UDP_BACKEND === 'zivpn') return true;
  return safeExec('systemctl', ['is-active', '--quiet', ZIVPN_SERVICE]);
}

function getUdpCustomListenPort() {
  try {
    if (!fs.existsSync(UDPCUSTOM_CONFIG)) return UDPCUSTOM_LISTEN_PORT;
    const root = JSON.parse(fs.readFileSync(UDPCUSTOM_CONFIG, 'utf8'));
    const raw = String(root?.listen || '').trim();
    const m = raw.match(/^:([0-9]{1,5})$/);
    if (!m) return UDPCUSTOM_LISTEN_PORT;
    const n = Number(m[1]);
    if (!Number.isInteger(n) || n < 1 || n > 65535) return UDPCUSTOM_LISTEN_PORT;
    return n;
  } catch (_) {
    return UDPCUSTOM_LISTEN_PORT;
  }
}

function isIpv6(ip) {
  return String(ip || '').includes(':');
}

function nftDropSnippet(ip, port) {
  const fam = isIpv6(ip) ? 'ip6' : 'ip';
  return `${fam} saddr ${ip} udp dport ${port} drop`;
}

function detectNftInputChain() {
  if (safeExec('nft', ['list', 'chain', 'inet', 'filter', 'input'])) {
    return ['inet', 'filter', 'input'];
  }
  if (safeExec('nft', ['list', 'chain', 'ip', 'filter', 'input'])) {
    return ['ip', 'filter', 'input'];
  }
  return null;
}

function addNftUdpDropRule(ip, port) {
  const chain = detectNftInputChain();
  if (!chain) return false;
  const src = String(ip || '').trim();
  const dport = String(port);
  const fam = isIpv6(src) ? 'ip6' : 'ip';
  const chainDump = readExec('nft', ['list', 'chain', ...chain]);
  if (chainDump.includes(nftDropSnippet(src, dport))) return true;
  return safeExec('nft', ['add', 'rule', ...chain, fam, 'saddr', src, 'udp', 'dport', dport, 'drop']);
}

function removeNftUdpDropRule(ip, port) {
  const chain = detectNftInputChain();
  if (!chain) return;
  const src = String(ip || '').trim();
  const dport = String(port);
  const fam = isIpv6(src) ? 'ip6' : 'ip';
  while (safeExec('nft', ['delete', 'rule', ...chain, fam, 'saddr', src, 'udp', 'dport', dport, 'drop'])) {}
}

function addUdpDropRule(ip, port) {
  const src = String(ip || '').trim();
  if (!src) return false;
  if (safeExec('iptables', ['-L'])) {
    const cmd = isIpv6(src) ? 'ip6tables' : 'iptables';
    const rule = ['INPUT', '-p', 'udp', '-s', src, '--dport', String(port), '-j', 'DROP'];
    if (safeExec(cmd, ['-C', ...rule])) return true;
    return safeExec(cmd, ['-I', ...rule]);
  }
  if (safeExec('nft', ['list', 'ruleset'])) {
    return addNftUdpDropRule(src, port);
  }
  return false;
}

function removeUdpDropRule(ip, port) {
  const src = String(ip || '').trim();
  if (!src) return;
  if (safeExec('iptables', ['-L'])) {
    const cmd = isIpv6(src) ? 'ip6tables' : 'iptables';
    const rule = ['INPUT', '-p', 'udp', '-s', src, '--dport', String(port), '-j', 'DROP'];
    while (safeExec(cmd, ['-D', ...rule])) {}
    return;
  }
  if (safeExec('nft', ['list', 'ruleset'])) {
    removeNftUdpDropRule(src, port);
  }
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
  await run(`CREATE TABLE IF NOT EXISTS temp_ip_lock_ips (
    account_type TEXT NOT NULL,
    username TEXT NOT NULL,
    ip TEXT NOT NULL,
    PRIMARY KEY (account_type, username, ip)
  )`);
}

async function unlockExpired(nowTs) {
  const rows = await all("SELECT account_type, username, zivpn_removed FROM temp_ip_locks WHERE locked_until <= ?", [nowTs]);
  if (rows.length === 0) return { xrayChanged: false, zivpnChanged: false };

  const udpcustomPort = getUdpCustomListenPort();
  let xrayChanged = false;
  let zivpnChanged = false;
  for (const row of rows) {
    const t = String(row.account_type || '');
    const u = String(row.username || '');
    if (t === 'ssh') {
      const ipRows = await all("SELECT ip FROM temp_ip_lock_ips WHERE account_type='ssh' AND username=?", [u]).catch(() => []);
      for (const item of ipRows) {
        removeUdpDropRule(String(item?.ip || ''), udpcustomPort);
      }
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
    await run("DELETE FROM temp_ip_lock_ips WHERE account_type=? AND username=?", [t, u]).catch(() => {});
    await run("DELETE FROM temp_ip_locks WHERE account_type=? AND username=?", [t, u]).catch(() => {});
  }
  return { xrayChanged, zivpnChanged };
}

async function lockIfExceeded(nowTs) {
  const sshUsage = parseSshAndUdpUsage();
  const sshIpMap = sshUsage.ipMap;
  const sshSessionMap = sshUsage.sessionMap;
  const xrayMap = parseXrayRecentIpMap();
  const udpcustomPort = getUdpCustomListenPort();
  let xrayChanged = false;
  let zivpnChanged = false;

  const sshRows = await all("SELECT username, limitip FROM account_sshs WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' AND CAST(COALESCE(limitip,0) AS INTEGER) > 0");
  for (const r of sshRows) {
    const user = String(r.username || '').trim();
    const userKey = user.toLowerCase();
    const lim = Number(r.limitip || 0);
    const cntIp = sshIpMap.has(userKey) ? sshIpMap.get(userKey).size : 0;
    const cntSession = sshSessionMap.has(userKey) ? sshSessionMap.get(userKey).size : 0;
    const cnt = Math.max(cntIp, cntSession);
    if (cnt <= lim) continue;
    const exists = await get("SELECT 1 AS ok FROM temp_ip_locks WHERE account_type='ssh' AND username=?", [user]);
    if (exists) continue;

    // Putuskan sesi aktif SSH user yang baru di-lock.
    safeExec('pkill', ['-KILL', '-u', user]);
    safeExec('passwd', ['-l', user]);

    // Untuk UDPHC: drop semua src IP aktif user ini selama masa lock.
    const lockIps = Array.from(sshIpMap.get(userKey) || []);
    await run("DELETE FROM temp_ip_lock_ips WHERE account_type='ssh' AND username=?", [user]).catch(() => {});
    for (const ip of lockIps) {
      if (addUdpDropRule(ip, udpcustomPort)) {
        await run("INSERT OR IGNORE INTO temp_ip_lock_ips(account_type, username, ip) VALUES('ssh', ?, ?)", [user, ip]).catch(() => {});
      }
    }

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
  if ((u.zivpnChanged || l.zivpnChanged) && shouldRestartZivpn()) {
    restartService(ZIVPN_SERVICE);
  }
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
Description=Run SC 1FORCR IP Limit Checker every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
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

setup_auto_reboot_timer() {
  log "Setup auto reboot harian jam 03:00..."

  cat > /usr/local/sbin/sc-1forcr-safe-reboot <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

logger -t sc-1forcr "Auto reboot timer triggered (03:00)."
sync
sleep 2
/usr/bin/systemctl --force reboot
EOF
  chmod +x /usr/local/sbin/sc-1forcr-safe-reboot

  cat > /etc/systemd/system/sc-1forcr-autoreboot.service <<'EOF'
[Unit]
Description=SC 1FORCR Safe Auto Reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sc-1forcr-safe-reboot
NoNewPrivileges=true
PrivateTmp=true
EOF

  cat > /etc/systemd/system/sc-1forcr-autoreboot.timer <<'EOF'
[Unit]
Description=Run SC 1FORCR auto reboot at 03:00 daily

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
AccuracySec=1min
Unit=sc-1forcr-autoreboot.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now sc-1forcr-autoreboot.timer
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
ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND}
ZIVPN_DNAT_RANGE=${ZIVPN_DNAT_RANGE}
UDPCUSTOM_DNAT_RANGE=${UDPCUSTOM_DNAT_RANGE}
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
ZIVPN_DNAT_RANGE="${ZIVPN_DNAT_RANGE:-6000:19999}"
UDPCUSTOM_DNAT_RANGE="${UDPCUSTOM_DNAT_RANGE:-}"

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
endpoint_unlock() {
  case "$1" in
    ssh|zivpn) echo "/unlocksshvpn" ;;
    vmess) echo "/unlockvmess" ;;
    vless) echo "/unlockvless" ;;
    trojan) echo "/unlocktrojan" ;;
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

print_account_picker_table() {
  local type="$1" lock_only="${2:-0}" table where rows
  table="$(account_table_by_type "${type}")"
  [[ -z "${table}" ]] && return 1
  where=""
  if [[ "${lock_only}" == "1" ]]; then
    where="WHERE UPPER(TRIM(COALESCE(status,''))) IN ('LOCK','LOCK_TMP')"
  fi
  rows="$(sqlite3 -separator '|' "$DB_PATH" \
    "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)), UPPER(TRIM(COALESCE(status,''))) FROM ${table} ${where} ORDER BY username;" 2>/dev/null || true)"
  if [[ -z "${rows}" ]]; then
    return 1
  fi
  printf "%-4s %-24s %-10s %-8s\n" "NO" "USERNAME" "STATUS" "SISA"
  printf "%-4s %-24s %-10s %-8s\n" "----" "------------------------" "----------" "--------"
  local i=0 u sisa st
  while IFS='|' read -r u sisa st; do
    [[ -z "${u}" ]] && continue
    i=$((i + 1))
    printf "%-4s %-24s %-10s %-8s\n" "${i}" "${u}" "${st:-AKTIF}" "${sisa:-0}h"
  done <<< "${rows}"
  return 0
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

  echo "LIST AKUN ${type^^}" >&2
  if ! print_account_picker_table "${type}" "0" >&2; then
    echo "Tidak ada data akun untuk ditampilkan." >&2
  fi
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

pick_locked_username() {
  local type="$1" table rows input username
  table="$(account_table_by_type "${type}")"
  [[ -z "${table}" ]] && return 1

  rows="$(sqlite3 "$DB_PATH" "SELECT username FROM ${table} WHERE UPPER(TRIM(COALESCE(status,''))) IN ('LOCK','LOCK_TMP') ORDER BY username;" 2>/dev/null || true)"
  if [[ -z "${rows}" ]]; then
    echo "Tidak ada akun ${type} dengan status LOCK/LOCK_TMP." >&2
    return 1
  fi

  echo "LIST AKUN LOCK ${type^^}" >&2
  if ! print_account_picker_table "${type}" "1" >&2; then
    echo "Tidak ada data lock untuk ditampilkan." >&2
  fi
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
  echo "RENEW AKUN ${type^^}"
  username="$(pick_existing_username "$type")" || return
  printf "%-12s : %s\n" "Username" "${username}"
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
  echo "DELETE AKUN ${type^^}"
  username="$(pick_existing_username "$type")" || return
  printf "%-12s : %s\n" "Username" "${username}"
  api_call "DELETE" "${ep}/${username}" | jq .
}

unlock_account() {
  local type ep username
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_unlock "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint unlock tidak ada."; return; }
  username="$(pick_locked_username "$type")" || return
  echo "Unlock akun: ${username}"
  api_call "PATCH" "${ep}/${username}" | jq .
}

list_accounts() {
  print_account_table() {
    local table="$1" title="$2" rows
    rows="$(sqlite3 -separator '|' "$DB_PATH" \
      "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday('now','localtime')) AS INTEGER)), UPPER(TRIM(COALESCE(status,''))) FROM ${table} ORDER BY username;" 2>/dev/null || true)"
    echo "LIST AKUN ${title}"
    printf "%-4s %-24s %-10s %-8s\n" "NO" "USERNAME" "STATUS" "SISA"
    printf "%-4s %-24s %-10s %-8s\n" "----" "------------------------" "----------" "--------"
    if [[ -z "${rows}" ]]; then
      echo "(kosong)"
      return
    fi
    local i=0 u sisa st
    while IFS='|' read -r u sisa st; do
      [[ -z "${u}" ]] && continue
      i=$((i + 1))
      printf "%-4s %-24s %-10s %-8s\n" "${i}" "${u}" "${st:-AKTIF}" "${sisa:-0}h"
    done <<< "${rows}"
  }

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
      print_account_table "account_sshs" "SSH/ZIVPN"
      ;;
    2)
      print_account_table "account_vmesses" "VMESS"
      ;;
    3)
      print_account_table "account_vlesses" "VLESS"
      ;;
    4)
      print_account_table "account_trojans" "TROJAN"
      ;;
    5)
      echo "LIST AKUN ZIVPN auth.config"
      printf "%-4s %-24s\n" "NO" "USERNAME"
      printf "%-4s %-24s\n" "----" "------------------------"
      if [[ -f /etc/zivpn/config.json ]]; then
        jq -r '.auth.config[]?' /etc/zivpn/config.json | nl -w1 -s' ' || true
      else
        echo "File /etc/zivpn/config.json tidak ditemukan."
      fi
      ;;
    6)
      print_account_table "account_sshs" "SSH/ZIVPN"
      echo
      print_account_table "account_vmesses" "VMESS"
      echo
      print_account_table "account_vlesses" "VLESS"
      echo
      print_account_table "account_trojans" "TROJAN"
      echo
      echo "LIST AKUN ZIVPN auth.config"
      printf "%-4s %-24s\n" "NO" "USERNAME"
      printf "%-4s %-24s\n" "----" "------------------------"
      if [[ -f /etc/zivpn/config.json ]]; then
        jq -r '.auth.config[]?' /etc/zivpn/config.json | nl -w1 -s' ' || true
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

cleanup_zivpn_dnat_for_udphc() {
  local udphc_port range_nft handle
  udphc_port="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  [[ -z "${udphc_port}" ]] && udphc_port="5667"
  if command -v iptables >/dev/null 2>&1; then
    while iptables -t nat -C PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${udphc_port}" >/dev/null 2>&1; do
      iptables -t nat -D PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${udphc_port}" >/dev/null 2>&1 || break
    done
  elif command -v nft >/dev/null 2>&1; then
    range_nft="${ZIVPN_DNAT_RANGE/:/-}"
    while IFS= read -r handle; do
      [[ -z "${handle}" ]] && continue
      nft delete rule ip nat prerouting handle "${handle}" >/dev/null 2>&1 || true
    done < <(
      nft -a list chain ip nat prerouting 2>/dev/null | \
        awk -v sig="udp dport ${range_nft} dnat to :${udphc_port}" '$0 ~ sig {for (i=1;i<=NF;i++) if ($i=="handle") print $(i+1)}'
    )
  fi
}

ensure_zivpn_dnat_for_zivpn() {
  local zivpn_port range_nft
  [[ -z "${ZIVPN_DNAT_RANGE}" ]] && return 0
  zivpn_port="$(jq -r '.listen // empty' /etc/zivpn/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  [[ -z "${zivpn_port}" ]] && zivpn_port="5667"

  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p udp --dport "${zivpn_port}" -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p udp --dport "${zivpn_port}" -j ACCEPT
    iptables -t nat -C PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${zivpn_port}" >/dev/null 2>&1 || \
      iptables -t nat -I PREROUTING -p udp --dport "${ZIVPN_DNAT_RANGE}" -j DNAT --to-destination ":${zivpn_port}"
  elif command -v nft >/dev/null 2>&1; then
    range_nft="${ZIVPN_DNAT_RANGE/:/-}"
    nft add table ip nat >/dev/null 2>&1 || true
    nft 'add chain ip nat prerouting { type nat hook prerouting priority dstnat; }' >/dev/null 2>&1 || true
    if nft list chain inet filter input >/dev/null 2>&1; then
      nft list chain inet filter input | grep -F -- "udp dport ${zivpn_port} accept" >/dev/null 2>&1 || \
        nft add rule inet filter input udp dport "${zivpn_port}" accept
    elif nft list chain ip filter input >/dev/null 2>&1; then
      nft list chain ip filter input | grep -F -- "udp dport ${zivpn_port} accept" >/dev/null 2>&1 || \
        nft add rule ip filter input udp dport "${zivpn_port}" accept
    fi
    nft list chain ip nat prerouting 2>/dev/null | grep -F -- "udp dport ${range_nft} dnat to :${zivpn_port}" >/dev/null 2>&1 || \
      nft add rule ip nat prerouting udp dport "${range_nft}" dnat to ":${zivpn_port}"
  fi
}

switch_udp_to_zivpn() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  systemctl disable --now "${udpcustom}" >/dev/null 2>&1 || true
  systemctl enable "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  ensure_zivpn_dnat_for_zivpn
  echo "Mode UDP aktif: ZIVPN (UDPHC dimatikan)."
}

switch_udp_to_udpcustom() {
  local udpcustom
  udpcustom="$(detect_udpcustom_service)"
  systemctl disable --now "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  systemctl enable "${udpcustom}" >/dev/null 2>&1 || true
  systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
  if [[ -z "${UDPCUSTOM_DNAT_RANGE}" ]]; then
    cleanup_zivpn_dnat_for_udphc
  fi
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

udp_port_from_config() {
  local cfg="$1" fallback="$2" port
  port="${fallback}"
  if [[ -f "${cfg}" ]]; then
    port="$(jq -r '.listen // empty' "${cfg}" 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  fi
  [[ -z "${port}" ]] && port="${fallback}"
  echo "${port}"
}

is_udp_port_listening() {
  local port="$1"
  ss -lunp 2>/dev/null | awk -v p=":${port}" '$5 ~ p"$" {ok=1} END {exit(ok?0:1)}'
}

diagnose_udp_backends() {
  local udpcustom zstat ustat zport uport
  udpcustom="$(detect_udpcustom_service)"
  zstat="$(systemctl is-active "${ZIVPN_SERVICE}" 2>/dev/null || true)"
  ustat="$(systemctl is-active "${udpcustom}" 2>/dev/null || true)"
  zport="$(udp_port_from_config /etc/zivpn/config.json 5667)"
  uport="$(udp_port_from_config /root/udp/config.json 5667)"

  echo "=== DIAGNOSE UDP BACKEND ==="
  echo "ZIVPN service   : ${ZIVPN_SERVICE} (${zstat:-unknown})"
  echo "UDPHC service   : ${udpcustom} (${ustat:-unknown})"
  echo "ZIVPN port      : ${zport} ($(is_udp_port_listening "${zport}" && echo LISTEN || echo NO-LISTEN))"
  echo "UDPHC port      : ${uport} ($(is_udp_port_listening "${uport}" && echo LISTEN || echo NO-LISTEN))"
  echo
  echo "NAT PREROUTING (ringkas):"
  if command -v iptables >/dev/null 2>&1; then
    iptables -t nat -S PREROUTING 2>/dev/null | grep -E 'DNAT|5667|5668|6000:19999' || echo "(tidak ada rule terkait)"
  elif command -v nft >/dev/null 2>&1; then
    nft list chain ip nat prerouting 2>/dev/null | grep -E 'dnat|5667|5668|6000-19999' || echo "(tidak ada rule terkait)"
  else
    echo "(iptables/nft tidak tersedia)"
  fi
  echo
  if [[ "${zstat}" != "active" ]]; then
    echo "--- log ${ZIVPN_SERVICE} ---"
    journalctl -u "${ZIVPN_SERVICE}" -n 25 --no-pager 2>/dev/null || true
  fi
  if [[ "${ustat}" != "active" ]]; then
    echo "--- log ${udpcustom} ---"
    journalctl -u "${udpcustom}" -n 25 --no-pager 2>/dev/null || true
  fi
}

repair_udp_backends() {
  local udpcustom zstat ustat chosen preferred
  udpcustom="$(detect_udpcustom_service)"
  zstat="$(systemctl is-active "${ZIVPN_SERVICE}" 2>/dev/null || true)"
  ustat="$(systemctl is-active "${udpcustom}" 2>/dev/null || true)"
  preferred="$(echo "${ACTIVE_UDP_BACKEND:-zivpn}" | tr '[:upper:]' '[:lower:]')"
  chosen=""

  echo "Auto-repair UDP backend..."
  systemctl daemon-reload >/dev/null 2>&1 || true

  if [[ "${zstat}" == "active" && "${ustat}" == "active" ]]; then
    # Single backend policy: default ke ZIVPN saat bentrok.
    systemctl disable --now "${udpcustom}" >/dev/null 2>&1 || true
    systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    chosen="zivpn"
  elif [[ "${zstat}" == "active" ]]; then
    systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    chosen="zivpn"
  elif [[ "${ustat}" == "active" ]]; then
    systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
    chosen="udphc"
  else
    # Tidak ada aktif: prioritaskan backend sesuai ACTIVE_UDP_BACKEND.
    if [[ "${preferred}" == "udpcustom" || "${preferred}" == "udp-custom" || "${preferred}" == "udphc" ]]; then
      systemctl enable "${udpcustom}" >/dev/null 2>&1 || true
      if systemctl restart "${udpcustom}" >/dev/null 2>&1; then
        chosen="udphc"
      else
        systemctl enable "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
        systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
        chosen="zivpn"
      fi
    else
      systemctl enable "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
      if systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1; then
        chosen="zivpn"
      else
        systemctl enable "${udpcustom}" >/dev/null 2>&1 || true
        systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
        chosen="udphc"
      fi
    fi
  fi

  sleep 1
  echo "Backend dipilih: ${chosen:-unknown}"
  diagnose_udp_backends
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
  echo "7) diagnose + auto-repair UDP backend"
  prompt_input s "Pilih [1-7]: " || return
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
    7)
      repair_udp_backends
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
  VNSTAT_MONTH_TOTAL="-"
  VNSTAT_MONTH_NAME="$(date +%B 2>/dev/null || echo "-")"
  VNSTAT_DAY_RX="-"
  VNSTAT_DAY_TX="-"
  VNSTAT_DAY_TOTAL="-"
  VNSTAT_DAY_NAME="$(date +%A 2>/dev/null || echo "-")"
  VNSTAT_RATE="-"
  VNSTAT_IFACE="-"
  if ! command -v vnstat >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return
  fi

  local js rx tx drx dtx iface rate5m mtotal dtotal
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
  if [[ "${rx}" =~ ^[0-9]+$ && "${tx}" =~ ^[0-9]+$ ]]; then
    mtotal="$((rx + tx))"
    VNSTAT_MONTH_TOTAL="$(bytes_human "${mtotal}")"
  fi
  if [[ "${drx}" =~ ^[0-9]+$ && "${dtx}" =~ ^[0-9]+$ ]]; then
    dtotal="$((drx + dtx))"
    VNSTAT_DAY_TOTAL="$(bytes_human "${dtotal}")"
  fi
  rate5m="$(echo "${js}" | jq -r '(.interfaces[0].traffic.fiveminute // [] | last | ((.rx // 0) + (.tx // 0)))' 2>/dev/null || echo 0)"
  if [[ "${rate5m}" =~ ^[0-9]+$ && "${rate5m}" -gt 0 ]]; then
    VNSTAT_RATE="$(awk -v b="${rate5m}" 'BEGIN { printf "%.2f Mbit/s", (b*8)/(300*1000000) }')"
  fi
}

draw_dashboard() {
  local os_name ram_mb swap_mb uptime_s uptime_h uptime_m
  local ip city isp udpcustom
  local ssh_on xray_on ws_on loadblc_on zivpn_on udphc_on
  local c_ssh c_vmess c_vless c_trojan
  local health
  local line

  # Color definitions
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local BLUE='\033[0;34m'
  local CYAN='\033[0;36m'
  local BOLD='\033[1m'
  local NC='\033[0m'
  local CHECK="${YELLOW}CHECK${NC}"
  local GOOD="${GREEN}GOOD${NC}"

  # Data collection
  os_name="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Unknown}")"
  ram_mb="$(free -m 2>/dev/null | awk '/^Mem:/ {print $3 "M"}')"
  swap_mb="$(free -m 2>/dev/null | awk '/^Swap:/ {print $3 "M"}')"
  uptime_s="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
  uptime_h="$((uptime_s / 3600))"
  uptime_m="$(((uptime_s % 3600) / 60))"

  ip="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  ip="${ip:-unknown}"
  city="$(curl -fsS --max-time 3 https://ipinfo.io/city 2>/dev/null || echo "-")"
  isp="$(curl -fsS --max-time 3 https://ipinfo.io/org 2>/dev/null || echo "-")"

  udpcustom="$(detect_udpcustom_service)"
  ssh_on="$(onoff_word ssh)"
  xray_on="$(onoff_word xray)"
  ws_on="$(onoff_word sc-1forcr-sshws)"
  loadblc_on="$(onoff_word haproxy)"
  zivpn_on="$(onoff_word "${ZIVPN_SERVICE}")"
  udphc_on="$(onoff_word "${udpcustom}")"

  health="CHECK"
  if [[ "${xray_on}" == "ON" && "${ws_on}" == "ON" && "${loadblc_on}" == "ON" ]]; then
    health="GOOD"
  fi
  local health_display="${CHECK}"
  [[ "${health}" == "GOOD" ]] && health_display="${GOOD}"

  c_ssh="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_sshs;" 2>/dev/null || echo 0)"
  c_vmess="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_vmesses;" 2>/dev/null || echo 0)"
  c_vless="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_vlesses;" 2>/dev/null || echo 0)"
  c_trojan="$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM account_trojans;" 2>/dev/null || echo 0)"

  read_vnstat_stats

  # Helper for separator (without right border)
  hr() {
    printf "├─────────────────────────────────────────────────\n"
  }

  # Dashboard - no closing pipe on the right
  printf "┌─────────────────────────────────────────────────\n"
  printf "│${BOLD}             SC 1FORCR NEXUS DASHBOARD            ${NC}\n"
  printf "├─────────────────────────────────────────────────\n"

  # System & Network
  printf "│ ${CYAN}${BOLD}■ SYSTEM & NETWORK${NC}${BOLD}${NC}                                  \n"
  printf "│   OS      : ${os_name}${NC}                              \n"
  printf "│   RAM     : ${ram_mb:-"-"}  │ SWAP : ${swap_mb:-"-"}${NC}                         \n"
  printf "│   UPTIME  : ${uptime_h}h ${uptime_m}m${NC}                                           \n"
  hr
  printf "│ ${CYAN}${BOLD}■ LOCATION & ISP${NC}${BOLD}${NC}                                    \n"
  printf "│   IP      : ${ip}${NC}                                                \n"
  printf "│   CITY    : ${city}${NC}                                              \n"
  printf "│   ISP     : ${isp}${NC}                                              \n"
  printf "│   DOMAIN  : ${DOMAIN}${NC}                                           \n"
  hr

  # Traffic Stats
  printf "│ ${CYAN}${BOLD}■ TRAFFIC STATS${NC}${BOLD}${NC}                                     \n"
  printf "│   MONTH   : ${VNSTAT_MONTH_TOTAL}     [${VNSTAT_MONTH_NAME}]${NC}                 \n"
  printf "│   RX      : ${VNSTAT_MONTH_RX}${NC}                                              \n"
  printf "│   TX      : ${VNSTAT_MONTH_TX}${NC}                                              \n"
  printf "│   DAY     : ${VNSTAT_DAY_TOTAL}     [${VNSTAT_DAY_NAME}]${NC}                    \n"
  printf "│   RX      : ${VNSTAT_DAY_RX}${NC}                                               \n"
  printf "│   TX      : ${VNSTAT_DAY_TX}${NC}                                               \n"
  printf "│   CURRENT : ${VNSTAT_RATE}${NC}                                              \n"
  hr

  # Services Status (includes zivpn and udphc)
  printf "│ ${CYAN}${BOLD}■ SERVICES STATUS${NC}${BOLD}${NC}                                   \n"
  local xray_color="${GREEN}ON${NC}"; [[ "$xray_on" != "ON" ]] && xray_color="${RED}OFF${NC}"
  local ws_color="${GREEN}ON${NC}";   [[ "$ws_on" != "ON" ]] && ws_color="${RED}OFF${NC}"
  local lb_color="${GREEN}ON${NC}";   [[ "$loadblc_on" != "ON" ]] && lb_color="${RED}OFF${NC}"
  local zivpn_color="${GREEN}ON${NC}"; [[ "$zivpn_on" != "ON" ]] && zivpn_color="${RED}OFF${NC}"
  local udphc_color="${GREEN}ON${NC}"; [[ "$udphc_on" != "ON" ]] && udphc_color="${RED}OFF${NC}"
  local ssh_color="${GREEN}ON${NC}";   [[ "$ssh_on" != "ON" ]] && ssh_color="${RED}OFF${NC}"

  printf "│   XRAY    : ${xray_color}   │ SSH-WS : ${ws_color}   │ LOADBLC : ${lb_color}   \n"
  printf "│   ZIVPN   : ${zivpn_color}   │ UDPHC  : ${udphc_color}   │ SSH    : ${ssh_color}   │ HEALTH : ${health_display}${NC} \n"
  hr

  # Account Summary
  printf "│ ${CYAN}${BOLD}■ ACCOUNT SUMMARY${NC}${BOLD}${NC}                                   \n"
  printf "│   SSH/OpenVPN : %-4s     │ VMESS : %-4s     \n" "${c_ssh}" "${c_vmess}"
  printf "│   VLESS       : %-4s     │ TROJAN: %-4s     \n" "${c_vless}" "${c_trojan}"
  hr

  # Version & Client
  printf "│ ${BLUE}${BOLD}■ VERSION & CLIENT${NC}${BOLD}${NC}                                  \n"
  printf "│   Version     : ${SCRIPT_VERSION:-unknown}${NC}                                 \n"
  printf "│   Order By    : SC 1FORCR${NC}                                               \n"
  printf "│   Client Name : ${ip}${NC}                                                \n"
  printf "│   Expiry In   : Unlimited${NC}                                              \n"
  printf "└─────────────────────────────────────────────────\n"
  printf " ─────────────────────────────────────────────────\n"
  printf "           ${BOLD}to access use 'menu' command${NC}\n"
  printf " ─────────────────────────────────────────────────\n"
}
show_combined_online() {
  local mode tmp_count tmp_status tmp_ssh_pid_ip tmp_pid_user tmp_ssh_pair tmp_ssh_count tmp_ssh_proc_count tmp_ssh_count_merged tmp_udp_pair tmp_udp_count udpcustom udp_ttl
  mode="${1:-realtime}"
  udp_ttl="180"
  udpcustom="$(detect_udpcustom_service)"

  tmp_count="$(mktemp)"
  tmp_status="$(mktemp)"
  tmp_ssh_pid_ip="$(mktemp)"
  tmp_pid_user="$(mktemp)"
  tmp_ssh_pair="$(mktemp)"
  tmp_ssh_count="$(mktemp)"
  tmp_ssh_proc_count="$(mktemp)"
  tmp_ssh_count_merged="$(mktemp)"
  tmp_udp_pair="$(mktemp)"
  tmp_udp_count="$(mktemp)"
  trap 'rm -f "${tmp_count:-}" "${tmp_status:-}" "${tmp_ssh_pid_ip:-}" "${tmp_pid_user:-}" "${tmp_ssh_pair:-}" "${tmp_ssh_count:-}" "${tmp_ssh_proc_count:-}" "${tmp_ssh_count_merged:-}" "${tmp_udp_pair:-}" "${tmp_udp_count:-}"' RETURN

  # SSH realtime: map pid->user dan pid->remote_ip, lalu pisahkan dari pasangan user+ip UDPHC aktif.
  : > "${tmp_ssh_pair}"
  : > "${tmp_ssh_count}"
  ss -Htnp state established 2>/dev/null | awk '
    {
      l=$4;
      r=$5;
      if (l ~ /:22$/ || l ~ /:109$/ || l ~ /:143$/) {
        ip=r;
        gsub(/^\[/, "", ip);
        gsub(/\]$/, "", ip);
        sub(/:[0-9]+$/, "", ip);
        if (ip == "") next;
        s=$0;
        while (match(s, /pid=[0-9]+/)) {
          pid=substr(s, RSTART + 4, RLENGTH - 4);
          if (pid ~ /^[0-9]+$/) print pid, ip;
          s=substr(s, RSTART + RLENGTH);
        }
      }
    }' | sort -u > "${tmp_ssh_pid_ip}" || true

  if [[ -s "${tmp_ssh_pid_ip}" ]]; then
    local pid_csv
    pid_csv="$(awk '{print $1}' "${tmp_ssh_pid_ip}" | sort -u | paste -sd, -)"
    ps -o pid=,args= -p "${pid_csv}" 2>/dev/null | awk '
      {
        pid=$1;
        $1="";
        sub(/^[[:space:]]+/, "", $0);
        u="";
        if ($0 ~ /^sshd:/) {
          u=$0;
          sub(/^sshd:[[:space:]]*/, "", u);
          sub(/[[:space:]].*$/, "", u);
          sub(/@.*$/, "", u);
          sub(/\[.*$/, "", u);
        } else if ($0 ~ /^dropbear/) {
          u=$0;
          if (u !~ /\[[^]]+\]/) next;
          sub(/^.*\[/, "", u);
          sub(/\].*$/, "", u);
        } else next;
        u=tolower(u);
        if (u !~ /^[a-z0-9._-]+$/) next;
        if (u == "root" || u == "priv" || u == "net") next;
        print pid, u;
      }' > "${tmp_pid_user}" || true

    awk '
      NR==FNR { u[$1]=$2; next }
      {
        pid=$1; ip=$2; user=(pid in u ? u[pid] : "");
        if (user != "" && ip != "") print user, ip;
      }' "${tmp_pid_user}" "${tmp_ssh_pid_ip}" | sort -u > "${tmp_ssh_pair}" || true
  fi

  # UDP Custom: pair connected/disconnected by src, lalu expire sesi lama (anti ghost session).
  : > "${tmp_udp_pair}"
  : > "${tmp_udp_count}"
  if [[ "${mode}" == "history" ]]; then
    udp_ttl="3600"
    journalctl -u "${udpcustom}" -n 2400 -o short-unix --no-pager 2>/dev/null
  else
    udp_ttl="180"
    journalctl -u "${udpcustom}" --since "-8 min" -n 800 -o short-unix --no-pager 2>/dev/null
  fi | awk -v ttl="${udp_ttl}" '
    function norm_user(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
      v=tolower(v);
      if (v ~ /^[a-z0-9._-]+$/ && v != "root") return v;
      return "";
    }
    BEGIN {
      now=systime();
      if (ttl <= 0) ttl=180;
    }
    function ip_only(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
      gsub(/^\[/, "", v);
      gsub(/\]$/, "", v);
      sub(/:[0-9]+$/, "", v);
      return v;
    }
    {
      ts=$1;
      sub(/\..*$/, "", ts);
      if (ts !~ /^[0-9]+$/) ts=now;
      line=$0;
      src=""; u=""; ip=""; key="";
      if (line ~ /\[src:[^]]+\][[:space:]]+\[user:[^]]+\][[:space:]]+Client connected/) {
        src=line;
        sub(/^.*\[src:/, "", src);
        sub(/\].*$/, "", src);
        u=line;
        sub(/^.*\[user:/, "", u);
        sub(/\].*$/, "", u);
        u=norm_user(u);
        ip=ip_only(src);
        if (src != "" && u != "" && ip != "") {
          key=u "|" ip;
          active[src]=key;
          seen[src]=ts + 0;
        }
        next;
      }
      if (line ~ /\[src:[^]]+\][[:space:]]+Client disconnected/) {
        src=line;
        sub(/^.*\[src:/, "", src);
        sub(/\].*$/, "", src);
        if (src in active) delete active[src];
        if (src in seen) delete seen[src];
        next;
      }
    }
    END {
      for (s in active) {
        age=now - (s in seen ? seen[s] : now);
        if (age > ttl) continue;
        key=active[s];
        if (key == "") continue;
        uniq[key]=1;
      }
      for (k in uniq) {
        split(k, a, /\|/);
        u=a[1]; ip=a[2];
        if (u != "" && ip != "") print u, ip;
      }
    }' > "${tmp_udp_pair}" || true

  awk '{ if ($1 ~ /^[a-z0-9._-]+$/ && $2 != "") cnt[$1]++ } END { for (u in cnt) print u, cnt[u]; }' "${tmp_udp_pair}" > "${tmp_udp_count}" || true

  # Hitung sesi SSH murni dari pair user+ip hasil socket mapping.
  # Jangan dikurangi dari data UDPHC; dua kolom ditampilkan terpisah.
  awk '{ if ($1 ~ /^[a-z0-9._-]+$/ && $2 != "") cnt[$1]++ } END { for (u in cnt) print u, cnt[u]; }' "${tmp_ssh_pair}" > "${tmp_ssh_count}" || true

  # Fallback untuk SSH-WS/HC: ambil sesi dari process list bila mapping socket->user tidak terbaca.
  ps -eo args= 2>/dev/null | awk '
    {
      u="";
      if ($0 ~ /^sshd:[[:space:]]+/) {
        # Hitung hanya sesi user, bukan proses helper seperti [priv].
        if ($0 ~ /\[priv\]/ || $0 ~ /\[preauth\]/ || $0 ~ /\[listener\]/) next;
        u=$0;
        sub(/^sshd:[[:space:]]*/, "", u);
        sub(/[[:space:]].*$/, "", u);
        sub(/@.*$/, "", u);
        sub(/\[.*$/, "", u);
      } else if ($0 ~ /^dropbear[[:space:]]+\[[^]]+\]/) {
        u=$0;
        sub(/^dropbear[[:space:]]+\[/, "", u);
        sub(/\].*$/, "", u);
      } else next;
      u=tolower(u);
      if (u !~ /^[a-z0-9._-]+$/) next;
      if (u == "root" || u == "priv" || u == "net") next;
      cnt[u]++;
    }
    END { for (u in cnt) print u, cnt[u]; }' > "${tmp_ssh_proc_count}" || true

  awk '
    NR==FNR {
      a[$1]=$2 + 0;
      seen[$1]=1;
      next
    }
    {
      b[$1]=$2 + 0;
      seen[$1]=1;
    }
    END {
      for (u in seen) {
        x=(u in a ? a[u] : 0);
        y=(u in b ? b[u] : 0);
        print u, (x > y ? x : y);
      }
    }' "${tmp_ssh_count}" "${tmp_ssh_proc_count}" > "${tmp_ssh_count_merged}" || true
  mv -f "${tmp_ssh_count_merged}" "${tmp_ssh_count}"

  awk '
    NR==FNR {
      u=$1; n=$2 + 0;
      if (u ~ /^[a-z0-9._-]+$/ && n > 0) {
        ssh[u]+=n;
        seen[u]=1;
      }
      next
    }
    {
      u=$1; n=$2 + 0;
      if (u ~ /^[a-z0-9._-]+$/ && n > 0) {
        udp[u]+=n;
        seen[u]=1;
      }
    }
    END {
      for (u in seen) {
        s=ssh[u] + 0;
        d=udp[u] + 0;
        t=s + d;
        if (t > 0) print u, s, d, t;
      }
    }' "${tmp_ssh_count}" "${tmp_udp_count}" > "${tmp_count}" || true

  sqlite3 "${DB_PATH}" "SELECT LOWER(username) || '|' || UPPER(TRIM(COALESCE(status,''))) || '|' || CAST(COALESCE(limitip,0) AS INTEGER) FROM account_sshs;" > "${tmp_status}" 2>/dev/null || true

  echo "Users Login SSH/Dropbear + UDP Custom"

  if [[ ! -s "${tmp_count}" ]]; then
    echo "Tidak ada user online terdeteksi."
    echo
    echo "Total User : 0"
    echo "Total SESI : 0"
    return
  fi

  echo "LIST USER LOGIN"
  printf "%-24s %-12s %-10s %-10s %-10s\n" "USERNAME" "STATUS" "SSH_SESI" "UDPHC" "TOTAL"
  printf "%-24s %-12s %-10s %-10s %-10s\n" "------------------------" "------------" "----------" "----------" "----------"
  awk '
    BEGIN { OFS="|" }
    NR==FNR {
      split($0, a, "|");
      st[a[1]]=a[2];
      lim[a[1]]=a[3] + 0;
      next
    }
    {
      n=split($0, b, /[[:space:]]+/);
      u=b[1];
      ssh=(n >= 2 ? b[2] + 0 : 0);
      udp=(n >= 3 ? b[3] + 0 : 0);
      cnt=(n >= 4 ? b[4] + 0 : (ssh + udp));
      s=(u in st ? st[u] : "AMAN");
      l=(u in lim ? lim[u] : 0);
      if (s == "LOCK" || s == "LOCK_TMP") {
        out="KENA_LOCK";
      } else if (l > 0 && cnt > l) {
        out="MULTI_LOGIN";
      } else {
        out="AMAN";
      }
      printf "%-24s %-12s %-10d %-10d %-10d\n", u, out, ssh, udp, cnt;
    }' "${tmp_status}" "${tmp_count}"

  local total_user total_sesi n
  total_user="$(wc -l < "${tmp_count}" | tr -d ' ')"
  total_sesi=0
  while read -r _ _ _ n; do
    [[ -n "${n:-}" ]] || continue
    total_sesi=$((total_sesi + n))
  done < "${tmp_count}"
  echo
  echo "Total User : ${total_user}"
  echo "Total SESI : ${total_sesi}"
}

show_ssh_online() {
  show_combined_online "realtime"
}

show_ssh_online_history() {
  show_combined_online "history"
}

show_ssh_only_online() {
  local tmp_ssh_count tmp_status
  tmp_ssh_count="$(mktemp)"
  tmp_status="$(mktemp)"
  trap 'rm -f "${tmp_ssh_count:-}" "${tmp_status:-}"' RETURN

  ps -eo args= 2>/dev/null | awk '
    {
      u="";
      if ($0 ~ /^sshd:[[:space:]]+/) {
        if ($0 ~ /\[priv\]/ || $0 ~ /\[preauth\]/ || $0 ~ /\[listener\]/ || $0 ~ /\[accepted\]/) next;
        u=$0;
        sub(/^sshd:[[:space:]]*/, "", u);
        sub(/[[:space:]].*$/, "", u);
        sub(/@.*$/, "", u);
        sub(/\[.*$/, "", u);
      } else if ($0 ~ /^dropbear[[:space:]]+\[[^]]+\]/) {
        u=$0;
        sub(/^dropbear[[:space:]]+\[/, "", u);
        sub(/\].*$/, "", u);
      } else next;
      u=tolower(u);
      if (u !~ /^[a-z0-9._-]+$/) next;
      if (u == "root" || u == "priv" || u == "net") next;
      cnt[u]++;
    }
    END { for (u in cnt) print u, cnt[u]; }' > "${tmp_ssh_count}" || true

  sqlite3 "${DB_PATH}" "SELECT LOWER(username) || '|' || UPPER(TRIM(COALESCE(status,''))) FROM account_sshs;" > "${tmp_status}" 2>/dev/null || true

  echo "LIST USER LOGIN SSH"
  if [[ ! -s "${tmp_ssh_count}" ]]; then
    echo "Tidak ada user SSH online."
    echo
    echo "Total User SSH : 0"
    echo "Total SESI SSH : 0"
    return
  fi

  printf "%-24s %-12s %-10s\n" "USERNAME" "STATUS" "SSH_SESI"
  printf "%-24s %-12s %-10s\n" "------------------------" "------------" "----------"
  awk '
    NR==FNR {
      split($0, a, "|");
      st[a[1]]=a[2];
      next
    }
    {
      u=$1;
      n=$2 + 0;
      s=(u in st ? st[u] : "AMAN");
      out=(s == "LOCK" || s == "LOCK_TMP" ? "KENA_LOCK" : "AMAN");
      printf "%-24s %-12s %-10d\n", u, out, n;
      total_user++;
      total_sesi+=n;
    }
    END {
      print "";
      printf "Total User SSH : %d\n", total_user + 0;
      printf "Total SESI SSH : %d\n", total_sesi + 0;
    }' "${tmp_status}" "${tmp_ssh_count}"
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
  journalctl -u "${udpcustom}" -n 1200 --no-pager 2>/dev/null | \
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
    echo "1) SSH Realtime"
    echo "2) UDP CUSTOM Realtime"
    echo "3) SSH + UDP CUSTOM realtime"
    echo "4) SSH + UDP CUSTOM Gabungan histori"
    echo "5) VMESS"
    echo "6) VLESS"
    echo "7) TROJAN"
    echo "0) Kembali"
    echo
    if ! prompt_input o "Pilih menu [0-7]: "; then
      return
    fi
    clear
    case "${o}" in
      1) show_ssh_only_online ;;
      2) show_udpcustom_online ;;
      3) show_ssh_online ;;
      4) show_ssh_online_history ;;
      5) show_xray_online_by_table "account_vmesses" "VMESS" ;;
      6) show_xray_online_by_table "account_vlesses" "VLESS" ;;
      7) show_xray_online_by_table "account_trojans" "TROJAN" ;;
      0) return ;;
      *) echo "Pilihan tidak valid." ;;
    esac
    echo
    read -rp "Enter untuk lanjut..." _ || true
  done
}

SHOW_FULL_MENU=1

while true; do
  clear
  if [[ "${SHOW_FULL_MENU}" == "1" ]]; then
    draw_dashboard
    echo
  fi

  echo " ┌─────────────────────────────────────────────────"
  echo " │  1.) > ADD ACCOUNT       7.) > CHANGE DOMAIN"
  echo " │  2.) > RENEW ACCOUNT     8.) > MONITOR USER LOCK"
  echo " │  3.) > DELETE ACCOUNT    9.) > MONITOR USER LOGIN"
  echo " │  4.) > LIST ACCOUNT      10.) > TEST SPEED VPS"
  echo " │  5.) > SERVICE MENU      11.) > UPDATE SCRIPT"
  echo " │  6.) > BACKUP/RESTORE    12.) > UNINSTALL"
  echo " │  13.) > UNLOCK ACCOUNT"
  echo " │  m.) > MENU UTAMA"
  echo " │  x.) > EXIT"
  echo " └─────────────────────────────────────────────────"
  if [[ "${SHOW_FULL_MENU}" == "1" ]]; then
    echo " ─────────────────────────────────────────────────"
  fi
  echo
  if ! prompt_input m "Select From Options [1-13, m, x] : "; then
    SHOW_FULL_MENU=0
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
    10) test_speed_vps ;;
    11) update_script_from_repo ;;
    12) /usr/local/sbin/uninstall-sc-1forcr ;;
    13) unlock_account ;;
    m|M)
      SHOW_FULL_MENU=1
      continue
      ;;
    x|X) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
  SHOW_FULL_MENU=0
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
systemctl stop sc-1forcr-autoreboot.timer >/dev/null 2>&1 || true
systemctl disable sc-1forcr-autoreboot.timer >/dev/null 2>&1 || true
systemctl stop sc-1forcr-autoreboot.service >/dev/null 2>&1 || true
systemctl disable sc-1forcr-autoreboot.service >/dev/null 2>&1 || true
systemctl stop sc-1forcr-udpcustom >/dev/null 2>&1 || true
systemctl disable sc-1forcr-udpcustom >/dev/null 2>&1 || true
systemctl stop udp-custom >/dev/null 2>&1 || true
systemctl disable udp-custom >/dev/null 2>&1 || true
rm -f /etc/systemd/system/sc-1forcr-api.service
rm -f /etc/systemd/system/sc-1forcr-sshws.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.timer
rm -f /etc/systemd/system/sc-1forcr-autoreboot.service
rm -f /etc/systemd/system/sc-1forcr-autoreboot.timer
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
rm -f /usr/local/sbin/sc-1forcr-safe-reboot

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

post_install_preflight() {
  local fw zstat ustat xstat apistat wsstat zport uport range_nft nat_ok
  fw="$(fw_backend_kind)"
  zstat="$(systemctl is-active "${ZIVPN_SERVICE_NAME}" 2>/dev/null || true)"
  ustat="$(systemctl is-active "${UDPCUSTOM_SERVICE_NAME}" 2>/dev/null || true)"
  xstat="$(systemctl is-active xray 2>/dev/null || true)"
  apistat="$(systemctl is-active sc-1forcr-api 2>/dev/null || true)"
  wsstat="$(systemctl is-active sc-1forcr-sshws 2>/dev/null || true)"

  zport="$(jq -r '.listen // empty' /etc/zivpn/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  [[ -z "${zport}" ]] && zport="${ZIVPN_LISTEN_PORT}"
  uport="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  [[ -z "${uport}" ]] && uport="${UDPCUSTOM_LISTEN_PORT}"

  nat_ok="n/a"
  if [[ -n "${ZIVPN_DNAT_RANGE}" ]]; then
    case "${fw}" in
      iptables)
        if iptables -t nat -S PREROUTING 2>/dev/null | grep -F -- "--dport ${ZIVPN_DNAT_RANGE}" | grep -F -- "--to-destination :${zport}" >/dev/null 2>&1; then
          nat_ok="yes"
        else
          nat_ok="no"
        fi
        ;;
      nft)
        range_nft="${ZIVPN_DNAT_RANGE/:/-}"
        if nft list chain ip nat prerouting 2>/dev/null | grep -F -- "udp dport ${range_nft}" | grep -F -- "dnat to :${zport}" >/dev/null 2>&1; then
          nat_ok="yes"
        else
          nat_ok="no"
        fi
        ;;
      *)
        nat_ok="no-fw"
        ;;
    esac
  fi

  cat <<EOF

=== PREFLIGHT CHECK ===
- firewall backend : ${fw}
- xray/api/sshws   : ${xstat}/${apistat}/${wsstat}
- zivpn/udphc      : ${zstat}/${ustat}
- zivpn listen     : ${zport} ($(ss -lunp 2>/dev/null | awk -v p=":${zport}" '$5 ~ p"$" {ok=1} END{print ok?"YES":"NO"}'))
- udphc listen     : ${uport} ($(ss -lunp 2>/dev/null | awk -v p=":${uport}" '$5 ~ p"$" {ok=1} END{print ok?"YES":"NO"}'))
- zivpn cert/key   : $( [[ -s /etc/zivpn/zivpn.crt && -s /etc/zivpn/zivpn.key ]] && echo OK || echo MISSING )
- dnat ${ZIVPN_DNAT_RANGE:-none}->${zport} : ${nat_ok}
=======================
EOF
}

main() {
  check_supported_os
  install_base_packages
  setup_vnstat
  apply_system_optimizations
  setup_logrotate_optimizations
  install_node_if_missing
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
  setup_auto_reboot_timer
  write_cli_menu
  write_version_marker
  post_install_preflight

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
- vnStat dan speedtest-cli otomatis terpasang untuk monitoring trafik + tes speed VPS.
- Auto reboot aktif setiap hari jam 03:00 via systemd timer sc-1forcr-autoreboot.timer.
- Reboot hanya menjalankan sync + reboot (tanpa ubah konfigurasi layanan).
- Menu VPS: jalankan perintah menu atau menu-sc-1forcr
- Update sekali klik dari menu: isi UPDATE_SCRIPT_URL lalu pilih menu 11 (Update Script dari Repo)
- Uninstall helper: uninstall-sc-1forcr
- Auto lock IP limit: timer systemd sc-1forcr-iplimit.timer (cek tiap 10 menit, lock sementara 15 menit)
EOF
}

main "$@"
