#!/bin/bash
# LingVPN Marzban Installer - Auto Resume
# Support: Debian 11/12/13 + Ubuntu 20.04/22.04

sfile="https://raw.githubusercontent.com/faiqzuhry/Faiq-zuhry/main"
# TIMEZONE POLICY: NEUTRAL — jangan set timezone berdasarkan IP/lokasi.
STATE_DIR="/var/lib/lingvpn-install/state"
LOG_FILE="/root/lingvpn-install.log"
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"
set -o pipefail

colorized_echo() {
    local color=$1 text=$2
    case "$color" in
        red) printf '\e[91m%s\e[0m\n' "$text";;
        green) printf '\e[92m%s\e[0m\n' "$text";;
        yellow) printf '\e[93m%s\e[0m\n' "$text";;
        blue) printf '\e[94m%s\e[0m\n' "$text";;
        magenta) printf '\e[95m%s\e[0m\n' "$text";;
        cyan) printf '\e[96m%s\e[0m\n' "$text";;
        *) printf '%s\n' "$text";;
    esac
}

log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

# Error helper used by optional BOT Usage installer and other non-fatal blocks.
err(){ colorized_echo red "[ERROR] $*"; }

if [ "$(id -u)" != "0" ]; then
    colorized_echo red "Error: Skrip ini harus dijalankan sebagai root."
    exit 1
fi

usage(){
cat <<'USAGE'
LingVPN Installer

Pemakaian:
  bash /root/install.sh                 # otomatis resume
  bash /root/install.sh --resume        # lanjut dari checkpoint terakhir
  bash /root/install.sh --reinstall     # ulang seluruh tahap dari awal
  bash /root/install.sh --status        # lihat status tahap
  bash /root/install.sh --reset         # hapus checkpoint, ulang dari awal

Checkpoint disimpan di:
  /var/lib/lingvpn-install/state/

Log utama:
  /root/lingvpn-install.log
USAGE
}

case "${1:-}" in
  --status)
    echo "=== STATUS INSTALLASI LINGVPN ==="
    for i in {01..10}; do
      if [ -f "$STATE_DIR/stage_$i.done" ]; then echo "[✓] Tahap $i selesai"; else echo "[ ] Tahap $i belum selesai"; fi
    done
    echo "Log: $LOG_FILE"
    exit 0
    ;;
  --reset)
    rm -f "$STATE_DIR"/stage_*.done
    log "Checkpoint di-reset. Instalasi akan dimulai dari tahap 01."
    ;;
  --reinstall)
    # Reinstall = jalankan ulang seluruh stage dari 01, bukan sekadar resume.
    # Input tersimpan (/etc/data/*) dipertahankan agar tidak meminta ulang domain
    # dan kredensial panel. Database Marzban juga tetap dilindungi oleh Stage 08.
    rm -f "$STATE_DIR"/stage_*.done
    log "REINSTALL diminta. Semua checkpoint stage dihapus; instalasi dimulai dari tahap 01."
    ;;
  --resume|"") ;;
  -h|--help) usage; exit 0 ;;
  *) colorized_echo red "Opsi tidak dikenal: $1"; usage; exit 1 ;;
esac

run_stage(){
    local id="$1" name="$2" func="$3"
    if [ -f "$STATE_DIR/stage_${id}.done" ]; then
        colorized_echo green "[✓] Tahap ${id} dilewati: ${name}"
        return 0
    fi
    echo
    colorized_echo cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    colorized_echo cyan "[→] Tahap ${id}/10: ${name}"
    colorized_echo cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if "$func"; then
        touch "$STATE_DIR/stage_${id}.done"
        log "DONE ${id} - ${name}"
        colorized_echo green "[✓] Tahap ${id} selesai. Checkpoint tersimpan."
    else
        log "FAILED ${id} - ${name} (exit=$?)"
        colorized_echo red "[x] Tahap ${id} gagal. Jalankan kembali: bash /root/install.sh --resume"
        colorized_echo yellow "    Atau gunakan: bash /root/install.sh --reinstall untuk mengulang semua tahap dari awal."
        exit 1
    fi
}

# Safe sysctl: parameter yang tidak tersedia di kernel akan dilewati.
# Muat kembali konfigurasi tersimpan agar resume melewati input tanpa variabel kosong.
[ -f /etc/os-release ] && {
    os_name=$(grep -E '^ID=' /etc/os-release | cut -d= -f2)
    os_version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
}
for _v in email domain userpanel passpanel nama port choice; do
    case "$_v" in
        choice) _f=/etc/data/ipv6_choice;;
        *) _f=/etc/data/$_v;;
    esac
    if [ -s "$_f" ]; then eval "$_v=\"\$(cat \"$_f\")\""; fi
done
unset _v _f

safe_sysctl_apply(){
    local key value
    [ -f /etc/sysctl.conf ] || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
            if sysctl -n "$key" >/dev/null 2>&1; then
                sysctl -w "$key=$value" >/dev/null 2>&1 || log "WARN sysctl gagal: $key"
            else
                log "SKIP sysctl tidak tersedia di kernel: $key"
            fi
        fi
    done < /etc/sysctl.conf
    return 0
}

# ===== AUTO SWAP 2GB =====
# Membuat dan mengaktifkan Swap 2GB pada VPS baru.
# Aman untuk --resume dan tidak membuat swap kedua jika sudah ada >= 2GB.

setup_swap_2gb(){
    local SWAPFILE="/swapfile"
    local SWAP_MB=2048
    local CURRENT_SWAP_MB=0

    CURRENT_SWAP_MB="$(free -m 2>/dev/null | awk '/^Swap:/ {print $2+0}')"

    # Jika sudah ada Swap >= 2GB, pertahankan konfigurasi yang ada.
    if [ "${CURRENT_SWAP_MB:-0}" -ge "$SWAP_MB" ]; then
        colorized_echo green "[✓] Swap >= 2GB sudah tersedia."
        return 0
    fi

    # Jika /swapfile ada tetapi tidak aktif/ukurannya salah, buat ulang.
    if [ -f "$SWAPFILE" ]; then
        if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAPFILE"; then
            colorized_echo green "[✓] /swapfile sudah aktif."
            return 0
        fi
        rm -f "$SWAPFILE"
    fi

    colorized_echo cyan "[*] Membuat Swap 2GB..."

    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l 2G "$SWAPFILE" 2>/dev/null || true
    fi

    # Fallback jika fallocate gagal/tidak tersedia.
    if [ ! -f "$SWAPFILE" ] || \
       [ "$(stat -c '%s' "$SWAPFILE" 2>/dev/null || echo 0)" -lt 2147483648 ]; then
        rm -f "$SWAPFILE"
        dd if=/dev/zero of="$SWAPFILE" bs=1M count=2048 status=none
    fi

    chmod 600 "$SWAPFILE"

    if ! mkswap "$SWAPFILE" >/dev/null 2>&1; then
        colorized_echo yellow "[!] Gagal membuat Swap 2GB."
        rm -f "$SWAPFILE"
        return 0
    fi

    if ! swapon "$SWAPFILE" >/dev/null 2>&1; then
        colorized_echo yellow "[!] Gagal mengaktifkan Swap 2GB."
        return 0
    fi

    # Permanen setelah reboot.
    if ! grep -qE '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap([[:space:]]|$)' /etc/fstab 2>/dev/null; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    # Swap hanya dipakai ketika memang diperlukan.
    if [ -f /etc/sysctl.conf ]; then
        if grep -qE '^[[:space:]]*vm\.swappiness=' /etc/sysctl.conf; then
            sed -i 's/^[[:space:]]*vm\.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
        else
            echo "vm.swappiness=10" >> /etc/sysctl.conf
        fi
    else
        echo "vm.swappiness=10" > /etc/sysctl.conf
    fi

    sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true

    colorized_echo green "[✓] Swap 2GB berhasil dibuat dan diaktifkan."
}

setup_swap_2gb

# ===== END AUTO SWAP 2GB =====

stage01(){
    local supported_os=false
    if [ -f /etc/os-release ]; then
        os_name=$(grep -E '^ID=' /etc/os-release | cut -d= -f2)
        os_version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        os_codename=$(grep -E '^(VERSION_CODENAME|UBUNTU_CODENAME)=' /etc/os-release | cut -d= -f2 | tr -d '"' | head -n1 || true)
        if [ "$os_name" = "debian" ] && [[ "$os_version" =~ ^(11|12|13)$ ]]; then supported_os=true; fi
        if [ "$os_name" = "ubuntu" ] && [[ "$os_version" =~ ^(20\.04|22\.04)$ ]]; then supported_os=true; fi
    fi
    if [ "$supported_os" != true ]; then
        colorized_echo red "OS tidak didukung. Gunakan Debian 11/12/13 atau Ubuntu 20.04/22.04."
        return 1
    fi
    log "OS terdeteksi: $os_name $os_version"

    # Repo functions
    addDebianRepo(){
        local v="$1" c
        case "$v" in 11)c=bullseye;;12)c=bookworm;;13)c=trixie;;*) return 1;; esac
        cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.list 2>/dev/null || true
        cat > /etc/apt/sources.list.d/debian.sources <<EOF2
Types: deb
URIs: http://kartolo.sby.datautama.net.id/debian
Suites: $c $c-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://kartolo.sby.datautama.net.id/debian-security
Suites: ${c}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF2
        : > /etc/apt/sources.list
    }
    addUbuntuRepo(){
        local v="$1" c
        case "$v" in 20.04)c=focal;;22.04)c=jammy;;*) return 1;; esac
        cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        cat > /etc/apt/sources.list <<EOF2
 deb https://buaya.klas.or.id/ubuntu/ $c main restricted universe multiverse
 deb https://buaya.klas.or.id/ubuntu/ ${c}-updates main restricted universe multiverse
 deb https://buaya.klas.or.id/ubuntu/ ${c}-security main restricted universe multiverse
 deb https://buaya.klas.or.id/ubuntu/ ${c}-backports main restricted universe multiverse
