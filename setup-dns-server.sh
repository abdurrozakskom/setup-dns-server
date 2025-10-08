#!/bin/bash

# Script untuk konfigururasi DNS Server (Bind9) pada Debian
# Author: System Administrator
# Date: $(date +%Y-%m-%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Script harus dijalankan sebagai root user"
    exit 1
fi

# Variables - Edit sesuai kebutuhan
DOMAIN="example.com"
IP_ADDRESS="192.168.1.10"
REVERSE_ZONE="1.168.192"
NAMESERVERS=("ns1.$DOMAIN" "ns2.$DOMAIN")
EMAIL="admin.$DOMAIN"

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
10      IN      PTR     ns1.$DOMAIN.
10      IN      PTR     ns2.$DOMAIN.
10      IN      PTR     www.$DOMAIN.
10      IN      PTR     ftp.$DOMAIN.
10      IN      PTR     mail.$DOMAIN.
10      IN      PTR     server.$DOMAIN.
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

# Restart BIND9 service
log "Restarting BIND9 service..."
systemctl restart bind9
systemctl enable bind9

if [ $? -ne 0 ]; then
    error "Gagal restart BIND9 service"
    exit 1
fi

# Test DNS configuration
log "Testing DNS configuration..."
dig @localhost ns1.$DOMAIN
dig @localhost $DOMAIN
dig @localhost -x $IP_ADDRESS

# Update resolv.conf
log "Mengupdate /etc/resolv.conf..."
cat > /etc/resolv.conf << EOF
# Generated by DNS setup script
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
domain $DOMAIN
search $DOMAIN
EOF

# Enable DNS on startup
log "Mengkonfigurasi DNS pada startup..."
systemctl disable systemd-resolved
systemctl stop systemd-resolved

# Firewall configuration (jika menggunakan UFW)
if command -v ufw > /dev/null; then
    log "Mengkonfigurasi firewall..."
    ufw allow 53/tcp
    ufw allow 53/udp
fi

log "Konfigurasi DNS Server selesai!"
echo ""
echo "=== SUMMARY KONFIGURASI ==="
echo "Domain: $DOMAIN"
echo "IP Address: $IP_ADDRESS"
echo "Forward Zone: /etc/bind/zones/db.$DOMAIN"
echo "Reverse Zone: /etc/bind/zones/db.$REVERSE_ZONE"
echo "Service Status: $(systemctl is-active bind9)"
echo ""
echo "Test DNS dengan perintah:"
echo "  dig @localhost www.$DOMAIN"
echo "  nslookup server.$DOMAIN localhost"
echo "  dig @localhost -x $IP_ADDRESS"