#!/bin/bash
# Install dependencies and Marzban
#warna hijau
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
RED='\033[0;31m'
PINK='\033[0;35m'
YELLOW='\033[0;33m'
INDIGO='\033[38;5;54m'
CYAN_BG='\033[46;1;97m'
TEAL='\033[38;5;30m'
ORANGE='\033[38;5;208m'
WHITE='\033[0;97m'


# Safety: installer must run as root and only on supported Debian/Ubuntu.
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ Script harus dijalankan sebagai root.${NC}"
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}❌ /etc/os-release tidak ditemukan.${NC}"
    exit 1
fi
. /etc/os-release
OS_ID="${ID:-}"
OS_VERSION="${VERSION_ID:-}"
case "${OS_ID}:${OS_VERSION}" in
    debian:11|debian:12|debian:13|ubuntu:20.04|ubuntu:22.04|ubuntu:24.04) ;;
    *)
        echo -e "${RED}❌ OS tidak didukung: ${PRETTY_NAME:-unknown}${NC}"
        echo -e "${YELLOW}Didukung: Debian 11/12/13 atau Ubuntu 20.04/22.04/24.04.${NC}"
        exit 1
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

# Bootstrap only the packages required to continue safely on a fresh VPS.
apt-get update -y
apt-get install -y ca-certificates curl gnupg jq iproute2 dnsutils
echo -e "${TEAL} │${NC} ${CYAN_BG} ♻️ Checking Ticket Masuk... ♻️${NC}"
sleep 2
clear

# Install BOT Usage dependencies
if command -v python3 >/dev/null 2>&1 && [ -f /usr/local/bin/requirements-bot.txt ]; then
    python3 -m pip install --disable-pip-version-check -r /usr/local/bin/requirements-bot.txt >/dev/null 2>&1 || true
fi

mkdir -p /etc/data

# Mendapatkan IP publik pengguna
user_ip=$(curl -fsS --max-time 10 https://ipinfo.io/ip 2>/dev/null || true)

# Meminta nama client dan memvalidasi
while true; do
    echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -rp $'\033[38;5;208m ❖ Masukkan Nama Client:\033[0m ' client_name

    # Validasi Nama Client (misalnya tidak kosong dan hanya huruf)
    if [[ -z "$client_name" ]]; then
        echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo " ❖ Nama Client tidak boleh kosong. Silakan masukkan kembali."
        continue
    elif [[ ! "$client_name" =~ ^[A-Za-z]+$ ]]; then
        echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo " ❖ Nama Client hanya boleh berisi huruf. Silakan masukkan kembali."
        continue
    fi

    # Menggunakan curl untuk memeriksa apakah client_name ada dalam file permission.txt
    permission_file=$(curl -fsSL --max-time 15 https://raw.githubusercontent.com/faiqzuhry/akses-faiq/main/iphost.txt 2>/dev/null || true)
    if [[ -n "$permission_file" ]] && echo "$permission_file" | grep -Fqi -- "$client_name"; then
        exp_date=$(echo "$permission_file" | grep -Fi -- "$client_name" | head -n1 | awk '{print $4}')
        echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN} ❖ Succeed, Access Accepted...${NC}"
        break
    else
        echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED} ❖ Sorry brother, Your IP not register.${NC}"
        echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PINK} ❖ Please Contact Dev : @Faiqzuhry.${NC}"
        rm -f /root/main # Ganti dengan path yang sesuai ke file installer
        exit 1
    fi
done


echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${NC} 🔥 Sedang Melanjutkan proses...${NC}"
sleep 2

colorized_echo() {
    local color=$1
    local text=$2
    
    case $color in
        "red")
        printf "\e[91m${text}\e[0m\n";;
        "green")
        printf "\e[92m${text}\e[0m\n";;
        "yellow")
        printf "\e[93m${text}\e[0m\n";;
        "blue")
        printf "\e[94m${text}\e[0m\n";;
        "magenta")
        printf "\e[95m${text}\e[0m\n";;
        "cyan")
        printf "\e[96m${text}\e[0m\n";;
        *)
            echo "${text}"
        ;;
    esac
}

echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${NC} 🌐 Mengunduh dan menginstal dependensi...${NC}"
echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e ""
sleep 2

# Telegram Bot API details
TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Function to send message to Telegram
send_telegram_message() {
    MESSAGE=$1

    # Telegram notification is optional. Configure these environment
    # variables only on the VPS; never commit real credentials to GitHub.
    if [[ -z "${TOKEN:-}" || -z "${CHAT_ID:-}" ]]; then
        return 0
    fi
    BUTTON1_URL="https://t.me/SaputraTech"
    BUTTON2_URL="https://t.me/SkartiVPN"
    BUTTON_TEXT1="Admin 😎"
    BUTTON_TEXT2="Follow 🐳"

    RESPONSE=$(curl -fsS --max-time 20 -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode="Markdown" \
        --data-urlencode text="$MESSAGE" \
        -d reply_markup='{
            "inline_keyboard": [
                [{"text": "'"$BUTTON_TEXT1"'", "url": "'"$BUTTON1_URL"'"}, {"text": "'"$BUTTON_TEXT2"'", "url": "'"$BUTTON2_URL"'"}]
            ]
        }')

    # Jangan menggagalkan installer jika notifikasi Telegram gagal.
    if command -v jq >/dev/null 2>&1; then echo "$RESPONSE" | jq -r 'if .ok then "Telegram: OK" else "Telegram: gagal" end' 2>/dev/null || true; fi
}