EOF2
        sed -i 's/^ //' /etc/apt/sources.list
    }

    mkdir -p /etc/data
    if [ -z "${REPO_CHOICE:-}" ]; then
        COUNTRY_CODE=$(curl -fsS --max-time 10 https://ipinfo.io/country 2>/dev/null || true)
        if [ "$COUNTRY_CODE" = "ID" ]; then
            read -rp "Gunakan repo lokal Indonesia? (y/n): " REPO_CHOICE
        else
            REPO_CHOICE="n"
        fi
        echo "$REPO_CHOICE" > /etc/data/repo_choice
    fi
    [ -f /etc/data/repo_choice ] && REPO_CHOICE=$(cat /etc/data/repo_choice)
    if [[ "$REPO_CHOICE" =~ ^[Yy]$ ]]; then
        [ "$os_name" = "debian" ] && addDebianRepo "$os_version"
        [ "$os_name" = "ubuntu" ] && addUbuntuRepo "$os_version"
    fi

    apt-get update
    apt-get install -y sudo curl lsb-release ca-certificates

    # Simpan input agar resume tidak bertanya ulang.
    read_saved(){ local var="$1" prompt="$2" file="$3"; if [ -s "$file" ]; then printf -v "$var" '%s' "$(cat "$file")"; else read -rp "$prompt" val; printf -v "$var" '%s' "$val"; printf '%s' "$val" > "$file"; fi; }
    # Email ACME dibuat otomatis agar domain tidak pernah salah dipakai sebagai email.
    # Jika file lama berisi domain / email tidak valid, otomatis diganti.
    ACME_EMAIL="faiqzuhry@gmail.com"
    if [ -s /etc/data/email ]; then
        saved_email="$(tr -d '\r\n' < /etc/data/email)"
        if [[ "$saved_email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
            email="$saved_email"
        else
            email="$ACME_EMAIL"
            printf '%s\n' "$email" > /etc/data/email
        fi
    else
        email="$ACME_EMAIL"
        printf '%s\n' "$email" > /etc/data/email
    fi
    colorized_echo green "[✓] Email ACME otomatis: ${email}"
    read_saved domain "Masukkan Domain: " /etc/data/domain
    while true; do
        if [ -s /etc/data/userpanel ]; then
            userpanel=$(cat /etc/data/userpanel)
            break
        fi
        read -rp "Masukkan Username & Password Panel (huruf dan angka): " userpanel
        if [[ "$userpanel" =~ ^[A-Za-z0-9]+$ ]] && [[ ! "$userpanel" =~ [Aa][Dd][Mm][Ii][Nn] ]]; then
            printf '%s\n' "$userpanel" > /etc/data/userpanel
            break
        fi
        echo "Username & Password Panel tidak valid."
    done

    # Username dan password panel sengaja dibuat sama agar cukup satu input.
    passpanel="$userpanel"
    printf '%s\n' "$passpanel" > /etc/data/passpanel

    read_saved nama "Masukkan ISP VPS: " /etc/data/nama
    # Port panel Marzban ditetapkan otomatis ke 12800.
    # Tidak ada pertanyaan port dan nilai lama /etc/data/port ditimpa.
    port="12800"
    printf '%s\n' "$port" > /etc/data/port
    colorized_echo green "[✓] Port Panel Marzban otomatis: ${port}"
    # IPv6 otomatis: gunakan "Ya" bila VPS memiliki IPv6 global/route IPv6,
    # selain itu otomatis "Tidak". Tidak ada pertanyaan interaktif.
    ipv6_addr="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2; exit}')"
    ipv6_route="$(ip -6 route show default 2>/dev/null | head -n1)"
    if [ -n "$ipv6_addr" ] || [ -n "$ipv6_route" ]; then
        choice="1"
        colorized_echo green "[✓] IPv6 terdeteksi — otomatis: Ya"
    else
        choice="2"
        colorized_echo yellow "[!] IPv6 tidak terdeteksi — otomatis: Tidak"
    fi
    printf '%s\n' "$choice" > /etc/data/ipv6_choice

    wget -q -O /etc/sysctl.conf "$sfile/sysctl.conf" || log "WARN: gagal mengambil sysctl.conf, memakai konfigurasi lama."
    case "$choice" in
      1) echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf; echo 'net.ipv6.conf.default.forwarding = 1' >> /etc/sysctl.conf;;
      2) echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf;;
    esac
    safe_sysctl_apply
    export email domain userpanel passpanel nama port choice os_name os_version os_codename
}


stage02() {
    set -e
#Preparation
clear
cd;
apt-get update;

#Remove unused Module
apt-get -y --purge remove samba*;
apt-get -y --purge remove apache2*;
apt-get -y --purge remove sendmail*;
apt-get -y --purge remove bind9*;

#install benchmark
wget -O /usr/bin/bench "https://raw.githubusercontent.com/teddysun/across/master/bench.sh" && chmod +x /usr/bin/bench

#install toolkit
sudo apt-get install -y git perl libio-socket-inet6-perl libsocket6-perl libio-socket-ssl-perl libwww-perl zlib1g-dev dbus iftop zip unzip wget net-tools curl ca-certificates nano sed screen gnupg bc build-essential dirmngr dnsutils at htop iptables cron lsof lnav xz-utils sqlite3
# Optional compatibility packages (do not abort installation if unavailable).
apt-get install -y libcrypt-ssleay-perl libnet-libidn-perl libpcre3 libpcre3-dev bsdmainutils apt-transport-https 2>/dev/null || true

#Install lolcat
apt-get install -y ruby;
gem install lolcat;


}


stage03() {
    set -e

# ===== TIMEZONE NEUTRAL =====
# Installer tidak mengubah timezone host berdasarkan IP/lokasi.
# VPS yang sudah UTC tetap UTC; VPS yang sudah Asia/Jakarta tetap Asia/Jakarta.
# Jangan bind-mount /etc/timezone atau /etc/localtime ke container.
export TZ="${TZ:-$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true)}"
# ===== END TIMEZONE NEUTRAL =====
#Install Marzban
# Gunakan script resmi hanya untuk menyiapkan Docker/CLI.
# Output ditulis ke log agar traceback sementara tidak memenuhi terminal.
curl -fsSL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh -o /tmp/marzban-install.sh

# Jalankan installer resmi Marzban tanpa follow log foreground.
# Script resmi menjalankan follow_marzban_logs setelah up_marzban,
# sehingga instalasi utama akan menunggu Ctrl+C. Di sini hanya pemanggilan
# follow tersebut di dalam install_command yang dinonaktifkan.
if [ -s /tmp/marzban-install.sh ]; then
    awk '
        /^install_command\(\)/ { in_install=1 }
        /^install_yq\(\)/ { in_install=0 }
        in_install && /^[[:space:]]*follow_marzban_logs[[:space:]]*$/ { next }
        { print }
    ' /tmp/marzban-install.sh > /tmp/marzban-install.no-follow.sh
    mv -f /tmp/marzban-install.no-follow.sh /tmp/marzban-install.sh
fi

if ! bash /tmp/marzban-install.sh install 2>&1 | tee -a /var/log/marzban-bootstrap.log; then
    colorized_echo yellow "Bootstrap Marzban selesai dengan peringatan. Instalasi utama akan dilanjutkan dengan konfigurasi resmi di bawah."
fi
rm -f /tmp/marzban-install.sh

#install subs
wget -O /opt/marzban/index.html "https://cdn.jsdelivr.net/gh/MuhammadAshouri/marzban-templates@master/template-01/index.html"

#install env
wget -O /opt/marzban/.env "$sfile/env"

#install compose
wget -O /opt/marzban/docker-compose.yml "$sfile/docker-compose.yml"

# Hapus seluruh bind-mount timezone dari Compose.
# Timezone host/container tidak dikonfigurasi oleh installer.
# Ini mencegah error Docker pada /etc/timezone dan /etc/localtime.
sed -i \
    -e '\#/etc/timezone#d' \
    -e '\#/etc/localtime#d' \
    /opt/marzban/docker-compose.yml

#install assets & core
mkdir -p /etc/autokill/logs
mkdir -p /etc/autokill/penalty_logs
mkdir -p /var/lib/marzban/assets
mkdir -p /var/lib/marzban/core

# Install Xray sesuai arsitektur VPS
XRAY_ARCH="$(uname -m)"
case "$XRAY_ARCH" in
    x86_64)
        XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
        ;;
    aarch64|arm64)
        XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
        ;;
    *)
        colorized_echo red "Arsitektur VPS tidak didukung: $XRAY_ARCH"
        exit 1
        ;;
esac

rm -rf /tmp/xray-install
mkdir -p /tmp/xray-install

curl -fL --retry 5 --retry-delay 2 -o /tmp/xray-install/xray.zip "$XRAY_URL" || {
    colorized_echo red "Gagal download Xray dari sumber resmi."
    exit 1
}

unzip -oq /tmp/xray-install/xray.zip xray -d /tmp/xray-install || {
    colorized_echo red "Gagal extract Xray."
    exit 1
}

if [ ! -s /tmp/xray-install/xray ]; then
    colorized_echo red "Binary Xray kosong/tidak ditemukan."
    exit 1
fi

install -m 755 /tmp/xray-install/xray /var/lib/marzban/core/xray
rm -rf /tmp/xray-install

/var/lib/marzban/core/xray version >/dev/null 2>&1 || {
    colorized_echo red "Binary Xray tidak dapat dijalankan. Arsitektur: $XRAY_ARCH"
    exit 1
}

colorized_echo green "Xray berhasil dipasang: $XRAY_ARCH"

}


stage04() {
    set -e
#profile
echo -e 'profile' >> /root/.profile
wget -O /usr/bin/profile "$sfile/profile";
chmod +x /usr/bin/profile
# Neofetch sudah tidak tersedia pada sebagian release baru (termasuk Debian 13).
# Gunakan fastfetch jika tersedia; neofetch hanya dipasang bila paket tersedia.
if apt-cache show neofetch >/dev/null 2>&1; then
    apt-get install -y neofetch >/dev/null 2>&1 || true
else
    apt-get install -y fastfetch >/dev/null 2>&1 || true
fi

# Profile eksternal dapat memanggil neofetch. Bungkus pemanggilannya agar
# login tidak menghasilkan "neofetch: command not found".
if [ -f /usr/bin/profile ]; then
    sed -i 's/^[[:space:]]*neofetch[[:space:]]*$/command -v neofetch >\/dev\/null 2>\&1 \&\& neofetch || (command -v fastfetch >\/dev\/null 2>\&1 \&\& fastfetch) || true/' /usr/bin/profile
fi

#Install VNSTAT
apt -y install vnstat
systemctl restart vnstat 2>/dev/null || true
apt -y install libsqlite3-dev
# Prefer Debian/Ubuntu's packaged vnstat on modern releases.
# Only fall back to the bundled 2.6 source if the package is unavailable.
if ! command -v vnstat >/dev/null 2>&1; then
    apt-get install -y vnstat || {
        wget -q -O /root/vnstat-2.6.tar.gz "$sfile/vnstat-2.6.tar.gz"
        tar zxf /root/vnstat-2.6.tar.gz -C /root
        cd /root/vnstat-2.6
        ./configure --prefix=/usr --sysconfdir=/etc && make -j"$(nproc)" && make install
        cd /root
        rm -rf /root/vnstat-2.6 /root/vnstat-2.6.tar.gz
    }
fi
mkdir -p /var/lib/vnstat
chown -R vnstat:vnstat /var/lib/vnstat 2>/dev/null || true
systemctl enable --now vnstat 2>/dev/null || true

#Install Speedtest
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt-get install speedtest -y

#install gotop
rm -rf /tmp/gotop
git clone --depth 1 https://github.com/cjbassi/gotop /tmp/gotop
cd /tmp/gotop
./scripts/download.sh || true
if [ -f /tmp/gotop/gotop ]; then
    install -m 755 /tmp/gotop/gotop /usr/bin/gotop
fi
cd /root

}


