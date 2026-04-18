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
#   UDPCUSTOM_DNAT_AUTO_RANGE=6000:6999         (opsional, dipakai jika backend UDPHC aktif & DNAT range kosong)
#   UDPCUSTOM_DEFAULT_USER=freeudphc
#   ACTIVE_UDP_BACKEND=zivpn                       (pilihan: zivpn|udpcustom)
#   DROPBEAR_PORT=109
#   DROPBEAR_ALT_PORT=143
#   DROPBEAR_VERSION=2019.78
#   TELEGRAM_BOT_TOKEN=123456:ABC...            (opsional, notif aksi menu ke Telegram)
#   TELEGRAM_CHAT_ID=-1001234567890             (opsional)
#   AUTO_BACKUP_ENABLE=1                         (opsional, 1=aktif timer backup harian)
#   AUTO_BACKUP_DIR=/root/backup-sc-1forcr      (opsional)
#   AUTO_BACKUP_KEEP_DAYS=7                      (opsional)
#   IPLIMIT_CHECK_INTERVAL_MINUTES=10            (opsional, interval checker iplimit dalam menit)
#   IPLIMIT_LOCK_MINUTES=15                      (opsional, durasi lock sementara dalam menit)
#   IPLIMIT_AUTO_TUNE=1                          (opsional, 1=otomatis tuning berbasis RAM/vCPU)
#   IPLIMIT_DEBUG=0                              (opsional, 0=hemat log, 1=debug detail)
#   DROPBEAR_LOG_MAX_LINES=auto                  (opsional, auto by specs jika IPLIMIT_AUTO_TUNE=1)
#   DROPBEAR_RECENT_LOG_MAX_LINES=auto           (opsional, auto by specs jika IPLIMIT_AUTO_TUNE=1)
#   UDPHC_LOG_LINES_HISTORY=auto                 (opsional, auto by specs jika IPLIMIT_AUTO_TUNE=1)
#   UDPHC_LOG_LINES_REALTIME=auto                (opsional, auto by specs jika IPLIMIT_AUTO_TUNE=1)
#   XRAY_BLOCK_TCP_PORTS=80,443                  (opsional, port TCP yang diblok saat lock tmp xray)
#   XRAY_RECENT_WINDOW_MINUTES=30                (opsional, jendela menit log xray untuk hitung multi-login)
#   XRAY_ACTIVE_WINDOW_SECONDS=120               (opsional, jendela detik untuk IP aktif xray)
#   XRAY_MIN_HITS_PER_IP=2                       (opsional, minimal hit/log per IP pada jendela aktif)
#   DB_PATH=/usr/sbin/potatonc/potato.db
#   APP_DIR=/opt/sc-1forcr

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
API_AUTH_TOKEN="${API_AUTH_TOKEN:-}"
SCRIPT_VERSION="${SCRIPT_VERSION:-V.1FSC}"
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
UDPCUSTOM_DNAT_AUTO_RANGE="${UDPCUSTOM_DNAT_AUTO_RANGE:-6000:6999}"
UDPCUSTOM_DEFAULT_USER="${UDPCUSTOM_DEFAULT_USER:-freeudphc}"
ACTIVE_UDP_BACKEND="${ACTIVE_UDP_BACKEND:-zivpn}"
DROPBEAR_PORT="${DROPBEAR_PORT:-109}"
DROPBEAR_ALT_PORT="${DROPBEAR_ALT_PORT:-143}"
DROPBEAR_VERSION="${DROPBEAR_VERSION:-2019.78}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
AUTO_BACKUP_ENABLE="${AUTO_BACKUP_ENABLE:-1}"
AUTO_BACKUP_DIR="${AUTO_BACKUP_DIR:-/root/backup-sc-1forcr}"
AUTO_BACKUP_KEEP_DAYS="${AUTO_BACKUP_KEEP_DAYS:-7}"
IPLIMIT_CHECK_INTERVAL_MINUTES="${IPLIMIT_CHECK_INTERVAL_MINUTES:-10}"
IPLIMIT_LOCK_MINUTES="${IPLIMIT_LOCK_MINUTES:-15}"
IPLIMIT_AUTO_TUNE="${IPLIMIT_AUTO_TUNE:-1}"
IPLIMIT_DEBUG="${IPLIMIT_DEBUG:-}"
DROPBEAR_LOG_MAX_LINES="${DROPBEAR_LOG_MAX_LINES:-}"
DROPBEAR_RECENT_LOG_MAX_LINES="${DROPBEAR_RECENT_LOG_MAX_LINES:-}"
UDPHC_LOG_LINES_HISTORY="${UDPHC_LOG_LINES_HISTORY:-}"
UDPHC_LOG_LINES_REALTIME="${UDPHC_LOG_LINES_REALTIME:-}"
XRAY_BLOCK_TCP_PORTS="${XRAY_BLOCK_TCP_PORTS:-80,443}"
XRAY_RECENT_WINDOW_MINUTES="${XRAY_RECENT_WINDOW_MINUTES:-30}"
XRAY_ACTIVE_WINDOW_SECONDS="${XRAY_ACTIVE_WINDOW_SECONDS:-120}"
XRAY_MIN_HITS_PER_IP="${XRAY_MIN_HITS_PER_IP:-2}"
SSH_HC_AUTH_LOOKBACK_HOURS="${SSH_HC_AUTH_LOOKBACK_HOURS:-24}"

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

# EMAIL opsional: jika kosong/invalid, certbot dijalankan tanpa email
# dengan --register-unsafely-without-email.

if [[ -z "${API_AUTH_TOKEN}" ]]; then
  API_AUTH_TOKEN="$(openssl rand -hex 24)"
fi

log() {
  echo "[autoscript-compat] $*"
}

normalize_bool_01() {
  local raw
  raw="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${raw}" in
    1|true|yes|on) echo "1" ;;
    *) echo "0" ;;
  esac
}

get_total_ram_mib() {
  local kib
  kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
  if [[ -z "${kib}" || ! "${kib}" =~ ^[0-9]+$ ]]; then
    echo "1024"
    return
  fi
  echo "$((kib / 1024))"
}

get_cpu_cores() {
  local cores
  cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  if [[ -z "${cores}" || ! "${cores}" =~ ^[0-9]+$ || "${cores}" -lt 1 ]]; then
    echo "1"
    return
  fi
  echo "${cores}"
}

auto_tune_iplimit_vars() {
  local profile_debug profile_dropbear profile_recent profile_udphc_hist profile_udphc_rt profile_users
  profile_debug="0"
  profile_dropbear="12000"
  profile_recent="5000"
  profile_udphc_hist="1200"
  profile_udphc_rt="400"
  profile_users="80-100"

  if [[ "$(normalize_bool_01 "${IPLIMIT_AUTO_TUNE}")" == "1" ]]; then
    local ram_mib ram_gb cores tier
    ram_mib="$(get_total_ram_mib)"
    cores="$(get_cpu_cores)"
    ram_gb=$((ram_mib / 1024))
    (( ram_gb < 1 )) && ram_gb=1

    # Tier konservatif: ambil bottleneck antara RAM dan vCPU.
    tier="${ram_gb}"
    (( cores < tier )) && tier="${cores}"
    (( tier < 1 )) && tier=1

    if (( tier >= 8 )); then
      profile_dropbear="36000"
      profile_recent="14000"
      profile_udphc_hist="3200"
      profile_udphc_rt="1000"
      profile_users="220-300"
    elif (( tier >= 4 )); then
      profile_dropbear="22000"
      profile_recent="9000"
      profile_udphc_hist="2200"
      profile_udphc_rt="700"
      profile_users="150-220"
    elif (( tier >= 2 )); then
      profile_dropbear="16000"
      profile_recent="6500"
      profile_udphc_hist="1600"
      profile_udphc_rt="500"
      profile_users="100-150"
    fi
    log "IPLIMIT auto-tune aktif: RAM=${ram_gb}GB vCPU=${cores} tier=${tier} target_user~${profile_users}"
  fi

  [[ -z "${IPLIMIT_DEBUG}" ]] && IPLIMIT_DEBUG="${profile_debug}"
  [[ -z "${DROPBEAR_LOG_MAX_LINES}" ]] && DROPBEAR_LOG_MAX_LINES="${profile_dropbear}"
  [[ -z "${DROPBEAR_RECENT_LOG_MAX_LINES}" ]] && DROPBEAR_RECENT_LOG_MAX_LINES="${profile_recent}"
  [[ -z "${UDPHC_LOG_LINES_HISTORY}" ]] && UDPHC_LOG_LINES_HISTORY="${profile_udphc_hist}"
  [[ -z "${UDPHC_LOG_LINES_REALTIME}" ]] && UDPHC_LOG_LINES_REALTIME="${profile_udphc_rt}"

  IPLIMIT_DEBUG="$(normalize_bool_01 "${IPLIMIT_DEBUG}")"
  DROPBEAR_LOG_MAX_LINES="$(echo "${DROPBEAR_LOG_MAX_LINES:-12000}" | tr -cd '0-9')"
  DROPBEAR_RECENT_LOG_MAX_LINES="$(echo "${DROPBEAR_RECENT_LOG_MAX_LINES:-5000}" | tr -cd '0-9')"
  UDPHC_LOG_LINES_HISTORY="$(echo "${UDPHC_LOG_LINES_HISTORY:-1200}" | tr -cd '0-9')"
  UDPHC_LOG_LINES_REALTIME="$(echo "${UDPHC_LOG_LINES_REALTIME:-400}" | tr -cd '0-9')"
  [[ -z "${DROPBEAR_LOG_MAX_LINES}" || "${DROPBEAR_LOG_MAX_LINES}" -lt 2000 ]] && DROPBEAR_LOG_MAX_LINES="12000"
  [[ -z "${DROPBEAR_RECENT_LOG_MAX_LINES}" || "${DROPBEAR_RECENT_LOG_MAX_LINES}" -lt 500 ]] && DROPBEAR_RECENT_LOG_MAX_LINES="5000"
  [[ -z "${UDPHC_LOG_LINES_HISTORY}" || "${UDPHC_LOG_LINES_HISTORY}" -lt 200 ]] && UDPHC_LOG_LINES_HISTORY="1200"
  [[ -z "${UDPHC_LOG_LINES_REALTIME}" || "${UDPHC_LOG_LINES_REALTIME}" -lt 100 ]] && UDPHC_LOG_LINES_REALTIME="400"
  return 0
}

auto_tune_iplimit_vars

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
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget jq sqlite3 openssl uuid-runtime ca-certificates \
    gnupg lsb-release socat cron unzip \
    haproxy \
    nginx certbot \
    openssh-server dropbear pwgen \
    build-essential python3 make g++ gcc libc6-dev pkg-config bzip2 zlib1g-dev \
    netfilter-persistent iptables-persistent

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

setup_default_banner_assets() {
  log "Menyiapkan banner default 1FORCR..."
  mkdir -p /etc/sc-1forcr

  cat > /etc/sc-1forcr/banner.html <<'EOF'
<div style="text-align:center; line-height:1.6; font-family: monospace;">

<!-- ╔══════════════╗ -->
<font color="#00ffff">╔═══════════════════════╗</font><br>
<font color="#17e8ff">⚡ SSH PREMIUM BY 1FORCR ⚡</font><br>
<font color="#00ffff">╚═══════════════════════╝</font><br>


<!-- ATURAN PAKAI -->
<font color="#ff45ba"><b>⚠️ ATURAN PEMAKAIAN ⚠️</b></font><br>
<font color="#84ecdb">
Jika beli akun untuk 1 pengguna <br>→ gunakan hanya untuk 1 orang.<br>
Jika beli akun untuk 2 pengguna <br>→ gunakan untuk 2 orang saja.<br>
</font><br>

<font color="red"><b>🚫 Melanggar = Akun Expired Otomatis!</b></font><br><br>

<!-- KONTAK ADMIN -->
<font color="#00ffff">╔════ KONTAK ADMIN ════╗</font><br>
<font color="#84ecdb">
📞 Hubungi Admin: <br>
<font color="#00ffff">http://wa.me/6289527159281</font><br><br>
📢 Info Config & SSH: <br>
<font color="#ff45ba">https://t.me/Oneforcr_info</font><br><br>
🤖 Order via Bot: <br>
<font color="#ff17e8">https://t.me/BOT1FORCR_STORE_bot</font>
</font><br>
<font color="#00ffff">╚════════════════════╝</font><br><br>

<font color="#84ecdb"><i>✨ Terimakasih udah order di 1FORCR ✨</i></font><br>
<font color="#00ffff">━━━━━━━━━━━━━━━━━━━━━━━━━</font><br>

</div>
EOF

  cat > /etc/sc-1forcr/banner.txt <<'EOF'
=================================
      SSH PREMIUM BY 1FORCR
=================================
ATURAN PEMAKAIAN:
- Jika beli akun untuk 1 pengguna, gunakan untuk 1 orang.
- Jika beli akun untuk 2 pengguna, gunakan untuk 2 orang.
Melanggar = akun expired otomatis.

Kontak Admin:
- WA: http://wa.me/6289527159281
- Telegram Info: https://t.me/Oneforcr_info
- Bot Order: https://t.me/BOT1FORCR_STORE_bot

Terimakasih sudah order di 1FORCR.
=================================
EOF

  chmod 644 /etc/sc-1forcr/banner.html /etc/sc-1forcr/banner.txt >/dev/null 2>&1 || true
}
setup_dropbear() {
  log "Setup Dropbear..."

  local main_port alt_port banner_file
  main_port="$(echo "${DROPBEAR_PORT}" | tr -cd '0-9')"
  alt_port="$(echo "${DROPBEAR_ALT_PORT}" | tr -cd '0-9')"
  [[ -z "${main_port}" ]] && main_port="109"
  [[ -z "${alt_port}" ]] && alt_port="143"
  if [[ "${main_port}" -lt 1 || "${main_port}" -gt 65535 ]]; then main_port="109"; fi
  if [[ "${alt_port}" -lt 1 || "${alt_port}" -gt 65535 ]]; then alt_port="143"; fi
  banner_file="/etc/sc-1forcr/banner.html"
  if [[ ! -s "${banner_file}" ]]; then
    banner_file=""
  fi

  if [[ -n "${banner_file}" ]]; then
    if grep -qE '^[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null; then
      sed -i "s|^[[:space:]]*Banner[[:space:]].*|Banner ${banner_file}|g" /etc/ssh/sshd_config
    else
      echo "Banner ${banner_file}" >> /etc/ssh/sshd_config
    fi
  fi

  cat > /etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=${main_port}
DROPBEAR_EXTRA_ARGS="-p ${alt_port}"
DROPBEAR_BANNER="${banner_file}"
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
  if [[ -n "${banner_file}" ]]; then
    cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
Type=simple
ExecStart=
ExecStart=${custom_bin} -R -E -F -p ${main_port} -p ${alt_port} -b ${banner_file}
EOF
  else
    cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
Type=simple
ExecStart=
ExecStart=${custom_bin} -R -E -F -p ${main_port} -p ${alt_port}
EOF
  fi

  systemctl daemon-reload
  systemctl restart ssh >/dev/null 2>&1 || true
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
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);

CREATE TABLE IF NOT EXISTS account_vmesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);

CREATE TABLE IF NOT EXISTS account_vlesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);

CREATE TABLE IF NOT EXISTS account_trojans (
  username TEXT PRIMARY KEY,
  password TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
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

  # Backward-compatible migration for older DB schema.
  local t
  for t in account_sshs account_vmesses account_vlesses account_trojans; do
    if ! sqlite3 "${DB_PATH}" "PRAGMA table_info(${t});" | grep -q '|owner_telegram_id|'; then
      sqlite3 "${DB_PATH}" "ALTER TABLE ${t} ADD COLUMN owner_telegram_id INTEGER;" >/dev/null 2>&1 || true
    fi
    if ! sqlite3 "${DB_PATH}" "PRAGMA table_info(${t});" | grep -q '|owner_telegram_chat_id|'; then
      sqlite3 "${DB_PATH}" "ALTER TABLE ${t} ADD COLUMN owner_telegram_chat_id INTEGER;" >/dev/null 2>&1 || true
    fi
  done
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
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_buffering off;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/sc-1forcr.conf /etc/nginx/sites-enabled/sc-1forcr.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx
  systemctl restart nginx

  log "Issue cert Let's Encrypt (webroot)..."
  local certbot_email_arg
  if [[ -z "${EMAIL}" || "${EMAIL}" == "admin@example.com" || "${EMAIL}" == *"@example.com" ]]; then
    certbot_email_arg="--register-unsafely-without-email"
  else
    certbot_email_arg="-m ${EMAIL}"
  fi
  if ! certbot certonly --webroot -w /var/www/html -d "${DOMAIN}" --non-interactive --agree-tos ${certbot_email_arg}; then
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

  local listen_port backend effective_dnat_range
  backend="$(echo "${ACTIVE_UDP_BACKEND:-}" | tr '[:upper:]' '[:lower:]')"
  effective_dnat_range="${UDPCUSTOM_DNAT_RANGE}"
  listen_port="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  if [[ -z "${listen_port}" ]]; then
    listen_port="$(echo "${UDPCUSTOM_LISTEN_PORT}" | tr -cd '0-9')"
  fi
  if [[ -z "${listen_port}" ]]; then
    listen_port="5667"
  fi

  log "Set rule UDP UDPHC: listen=${listen_port}, dnat_range=${UDPCUSTOM_DNAT_RANGE:-none}"

  fw_allow_udp_input "${listen_port}"

  if [[ -z "${effective_dnat_range}" && ( "${backend}" == "udpcustom" || "${backend}" == "udp-custom" || "${backend}" == "udphc" ) ]]; then
    effective_dnat_range="${UDPCUSTOM_DNAT_AUTO_RANGE}"
    log "UDPHC aktif dengan DNAT auto-range: ${effective_dnat_range}"
  fi

  if [[ -n "${effective_dnat_range}" ]]; then
    fw_add_udp_dnat_range "${effective_dnat_range}" "${listen_port}"
    # Hindari overlap jalur saat pindah dari ZIVPN ke UDPHC.
    fw_delete_udp_dnat_range "${ZIVPN_DNAT_RANGE}" "${listen_port}"
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
  local ssh_ws_target_port
  ssh_ws_target_port="$(echo "${DROPBEAR_PORT}" | tr -cd '0-9')"
  [[ -z "${ssh_ws_target_port}" ]] && ssh_ws_target_port="109"
  if [[ "${ssh_ws_target_port}" -lt 1 || "${ssh_ws_target_port}" -gt 65535 ]]; then
    ssh_ws_target_port="109"
  fi

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
SSH_WS_TARGET_PORT=${ssh_ws_target_port}
SSH_HTTP_BACKEND_HOST=127.0.0.1
SSH_HTTP_BACKEND_PORT=80
DROPBEAR_PORT=${DROPBEAR_PORT}
DROPBEAR_ALT_PORT=${DROPBEAR_ALT_PORT}
UDPCUSTOM_CONFIG=/root/udp/config.json
UDPCUSTOM_LISTEN_PORT=${UDPCUSTOM_LISTEN_PORT}
UDPCUSTOM_SERVICE=${UDPCUSTOM_SERVICE_NAME}
ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND}
IPLIMIT_CHECK_INTERVAL_MINUTES=${IPLIMIT_CHECK_INTERVAL_MINUTES}
IPLIMIT_LOCK_MINUTES=${IPLIMIT_LOCK_MINUTES}
IPLIMIT_AUTO_TUNE=${IPLIMIT_AUTO_TUNE}
IPLIMIT_DEBUG=${IPLIMIT_DEBUG}
DROPBEAR_LOG_MAX_LINES=${DROPBEAR_LOG_MAX_LINES}
DROPBEAR_RECENT_LOG_MAX_LINES=${DROPBEAR_RECENT_LOG_MAX_LINES}
UDPHC_LOG_LINES_HISTORY=${UDPHC_LOG_LINES_HISTORY}
UDPHC_LOG_LINES_REALTIME=${UDPHC_LOG_LINES_REALTIME}
XRAY_BLOCK_TCP_PORTS=${XRAY_BLOCK_TCP_PORTS}
XRAY_RECENT_WINDOW_MINUTES=${XRAY_RECENT_WINDOW_MINUTES}
XRAY_ACTIVE_WINDOW_SECONDS=${XRAY_ACTIVE_WINDOW_SECONDS}
XRAY_MIN_HITS_PER_IP=${XRAY_MIN_HITS_PER_IP}
SSH_HC_AUTH_LOOKBACK_HOURS=${SSH_HC_AUTH_LOOKBACK_HOURS}
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
const UDPCUSTOM_CONFIG = process.env.UDPCUSTOM_CONFIG || '/root/udp/config.json';
const UDPCUSTOM_SERVICE = process.env.UDPCUSTOM_SERVICE || 'sc-1forcr-udpcustom';
const DROPBEAR_PORT = String(process.env.DROPBEAR_PORT || '109').trim();
const DROPBEAR_ALT_PORT = String(process.env.DROPBEAR_ALT_PORT || '143').trim();

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
function parseIntId(raw) {
  const n = Number(String(raw ?? '').trim());
  return Number.isInteger(n) ? n : null;
}
function getOwnerInfo(req, body = {}) {
  const ownerTelegramId = parseIntId(
    req?.headers?.['x-telegram-user-id'] ??
    body?.telegram_user_id ??
    body?.owner_telegram_id ??
    body?.user_id
  );
  const ownerTelegramChatId = parseIntId(
    req?.headers?.['x-telegram-chat-id'] ??
    body?.telegram_chat_id ??
    body?.owner_telegram_chat_id ??
    body?.chat_id
  );
  return { ownerTelegramId, ownerTelegramChatId };
}
function ymdLocal(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
function ymdPlusDays(days, baseYmd = '') {
  let d;
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(baseYmd || ''))) {
    d = new Date(`${baseYmd}T00:00:00`);
  } else {
    d = new Date();
  }
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + Number(days || 0));
  return ymdLocal(d);
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

function udpcustomReload() {
  if (!safeExec('systemctl', ['restart', UDPCUSTOM_SERVICE])) {
    safeExec('service', [UDPCUSTOM_SERVICE, 'restart']);
  }
}