# Gunakan repository bawaan OS. Repository mirror lama dapat menyebabkan 404,
# paket tidak sinkron, atau gagal pada Debian/Ubuntu versi baru.
mkdir -p /etc/data

#domain
echo -e "${CYAN}❖ ───────────────────────────────────────────── ❖${NC}"
read -rp "$(echo -e " 🔰 Masukkan Domain ${GREEN}( wajib pointing dulu )${NC}: ")" domain
if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo -e "${RED}❌ Format domain tidak valid.${NC}"
    exit 1
fi
if ! getent ahostsv4 "$domain" >/dev/null 2>&1; then
    echo -e "${RED}❌ Domain $domain belum bisa di-resolve. Pastikan DNS A record sudah pointing.${NC}"
    exit 1
fi
echo "$domain" > /etc/data/domain
domain=$(cat /etc/data/domain)

# CloudFront memakai hostname terpisah yang selalu mengikuti domain utama.
CF_DOMAIN="cf.${domain}"
if ! getent ahostsv4 "$CF_DOMAIN" >/dev/null 2>&1; then
    echo -e "${RED}❌ ${CF_DOMAIN} belum bisa di-resolve.${NC}"
    echo -e "${YELLOW}Buat A record ${CF_DOMAIN} ke IP VPS terlebih dahulu.${NC}"
    exit 1
fi