stage05() {
    set -e
#install nginx
mkdir -p /var/log/nginx
touch /var/log/nginx/access.log
touch /var/log/nginx/error.log
wget -O /opt/marzban/nginx.conf "$sfile/nginx.conf"
wget -O /opt/marzban/default.conf "$sfile/vps.conf"
wget -O /opt/marzban/xray.conf "$sfile/xray.conf"

# NGINX HASH HARDENING
# Mencegah: could not build server_names_hash
if ! grep -q 'server_names_hash_bucket_size' /opt/marzban/nginx.conf; then
    sed -i \
        '/^[[:space:]]*types_hash_max_size 2048;/a\    server_names_hash_bucket_size 64;' \
        /opt/marzban/nginx.conf
fi
# Sinkronkan server_name Xray dengan domain yang dimasukkan saat instalasi.
domain="$(cat /etc/data/domain 2>/dev/null || printf "")"
if [ -z "$domain" ]; then echo "ERROR: domain kosong."; exit 1; fi
if grep -qE '^[[:space:]]*server_name[[:space:]]+[^;]+;' /opt/marzban/xray.conf; then
    sed -i -E "0,/^[[:space:]]*server_name[[:space:]]+[^;]+;/s//            server_name ${domain};/" /opt/marzban/xray.conf
else
    printf '\n            server_name %s;\n' "$domain" >> /opt/marzban/xray.conf
fi
mkdir -p /var/www/html
echo "<pre>Setup by AutoScript LingVPN</pre>" > /var/www/html/index.html

#install socat
apt install iptables -y
apt install curl socat xz-utils wget gnupg gnupg2 dnsutils lsb-release -y 
apt install socat cron bash-completion -y

#install cert
curl -4fsSL https://get.acme.sh | sh -s email="$email"
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
# Request the certificate only for the VPS domain.
# cf.${domain} is handled by CloudFront and is intentionally not included.
# ACME standalone membutuhkan TCP/80 kosong.
# Matikan stack Marzban sementara bila sudah ada, lalu pastikan port 80 bebas.
if [ -f /opt/marzban/docker-compose.yml ] || [ -f /opt/marzban/compose.yml ]; then
    cd /opt/marzban
    if command -v docker >/dev/null 2>&1; then
        docker compose down >/dev/null 2>&1 || true
    fi
fi
if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$'; then
    echo "ERROR: TCP/80 masih digunakan. ACME standalone tidak dapat dilanjutkan."
    ss -ltnp 2>/dev/null | grep -E '(:|\])80[[:space:]]' || true
    exit 1
fi
/root/.acme.sh/acme.sh --server letsencrypt --register-account --issue -d "$domain" --standalone -k ec-256 --debug
~/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /var/lib/marzban/xray.crt --keypath /var/lib/marzban/xray.key --ecc
wget -O /var/lib/marzban/xray_config.json "$sfile/xray_config.json"

}