let udpcustomReloadTimer = null;
function scheduleUdpcustomReload(delayMs = 5000) {
  if (udpcustomReloadTimer) clearTimeout(udpcustomReloadTimer);
  udpcustomReloadTimer = setTimeout(() => {
    udpcustomReloadTimer = null;
    udpcustomReload();
  }, Number(delayMs) || 5000);
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

function syncUdpcustomUser(secret, addMode) {
  try {
    const key = String(secret || '').trim();
    if (!key) return;
    let root = { auth: { mode: 'passwords', config: [] } };
    if (fs.existsSync(UDPCUSTOM_CONFIG)) root = JSON.parse(fs.readFileSync(UDPCUSTOM_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') root.auth = {};
    if (!Array.isArray(root.auth.config)) root.auth.config = [];
    root.auth.mode = 'passwords';

    const beforeSet = new Set(root.auth.config.map((v) => String(v || '').trim()).filter(Boolean));
    const set = new Set(beforeSet);
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
    fs.writeFileSync(UDPCUSTOM_CONFIG, JSON.stringify(root, null, 2));
    scheduleUdpcustomReload();
  } catch (_) {}
}

let sshBackendSyncBusy = false;
async function syncSshBackendsFromDb() {
  if (sshBackendSyncBusy) return;
  sshBackendSyncBusy = true;
  try {
    const rows = await all("SELECT username, password FROM account_sshs WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' ORDER BY LOWER(username)");
    const zivpnUsers = [];
    const udphcSecrets = [];
    const zivpnSeen = new Set();
    const udphcSeen = new Set();

    for (const row of rows) {
      const username = String(row?.username || '').trim().toLowerCase();
      if (username && !zivpnSeen.has(username)) {
        zivpnSeen.add(username);
        zivpnUsers.push(username);
      }
      const secret = String(row?.password || row?.username || '').trim();
      if (secret && !udphcSeen.has(secret)) {
        udphcSeen.add(secret);
        udphcSecrets.push(secret);
      }
    }

    try {
      let z = { auth: { mode: 'passwords', config: [] } };
      if (fs.existsSync(ZIVPN_CONFIG)) z = JSON.parse(fs.readFileSync(ZIVPN_CONFIG, 'utf8'));
      if (!z.auth || typeof z.auth !== 'object') z.auth = {};
      const prev = Array.isArray(z.auth.config)
        ? Array.from(new Set(z.auth.config.map((v) => String(v || '').trim().toLowerCase()).filter(Boolean))).sort()
        : [];
      const next = Array.from(new Set(zivpnUsers.map((v) => String(v || '').trim().toLowerCase()).filter(Boolean))).sort();
      const changed = z.auth.mode !== 'passwords' || JSON.stringify(prev) !== JSON.stringify(next);
      if (changed) {
        z.auth.mode = 'passwords';
        z.auth.config = next;
        fs.writeFileSync(ZIVPN_CONFIG, JSON.stringify(z, null, 2));
        scheduleZivpnReload(1500);
      }
    } catch (_) {}

    try {
      let u = { auth: { mode: 'passwords', config: [] } };
      if (fs.existsSync(UDPCUSTOM_CONFIG)) u = JSON.parse(fs.readFileSync(UDPCUSTOM_CONFIG, 'utf8'));
      if (!u.auth || typeof u.auth !== 'object') u.auth = {};
      const prev = Array.isArray(u.auth.config)
        ? Array.from(new Set(u.auth.config.map((v) => String(v || '').trim()).filter(Boolean))).sort()
        : [];
      const next = Array.from(new Set(udphcSecrets.map((v) => String(v || '').trim()).filter(Boolean))).sort();
      const changed = u.auth.mode !== 'passwords' || JSON.stringify(prev) !== JSON.stringify(next);
      if (changed) {
        u.auth.mode = 'passwords';
        u.auth.config = next;
        fs.writeFileSync(UDPCUSTOM_CONFIG, JSON.stringify(u, null, 2));
        scheduleUdpcustomReload(1200);
      }
    } catch (_) {}
  } catch (_) {
    // no-op: keep API running even if background sync fails
  } finally {
    sshBackendSyncBusy = false;
  }
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
  // Hindari restart agar koneksi user existing tidak terputus.
  // Prioritas: systemctl reload, fallback kirim HUP ke service.
  if (!safeExec('systemctl', ['reload', 'xray'])) {
    safeExec('systemctl', ['kill', '-s', 'HUP', 'xray']);
  }
}

app.get('/vps/health', (_req, res) => ok(res, { ok: true, domain: DOMAIN }));
app.use('/vps', auth);

app.get('/vps/my-accounts', async (req, res) => {
  try {
    const ownerTelegramId = parseIntId(req.query?.telegram_user_id ?? req.headers?.['x-telegram-user-id']);
    if (!ownerTelegramId) return fail(res, 400, 'telegram_user_id required');
    const includeInactive = String(req.query?.include_inactive || '0').trim() === '1';
    const statusFilter = includeInactive ? '' : "AND UPPER(TRIM(COALESCE(status,'')))='AKTIF'";

    const rows = await all(
      `
      SELECT 'ssh' AS type, username, date_exp, status, quota, limitip FROM account_sshs
      WHERE owner_telegram_id=? ${statusFilter}
      UNION ALL
      SELECT 'vmess' AS type, username, date_exp, status, quota, limitip FROM account_vmesses
      WHERE owner_telegram_id=? ${statusFilter}
      UNION ALL
      SELECT 'vless' AS type, username, date_exp, status, quota, limitip FROM account_vlesses
      WHERE owner_telegram_id=? ${statusFilter}
      UNION ALL
      SELECT 'trojan' AS type, username, date_exp, status, quota, limitip FROM account_trojans
      WHERE owner_telegram_id=? ${statusFilter}
      ORDER BY LOWER(username), type
      `,
      [ownerTelegramId, ownerTelegramId, ownerTelegramId, ownerTelegramId]
    );
    return ok(res, {
      telegram_user_id: ownerTelegramId,
      accounts: rows || [],
      total: Array.isArray(rows) ? rows.length : 0
    });
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

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

async function generateTrialUsername(table, prefix = 'trial') {
  const cleanPrefix = String(prefix || 'trial').toLowerCase().replace(/[^a-z0-9]/g, '') || 'trial';
  for (let i = 0; i < 50; i += 1) {
    const candidate = `${cleanPrefix}${String(Math.floor(Math.random() * 10000)).padStart(4, '0')}`;
    const row = await get(`SELECT 1 AS ok FROM ${table} WHERE LOWER(username)=LOWER(?)`, [candidate]);
    if (!row) return candidate;
  }
  return `${cleanPrefix}${Date.now().toString().slice(-6)}`;
}

async function createOrUpdateSshFromBody(req, body, forcedDays = null) {
  const isTrial = forcedDays !== null;
  let username = String(body?.username || '').trim().toLowerCase();
  if (!username && isTrial) {
    username = await generateTrialUsername('account_sshs', 'trial');
  }
  const owner = getOwnerInfo(req, body || {});
  const requestedPassword = String(body?.password || '').trim();
  const password = requestedPassword || (isTrial ? crypto.randomBytes(6).toString('hex') : username);
  const expDays = forcedDays === null ? Number(body?.expired || 30) : Number(forcedDays || 1);
  const quota = Number(body?.kuota || 0);
  const limitip = Number(body?.limitip || 0);
  if (!username) throw new Error('username required');
  await ensureUsernameNotExists('account_sshs', username);
  const expDate = ymdPlusDays(expDays);
  ensureLinuxUser(username, password, expDate);
  await run(
    "INSERT INTO account_sshs(username,password,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id) VALUES(?,?,?,?,?,?,?,?)",
    [username, password, expDate, 'AKTIF', quota, limitip, owner.ownerTelegramId, owner.ownerTelegramChatId]
  );
  syncZivpnUser(username, true);
  syncUdpcustomUser(password, true);
  return sshPayload(username, password, expDate, limitip);
}

app.post('/vps/sshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req, req.body, null));
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});

app.post('/vps/trialsshvpn', async (req, res) => {
  try {
    return ok(res, await createOrUpdateSshFromBody(req, req.body, 1));
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});

app.delete('/vps/deletesshvpn/:username', async (req, res) => {
  try {
    const username = String(req.params.username || '').trim();
    const row = await get("SELECT password FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]).catch(() => null);
    deleteLinuxUser(username);
    await run("DELETE FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]);
    syncZivpnUser(username, false);
    syncUdpcustomUser(String(row?.password || ''), false);
    syncUdpcustomUser(username, false);
    return ok(res, { username });
  } catch (e) {
    return fail(res, 500, e.message);
  }
});

async function renewSsh(req, res) {
  try {
    const username = String(req.params.username || '').trim();
    const exp = Number(req.params.exp || 30);
    const row = await get("SELECT password,limitip,quota,date_exp FROM account_sshs WHERE LOWER(username)=LOWER(?)", [username]);
    const pass = String(row?.password || username);
    const currentQuota = Number(row?.quota || 0);
    const bodyQuota = Number(req.body?.kuota);
    const nextQuota = Number.isFinite(bodyQuota) ? bodyQuota : currentQuota;
    const fromExp = String(row?.date_exp || '-');
    const today = ymdPlusDays(0);
    const baseExp = String(row?.date_exp || '');
    const renewBase = (/^\d{4}-\d{2}-\d{2}$/.test(baseExp) && baseExp > today) ? baseExp : today;
    const expDate = ymdPlusDays(exp, renewBase);
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

async function createXray(req, protocol, username, expDays, quota, limitip, trial) {
  const protocolTable = {
    vmess: 'account_vmesses',
    vless: 'account_vlesses',
    trojan: 'account_trojans'
  };
  const owner = getOwnerInfo(req, req?.body || {});
  let finalUsername = String(username || '').trim().toLowerCase();
  if (!finalUsername && trial) {
    finalUsername = await generateTrialUsername(protocolTable[protocol], 'trial');
  }
  if (!finalUsername) throw new Error('username required');
  const expDate = ymdPlusDays(trial ? 1 : expDays);
  let data = null;
  if (protocol === 'vmess') {
    await ensureUsernameNotExists('account_vmesses', finalUsername);
    const uuid = crypto.randomUUID();
    await run(
      "INSERT INTO account_vmesses(username,uuid,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id) VALUES(?,?,?,?,?,?,?,?)",
      [finalUsername, uuid, expDate, 'AKTIF', quota, limitip, owner.ownerTelegramId, owner.ownerTelegramChatId]
    );
    data = {
      hostname: DOMAIN, username: finalUsername, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vmess', stn: '/vmess', upgrade: '/upvmess' },
      serviceName: 'vmess-grpc',
      link: { tls: vmessLink(DOMAIN, uuid, true), none: vmessLink(DOMAIN, uuid, false), grpc: vmessLink(DOMAIN, uuid, true), uptls: vmessLink(DOMAIN, uuid, true), upntls: vmessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'vless') {
    await ensureUsernameNotExists('account_vlesses', finalUsername);
    const uuid = crypto.randomUUID();
    await run(
      "INSERT INTO account_vlesses(username,uuid,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id) VALUES(?,?,?,?,?,?,?,?)",
      [finalUsername, uuid, expDate, 'AKTIF', quota, limitip, owner.ownerTelegramId, owner.ownerTelegramChatId]
    );
    data = {
      hostname: DOMAIN, username: finalUsername, uuid, expired: expDate, exp: expDate, time: nowTime(),
      city: 'Auto', isp: 'Auto',
      port: { tls: '443', none: '80', any: '443', grpc: '443' },
      path: { ws: '/vless', stn: '/vless', upgrade: '/upvless' },
      serviceName: 'vless-grpc',
      link: { tls: vlessLink(DOMAIN, uuid, true), none: vlessLink(DOMAIN, uuid, false), grpc: vlessLink(DOMAIN, uuid, true), uptls: vlessLink(DOMAIN, uuid, true), upntls: vlessLink(DOMAIN, uuid, false) }
    };
  } else if (protocol === 'trojan') {
    await ensureUsernameNotExists('account_trojans', finalUsername);
    const pass = crypto.randomUUID();
    await run(
      "INSERT INTO account_trojans(username,password,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id) VALUES(?,?,?,?,?,?,?,?)",
      [finalUsername, pass, expDate, 'AKTIF', quota, limitip, owner.ownerTelegramId, owner.ownerTelegramChatId]
    );
    data = {
      hostname: DOMAIN, username: finalUsername, password: pass, uuid: pass, expired: expDate, exp: expDate, time: nowTime(),
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
    const data = await createXray(req, 'vmess', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialvmessall', async (req, res) => {
  try {
    const data = await createXray(req, 'vmess', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/vlessall', async (req, res) => {
  try {
    const data = await createXray(req, 'vless', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialvlessall', async (req, res) => {
  try {
    const data = await createXray(req, 'vless', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trojanall', async (req, res) => {
  try {
    const data = await createXray(req, 'trojan', String(req.body?.username || '').trim(), Number(req.body?.expired || 30), Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), false);
    return ok(res, data);
  } catch (e) {
    return fail(res, Number(e?.statusCode || 500), e.message);
  }
});
app.post('/vps/trialtrojanall', async (req, res) => {
  try {
    const data = await createXray(req, 'trojan', String(req.body?.username || '').trim(), 1, Number(req.body?.kuota || 0), Number(req.body?.limitip || 0), true);
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
  const today = ymdPlusDays(0);
  const baseExp = String(row?.date_exp || '');
  const renewBase = (/^\d{4}-\d{2}-\d{2}$/.test(baseExp) && baseExp > today) ? baseExp : today;
  const expDate = ymdPlusDays(exp, renewBase);
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
  syncSshBackendsFromDb();
  setInterval(syncSshBackendsFromDb, 2 * 60 * 1000);
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
const DROPBEAR_PORT = String(process.env.DROPBEAR_PORT || '109').trim();
const DROPBEAR_ALT_PORT = String(process.env.DROPBEAR_ALT_PORT || '143').trim();
const ACTIVE_UDP_BACKEND = String(process.env.ACTIVE_UDP_BACKEND || '').trim().toLowerCase();
const CHECK_INTERVAL_MINUTES_RAW = Number(process.env.IPLIMIT_CHECK_INTERVAL_MINUTES || 10);
const CHECK_INTERVAL_MINUTES = Number.isFinite(CHECK_INTERVAL_MINUTES_RAW) && CHECK_INTERVAL_MINUTES_RAW > 0
  ? Math.floor(CHECK_INTERVAL_MINUTES_RAW)
  : 10;
const LOCK_MINUTES_RAW = Number(process.env.IPLIMIT_LOCK_MINUTES || 15);
const LOCK_MINUTES = Number.isFinite(LOCK_MINUTES_RAW) && LOCK_MINUTES_RAW > 0 ? Math.floor(LOCK_MINUTES_RAW) : 15;
const LOCK_SECONDS = LOCK_MINUTES * 60;
const XRAY_BLOCK_TCP_PORTS = String(process.env.XRAY_BLOCK_TCP_PORTS || '80,443')
  .split(',')
  .map((v) => Number(String(v || '').trim()))
  .filter((n) => Number.isInteger(n) && n >= 1 && n <= 65535);
const XRAY_RECENT_WINDOW_MINUTES_RAW = Number(process.env.XRAY_RECENT_WINDOW_MINUTES || (CHECK_INTERVAL_MINUTES * 3));
const XRAY_RECENT_WINDOW_MINUTES = Number.isFinite(XRAY_RECENT_WINDOW_MINUTES_RAW) && XRAY_RECENT_WINDOW_MINUTES_RAW >= 5
  ? Math.min(Math.floor(XRAY_RECENT_WINDOW_MINUTES_RAW), 1440)
  : Math.max(10, CHECK_INTERVAL_MINUTES * 3);
const XRAY_ACTIVE_WINDOW_SECONDS_RAW = Number(process.env.XRAY_ACTIVE_WINDOW_SECONDS || 120);
const XRAY_ACTIVE_WINDOW_SECONDS = Number.isFinite(XRAY_ACTIVE_WINDOW_SECONDS_RAW) && XRAY_ACTIVE_WINDOW_SECONDS_RAW >= 30
  ? Math.min(Math.floor(XRAY_ACTIVE_WINDOW_SECONDS_RAW), 1800)
  : 120;
const XRAY_MIN_HITS_PER_IP_RAW = Number(process.env.XRAY_MIN_HITS_PER_IP || 2);
const XRAY_MIN_HITS_PER_IP = Number.isFinite(XRAY_MIN_HITS_PER_IP_RAW) && XRAY_MIN_HITS_PER_IP_RAW >= 1
  ? Math.min(Math.floor(XRAY_MIN_HITS_PER_IP_RAW), 20)
  : 2;
const XRAY_LOG_TAIL_LINES_RAW = Number(process.env.XRAY_LOG_TAIL_LINES || 8000);
const XRAY_LOG_TAIL_LINES = Number.isFinite(XRAY_LOG_TAIL_LINES_RAW) && XRAY_LOG_TAIL_LINES_RAW >= 1000
  ? Math.min(Math.floor(XRAY_LOG_TAIL_LINES_RAW), 60000)
  : 8000;
const RECENT_AUTH_WINDOW_MINUTES = Math.max(2, CHECK_INTERVAL_MINUTES);
const DROPBEAR_LOG_MAX_LINES_RAW = Number(process.env.DROPBEAR_LOG_MAX_LINES || 12000);
const DROPBEAR_LOG_MAX_LINES = Number.isFinite(DROPBEAR_LOG_MAX_LINES_RAW) && DROPBEAR_LOG_MAX_LINES_RAW >= 2000
  ? Math.min(Math.floor(DROPBEAR_LOG_MAX_LINES_RAW), 80000)
  : 12000;
const DROPBEAR_RECENT_LOG_MAX_LINES_RAW = Number(process.env.DROPBEAR_RECENT_LOG_MAX_LINES || 5000);
const DROPBEAR_RECENT_LOG_MAX_LINES = Number.isFinite(DROPBEAR_RECENT_LOG_MAX_LINES_RAW) && DROPBEAR_RECENT_LOG_MAX_LINES_RAW >= 500
  ? Math.min(Math.floor(DROPBEAR_RECENT_LOG_MAX_LINES_RAW), 30000)
  : 5000;
const IPLIMIT_DEBUG = String(process.env.IPLIMIT_DEBUG || '0').trim() === '1';

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
function safeExec(cmd, args, input) {
  try {
    const opts = { stdio: ['pipe', 'ignore', 'ignore'] };
    if (typeof input === 'string') opts.input = input;
    execFileSync(cmd, args, opts);
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

function addPortToUserMap(map, username, port) {
  const u = String(username || '').trim().toLowerCase();
  const p = String(port || '').trim();
  if (!u || !/^[0-9]{1,5}$/.test(p) || u === 'root') return;
  if (!map.has(u)) map.set(u, new Set());
  map.get(u).add(p);
}

function extractIp(raw) {
  let v = String(raw || '').trim();
  if (!v) return '';
  v = v.replace(/^\[/, '').replace(/\]$/, '');
  v = v.replace(/:[0-9]+$/, '');
  return v;
}

function extractPort(raw) {
  const s = String(raw || '').trim();
  if (!s) return '';
  const m = s.match(/:([0-9]{1,5})$/);
  return m ? m[1] : '';
}

function isLoopbackIp(ip) {
  const v = String(ip || '').trim().toLowerCase();
  return v === '127.0.0.1' || v === '::1' || v === 'localhost';
}

function getDropbearPortSet() {
  const ports = [DROPBEAR_PORT, DROPBEAR_ALT_PORT, '22']
    .map((v) => String(v || '').trim())
    .filter((v) => /^[0-9]{1,5}$/.test(v));
  if (ports.length === 0) return new Set(['109', '143', '22']);
  return new Set(ports);
}

function parseDropbearAuthLine(lineRaw) {
  const line = String(lineRaw || '').trim();
  if (!line || !/auth succeeded/i.test(line)) return null;

  const userMatch =
    line.match(/auth succeeded for ['"]([^'"]+)['"]/i) ||
    line.match(/auth succeeded for ([^\s'"`]+)/i);
  if (!userMatch) return null;

  const fromMatch = line.match(/ from (.+?)(?::([0-9]{1,5}))?\s*$/i);
  const username = String(userMatch[1] || '').trim().toLowerCase();
  const source = String(fromMatch?.[1] || '').replace(/\s+/g, '').trim();
  const port = String(fromMatch?.[2] || '').trim();
  if (!username || !port) return null;

  const pidMatch = line.match(/\[([0-9]+)\]/);
  const pid = String(pidMatch?.[1] || '').trim();
  return { username, source, port, pid };
}

function parseDropbearExitLine(lineRaw) {
  const line = String(lineRaw || '').trim();
  if (!line) return null;
  if (!/Exit \(|Exit before auth:/i.test(line)) return null;
  const pidMatch = line.match(/\[([0-9]+)\]/);
  const pid = String(pidMatch?.[1] || '').trim();
  if (!pid) return null;
  return { pid };
}

function parseSshAndUdpUsage() {
  const ipMap = new Map();
  const sessionMap = new Map();
  const recentAuthMap = new Map();
  const procSessionMap = new Map();
  const wsClientPortMap = new Map();
  const dropbearPorts = getDropbearPortSet();
  const dropbearActiveClientPorts = new Set();

  // SSH realtime (native sshd): established sockets + sshd PID owner -> username.
  const pidIpMap = new Map();
  let ssOut = '';
  try {
    ssOut = execFileSync('ss', ['-Htnp', 'state', 'established'], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  } catch (_) {}
  for (const lineRaw of String(ssOut || '').split('\n')) {
    const line = String(lineRaw || '').trim();
    if (!line) continue;
    const cols = line.split(/\s+/);
    const local = String(cols[3] || '');
    const remote = String(cols[4] || '');

    const lport = extractPort(local);
    const rport = extractPort(remote);
    const lip = extractIp(local);
    const rip = extractIp(remote);

    // Keep traditional sshd mapping for direct SSH sessions.
    if (lport === '22') {
      const ip = rip;
      if (ip) {
        const pids = Array.from(line.matchAll(/pid=(\d+)/g)).map((m) => Number(m[1])).filter((n) => Number.isInteger(n) && n > 0);
        for (const pid of new Set(pids)) {
          if (!pidIpMap.has(pid)) pidIpMap.set(pid, new Set());
          pidIpMap.get(pid).add(ip);
        }
      }
    }

    // For HC/ssh-mux path, count unique active client-side ports to dropbear.
    if (dropbearPorts.has(lport) && rport) {
      dropbearActiveClientPorts.add(rport);
    } else if (dropbearPorts.has(rport) && lport) {
      dropbearActiveClientPorts.add(lport);
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

  // Dropbear auth sessions (HC/WS friendly):
  // map "password auth succeeded" -> active client port on localhost tunnel.
  let dropbearLog = '';
  try {
    dropbearLog = execFileSync(
      'journalctl',
      ['-u', 'dropbear', '-n', String(DROPBEAR_LOG_MAX_LINES), '--no-pager'],
      { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }
    );
  } catch (_) {}
  for (const lineRaw of String(dropbearLog || '').split('\n')) {
    const parsed = parseDropbearAuthLine(lineRaw);
    if (!parsed) continue;
    const user = parsed.username;
    const src = parsed.source;
    const clientPort = parsed.port;
    if (!user || !clientPort) continue;
    if (!dropbearActiveClientPorts.has(clientPort)) continue;
    addSessionKeyToUserMap(sessionMap, user, `dropbear-port:${clientPort}`);
    addIpToUserMap(ipMap, user, extractIp(src));
    addPortToUserMap(wsClientPortMap, user, clientPort);
  }

  // Recent auth fallback (HC often rotates sessions quickly, so active socket mapping can miss).
  let dropbearRecent = '';
  try {
    dropbearRecent = execFileSync(
      'journalctl',
      ['-u', 'dropbear', '--since', `-${RECENT_AUTH_WINDOW_MINUTES} min`, '-n', String(DROPBEAR_RECENT_LOG_MAX_LINES), '--no-pager'],
      { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }
    );
  } catch (_) {}
  const recentAuthByPid = new Map();
  const closedRecentPid = new Set();
  for (const lineRaw of String(dropbearRecent || '').split('\n')) {
    const auth = parseDropbearAuthLine(lineRaw);
    if (auth) {
      const user = auth.username;
      const srcIp = extractIp(auth.source);
      const clientPort = auth.port;
      const pid = String(auth.pid || '').trim();
      if (!user || !clientPort) continue;
      if (srcIp) {
        const recentKey = isLoopbackIp(srcIp)
          ? `dropbear-recent-port:${clientPort}`
          : `dropbear-recent-ip:${srcIp}`;
        if (pid) {
          recentAuthByPid.set(pid, { user, recentKey, clientPort });
        } else {
          addSessionKeyToUserMap(recentAuthMap, user, recentKey);
        }
      }
      if (dropbearActiveClientPorts.has(clientPort)) {
        addPortToUserMap(wsClientPortMap, user, clientPort);
      }
      continue;
    }
    const ex = parseDropbearExitLine(lineRaw);
    if (ex) {
      closedRecentPid.add(ex.pid);
    }
  }
  for (const [pid, data] of recentAuthByPid.entries()) {
    if (closedRecentPid.has(pid)) continue;
    addSessionKeyToUserMap(recentAuthMap, data.user, data.recentKey);
    if (dropbearActiveClientPorts.has(data.clientPort)) {
      addPortToUserMap(wsClientPortMap, data.user, data.clientPort);
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

  // Fallback HC: hitung sesi dari process list (tetap terbaca meski 1 IP/Wi-Fi).
  let psAll = '';
  try {
    psAll = execFileSync('ps', ['-eo', 'pid=,args='], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  } catch (_) {}
  for (const lineRaw of String(psAll || '').split('\n')) {
    const mm = String(lineRaw || '').match(/^\s*(\d+)\s+(.*)$/);
    if (!mm) continue;
    const pid = Number(mm[1]);
    const args = String(mm[2] || '').trim();
    if (!args) continue;
    let user = '';
    if (/^sshd:\s+/i.test(args)) {
      if (/\[(priv|preauth|listener)\]/i.test(args)) continue;
      user = args.replace(/^sshd:\s*/i, '').split(/\s+/)[0] || '';
      user = user.replace(/@.*$/, '').replace(/\[.*$/, '');
    } else if (/^dropbear[^\s]*\s+\[[^\]]+\]/i.test(args) || /\/dropbear-[^\s]+\s+\[[^\]]+\]/i.test(args)) {
      const m = args.match(/\[([^\]]+)\]/);
      user = String(m?.[1] || '').trim();
    } else {
      continue;
    }
    user = user.toLowerCase();
    if (!/^[a-z0-9._-]+$/.test(user)) continue;
    if (user === 'root' || user === 'priv' || user === 'net') continue;
    addSessionKeyToUserMap(procSessionMap, user, `proc-pid:${pid}`);
  }

  // Catatan: keputusan lock akun SSH dihitung dari data SSH/Dropbear/WSS saja.
  // Jangan campur log UDPHC di sini agar perilaku lock SSH konsisten.
  return { ipMap, sessionMap, recentAuthMap, procSessionMap, wsClientPortMap };
}

function parseXrayRecentIpMap() {
  const map = new Map();
  const path = '/var/log/xray/access.log';
  if (!fs.existsSync(path)) return map;
  let tailOut = '';
  try {
    tailOut = execFileSync('tail', ['-n', String(XRAY_LOG_TAIL_LINES), path], { encoding: 'utf8', maxBuffer: 12 * 1024 * 1024 });
  } catch (_) {
    return map;
  }
  const nowMs = Date.now();
  const cutoffTs = nowMs - (XRAY_RECENT_WINDOW_MINUTES * 60 * 1000);
  const activeCutoffTs = nowMs - (XRAY_ACTIVE_WINDOW_SECONDS * 1000);
  const hitMap = new Map();
  const lastSeenMap = new Map();
  const latestIpByUser = new Map();
  const latestTsByUser = new Map();
  const lines = String(tailOut || '').split('\n');
  for (const lineRaw of lines) {
    const line = String(lineRaw || '').trim();
    if (!line) continue;
    let ts = 0;
    const tm = line.match(/^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})/);
    if (tm) {
      ts = new Date(
        Number(tm[1]),
        Number(tm[2]) - 1,
        Number(tm[3]),
        Number(tm[4]),
        Number(tm[5]),
        Number(tm[6]),
        0
      ).getTime();
      if (Number.isFinite(ts) && ts < cutoffTs) continue;
    }
    const emailJson = line.match(/"email":"([^"]+)"/);
    const emailTxt = line.match(/\bemail:\s*([^\s]+)/i);
    const email = String(emailJson?.[1] || emailTxt?.[1] || '').trim().toLowerCase();
    if (!email) continue;
    const srcJson = line.match(/"source":"([^"]+)"/);
    const srcTxt = line.match(/\bfrom\s+([0-9a-fA-F\.:]+)/i);
    const src = String(srcJson?.[1] || srcTxt?.[1] || '').trim();
    const ip = extractIp(src);
    if (!ip) continue;
    const key = `${email}|${ip}`;
    hitMap.set(key, (hitMap.get(key) || 0) + 1);
    const lastSeen = Number.isFinite(ts) && ts > 0 ? ts : nowMs;
    lastSeenMap.set(key, lastSeen);
    const prevTs = latestTsByUser.get(email) || 0;
    if (lastSeen >= prevTs) {
      latestTsByUser.set(email, lastSeen);
      latestIpByUser.set(email, ip);
    }
  }

  for (const [key, hits] of hitMap.entries()) {
    const sep = key.indexOf('|');
    if (sep <= 0) continue;
    const email = key.slice(0, sep);
    const ip = key.slice(sep + 1);
    const lastSeen = lastSeenMap.get(key) || 0;
    const isActive = lastSeen >= activeCutoffTs;
    const isLatestIp = latestIpByUser.get(email) === ip;
    if (!isActive) continue;
    if (!isLatestIp && hits < XRAY_MIN_HITS_PER_IP) continue;
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

function removeUdpcustomUser(secret) {
  try {
    const key = String(secret || '').trim();
    if (!key) return false;
    if (!fs.existsSync(UDPCUSTOM_CONFIG)) return false;
    const root = JSON.parse(fs.readFileSync(UDPCUSTOM_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') return false;
    if (!Array.isArray(root.auth.config)) return false;
    const before = root.auth.config.length;
    root.auth.config = root.auth.config.filter((v) => String(v || '').trim() !== key);
    const changed = root.auth.config.length !== before;
    if (changed) fs.writeFileSync(UDPCUSTOM_CONFIG, JSON.stringify(root, null, 2));
    return changed;
  } catch (_) {
    return false;
  }
}

function addUdpcustomUser(secret) {
  try {
    const key = String(secret || '').trim();
    if (!key) return false;
    let root = { auth: { mode: 'passwords', config: [] } };
    if (fs.existsSync(UDPCUSTOM_CONFIG)) root = JSON.parse(fs.readFileSync(UDPCUSTOM_CONFIG, 'utf8'));
    if (!root.auth || typeof root.auth !== 'object') root.auth = {};
    if (!Array.isArray(root.auth.config)) root.auth.config = [];
    root.auth.mode = 'passwords';
    const set = new Set(root.auth.config.map((v) => String(v || '').trim()).filter(Boolean));
    const before = set.size;
    set.add(key);
    const changed = set.size !== before;
    root.auth.config = Array.from(set);
    if (changed) fs.writeFileSync(UDPCUSTOM_CONFIG, JSON.stringify(root, null, 2));
    return changed;
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

function shouldRestartUdpcustom() {
  if (ACTIVE_UDP_BACKEND === 'zivpn') {
    return false;
  }
  if (ACTIVE_UDP_BACKEND === 'udpcustom' || ACTIVE_UDP_BACKEND === 'udp-custom' || ACTIVE_UDP_BACKEND === 'udphc') {
    return true;
  }
  return safeExec('systemctl', ['is-active', '--quiet', UDPCUSTOM_SERVICE]);
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

function nftDropSnippet(ip, proto, port) {
  const fam = isIpv6(ip) ? 'ip6' : 'ip';
  return `${fam} saddr ${ip} ${proto} dport ${port} drop`;
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

function addNftDropRule(ip, proto, port) {
  const chain = detectNftInputChain();
  if (!chain) return false;
  const src = String(ip || '').trim();
  const p = String(proto || '').trim().toLowerCase();
  const dport = String(port);
  if (!src || (p !== 'tcp' && p !== 'udp')) return false;
  const fam = isIpv6(src) ? 'ip6' : 'ip';
  const chainDump = readExec('nft', ['list', 'chain', ...chain]);
  if (chainDump.includes(nftDropSnippet(src, p, dport))) return true;
  return safeExec('nft', ['add', 'rule', ...chain, fam, 'saddr', src, p, 'dport', dport, 'drop']);
}

function removeNftDropRule(ip, proto, port) {
  const chain = detectNftInputChain();
  if (!chain) return;
  const src = String(ip || '').trim();
  const p = String(proto || '').trim().toLowerCase();
  const dport = String(port);
  if (!src || (p !== 'tcp' && p !== 'udp')) return;
  const fam = isIpv6(src) ? 'ip6' : 'ip';
  while (safeExec('nft', ['delete', 'rule', ...chain, fam, 'saddr', src, p, 'dport', dport, 'drop'])) {}
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
    return addNftDropRule(src, 'udp', port);
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
    removeNftDropRule(src, 'udp', port);
  }
}

function addTcpDropRule(ip, port) {
  const src = String(ip || '').trim();
  if (!src) return false;
  if (safeExec('iptables', ['-L'])) {
    const cmd = isIpv6(src) ? 'ip6tables' : 'iptables';
    const rule = ['INPUT', '-p', 'tcp', '-s', src, '--dport', String(port), '-j', 'DROP'];
    if (safeExec(cmd, ['-C', ...rule])) return true;
    return safeExec(cmd, ['-I', ...rule]);
  }
  if (safeExec('nft', ['list', 'ruleset'])) {
    return addNftDropRule(src, 'tcp', port);
  }
  return false;
}

function removeTcpDropRule(ip, port) {
  const src = String(ip || '').trim();
  if (!src) return;
  if (safeExec('iptables', ['-L'])) {
    const cmd = isIpv6(src) ? 'ip6tables' : 'iptables';
    const rule = ['INPUT', '-p', 'tcp', '-s', src, '--dport', String(port), '-j', 'DROP'];
    while (safeExec(cmd, ['-D', ...rule])) {}
    return;
  }
  if (safeExec('nft', ['list', 'ruleset'])) {
    removeNftDropRule(src, 'tcp', port);
  }
}

function normalizeRuleSource(raw) {
  let s = String(raw || '').trim();
  if (!s) return '';
  s = s.replace(/\/(32|128)$/, '');
  return s;
}

function listCurrentTcpDropRuleIps(port, ipv6 = false) {
  const cmd = ipv6 ? 'ip6tables-save' : 'iptables-save';
  const out = readExec(cmd, []);
  const set = new Set();
  if (!out) return set;
  const dport = String(port);
  for (const lineRaw of String(out).split('\n')) {
    const line = String(lineRaw || '').trim();
    if (!line.startsWith('-A INPUT ')) continue;
    if (!line.includes(' -p tcp ')) continue;
    if (!line.includes(` --dport ${dport} `)) continue;
    if (!line.endsWith(' -j DROP')) continue;
    const m = line.match(/-s\s+([^\s]+)/);
    const src = normalizeRuleSource(m?.[1] || '');
    if (!src) continue;
    set.add(src);
  }
  return set;
}

async function cleanupOrphanXrayDropRules() {
  const expectedRows = await all(
    "SELECT DISTINCT ip FROM temp_ip_lock_ips WHERE account_type IN ('vmess','vless','trojan')"
  ).catch(() => []);
  const expected = new Set(
    expectedRows
      .map((r) => normalizeRuleSource(String(r?.ip || '').trim()))
      .filter(Boolean)
  );

  let removed = 0;
  for (const p of XRAY_BLOCK_TCP_PORTS) {
    const ipv4Set = listCurrentTcpDropRuleIps(p, false);
    for (const ip of ipv4Set) {
      if (expected.has(ip)) continue;
      removeTcpDropRule(ip, p);
      removed += 1;
    }
    const ipv6Set = listCurrentTcpDropRuleIps(p, true);
    for (const ip of ipv6Set) {
      if (expected.has(ip)) continue;
      removeTcpDropRule(ip, p);
      removed += 1;
    }
  }
  if (IPLIMIT_DEBUG && removed > 0) {
    console.log(`[iplimit-debug][xray] orphan tcp-drop removed=${removed}`);
  }
}

function disconnectXrayIpNow(ip) {
  const src = String(ip || '').trim();
  if (!src) return;

  // Kill only sockets related to public ingress ports (avoid broad collateral drops).
  for (const p of XRAY_BLOCK_TCP_PORTS) {
    safeExec('ss', ['-K', 'dst', src, 'dport', '=', `:${p}`]);
    safeExec('ss', ['-K', 'dst', src, 'sport', '=', `:${p}`]);
    safeExec('ss', ['-K', 'src', src, 'dport', '=', `:${p}`]);
    safeExec('ss', ['-K', 'src', src, 'sport', '=', `:${p}`]);
    // Compatibility fallback for older iproute2 expression parsing.
    safeExec('ss', ['-K', `dst ${src} dport = :${p}`]);
    safeExec('ss', ['-K', `src ${src} sport = :${p}`]);
  }

  // If conntrack exists, drop tracked flows so packets are cut immediately.
  if (safeExec('conntrack', ['-V'])) {
    for (const p of XRAY_BLOCK_TCP_PORTS) {
      safeExec('conntrack', ['-D', '-p', 'tcp', '-s', src, '--dport', String(p)]);
      safeExec('conntrack', ['-D', '-p', 'tcp', '-d', src, '--sport', String(p)]);
    }
  }
}

function disconnectSshWsByClientPorts(ports) {
  const list = Array.from(new Set((ports || []).map((v) => String(v || '').trim()).filter((v) => /^[0-9]{1,5}$/.test(v))));
  for (const p of list) {
    safeExec('ss', ['-K', `sport = :${p}`]);
    safeExec('ss', ['-K', `dport = :${p}`]);
    safeExec('ss', ['-K', `src 127.0.0.1 sport = :${p}`]);
    safeExec('ss', ['-K', `src 127.0.0.1 dport = :${p}`]);
    safeExec('ss', ['-K', `src ::1 sport = :${p}`]);
    safeExec('ss', ['-K', `src ::1 dport = :${p}`]);
  }
}

function extractClientPortsFromSessionKeys(keys) {
  const out = new Set();
  if (!keys || typeof keys[Symbol.iterator] !== 'function') return out;
  for (const raw of keys) {
    const s = String(raw || '').trim().toLowerCase();
    if (!s) continue;
    const m = s.match(/(?:^|:)([0-9]{1,5})$/);
    if (!m) continue;
    out.add(m[1]);
  }
  return out;
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
  if (rows.length === 0) return { zivpnChanged: false, udpcustomChanged: false, xrayChanged: false };

  const udpcustomPort = getUdpCustomListenPort();
  let zivpnChanged = false;
  let udpcustomChanged = false;
  let xrayChanged = false;
  for (const row of rows) {
    const t = String(row.account_type || '');
    const u = String(row.username || '');
    const ipRows = await all("SELECT ip FROM temp_ip_lock_ips WHERE account_type=? AND username=?", [t, u]).catch(() => []);
    if (t === 'ssh') {
      for (const item of ipRows) {
        removeUdpDropRule(String(item?.ip || ''), udpcustomPort);
      }
    } else if (t === 'vmess' || t === 'vless' || t === 'trojan') {
      for (const item of ipRows) {
        const ip = String(item?.ip || '');
        for (const p of XRAY_BLOCK_TCP_PORTS) {
          removeTcpDropRule(ip, p);
        }
      }
    }
    if (t === 'ssh') {
      const sshRow = await get("SELECT password, date_exp FROM account_sshs WHERE LOWER(username)=LOWER(?)", [u]).catch(() => null);
      const pass = String(sshRow?.password || '').trim();
      const expDate = String(sshRow?.date_exp || '').trim();
      // Selalu sinkronkan ulang kredensial Linux dari DB saat unlock.
      if (pass) {
        safeExec('chpasswd', [], `${u}:${pass}\n`);
      }
      safeExec('usermod', ['-s', '/bin/bash', u]);
      if (/^\d{4}-\d{2}-\d{2}$/.test(expDate)) {
        safeExec('chage', ['-E', expDate, u]);
      }
      let unlocked = safeExec('passwd', ['-u', u]) || safeExec('usermod', ['-U', u]);
      if (!unlocked && pass) {
        safeExec('chpasswd', [], `${u}:${pass}\n`);
        unlocked = safeExec('passwd', ['-u', u]) || safeExec('usermod', ['-U', u]);
      }
      await run("UPDATE account_sshs SET status='AKTIF' WHERE LOWER(username)=LOWER(?)", [u]).catch(() => {});
      if (Number(row.zivpn_removed || 0) === 1) {
        if (addZivpnUser(u)) zivpnChanged = true;
      }
      if (pass) {
        if (addUdpcustomUser(pass)) udpcustomChanged = true;
      } else if (addUdpcustomUser(u)) {
        udpcustomChanged = true;
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
  return { zivpnChanged, udpcustomChanged, xrayChanged };
}

async function lockIfExceeded(nowTs) {
  const sshUsage = parseSshAndUdpUsage();
  const sshIpMap = sshUsage.ipMap;
  const sshSessionMap = sshUsage.sessionMap;
  const sshRecentAuthMap = sshUsage.recentAuthMap || new Map();
  const sshProcSessionMap = sshUsage.procSessionMap || new Map();
  const sshWsClientPortMap = sshUsage.wsClientPortMap || new Map();
  const xrayMap = parseXrayRecentIpMap();
  const udpcustomPort = getUdpCustomListenPort();
  let zivpnChanged = false;
  let udpcustomChanged = false;
  let xrayChanged = false;

  const sshRows = await all("SELECT username, password, limitip FROM account_sshs WHERE UPPER(TRIM(COALESCE(status,'')))='AKTIF' AND CAST(COALESCE(limitip,0) AS INTEGER) > 0");
  for (const r of sshRows) {
    const user = String(r.username || '').trim();
    const pass = String(r.password || '').trim();
    const userKey = user.toLowerCase();
    const passKey = pass.toLowerCase();
    const keyCandidates = passKey && passKey !== userKey ? [userKey, passKey] : [userKey];
    const setMaxSize = (m) => {
      let max = 0;
      for (const k of keyCandidates) {
        if (m.has(k)) {
          const n = m.get(k).size;
          if (n > max) max = n;
        }
      }
      return max;
    };
    const setUnionValues = (m) => {
      const out = new Set();
      for (const k of keyCandidates) {
        if (!m.has(k)) continue;
        for (const v of m.get(k)) out.add(v);
      }
      return out;
    };
    const lim = Number(r.limitip || 0);
    const cntIp = setMaxSize(sshIpMap);
    const cntSession = setMaxSize(sshSessionMap);
    const cntWsPorts = setMaxSize(sshWsClientPortMap);
    const cntRecent = setMaxSize(sshRecentAuthMap);
    const cntProc = setMaxSize(sshProcSessionMap);
    // Sumber realtime utama:
    // - ipMap/sessionMap untuk SSH normal
    // - wsClientPortMap untuk jalur HC/WS (satu koneksi = satu client port)
    const cntActive = Math.max(cntIp, cntSession, cntWsPorts);
    // proc/recent dipakai sebagai fallback kuantitatif ringan (cap) agar kasus 2 HP tetap terdeteksi.
    // recent sudah dedup berdasarkan source IP, jadi tidak overcount karena port reconnect.
    const cntProcHint = Math.min(Math.max(cntProc, 0), 3);
    const cntRecentHint = Math.min(Math.max(cntRecent, 0), 3);
    const cnt = Math.max(cntActive, cntProcHint, cntRecentHint);
    if (IPLIMIT_DEBUG) {
      console.log(`[iplimit-debug][ssh] user=${user} lim=${lim} cntIp=${cntIp} cntSession=${cntSession} cntWsPorts=${cntWsPorts} cntProc=${cntProc} cntRecent=${cntRecent} cnt=${cnt}`);
    }
    if (cnt <= lim) continue;
    const exists = await get("SELECT 1 AS ok FROM temp_ip_locks WHERE account_type='ssh' AND username=?", [user]);
    if (exists) continue;

    // Putuskan sesi aktif SSH user yang baru di-lock.
    safeExec('pkill', ['-KILL', '-u', user]);
    safeExec('pkill', ['-KILL', '-f', `sshd: ${user}`]);
    safeExec('pkill', ['-KILL', '-f', `dropbear.*\\[${user}\\]`]);
    const activeWsPorts = Array.from(setUnionValues(sshWsClientPortMap));
    const recentAuthPorts = Array.from(extractClientPortsFromSessionKeys(setUnionValues(sshRecentAuthMap)));
    const sessionPorts = Array.from(extractClientPortsFromSessionKeys(setUnionValues(sshSessionMap)));
    disconnectSshWsByClientPorts(Array.from(new Set([...activeWsPorts, ...recentAuthPorts, ...sessionPorts])));
    safeExec('passwd', ['-l', user]);

    // Untuk UDPHC: drop semua src IP aktif user ini selama masa lock.
    const lockIps = Array.from(setUnionValues(sshIpMap));
    await run("DELETE FROM temp_ip_lock_ips WHERE account_type='ssh' AND username=?", [user]).catch(() => {});
    for (const ip of lockIps) {
      if (addUdpDropRule(ip, udpcustomPort)) {
        await run("INSERT OR IGNORE INTO temp_ip_lock_ips(account_type, username, ip) VALUES('ssh', ?, ?)", [user, ip]).catch(() => {});
      }
    }

    const removed = removeZivpnUser(user) ? 1 : 0;
    if (removed) zivpnChanged = true;
    let udphcSecretChanged = false;
    if (pass) {
      if (removeUdpcustomUser(pass)) udphcSecretChanged = true;
    }
    if (removeUdpcustomUser(user)) udphcSecretChanged = true;
    if (udphcSecretChanged) udpcustomChanged = true;
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
      const lockIpSet = xrayMap.has(userKey) ? xrayMap.get(userKey) : new Set();
      const cnt = lockIpSet.size;
      if (IPLIMIT_DEBUG) {
        const ips = Array.from(lockIpSet).slice(0, 8).join(',');
        console.log(`[iplimit-debug][${item.type}] user=${user} lim=${lim} cnt=${cnt} ips=${ips}`);
      }
      if (cnt <= lim) continue;
      const exists = await get("SELECT 1 AS ok FROM temp_ip_locks WHERE account_type=? AND username=?", [item.type, user]);
      if (exists) continue;
      const lockIps = Array.from(lockIpSet);
      await run("DELETE FROM temp_ip_lock_ips WHERE account_type=? AND username=?", [item.type, user]).catch(() => {});
      for (const ipRaw of lockIps) {
        const ip = String(ipRaw || '').trim();
        if (!ip) continue;
        let blocked = false;
        for (const p of XRAY_BLOCK_TCP_PORTS) {
          if (addTcpDropRule(ip, p)) blocked = true;
        }
        if (blocked) {
          // Force-cut active session so lock is effective immediately.
          disconnectXrayIpNow(ip);
        }
        if (blocked) {
          await run("INSERT OR IGNORE INTO temp_ip_lock_ips(account_type, username, ip) VALUES(?, ?, ?)", [item.type, user, ip]).catch(() => {});
        }
      }
      await run(`UPDATE ${item.table} SET status='LOCK_TMP' WHERE LOWER(username)=LOWER(?)`, [user]).catch(() => {});
      await run("INSERT OR REPLACE INTO temp_ip_locks(account_type, username, locked_until, zivpn_removed) VALUES(?, ?, ?, 0)", [item.type, user, nowTs + LOCK_SECONDS]).catch(() => {});
      xrayChanged = true;
    }
  }
  return { zivpnChanged, udpcustomChanged, xrayChanged };
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
  if (!safeExec('systemctl', ['reload', 'xray'])) {
    safeExec('systemctl', ['kill', '-s', 'HUP', 'xray']);
  }
}

async function main() {
  const now = Math.floor(Date.now() / 1000);
  await ensureTables();
  const u = await unlockExpired(now);
  const l = await lockIfExceeded(now);
  await cleanupOrphanXrayDropRules().catch(() => {});
  if (u.xrayChanged || l.xrayChanged) {
    await rebuildXrayFromDb().catch(() => {});
  }
  if ((u.zivpnChanged || l.zivpnChanged) && shouldRestartZivpn()) {
    restartService(ZIVPN_SERVICE);
  }
  if ((u.udpcustomChanged || l.udpcustomChanged) && shouldRestartUdpcustom()) {
    restartService(UDPCUSTOM_SERVICE);
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
  local iplimit_interval_min
  iplimit_interval_min="$(echo "${IPLIMIT_CHECK_INTERVAL_MINUTES}" | tr -cd '0-9')"
  if [[ -z "${iplimit_interval_min}" || "${iplimit_interval_min}" -lt 1 || "${iplimit_interval_min}" -gt 1440 ]]; then
    iplimit_interval_min="10"
  fi

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
MemoryMax=512M

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

  cat > /etc/systemd/system/sc-1forcr-iplimit.timer <<EOF
[Unit]
Description=Run SC 1FORCR IP Limit Checker every ${iplimit_interval_min} minutes

[Timer]
OnBootSec=15s
OnUnitActiveSec=${iplimit_interval_min}min
AccuracySec=1s
RandomizedDelaySec=0
Persistent=true
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

setup_udp_bootfix_service() {
  log "Setup UDP boot-fix service..."

  cat > /usr/local/sbin/sc-1forcr-udp-bootfix <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/sc-1forcr.env"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}" || true

ZIVPN_SERVICE="${ZIVPN_SERVICE:-zivpn}"
UDPCUSTOM_SERVICE="${UDPCUSTOM_SERVICE:-sc-1forcr-udpcustom}"
ACTIVE_UDP_BACKEND="$(echo "${ACTIVE_UDP_BACKEND:-zivpn}" | tr '[:upper:]' '[:lower:]')"
ZIVPN_DNAT_RANGE="${ZIVPN_DNAT_RANGE:-6000:19999}"
UDPCUSTOM_DNAT_RANGE="${UDPCUSTOM_DNAT_RANGE:-}"
UDPCUSTOM_DNAT_AUTO_RANGE="${UDPCUSTOM_DNAT_AUTO_RANGE:-6000:6999}"

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
  local port="$1"
  case "$(fw_backend_kind)" in
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
      fi
      ;;
  esac
}

fw_add_udp_dnat_range() {
  local range="$1" to_port="$2"
  [[ -z "${range}" ]] && return 0
  case "$(fw_backend_kind)" in
    iptables)
      iptables -t nat -C PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1 || \
        iptables -t nat -I PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}"
      ;;
    nft)
      local range_nft
      range_nft="${range/:/-}"
      nft add table ip nat >/dev/null 2>&1 || true
      nft 'add chain ip nat prerouting { type nat hook prerouting priority dstnat; }' >/dev/null 2>&1 || true
      nft list chain ip nat prerouting 2>/dev/null | grep -F -- "udp dport ${range_nft} dnat to :${to_port}" >/dev/null 2>&1 || \
        nft add rule ip nat prerouting udp dport "${range_nft}" dnat to ":${to_port}"
      ;;
  esac
}

fw_delete_udp_dnat_range() {
  local range="$1" to_port="$2"
  [[ -z "${range}" ]] && return 0
  case "$(fw_backend_kind)" in
    iptables)
      while iptables -t nat -C PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp --dport "${range}" -j DNAT --to-destination ":${to_port}" >/dev/null 2>&1 || break
      done
      ;;
    nft)
      local range_nft handle
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

zivpn_port="$(jq -r '.listen // empty' /etc/zivpn/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
[[ -z "${zivpn_port}" ]] && zivpn_port="5667"
udphc_port="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
[[ -z "${udphc_port}" ]] && udphc_port="5667"

case "${ACTIVE_UDP_BACKEND}" in
  udpcustom|udp-custom|udphc)
    systemctl disable --now "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    systemctl enable "${UDPCUSTOM_SERVICE}" >/dev/null 2>&1 || true
    systemctl restart "${UDPCUSTOM_SERVICE}" >/dev/null 2>&1 || true
    fw_allow_udp_input "${udphc_port}"
    range="${UDPCUSTOM_DNAT_RANGE}"
    [[ -z "${range}" ]] && range="${UDPCUSTOM_DNAT_AUTO_RANGE}"
    fw_add_udp_dnat_range "${range}" "${udphc_port}"
    fw_delete_udp_dnat_range "${ZIVPN_DNAT_RANGE}" "${udphc_port}"
    ;;
  *)
    systemctl disable --now "${UDPCUSTOM_SERVICE}" >/dev/null 2>&1 || true
    systemctl enable "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    systemctl restart "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
    fw_allow_udp_input "${zivpn_port}"
    fw_add_udp_dnat_range "${ZIVPN_DNAT_RANGE}" "${zivpn_port}"
    ;;
esac

fw_persist_rules
EOF
  chmod +x /usr/local/sbin/sc-1forcr-udp-bootfix

  cat > /etc/systemd/system/sc-1forcr-udp-bootfix.service <<'EOF'
[Unit]
Description=SC 1FORCR UDP Boot Fix
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sc-1forcr-udp-bootfix
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now sc-1forcr-udp-bootfix.service >/dev/null 2>&1 || true
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

setup_auto_backup_timer() {
  log "Setup auto backup harian kirim Telegram jam 02:00 WIB..."

  cat > /usr/local/sbin/sc-1forcr-auto-backup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/sc-1forcr.env"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}" || true

DOMAIN="${DOMAIN:-unknown}"
DB_PATH="${DB_PATH:-/usr/sbin/potatonc/potato.db}"
AUTO_BACKUP_ENABLE="${AUTO_BACKUP_ENABLE:-1}"
AUTO_BACKUP_DIR="${AUTO_BACKUP_DIR:-/root/backup-sc-1forcr}"
AUTO_BACKUP_KEEP_DAYS="${AUTO_BACKUP_KEEP_DAYS:-7}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

mode="${1:-manual}"
mkdir -p "${AUTO_BACKUP_DIR}" /var/lib/sc-1forcr

if [[ "${AUTO_BACKUP_ENABLE}" != "1" ]]; then
  exit 0
fi

if [[ "${mode}" == "scheduled" ]]; then
  wib_hour="$(TZ=Asia/Jakarta date +%H)"
  wib_date="$(TZ=Asia/Jakarta date +%F)"
  stamp_file="/var/lib/sc-1forcr/last-auto-backup-date"
  last_date="$(cat "${stamp_file}" 2>/dev/null || true)"
  [[ "${wib_hour}" == "02" ]] || exit 0
  [[ "${last_date}" == "${wib_date}" ]] && exit 0
fi

ts_wib="$(TZ=Asia/Jakarta date +%Y%m%d-%H%M%S)"
backup_json="${AUTO_BACKUP_DIR}/sc1forcr-accounts-${ts_wib}-WIB.json"

if [[ ! -f "${DB_PATH}" ]]; then
  echo "DB tidak ditemukan: ${DB_PATH}"
  exit 1
fi

python3 - "${DB_PATH}" "${DOMAIN}" "${backup_json}" <<'PY'
import json
import sqlite3
import sys
from datetime import datetime, timezone

db_path = sys.argv[1]
domain = sys.argv[2]
out_path = sys.argv[3]

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

def fetch(table, cols):
    q = "SELECT " + ",".join(cols) + f" FROM {table} ORDER BY username"
    try:
        rows = cur.execute(q).fetchall()
    except Exception:
        return []
    out = []
    for r in rows:
        item = {}
        for c in cols:
            item[c] = r[c]
        out.append(item)
    return out

payload = {
    "meta": {
        "format": "sc1forcr-accounts-backup-v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_domain": domain or "unknown",
    },
    "data": {
        "ssh": fetch("account_sshs", ["username", "password", "date_exp", "status", "quota", "limitip", "owner_telegram_id", "owner_telegram_chat_id"]),
        "vmess": fetch("account_vmesses", ["username", "uuid", "date_exp", "status", "quota", "limitip", "owner_telegram_id", "owner_telegram_chat_id"]),
        "vless": fetch("account_vlesses", ["username", "uuid", "date_exp", "status", "quota", "limitip", "owner_telegram_id", "owner_telegram_chat_id"]),
        "trojan": fetch("account_trojans", ["username", "password", "date_exp", "status", "quota", "limitip", "owner_telegram_id", "owner_telegram_chat_id"]),
        "zivpn_auth": [],
        "banner_html": "",
        "banner_txt": "",
    },
}

try:
    with open("/etc/zivpn/config.json", "r", encoding="utf-8") as f:
        zcfg = json.load(f)
    auth = ((zcfg or {}).get("auth") or {}).get("config")
    if isinstance(auth, list):
        out = []
        seen = set()
        for item in auth:
            v = str(item).strip().lower()
            if not v or v in seen:
                continue
            seen.add(v)
            out.append(v)
        payload["data"]["zivpn_auth"] = out
except Exception:
    pass

try:
    with open("/etc/sc-1forcr/banner.html", "r", encoding="utf-8") as f:
        payload["data"]["banner_html"] = f.read()
except Exception:
    pass

try:
    with open("/etc/sc-1forcr/banner.txt", "r", encoding="utf-8") as f:
        payload["data"]["banner_txt"] = f.read()
except Exception:
    pass

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY

chmod 600 "${backup_json}" >/dev/null 2>&1 || true

if [[ "${mode}" == "scheduled" ]]; then
  TZ=Asia/Jakarta date +%F > /var/lib/sc-1forcr/last-auto-backup-date
fi

keep_days="$(echo "${AUTO_BACKUP_KEEP_DAYS}" | tr -cd '0-9')"
[[ -z "${keep_days}" ]] && keep_days="7"
find "${AUTO_BACKUP_DIR}" -maxdepth 1 -type f -name 'sc1forcr-accounts-*-WIB.json' -mtime +"${keep_days}" -delete >/dev/null 2>&1 || true

if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
  host="$(hostname 2>/dev/null || echo vps)"
  ssh_count="$(jq -r '.data.ssh | length' "${backup_json}" 2>/dev/null || echo 0)"
  vmess_count="$(jq -r '.data.vmess | length' "${backup_json}" 2>/dev/null || echo 0)"
  vless_count="$(jq -r '.data.vless | length' "${backup_json}" 2>/dev/null || echo 0)"
  trojan_count="$(jq -r '.data.trojan | length' "${backup_json}" 2>/dev/null || echo 0)"
  zivpn_count="$(jq -r '.data.zivpn_auth | length' "${backup_json}" 2>/dev/null || echo 0)"
  banner_html_on="$(jq -r 'if (.data.banner_html // "") != "" then "yes" else "no" end' "${backup_json}" 2>/dev/null || echo no)"
  banner_txt_on="$(jq -r 'if (.data.banner_txt // "") != "" then "yes" else "no" end' "${backup_json}" 2>/dev/null || echo no)"
  caption="SC 1FORCR auto backup
Domain: ${DOMAIN}
Host: ${host}
WIB: $(TZ=Asia/Jakarta date '+%F %T')
File: $(basename "${backup_json}")
SSH:${ssh_count} VMESS:${vmess_count} VLESS:${vless_count} TROJAN:${trojan_count} ZIVPN:${zivpn_count}
BannerHTML:${banner_html_on} BannerTXT:${banner_txt_on}"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "disable_content_type_detection=true" \
    -F "caption=${caption}" \
    -F "document=@${backup_json}" >/dev/null 2>&1 || true
fi

echo "Backup akun selesai: ${backup_json}"
EOF
  chmod +x /usr/local/sbin/sc-1forcr-auto-backup

  cat > /usr/local/sbin/sc-1forcr-restore-backup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Jalankan sebagai root."
  exit 1
fi

backup_file="${1:-}"
if [[ -z "${backup_file}" || ! -f "${backup_file}" ]]; then
  echo "Usage: sc-1forcr-restore-backup /path/backup.json"
  exit 1
fi

if ! jq -e '.data' "${backup_file}" >/dev/null 2>&1; then
  echo "File backup bukan JSON akun yang valid."
  exit 1
fi

if [[ -f /etc/sc-1forcr.env ]]; then
  # shellcheck disable=SC1091
  source /etc/sc-1forcr.env || true
fi
DB_PATH="${DB_PATH:-/usr/sbin/potatonc/potato.db}"
mkdir -p "$(dirname "${DB_PATH}")"

sqlite3 "${DB_PATH}" <<'SQL'
CREATE TABLE IF NOT EXISTS account_sshs (
  username TEXT PRIMARY KEY,
  password TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);
CREATE TABLE IF NOT EXISTS account_vmesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);
CREATE TABLE IF NOT EXISTS account_vlesses (
  username TEXT PRIMARY KEY,
  uuid TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);
CREATE TABLE IF NOT EXISTS account_trojans (
  username TEXT PRIMARY KEY,
  password TEXT,
  date_exp TEXT,
  status TEXT DEFAULT 'AKTIF',
  quota INTEGER DEFAULT 0,
  limitip INTEGER DEFAULT 0,
  owner_telegram_id INTEGER,
  owner_telegram_chat_id INTEGER
);
SQL

python3 - "${backup_file}" "${DB_PATH}" <<'PY'
import json
import sqlite3
import sys

backup_path = sys.argv[1]
db_path = sys.argv[2]

with open(backup_path, "r", encoding="utf-8") as f:
    root = json.load(f)
data = root.get("data") or {}

conn = sqlite3.connect(db_path)
cur = conn.cursor()

def to_int(v, d=0):
    try:
        return int(v)
    except Exception:
        return d

def upsert_ssh(rows):
    for r in rows:
        u = str((r or {}).get("username", "")).strip()
        if not u:
            continue
        cur.execute(
            """
            INSERT INTO account_sshs(username,password,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(username) DO UPDATE SET
              password=excluded.password,
              date_exp=excluded.date_exp,
              status=excluded.status,
              quota=excluded.quota,
              limitip=excluded.limitip,
              owner_telegram_id=excluded.owner_telegram_id,
              owner_telegram_chat_id=excluded.owner_telegram_chat_id
            """,
            (
                u,
                str((r or {}).get("password", "")),
                str((r or {}).get("date_exp", "")),
                str((r or {}).get("status", "AKTIF")) or "AKTIF",
                to_int((r or {}).get("quota", 0)),
                to_int((r or {}).get("limitip", 0)),
                to_int((r or {}).get("owner_telegram_id", 0), 0) or None,
                to_int((r or {}).get("owner_telegram_chat_id", 0), 0) or None,
            ),
        )

def upsert_uuid(table, rows):
    for r in rows:
        u = str((r or {}).get("username", "")).strip()
        if not u:
            continue
        cur.execute(
            f"""
            INSERT INTO {table}(username,uuid,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(username) DO UPDATE SET
              uuid=excluded.uuid,
              date_exp=excluded.date_exp,
              status=excluded.status,
              quota=excluded.quota,
              limitip=excluded.limitip,
              owner_telegram_id=excluded.owner_telegram_id,
              owner_telegram_chat_id=excluded.owner_telegram_chat_id
            """,
            (
                u,
                str((r or {}).get("uuid", "")),
                str((r or {}).get("date_exp", "")),
                str((r or {}).get("status", "AKTIF")) or "AKTIF",
                to_int((r or {}).get("quota", 0)),
                to_int((r or {}).get("limitip", 0)),
                to_int((r or {}).get("owner_telegram_id", 0), 0) or None,
                to_int((r or {}).get("owner_telegram_chat_id", 0), 0) or None,
            ),
        )

def upsert_trojan(rows):
    for r in rows:
        u = str((r or {}).get("username", "")).strip()
        if not u:
            continue
        cur.execute(
            """
            INSERT INTO account_trojans(username,password,date_exp,status,quota,limitip,owner_telegram_id,owner_telegram_chat_id)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(username) DO UPDATE SET
              password=excluded.password,
              date_exp=excluded.date_exp,
              status=excluded.status,
              quota=excluded.quota,
              limitip=excluded.limitip,
              owner_telegram_id=excluded.owner_telegram_id,
              owner_telegram_chat_id=excluded.owner_telegram_chat_id
            """,
            (
                u,
                str((r or {}).get("password", "")),
                str((r or {}).get("date_exp", "")),
                str((r or {}).get("status", "AKTIF")) or "AKTIF",
                to_int((r or {}).get("quota", 0)),
                to_int((r or {}).get("limitip", 0)),
                to_int((r or {}).get("owner_telegram_id", 0), 0) or None,
                to_int((r or {}).get("owner_telegram_chat_id", 0), 0) or None,
            ),
        )

upsert_ssh(data.get("ssh") or [])
upsert_uuid("account_vmesses", data.get("vmess") or [])
upsert_uuid("account_vlesses", data.get("vless") or [])
upsert_trojan(data.get("trojan") or [])

zivpn_auth = data.get("zivpn_auth") or []
if isinstance(zivpn_auth, list):
    clean = []
    seen = set()
    for item in zivpn_auth:
        v = str(item).strip().lower()
        if not v or v in seen:
            continue
        seen.add(v)
        clean.append(v)
    try:
        with open("/etc/zivpn/config.json", "r", encoding="utf-8") as f:
            zcfg = json.load(f)
    except Exception:
        zcfg = {}
    if not isinstance(zcfg, dict):
        zcfg = {}
    auth = zcfg.get("auth")
    if not isinstance(auth, dict):
        auth = {}
    auth["mode"] = "passwords"
    auth["config"] = clean
    zcfg["auth"] = auth
    try:
        with open("/etc/zivpn/config.json", "w", encoding="utf-8") as f:
            json.dump(zcfg, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

banner_html = str(data.get("banner_html") or "")
banner_txt = str(data.get("banner_txt") or "")
try:
    import os
    os.makedirs("/etc/sc-1forcr", exist_ok=True)
    if banner_html:
        with open("/etc/sc-1forcr/banner.html", "w", encoding="utf-8") as f:
            f.write(banner_html)
    if banner_txt:
        with open("/etc/sc-1forcr/banner.txt", "w", encoding="utf-8") as f:
            f.write(banner_txt)
except Exception:
    pass

conn.commit()
conn.close()
PY

chown root:root "${DB_PATH}" >/dev/null 2>&1 || true
chmod 600 "${DB_PATH}" >/dev/null 2>&1 || true
chmod 644 /etc/sc-1forcr/banner.html >/dev/null 2>&1 || true
chmod 644 /etc/sc-1forcr/banner.txt >/dev/null 2>&1 || true
systemctl restart sc-1forcr-api >/dev/null 2>&1 || true
systemctl restart xray >/dev/null 2>&1 || true
systemctl restart "${ZIVPN_SERVICE:-zivpn}" >/dev/null 2>&1 || true
systemctl restart ssh >/dev/null 2>&1 || true
systemctl restart dropbear >/dev/null 2>&1 || true
echo "Restore akun selesai dari: ${backup_file}"
EOF
  chmod +x /usr/local/sbin/sc-1forcr-restore-backup

  cat > /etc/systemd/system/sc-1forcr-autobackup.service <<'EOF'
[Unit]
Description=SC 1FORCR Auto Backup and Send Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sc-1forcr-auto-backup scheduled
NoNewPrivileges=true
PrivateTmp=true
EOF

  cat > /etc/systemd/system/sc-1forcr-autobackup.timer <<'EOF'
[Unit]
Description=Run SC 1FORCR auto backup hourly (executes at 02:00 WIB)

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=30s
Unit=sc-1forcr-autobackup.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now sc-1forcr-autobackup.timer >/dev/null 2>&1 || true
}

write_cli_menu() {
  local menu_runtime
  menu_runtime="${APP_DIR}/menu-sc-1forcr.sh"

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
UDPCUSTOM_DNAT_AUTO_RANGE=${UDPCUSTOM_DNAT_AUTO_RANGE}
DROPBEAR_PORT=${DROPBEAR_PORT}
DROPBEAR_ALT_PORT=${DROPBEAR_ALT_PORT}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
AUTO_BACKUP_ENABLE=${AUTO_BACKUP_ENABLE}
AUTO_BACKUP_DIR=${AUTO_BACKUP_DIR}
AUTO_BACKUP_KEEP_DAYS=${AUTO_BACKUP_KEEP_DAYS}
IPLIMIT_CHECK_INTERVAL_MINUTES=${IPLIMIT_CHECK_INTERVAL_MINUTES}
IPLIMIT_LOCK_MINUTES=${IPLIMIT_LOCK_MINUTES}
IPLIMIT_AUTO_TUNE=${IPLIMIT_AUTO_TUNE}
IPLIMIT_DEBUG=${IPLIMIT_DEBUG}
DROPBEAR_LOG_MAX_LINES=${DROPBEAR_LOG_MAX_LINES}
DROPBEAR_RECENT_LOG_MAX_LINES=${DROPBEAR_RECENT_LOG_MAX_LINES}
UDPHC_LOG_LINES_HISTORY=${UDPHC_LOG_LINES_HISTORY}
UDPHC_LOG_LINES_REALTIME=${UDPHC_LOG_LINES_REALTIME}
XRAY_BLOCK_TCP_PORTS=${XRAY_BLOCK_TCP_PORTS}
XRAY_RECENT_WINDOW_MINUTES=${XRAY_RECENT_WINDOW_MINUTES}
XRAY_ACTIVE_WINDOW_SECONDS=${XRAY_ACTIVE_WINDOW_SECONDS}
XRAY_MIN_HITS_PER_IP=${XRAY_MIN_HITS_PER_IP}
SSH_HC_AUTH_LOOKBACK_HOURS=${SSH_HC_AUTH_LOOKBACK_HOURS}
EOF
  chmod 600 /etc/sc-1forcr.env

  mkdir -p "${APP_DIR}"
  cat > "${menu_runtime}" <<'MENU_SCRIPT_EOF'
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
UDPCUSTOM_DNAT_AUTO_RANGE="${UDPCUSTOM_DNAT_AUTO_RANGE:-6000:6999}"
DROPBEAR_LOG_MAX_LINES="$(echo "${DROPBEAR_LOG_MAX_LINES:-12000}" | tr -cd '0-9')"
DROPBEAR_RECENT_LOG_MAX_LINES="$(echo "${DROPBEAR_RECENT_LOG_MAX_LINES:-5000}" | tr -cd '0-9')"
UDPHC_LOG_LINES_HISTORY="$(echo "${UDPHC_LOG_LINES_HISTORY:-1200}" | tr -cd '0-9')"
UDPHC_LOG_LINES_REALTIME="$(echo "${UDPHC_LOG_LINES_REALTIME:-400}" | tr -cd '0-9')"
xray_recent_window_min="$(echo "${XRAY_RECENT_WINDOW_MINUTES:-30}" | tr -cd '0-9')"
xray_active_window_sec="$(echo "${XRAY_ACTIVE_WINDOW_SECONDS:-120}" | tr -cd '0-9')"
xray_min_hits_per_ip="$(echo "${XRAY_MIN_HITS_PER_IP:-2}" | tr -cd '0-9')"
[[ -z "${DROPBEAR_LOG_MAX_LINES}" || "${DROPBEAR_LOG_MAX_LINES}" -lt 2000 ]] && DROPBEAR_LOG_MAX_LINES="12000"
[[ -z "${DROPBEAR_RECENT_LOG_MAX_LINES}" || "${DROPBEAR_RECENT_LOG_MAX_LINES}" -lt 500 ]] && DROPBEAR_RECENT_LOG_MAX_LINES="5000"
[[ -z "${UDPHC_LOG_LINES_HISTORY}" || "${UDPHC_LOG_LINES_HISTORY}" -lt 200 ]] && UDPHC_LOG_LINES_HISTORY="1200"
[[ -z "${UDPHC_LOG_LINES_REALTIME}" || "${UDPHC_LOG_LINES_REALTIME}" -lt 100 ]] && UDPHC_LOG_LINES_REALTIME="400"
[[ -z "${xray_recent_window_min}" || "${xray_recent_window_min}" -lt 5 ]] && xray_recent_window_min="30"
[[ -z "${xray_active_window_sec}" || "${xray_active_window_sec}" -lt 30 ]] && xray_active_window_sec="120"
[[ -z "${xray_min_hits_per_ip}" || "${xray_min_hits_per_ip}" -lt 1 ]] && xray_min_hits_per_ip="2"

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

telegram_notify() {
  local text="$1"
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "disable_web_page_preview=true" \
    --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

telegram_notify_action() {
  local action="$1" type="$2" username="$3"
  telegram_notify "SC 1FORCR
Action: ${action}
Type: ${type}
Username: ${username}
Domain: ${DOMAIN}
Time: $(date '+%F %T')"
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

mask_secret() {
  local s="$1" n
  n="${#s}"
  if [[ -z "${s}" ]]; then
    echo "-"
    return
  fi
  if [[ "${n}" -le 8 ]]; then
    echo "****"
    return
  fi
  echo "${s:0:4}****${s:n-4:4}"
}

update_sc_env_var() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${value}" '
    BEGIN { done=0 }
    $0 ~ ("^" k "=") { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' /etc/sc-1forcr.env > "${tmp}" && mv -f "${tmp}" /etc/sc-1forcr.env
  chmod 600 /etc/sc-1forcr.env
}

update_app_env_var() {
  local key="$1" value="$2" app_env tmp
  app_env="/opt/sc-1forcr/.env"
  if [[ ! -f "${app_env}" ]]; then
    app_env="/opt/potato-compat/.env"
  fi
  if [[ ! -f "${app_env}" ]]; then
    return 0
  fi
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${value}" '
    BEGIN { done=0 }
    $0 ~ ("^" k "=") { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "${app_env}" > "${tmp}" && mv -f "${tmp}" "${app_env}"
}

write_iplimit_timer_unit() {
  local interval="$1"
  cat > /etc/systemd/system/sc-1forcr-iplimit.timer <<EOF
[Unit]
Description=Run SC 1FORCR IP Limit Checker every ${interval} minutes

[Timer]
OnBootSec=15s
OnUnitActiveSec=${interval}min
AccuracySec=1s
RandomizedDelaySec=0
Persistent=true
Unit=sc-1forcr-iplimit.service

[Install]
WantedBy=timers.target
EOF
}

pick_type() {
  echo "Pilih tipe:" >&2
  echo "0) kembali" >&2
  echo "1) ssh" >&2
  echo "2) vmess" >&2
  echo "3) vless" >&2
  echo "4) trojan" >&2
  echo "5) zivpn" >&2
  if ! prompt_input t "Input [0-5]: "; then
    echo ""
    return 0
  fi
  case "$t" in
    0) echo "" ;;
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
endpoint_trial() {
  case "$1" in
    ssh|zivpn) echo "/trialsshvpn" ;;
    vmess) echo "/trialvmessall" ;;
    vless) echo "/trialvlessall" ;;
    trojan) echo "/trialtrojanall" ;;
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
  local code err_msg
  code="$(echo "${raw}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
  if [[ "${code}" != "200" ]]; then
    err_msg="$(echo "${raw}" | jq -r '.meta.message // .message // "unknown error"' 2>/dev/null || echo "unknown error")"
    echo "Gagal membuat akun ${type^^}: ${err_msg}"
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
      local host user exp
      host="$(echo "${raw}" | jq -r '.data.hostname // "-"' )"
      user="$(echo "${raw}" | jq -r '.data.username // "-"' )"
      exp="$(echo "${raw}" | jq -r '.data.exp // .data.expired // "-"' )"
      cat <<EOT_ZIVPN
=============================
 ZIVPN SSH ACCOUNT
=============================
udp password : ${user}
Hostname     : ${host}
Expired      : ${exp}
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
  local type ep username password exp limitip quota payload resp code
  while true; do
    type="$(pick_type)"
    [[ -z "$type" ]] && return
    ep="$(endpoint_create "$type")"
    [[ -z "$ep" ]] && { echo "Endpoint create tidak ada."; return; }

    username="$(prompt_new_username "$type")" || continue
    prompt_input exp "Expired (hari) [30]: " || continue
    exp="${exp:-30}"
    if [[ "$type" == "zivpn" ]]; then
      # Mode ringkas ZIVPN: cukup username + masa aktif.
      # Nilai lain tetap disimpan default di belakang layar.
      limitip="0"
      quota="0"
      password="${username}"
    else
      prompt_input limitip "Limit IP [2]: " || continue
      limitip="${limitip:-2}"
      prompt_input quota "Quota GB [0]: " || continue
      quota="${quota:-0}"
    fi
    if [[ "$type" == "ssh" ]]; then
      prompt_input password "Password [default=username]: " || continue
      password="${password:-$username}"
    elif [[ "$type" != "zivpn" ]]; then
      password=""
    fi

    if [[ -n "$password" ]]; then
      payload="$(jq -nc --arg u "$username" --arg p "$password" --argjson e "$exp" --arg l "$limitip" --arg q "$quota" \
        '{username:$u,password:$p,expired:$e,limitip:$l,kuota:$q}')"
    else
      payload="$(jq -nc --arg u "$username" --argjson e "$exp" --arg l "$limitip" --arg q "$quota" \
        '{username:$u,expired:$e,limitip:$l,kuota:$q}')"
    fi
    resp="$(api_call "POST" "$ep" "$payload")"
    print_created_account "$type" "${resp}"
    code="$(echo "${resp}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
    [[ "${code}" == "200" ]] && telegram_notify_action "CREATE" "${type}" "${username}"
    return
  done
}

schedule_trial_delete_1h() {
  local type="$1" username="$2" del_ep unit safe_user
  del_ep="$(endpoint_delete "${type}")"
  [[ -z "${del_ep}" ]] && return
  if ! command -v systemd-run >/dev/null 2>&1; then
    echo "Catatan: systemd-run tidak tersedia, auto-delete trial 1 jam tidak dijadwalkan."
    return
  fi
  safe_user="$(echo "${username}" | tr -c 'A-Za-z0-9._-' '_')"
  unit="sc1forcr-trial-${type}-${safe_user}-$(date +%s)"
  if systemd-run --quiet --unit "${unit}" --on-active=1h \
    /usr/bin/curl -sS -X DELETE "${API_BASE}${del_ep}/${username}" \
    -H "Authorization: ${AUTH_TOKEN}" >/dev/null 2>&1; then
    echo "Trial 1 jam aktif. Auto-delete dijadwalkan (unit: ${unit})."
  else
    echo "Peringatan: gagal jadwalkan auto-delete trial 1 jam."
  fi
}

create_trial_account() {
  local type ep username password resp code
  while true; do
    type="$(pick_type)"
    [[ -z "${type}" ]] && return
    ep="$(endpoint_trial "${type}")"
    [[ -z "${ep}" ]] && { echo "Endpoint trial tidak ada."; return; }

    username="$(prompt_new_username "${type}")" || continue

    if [[ "${type}" == "zivpn" ]]; then
      password="${username}"
    elif [[ "${type}" == "ssh" ]]; then
      prompt_input password "Password [default=username]: " || continue
      password="${password:-$username}"
    else
      password=""
    fi

    if [[ -n "${password}" ]]; then
      resp="$(api_call "POST" "${ep}" "$(jq -nc --arg u "${username}" --arg p "${password}" --argjson e 1 --arg l "0" --arg q "0" '{username:$u,password:$p,expired:$e,limitip:$l,kuota:$q}')")"
    else
      resp="$(api_call "POST" "${ep}" "$(jq -nc --arg u "${username}" --argjson e 1 --arg l "0" --arg q "0" '{username:$u,expired:$e,limitip:$l,kuota:$q}')")"
    fi

    print_created_account "${type}" "${resp}"
    code="$(echo "${resp}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
      schedule_trial_delete_1h "${type}" "${username}"
      telegram_notify_action "TRIAL_1H" "${type}" "${username}"
    fi
    return
  done
}

edit_limit_ip_account() {
  local type table username new_limit
  type="$(pick_type)"
  [[ -z "${type}" ]] && { echo "Tipe tidak valid."; return; }
  table="$(account_table_by_type "${type}")"
  [[ -z "${table}" ]] && { echo "Tabel akun tidak ditemukan."; return; }
  username="$(pick_existing_username "${type}")" || return
  prompt_input new_limit "Limit IP baru [0]: " || return
  new_limit="${new_limit:-0}"
  if [[ ! "${new_limit}" =~ ^[0-9]+$ ]]; then
    echo "Limit IP harus angka 0 atau lebih."
    return
  fi
  sqlite3 "${DB_PATH}" "UPDATE ${table} SET limitip=${new_limit} WHERE LOWER(username)=LOWER('${username}');" >/dev/null 2>&1 || {
    echo "Gagal update limit IP."
    return
  }
  echo "Berhasil update limit IP akun ${type^^} '${username}' jadi ${new_limit}."
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

username_exists_by_type() {
  local type="$1" username="$2" table cnt
  table="$(account_table_by_type "${type}")"
  [[ -z "${table}" ]] && return 1
  cnt="$(sqlite3 "${DB_PATH}" "SELECT COUNT(1) FROM ${table} WHERE LOWER(username)=LOWER('${username}');" 2>/dev/null || echo 0)"
  [[ "${cnt}" =~ ^[0-9]+$ ]] || cnt="0"
  if [[ "${cnt}" -gt 0 ]]; then
    return 0
  fi
  return 1
}

prompt_new_username() {
  local type="$1" username=""
  while true; do
    prompt_input username "Username: " || return 1
    username="$(echo "${username}" | tr -d '[:space:]')"
    if [[ -z "${username}" ]]; then
      echo "Username tidak boleh kosong." >&2
      continue
    fi
    if [[ ! "${username}" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "Username hanya boleh huruf, angka, titik, underscore, dan dash." >&2
      continue
    fi
    if username_exists_by_type "${type}" "${username}"; then
      echo "Username '${username}' sudah ada di database. Coba username lain." >&2
      continue
    fi
    echo "${username}"
    return 0
  done
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
    "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday(date('now','localtime'))) AS INTEGER)), UPPER(TRIM(COALESCE(status,''))), CAST(COALESCE(limitip,0) AS INTEGER) FROM ${table} ${where} ORDER BY username;" 2>/dev/null || true)"
  if [[ -z "${rows}" ]]; then
    return 1
  fi
  printf "%-4s %-24s %-10s %-8s %-8s\n" "NO" "USERNAME" "STATUS" "SISA" "LIM_IP"
  printf "%-4s %-24s %-10s %-8s %-8s\n" "----" "------------------------" "----------" "--------" "--------"
  local i=0 u sisa st lim
  while IFS='|' read -r u sisa st lim; do
    [[ -z "${u}" ]] && continue
    i=$((i + 1))
    printf "%-4s %-24s %-10s %-8s %-8s\n" "${i}" "${u}" "${st:-AKTIF}" "${sisa:-0}h" "${lim:-0}"
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
  local type ep username exp resp code message from_date to_date quota limitip
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_renew "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint renew tidak ada."; return; }
  echo "RENEW AKUN ${type^^}"
  username="$(pick_existing_username "$type")" || return
  printf "%-12s : %s\n" "Username" "${username}"
  prompt_input exp "Tambah expired (hari) [30]: " || return
  exp="${exp:-30}"
  resp="$(api_call "POST" "${ep}/${username}/${exp}")"
  code="$(echo "${resp}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
  message="$(echo "${resp}" | jq -r '.meta.message // .message // "unknown error"' 2>/dev/null || echo "unknown error")"
  if [[ "${code}" != "200" ]]; then
    echo "Gagal renew akun ${type^^}: ${message}"
    return
  fi
  from_date="$(echo "${resp}" | jq -r '.data.from // "-"' 2>/dev/null || echo "-")"
  to_date="$(echo "${resp}" | jq -r '.data.to // .data.exp // "-"' 2>/dev/null || echo "-")"
  quota="$(echo "${resp}" | jq -r '.data.quota // "0"' 2>/dev/null || echo "0")"
  limitip="$(echo "${resp}" | jq -r '.data.limitip // "0"' 2>/dev/null || echo "0")"
  cat <<EOT_RENEW
=============================
 RENEW ${type^^} BERHASIL
=============================
Username     : ${username}
Dari         : ${from_date}
Sampai       : ${to_date}
Quota        : ${quota}
IP Limit     : ${limitip}
EOT_RENEW
  telegram_notify_action "RENEW" "${type}" "${username}"
}

delete_account() {
  local type ep username resp code message
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_delete "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint delete tidak ada."; return; }
  echo "DELETE AKUN ${type^^}"
  username="$(pick_existing_username "$type")" || return
  printf "%-12s : %s\n" "Username" "${username}"
  resp="$(api_call "DELETE" "${ep}/${username}")"
  code="$(echo "${resp}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
  message="$(echo "${resp}" | jq -r '.meta.message // .message // "unknown error"' 2>/dev/null || echo "unknown error")"
  if [[ "${code}" != "200" ]]; then
    echo "Gagal hapus akun ${type^^}: ${message}"
    return
  fi
  echo "Akun ${type^^} '${username}' berhasil dihapus."
  telegram_notify_action "DELETE" "${type}" "${username}"
}

unlock_account() {
  local type ep username resp code message
  type="$(pick_type)"
  [[ -z "$type" ]] && { echo "Tipe tidak valid."; return; }
  ep="$(endpoint_unlock "$type")"
  [[ -z "$ep" ]] && { echo "Endpoint unlock tidak ada."; return; }
  username="$(pick_locked_username "$type")" || return
  echo "Unlock akun: ${username}"
  resp="$(api_call "PATCH" "${ep}/${username}")"
  code="$(echo "${resp}" | jq -r '.meta.code // empty' 2>/dev/null || true)"
  message="$(echo "${resp}" | jq -r '.meta.message // .message // "unknown error"' 2>/dev/null || echo "unknown error")"
  if [[ "${code}" != "200" ]]; then
    echo "Gagal unlock akun ${type^^}: ${message}"
    return
  fi
  echo "Akun ${type^^} '${username}' berhasil di-unlock."
  telegram_notify_action "UNLOCK" "${type}" "${username}"
}

list_accounts() {
  print_account_table() {
    local table="$1" title="$2" rows
    rows="$(sqlite3 -separator '|' "$DB_PATH" \
      "SELECT username, MAX(0, CAST((julianday(date_exp) - julianday(date('now','localtime'))) AS INTEGER)), UPPER(TRIM(COALESCE(status,''))), CAST(COALESCE(limitip,0) AS INTEGER) FROM ${table} ORDER BY username;" 2>/dev/null || true)"
    echo "LIST AKUN ${title}"
    printf "%-4s %-24s %-10s %-8s %-8s\n" "NO" "USERNAME" "STATUS" "SISA" "LIM_IP"
    printf "%-4s %-24s %-10s %-8s %-8s\n" "----" "------------------------" "----------" "--------" "--------"
    if [[ -z "${rows}" ]]; then
      echo "(kosong)"
      return
    fi
    local i=0 u sisa st lim
    while IFS='|' read -r u sisa st lim; do
      [[ -z "${u}" ]] && continue
      i=$((i + 1))
      printf "%-4s %-24s %-10s %-8s %-8s\n" "${i}" "${u}" "${st:-AKTIF}" "${sisa:-0}h" "${lim:-0}"
    done <<< "${rows}"
  }

  echo "Pilih list akun:"
  echo "1) SSH/ZIVPN (DB)"
  echo "2) VMESS (DB)"
  echo "3) VLESS (DB)"
  echo "4) TROJAN (DB)"
  echo "5) ZIVPN auth.config"
  echo "6) Semua"
  echo "0) Kembali"
  prompt_input l "Input [0-6]: " || return
  clear

  case "${l}" in
    0) return ;;
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

show_account_detail() {
  local type username username_sql row
  type="$(pick_type)"
  [[ -z "${type}" ]] && { echo "Tipe tidak valid."; return; }
  username="$(pick_existing_username "${type}")" || return
  username_sql="${username//\'/''}"

  case "${type}" in
    ssh|zivpn)
      row="$(sqlite3 -separator '|' "${DB_PATH}" \
        "SELECT username,password,date_exp,UPPER(TRIM(COALESCE(status,''))),CAST(COALESCE(quota,0) AS INTEGER),CAST(COALESCE(limitip,0) AS INTEGER) FROM account_sshs WHERE LOWER(username)=LOWER('${username_sql}') LIMIT 1;" 2>/dev/null || true)"
      if [[ -z "${row}" ]]; then
        echo "Data akun tidak ditemukan."
        return
      fi
      IFS='|' read -r d_user d_pass d_exp d_status d_quota d_limit <<< "${row}"
      cat <<EOT_SSH_DETAIL
=============================
 DETAIL AKUN ${type^^}
=============================
Username     : ${d_user}
Password     : ${d_pass}
Expired      : ${d_exp}
Status       : ${d_status}
Quota        : ${d_quota}
Limit IP     : ${d_limit}
Host         : ${DOMAIN}
SSH WS       : ${DOMAIN}:80@${d_user}:${d_pass}
SSH SSL      : ${DOMAIN}:443@${d_user}:${d_pass}
EOT_SSH_DETAIL
      if [[ -f /etc/zivpn/config.json ]]; then
        if jq -e --arg u "${d_user}" '.auth.config // [] | map(tostring|ascii_downcase) | index($u|ascii_downcase)' /etc/zivpn/config.json >/dev/null 2>&1; then
          echo "ZIVPN AUTH   : TERDAFTAR"
        else
          echo "ZIVPN AUTH   : TIDAK TERDAFTAR"
        fi
      fi
      ;;
    vmess)
      row="$(sqlite3 -separator '|' "${DB_PATH}" \
        "SELECT username,uuid,date_exp,UPPER(TRIM(COALESCE(status,''))),CAST(COALESCE(quota,0) AS INTEGER),CAST(COALESCE(limitip,0) AS INTEGER) FROM account_vmesses WHERE LOWER(username)=LOWER('${username_sql}') LIMIT 1;" 2>/dev/null || true)"
      if [[ -z "${row}" ]]; then
        echo "Data akun tidak ditemukan."
        return
      fi
      IFS='|' read -r d_user d_uuid d_exp d_status d_quota d_limit <<< "${row}"
      vmess_tls="$(printf '{"v":"2","ps":"%s","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"tls","sni":"%s"}' "${d_user}" "${DOMAIN}" "${d_uuid}" "${DOMAIN}" "${DOMAIN}" | base64 -w 0 2>/dev/null || true)"
      vmess_ntls="$(printf '{"v":"2","ps":"%s","add":"%s","port":"80","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"none","sni":"%s"}' "${d_user}" "${DOMAIN}" "${d_uuid}" "${DOMAIN}" "${DOMAIN}" | base64 -w 0 2>/dev/null || true)"
      cat <<EOT_VMESS_DETAIL
=============================
 DETAIL AKUN VMESS
=============================
Username     : ${d_user}
UUID         : ${d_uuid}
Expired      : ${d_exp}
Status       : ${d_status}
Quota        : ${d_quota}
Limit IP     : ${d_limit}
Host         : ${DOMAIN}
Link TLS     : vmess://${vmess_tls}
Link NON TLS : vmess://${vmess_ntls}
EOT_VMESS_DETAIL
      ;;
    vless)
      row="$(sqlite3 -separator '|' "${DB_PATH}" \
        "SELECT username,uuid,date_exp,UPPER(TRIM(COALESCE(status,''))),CAST(COALESCE(quota,0) AS INTEGER),CAST(COALESCE(limitip,0) AS INTEGER) FROM account_vlesses WHERE LOWER(username)=LOWER('${username_sql}') LIMIT 1;" 2>/dev/null || true)"
      if [[ -z "${row}" ]]; then
        echo "Data akun tidak ditemukan."
        return
      fi
      IFS='|' read -r d_user d_uuid d_exp d_status d_quota d_limit <<< "${row}"
      cat <<EOT_VLESS_DETAIL
=============================
 DETAIL AKUN VLESS
=============================
Username     : ${d_user}
UUID         : ${d_uuid}
Expired      : ${d_exp}
Status       : ${d_status}
Quota        : ${d_quota}
Limit IP     : ${d_limit}
Host         : ${DOMAIN}
Link TLS     : vless://${d_uuid}@${DOMAIN}:443?type=ws&path=%2Fvless&security=tls&sni=${DOMAIN}#${d_user}
Link NON TLS : vless://${d_uuid}@${DOMAIN}:80?type=ws&path=%2Fvless&security=none&sni=${DOMAIN}#${d_user}
EOT_VLESS_DETAIL
      ;;
    trojan)
      row="$(sqlite3 -separator '|' "${DB_PATH}" \
        "SELECT username,password,date_exp,UPPER(TRIM(COALESCE(status,''))),CAST(COALESCE(quota,0) AS INTEGER),CAST(COALESCE(limitip,0) AS INTEGER) FROM account_trojans WHERE LOWER(username)=LOWER('${username_sql}') LIMIT 1;" 2>/dev/null || true)"
      if [[ -z "${row}" ]]; then
        echo "Data akun tidak ditemukan."
        return
      fi
      IFS='|' read -r d_user d_pass d_exp d_status d_quota d_limit <<< "${row}"
      cat <<EOT_TROJAN_DETAIL
=============================
 DETAIL AKUN TROJAN
=============================
Username     : ${d_user}
Password     : ${d_pass}
Expired      : ${d_exp}
Status       : ${d_status}
Quota        : ${d_quota}
Limit IP     : ${d_limit}
Host         : ${DOMAIN}
Link TLS     : trojan://${d_pass}@${DOMAIN}:443?type=ws&path=%2Ftrojan&security=tls&sni=${DOMAIN}#${d_user}
Link NON TLS : trojan://${d_pass}@${DOMAIN}:80?type=ws&path=%2Ftrojan&security=none&sni=${DOMAIN}#${d_user}
EOT_TROJAN_DETAIL
      ;;
    *)
      echo "Tipe tidak valid."
      ;;
  esac
}

akun_menu() {
  while true; do
    clear
    echo "===================================="
    echo "           MENU AKUN"
    echo "===================================="
    echo "1) Add Account"
    echo "2) Trial Account (1 jam)"
    echo "3) Renew Account"
    echo "4) Edit Limit IP"
    echo "5) Delete Account"
    echo "6) List Account"
    echo "7) Unlock Account"
    echo "8) Lihat Detail Account"
    echo "0) Kembali"
    echo
    if ! prompt_input am "Pilih menu [0-8]: "; then
      return
    fi
    clear
    case "${am}" in
      1) create_account ;;
      2) create_trial_account ;;
      3) renew_account ;;
      4) edit_limit_ip_account ;;
      5) delete_account ;;
      6) list_accounts ;;
      7) unlock_account ;;
      8) show_account_detail ;;
      0) return ;;
      *) echo "Pilihan tidak valid." ;;
    esac
    echo
    read -rp "Enter untuk lanjut..." _ || true
  done
}

set_iplimit_checker_config_menu() {
  local current_interval current_lock interval_in lock_in
  current_interval="$(echo "${IPLIMIT_CHECK_INTERVAL_MINUTES:-10}" | tr -cd '0-9')"
  current_lock="$(echo "${IPLIMIT_LOCK_MINUTES:-15}" | tr -cd '0-9')"
  [[ -z "${current_interval}" ]] && current_interval="10"
  [[ -z "${current_lock}" ]] && current_lock="15"

  echo "=== SETTING IP LIMIT CHECKER ==="
  echo "Interval checker saat ini : ${current_interval} menit"
  echo "Durasi unlock (lock tmp)  : ${current_lock} menit"
  echo
  echo "Kosongkan input untuk mempertahankan nilai lama."
  echo "Ketik 'batal' untuk kembali."

  if ! prompt_input interval_in "Interval checker (menit) [${current_interval}]: "; then
    return
  fi
  [[ "${interval_in,,}" == "batal" ]] && return
  interval_in="${interval_in:-${current_interval}}"
  if [[ ! "${interval_in}" =~ ^[0-9]+$ || "${interval_in}" -lt 1 || "${interval_in}" -gt 1440 ]]; then
    echo "Interval checker harus angka 1-1440 menit."
    return
  fi

  if ! prompt_input lock_in "Durasi unlock otomatis (menit) [${current_lock}]: "; then
    return
  fi
  [[ "${lock_in,,}" == "batal" ]] && return
  lock_in="${lock_in:-${current_lock}}"
  if [[ ! "${lock_in}" =~ ^[0-9]+$ || "${lock_in}" -lt 1 || "${lock_in}" -gt 10080 ]]; then
    echo "Durasi unlock harus angka 1-10080 menit."
    return
  fi

  IPLIMIT_CHECK_INTERVAL_MINUTES="${interval_in}"
  IPLIMIT_LOCK_MINUTES="${lock_in}"

  update_sc_env_var "IPLIMIT_CHECK_INTERVAL_MINUTES" "${IPLIMIT_CHECK_INTERVAL_MINUTES}"
  update_sc_env_var "IPLIMIT_LOCK_MINUTES" "${IPLIMIT_LOCK_MINUTES}"
  update_app_env_var "IPLIMIT_CHECK_INTERVAL_MINUTES" "${IPLIMIT_CHECK_INTERVAL_MINUTES}"
  update_app_env_var "IPLIMIT_LOCK_MINUTES" "${IPLIMIT_LOCK_MINUTES}"

  write_iplimit_timer_unit "${IPLIMIT_CHECK_INTERVAL_MINUTES}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now sc-1forcr-iplimit.timer >/dev/null 2>&1 || true
  systemctl restart sc-1forcr-iplimit.timer >/dev/null 2>&1 || true
  systemctl start sc-1forcr-iplimit.service >/dev/null 2>&1 || true

  echo
  echo "Berhasil update checker limit IP:"
  echo "- Interval checker : ${IPLIMIT_CHECK_INTERVAL_MINUTES} menit"
  echo "- Durasi unlock    : ${IPLIMIT_LOCK_MINUTES} menit"
}

tools_menu() {
  while true; do
    clear
    echo "===================================="
    echo "          MENU TOOLS"
    echo "===================================="
    echo "1) Informasi Key SC"
    echo "2) Install API Summary 1FORCR"
    echo "3) Setting Banner HTML"
    echo "4) Update Script"
    echo "5) Setting Notif Telegram"
    echo "6) Setting Checker IP Limit"
    echo "0) Kembali"
    echo
    if ! prompt_input tm "Pilih menu [0-6]: "; then
      return
    fi
    clear
    case "${tm}" in
      1) show_sc_key_info ;;
      2) install_summary_api_1forcr ;;
      3) set_html_banner_menu ;;
      4) update_script_from_repo ;;
      5) set_telegram_notif_config ;;
      6) set_iplimit_checker_config_menu ;;
      0) return ;;
      *) echo "Pilihan tidak valid." ;;
    esac
    echo
    read -rp "Enter untuk lanjut..." _ || true
  done
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
  local udpcustom udphc_port dnat_range range_nft
  udpcustom="$(detect_udpcustom_service)"
  udphc_port="$(jq -r '.listen // empty' /root/udp/config.json 2>/dev/null | sed -E 's/^:([0-9]+)$/\1/' | tr -cd '0-9')"
  [[ -z "${udphc_port}" ]] && udphc_port="5667"
  dnat_range="${UDPCUSTOM_DNAT_RANGE}"
  [[ -z "${dnat_range}" ]] && dnat_range="${UDPCUSTOM_DNAT_AUTO_RANGE}"
  systemctl disable --now "${ZIVPN_SERVICE}" >/dev/null 2>&1 || true
  systemctl enable "${udpcustom}" >/dev/null 2>&1 || true
  systemctl restart "${udpcustom}" >/dev/null 2>&1 || true
  cleanup_zivpn_dnat_for_udphc
  if [[ -n "${dnat_range}" ]]; then
    if command -v iptables >/dev/null 2>&1; then
      iptables -C INPUT -p udp --dport "${udphc_port}" -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT -p udp --dport "${udphc_port}" -j ACCEPT
      iptables -t nat -C PREROUTING -p udp --dport "${dnat_range}" -j DNAT --to-destination ":${udphc_port}" >/dev/null 2>&1 || \
        iptables -t nat -I PREROUTING -p udp --dport "${dnat_range}" -j DNAT --to-destination ":${udphc_port}"
    elif command -v nft >/dev/null 2>&1; then
      range_nft="${dnat_range/:/-}"
      nft add table ip nat >/dev/null 2>&1 || true
      nft 'add chain ip nat prerouting { type nat hook prerouting priority dstnat; }' >/dev/null 2>&1 || true
      nft list chain ip nat prerouting 2>/dev/null | grep -F -- "udp dport ${range_nft} dnat to :${udphc_port}" >/dev/null 2>&1 || \
        nft add rule ip nat prerouting udp dport "${range_nft}" dnat to ":${udphc_port}"
    fi
  else
    echo "UDPHC aktif tanpa DNAT range."
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
  echo "0) kembali"
  echo "1) status semua"
  echo "2) restart semua"
  echo "3) restart backend UDP aktif"
  echo "4) aktifkan ZIVPN (matikan UDPHC)"
  echo "5) aktifkan UDPHC (matikan ZIVPN)"
  echo "6) status backend UDP"
  echo "7) diagnose + auto-repair UDP backend"
  prompt_input s "Pilih [0-7]: " || return
  clear
  case "$s" in
    0)
      return
      ;;
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
  local full_file
  echo "0) Kembali"
  echo "1) BACKUP AKUN + AUTH ZIVPN (1 file JSON) & kirim ke Telegram"
  echo "2) Restore AKUN + AUTH ZIVPN (.json) dari path file"
  prompt_input b "Pilih [0-2]: " || return
  clear
  case "$b" in
    0)
      return
      ;;
    1)
      if [[ -x /usr/local/sbin/sc-1forcr-auto-backup ]]; then
        /usr/local/sbin/sc-1forcr-auto-backup manual
      else
        echo "Script auto backup belum tersedia."
      fi
      ;;
    2)
      prompt_input full_file "Path file backup (.json): " || return
      if [[ -z "${full_file}" || ! -f "${full_file}" ]]; then
        echo "File backup tidak ditemukan."
        return
      fi
      if [[ -x /usr/local/sbin/sc-1forcr-restore-backup ]]; then
        /usr/local/sbin/sc-1forcr-restore-backup "${full_file}"
      else
        echo "Script restore backup belum tersedia."
      fi
      ;;
    *)
      echo "Pilihan tidak valid."
      ;;
  esac
}

change_domain_menu() {
  local new_domain email app_env pem email_arg
  prompt_input new_domain "Masukkan domain baru: " || return
  if [[ -z "${new_domain}" ]]; then
    echo "Domain tidak boleh kosong."
    return
  fi

  # Tidak perlu input email tiap ganti domain:
  # pakai EMAIL lama jika valid, fallback admin@domain.
  email="${EMAIL:-}"
  if [[ -z "${email}" || "${email}" == "admin@example.com" || "${email}" == *"@example.com" ]]; then
    email="admin@${new_domain}"
  fi

  DOMAIN="${new_domain}"
  EMAIL="${email}"

  mkdir -p /var/www/html
  cat > /etc/nginx/sites-available/sc-1forcr.conf <<EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${new_domain};
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
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_buffering off;
    }
}
EONGINX

  ln -sf /etc/nginx/sites-available/sc-1forcr.conf /etc/nginx/sites-enabled/sc-1forcr.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t || { echo "Konfigurasi nginx invalid."; return; }
  systemctl restart nginx || true

  if [[ "${email}" == "admin@example.com" || "${email}" == *"@example.com" ]]; then
    email_arg="--register-unsafely-without-email"
  else
    email_arg="-m ${email}"
  fi

  if ! certbot certonly --webroot -w /var/www/html -d "${new_domain}" --non-interactive --agree-tos ${email_arg}; then
    echo "Gagal issue cert untuk domain ${new_domain}."
    echo "Pastikan A record domain mengarah ke VPS, lalu ulangi."
    return
  fi

  pem="/etc/haproxy/certs/${new_domain}.pem"
  mkdir -p /etc/haproxy/certs
  cat "/etc/letsencrypt/live/${new_domain}/fullchain.pem" "/etc/letsencrypt/live/${new_domain}/privkey.pem" > "${pem}" || {
    echo "Gagal menyiapkan sertifikat HAProxy."
    return
  }
  chmod 600 "${pem}"

  cat > /etc/haproxy/haproxy.cfg <<EOHAP
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
EOHAP

  haproxy -c -f /etc/haproxy/haproxy.cfg || {
    echo "Konfigurasi haproxy invalid."
    return
  }
  systemctl restart haproxy || true

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

get_hc_auth_lookback_hours() {
  local h
  h="$(echo "${SSH_HC_AUTH_LOOKBACK_HOURS:-24}" | tr -cd '0-9')"
  [[ -z "${h}" ]] && h="24"
  if [[ "${h}" -lt 1 ]]; then h="1"; fi
  if [[ "${h}" -gt 168 ]]; then h="168"; fi
  echo "${h}"
}

menu_bool_01() {
  local raw
  raw="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${raw}" in
    1|true|yes|on) echo "1" ;;
    *) echo "0" ;;
  esac
}

