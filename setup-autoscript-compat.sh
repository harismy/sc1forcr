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
#   ZIVPN_BIN_URL=https://.../zivpn-linux-amd64   (opsional)
#   ZIVPN_RELEASE_TAG=udp-zivpn_1.4.9             (opsional, default dari repo zahidbd2/udp-zivpn)
#   ZIVPN_SERVICE_NAME=zivpn
#   DROPBEAR_PORT=109
#   DROPBEAR_ALT_PORT=143
#   DROPBEAR_VERSION=2019.78
#   DB_PATH=/usr/sbin/potatonc/potato.db
#   APP_DIR=/opt/sc-1forcr

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
API_AUTH_TOKEN="${API_AUTH_TOKEN:-}"
DB_PATH="${DB_PATH:-/usr/sbin/potatonc/potato.db}"
APP_DIR="${APP_DIR:-/opt/sc-1forcr}"
API_PORT="${API_PORT:-8088}"
ZIVPN_BIN_URL="${ZIVPN_BIN_URL:-}"
ZIVPN_RELEASE_TAG="${ZIVPN_RELEASE_TAG:-udp-zivpn_1.4.9}"
ZIVPN_SERVICE_NAME="${ZIVPN_SERVICE_NAME:-zivpn}"
DROPBEAR_PORT="${DROPBEAR_PORT:-109}"
DROPBEAR_ALT_PORT="${DROPBEAR_ALT_PORT:-143}"
DROPBEAR_VERSION="${DROPBEAR_VERSION:-2019.78}"

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