stage06() {
    set -e
#install command
cd /usr/bin
#List Trojan
wget -O addtrws "$sfile/addtrws" && chmod +x addtrws
wget -O addtrhu "$sfile/addtrhu" && chmod +x addtrhu
wget -O addtrgrpc "$sfile/addtrgrpc" && chmod +x addtrgrpc
wget -O addtrojan "$sfile/addtrojan" && chmod +x addtrojan
#Lits VMess
wget -O addvmws "$sfile/addvmws" && chmod +x addvmws
wget -O addvmhu "$sfile/addvmhu" && chmod +x addvmhu
wget -O addvmgrpc "$sfile/addvmgrpc" && chmod +x addvmgrpc
wget -O addvmess "$sfile/addvmess" && chmod +x addvmess
#List VLess
wget -O addvlws "$sfile/addvlws" && chmod +x addvlws
wget -O addvlhu "$sfile/addvlhu" && chmod +x addvlhu
wget -O addvlgrpc "$sfile/addvlgrpc" && chmod +x addvlgrpc
wget -O addvless "$sfile/addvless" && chmod +x addvless
#List ShadowSocks
wget -O addshadow "$sfile/addshadow" && chmod +x addshadow
wget -O addsso "$sfile/addsso" && chmod +x addsso
wget -O addssws "$sfile/addssws" && chmod +x addssws
wget -O addsshu "$sfile/addsshu" && chmod +x addsshu
wget -O addssgrpc "$sfile/addssgrpc" && chmod +x addssgrpc
wget -O addtrial "$sfile/addtrial" && chmod +x addtrial
#Additional
wget -O status "$sfile/status" && chmod +x status
wget -qO /usr/bin/menu "$sfile/menu" && chmod 755 /usr/bin/menu
test -s /usr/bin/menu || { echo "ERROR: file menu kosong/gagal di-download."; exit 1; }
bash -n /usr/bin/menu || { echo "ERROR: file menu dari repository tidak valid."; exit 1; }
# Download ganti_domain sebagai file terpisah dari repository.
wget -qO /usr/bin/ganti_domain "$sfile/ganti_domain" && chmod 755 /usr/bin/ganti_domain
test -s /usr/bin/ganti_domain || { echo "ERROR: file ganti_domain kosong/gagal di-download."; exit 1; }
bash -n /usr/bin/ganti_domain || { echo "ERROR: file ganti_domain dari repository tidak valid."; exit 1; }
wget -O ceklogin "$sfile/ceklogin" && chmod +x ceklogin
wget -O hapus "$sfile/hapus" && chmod +x hapus
wget -O renew "$sfile/renew" && chmod +x renew
wget -O resetusage "$sfile/resetusage" && chmod +x resetusage
wget -O buat_token "$sfile/buat_token" && chmod +x buat_token
wget -O cekservice "$sfile/cekservice" && chmod +x cekservice
wget -O ram "$sfile/ram" && chmod +x ram
# Backup/Restore: gunakan versi otomatis Telegram tanpa password dan tanpa input File ID.
# Dipasang sebagai /usr/bin/menu-backup.
wget -O /usr/bin/menu-backup "$sfile/menu-backup" && chmod 755 /usr/bin/menu-backup
if [ ! -s /usr/bin/menu-backup ]; then
    colorized_echo red "ERROR: menu-backup gagal di-download."
    exit 1
fi
bash -n /usr/bin/menu-backup || {
    colorized_echo red "ERROR: syntax menu-backup tidak valid."
    exit 1
}
# Timer backup pada menu-backup memanggil /usr/bin/backup <daily|weekly|monthly>.
# Jadikan backup sebagai alias ke menu-backup yang sama agar backup otomatis
# memakai mekanisme tanpa password yang identik dengan menu-backup.
ln -sfn /usr/bin/menu-backup /usr/bin/backup

wget -O menu-reboot "$sfile/menu-reboot" && chmod +x menu-reboot
wget -O menu-akun "$sfile/menu-akun" && chmod +x menu-akun
wget -O clearlog "$sfile/clearlog" && chmod +x clearlog
# Jalankan clearlog otomatis setiap hari pukul 02:00 WIB.
cat > /etc/cron.d/clearlog_otomatis <<'EOF'
00 2 * * * root /usr/bin/clearlog >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/clearlog_otomatis
systemctl restart cron 2>/dev/null || true
wget -O ceklog "$sfile/ceklog" && chmod +x ceklog
wget -O cekerror "$sfile/cekerror" && chmod +x cekerror
wget -O ceknginx "$sfile/ceknginx" && chmod +x ceknginx
wget -O expired "$sfile/expired" && chmod +x expired
wget -O setlimit "$sfile/setlimit" && chmod +x setlimit
wget -O autokill "$sfile/autokill" && chmod +x autokill

# =========================================================
# Install BWBOT - bandwidth monitor Telegram
# Aman untuk installer: tidak meminta input, tidak mengubah Marzban,
# memakai konfigurasi Telegram bersama menu-backup, dan dijalankan 02:00.
# =========================================================
cat > /usr/local/bin/bwbot <<'BWBOT_EOF'
#!/bin/bash

# BWBOT 02AM - CLEAN / SYNC
# - Public IP otomatis
# - Telegram config bersama dengan menu-backup
# - Client/expiry dari permission database
# - Tidak bergantung pada CRONTAB_ENABLED_FILE
# - Cron dijadwalkan di /etc/cron.d/bwbot (02:00)

set -u

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export CYAN='\033[0;36m'
export PINK='\033[0;35m'
export ORANGE='\033[38;5;208m'
export TEAL='\033[38;5;30m'
export WHITE='\033[1;37m'
export NC='\033[0m'

CONFIG_FILE="/etc/data/telegram_config.conf"
PERMISSION_URL="https://raw.githubusercontent.com/faiqzuhry/akses-faiq/main/iphost.txt"
IPIFY_URL="https://api.ipify.org"
IPINFO_IP_URL="https://ipinfo.io/ip"
IPINFO_JSON_BASE="https://ipinfo.io"
TELEGRAM_API="https://api.telegram.org"

# ---------- Helpers ----------
die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl tidak tersedia."
command -v jq >/dev/null 2>&1 || die "jq tidak tersedia."
command -v vnstat >/dev/null 2>&1 || die "vnstat tidak tersedia."

# ---------- Shared Telegram config ----------
if [[ ! -s "$CONFIG_FILE" ]]; then
    die "Konfigurasi Telegram belum tersedia. Jalankan menu-backup dan simpan konfigurasi Telegram."
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

BOT_TOKEN="${BOT_TOKEN:-${botToken:-}}"
CHAT_ID="${CHAT_ID:-${chatId:-}}"
REMARKS="${REMARKS:-}"
button_text="${button_text:-Cek Server}"
button_url="${button_url:-https://google.com}"

[[ -n "$BOT_TOKEN" ]] || die "BOT_TOKEN kosong."
[[ -n "$CHAT_ID" ]] || die "CHAT_ID kosong."
[[ -n "$button_text" ]] || button_text="Cek Server"
[[ -n "$button_url" ]] || button_url="https://google.com"

# ---------- System ----------
OS=$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
RAM=$(free -m | awk '/Mem:/ {print $2}')
UPTIME=$(uptime -p 2>/dev/null || echo "-")
DOMAIN=$(cat /etc/data/domain 2>/dev/null || echo "-")

# ---------- Public IP ----------
IP_VPS=$(curl -4fsS --max-time 10 "$IPIFY_URL" 2>/dev/null || true)

if [[ -z "$IP_VPS" ]]; then
    IP_VPS=$(curl -4fsS --max-time 10 "$IPINFO_IP_URL" 2>/dev/null || true)
fi

if [[ -z "$IP_VPS" ]]; then
    IP_VPS=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

[[ -n "$IP_VPS" ]] || die "Tidak dapat mendeteksi IP VPS."

echo -e "${TEAL}♻️ Detected public IP VPS: ${CYAN}${IP_VPS}${NC}"

# ---------- IP / ISP information ----------
IP_INFO=$(curl -4fsS --max-time 10 "${IPINFO_JSON_BASE}/${IP_VPS}/json" 2>/dev/null || true)

ISP=$(printf '%s' "$IP_INFO" | jq -r '.org // empty' 2>/dev/null || true)
REGION=$(printf '%s' "$IP_INFO" | jq -r '.timezone // .region // empty' 2>/dev/null || true)
IP_COUNTRY=$(printf '%s' "$IP_INFO" | jq -r '.country // empty' 2>/dev/null || true)
IP_LOC=$(printf '%s' "$IP_INFO" | jq -r '.loc // empty' 2>/dev/null || true)

[[ -n "$ISP" ]] || ISP="Unknown ISP"
[[ -n "$REGION" ]] || REGION="-"

# ---------- Permission database ----------
# Hanya satu request. Tidak ada curl dengan URL kosong.
PERMISSION_FILE=$(curl -4fsS --max-time 10 "$PERMISSION_URL" 2>/dev/null || true)

clientname="Auto IP"
exp_date="-"
CLIENT_REGISTERED="no"

if [[ -n "$PERMISSION_FILE" ]]; then
    CLIENT_INFO=$(printf '%s\n' "$PERMISSION_FILE" |
        awk -v ip="$IP_VPS" '$1 == ip {print $2 "|" $4; exit}')

    if [[ -n "$CLIENT_INFO" ]]; then
        IFS='|' read -r clientname exp_date <<< "$CLIENT_INFO"
        CLIENT_REGISTERED="yes"
    fi
fi

# ---------- Expiry ----------
current_date=$(date +%Y-%m-%d)

if [[ "$exp_date" != "-" && "$exp_date" != "Not Found" && -n "$exp_date" ]]; then
    if expiry_epoch=$(date -d "$exp_date" +%s 2>/dev/null); then
        current_epoch=$(date -d "$current_date" +%s)

        if (( expiry_epoch < current_epoch )); then
            echo -e "${RED}[ INFO ] Script Expired ⛔${NC}"
            echo -e "${CYAN}Contact admin : ✦ @Faiqzuhry ✦${NC}"
            exit 1
        fi

        days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
    else
        days_remaining="-"
    fi
else
    days_remaining="-"
fi

# ---------- Bandwidth ----------
vnstat_output=$(
    vnstat -y 1 --style 0 2>/dev/null |
    sed -n 6p |
    awk '{print "Download :", $2, $3 "\nUpload :", $5, $6 "\nTotal Usage :", $8, $9}'
)

if [[ -z "$vnstat_output" ]]; then
    vnstat_output=$'Download : -\nUpload : -\nTotal Usage : -'
fi

# ---------- Uptime ----------
uptime_raw="$UPTIME"
uptime_filtered=$(printf '%s\n' "$uptime_raw" |
    sed -e 's/.*up *//' \
        -e 's/minutes/min/g' \
        -e 's/minute/min/g' \
        -e 's/hours/hrs/g' \
        -e 's/hour/hr/g' \
        -e 's/weeks/week/g' \
        -e 's/days/day/g' |
    awk -F, '{print $1 "," $2}')

uptime_final=$(printf '%s' "$uptime_filtered" | sed 's/,$//' | sed 's/^,//')
[[ -n "$uptime_final" ]] || uptime_final="-"

# ---------- Telegram message ----------
current_time=$(date +"%d-%m-%Y %I:%M %p")
button_text_with_emoji="🐳 ${button_text} 🐳"

monospace_message=$(cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━
     🌙 DATA TRAFFIC SERVER 🌙
━━━━━━━━━━━━━━━━━━━━━━━
🌐 ISP : <code>${ISP}</code>
🚀 Status : <code>Active</code>
⏱ Uptime : <code>${uptime_final}</code>
🌍 Reg : <code>${REGION}</code>
➖➖➖➖➖➖➖➖➖➖➖➖
📥 <code>$(printf '%s\n' "$vnstat_output" | sed -n '1p')</code>
📤 <code>$(printf '%s\n' "$vnstat_output" | sed -n '2p')</code>
💼 <code>$(printf '%s\n' "$vnstat_output" | sed -n '3p')</code>
━━━━━━━━━━━━━━━━━━━━━━━
  ⚠️ Automatic 02:00 Update ⚠️
━━━━━━━━━━━━━━━━━━━━━━━
Last Update : ${current_time}
━━━━━━━━━━━━━━━━━━━━━━━
 🤖 Bot Version 0.23.1
EOF
)

keyboard=$(jq -n \
    --arg text "$button_text_with_emoji" \
    --arg url "$button_url" \
    '{inline_keyboard: [[{text: $text, url: $url}]]}')

data=$(jq -n \
    --arg chat_id "$CHAT_ID" \
    --arg text "$monospace_message" \
    --argjson reply_markup "$keyboard" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML", reply_markup: $reply_markup}')

TELEGRAM_URL="${TELEGRAM_API}/bot${BOT_TOKEN}/sendMessage"

if curl -fsS --max-time 20 \
    -X POST "$TELEGRAM_URL" \
    -H "Content-Type: application/json" \
    -d "$data" >/dev/null; then

    echo -e "${CYAN}────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}❖ Pesan berhasil dikirim ke Telegram.${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────${NC}"
else
    echo -e "${RED}❖ Gagal mengirim pesan ke Telegram.${NC}"
    exit 1
fi
BWBOT_EOF
chmod 755 /usr/local/bin/bwbot

# Dependensi BWBOT. curl/vnstat sudah dipakai installer; jq diperlukan bot.
apt-get install -y jq curl vnstat

# Pastikan hanya ada satu jadwal BWBOT dan tidak mengganggu cron lain.
rm -f /etc/cron.d/bwbot
cat > /etc/cron.d/bwbot <<'CRON_EOF'
0 2 * * * root /usr/local/bin/bwbot >/var/log/bwbot.log 2>&1
CRON_EOF
chmod 644 /etc/cron.d/bwbot

# Aktifkan cron tanpa menyentuh konfigurasi service lain.
systemctl enable --now cron 2>/dev/null || systemctl enable --now crond 2>/dev/null || true

log "BWBOT terpasang: /usr/local/bin/bwbot; cron setiap hari 02:00."
wget -O fix-ssl "$sfile/fix-ssl.sh" && chmod +x fix-ssl
wget -O ganticore "$sfile/ganticore" && chmod +x ganticore
wget -O routing "$sfile/routing" && chmod +x routing

# ROUTING HARDENING: validate downloaded routing before continuing.
if [ ! -s /usr/bin/routing ]; then
    colorized_echo red "ERROR: file routing gagal di-download."
    exit 1
fi
bash -n /usr/bin/routing || {
    colorized_echo red "ERROR: syntax routing tidak valid."
    exit 1
}
# ROUTING COMPATIBILITY HARDENING
# - Fix regex variable expansion bug in older routing revisions.
# - Remove legacy allowInsecure so the same routing file remains usable
#   with newer Xray cores where allowInsecure is no longer accepted.
# - Do not hard-code a particular Xray version; the routing preflight below
#   detects the Xray binary actually used by Marzban.
sed -i \
    -e 's/regexp:\.\*$regex\.\*/regexp:.*${regex_routing}.*/g' \
    -e '/^[[:space:]]*"allowInsecure"[[:space:]]*:[[:space:]]*true[[:space:]]*,[[:space:]]*$/d' \
    /usr/bin/routing
apt-get install -y jq curl lsof iproute2 >/dev/null 2>&1 || true
mkdir -p /etc/data
printf '%s\n' "${domain}" > /etc/data/domain
printf '%s\n' "${port}" > /etc/data/port
cat > /usr/local/bin/routing-check <<'ROUTING_CHECK_EOF'
#!/bin/bash
set -u
ROUTING=/usr/bin/routing
[ -x "$ROUTING" ] || { echo "ERROR: /usr/bin/routing tidak ditemukan."; exit 1; }
bash -n "$ROUTING" || { echo "ERROR: syntax /usr/bin/routing tidak valid."; exit 1; }
exec bash "$ROUTING" "$@"
ROUTING_CHECK_EOF
chmod 755 /usr/local/bin/routing-check
colorized_echo green "[✓] Routing berhasil di-download dan syntax valid."
wget -O seeroute "$sfile/seeroute" && chmod +x seeroute
cd

#Install reboot dan expired otomatis
wget -O /usr/bin/reboot_otomatis "$sfile/reboot_otomatis.sh";
chmod +x /usr/bin/reboot_otomatis;
cat > /etc/cron.d/expired_otomatis <<'EOF'
00 1 * * * root /usr/bin/expired >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/expired_otomatis;
systemctl restart cron;

}




# =========================================================
# BOT USAGE - FINAL
# Menggunakan BOT_TOKEN + CHAT_ID yang SAMA dengan BWBOT/menu-backup.
# Menggunakan virtual environment terisolasi untuk python-telegram-bot.
# =========================================================
log "Memasang BOT Usage FINAL..."

apt-get install -y python3 >/dev/null 2>&1

# ==================== BOT USAGE - FINAL ====================
install_bot_usage() {
    log "Memasang BOT Usage..."

    local usage_url="https://raw.githubusercontent.com/faiqzuhry/Faiq-zuhry/main/usage.py"
    local venv="/opt/bot-usage-venv"
    local legacy_venv="/opt/bot-usage-env"
    local usage_file="/usr/local/bin/usage.py"
    local config_file="/etc/data/telegram_config.conf"

    # BOT Usage source
    curl -4fsSL "$usage_url" -o "$usage_file" || {
        err "Gagal download usage.py dari GitHub."
        return 1
    }

    chmod 755 "$usage_file"

    # uv dipakai agar Python 3.12 tersedia tanpa mengubah Python sistem.
    if ! command -v uv >/dev/null 2>&1; then
        log "Memasang uv untuk menyediakan Python 3.12..."
        curl -4LsSf https://astral.sh/uv/install.sh | sh || {
            err "Gagal memasang uv."
            return 1
        }
    fi

    export PATH="/root/.local/bin:/usr/local/bin:$PATH"

    log "Menyiapkan Python 3.12 untuk BOT Usage..."
    uv python install 3.12 || {
        err "Gagal menyediakan Python 3.12."
        return 1
    }

    rm -rf "$venv"
    uv venv --python 3.12 --seed "$venv" || {
        err "Gagal membuat virtual environment BOT Usage."
        return 1
    }

    # Kompatibilitas dengan installer/service lama yang masih memanggil
    # /opt/bot-usage-env/bin/python. Symlink dibuat SETELAH venv benar-benar ada,
    # sehingga tidak pernah menghasilkan "No such file or directory".
    if [ -L "$legacy_venv" ] || [ -e "$legacy_venv" ]; then
        rm -rf "$legacy_venv"
    fi
    ln -s "$venv" "$legacy_venv"

    if [ ! -x "$venv/bin/python" ]; then
        err "Interpreter BOT Usage tidak ditemukan: $venv/bin/python"
        return 1
    fi

    # usage.py diambil dari repository versi terbaru dan dipakai apa adanya.
    # Installer TIDAK melakukan patch/penyisipan kode ke usage.py.

    # PTB 13.15 membutuhkan dependency lama tertentu.
    "$venv/bin/python" -m pip install --no-cache-dir \
        "pip<25" \
        "setuptools<81" \
        wheel \
        "six==1.16.0" \
        "urllib3==1.26.20" \
        "certifi>=2021.5.30" \
        "cachetools==4.2.2" \
        "APScheduler==3.6.3" \
        "pytz>=2018.6" \
        "tornado==6.1" || {
        err "Gagal memasang dependency BOT Usage."
        return 1
    }

    "$venv/bin/python" -m pip install --no-cache-dir \
        "python-telegram-bot==13.15" --no-deps || {
        err "Gagal memasang python-telegram-bot 13.15."
        return 1
    }

    # PTB 13.15 membawa vendored urllib3 yang bermasalah pada environment ini.
    rm -rf "$venv/lib/python3.12/site-packages/telegram/vendor/ptb_urllib3/urllib3"

    # Config BOT_TOKEN tetap bersumber dari /etc/data/telegram_config.conf.
    if [ ! -f "$config_file" ]; then
        err "$config_file tidak ditemukan. Jalankan telegram_final_setup terlebih dahulu."
        return 1
    fi

    local bot_token chat_id
    bot_token="$(grep -m1 '^BOT_TOKEN=' "$config_file" | cut -d= -f2-)"
    chat_id="$(grep -m1 '^CHAT_ID=' "$config_file" | cut -d= -f2-)"

    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        err "BOT_TOKEN/CHAT_ID tidak ditemukan di $config_file."
        return 1
    fi

    # usage.py lama membaca bot_usage.json secara relatif terhadap WorkingDirectory.
    cat > /usr/local/bin/bot_usage.json <<EOF
{
  "API_TOKEN": "$bot_token",
  "CHAT_ID": "$chat_id"
}
EOF
    chmod 600 /usr/local/bin/bot_usage.json

    # Validasi dependency dan syntax sebelum service dijalankan.
    "$venv/bin/python" - <<'PY' || return 1
import telegram
import cachetools
import apscheduler
import tornado
import urllib3
print("telegram =", telegram.__version__)
print("cachetools =", cachetools.__version__)
print("APScheduler =", apscheduler.__version__)
print("tornado =", tornado.version)
print("urllib3 =", urllib3.__version__)
PY

    "$venv/bin/python" -m py_compile "$usage_file" || {
        err "usage.py gagal py_compile."
        return 1
    }

    # Verifikasi juga path legacy yang muncul pada installer lama.
    "$legacy_venv/bin/python" --version >/dev/null 2>&1 || {
        err "Compatibility interpreter BOT Usage gagal: $legacy_venv/bin/python"
        return 1
    }

    systemctl disable --now bot-usage.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/bot-usage.service

    cat > /etc/systemd/system/check-usage.service <<'EOF'
[Unit]
Description=Telegram Check Usage Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/opt/bot-usage-venv/bin/python /usr/local/bin/usage.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable check-usage.service >/dev/null 2>&1
    systemctl restart check-usage.service
    sleep 3

    if systemctl is-active --quiet check-usage.service; then
        log "[✓] BOT Check Usage aktif."
    else
        err "BOT Check Usage gagal aktif."
        systemctl status check-usage.service --no-pager || true
        journalctl -u check-usage.service -n 30 --no-pager || true
        return 1
    fi
}