#email
echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
while true; do
    read -rp "$(echo -e " ➣ Masukkan Email anda ${GREEN}( ex: skt@gmail.com )${NC}: ")" email
    if [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
        break
    fi
    echo -e "${RED}Email tidak valid.${NC}"
done
echo "$email" > /etc/data/email

#username
while true; do
echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -rp "$(echo -e " ➣ Masukkan Username Panel ${GREEN}( hanya huruf dan angka )${NC}: ")" userpanel

    # Memeriksa apakah userpanel hanya mengandung huruf dan angka
    if [[ ! "$userpanel" =~ ^[A-Za-z0-9]+$ ]]; then
        echo "UsernamePanel hanya boleh berisi huruf dan angka. Silakan masukkan kembali."
    elif [[ "$userpanel" =~ [Aa][Dd][Mm][Ii][Nn] ]]; then
        echo "UsernamePanel tidak boleh mengandung kata 'admin'. Silakan masukkan kembali."
    else
        echo "$userpanel" > /etc/data/userpanel
        break
    fi
done

echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -rsp "$(echo -e " ➣ Masukkan Password Panel ${GREEN}( buat dashboard )${NC}: ")" passpanel
echo
if [[ ${#passpanel} -lt 8 ]]; then
    echo -e "${RED}Password minimal 8 karakter.${NC}"
    exit 1
fi
echo "$passpanel" > /etc/data/passpanel
chmod 600 /etc/data/passpanel

# Function to validate port input
while true; do
echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  read -rp "$(echo -e " ➣ Masukkan Port Dashboard Marzban ${GREEN}(contoh 12800)${NC}: ")" port

  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
    echo -e "${RED}Port harus angka 1024-65535.${NC}"
  elif [[ "$port" -eq 443 || "$port" -eq 80 ]]; then
    echo -e "${RED}Port 80/443 dipakai Nginx dan tidak boleh digunakan Marzban.${NC}"
  else
    echo "Port yang Anda masukkan adalah: $port"
    echo "$port" > /etc/data/marzban_port
    break
  fi
done

#Preparation
#install dependient template bot
clear
cd;
echo -e "${RED}
██████╗░██╗░░░░░███████╗░█████╗░░██████╗███████╗
██╔══██╗██║░░░░░██╔════╝██╔══██╗██╔════╝██╔════╝
██████╔╝██║░░░░░█████╗░░███████║╚█████╗░█████╗░░${NC}${WHITE}
██╔═══╝░██║░░░░░██╔══╝░░██╔══██║░╚═══██╗██╔══╝░░
██║░░░░░███████╗███████╗██║░░██║██████╔╝███████╗
╚═╝░░░░░╚══════╝╚══════╝╚═╝░░╚═╝╚═════╝░╚══════╝
${NC}"
echo -e "${WHITE}
░██╗░░░░░░░██╗░█████╗░██╗████████╗░░░░░░░░░░░░░░░
░██║░░██╗░░██║██╔══██╗██║╚══██╔══╝░░░░░░░░░░░░░░░
░╚██╗████╗██╔╝███████║██║░░░██║░░░░░░░░░░░░░░░░░░
░░████╔═████║░██╔══██║██║░░░██║░░░░░░░░░░░░░░░░░░
░░╚██╔╝░╚██╔╝░██║░░██║██║░░░██║░░░${NC}${RED}██╗██╗██╗██╗██╗${NC}${WHITE}██╗██╗██╗██╗██╗
░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░░╚═╝░░░${NC}${RED}╚═╝╚═╝╚═╝╚═╝╚═╝
${NC}"
apt-get update -y >/dev/null 2>&1
apt-get install figlet toilet lolcat -y >/dev/null 2>&1
apt-get install ruby -y >/dev/null 2>&1
# Install lolcat gem without confirmation
gem install lolcat >/dev/null 2>&1
apt-get install -y sqlite3 python3 python3-pip python3-venv
# Debian 12/13 may enforce PEP 668. Keep compatibility with the existing BOT scripts.
python3 -m pip install --break-system-packages --disable-pip-version-check requests==2.31.0 colorama python-telegram-bot==13.7

#Remove unused Module
apt-get -y --purge remove samba*;
apt-get -y --purge remove apache2*;
apt-get -y --purge remove sendmail*;
apt-get -y --purge remove bind9*;

# Network tuning / BBR (safe on kernels that provide BBR).
cat > /etc/sysctl.d/99-faiqvpn.conf <<'SYSCTL'
fs.file-max = 500000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
SYSCTL
sysctl --system >/dev/null 2>&1 || true
if modprobe tcp_bbr 2>/dev/null || grep -qw bbr /proc/sys/net/ipv4/tcp_allowed_congestion_control 2>/dev/null; then
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
fi

#install toolkit
apt-get install libio-socket-inet6-perl libsocket6-perl libcrypt-ssleay-perl libnet-libidn-perl perl libio-socket-ssl-perl libwww-perl libpcre3 libpcre3-dev zlib1g-dev dbus iftop zip unzip wget net-tools curl nano sed screen gnupg gnupg1 bc apt-transport-https build-essential dirmngr dnsutils sudo at htop iptables bsdmainutils cron lsof lnav -y

# Jangan memaksa timezone server; ikuti timezone OS/VPS yang sudah dikonfigurasi.

#Install Marzban
sudo bash -c "$(curl -fsSL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install --version latest

# Reliable downloader: fail on HTTP errors instead of silently installing empty files.
download_file() {
    local url="$1" dest="$2"
    echo -e "${CYAN}↓ ${url}${NC}"
    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 -o "$dest" "$url"; then
        echo -e "${RED}❌ Gagal mengunduh: $url${NC}"
        exit 1
    fi
    [[ -s "$dest" ]] || { echo -e "${RED}❌ File kosong: $dest${NC}"; exit 1; }
}

#Install Subs
mkdir -p /var/lib/marzban/templates/subscription
download_file "https://raw.githubusercontent.com/raffasyaa/semvak-subs/master/template-01/index.html" /var/lib/marzban/templates/subscription/index.html

#install env
mkdir -p /opt/marzban
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/env" /opt/marzban/.env

# Use the Xray-core downloaded below instead of the Xray binary bundled in the image.
# Marzban supports XRAY_EXECUTABLE_PATH for this purpose.
if grep -q '^XRAY_EXECUTABLE_PATH=' /opt/marzban/.env; then
    sed -i 's#^XRAY_EXECUTABLE_PATH=.*#XRAY_EXECUTABLE_PATH = "/var/lib/marzban/core/xray"#' /opt/marzban/.env
else
    printf '\nXRAY_EXECUTABLE_PATH = "/var/lib/marzban/core/xray"\n' >> /opt/marzban/.env
fi

#install core Xray & Assets folder
mkdir -p /var/lib/marzban/assets
mkdir -p /var/lib/marzban/core
# Install Xray-core dari release terbaru resmi.
mkdir -p /var/lib/marzban/core
XRAY_ARCH="64"
case "$(uname -m)" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    armv7l|armv7) XRAY_ARCH="arm32-v7a" ;;
    armv6l) XRAY_ARCH="arm32-v6" ;;
    armv5*) XRAY_ARCH="arm32-v5" ;;
    i386|i686) XRAY_ARCH="32" ;;
    *) XRAY_ARCH="64" ;;
esac
XRAY_LATEST="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')"
if [ -z "$XRAY_LATEST" ] || [ "$XRAY_LATEST" = "null" ]; then
    echo "Gagal mendapatkan versi Xray terbaru."
    exit 1
fi
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_LATEST}/Xray-linux-${XRAY_ARCH}.zip"
download_file "$XRAY_URL" /var/lib/marzban/core/xray.zip
rm -f /var/lib/marzban/core/xray
cd /var/lib/marzban/core && unzip -o xray.zip && chmod +x xray
rm -f xray.zip
if [ ! -x /var/lib/marzban/core/xray ]; then
    echo -e "${RED}❌ Xray-core gagal dipasang atau binary tidak ditemukan.${NC}"
    exit 1