get_server_capacity_profile() {
  local ram_kib ram_mb ram_gb cores tier est
  ram_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
  if [[ -z "${ram_kib}" || ! "${ram_kib}" =~ ^[0-9]+$ ]]; then
    ram_mb="1024"
  else
    ram_mb="$((ram_kib / 1024))"
  fi
  (( ram_mb < 256 )) && ram_mb=1024
  ram_gb="$((ram_mb / 1024))"
  (( ram_gb < 1 )) && ram_gb=1

  cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ -z "${cores}" || ! "${cores}" =~ ^[0-9]+$ || "${cores}" -lt 1 ]] && cores=1

  tier="${ram_gb}"
  (( cores < tier )) && tier="${cores}"
  (( tier < 1 )) && tier=1

  est="80-100"
  if (( tier >= 8 )); then
    est="220-300"
  elif (( tier >= 4 )); then
    est="150-220"
  elif (( tier >= 2 )); then
    est="100-150"
  fi

  echo "${ram_gb}|${cores}|${tier}|${est}"
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
  local cap_ram_gb cap_cores cap_tier cap_est cap_mode
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
  IFS='|' read -r cap_ram_gb cap_cores cap_tier cap_est <<< "$(get_server_capacity_profile)"
  if [[ "$(menu_bool_01 "${IPLIMIT_AUTO_TUNE:-1}")" == "1" ]]; then
    cap_mode="AUTO"
  else
    cap_mode="MANUAL"
  fi

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
  printf "│   OS                     : ${os_name}${NC}                              \n"
  printf "│   RAM                    : ${ram_mb:-"-"}  │ SWAP : ${swap_mb:-"-"}${NC}                         \n"
  printf "│   UPTIME                 : ${uptime_h}h ${uptime_m}m${NC}                                           \n"
  printf "│   Spesifikasi server anda: ${cap_ram_gb} GB RAM / ${cap_cores} vCPU${NC}                    \n"
  printf "│   Auto tuning SC         : ${cap_mode} (tier ${cap_tier})${NC}                               \n"
  printf "│   Estimasi akun          : sekitar ${cap_est} user${NC}                              \n"
  printf "│ \n"
  printf "│   ${CYAN}${BOLD}Script menyesuaikan limit scan log agar${NC}\n" 
  printf "│   ${CYAN}${BOLD}tidak terlalu berat di server.${NC}      \n"
  printf "│ \n"
  printf "│   ${CYAN}${BOLD}Auto tunning ini memprediksi estimasi akun${NC}      \n"
  printf "│   ${CYAN}${BOLD}dengan mengabaikan Bandwidth server.${NC}      \n"
  printf "│   ${CYAN}${BOLD}Jika BW unlimited maka tidak perlu di pikirkan. ${NC}      \n"
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

  printf "│   XRAY    : ${xray_color}   │ SSH-WS : ${ws_color}    │ LOADBLC : ${lb_color}   \n"
  printf "│   ZIVPN   : ${zivpn_color}   │ UDPHC  : ${udphc_color}   │ SSH     : ${ssh_color}   \n"
  printf "│   HEALTH  : ${health_display}${NC} │ \n"
  hr

  # Account Summary
  printf "│ ${CYAN}${BOLD}■ ACCOUNT SUMMARY${NC}${BOLD}${NC}                                   \n"
  printf "│   SSH/OpenVPN : %-4s     │ VMESS : %-4s     \n" "${c_ssh}" "${c_vmess}"
  printf "│   VLESS       : %-4s     │ TROJAN: %-4s     \n" "${c_vless}" "${c_trojan}"
  hr

  # Version & Client
  printf "│ ${BLUE}${BOLD}■ VERSION & CLIENT${NC}${BOLD}${NC}                                  \n"
  printf "│   Version     : ${SCRIPT_VERSION:-unknown}${NC}                                 \n"
  printf "│   Distribusi  : Community / Open Source${NC}                                \n"
  printf "│   Client Name : ${ip}${NC}                                                \n"
  printf "│   Expiry In   : Unlimited${NC}                                              \n"
  printf "└─────────────────────────────────────────────────\n"
  printf " ─────────────────────────────────────────────────\n"
  printf "           ${BOLD}to access use 'menu' command${NC}\n"
  printf " ─────────────────────────────────────────────────\n"
}
show_combined_online() {
  local mode tmp_count tmp_status tmp_ssh_pid_ip tmp_pid_user tmp_ssh_pair tmp_ssh_count tmp_ssh_proc_count tmp_ssh_count_merged tmp_ssh_count_logs tmp_udp_pair tmp_udp_count tmp_db_ports tmp_db_recent tmp_db_recent_loose udpcustom udp_ttl dropbear_main_port dropbear_alt_port hc_auth_lookback_h
  mode="${1:-realtime}"
  udp_ttl="180"
  udpcustom="$(detect_udpcustom_service)"
  hc_auth_lookback_h="$(get_hc_auth_lookback_hours)"
  dropbear_main_port="$(echo "${DROPBEAR_PORT:-109}" | tr -cd '0-9')"
  dropbear_alt_port="$(echo "${DROPBEAR_ALT_PORT:-143}" | tr -cd '0-9')"
  [[ -z "${dropbear_main_port}" ]] && dropbear_main_port="109"
  [[ -z "${dropbear_alt_port}" ]] && dropbear_alt_port="143"

  tmp_count="$(mktemp)"
  tmp_status="$(mktemp)"
  tmp_ssh_pid_ip="$(mktemp)"
  tmp_pid_user="$(mktemp)"
  tmp_ssh_pair="$(mktemp)"
  tmp_ssh_count="$(mktemp)"
  tmp_ssh_proc_count="$(mktemp)"
  tmp_ssh_count_merged="$(mktemp)"
  tmp_ssh_count_logs="$(mktemp)"
  tmp_udp_pair="$(mktemp)"
  tmp_udp_count="$(mktemp)"
  tmp_db_ports="$(mktemp)"
  tmp_db_recent="$(mktemp)"
  tmp_db_recent_loose="$(mktemp)"
  trap 'rm -f "${tmp_count:-}" "${tmp_status:-}" "${tmp_ssh_pid_ip:-}" "${tmp_pid_user:-}" "${tmp_ssh_pair:-}" "${tmp_ssh_count:-}" "${tmp_ssh_proc_count:-}" "${tmp_ssh_count_merged:-}" "${tmp_ssh_count_logs:-}" "${tmp_udp_pair:-}" "${tmp_udp_count:-}" "${tmp_db_ports:-}" "${tmp_db_recent:-}" "${tmp_db_recent_loose:-}"' RETURN

  # SSH realtime: map pid->user dan pid->remote_ip, lalu pisahkan dari pasangan user+ip UDPHC aktif.
  : > "${tmp_ssh_pair}"
  : > "${tmp_ssh_count}"
  ss -Htnp state established 2>/dev/null | awk '
    {
      l=$4;
      r=$5;
      if (l ~ /:22$/ || l ~ /:'"${dropbear_main_port}"'$/ || l ~ /:'"${dropbear_alt_port}"'$/) {
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
        } else if ($0 ~ /^dropbear[^[:space:]]*[[:space:]]+\[[^]]+\]/ || $0 ~ /\/dropbear-[^[:space:]]+[[:space:]]+\[[^]]+\]/) {
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
    journalctl -u "${udpcustom}" -n "${UDPHC_LOG_LINES_HISTORY}" -o short-unix --no-pager 2>/dev/null
  else
    udp_ttl="180"
    journalctl -u "${udpcustom}" --since "-8 min" -n "${UDPHC_LOG_LINES_REALTIME}" -o short-unix --no-pager 2>/dev/null
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
      } else if ($0 ~ /^dropbear[^[:space:]]*[[:space:]]+\[[^]]+\]/ || $0 ~ /\/dropbear-[^[:space:]]+[[:space:]]+\[[^]]+\]/) {
        u=$0;
        sub(/^.*dropbear[^[:space:]]*[[:space:]]+\[/, "", u);
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

  # Fallback tambahan untuk jalur SSH-WS/HTTP Custom:
  # pakai log auth dropbear yang port-nya masih aktif di socket.
  : > "${tmp_db_ports}"
  : > "${tmp_db_recent}"
  ss -Htnp state established 2>/dev/null | awk '
    function p(v,   s,n,a,port) {
      s=v;
      gsub(/^\[/, "", s); gsub(/\]$/, "", s);
      n=split(s, a, ":");
      port=a[n];
      if (port ~ /^[0-9]{1,5}$/) return port;
      return "";
    }
    {
      lp=p($4); rp=p($5);
      if (lp == "'"${dropbear_main_port}"'" || lp == "'"${dropbear_alt_port}"'") {
        if (rp ~ /^[0-9]{1,5}$/) act[rp]=1;
      } else if (rp == "'"${dropbear_main_port}"'" || rp == "'"${dropbear_alt_port}"'") {
        if (lp ~ /^[0-9]{1,5}$/) act[lp]=1;
      }
    }
    END { for (k in act) print k; }' > "${tmp_db_ports}" || true

  if [[ -s "${tmp_db_ports}" ]]; then
    journalctl -u dropbear --since "-${hc_auth_lookback_h} hours" -n "${DROPBEAR_LOG_MAX_LINES}" --no-pager 2>/dev/null | awk '
      NR==FNR { ap[$1]=1; next }
      function norm_ip(v) {
        gsub(/[[:space:]]/, "", v);
        gsub(/^\[/, "", v);
        gsub(/\]/, "", v);
        sub(/:[0-9]+$/, "", v);
        return v;
      }
      function is_loopback_ip(v,   t) {
        t=tolower(v);
        return (t=="127.0.0.1" || t=="::1" || t=="localhost");
      }
      function sess_key(u, ip, port) {
        if (is_loopback_ip(ip) && port ~ /^[0-9]{1,5}$/) return u "|port:" port;
        return u "|ip:" ip;
      }
      function parse_pid(line,   p) {
        if (match(line, /\[[0-9]+\]/)) {
          p=substr(line, RSTART+1, RLENGTH-2);
          if (p ~ /^[0-9]+$/) return p;
        }
        return "";
      }
      /auth succeeded for /{
        pid=parse_pid($0);
        u=$0;
        sub(/^.*auth succeeded for /,"",u);
        sub(/^'\''/,"",u); sub(/^"/,"",u);
        sub(/'\''.*/,"",u); sub(/".*/,"",u);
        sub(/[[:space:]].*$/,"",u);
        u=tolower(u);
        if (u !~ /^[a-z0-9._-]+$/ || u=="root" || u=="priv" || u=="net") next;

        src=$0;
        sub(/^.* from /, "", src);
        gsub(/[[:space:]]+$/, "", src);
        ip=src;
        port=src;
        ip=norm_ip(ip);
        sub(/^.*:/, "", port);
        if (ip == "") next;
        if (port !~ /^[0-9]{1,5}$/) next;
        if (!(port in ap)) next;
        k=sess_key(u, ip, port);
        if (pid != "") {
          auth_by_pid[pid]=k;
        } else {
          auth_no_pid[k]=1;
        }
        next;
      }
      /Exit \(|Exit before auth:/{
        pid=parse_pid($0);
        if (pid != "") closed_pid[pid]=1;
      }
      END{
        for (pid in auth_by_pid) {
          if (pid in closed_pid) continue;
          seen[auth_by_pid[pid]]=1;
        }
        for (k in auth_no_pid) seen[k]=1;
        for (k in seen) {
          split(k, a, /\|/);
          cnt[a[1]]++;
        }
        for (u in cnt) print u, cnt[u];
      }' "${tmp_db_ports}" - > "${tmp_db_recent}" || true

    awk '
      NR==FNR { a[$1]=$2+0; seen[$1]=1; next }
      { b[$1]=$2+0; seen[$1]=1; }
      END {
        for (u in seen) {
          x=(u in a ? a[u] : 0);
          y=(u in b ? b[u] : 0);
          n=(x > y ? x : y);
          if (n > 0) print u, n;
        }
      }' "${tmp_ssh_count}" "${tmp_db_recent}" > "${tmp_ssh_count_logs}" || true
    mv -f "${tmp_ssh_count_logs}" "${tmp_ssh_count}"
  fi

  # Fallback longgar untuk HTTP Custom:
  # jika mapping port aktif miss, tetap hitung auth sukses 2 menit terakhir.
  journalctl -u dropbear --since "-2 min" -n "${DROPBEAR_RECENT_LOG_MAX_LINES}" --no-pager 2>/dev/null | awk '
    function norm_ip(v) {
      gsub(/[[:space:]]/, "", v);
      gsub(/^\[/, "", v);
      gsub(/\]/, "", v);
      sub(/:[0-9]+$/, "", v);
      return v;
    }
    function is_loopback_ip(v,   t) {
      t=tolower(v);
      return (t=="127.0.0.1" || t=="::1" || t=="localhost");
    }
    function sess_key(u, ip, port) {
      if (is_loopback_ip(ip) && port ~ /^[0-9]{1,5}$/) return u "|port:" port;
      return u "|ip:" ip;
    }
    function parse_pid(line,   p) {
      if (match(line, /\[[0-9]+\]/)) {
        p=substr(line, RSTART+1, RLENGTH-2);
        if (p ~ /^[0-9]+$/) return p;
      }
      return "";
    }
    /auth succeeded for /{
      pid=parse_pid($0);
      u=$0;
      sub(/^.*auth succeeded for /,"",u);
      sub(/^'\''/,"",u); sub(/^"/,"",u);
      sub(/'\''.*/,"",u); sub(/".*/,"",u);
      sub(/[[:space:]].*$/,"",u);
      u=tolower(u);
      if (u !~ /^[a-z0-9._-]+$/ || u=="root" || u=="priv" || u=="net") next;

      src=$0;
      sub(/^.* from /, "", src);
      gsub(/[[:space:]]+$/, "", src);
      ip=norm_ip(src);
      port=src;
      sub(/^.*:/, "", port);
      if (ip == "") next;
      if (port !~ /^[0-9]{1,5}$/) next;
      k=sess_key(u, ip, port);
      if (pid != "") {
        auth_by_pid[pid]=k;
      } else {
        auth_no_pid[k]=1;
      }
      next;
    }
    /Exit \(|Exit before auth:/{
      pid=parse_pid($0);
      if (pid != "") closed_pid[pid]=1;
    }
    END{
      for (pid in auth_by_pid) {
        if (pid in closed_pid) continue;
        seen[auth_by_pid[pid]]=1;
      }
      for (k in auth_no_pid) seen[k]=1;
      for (k in seen) {
        split(k, a, /\|/);
        cnt[a[1]]++;
      }
      for (u in cnt) print u, cnt[u];
    }' > "${tmp_db_recent_loose}" || true

  awk '
    NR==FNR { a[$1]=$2+0; seen[$1]=1; next }
    { b[$1]=$2+0; seen[$1]=1; }
    END {
      for (u in seen) {
        x=(u in a ? a[u] : 0);
        y=(u in b ? b[u] : 0);
        n=(x > y ? x : y);
        if (n > 0) print u, n;
      }
    }' "${tmp_ssh_count}" "${tmp_db_recent_loose}" > "${tmp_ssh_count_logs}" || true
  mv -f "${tmp_ssh_count_logs}" "${tmp_ssh_count}"

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
  local tmp_status tmp_ss_pid_ip tmp_pid_user tmp_pair tmp_ip_count tmp_db_ports tmp_db_recent tmp_db_recent_loose tmp_merge hc_auth_lookback_h
  local dropbear_main_port dropbear_alt_port
  tmp_status="$(mktemp)"
  tmp_ss_pid_ip="$(mktemp)"
  tmp_pid_user="$(mktemp)"
  tmp_pair="$(mktemp)"
  tmp_ip_count="$(mktemp)"
  tmp_db_ports="$(mktemp)"
  tmp_db_recent="$(mktemp)"
  tmp_db_recent_loose="$(mktemp)"
  tmp_merge="$(mktemp)"
  trap 'rm -f "${tmp_status:-}" "${tmp_ss_pid_ip:-}" "${tmp_pid_user:-}" "${tmp_pair:-}" "${tmp_ip_count:-}" "${tmp_db_ports:-}" "${tmp_db_recent:-}" "${tmp_db_recent_loose:-}" "${tmp_merge:-}"' RETURN

  dropbear_main_port="$(echo "${DROPBEAR_PORT:-109}" | tr -cd '0-9')"
  dropbear_alt_port="$(echo "${DROPBEAR_ALT_PORT:-143}" | tr -cd '0-9')"
  hc_auth_lookback_h="$(get_hc_auth_lookback_hours)"
  [[ -z "${dropbear_main_port}" ]] && dropbear_main_port="109"
  [[ -z "${dropbear_alt_port}" ]] && dropbear_alt_port="143"

  # Sumber utama realtime: socket established (SSH + Dropbear), map PID -> user, lalu hitung unik user+ip.
  : > "${tmp_pair}"
  : > "${tmp_ip_count}"
  ss -Htnp state established 2>/dev/null | awk '
    {
      l=$4;
      r=$5;
      if (l ~ /:22$/ || l ~ /:'"${dropbear_main_port}"'$/ || l ~ /:'"${dropbear_alt_port}"'$/) {
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
    }' | sort -u > "${tmp_ss_pid_ip}" || true

  if [[ -s "${tmp_ss_pid_ip}" ]]; then
    local pid_csv
    pid_csv="$(awk '{print $1}' "${tmp_ss_pid_ip}" | sort -u | paste -sd, -)"
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
        } else if ($0 ~ /^dropbear[^[:space:]]*[[:space:]]+\[[^]]+\]/ || $0 ~ /\/dropbear-[^[:space:]]+[[:space:]]+\[[^]]+\]/) {
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
      }' "${tmp_pid_user}" "${tmp_ss_pid_ip}" | sort -u > "${tmp_pair}" || true
  fi

  awk '{ if ($1 ~ /^[a-z0-9._-]+$/ && $2 != "") cnt[$1]++ } END { for (u in cnt) print u, cnt[u]; }' "${tmp_pair}" > "${tmp_ip_count}" || true

  # Tambahan untuk jalur SSH-WS/HC:
  # Ambil user dari log auth dropbear, tapi hanya untuk client-port yang masih aktif saat ini.
  : > "${tmp_db_ports}"
  : > "${tmp_db_recent}"
  ss -Htnp state established 2>/dev/null | awk '
    function p(v,   s,n,a,port) {
      s=v;
      gsub(/^\[/, "", s); gsub(/\]$/, "", s);
      n=split(s, a, ":");
      port=a[n];
      if (port ~ /^[0-9]{1,5}$/) return port;
      return "";
    }
    {
      lp=p($4); rp=p($5);
      if (lp == "'"${dropbear_main_port}"'" || lp == "'"${dropbear_alt_port}"'") {
        if (rp ~ /^[0-9]{1,5}$/) act[rp]=1;
      } else if (rp == "'"${dropbear_main_port}"'" || rp == "'"${dropbear_alt_port}"'") {
        if (lp ~ /^[0-9]{1,5}$/) act[lp]=1;
      }
    }
    END { for (k in act) print k; }' > "${tmp_db_ports}" || true

  if [[ -s "${tmp_db_ports}" ]]; then
    journalctl -u dropbear --since "-${hc_auth_lookback_h} hours" -n "${DROPBEAR_LOG_MAX_LINES}" --no-pager 2>/dev/null | awk '
      NR==FNR { ap[$1]=1; next }
      function norm_ip(v) {
        gsub(/[[:space:]]/, "", v);
        gsub(/^\[/, "", v);
        gsub(/\]/, "", v);
        sub(/:[0-9]+$/, "", v);
        return v;
      }
      function is_loopback_ip(v,   t) {
        t=tolower(v);
        return (t=="127.0.0.1" || t=="::1" || t=="localhost");
      }
      function sess_key(u, ip, port) {
        if (is_loopback_ip(ip) && port ~ /^[0-9]{1,5}$/) return u "|port:" port;
        return u "|ip:" ip;
      }
      function parse_pid(line,   p) {
        if (match(line, /\[[0-9]+\]/)) {
          p=substr(line, RSTART+1, RLENGTH-2);
          if (p ~ /^[0-9]+$/) return p;
        }
        return "";
      }
      /auth succeeded for /{
        pid=parse_pid($0);
        u=$0;
        sub(/^.*auth succeeded for /,"",u);
        sub(/^'\''/,"",u); sub(/^"/,"",u);
        sub(/'\''.*/,"",u); sub(/".*/,"",u);
        sub(/[[:space:]].*$/,"",u);
        u=tolower(u);
        if (u !~ /^[a-z0-9._-]+$/ || u=="root" || u=="priv" || u=="net") next;

        src=$0;
        sub(/^.* from /, "", src);
        gsub(/[[:space:]]+$/, "", src);
        ip=src;
        port=src;
        sub(/^.*:/, "", port);
        ip=norm_ip(ip);
        if (ip == "") next;
        if (port !~ /^[0-9]{1,5}$/) next;
        if (!(port in ap)) next;
        k=sess_key(u, ip, port);
        if (pid != "") {
          auth_by_pid[pid]=k;
        } else {
          auth_no_pid[k]=1;
        }
        next;
      }
      /Exit \(|Exit before auth:/{
        pid=parse_pid($0);
        if (pid != "") closed_pid[pid]=1;
      }
      END{
        for (pid in auth_by_pid) {
          if (pid in closed_pid) continue;
          seen[auth_by_pid[pid]]=1;
        }
        for (k in auth_no_pid) seen[k]=1;
        for (k in seen) {
          split(k,a,"|");
          cnt[a[1]]++;
        }
        for (u in cnt) print u, cnt[u];
      }' "${tmp_db_ports}" - > "${tmp_db_recent}" || true

    awk '
      NR==FNR { a[$1]=$2+0; seen[$1]=1; next }
      { b[$1]=$2+0; seen[$1]=1; }
      END {
        for (u in seen) {
          x=(u in a ? a[u] : 0);
          y=(u in b ? b[u] : 0);
          n=(x > y ? x : y);
          if (n > 0) print u, n;
        }
      }' "${tmp_ip_count}" "${tmp_db_recent}" > "${tmp_merge}" || true
    mv -f "${tmp_merge}" "${tmp_ip_count}"
  fi

  # Fallback longgar untuk HTTP Custom:
  # jika mapping port aktif miss, tetap hitung auth sukses 2 menit terakhir.
  journalctl -u dropbear --since "-2 min" -n "${DROPBEAR_RECENT_LOG_MAX_LINES}" --no-pager 2>/dev/null | awk '
    function norm_ip(v) {
      gsub(/[[:space:]]/, "", v);
      gsub(/^\[/, "", v);
      gsub(/\]/, "", v);
      sub(/:[0-9]+$/, "", v);
      return v;
    }
    function is_loopback_ip(v,   t) {
      t=tolower(v);
      return (t=="127.0.0.1" || t=="::1" || t=="localhost");
    }
    function sess_key(u, ip, port) {
      if (is_loopback_ip(ip) && port ~ /^[0-9]{1,5}$/) return u "|port:" port;
      return u "|ip:" ip;
    }
    function parse_pid(line,   p) {
      if (match(line, /\[[0-9]+\]/)) {
        p=substr(line, RSTART+1, RLENGTH-2);
        if (p ~ /^[0-9]+$/) return p;
      }
      return "";
    }
    /auth succeeded for /{
      pid=parse_pid($0);
      u=$0;
      sub(/^.*auth succeeded for /,"",u);
      sub(/^'\''/,"",u); sub(/^"/,"",u);
      sub(/'\''.*/,"",u); sub(/".*/,"",u);
      sub(/[[:space:]].*$/,"",u);
      u=tolower(u);
      if (u !~ /^[a-z0-9._-]+$/ || u=="root" || u=="priv" || u=="net") next;

      src=$0;
      sub(/^.* from /, "", src);
      gsub(/[[:space:]]+$/, "", src);
      ip=norm_ip(src);
      port=src;
      sub(/^.*:/, "", port);
      if (ip == "") next;
      if (port !~ /^[0-9]{1,5}$/) next;
      k=sess_key(u, ip, port);
      if (pid != "") {
        auth_by_pid[pid]=k;
      } else {
        auth_no_pid[k]=1;
      }
      next;
    }
    /Exit \(|Exit before auth:/{
      pid=parse_pid($0);
      if (pid != "") closed_pid[pid]=1;
    }
    END{
      for (pid in auth_by_pid) {
        if (pid in closed_pid) continue;
        seen[auth_by_pid[pid]]=1;
      }
      for (k in auth_no_pid) seen[k]=1;
      for (k in seen) {
        split(k, a, /\|/);
        cnt[a[1]]++;
      }
      for (u in cnt) print u, cnt[u];
    }' > "${tmp_db_recent_loose}" || true

  awk '
    NR==FNR { a[$1]=$2+0; seen[$1]=1; next }
    { b[$1]=$2+0; seen[$1]=1; }
    END {
      for (u in seen) {
        x=(u in a ? a[u] : 0);
        y=(u in b ? b[u] : 0);
        n=(x > y ? x : y);
        if (n > 0) print u, n;
      }
    }' "${tmp_ip_count}" "${tmp_db_recent_loose}" > "${tmp_merge}" || true
  mv -f "${tmp_merge}" "${tmp_ip_count}"

  sqlite3 "${DB_PATH}" "SELECT LOWER(username) || '|' || UPPER(TRIM(COALESCE(status,''))) || '|' || CAST(COALESCE(limitip,0) AS INTEGER) FROM account_sshs;" > "${tmp_status}" 2>/dev/null || true

  echo "LIST USER LOGIN SSH (REALTIME SOCKET)"
  if [[ ! -s "${tmp_ip_count}" ]]; then
    echo "Tidak ada user SSH yang sedang online."
    echo
    echo "Total User SSH : 0"
    echo "Total HP SSH   : 0"
    return
  fi

  printf "%-24s %-12s %-10s %-13s\n" "USERNAME" "STATUS" "LIMIT_IP" "TERKONEKSI_HP"
  printf "%-24s %-12s %-10s %-13s\n" "------------------------" "------------" "----------" "-------------"
  awk '
    NR==FNR {
      split($0,a,"|");
      st[a[1]]=a[2];
      lim[a[1]]=(a[3] ~ /^[0-9]+$/ ? a[3] + 0 : 0);
      next
    }
    {
      u=$1; n=$2+0;
      s=(u in st ? st[u] : "AMAN");
      l=(u in lim ? lim[u] : 0);
      if (s=="LOCK" || s=="LOCK_TMP") out="KENA_LOCK";
      else if (l > 0 && n > l) out="MULTI_LOGIN";
      else out="AMAN";
      printf "%-24s %-12s %-10d %-13d\n", u, out, l, n;
      total_user++; total_hp+=n;
    }
    END {
      print "";
      printf "Total User SSH : %d\n", total_user + 0;
      printf "Total HP SSH   : %d\n", total_hp + 0;
    }' "${tmp_status}" "${tmp_ip_count}"
}

xray_log_snapshot() {
  local dst="$1"
  local cutoff_ts active_cutoff_ts
  cutoff_ts="$(( $(date +%s) - (xray_recent_window_min * 60) ))"
  active_cutoff_ts="$(( $(date +%s) - xray_active_window_sec ))"
  if [[ ! -f /var/log/xray/access.log ]]; then
    : > "${dst}"
    return
  fi
  tail -n 25000 /var/log/xray/access.log | awk -v cutoff="${cutoff_ts}" -v active_cutoff="${active_cutoff_ts}" -v min_hits="${xray_min_hits_per_ip}" '
    function norm_ip(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
      gsub(/^\[/, "", v);
      gsub(/\]$/, "", v);
      sub(/:[0-9]+$/, "", v);
      return v;
    }
    function ts_from_line(line, a, ts) {
      if (match(line, /^([0-9]{4})\/([0-9]{2})\/([0-9]{2})[[:space:]]+([0-9]{2}):([0-9]{2}):([0-9]{2})/, a)) {
        ts = mktime(a[1] " " a[2] " " a[3] " " a[4] " " a[5] " " a[6]);
        if (ts > 0) return ts;
      }
      return 0;
    }
    {
      ts=ts_from_line($0);
      if (ts > 0 && ts < cutoff) next;
      if (ts == 0) ts=systime();

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
      if (email !~ /^[a-z0-9._-]+$/) next;

      ip=norm_ip(src);
      if (ip == "") next;
      key=email "|" ip;
      hits[key]++;
      if (!(key in last_ts) || ts > last_ts[key]) last_ts[key]=ts;
      if (!(email in latest_ts) || ts >= latest_ts[email]) {
        latest_ts[email]=ts;
        lastip[email]=ip;
      }
      seen[email]=1;
    }
    END {
      for (k in hits) {
        split(k, a, /\|/);
        u=a[1]; ip=a[2];
        if (last_ts[k] < active_cutoff) continue;
        if (hits[k] < min_hits && lastip[u] != ip) continue;
        cnt[u]++;
      }
      for (u in seen) {
        printf "%s|%d|%s\n", u, (u in cnt ? cnt[u] : 0), (u in lastip ? lastip[u] : "-");
      }
    }' > "${dst}"
}

show_xray_online_by_table() {
  local table="$1" label="$2"
  local t_users t_seen
  t_users="$(mktemp)"
  t_seen="$(mktemp)"
  trap 'rm -f "${t_users:-}" "${t_seen:-}"' RETURN

  sqlite3 "${DB_PATH}" "SELECT LOWER(username) || '|' || UPPER(TRIM(COALESCE(status,''))) || '|' || CAST(COALESCE(limitip,0) AS INTEGER) FROM ${table} ORDER BY LOWER(username);" > "${t_users}" 2>/dev/null || true
  if [[ ! -s "${t_users}" ]]; then
    echo "=== ${label} ONLINE ==="
    echo "Tidak ada akun ${label} di DB."
    return
  fi

  xray_log_snapshot "${t_seen}"

  echo "=== ${label} USER LOGIN (berdasarkan log xray terbaru) ==="
  if [[ ! -s "${t_seen}" ]]; then
    echo "Tidak ada aktivitas terbaru."
    echo
    echo "Total User ${label} : 0"
    echo "Total IP ${label}   : 0"
    return
  fi

  printf "%-24s %-12s %-10s %-13s %-22s\n" "USERNAME" "STATUS" "LIMIT_IP" "TERKONEKSI_IP" "LAST_IP"
  printf "%-24s %-12s %-10s %-13s %-22s\n" "------------------------" "------------" "----------" "-------------" "----------------------"
  awk -F'|' '
    NR==FNR {
      db_status[$1]=$2;
      db_limit[$1]=($3 ~ /^[0-9]+$/ ? $3 + 0 : 0);
      next
    }
    {
      u=$1;
      c=($2 ~ /^[0-9]+$/ ? $2 + 0 : 0);
      lip=$3;
      if (!(u in db_status)) next;
      s=db_status[u];
      l=(u in db_limit ? db_limit[u] : 0);
      if (s=="LOCK" || s=="LOCK_TMP") out="KENA_LOCK";
      else if (l > 0 && c > l) out="MULTI_LOGIN";
      else out="AMAN";
      printf "%-24s %-12s %-10d %-13d %-22s\n", u, out, l, c, (lip=="" ? "-" : lip);
      total_user++;
      total_ip+=c;
    }
    END {
      print "";
      printf "Total User : %d\n", total_user + 0;
      printf "Total IP   : %d\n", total_ip + 0;
    }' "${t_users}" "${t_seen}"
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
  local url tmp active_backend alt_url downloaded_ok
  local banner_html banner_txt had_banner_html had_banner_txt
  local update_note ts_now new_ver
  url="${UPDATE_SCRIPT_URL:-}"
  if [[ -z "${url}" ]]; then
    echo "UPDATE_SCRIPT_URL belum diisi di /etc/sc-1forcr.env"
    echo "Contoh:"
    echo "UPDATE_SCRIPT_URL=https://raw.githubusercontent.com/<user>/<repo>/main/setup-autoscript-compat.sh"
    return
  fi

  tmp="/tmp/setup-autoscript-compat.sh"
  banner_html="/tmp/sc-1forcr-banner.html.bak"
  banner_txt="/tmp/sc-1forcr-banner.txt.bak"
  had_banner_html="0"
  had_banner_txt="0"
  downloaded_ok=0
  echo "Download update script dari: ${url}"
  if curl -fsSL "${url}" -o "${tmp}"; then
    downloaded_ok=1
  else
    # Fallback path otomatis untuk repo yang menyimpan file di /scripts/.
    alt_url="$(echo "${url}" | sed 's|/main/setup-autoscript-compat\.sh$|/main/scripts/setup-autoscript-compat.sh|')"
    if [[ "${alt_url}" != "${url}" ]]; then
      echo "URL utama gagal, coba fallback: ${alt_url}"
      if curl -fsSL "${alt_url}" -o "${tmp}"; then
        downloaded_ok=1
      fi
    fi
  fi
  if [[ "${downloaded_ok}" != "1" ]]; then
    echo "Gagal download update script."
    telegram_notify "Update SC 1FORCR GAGAL
Domain: ${DOMAIN}
Alasan: gagal download script update
Time: $(date '+%F %T')"
    return
  fi
  chmod +x "${tmp}"
  if ! bash -n "${tmp}"; then
    echo "Update script gagal validasi syntax (bash -n)."
    telegram_notify "Update SC 1FORCR GAGAL
Domain: ${DOMAIN}
Alasan: validasi syntax script gagal
Time: $(date '+%F %T')"
    return
  fi

  active_backend="$(echo "${ACTIVE_UDP_BACKEND:-zivpn}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${active_backend}" != "zivpn" && "${active_backend}" != "udpcustom" && "${active_backend}" != "udp-custom" && "${active_backend}" != "udphc" ]]; then
    active_backend="zivpn"
  fi
  if [[ "${active_backend}" == "udp-custom" || "${active_backend}" == "udphc" ]]; then
    active_backend="udpcustom"
  fi

  # Backup banner custom agar tidak tertimpa saat proses update installer.
  rm -f "${banner_html}" "${banner_txt}" >/dev/null 2>&1 || true
  if [[ -s /etc/sc-1forcr/banner.html ]]; then
    cp -f /etc/sc-1forcr/banner.html "${banner_html}" >/dev/null 2>&1 || true
    [[ -s "${banner_html}" ]] && had_banner_html="1"
  fi
  if [[ -s /etc/sc-1forcr/banner.txt ]]; then
    cp -f /etc/sc-1forcr/banner.txt "${banner_txt}" >/dev/null 2>&1 || true
    [[ -s "${banner_txt}" ]] && had_banner_txt="1"
  fi

  echo "Menjalankan update installer..."
  if ! DOMAIN="${DOMAIN}" \
    EMAIL="${EMAIL:-}" \
    API_AUTH_TOKEN="${AUTH_TOKEN}" \
    UPDATE_SCRIPT_URL="${UPDATE_SCRIPT_URL}" \
    DB_PATH="${DB_PATH}" \
    APP_DIR="/opt/sc-1forcr" \
    ZIVPN_SERVICE_NAME="${ZIVPN_SERVICE}" \
    UDPCUSTOM_SERVICE_NAME="${UDPCUSTOM_SERVICE}" \
    ZIVPN_DNAT_RANGE="${ZIVPN_DNAT_RANGE}" \
    UDPCUSTOM_DNAT_RANGE="${UDPCUSTOM_DNAT_RANGE}" \
    UDPCUSTOM_DNAT_AUTO_RANGE="${UDPCUSTOM_DNAT_AUTO_RANGE}" \
    DROPBEAR_PORT="${DROPBEAR_PORT}" \
    DROPBEAR_ALT_PORT="${DROPBEAR_ALT_PORT}" \
    IPLIMIT_CHECK_INTERVAL_MINUTES="${IPLIMIT_CHECK_INTERVAL_MINUTES}" \
    IPLIMIT_LOCK_MINUTES="${IPLIMIT_LOCK_MINUTES}" \
    XRAY_BLOCK_TCP_PORTS="${XRAY_BLOCK_TCP_PORTS}" \
    XRAY_RECENT_WINDOW_MINUTES="${XRAY_RECENT_WINDOW_MINUTES}" \
    XRAY_ACTIVE_WINDOW_SECONDS="${XRAY_ACTIVE_WINDOW_SECONDS}" \
    XRAY_MIN_HITS_PER_IP="${XRAY_MIN_HITS_PER_IP}" \
    TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}" \
    TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}" \
    AUTO_BACKUP_ENABLE="${AUTO_BACKUP_ENABLE}" \
    AUTO_BACKUP_DIR="${AUTO_BACKUP_DIR}" \
    AUTO_BACKUP_KEEP_DAYS="${AUTO_BACKUP_KEEP_DAYS}" \
    ACTIVE_UDP_BACKEND="${active_backend}" \
    bash "${tmp}"; then
    echo "Update script gagal dijalankan."
    telegram_notify "Update SC 1FORCR GAGAL
Domain: ${DOMAIN}
Alasan: installer update exit non-zero
Time: $(date '+%F %T')"
    rm -f "${tmp}" "${banner_html}" "${banner_txt}" >/dev/null 2>&1 || true
    return
  fi

  # Restore banner lama (jika sebelumnya ada), atau tetap nonaktif bila sebelumnya memang tidak ada.
  if [[ "${had_banner_html}" == "1" && -s "${banner_html}" ]]; then
    mkdir -p /etc/sc-1forcr
    cp -f "${banner_html}" /etc/sc-1forcr/banner.html >/dev/null 2>&1 || true
    chmod 644 /etc/sc-1forcr/banner.html >/dev/null 2>&1 || true
    apply_html_banner_config "/etc/sc-1forcr/banner.html"
  elif [[ "${had_banner_html}" != "1" ]]; then
    rm -f /etc/sc-1forcr/banner.html >/dev/null 2>&1 || true
    apply_html_banner_config ""
  fi
  if [[ "${had_banner_txt}" == "1" && -s "${banner_txt}" ]]; then
    mkdir -p /etc/sc-1forcr
    cp -f "${banner_txt}" /etc/sc-1forcr/banner.txt >/dev/null 2>&1 || true
    chmod 644 /etc/sc-1forcr/banner.txt >/dev/null 2>&1 || true
  elif [[ "${had_banner_txt}" != "1" ]]; then
    rm -f /etc/sc-1forcr/banner.txt >/dev/null 2>&1 || true
  fi

  ts_now="$(date '+%F %T')"
  new_ver="-"
  if [[ -f /etc/sc-1forcr-version ]]; then
    new_ver="$(awk -F= '/^SCRIPT_VERSION=/{print $2}' /etc/sc-1forcr-version | head -n1)"
    [[ -z "${new_ver}" ]] && new_ver="-"
  fi
  update_note="Update SC 1FORCR BERHASIL
Domain: ${DOMAIN}
Version: ${new_ver}
Time: ${ts_now}
Checker IP Limit: ${IPLIMIT_CHECK_INTERVAL_MINUTES}m/${IPLIMIT_LOCK_MINUTES}m
Auto Backup: ${AUTO_BACKUP_ENABLE}"
  telegram_notify "${update_note}"

  rm -f "${tmp}" "${banner_html}" "${banner_txt}" >/dev/null 2>&1 || true
}

show_sc_key_info() {
  echo "=== INFORMASI KEY SC ==="
  echo "Domain        : ${DOMAIN}"
  echo "API Base      : https://${DOMAIN}/vps"
  echo "Auth Token    : ${AUTH_TOKEN}"
}

set_telegram_notif_config() {
  local token chat send_test ans
  echo "=== SETTING NOTIF TELEGRAM ==="
  echo "Bot Token     : $(mask_secret "${TELEGRAM_BOT_TOKEN:-}")"
  echo "Chat ID       : ${TELEGRAM_CHAT_ID:-"-"}"
  echo
  echo "Kosongkan input untuk mempertahankan nilai lama."
  echo "Ketik 'batal' untuk kembali."

  if ! prompt_input token "TELEGRAM_BOT_TOKEN: "; then
    return
  fi
  [[ "${token,,}" == "batal" ]] && return

  if ! prompt_input chat "TELEGRAM_CHAT_ID: "; then
    return
  fi
  [[ "${chat,,}" == "batal" ]] && return

  if [[ -n "${token}" ]]; then
    TELEGRAM_BOT_TOKEN="${token}"
    update_sc_env_var "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN}"
  fi
  if [[ -n "${chat}" ]]; then
    TELEGRAM_CHAT_ID="${chat}"
    update_sc_env_var "TELEGRAM_CHAT_ID" "${TELEGRAM_CHAT_ID}"
  fi

  echo "Konfigurasi Telegram tersimpan."
  echo "Bot Token     : $(mask_secret "${TELEGRAM_BOT_TOKEN:-}")"
  echo "Chat ID       : ${TELEGRAM_CHAT_ID:-"-"}"

  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    if prompt_input ans "Kirim pesan test sekarang? [y/N]: "; then
      if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
        telegram_notify "Test notif SC 1FORCR
Domain: ${DOMAIN}
Time: $(date '+%F %T')"
        echo "Pesan test dikirim (cek chat Telegram)."
      fi
    fi
  fi
}

install_summary_api_1forcr() {
  local url tmp
  url="https://raw.githubusercontent.com/harismy/apiCekTotalUserPotato/main/setup-summary-api.sh"
  tmp="/tmp/setup-summary-api.sh"
  echo "Install Summary API 1FORCR..."
  if ! curl -fL --retry 5 --retry-delay 2 "${url}" -o "${tmp}"; then
    echo "Gagal download script summary API."
    return
  fi
  sed -i 's/\r$//' "${tmp}"
  chmod +x "${tmp}"
  bash "${tmp}"
}

write_default_banner_html() {
  local banner_file
  banner_file="/etc/sc-1forcr/banner.html"
  mkdir -p /etc/sc-1forcr
  cat > "${banner_file}" <<'EOF'
<div style="text-align:center; line-height:1.6; font-family: monospace;">

<!-- ╔══════════════╗ -->
<font color="#00ffff">╔═══════════════════════╗</font><br>
<font color="#17e8ff">⚡ SSH PREMIUM BY 1FORCR ⚡</font><br>
<font color="#00ffff">╚═══════════════════════╝</font><br>


<!-- ATURAN PAKAI -->
<font color="#ff45ba"><b>⚠️ ATURAN PEMAKAIAN ⚠️</b></font><br>
<font color="#84ecdb">
Jika beli akun untuk 1 pengguna <br>→ gunakan hanya untuk 1 orang.<br>
Jika beli akun untuk 2 pengguna <br>→ gunakan untuk 2 orang saja.<br>
</font><br>

<font color="red"><b>🚫 Melanggar = Akun Expired Otomatis!</b></font><br><br>

<!-- KONTAK ADMIN -->
<font color="#00ffff">╔════ KONTAK ADMIN ════╗</font><br>
<font color="#84ecdb">
📞 Hubungi Admin: <br>
<font color="#00ffff">http://wa.me/6289527159281</font><br><br>
📢 Info Config & SSH: <br>
<font color="#ff45ba">https://t.me/Oneforcr_info</font><br><br>
🤖 Order via Bot: <br>
<font color="#ff17e8">https://t.me/BOT1FORCR_STORE_bot</font>
</font><br>
<font color="#00ffff">╚════════════════════╝</font><br><br>

<font color="#84ecdb"><i>✨ Terimakasih udah order di 1FORCR ✨</i></font><br>
<font color="#00ffff">━━━━━━━━━━━━━━━━━━━━━━━━━</font><br>

</div>
EOF
  chmod 644 "${banner_file}" >/dev/null 2>&1 || true
}

apply_html_banner_config() {
  local banner_file="$1" main_port alt_port dropbear_bin

  main_port="$(echo "${DROPBEAR_PORT:-109}" | tr -cd '0-9')"
  alt_port="$(echo "${DROPBEAR_ALT_PORT:-143}" | tr -cd '0-9')"
  [[ -z "${main_port}" ]] && main_port="109"
  [[ -z "${alt_port}" ]] && alt_port="143"
  if [[ "${main_port}" -lt 1 || "${main_port}" -gt 65535 ]]; then main_port="109"; fi
  if [[ "${alt_port}" -lt 1 || "${alt_port}" -gt 65535 ]]; then alt_port="143"; fi

  # Prioritaskan binary custom build, fallback ke dropbear bawaan sistem.
  dropbear_bin="$(ls -1 /usr/local/sbin/dropbear-* 2>/dev/null | head -n1 || true)"
  [[ -z "${dropbear_bin}" || ! -x "${dropbear_bin}" ]] && dropbear_bin="/usr/sbin/dropbear"

  if [[ -n "${banner_file}" && -f "${banner_file}" ]]; then
    if grep -qE '^[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null; then
      sed -i "s|^[[:space:]]*Banner[[:space:]].*|Banner ${banner_file}|g" /etc/ssh/sshd_config
    else
      echo "Banner ${banner_file}" >> /etc/ssh/sshd_config
    fi
    if [[ -f /etc/default/dropbear ]]; then
      if grep -q '^DROPBEAR_BANNER=' /etc/default/dropbear; then
        sed -i "s|^DROPBEAR_BANNER=.*|DROPBEAR_BANNER=\"${banner_file}\"|g" /etc/default/dropbear
      else
        echo "DROPBEAR_BANNER=\"${banner_file}\"" >> /etc/default/dropbear
      fi
    fi
    mkdir -p /etc/systemd/system/dropbear.service.d
    cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
Type=simple
ExecStart=
ExecStart=${dropbear_bin} -R -E -F -p ${main_port} -p ${alt_port} -b ${banner_file}
EOF
    echo "Banner aktif: ${banner_file}"
  else
    if grep -qE '^[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null; then
      sed -i "s|^[[:space:]]*Banner[[:space:]].*|Banner none|g" /etc/ssh/sshd_config
    else
      echo "Banner none" >> /etc/ssh/sshd_config
    fi
    if [[ -f /etc/default/dropbear ]] && grep -q '^DROPBEAR_BANNER=' /etc/default/dropbear; then
      sed -i 's|^DROPBEAR_BANNER=.*|DROPBEAR_BANNER=""|g' /etc/default/dropbear
    fi
    mkdir -p /etc/systemd/system/dropbear.service.d
    cat > /etc/systemd/system/dropbear.service.d/override.conf <<EOF
[Service]
Type=simple
ExecStart=
ExecStart=${dropbear_bin} -R -E -F -p ${main_port} -p ${alt_port}
EOF
    echo "Banner dinonaktifkan."
  fi

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart ssh >/dev/null 2>&1 || true
  systemctl restart dropbear >/dev/null 2>&1 || true
}

set_html_banner_menu() {
  local banner_file tmp line
  banner_file="/etc/sc-1forcr/banner.html"
  mkdir -p /etc/sc-1forcr

  while true; do
    echo "===================================="
    echo "        SETTING BANNER HTML"
    echo "===================================="
    echo "1) Set/Edit banner"
    echo "2) Lihat banner aktif"
    echo "3) Nonaktifkan banner"
    echo "4) Pakai template default 1FORCR"
    echo "0) Kembali"
    echo
    if ! prompt_input bm "Pilih menu [0-4]: "; then
      return
    fi
    case "${bm}" in
      1)
        tmp="$(mktemp)"
        echo "Paste HTML banner. Akhiri dengan satu baris: EOF"
        : > "${tmp}"
        while IFS= read -r line </dev/tty; do
          [[ "${line}" == "EOF" ]] && break
          printf '%s\n' "${line}" >> "${tmp}"
        done
        if [[ ! -s "${tmp}" ]]; then
          rm -f "${tmp}"
          echo "Banner kosong, dibatalkan."
        else
          mv -f "${tmp}" "${banner_file}"
          chmod 644 "${banner_file}"
          apply_html_banner_config "${banner_file}"
        fi
        ;;
      2)
        if [[ -f "${banner_file}" ]]; then
          echo "=== BANNER AKTIF (${banner_file}) ==="
          cat "${banner_file}"
        else
          echo "Belum ada banner aktif."
        fi
        ;;
      3)
        rm -f "${banner_file}" >/dev/null 2>&1 || true
        apply_html_banner_config ""
        ;;
      4)
        write_default_banner_html
        apply_html_banner_config "${banner_file}"
        echo "Template default 1FORCR berhasil diterapkan."
        ;;
      0)
        return
        ;;
      *)
        echo "Pilihan tidak valid."
        ;;
    esac
    echo
    read -rp "Enter untuk lanjut..." _ || true
    clear
  done
}

monitor_online_menu() {
  while true; do
    clear
    echo "===================================="
    echo "      MONITOR USER ONLINE"
    echo "===================================="
    echo "1) Lihat User Login SSH (Realtime)"
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
  echo " │  1.) > MENU AKUN         5.) > MONITOR USER LOCK"
  echo " │  2.) > SERVICE MENU      6.) > MONITOR USER LOGIN"
  echo " │  3.) > BACKUP/RESTORE    7.) > TOOLS"
  echo " │  4.) > CHANGE DOMAIN"
  echo " │  m.) > MENU UTAMA"
  echo " │  x.) > EXIT"
  echo " └─────────────────────────────────────────────────"
  if [[ "${SHOW_FULL_MENU}" == "1" ]]; then
    echo " ─────────────────────────────────────────────────"
  fi
  echo
  if ! prompt_input m "Select From Options [1-7, m, x] : "; then
    SHOW_FULL_MENU=0
    continue
  fi
  clear
  case "$m" in
    1) akun_menu ;;
    2) service_menu ;;
    3) backup_restore_menu ;;
    4) change_domain_menu ;;
    5) monitor_temp_lock_menu ;;
    6) monitor_online_menu ;;
    7) tools_menu ;;
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
MENU_SCRIPT_EOF

  chmod +x "${menu_runtime}"

  cat > /usr/local/sbin/menu-sc-1forcr <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "${menu_runtime}" "\$@"
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
systemctl stop sc-1forcr-autobackup.timer >/dev/null 2>&1 || true
systemctl disable sc-1forcr-autobackup.timer >/dev/null 2>&1 || true
systemctl stop sc-1forcr-autobackup.service >/dev/null 2>&1 || true
systemctl disable sc-1forcr-autobackup.service >/dev/null 2>&1 || true
systemctl stop sc-1forcr-udp-bootfix.service >/dev/null 2>&1 || true
systemctl disable sc-1forcr-udp-bootfix.service >/dev/null 2>&1 || true
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
rm -f /etc/systemd/system/sc-1forcr-autobackup.service
rm -f /etc/systemd/system/sc-1forcr-autobackup.timer
rm -f /etc/systemd/system/sc-1forcr-udp-bootfix.service
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
rm -f /usr/local/sbin/sc-1forcr-auto-backup
rm -f /usr/local/sbin/sc-1forcr-restore-backup
rm -f /usr/local/sbin/sc-1forcr-udp-bootfix

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