stage07() {
    set -e
#install Firewall
apt install ufw -y
apt install fail2ban -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 1080/tcp
sudo ufw allow 2082/tcp
sudo ufw allow 2083/tcp
sudo ufw allow 3128/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 8880/tcp
sudo ufw allow 8081/tcp
sudo ufw allow $port/tcp
yes | sudo ufw enable
systemctl enable ufw
systemctl start ufw

}


stage08() {
    set -e
#install database
# Jangan menimpa database Marzban yang sudah ada.
if [ -s /var/lib/marzban/db.sqlite3 ]; then
    echo "Database Marzban existing ditemukan; tidak ditimpa."
    cp -a /var/lib/marzban/db.sqlite3 "/var/lib/marzban/db.sqlite3.backup.$(date +%Y%m%d-%H%M%S)"
else
    wget -O /var/lib/marzban/db.sqlite3 "$sfile/db.sqlite3"
fi

#install warp
wget -O /root/warp "https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh"
sudo chmod +x /root/warp
sudo bash /root/warp -y
rm /root/warp

#finishing
apt autoremove -y
apt clean


}



# Logrotate Marzban
mkdir -p /etc/logrotate.d
cat > /etc/logrotate.d/marzban <<'EOF'
/var/lib/marzban/assets/*.log {
    daily
    rotate 7
    size 50M
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF


stage09() {
    set -e
cd /opt/marzban

# ===== TIMEZONE NEUTRAL =====
# Jangan mengubah timezone host/container. Hapus bind-mount timezone
# dari compose agar Docker mengikuti environment tanpa memaksa zona waktu.
sed -i -e '\\#/etc/timezone#d' -e '\\#/etc/localtime#d' /opt/marzban/docker-compose.yml 2>/dev/null || true
# ===== END TIMEZONE NEUTRAL =====

# ---------------------------------------------------------
# Marzban database safety + migration
# Mencegah error: sqlite3.OperationalError: no such column: admins.users_usage
# ---------------------------------------------------------
if [ ! -f /opt/marzban/.env ] || [ ! -f /opt/marzban/docker-compose.yml ]; then
    colorized_echo red "File konfigurasi Marzban tidak lengkap."
    return 1
fi

# Pastikan Compose yang dipakai migration bersih dari konfigurasi timezone.
# Ini juga memperbaiki instalasi lama saat --resume langsung masuk ke Stage 09.
sed -i \
    -e '\#/etc/timezone#d' \
    -e '\#/etc/localtime#d' \
    /opt/marzban/docker-compose.yml

# Pastikan image panel dan migration berasal dari upstream Marzban yang sama.
# Ini mencegah compose custom lama menjalankan kode baru dengan schema lama.
if grep -qE 'image:[[:space:]]*gozargah/marzban:' /opt/marzban/docker-compose.yml; then
    sed -i -E 's#(image:[[:space:]]*gozargah/marzban:)[^[:space:]]+#\1latest#' /opt/marzban/docker-compose.yml
fi

# Migration tanpa membuat backup database otomatis sebelum migration.
DB_BACKUP=""

# Set kredensial sementara untuk import admin.
sed -i "s/# SUDO_USERNAME = \"admin\"/SUDO_USERNAME = \"${userpanel}\"/" /opt/marzban/.env
sed -i "s/# SUDO_PASSWORD = \"admin\"/SUDO_PASSWORD = \"${passpanel}\"/" /opt/marzban/.env
sed -i "s/UVICORN_PORT = 7879/UVICORN_PORT = ${port}/" /opt/marzban/.env

if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    colorized_echo red "Docker Compose tidak ditemukan."
    return 1
fi

# Pastikan image Marzban v0.8.4 tersedia sebelum migration.
# Pull langsung dibuat eksplisit agar kegagalan tidak tersembunyi.
MARZBAN_IMAGE="gozargah/marzban:latest"
colorized_echo cyan "Mengambil image ${MARZBAN_IMAGE}..."
if ! docker pull "${MARZBAN_IMAGE}" >> /var/log/marzban-bootstrap.log 2>&1; then
    colorized_echo red "Gagal mengambil image Marzban ${MARZBAN_IMAGE}."
    echo "===== docker pull error ====="
    tail -n 80 /var/log/marzban-bootstrap.log || true
    return 1
fi

# Pastikan compose menunjuk ke image yang benar-benar tersedia.
sed -i -E 's#(image:[[:space:]]*gozargah/marzban:)[^[:space:]]+#\1latest#' /opt/marzban/docker-compose.yml

# Jalankan Alembic SEBELUM panel dijalankan.
# Dengan demikian query admin baru tidak dieksekusi pada schema lama.
colorized_echo cyan "Menjalankan database migration Marzban..."
if ! $COMPOSE_CMD run --rm --no-deps --entrypoint alembic marzban upgrade head; then
    colorized_echo yellow "Perintah alembic langsung gagal, mencoba Python module alembic..."
    if ! $COMPOSE_CMD run --rm --no-deps --entrypoint python marzban -m alembic upgrade head; then
        colorized_echo red "Migration database Marzban gagal."
        return 1
    fi
fi

colorized_echo green "Database migration Marzban berhasil."

# Baru jalankan panel setelah schema selesai dimigrasikan.
$COMPOSE_CMD up -d --remove-orphans

# Tunggu container sehat sebelum import admin.
for i in $(seq 1 30); do
    if $COMPOSE_CMD ps --status running 2>/dev/null | grep -q marzban; then
        break
    fi
    sleep 2
done

# Import admin setelah migration.
# Kompatibilitas dengan model Admin pada image Marzban saat ini:
# telegram_id harus integer dan discord_webhook berupa string.
# Patch dilakukan DI DALAM container sebelum CLI dijalankan.
if $COMPOSE_CMD exec -T marzban bash -lc 'command -v marzban >/dev/null 2>&1' >/dev/null 2>&1; then
    colorized_echo cyan "Menyiapkan kompatibilitas CLI admin Marzban..."

    $COMPOSE_CMD exec -T marzban python - <<'PY'
from pathlib import Path

p = Path("/code/cli/admin.py")
s = p.read_text(encoding="utf-8")
original = s

# Existing-admin path
s = s.replace(
    'AdminPartialModify(password=password, is_sudo=True)',
    'AdminPartialModify(password=password, is_sudo=True, telegram_id=0, discord_webhook="")'
)
s = s.replace(
    'AdminPartialModify(password=password, is_sudo=True, telegram_id="", discord_webhook="")',
    'AdminPartialModify(password=password, is_sudo=True, telegram_id=0, discord_webhook="")'
)

# New-admin path
s = s.replace(
    'AdminCreate(username=username, password=password, is_sudo=True)',
    'AdminCreate(username=username, password=password, is_sudo=True, telegram_id=0, discord_webhook="")'
)
s = s.replace(
    'AdminCreate(username=username, password=password, is_sudo=True, telegram_id="", discord_webhook="")',
    'AdminCreate(username=username, password=password, is_sudo=True, telegram_id=0, discord_webhook="")'
)

if s != original:
    p.write_text(s, encoding="utf-8")
    print("ADMIN_CLI_PATCHED")
else:
    print("ADMIN_CLI_ALREADY_COMPATIBLE_OR_PATTERN_CHANGED")
PY

    if ! $COMPOSE_CMD exec -T marzban bash -lc 'marzban cli admin import-from-env -y'; then
        colorized_echo red "Import admin gagal."
        $COMPOSE_CMD logs --tail=80 marzban || true
        return 1
    fi

    # Remove bootstrap credentials after successful import.
    if [ -f /opt/marzban/.env ]; then
        sed -i             '/^[[:space:]]*SUDO_USERNAME[[:space:]]*=/d;
             /^[[:space:]]*SUDO_PASSWORD[[:space:]]*=/d'             /opt/marzban/.env
    fi
fi

# Hapus kredensial sementara dari .env setelah admin berhasil dibuat.
sed -i "s/SUDO_USERNAME = \"${userpanel}\"/# SUDO_USERNAME = \"admin\"/" /opt/marzban/.env
sed -i "s/SUDO_PASSWORD = \"${passpanel}\"/# SUDO_PASSWORD = \"admin\"/" /opt/marzban/.env

$COMPOSE_CMD up -d --remove-orphans
cd
echo "Marzban siap; melanjutkan ke pembuatan token API."

}



# =========================================================
# ROUTING ENGINE SAFETY HELPERS
# Validasi JSON, outboundTag, dan Xray-core Marzban sebelum konfigurasi diterapkan.
# =========================================================
marzban_xray_bin() {
    # Prefer the binary actually used by current Marzban images.
    # Fall back to the legacy installer path used by older releases.
    if [ -x /var/lib/marzban/xray-core/xray ]; then
        printf '%s\n' /var/lib/marzban/xray-core/xray
        return 0
    fi
    if [ -x /var/lib/marzban/core/xray ]; then
        printf '%s\n' /var/lib/marzban/core/xray
        return 0
    fi
    return 1
}

routing_test_json() {
    local cfg="$1" container xray_bin rc
    [ -s "$cfg" ] || return 1
    jq empty "$cfg" >/dev/null 2>&1 || return 1
    jq -e '.outbounds as $obs | all((.routing.rules // [])[]; (.outboundTag == null) or (.outboundTag as $tag | any($obs[]; .tag == $tag)))' "$cfg" >/dev/null 2>&1 || return 1

    if xray_bin="$(marzban_xray_bin 2>/dev/null)"; then
        "$xray_bin" -test -config "$cfg" >/tmp/routing-xray-test.log 2>&1
        return $?
    fi

    container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^marzban-marzban-1$|^marzban-marzban-[0-9]+$' | head -n1)"
    [ -n "$container" ] || return 1
    docker cp "$cfg" "$container:/tmp/routing-xray-test.json" >/dev/null 2>&1 || return 1

    for xray_bin in /var/lib/marzban/xray-core/xray /var/lib/marzban/core/xray; do
        if docker exec "$container" test -x "$xray_bin" >/dev/null 2>&1; then
            docker exec "$container" "$xray_bin" -test -config /tmp/routing-xray-test.json >/tmp/routing-xray-test.log 2>&1
            rc=$?
            docker exec "$container" rm -f /tmp/routing-xray-test.json >/dev/null 2>&1 || true
            return "$rc"
        fi
    done

    docker exec "$container" rm -f /tmp/routing-xray-test.json >/dev/null 2>&1 || true
    return 1
}

routing_preflight() {
    local cfg="$1"
    routing_test_json "$cfg" || {
        colorized_echo red "[ROUTING] Preflight gagal: konfigurasi ditolak Xray atau outboundTag tidak valid."
        cat /tmp/routing-xray-test.log 2>/dev/null || true
        return 1
    }
    colorized_echo green "[✓] ROUTING PREFLIGHT OK — JSON + outboundTag + Xray."
}

# =========================================================
# XRAY CLOUDFRONT - TAMBAHAN SAJA
# Tidak mengubah SSH/Dropbear/ZiVPN.
# Host: cf.<domain>
# WS: /vmess-cloudfront /vless-cloudfront /trojan-cloudfront
# =========================================================
setup_xray_cloudfront() {
    set -e
    local CF_DOMAIN="cf.${domain}"
    local CF_DIR="/var/lib/marzban/cloudfront"
    local CF_CONFIG="${CF_DIR}/config.json"
    local CF_STATE="${CF_DIR}/active-users.json"
    local CF_SYNC="/usr/local/bin/sync-marzban-cloudfront.py"
    local CF_SERVICE="/etc/systemd/system/xray-cloudfront.service"
    local CF_SYNC_SERVICE="/etc/systemd/system/marzban-cloudfront-sync.service"
    local CF_TIMER="/etc/systemd/system/marzban-cloudfront-sync.timer"
    local CF_NGINX="/opt/marzban/cloudfront-nginx.conf"
    local XRAY_BIN="$(marzban_xray_bin 2>/dev/null || true)"

    [ -n "$XRAY_BIN" ] && [ -x "$XRAY_BIN" ] || { colorized_echo red "❌ Xray-core tidak ditemukan pada path Marzban."; return 1; }
    [ -f /opt/marzban/docker-compose.yml ] || { colorized_echo red "❌ docker-compose.yml Marzban tidak ditemukan."; return 1; }

    mkdir -p "$CF_DIR" /var/log/xray

    # =========================================================
    # CLOUDFRONT SYNC TANPA RESTART XRAY
    #
    # Xray CloudFront dijalankan sebagai instance terpisah.
    # User ditambah/dihapus melalui Xray HandlerService API (adu/rmu),
    # sehingga perubahan akun tidak mematikan listener WS yang sedang aktif.
    # File config tetap disimpan sebagai desired-state + backup/fallback.
    # =========================================================
    cat > "$CF_SYNC" <<'PY'
#!/usr/bin/env python3
import json, os, sqlite3, subprocess, tempfile, time
DB="/var/lib/marzban/db.sqlite3"
OUT="/var/lib/marzban/cloudfront/config.json"
STATE="/var/lib/marzban/cloudfront/active-users.json"
XRAY="/var/lib/marzban/core/xray"
API="127.0.0.1:10085"
TAGS={"vmess":"cf-vmess","vless":"cf-vless","trojan":"cf-trojan"}

def active(expire,status):
    status=(status or "").lower()
    if status and status!="active": return False
    if expire not in (None,0) and int(expire)<=int(time.time()): return False
    return True

def run_api(cmd, cfg):
    r=subprocess.run([XRAY,"api",cmd,f"--server={API}",cfg],text=True,capture_output=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or f"xray api {cmd} gagal").strip())
    return (r.stdout or "").strip()

def write_json(path, obj):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix=".cf-",suffix=".json",dir=os.path.dirname(path))
    with os.fdopen(fd,"w") as f:
        json.dump(obj,f,indent=2,sort_keys=True); f.write("\n")
    os.replace(tmp,path)

def credential(ptype, settings):
    if ptype in ("vmess","vless"):
        uid=settings.get("id")
        return str(uid) if uid else None
    if ptype=="trojan":
        pwd=settings.get("password")
        return str(pwd) if pwd else None
    return None

if not os.path.isfile(DB): raise SystemExit("Database Marzban tidak ditemukan: "+DB)
con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
try:
    rows=con.execute("""
        SELECT u.username, u.status, u.expire, p.type, p.settings
        FROM users AS u
        LEFT JOIN proxies AS p ON p.user_id = u.id
        ORDER BY u.username
    """).fetchall()
finally: con.close()

wanted={}
for r in rows:
    if not active(r["expire"],r["status"]): continue
    try: settings=json.loads(r["settings"] or "{}")
    except Exception: continue
    ptype=(r["type"] or "").lower()
    if ptype not in TAGS: continue
    cred=credential(ptype,settings)
    if not cred: continue
    email=r["username"] or ""
    if not email: continue
    key=f"{ptype}|{email}"
    wanted[key]={"type":ptype,"email":email,"credential":cred}

vmess=[{"id":u["credential"],"email":u["email"]} for u in wanted.values() if u["type"]=="vmess"]
vless=[{"id":u["credential"],"email":u["email"]} for u in wanted.values() if u["type"]=="vless"]
trojan=[{"password":u["credential"],"email":u["email"]} for u in wanted.values() if u["type"]=="trojan"]

cfg={
 "api":{"tag":"api","listen":API,"services":["HandlerService"]},
 "log":{"access":"/var/log/xray/cloudfront-access.log","error":"/var/log/xray/cloudfront-error.log","loglevel":"warning"},
 "inbounds":[
   {"tag":TAGS["vmess"],"listen":"127.0.0.1","port":10010,"protocol":"vmess","settings":{"clients":vmess},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-cloudfront","heartbeatPeriod":30}}},
   {"tag":TAGS["vless"],"listen":"127.0.0.1","port":10011,"protocol":"vless","settings":{"clients":vless,"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-cloudfront","heartbeatPeriod":30}}},
   {"tag":TAGS["trojan"],"listen":"127.0.0.1","port":10012,"protocol":"trojan","settings":{"clients":trojan},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/trojan-cloudfront","heartbeatPeriod":30}}}],
 "outbounds":[{"protocol":"freedom","tag":"direct"}]
}
write_json(OUT,cfg)

    # Runtime reconcile uses the proven full config.json API call.
# This avoids the per-user temporary-file method that previously left
# runtime empty on a fresh VPS.
def runtime_users(tag):
    r = subprocess.run(
        [XRAY, "api", "inbounduser", f"--server={API}", f"-tag={tag}"],
        text=True, capture_output=True
    )
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "inbounduser gagal").strip())
    try:
        data = json.loads(r.stdout or "{}")
    except Exception:
        return []
    return sorted(set(
        item.get("email") for item in data.get("users", [])
        if isinstance(item, dict) and item.get("email")
    ))

def remove_runtime(tag, emails):
    if not emails:
        return
    r = subprocess.run(
        [XRAY, "api", "rmu", f"--server={API}", f"-tag={tag}", *emails],
        text=True, capture_output=True
    )
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "rmu gagal").strip())

def add_all_runtime():
    # Proven working form: one adu call against the complete config.json.
    r = subprocess.run(
        [XRAY, "api", "adu", f"--server={API}", OUT],
        text=True, capture_output=True
    )
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "adu gagal").strip())

expected = {
    "cf-vmess": sorted(u["email"] for u in vmess),
    "cf-vless": sorted(u["email"] for u in vless),
    "cf-trojan": sorted(u["email"] for u in trojan),
}

try:
    current = {tag: runtime_users(tag) for tag in expected}
except Exception:
    # During the first installer pass Xray API may not be ready yet.
    # Config generation must still succeed; the installer will run this script
    # again after xray-cloudfront.service is confirmed ready.
    current = None

if current is None:
    print("CloudFront config dibuat; API runtime belum tersedia.")
elif current != expected:
    print("Runtime berbeda dari desired-state; melakukan reconcile...")
    for tag, emails in current.items():
        remove_runtime(tag, emails)
    if wanted:
        add_all_runtime()

    verified = {tag: runtime_users(tag) for tag in expected}
    if verified != expected:
        raise RuntimeError(
            "Verifikasi runtime gagal: " + json.dumps(verified, sort_keys=True)
        )
    print("CloudFront runtime berhasil disamakan.")
else:
    print("CloudFront runtime sudah sesuai; tidak ada perubahan.")

write_json(STATE, wanted)
print("CloudFront sync selesai.")
print(f"VMess  : {len(vmess)}")
print(f"VLESS  : {len(vless)}")
print(f"Trojan : {len(trojan)}")
print(f"TOTAL  : {len(wanted)}")
print("Xray TIDAK DIRESTART.")
PY
    chmod 755 "$CF_SYNC"

    # Generate desired config before Xray starts. Runtime API sync is done
    # only after Xray API 127.0.0.1:10085 is confirmed ready.
    python3 "$CF_SYNC" >/tmp/cloudfront-sync-initial.log 2>&1 || {
        cat /tmp/cloudfront-sync-initial.log
        return 1
    }

    "$XRAY_BIN" run -test -config "$CF_CONFIG" >/tmp/xray-cloudfront-test.log 2>&1 || {
        cat /tmp/xray-cloudfront-test.log
        return 1
    }

    cat > "$CF_SERVICE" <<EOF
[Unit]
Description=Xray CloudFront WS (Marzban users)
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${CF_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

    # Sinkronisasi hanya mengubah user melalui API. TIDAK ada try-restart/restart
    # di service ini, sehingga koneksi WS aktif tidak diputus saat akun berubah.
    cat > "$CF_SYNC_SERVICE" <<EOF
[Unit]
Description=Sync Marzban users to Xray CloudFront without restart
After=xray-cloudfront.service docker.service
Requires=xray-cloudfront.service
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${CF_SYNC}
EOF

    cat > "$CF_TIMER" <<EOF
[Unit]
Description=Periodic Marzban CloudFront user sync without restart
[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
Unit=marzban-cloudfront-sync.service
Persistent=true
[Install]
WantedBy=timers.target
EOF

    # QUOTED heredoc: Nginx variables must reach Nginx literally.
    # CloudFront AWS: sertifikat origin hanya mencakup DOMAIN utama.
    # Karena itu CloudFront harus memakai ${domain} sebagai Origin Domain
    # dan tidak meneruskan viewer Host (cf.${domain}) ke origin HTTPS.
    # Nginx tetap menerima kedua Host agar tidak rapuh terhadap variasi Host header.
    cat > "$CF_NGINX" <<'NGINX_EOF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__ __CF_DOMAIN__;
    location / {
        return 301 https://$host$request_uri;
    }
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name __DOMAIN__ __CF_DOMAIN__;
    ssl_certificate /var/lib/marzban/xray.crt;
    ssl_certificate_key /var/lib/marzban/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    location = /vmess-cloudfront {
        proxy_pass http://127.0.0.1:10010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host __DOMAIN__;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location = /vless-cloudfront {
        proxy_pass http://127.0.0.1:10011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host __DOMAIN__;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location = /trojan-cloudfront {
        proxy_pass http://127.0.0.1:10012;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host __DOMAIN__;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
    location / { return 404; }
}
NGINX_EOF
    sed -i -e "s#__DOMAIN__#${domain}#g" -e "s#__CF_DOMAIN__#${CF_DOMAIN}#g" "$CF_NGINX"

    apt-get install -y python3-yaml >/dev/null 2>&1 || {
        colorized_echo red "❌ Gagal memasang python3-yaml."
        return 1
    }

    python3 - <<'PY'
from pathlib import Path
import yaml
p = Path("/opt/marzban/docker-compose.yml")
data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
services = data.setdefault("services", {})
nginx = services.get("nginx")
if not isinstance(nginx, dict): raise SystemExit("Service nginx tidak ditemukan di docker-compose.yml")
volumes = nginx.setdefault("volumes", [])
required = [
    "/opt/marzban/nginx.conf:/etc/nginx/nginx.conf:ro",
    "/opt/marzban/cloudfront-nginx.conf:/etc/nginx/cloudfront-nginx.conf:ro",
    "/var/lib/marzban:/var/lib/marzban:ro",
]
for item in required:
    if item not in volumes: volumes.append(item)
p.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False), encoding="utf-8")
print("NGINX_CLOUDFRONT_MOUNTS_OK")
PY

    if ! grep -Fq 'include /etc/nginx/cloudfront-nginx.conf;' /opt/marzban/nginx.conf; then
        python3 - <<'PY'
from pathlib import Path
p=Path("/opt/marzban/nginx.conf")
s=p.read_text()
needle="include /etc/nginx/cloudfront-nginx.conf;"
lines=s.splitlines(True); depth=0; in_http=False; inserted=False; out=[]
for line in lines:
    stripped=line.strip()
    if stripped.startswith("http") and stripped.endswith("{") and not in_http: in_http=True
    if in_http and stripped=="}" and depth==1 and not inserted:
        out.append("    "+needle+"\n"); inserted=True
    out.append(line)
    depth += line.count("{")-line.count("}")
    if in_http and depth<=0: in_http=False
if not inserted: raise SystemExit("Blok http{} tidak ditemukan pada nginx.conf")
p.write_text("".join(out))
PY
    fi

    systemctl disable --now xray-cloudflare.service >/dev/null 2>&1 || true
    systemctl daemon-reload
    systemctl enable --now xray-cloudfront.service

    # Wait until the CloudFront Xray API is actually listening.
    for i in $(seq 1 30); do
        if ss -lnt 2>/dev/null | grep -Eq ':10085\b'; then break; fi
        sleep 1
done
    if ! ss -lnt 2>/dev/null | grep -Eq ':10085\b'; then
        colorized_echo red "❌ Xray CloudFront API 127.0.0.1:10085 tidak LISTEN."
        journalctl -u xray-cloudfront.service -n 80 --no-pager || true
        return 1
    fi

    # First runtime reconcile happens immediately. The timer is only the
    # periodic safety net after the initial installation has been verified.
    python3 "$CF_SYNC" || {
        colorized_echo red "❌ Sinkronisasi awal CloudFront gagal."
        return 1
    }

    systemctl enable --now marzban-cloudfront-sync.timer
    docker compose -f /opt/marzban/docker-compose.yml up -d --force-recreate nginx

    for i in $(seq 1 15); do
        if docker inspect -f '{{.State.Running}}' marzban-nginx-1 2>/dev/null | grep -q true; then break; fi
        sleep 2
    done
    if ! docker inspect -f '{{.State.Running}}' marzban-nginx-1 2>/dev/null | grep -q true; then
        colorized_echo red "❌ Container marzban-nginx-1 tidak RUNNING."
        docker logs --tail 80 marzban-nginx-1 2>&1 || true
        return 1
    fi
    docker compose -f /opt/marzban/docker-compose.yml exec -T nginx nginx -t

    systemctl is-active --quiet xray-cloudfront.service || {
        journalctl -u xray-cloudfront.service -n 80 --no-pager || true
        return 1
    }
    for p in 10010 10011 10012; do
        ss -lnt 2>/dev/null | grep -Eq ":${p}\\b" || {
            echo "CloudFront port ${p} tidak LISTEN."
            journalctl -u xray-cloudfront.service -n 80 --no-pager || true
            return 1
        }
    done

    echo -e "${GREEN}✓ Xray CloudFront: VMess + VLESS + Trojan.${NC}"
    echo "  Viewer : ${CF_DOMAIN}:443 (CloudFront AWS)"
    echo "  Origin : ${domain}:443 (sertifikat origin hanya ${domain})"
    echo "  Paths  : /vmess-cloudfront /vless-cloudfront /trojan-cloudfront"
    echo "  Sync   : API dinamis — tanpa restart Xray saat user berubah"
}

stage10() {
    set -e

    # =========================================================
    # TOKEN API MARZBAN - FINAL ROBUST
    # Jangan langsung request setelah container start.
    # Marzban/uvicorn butuh waktu untuk bind port dan siap menerima API.
    # =========================================================
    mkdir -p /etc/data
    chmod 700 /etc/data

    TOKEN_FILE="/etc/data/token.json"
    TOKEN_TMP="/etc/data/.token.json.tmp"
    rm -f "$TOKEN_TMP"

    # Ambil port yang benar-benar digunakan Marzban dari .env.
    # Jika tidak ditemukan, gunakan port dari konfigurasi installer.
    API_PORT=""
    if [ -f /opt/marzban/.env ]; then
        API_PORT="$(sed -n 's/^[[:space:]]*UVICORN_PORT[[:space:]]*=[[:space:]]*//p' /opt/marzban/.env | tail -n 1 | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
    fi
    [ -n "$API_PORT" ] || API_PORT="${port}"
    [ -n "$API_PORT" ] || API_PORT="8000"

    token_ok() {
        [ -s "$TOKEN_TMP" ] || return 1
        if command -v jq >/dev/null 2>&1; then
            jq -e '(.access_token // "") | length > 0' "$TOKEN_TMP" >/dev/null 2>&1
        else
            grep -q '"access_token"[[:space:]]*:' "$TOKEN_TMP"
        fi
    }

    request_token() {
        local url="$1"
        : > "$TOKEN_TMP"
        curl -4ksS --connect-timeout 5 --max-time 15 \
            -X POST "$url" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode 'grant_type=password' \
            --data-urlencode "username=${userpanel}" \
            --data-urlencode "password=${passpanel}" \
            --data-urlencode 'scope=' \
            --data-urlencode 'client_id=' \
            --data-urlencode 'client_secret=' \
            > "$TOKEN_TMP" 2>/dev/null
    }

    colorized_echo cyan "Menunggu Marzban benar-benar siap..."

    # Tunggu sampai port API benar-benar listen.
    READY=0
    for i in $(seq 1 45); do
        if (command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ":${API_PORT}$|\]:${API_PORT}$") \
           || (command -v netstat >/dev/null 2>&1 && netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ":${API_PORT}$|\]:${API_PORT}$"); then
            READY=1
            break
        fi

        # Pastikan container tetap hidup sambil menunggu.
        if ! docker inspect -f '{{.State.Running}}' marzban-marzban-1 2>/dev/null | grep -q true; then
            $COMPOSE_CMD -f /opt/marzban/docker-compose.yml up -d marzban >/dev/null 2>&1 || true
        fi
        sleep 2
    done

    if [ "$READY" -eq 0 ]; then
        colorized_echo yellow "Port ${API_PORT} belum terdeteksi setelah 90 detik; tetap mencoba API lokal."
    else
        colorized_echo green "Marzban API sudah listen di port ${API_PORT}."
    fi

    colorized_echo cyan "Membuat token API Marzban..."
    TOKEN_SUCCESS=0

    # Coba lokal berulang kali. Ini mengatasi race-condition saat container baru start.
    for i in $(seq 1 15); do
        if request_token "https://127.0.0.1:${API_PORT}/api/admin/token" && token_ok; then
            TOKEN_SUCCESS=1
            break
        fi

        if request_token "http://127.0.0.1:${API_PORT}/api/admin/token" && token_ok; then
            TOKEN_SUCCESS=1
            break
        fi

        sleep 2
    done

    # Domain hanya fallback terakhir.
    if [ "$TOKEN_SUCCESS" -eq 0 ]; then
        for i in $(seq 1 5); do
            if request_token "https://${domain}:${API_PORT}/api/admin/token" && token_ok; then
                TOKEN_SUCCESS=1
                break
            fi
            sleep 2
        done
    fi

    if [ "$TOKEN_SUCCESS" -eq 0 ]; then
        colorized_echo red "Gagal membuat token API Marzban."
        echo "Port API yang digunakan: ${API_PORT}"
        echo "Periksa status Marzban dan listener port:"
        ss -ltnp 2>/dev/null | grep -E ":${API_PORT}[[:space:]]|:${API_PORT}$" || true
        echo
        $COMPOSE_CMD -f /opt/marzban/docker-compose.yml ps 2>/dev/null || true
        echo
        echo "Log Marzban terakhir:"
        $COMPOSE_CMD -f /opt/marzban/docker-compose.yml logs --tail=40 marzban 2>/dev/null || true
        echo
        echo "Respons terakhir:"
        cat "$TOKEN_TMP" 2>/dev/null || true
        rm -f "$TOKEN_TMP"
        return 1
    fi

    mv -f "$TOKEN_TMP" "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    colorized_echo green "Token API Marzban berhasil dibuat."

    cd
    sed -i -e 's/\r$//' /usr/bin/routing
    if command -v neofetch >/dev/null 2>&1; then
        neofetch
    elif command -v fastfetch >/dev/null 2>&1; then
        fastfetch
    fi
    if [ -f ~/.config/neofetch/config.conf ]; then
        sed -i '/info title/d' ~/.config/neofetch/config.conf
        sed -i '/info "Packages" packages/d' ~/.config/neofetch/config.conf
        sed -i '/info "Shell" shell/d' ~/.config/neofetch/config.conf
        sed -i '/info "Resolution" resolution/d' ~/.config/neofetch/config.conf
        sed -i '/info "Memory" memory/d' ~/.config/neofetch/config.conf
    fi
    command -v profile >/dev/null 2>&1 && profile || true
    echo "Untuk data login dashboard Marzban: " | tee -a /root/log-install.txt
    echo "-=================================-" | tee -a /root/log-install.txt
    echo "URL       : https://${domain}:${port}/dashboard" | tee -a /root/log-install.txt
    echo "username  : ${userpanel}" | tee -a /root/log-install.txt
    echo "password  : ${passpanel}" | tee -a /root/log-install.txt
    echo "-=================================-" | tee -a /root/log-install.txt
    echo "Script telah berhasil di install" | tee -a /root/log-install.txt
    marzban cli admin delete -u admin -y || log "WARN: cleanup admin dilewati (exit=$?)"
}

