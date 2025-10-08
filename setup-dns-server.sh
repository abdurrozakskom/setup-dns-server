#!/bin/bash

# Script untuk konfigurasi DNS Server (Bind9) pada Debian - INTERAKTIF VERSION
# Author: System Administrator
# Date: $(date +%Y-%m-%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function untuk log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function untuk validasi IP address
validate_ip() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Function untuk validasi domain
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function untuk mendapatkan reverse zone dari IP
get_reverse_zone() {
    local ip=$1
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    echo "$i3.$i2.$i1"
}

# Function untuk input interaktif
get_user_input() {
    echo -e "${BLUE}"
    echo "================================================"
    echo "    KONFIGURASI DNS SERVER - INPUT INTERAKTIF   "
    echo "================================================"
    echo -e "${NC}"
    
    # Input domain name
    while true; do
        read -p "Masukkan nama domain (contoh: example.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        else
            error "Format domain tidak valid. Contoh: example.com, company.local, dll."
        fi
    done
    
    # Input IP address
    while true; do
        read -p "Masukkan IP address server DNS (contoh: 192.168.1.10): " IP_ADDRESS
        if validate_ip "$IP_ADDRESS"; then
            break
        else
            error "IP address tidak valid. Contoh: 192.168.1.10, 10.0.0.5, dll."
        fi
    done
    
    # Generate reverse zone otomatis
    REVERSE_ZONE=$(get_reverse_zone "$IP_ADDRESS")
    info "Reverse zone otomatis: $REVERSE_ZONE"
    
    # Konfirmasi reverse zone
    read -p "Apakah reverse zone '$REVERSE_ZONE' sudah benar? (y/n) [y]: " confirm_reverse
    confirm_reverse=${confirm_reverse:-y}
    if [[ $confirm_reverse =~ ^[Nn]$ ]]; then
        read -p "Masukkan reverse zone manual (contoh: 1.168.192): " REVERSE_ZONE
    fi
    
    # Input email admin
    read -p "Masukkan email administrator [admin.$DOMAIN]: " EMAIL
    EMAIL=${EMAIL:-admin.$DOMAIN}
    
    # Tampilkan summary
    echo -e "${GREEN}"
    echo "================================================"
    echo "               SUMMARY KONFIGURASI              "
    echo "================================================"
    echo "Domain         : $DOMAIN"
    echo "IP Address     : $IP_ADDRESS"
    echo "Reverse Zone   : $REVERSE_ZONE"
    echo "Email Admin    : $EMAIL"
    echo "================================================"
    echo -e "${NC}"
    
    # Konfirmasi akhir
    read -p "Apakah konfigurasi di atas sudah benar? (y/n) [y]: " final_confirm
    final_confirm=${final_confirm:-y}
    if [[ ! $final_confirm =~ ^[Yy]$ ]]; then
        info "Mengulang input konfigurasi..."
        get_user_input
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Script harus dijalankan sebagai root user"
    exit 1
fi

# Dapatkan input dari user
get_user_input

# Set nameservers
NAMESERVERS=("ns1.$DOMAIN" "ns2.$DOMAIN")

log "Memulai konfigurasi DNS Server untuk domain: $DOMAIN"

# Update system dan install BIND9
log "Mengupdate package list dan menginstall BIND9..."
apt update
apt install -y bind9 bind9utils bind9-doc dnsutils

if [ $? -ne 0 ]; then
    error "Gagal menginstall BIND9"
    exit 1
fi

log "BIND9 berhasil diinstall"

# Backup konfigurasi original
log "Backup konfigurasi original..."
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.backup
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.backup

# Konfigurasi options
log "Membuat konfigurasi options..."
cat > /etc/bind/named.conf.options << EOF
options {
    directory "/var/cache/bind";
    
    // IPv4 Settings
    listen-on { any; };
    listen-on-v6 { any; };
    
    // Security settings
    allow-query { any; };
    allow-recursion { any; };
    allow-transfer { none; };
    
    // Forwarders
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    // DNS Security Extensions (DNSSEC)
    dnssec-validation auto;
    
    // Version hiding
    version "DNS Server";
    
    // Query logging (disable in production)
    // querylog yes;
    
    auth-nxdomain no;    # conform to RFC1035
    listen-on-v6 { any; };
};
EOF

# Membuat zone file forward (A records)
log "Membuat forward zone file..."
mkdir -p /etc/bind/zones

# Ekstrak octet terakhir dari IP untuk PTR records
IFS='.' read -r i1 i2 i3 i4 <<< "$IP_ADDRESS"

cat > /etc/bind/zones/db.$DOMAIN << EOF
; BIND data file for $DOMAIN
;
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. $EMAIL. (
                              2024010101    ; Serial
                              604800        ; Refresh
                              86400         ; Retry
                              2419200       ; Expire
                              604800 )      ; Negative Cache TTL

; Name Servers
@       IN      NS      ns1.$DOMAIN.
@       IN      NS      ns2.$DOMAIN.

; A Records
@       IN      A       $IP_ADDRESS
ns1     IN      A       $IP_ADDRESS
ns2     IN      A       $IP_ADDRESS
www     IN      A       $IP_ADDRESS
ftp     IN      A       $IP_ADDRESS
mail    IN      A       $IP_ADDRESS
server  IN      A       $IP_ADDRESS

; CNAME Records
webserver IN    CNAME   www
fileserver IN   CNAME   ftp

; MX Record
@       IN      MX      10      mail.$DOMAIN.
EOF

# Membuat reverse zone file (PTR records)
log "Membuat reverse zone file..."
cat > /etc/bind/zones/db.$REVERSE_ZONE << EOF
; BIND reverse data file for $REVERSE_ZONE.in-addr.arpa
;
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. $EMAIL. (
                              2024010101    ; Serial
                              604800        ; Refresh
                              86400         ; Retry
                              2419200       ; Expire
                              604800 )      ; Negative Cache TTL

; Name Servers
@       IN      NS      ns1.$DOMAIN.
@       IN      NS      ns2.$DOMAIN.

; PTR Records
$i4      IN      PTR     ns1.$DOMAIN.
$i4      IN      PTR     ns2.$DOMAIN.
$i4      IN      PTR     www.$DOMAIN.
$i4      IN      PTR     ftp.$DOMAIN.
$i4      IN      PTR     mail.$DOMAIN.
$i4      IN      PTR     server.$DOMAIN.
EOF

# Konfigurasi zone di named.conf.local
log "Mengkonfigurasi zones di named.conf.local..."
cat > /etc/bind/named.conf.local << EOF
// Forward Zone
zone "$DOMAIN" {
    type master;
    file "/etc/bind/zones/db.$DOMAIN";
};

// Reverse Zone
zone "$REVERSE_ZONE.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.$REVERSE_ZONE";
};
EOF