fi
printf '%s\n' "$XRAY_LATEST" > /var/lib/marzban/core/VERSION
cd

# ============================================================
# XRAY CLOUDFLARE (SEPARATE FROM MARZBAN)
# Cloudflare -> Nginx :443 -> Xray WS :10010
#
# IMPORTANT:
# - No SSH / Dropbear / WebSocket proxy is installed or modified.
# - Marzban keeps using its own Xray configuration.
# - Cloudflare uses a separate Xray config and localhost port.
# - CloudFront uses a dedicated hostname:
#       https://cf.DOMAIN/vmess-cloudfront
#       https://cf.DOMAIN/vless-cloudfront
#       https://cf.DOMAIN/trojan-cloudfront
#   so the normal Marzban hostname remains untouched.
# ============================================================
CF_DOMAIN="cf.${domain}"
CF_PORT_VMESS=10010
CF_PORT_VLESS=10011
CF_PORT_TROJAN=10012
CF_PATH_VMESS="/vmess-cloudfront"
CF_PATH_VLESS="/vless-cloudfront"
CF_PATH_TROJAN="/trojan-cloudfront"
CF_DIR="/var/lib/marzban/cloudfront"
CF_CONFIG_FILE="${CF_DIR}/config.json"
CF_UUID_FILE="${CF_DIR}/uuid"
CF_SERVICE="/etc/systemd/system/xray-cloudflare.service"

setup_xray_cloudflare() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Menyiapkan Xray Cloudflare dari user Marzban...${NC}"

    local CF_DIR="/var/lib/marzban/cloudfront"
    local CF_CONFIG_FILE="${CF_DIR}/config.json"
    local CF_SYNC="/usr/local/bin/sync-marzban-cloudfront.py"
    local CF_SERVICE="/etc/systemd/system/xray-cloudflare.service"
    local CF_SYNC_SERVICE="/etc/systemd/system/marzban-cloudfront-sync.service"
    local CF_TIMER="/etc/systemd/system/marzban-cloudfront-sync.timer"
    local XRAY_BIN="/var/lib/marzban/core/xray"

    mkdir -p "$CF_DIR" /var/log/xray
    chmod 755 "$CF_DIR"

    if [[ ! -x "$XRAY_BIN" ]]; then
        echo -e "${RED}❌ Xray-core Marzban tidak ditemukan: $XRAY_BIN${NC}"
        exit 1
    fi

    # Read the actual Marzban users database. No generated UUID/passwords.
    cat > "$CF_SYNC" <<'PY'
#!/usr/bin/env python3
import json, os, sqlite3, tempfile, time

DB = "/var/lib/marzban/db.sqlite3"
OUT = "/var/lib/marzban/cloudfront/config.json"

def active(expire, status):
    status = (status or "").lower()
    if status and status != "active":
        return False
    if expire not in (None, 0) and int(expire) <= int(time.time()):
        return False
    return True

if not os.path.exists(DB):
    raise SystemExit("Marzban DB not found: " + DB)

conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
try:
    rows = conn.execute("SELECT username, proxies, status, expire FROM users").fetchall()
finally:
    conn.close()

vmess, vless, trojan = [], [], []
seen_vmess, seen_vless, seen_trojan = set(), set(), set()

for row in rows:
    if not active(row["expire"], row["status"]):
        continue
    try:
        proxies = json.loads(row["proxies"] or "{}")
    except Exception:
        continue

    x = proxies.get("vmess") or {}
    uid = x.get("id")
    if uid and uid not in seen_vmess:
        vmess.append({"id": uid, "alterId": int(x.get("alterId", 0))})
        seen_vmess.add(uid)

    x = proxies.get("vless") or {}
    uid = x.get("id")
    if uid and uid not in seen_vless:
        vless.append({"id": uid, "email": row["username"] or ""})
        seen_vless.add(uid)

    x = proxies.get("trojan") or {}
    pwd = x.get("password")
    if pwd and pwd not in seen_trojan:
        trojan.append({"password": pwd, "email": row["username"] or ""})
        seen_trojan.add(pwd)

cfg = {
    "log": {
        "access": "/var/log/xray/cloudfront-access.log",
        "error": "/var/log/xray/cloudfront-error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": 10010,
            "protocol": "vmess",
            "settings": {"clients": vmess},
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"path": "/vmess-cloudfront"}
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 10011,
            "protocol": "vless",
            "settings": {"clients": vless, "decryption": "none"},
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"path": "/vless-cloudfront"}
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 10012,
            "protocol": "trojan",
            "settings": {"clients": trojan},
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"path": "/trojan-cloudfront"}
            }
        }
    ],
    "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=".cloudfront-", suffix=".json", dir=os.path.dirname(OUT))
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.replace(tmp, OUT)
print(f"Cloudfront users synced: VMess={len(vmess)} VLESS={len(vless)} Trojan={len(trojan)}")
PY
    chmod 755 "$CF_SYNC"

    # Initial sync uses the real Marzban DB.
    python3 "$CF_SYNC" || {
        echo -e "${RED}❌ Gagal membaca user Marzban.${NC}"
        exit 1
    }

    "$XRAY_BIN" run -test -config "$CF_CONFIG_FILE" >/tmp/xray-cloudflare-test.log 2>&1 || {
        cat /tmp/xray-cloudflare-test.log
        echo -e "${RED}❌ Konfigurasi Xray Cloudflare tidak valid.${NC}"
        exit 1
    }

    cat > "$CF_SERVICE" <<EOF