# =========================================================
# REBUILD VPS
# Dipasang sebagai /usr/local/bin/rebuild
# =========================================================
install_rebuild() {
    local target="/usr/local/bin/rebuild"
    local tmp="${target}.tmp"
    local url="${sfile}/rebuild"

    colorized_echo cyan "[*] Memasang Rebuild VPS..."

    if ! command -v curl >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y curl >/dev/null 2>&1 || {
            colorized_echo yellow "[!] curl tidak tersedia. Rebuild dilewati."
            return 0
        }
    fi

    if curl -4fsSL --retry 3 --connect-timeout 15 --max-time 120 \
        "$url" -o "$tmp"; then
        if [ -s "$tmp" ] && bash -n "$tmp" >/dev/null 2>&1; then
            chmod 755 "$tmp"
            mv -f "$tmp" "$target"
            colorized_echo green "[✓] Rebuild VPS terpasang: $target"
        else
            rm -f "$tmp"
            colorized_echo yellow "[!] File Rebuild tidak valid. Instalasi dilanjutkan."
        fi
    else
        rm -f "$tmp"
        colorized_echo yellow "[!] Gagal mengambil Rebuild. Instalasi dilanjutkan."
    fi
}

install_rebuild

run_stage 01 "Validasi OS + input konfigurasi" stage01
run_stage 02 "Persiapan VPS + paket" stage02
run_stage 03 "Bootstrap Marzban + Xray" stage03
run_stage 04 "Profile + VNStat + Speedtest + Gotop" stage04
run_stage 05 "Nginx + SSL + konfigurasi Xray" stage05
run_stage 06 "Command LingVPN + Ganti Domain + BWBOT + cron" stage06
run_stage 07 "Firewall + Fail2ban" stage07
run_stage 08 "Database + WARP" stage08
run_stage 09 "Migration database + Admin Marzban" stage09
setup_xray_cloudfront
run_stage 10 "Token API + finalisasi" stage10