# Set permissions
log "Mengatur permissions..."
chown bind:bind /etc/bind/zones/db.*
chmod 644 /etc/bind/zones/db.*

# Validasi konfigurasi
log "Memvalidasi konfigurasi BIND9..."
named-checkconf /etc/bind/named.conf.local
if [ $? -ne 0 ]; then
    error "Validasi named.conf.local gagal"
    exit 1
fi

named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN
if [ $? -ne 0 ]; then
    error "Validasi forward zone gagal"
    exit 1
fi

named-checkzone $REVERSE_ZONE.in-addr.arpa /etc/bind/zones/db.$REVERSE_ZONE
if [ $? -ne 0 ]; then
    error "Validasi reverse zone gagal"
    exit 1
fi

log "Validasi konfigurasi berhasil"

# FIX: Service management yang aman untuk Debian
log "Mengelola BIND9 service..."

# Tentukan service name yang benar
if systemctl list-unit-files | grep -q "named.service" && systemctl is-active named >/dev/null 2>&1; then
    SERVICE_NAME="named"
elif systemctl list-unit-files | grep -q "bind9.service" && systemctl is-active bind9 >/dev/null 2>&1; then
    SERVICE_NAME="bind9"
else
    # Default ke named
    SERVICE_NAME="named"
fi