[Unit]
Description=Xray Cloudflare VMess VLESS Trojan - Marzban Users
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${CF_CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    cat > "$CF_SYNC_SERVICE" <<EOF
[Unit]
Description=Sync Marzban users to Cloudflare Xray
After=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${CF_SYNC} && ${XRAY_BIN} run -test -config ${CF_CONFIG_FILE} && systemctl try-restart xray-cloudflare.service'
EOF

    cat > "$CF_TIMER" <<EOF
[Unit]
Description=Periodic Marzban to Cloudflare Xray user sync

[Timer]
OnBootSec=20s
OnUnitActiveSec=30s
Unit=marzban-cloudfront-sync.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Dedicated hostname + exact paths; root "/" is never taken over.
    cat > /etc/nginx/conf.d/cloudfront-xray.conf <<EOF
map \$http_upgrade \$connection_upgrade_cf {
    default upgrade;
    '' close;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${CF_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = ${CF_PATH_VMESS} {
        proxy_pass http://127.0.0.1:${CF_PORT_VMESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade_cf;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location = ${CF_PATH_VLESS} {
        proxy_pass http://127.0.0.1:${CF_PORT_VLESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade_cf;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location = ${CF_PATH_TROJAN} {
        proxy_pass http://127.0.0.1:${CF_PORT_TROJAN};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade_cf;
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location / { return 404; }
}
EOF

    nginx -t || exit 1
    systemctl daemon-reload
    systemctl enable --now xray-cloudflare
    systemctl enable --now marzban-cloudfront-sync.timer
    systemctl start marzban-cloudfront-sync.service
    systemctl reload nginx

    if ! systemctl is-active --quiet xray-cloudflare; then
        echo -e "${RED}❌ xray-cloudflare.service gagal berjalan.${NC}"
        journalctl -u xray-cloudflare -n 80 --no-pager || true
        exit 1
    fi

    for cf_port in "$CF_PORT_VMESS" "$CF_PORT_VLESS" "$CF_PORT_TROJAN"; do
        if ! ss -lnt 2>/dev/null | grep -Eq ":${cf_port}\\b"; then
            echo -e "${RED}❌ Port CloudFront ${cf_port} tidak LISTEN.${NC}"
            journalctl -u xray-cloudflare -n 80 --no-pager || true
            exit 1
        fi
    done

    echo -e "${GREEN}✓ CloudFront Xray aktif: VMess + VLESS + Trojan.${NC}"
    echo -e "${GREEN}✓ UUID/password memakai credential ASLI user Marzban.${NC}"
    echo "  VMess  : ${CF_DOMAIN}:443 ${CF_PATH_VMESS}"
    echo "  VLESS  : ${CF_DOMAIN}:443 ${CF_PATH_VLESS}"
    echo "  Trojan : ${CF_DOMAIN}:443 ${CF_PATH_TROJAN}"
    echo "  Sync   : setiap 30 detik"
}


PRECHECK_NGINX_PORTS() {
    echo "Checking ports 80/443 before host Nginx..."
    if ss -lnt 2>/dev/null | grep -Eq '0\.0\.0\.0:80|:::80|0\.0\.0\.0:443|:::443'; then
        echo "WARNING: ports 80/443 are already in use."
        ss -lntp 2>/dev/null | grep -E ':(80|443)\b' || true
    fi
}

PRECHECK_NGINX_PORTS
setup_host_nginx_cloudflare() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Menyiapkan Nginx + SSL + Cloudflare...${NC}"

    apt-get update -y >/dev/null 2>&1
    apt-get install -y nginx openssl >/dev/null 2>&1

    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    mkdir -p /etc/letsencrypt/live/"$domain"

    # Stop the distro Nginx only while ACME standalone binds to port 80.
    systemctl stop nginx >/dev/null 2>&1 || true

    CERT_FULL="/etc/letsencrypt/live/${domain}/fullchain.pem"
    CERT_KEY="/etc/letsencrypt/live/${domain}/privkey.pem"

    NEED_CERT=0
    if [[ ! -s "$CERT_FULL" || ! -s "$CERT_KEY" ]]; then
        NEED_CERT=1
    elif ! openssl x509 -in "$CERT_FULL" -noout -ext subjectAltName 2>/dev/null | grep -Fq "DNS:${CF_DOMAIN}"; then
        NEED_CERT=1
    fi

    if (( NEED_CERT )); then
        if [[ ! -x /root/.acme.sh/acme.sh ]]; then
            curl -fsSL https://get.acme.sh | sh -s email="$email"
        fi

        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        /root/.acme.sh/acme.sh --issue -d "$domain" -d "$CF_DOMAIN" --standalone -k ec-256 --force
        /root/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
            --fullchain-file "$CERT_FULL" \
            --key-file "$CERT_KEY"
    fi

    if [[ ! -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ||
          ! -s "/etc/letsencrypt/live/${domain}/privkey.pem" ]]; then
        echo -e "${RED}❌ SSL certificate tidak tersedia.${NC}"
        exit 1
    fi

    # Do NOT replace Marzban's generated Xray config.
    # Nginx serves the Marzban dashboard on the main domain; CloudFront has a separate hostname.
    cat > /etc/nginx/sites-available/marzban-cloudflare <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\\$host\\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    # Marzban dashboard/API/subscription.
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sfn /etc/nginx/sites-available/marzban-cloudflare /etc/nginx/sites-enabled/marzban-cloudflare

    nginx -t
    systemctl enable nginx >/dev/null 2>&1
    systemctl restart nginx
    sleep 2

    if ! systemctl is-active --quiet nginx; then
        echo -e "${RED}❌ Nginx gagal berjalan.${NC}"
        systemctl status nginx --no-pager -l || true
        exit 1
    fi
}




#profile
echo -e 'profile' >> /root/.profile
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/profile" /usr/local/bin/profile
chmod +x /usr/local/bin/profile

#install compose
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/docker-compose.yml" /opt/marzban/docker-compose.yml

# Force the Marzban container to track the official latest stable image.
# This prevents a custom compose file from silently pinning an older version.
apt-get install -y yq >/dev/null 2>&1 || true
if command -v yq >/dev/null 2>&1; then
    yq -i '.services.marzban.image = "gozargah/marzban:latest"' /opt/marzban/docker-compose.yml
else
    sed -i -E 's#(^[[:space:]]*image:[[:space:]]*gozargah/marzban:).*#\1latest#' /opt/marzban/docker-compose.yml
fi

# Make sure the custom compose file mounts the Marzban data directory.
# Without this mount, the host-installed Xray core cannot be reached by the container.
if command -v yq >/dev/null 2>&1; then
    yq -i '(.services.marzban.volumes //= []) | (.services.marzban.volumes |= unique) | (.services.marzban.volumes += ["/var/lib/marzban:/var/lib/marzban"] | unique)' /opt/marzban/docker-compose.yml
else
    echo -e "${RED}❌ yq tidak tersedia; hentikan instalasi agar Xray-core tidak salah mount.${NC}"
    exit 1
fi

#Install VNSTAT
apt -y install vnstat
/etc/init.d/vnstat restart
apt -y install libsqlite3-dev
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/vnstat-2.6.tar.gz" /root/vnstat-2.6.tar.gz
tar zxvf /root/vnstat-2.6.tar.gz
cd vnstat-2.6
./configure --prefix=/usr --sysconfdir=/etc && make && make install 
cd
chown vnstat:vnstat /var/lib/vnstat -R
systemctl enable vnstat
/etc/init.d/vnstat restart
rm -f /root/vnstat-2.6.tar.gz 
rm -rf /root/vnstat-2.6

#Install Speedtest
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt-get install speedtest -y

# Nginx is configured later by setup_host_nginx_cloudflare().
# Do not download the old custom Nginx/Marzban compose templates here:
# they can conflict with the official Marzban layout and are not needed
# for the dedicated Cloudflare path.
mkdir -p /var/log/nginx
touch /var/log/nginx/access.log /var/log/nginx/error.log
mkdir -p /var/www/html

#install socat
apt install iptables -y
apt install curl socat xz-utils wget apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release jq -y 
apt install socat cron bash-completion -y

#install cert
# Marzban generates/maintains /var/lib/marzban/xray_config.json.
# The Cloudflare inbound is isolated in /var/lib/marzban/cloudfront/config.json.

#install firewall
apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 8081/tcp
sudo ufw allow $port/tcp
yes | sudo ufw enable

# Marzban database
# Do NOT download/restore a bundled db.sqlite3 from GitHub.
# Marzban creates and migrates its runtime database during installation.
mkdir -p /var/lib/marzban

# WARP Proxy tidak dipasang otomatis. Installer ini fokus pada Xray/Marzban.
# Jika WARP diperlukan, pasang secara terpisah melalui menu yang memang digunakan.

#finishing
apt autoremove -y
apt clean
cd /opt/marzban
sed -i "s/# SUDO_USERNAME = \"admin\"/SUDO_USERNAME = \"${userpanel}\"/" /opt/marzban/.env
sed -i "s/# SUDO_PASSWORD = \"admin\"/SUDO_PASSWORD = \"${passpanel}\"/" /opt/marzban/.env
sed -i "s/UVICORN_PORT = 7879/UVICORN_PORT = ${port}/" /opt/marzban/.env
sed -i "s/__MARZBAN_PORT__/${port}/g; s/__MARZBAN_DOMAIN__/${domain}/g" /opt/marzban/xray.conf
docker compose down || true
# Pull the latest Marzban image explicitly so an old local image is never reused.
docker compose pull marzban

# Host Nginx owns ports 80/443. If the compose file contains an Nginx
# service using host networking, disable that service before starting Marzban.
if docker compose config --services 2>/dev/null | grep -qx 'nginx'; then
    echo "Disabling compose nginx: host nginx will own ports 80/443"
    docker compose stop nginx >/dev/null 2>&1 || true
fi
docker compose up -d marzban
sleep 8
if ! docker compose ps >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker Compose Marzban gagal dijalankan.${NC}"
    docker compose ps || true
    exit 1
fi
marzban cli admin import-from-env -y
sed -i "s/SUDO_USERNAME = \"${userpanel}\"/# SUDO_USERNAME = \"admin\"/" /opt/marzban/.env
sed -i "s/SUDO_PASSWORD = \"${passpanel}\"/# SUDO_PASSWORD = \"admin\"/" /opt/marzban/.env
docker compose down || true
docker compose up -d
sleep 5

# Marzban DB now exists; sync its real users into the isolated Cloudflare Xray.
setup_xray_cloudflare

# Start the independent Cloudflare Xray endpoint and host Nginx.
# This does not install, stop, or reconfigure SSH/Dropbear services.
setup_host_nginx_cloudflare

cd
# Verify that the running container uses the latest Marzban image and the requested Xray core.
MARZBAN_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$(docker compose -f /opt/marzban/docker-compose.yml ps -q marzban)" 2>/dev/null || true)"
if [[ "$MARZBAN_IMAGE" != "gozargah/marzban:latest" ]]; then
    echo -e "${RED}❌ Marzban image bukan latest: ${MARZBAN_IMAGE:-unknown}${NC}"
    exit 1
fi
if ! grep -q '^XRAY_EXECUTABLE_PATH = "/var/lib/marzban/core/xray"' /opt/marzban/.env; then
    echo -e "${RED}❌ XRAY_EXECUTABLE_PATH belum mengarah ke core terbaru.${NC}"
    exit 1
fi

# Final health check before reporting success.
if ! docker compose -f /opt/marzban/docker-compose.yml ps >/dev/null 2>&1; then
    echo -e "${RED}❌ Marzban belum sehat. Cek: cd /opt/marzban && docker compose ps${NC}"
    exit 1
fi
echo -e " ${TEAL}╭───────────── ❏ ${WHITE}Login Panel Marzban${NC} ${TEAL}❏ ─────────────╮${NC}" | tee -a log-install.txt
echo -e " ${TEAL}│ ❖${NC} ${WHITE}URL  :${NC} ${ORANGE}${domain}:${port}/dashboard${NC}" | tee -a log-install.txt
echo -e " ${TEAL}│ ❖${NC} ${WHITE}User :${NC} ${ORANGE}${userpanel}${NC}" | tee -a log-install.txt
echo -e " ${TEAL}│ ❖${NC} ${WHITE}Pass :${NC} ${ORANGE}${passpanel}${NC}" | tee -a log-install.txt
echo -e " ${TEAL}╰───────────────────────────────────────────────────╯${NC}" | tee -a log-install.txt
clear

# Unduh skrip pelerr
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Token...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/faiq-token" /usr/local/bin/faiq-token
chmod +x /usr/local/bin/faiq-token
# Unduh skrip Routing
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Routing...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/routing" /usr/local/bin/routing
chmod +x /usr/local/bin/routing
# Unduh skrip Hasil Rute
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Hasil Routing...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/cek-route" /usr/local/bin/cek-route
chmod +x /usr/local/bin/cek-route
# Unduh skrip es pejuh
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service BOT Info...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/bwbot" /usr/local/bin/bwbot
chmod +x /usr/local/bin/bwbot
# Unduh skrip es memek
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Speedtest...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/mod-benchmark" /usr/local/bin/mod-benchmark
chmod +x /usr/local/bin/mod-benchmark
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/speedtest" /usr/local/bin/speedtest
chmod +x /usr/local/bin/speedtest
# Unduh skrip jembot bakar
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Change Domain...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/faiq-change-domain" /usr/local/bin/faiq-change-domain
chmod +x /usr/local/bin/faiq-change-domain
# Unduh Service BOT Usage
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service BOT Usage...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/edydevelopeler/eDYc1Nt4j3kiFoReEveRr/main/jembot.sh" /usr/local/bin/jembot.sh
chmod +x /usr/local/bin/jembot.sh
# Unduh skrip memek goreng
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Update Script...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/faiq-update" /usr/local/bin/faiq-update
chmod +x /usr/local/bin/faiq-update
# Unduh skrip memek bakar
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Limit IP...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/faiq-limit-ip" /usr/local/bin/faiq-limit-ip
chmod +x /usr/local/bin/faiq-limit-ip
# Unduh skrip kontol goreng
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Restore...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/restore" /usr/local/bin/restore
chmod +x /usr/local/bin/restore
# Download backup script
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Backup...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/backup" /usr/local/bin/backup
chmod +x /usr/local/bin/backup
# Download Menu
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Menu...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/menu" /usr/local/bin/menu
chmod +x /usr/local/bin/menu
# Download Repo Rebuild VPS
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Rebuild VPS...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/faiq-rebuild" /usr/local/bin/faiq-rebuild
chmod +x /usr/local/bin/faiq-rebuild
# Download template
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service BOT Template...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/main.py" /usr/local/bin/main.py
chmod +x /usr/local/bin/main.py
# Download template
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Usage VPN...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/usage.py" /usr/local/bin/usage.py
chmod +x /usr/local/bin/usage.py
# Download warpmenu
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Warp...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/warp-hamidgh" /usr/local/bin/warp-hamidgh
chmod +x /usr/local/bin/warp-hamidgh
# Download apdetcore
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Mengunduh Service Update Core...${NC}"
sleep 1.5
download_file "https://raw.githubusercontent.com/faiqzuhry/mummy/main/apdetcore" /usr/local/bin/apdetcore
chmod +x /usr/local/bin/apdetcore

# Tambahkan alias yang valid tanpa mengeksekusi string asing saat shell dibuka.
for entry in "alias faiq-update='/usr/local/bin/faiq-update'" "alias menu='/usr/local/bin/menu'"; do
    grep -Fqx "$entry" /root/.bashrc 2>/dev/null || echo "$entry" >> /root/.bashrc
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN} ♻️ Sabar brother sedang proses pengecekan${NC}${YELLOW}...${NC}"
sleep 2