show_install_banner() {
  cat <<'EOF'
=========================================
AutoScript 1FORCR Nexus sedang di install
harap tunggu :)
=========================================
EOF
}

show_install_progress() {
  local pct="$1"
  local msg="$2"
  local width filled empty
  local bar_filled bar_empty

  width=40
  filled=$((pct * width / 100))
  empty=$((width - filled))
  bar_filled="$(printf '%*s' "${filled}" '' | tr ' ' '=')"
  bar_empty="$(printf '%*s' "${empty}" '' | tr ' ' '-')"

  printf '[%s%s] %3d%% | %s\n' "${bar_filled}" "${bar_empty}" "${pct}" "${msg}"
}

open_menu_after_install() {
  if [[ -x /usr/local/sbin/menu-sc-1forcr && -t 0 && -t 1 ]]; then
    echo
    echo "Membuka menu SC 1FORCR..."
    /usr/local/sbin/menu-sc-1forcr || true
  else
    echo
    echo "Install selesai. Jalankan perintah: menu"
  fi
}

main() {
  show_install_banner
  show_install_progress 0 "Tunggu dulu mas, proses baru mulai..."

  check_supported_os
  install_base_packages
  setup_vnstat
  apply_system_optimizations
  setup_logrotate_optimizations
  show_install_progress 20 "Tahan mas, baru setengah jalan awal..."

  install_node_if_missing
  install_go_if_missing
  install_xray
  setup_default_banner_assets
  setup_dropbear
  init_db
  setup_nginx_and_cert
  setup_haproxy_tls_mux
  setup_zivpn_service_if_possible
  setup_zivpn_udp_nat_rules
  setup_udpcustom_service_if_possible
  setup_udpcustom_udp_nat_rules
  enforce_single_udp_backend
  show_install_progress 70 "Hampir selesai mas, core service sudah kepasang..."

  write_api_files
  write_go_mux_files
  build_go_files
  write_iplimit_checker
  setup_services
  setup_udp_bootfix_service
  setup_auto_reboot_timer
  setup_auto_backup_timer
  show_install_progress 90 "Sedikit lagi, finishing konfigurasi..."

  write_cli_menu
  write_version_marker
  post_install_preflight
  show_install_progress 100 "Berhasil keinstall semua. Selamat, SC anda sudah selesai terinstall. Cobain mas."

  cat <<EOF

=========================================
SELESAI - SC 1FORCR NEXUS TERPASANG
=========================================
Script Version : ${SCRIPT_VERSION}
Domain         : ${DOMAIN}
Email LE       : ${EMAIL:-without-email}
API Token      : ${API_AUTH_TOKEN}
API Base       : https://${DOMAIN}/vps
Summary DB key : tabel servers kolom key = token di atas

Contoh test:
curl -s -X POST "https://${DOMAIN}/vps/sshvpn" \\
  -H "Authorization: ${API_AUTH_TOKEN}" \\
  -H "Content-Type: application/json" \\
  -d '{"username":"test123","password":"test123","expired":3,"limitip":"2","kuota":"0"}'

Catatan:
- SC 1FORCR Nexus ini bersifat gratis, bebas dipakai, dan open source.
- Tidak ada lisensi komersial wajib; silakan modifikasi sesuai kebutuhan.
- Endpoint /vps/* sudah kompatibel pola bot 1FORCR (create/trial/renew/delete/lock/unlock).
- WS paths aktif: /ssh-ws, /ws, /vmess, /vless, /trojan (port 80 & 443)
- Dropbear aktif di port ${DROPBEAR_PORT} dan ${DROPBEAR_ALT_PORT}; ssh-ws bridge default ke ${DROPBEAR_PORT}
- SSH mux runtime sudah pakai Go binary: ${APP_DIR}/bin/ssh-mux
- Untuk summary API, tinggal pakai scripts/setup-summary-api.sh di repo ini.
- Jika binary zivpn belum ada, isi ZIVPN_BIN_URL lalu jalankan ulang script.
- Rule UDP ZIVPN otomatis dipasang: INPUT udp ${ZIVPN_LISTEN_PORT}, DNAT ${ZIVPN_DNAT_RANGE} -> ${ZIVPN_LISTEN_PORT}.
- UDP Custom juga otomatis disiapkan di service ${UDPCUSTOM_SERVICE_NAME} (config: /root/udp/config.json).
- UDP Custom akan pakai DNAT range ${UDPCUSTOM_DNAT_RANGE:-${UDPCUSTOM_DNAT_AUTO_RANGE}} saat backend UDPHC aktif (override via UDPCUSTOM_DNAT_RANGE).
- Hanya 1 backend UDP aktif sesuai ACTIVE_UDP_BACKEND=${ACTIVE_UDP_BACKEND} (zivpn|udpcustom).
- vnStat dan speedtest-cli otomatis terpasang untuk monitoring trafik + tes speed VPS.
- Auto reboot aktif setiap hari jam 03:00 via systemd timer sc-1forcr-autoreboot.timer.
- Reboot hanya menjalankan sync + reboot (tanpa ubah konfigurasi layanan).
- Auto backup semua akun (JSON) dikirim ke Telegram setiap jam 02:00 WIB via sc-1forcr-autobackup.timer.
- Backup manual: /usr/local/sbin/sc-1forcr-auto-backup manual
- Restore akun dari backup: /usr/local/sbin/sc-1forcr-restore-backup /path/file.json
- UDP boot-fix aktif via systemd sc-1forcr-udp-bootfix.service (re-apply backend/rule saat startup).
- Menu VPS: jalankan perintah menu atau menu-sc-1forcr
- Update sekali klik dari menu: isi UPDATE_SCRIPT_URL lalu gunakan Tools -> Update Script
- Auto lock IP limit: timer systemd sc-1forcr-iplimit.timer (cek tiap ${IPLIMIT_CHECK_INTERVAL_MINUTES} menit, lock sementara ${IPLIMIT_LOCK_MINUTES} menit)
EOF

  open_menu_after_install
}

main "$@"