log "Menggunakan service: $SERVICE_NAME"

# Stop service yang mungkin berjalan
systemctl stop bind9 2>/dev/null
systemctl stop named 2>/dev/null

# Reset failed state
systemctl reset-failed

# Start service
log "Menjalankan service $SERVICE_NAME..."
systemctl start $SERVICE_NAME

if [ $? -eq 0 ]; then
    log "✅ Service $SERVICE_NAME berhasil dijalankan"
else
    error "❌ Gagal menjalankan service $SERVICE_NAME"
    
    # Coba start manual sebagai fallback
    log "Mencoba start manual BIND9..."
    if /usr/sbin/named -u bind -g; then
        log "✅ BIND9 berhasil dijalankan manual"
    else
        error "❌ BIND9 gagal dijalankan manual"
        exit 1
    fi
fi

# Enable service tanpa force (hindari error alias)
log "Mengenable service..."
if systemctl enable $SERVICE_NAME 2>/dev/null; then
    log "✅ Service $SERVICE_NAME berhasil dienable"
else
    warning "⚠️ Service mungkin sudah enabled, melanjutkan..."
fi

# Check service status
log "Memeriksa status service..."
if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ Service $SERVICE_NAME aktif dan berjalan"
else
    warning "⚠️ Service $SERVICE_NAME tidak aktif"
fi

# Test DNS configuration
log "Testing DNS configuration..."
sleep 2

if dig @localhost ns1.$DOMAIN +short >/dev/null 2>&1; then
    log "✅ DNS forward lookup berhasil"
else
    warning "⚠️ DNS forward lookup mengalami masalah"
fi

if dig @localhost -x $IP_ADDRESS +short >/dev/null 2>&1; then
    log "✅ DNS reverse lookup berhasil"
else
    warning "⚠️ DNS reverse lookup mengalami masalah"
fi

# Update resolv.conf dengan hati-hati
log "Mengupdate /etc/resolv.conf..."
if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup
fi

cat > /etc/resolv.conf << EOF
# Generated by DNS setup script
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
domain $DOMAIN
search $DOMAIN
EOF

# Handle systemd-resolved dengan lebih baik
if systemctl is-active --quiet systemd-resolved; then
    log "Systemd-resolved aktif, menonaktifkan..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved 2>/dev/null
fi

# Firewall configuration (jika menggunakan UFW)
if command -v ufw > /dev/null; then
    log "Mengkonfigurasi firewall..."
    ufw allow 53/tcp
    ufw allow 53/udp
    ufw reload
fi

log "Konfigurasi DNS Server selesai!"
echo ""
echo -e "${GREEN}=== SUMMARY KONFIGURASI ==="
echo "Domain: $DOMAIN"
echo "IP Address: $IP_ADDRESS"
echo "Reverse Zone: $REVERSE_ZONE"
echo "Email Admin: $EMAIL"
echo "Service Name: $SERVICE_NAME"
echo "Service Status: $(systemctl is-active $SERVICE_NAME)"
echo "Forward Zone: /etc/bind/zones/db.$DOMAIN"
echo "Reverse Zone: /etc/bind/zones/db.$REVERSE_ZONE"
echo -e "${NC}"
echo "=== TEST COMMANDS ==="
echo "dig @localhost www.$DOMAIN"
echo "nslookup server.$DOMAIN localhost"
echo "dig @localhost -x $IP_ADDRESS"
echo ""
echo "=== SERVICE MANAGEMENT ==="
echo "systemctl status $SERVICE_NAME"
echo "systemctl restart $SERVICE_NAME"
echo "journalctl -u $SERVICE_NAME -f"