# Send success message to Telegram
IPVPS=$(curl -fsS --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "Unknown")
HOSTNAME=$(hostname)
OS="${PRETTY_NAME:-unknown}"
ISP=$(curl -fsS --max-time 10 https://ipinfo.io/org 2>/dev/null || echo "Unknown")
REGION=$(curl -fsS --max-time 10 https://ipinfo.io/region 2>/dev/null || echo "Unknown")
DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M:%S')

MESSAGE="\`\`\`
◇━━━━━━━━━━━━━━━━━◇
🤖 SKT x WAN Project 🤖
◇━━━━━━━━━━━━━━━━━◇
❖ Status      : Active
❖ ClientName  : $client_name
❖ Linux OS    : $OS
❖ Nama ISP    : $ISP
❖ Domain      : $domain
❖ IP VPS      : $IPVPS
❖ Area ISP    : $REGION
❖ Waktu       : $TIME
❖ Tanggal     : $DATE
❖ Exp SC      : $exp_date
❖ Status SC   : Registrasi
❖ Presiden    : @SaputraTech
◇━━━━━━━━━━━━━━━━━◇
\`\`\`"

send_telegram_message "$MESSAGE"

clear
sleep 2
echo -e "${YELLOW}╭────────────────────────────────────────────────────┐\033[0m${NC}"
colorized_echo green "│ ➽ Alhamdulillah Beb, Script telah berhasil di install."
echo -e "${CYAN} CloudFront Host : ${CF_DOMAIN}"
echo -e "${CYAN} CloudFront Path : ${CF_PATH_VMESS} | ${CF_PATH_VLESS} | ${CF_PATH_TROJAN}"
echo -e "${CYAN} VMess WS        : ${CF_PATH_VMESS}"
echo -e "${CYAN} VLESS WS        : ${CF_PATH_VLESS}"
echo -e "${CYAN} Trojan WS       : ${CF_PATH_TROJAN}"
echo -e "${CYAN} Xray-core       : ${XRAY_LATEST}"
echo -e "${CYAN} Backends        : 127.0.0.1:${CF_PORT_VMESS},${CF_PORT_VLESS},${CF_PORT_TROJAN}"
echo -e "${YELLOW} DNS Cloudflare  : ${CF_DOMAIN} -> IP VPS + Proxy (orange cloud).${NC}"
rm -f -- "$0" /root/inbound 2>/dev/null || true
colorized_echo magenta "│ ➽ Sabar sayang, Sedang Menghapus admin bawaan db.sqlite"
echo -e "${YELLOW}╰────────────────────────────────────────────────────┘\033[0m${NC}"
marzban cli admin delete -u admin -y
sleep 1
echo -e "[\e[1;31mWARNING\e[0m]➽ Reboot dulu yuk sayang biar gk error, (y/n)? "
read answer
if [ "$answer" == "${answer#[Yy]}" ] ;then
exit 0
else
cat /dev/null > ~/.bash_history && history -c && reboot
fi