# =========================================================
# TELEGRAM FINAL SETUP - PALING AKHIR
# Token + Chat ID baru diminta setelah seluruh stage 01-10 selesai.
# Config yang sama dipakai BWBOT + menu-backup + BOT Usage.
# =========================================================
telegram_final_setup() {
    mkdir -p /etc/data
    chmod 700 /etc/data

    local config_file="/etc/data/telegram_config.conf"
    local tg_bot tg_chat

    echo
    colorized_echo cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    colorized_echo cyan "        KONFIGURASI TELEGRAM - TAHAP AKHIR"
    colorized_echo cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Semua instalasi VPS sudah selesai."
    echo "Sekarang masukkan Bot Token dan Chat ID Telegram."
    echo

    while true; do
        read -r -p "Masukkan Telegram Bot Token: " tg_bot
        tg_bot="${tg_bot#botToken=}"
        tg_bot="${tg_bot#BOT_TOKEN=}"
        tg_bot="${tg_bot#TELEGRAM_BOT_TOKEN=}"
        tg_bot="${tg_bot//$'\r'/}"
        tg_bot="${tg_bot//$'\n'/}"

        if [[ "$tg_bot" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            break
        fi
        colorized_echo red "[ERROR] Bot Token tidak valid."
    done

    while true; do
        read -r -p "Masukkan Telegram Chat ID: " tg_chat
        tg_chat="${tg_chat#chatId=}"
        tg_chat="${tg_chat#CHAT_ID=}"
        tg_chat="${tg_chat#TELEGRAM_CHAT_ID=}"
        tg_chat="${tg_chat//$'\r'/}"
        tg_chat="${tg_chat//$'\n'/}"

        if [[ "$tg_chat" =~ ^-?[0-9]+$ ]]; then
            break
        fi
        colorized_echo red "[ERROR] Chat ID harus berupa angka."
    done

    # Shell-safe config. Semua nama variabel kompatibel dengan script lama/baru.
    umask 077
    {
        printf 'BOT_TOKEN=%q\n' "$tg_bot"
        printf 'CHAT_ID=%q\n' "$tg_chat"
        printf 'botToken=%q\n' "$tg_bot"
        printf 'chatId=%q\n' "$tg_chat"
        printf 'TELEGRAM_BOT_TOKEN=%q\n' "$tg_bot"
        printf 'TELEGRAM_CHAT_ID=%q\n' "$tg_chat"
        printf 'REMARKS=%q\n' ""
        printf 'button_text=%q\n' "Cek Server"
        printf 'button_url=%q\n' "https://google.com"
    } > "$config_file"
    chmod 600 "$config_file"

    echo
    colorized_echo green "[✓] Konfigurasi Telegram tersimpan."

    # Validasi token langsung ke Telegram tanpa menampilkan token.
    local api_result
    api_result="$(curl -4fsS --connect-timeout 10 --max-time 20 \
        "https://api.telegram.org/bot${tg_bot}/getMe" 2>/dev/null || true)"

    if printf '%s' "$api_result" | grep -q '"ok":true'; then
        colorized_echo green "[✓] Bot Token Telegram valid."
    else
        colorized_echo yellow "[!] Token tersimpan, tetapi validasi Telegram gagal."
        echo "    Periksa token atau koneksi internet bila bot belum merespons."
    fi

    echo
    colorized_echo green "[✓] Telegram BWBOT + menu-backup + BOT Usage tersinkron."
}

telegram_final_setup
install_bot_usage

colorized_echo green "╔════════════════════════════════════════════════════╗"
# =========================================================
# FAIQVPN CHECK_USAGE BOT
# Telegram token/chat ID memakai /etc/data/telegram_config.conf.
# Tidak memasang telegram-vps-menu.py / remote menu.
# =========================================================

# Aktifkan BOT Check Usage sebelum installer menawarkan reboot.

colorized_echo green "╔════════════════════════════════════════════════════╗"
colorized_echo green "║       LINGVPN MARZBAN INSTALLATION SELESAI       ║"
colorized_echo green "╚════════════════════════════════════════════════════╝"
log "INSTALLATION COMPLETE"
echo
echo "Telegram Check Usage: /cek_usage atau /cek_usage username"
echo "Service: check-usage.service"
echo
read -rp "Reboot sekarang? [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then reboot; fi