setup_nginx_and_cert() {
  log "Setup Nginx vhost (80 only)..."
  mkdir -p /var/www/html
  cat > /etc/nginx/sites-available/sc-1forcr.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location = /cdn-cgi/trace {
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
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location /trojan {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "websocket";
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
    }

    location / {
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
    maxconn 50000

defaults
    log global
    mode tcp
    option tcplog
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
    cat > /etc/zivpn/config.json <<'EOF'
{
  "auth": {
    "mode": "passwords",
    "config": []
  },
  "network": {
    "tcp": true,
    "udp": true
  },
  "listen": ":7300"
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
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${ZIVPN_SERVICE_NAME}" || true
    systemctl restart "${ZIVPN_SERVICE_NAME}" || true
  fi
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
SSH_WS_TARGET_PORT=${DROPBEAR_PORT}
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

function syncZivpnUser(username, addMode) {
  try {
    let root = { auth: { mode: 'passwords', config: [] } };
    if (fs.existsSync(ZIVPN_CONFIG)) root = JSON.parse(fs.readFileSync(ZIVPN_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') root.auth = {};
    if (!Array.isArray(root.auth.config)) root.auth.config = [];
    const set = new Set(root.auth.config.map((v) => String(v || '').trim().toLowerCase()).filter(Boolean));
    const key = String(username || '').trim().toLowerCase();
    if (!key) return;
    if (addMode) set.add(key);
    else set.delete(key);
    root.auth.config = Array.from(set);
    fs.writeFileSync(ZIVPN_CONFIG, JSON.stringify(root, null, 2));
    zivpnReload();
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

async function createOrUpdateSshFromBody(body, forcedDays = null) {
  const username = String(body?.username || '').trim();
  const password = String(body?.password || username || '').trim() || username;
  const expDays = forcedDays === null ? Number(body?.expired || 30) : Number(forcedDays || 1);
  const quota = Number(body?.kuota || 0);
  const limitip = Number(body?.limitip || 0);
  if (!username) throw new Error('username required');
  const expDate = ymdPlusDays(expDays);
  ensureLinuxUser(username, password, expDate);
  await run(
    "INSERT OR REPLACE INTO account_sshs(username,password,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)",
    [username, password, expDate, 'AKTIF', quota, limitip]
  );
  syncZivpnUser(username, true);
  return sshPayload(username, password, expDate, limitip);
}

app.post('/vps/sshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req.body, null));
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

app.post('/vps/trialsshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req.body, 1));
  } catch (e) {
    return fail(res, 500, e.message);
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

app.post('/vps/renewsshvpn/:username/:exp', async (req, res) => {
  try {
    const username = String(req.params.username || '').trim();
    const exp = Number(req.params.exp || 30);
    const expDate = ymdPlusDays(exp);
    const row = await get("SELECT password,limitip FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]);
    const pass = String(row?.password || username);
    ensureLinuxUser(username, pass, expDate);
    await run("UPDATE account_sshs SET date_exp=?, status='AKTIF' WHERE LOWER(username)=LOWER(?)", [expDate, username]);
    return ok(res, { username, exp: expDate, time: nowTime() });
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

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
  const expDate = ymdPlusDays(trial ? 1 : expDays);
  let data = null;
  if (protocol === 'vmess') {
    const uuid = crypto.randomUUID();
    await run("INSERT OR REPLACE INTO account_vmesses(username,uuid,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, uuid, expDate, 'AKTIF', quota, limitip]);
    data = {
      hostname: DOMAIN, username, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vmess', stn: '/vmess', upgrade: '/upvmess' },
      serviceName: 'vmess-grpc',
      link: { tls: vmessLink(DOMAIN, uuid, true), none: vmessLink(DOMAIN, uuid, false), grpc: vmessLink(DOMAIN, uuid, true), uptls: vmessLink(DOMAIN, uuid, true), upntls: vmessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'vless') {
    const uuid = crypto.randomUUID();
    await run("INSERT OR REPLACE INTO account_vlesses(username,uuid,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, uuid, expDate, 'AKTIF', quota, limitip]);
    data = {
      hostname: DOMAIN, username, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vless', stn: '/vless', upgrade: '/upvless' },
      serviceName: 'vless-grpc',
      link: { tls: vlessLink(DOMAIN, uuid, true), none: vlessLink(DOMAIN, uuid, false), grpc: vlessLink(DOMAIN, uuid, true), uptls: vlessLink(DOMAIN, uuid, true), upntls: vlessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'trojan') {
    const pass = crypto.randomUUID();
    await run("INSERT OR REPLACE INTO account_trojans(username,password,date_exp,status,quota,limitip) VALUES(?,?,?,?,?,?)", [username, pass, expDate, 'AKTIF', quota, limitip]);
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
    return fail(res, 500, e.message);
  }
});
app.post('/vps/trialvmessall', async (req, res) => {
  try {
    const data = await createXray('vmess', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, 500, e.message);
  }
});
app.post('/vps/vlessall', async (req, res) => {
  try {
    const data = await createXray('vless', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, 500, e.message);
  }
});
app.post('/vps/trialvlessall', async (req, res) => {
  try {
    const data = await createXray('vless', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, 500, e.message);
  }
});
app.post('/vps/trojanall', async (req, res) => {
  try {
    const data = await createXray('trojan', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, 500, e.message);
  }
});
app.post('/vps/trialtrojanall', async (req, res) => {
  try {
    const data = await createXray('trojan', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

async function renewXray(table, username, exp) {
  const expDate = ymdPlusDays(exp);
  await run(`UPDATE ${table} SET date_exp=?, status='AKTIF' WHERE LOWER(username)=LOWER(?)`, [expDate, username]);
  await renderAndReloadXray();
  return { username, exp: expDate, time: nowTime() };
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

app.post('/vps/renewvmess/:username/:exp', async (req, res) => ok(res, await renewXray('account_vmesses', String(req.params.username || '').trim(), Number(req.params.exp || 30))));
app.post('/vps/renewvless/:username/:exp', async (req, res) => ok(res, await renewXray('account_vlesses', String(req.params.username || '').trim(), Number(req.params.exp || 30))));
app.post('/vps/renewtrojan/:username/:exp', async (req, res) => ok(res, await renewXray('account_trojans', String(req.params.username || '').trim(), Number(req.params.exp || 30))));

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
    upstream.setTimeout(180000, closeAll);
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

    if (stage === 'first' && chunk.length >= 4 && chunk.slice(0, 4).toString() === 'SSH-') {
      startRawSshTunnel(chunk);
      return;
    }

    handleHttpLike(chunk);
  });

  client.on('error', closeAll);
  client.on('close', closeAll);
  client.setTimeout(180000, closeAll);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`ssh-ws mux on 127.0.0.1:${PORT} -> ssh ${SSH_HOST}:${SSH_PORT}, http ${HTTP_BACKEND_HOST}:${HTTP_BACKEND_PORT}`);
});
EOF

  cd "${APP_DIR}"
  rm -rf node_modules package-lock.json
  npm cache clean --force >/dev/null 2>&1 || true
  export npm_config_build_from_source=true
  export npm_config_fallback_to_build=true
  export npm_config_update_binary=false
  npm install --omit=dev --foreground-scripts
  node -e "require('sqlite3'); console.log('sqlite3 load ok')"
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

function parseWhoMap() {
  const map = new Map();
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
    const host = String(hostMatch?.[1] || '').trim();
    if (!user || !host) continue;
    if (!map.has(user)) map.set(user, new Set());
    map.get(user).add(host);
  }
  return map;
}

function parseXrayRecentIpMap() {
  const map = new Map();
  const path = '/var/log/xray/access.log';
  if (!fs.existsSync(path)) return map;
  const lines = fs.readFileSync(path, 'utf8').split('\n').slice(-20000);
  for (const lineRaw of lines) {
    const line = String(lineRaw || '').trim();
    if (!line) continue;
    const emailJson = line.match(/"email":"([^"]+)"/);
    const emailTxt = line.match(/\bemail:\s*([^\s]+)/i);
    const email = String(emailJson?.[1] || emailTxt?.[1] || '').trim();
    if (!email) continue;
    const srcJson = line.match(/"source":"([^"]+)"/);
    const srcTxt = line.match(/\bfrom\s+([0-9a-fA-F\.:]+)/i);
    const src = String(srcJson?.[1] || srcTxt?.[1] || '').trim();
    const ip = src.split(':')[0];
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
  const sshMap = parseWhoMap();
  const xrayMap = parseXrayRecentIpMap();
  let xrayChanged = false;
  let zivpnChanged = false;

  const sshRows = await all("SELECT username, limitip FROM account_sshs WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' AND CAST(COALESCE(limitip,0) AS INTEGER) > 0");
  for (const r of sshRows) {
    const user = String(r.username || '').trim();
    const lim = Number(r.limitip || 0);
    const cnt = sshMap.has(user) ? sshMap.get(user).size : 0;
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
      const lim = Number(r.limitip || 0);
      const cnt = xrayMap.has(user) ? xrayMap.get(user).size : 0;
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
ExecStart=/usr/bin/node ${APP_DIR}/api.js
Restart=always
RestartSec=2

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
ExecStart=/usr/bin/node ${APP_DIR}/ssh-ws.js
Restart=always
RestartSec=2

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
ExecStart=/usr/bin/node ${APP_DIR}/iplimit-checker.js
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
DOMAIN=${DOMAIN}
API_PORT=${API_PORT}
AUTH_TOKEN=${API_AUTH_TOKEN}
DB_PATH=${DB_PATH}
ZIVPN_SERVICE=${ZIVPN_SERVICE_NAME}
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

pick_type() {
  echo "Pilih tipe:" >&2
  echo "1) ssh" >&2
  echo "2) vmess" >&2
  echo "3) vless" >&2
  echo "4) trojan" >&2
  echo "5) zivpn" >&2
  read -rp "Input [1-5]: " t </dev/tty
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

create_account() {
  local type ep username password exp limitip quota
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_create "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint create tidak ada."; return; }

  read -rp "Username: " username
  read -rp "Expired (hari) [30]: " exp
  exp="${exp:-30}"
  read -rp "Limit IP [2]: " limitip
  limitip="${limitip:-2}"
  read -rp "Quota GB [0]: " quota
  quota="${quota:-0}"
  if [[ "$type" == "ssh" || "$type" == "zivpn" ]]; then
    read -rp "Password [default=username]: " password
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
  api_call "POST" "$ep" "$payload" | jq .
}

renew_account() {
  local type ep username exp
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_renew "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint renew tidak ada."; return; }
  read -rp "Username: " username
  read -rp "Tambah expired (hari) [30]: " exp
  exp="${exp:-30}"
  api_call "POST" "${ep}/${username}/${exp}" | jq .
}

delete_account() {
  local type ep username
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_delete "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint delete tidak ada."; return; }
  read -rp "Username: " username
  api_call "DELETE" "${ep}/${username}" | jq .
}

list_accounts() {
  echo "=== SSH/ZIVPN (DB) ==="
  sqlite3 "$DB_PATH" "SELECT username, date_exp, status FROM account_sshs ORDER BY username;"
  echo
  echo "=== VMESS (DB) ==="
  sqlite3 "$DB_PATH" "SELECT username, date_exp, status FROM account_vmesses ORDER BY username;"
  echo
  echo "=== VLESS (DB) ==="
  sqlite3 "$DB_PATH" "SELECT username, date_exp, status FROM account_vlesses ORDER BY username;"
  echo
  echo "=== TROJAN (DB) ==="
  sqlite3 "$DB_PATH" "SELECT username, date_exp, status FROM account_trojans ORDER BY username;"
  echo
  if [[ -f /etc/zivpn/config.json ]]; then
    echo "=== ZIVPN auth.config ==="
    jq -r '.auth.config[]?' /etc/zivpn/config.json || true
  fi
}

service_menu() {
  echo "1) status semua"
  echo "2) restart semua"
  echo "3) restart ZIVPN"
  read -rp "Pilih [1-3]: " s
  case "$s" in
    1)
      systemctl status ssh --no-pager | head -n 12
      systemctl status nginx --no-pager | head -n 12
      systemctl status xray --no-pager | head -n 12
      systemctl status sc-1forcr-api --no-pager | head -n 12
      systemctl status sc-1forcr-sshws --no-pager | head -n 12
      systemctl status haproxy --no-pager | head -n 12 || true
      systemctl status dropbear --no-pager | head -n 12 || true
      systemctl status "${ZIVPN_SERVICE}" --no-pager | head -n 12 || true
      ;;
    2)
      systemctl restart ssh dropbear nginx haproxy xray sc-1forcr-api sc-1forcr-sshws
      systemctl restart "${ZIVPN_SERVICE}" || true
      echo "Restart selesai."
      ;;
    3)
      systemctl restart "${ZIVPN_SERVICE}" || true
      echo "Restart ZIVPN selesai."
      ;;
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

backup_restore_menu() {
  echo "1) Backup config ZIVPN ke /root/config.json.zivpn"
  echo "2) Restore config ZIVPN dari /root/config.json.zivpn"
  read -rp "Pilih [1-2]: " b
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
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

change_domain_menu() {
  local new_domain email app_env pem
  read -rp "Masukkan domain baru: " new_domain
  if [[ -z "${new_domain}" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi
  read -rp "Masukkan email Let's Encrypt [admin@${new_domain}]: " email
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

while true; do
  clear
  echo "===================================="
  echo "        SC 1FORCR MENU"
  echo "===================================="
  echo "Domain : ${DOMAIN}"
  echo
  echo "1) Add Account"
  echo "2) Renew Account"
  echo "3) Delete Account"
  echo "4) List Account"
  echo "5) Service Menu"
  echo "6) Backup/Restore ZIVPN Config"
  echo "7) Ganti Domain + Renew SSL"
  echo "8) Monitor Lock Sementara (IP Limit)"
  echo "9) Uninstall SC 1FORCR"
  echo "x) Exit"
  echo
  read -rp "Pilih menu: " m
  case "$m" in
    1) create_account ;;
    2) renew_account ;;
    3) delete_account ;;
    4) list_accounts ;;
    5) service_menu ;;
    6) backup_restore_menu ;;
    7) change_domain_menu ;;
    8) monitor_temp_lock_menu ;;
    9) /usr/local/sbin/uninstall-sc-1forcr ;;
    x|X) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
  echo
  read -rp "Enter untuk lanjut..." _
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
rm -f /etc/systemd/system/sc-1forcr-api.service
rm -f /etc/systemd/system/sc-1forcr-sshws.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.service
rm -f /etc/systemd/system/sc-1forcr-iplimit.timer
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

main() {
  install_base_packages
  apply_system_optimizations
  install_node20_if_missing
  install_xray
  setup_dropbear
  init_db
  setup_nginx_and_cert
  setup_haproxy_tls_mux
  setup_zivpn_service_if_possible
  write_api_files
  write_iplimit_checker
  setup_services
  write_cli_menu

  cat <<EOF

=========================================
SELESAI - SC 1FORCR TERPASANG
=========================================
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
- Untuk summary API, tinggal pakai scripts/setup-summary-api.sh di repo ini.
- Jika binary zivpn belum ada, isi ZIVPN_BIN_URL lalu jalankan ulang script.
- Menu VPS: jalankan perintah menu atau menu-sc-1forcr
- Uninstall helper: uninstall-sc-1forcr
- Auto lock IP limit: timer systemd sc-1forcr-iplimit.timer (cek tiap 15 menit, lock sementara 15 menit)
EOF
}

main "$@"
