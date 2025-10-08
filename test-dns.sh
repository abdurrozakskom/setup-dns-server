#!/bin/bash

# Script untuk testing DNS Server - INTERAKTIF VERSION

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Function untuk input interaktif
get_test_input() {
    echo -e "${BLUE}"
    echo "================================================"
    echo "         TEST DNS SERVER - INPUT INTERAKTIF     "
    echo "================================================"
    echo -e "${NC}"
    
    # Coba baca dari konfigurasi existing
    if [ -f "/etc/bind/named.conf.local" ]; then
        existing_domain=$(grep -oP 'zone "\K[^"]+' /etc/bind/named.conf.local | head -1)
        if [ ! -z "$existing_domain" ] && [ "$existing_domain" != "." ] && [ "$existing_domain" != "localhost" ]; then
            read -p "Gunakan domain yang ada: $existing_domain? (y/n) [y]: " use_existing
            use_existing=${use_existing:-y}
            if [[ $use_existing =~ ^[Yy]$ ]]; then
                DOMAIN="$existing_domain"
                
                # Cari IP dari zone file
                if [ -f "/etc/bind/zones/db.$DOMAIN" ]; then
                    existing_ip=$(grep -oP '^@\s+IN\s+A\s+\K[0-9.]+' /etc/bind/zones/db.$DOMAIN | head -1)
                    if [ ! -z "$existing_ip" ]; then
                        IP_ADDRESS="$existing_ip"
                    fi
                fi
            fi
        fi
    fi
    
    # Input domain name jika belum ada
    if [ -z "$DOMAIN" ]; then
        while true; do
            read -p "Masukkan nama domain untuk testing (contoh: example.com): " DOMAIN
            if validate_domain "$DOMAIN"; then
                break
            else
                error "Format domain tidak valid. Contoh: example.com, company.local, dll."
            fi
        done
    else
        info "Menggunakan domain: $DOMAIN"
    fi
    
    # Input IP address jika belum ada
    if [ -z "$IP_ADDRESS" ]; then
        while true; do
            read -p "Masukkan IP address server DNS (contoh: 192.168.1.10): " IP_ADDRESS
            if validate_ip "$IP_ADDRESS"; then
                break
            else
                error "IP address tidak valid. Contoh: 192.168.1.10, 10.0.0.5, dll."
            fi
        done
    else
        info "Menggunakan IP address: $IP_ADDRESS"
    fi
    
    # Tampilkan summary
    echo -e "${GREEN}"
    echo "================================================"
    echo "               PARAMETER TESTING                "
    echo "================================================"
    echo "Domain         : $DOMAIN"
    echo "IP Address     : $IP_ADDRESS"
    echo "================================================"
    echo -e "${NC}"
}

# Dapatkan input dari user
get_test_input

# Determine service name
if systemctl is-active --quiet named; then
    SERVICE_NAME="named"
elif systemctl is-active --quiet bind9; then
    SERVICE_NAME="bind9"
else
    SERVICE_NAME="named"
fi

echo -e "${GREEN}=== DNS SERVER TEST SUITE ==="
echo "Domain: $DOMAIN"
echo "IP Address: $IP_ADDRESS"
echo "Service: $SERVICE_NAME"
echo -e "${NC}"
echo ""

# 1. Test service status
log "1. Testing BIND9 service status..."
systemctl status $SERVICE_NAME --no-pager -l | head -10

if systemctl is-active --quiet $SERVICE_NAME; then
    log "✅ Service $SERVICE_NAME aktif"
else
    error "❌ Service $SERVICE_NAME tidak aktif"
    exit 1
fi

# 2. Test forward lookup (A records)
log "2. Testing forward lookup (A records):"
echo "--- Testing ns1.$DOMAIN ---"
result=$(dig @localhost ns1.$DOMAIN +short)
if [ -n "$result" ]; then
    echo "✅ $result"
else
    echo "❌ Tidak ada hasil"
fi

echo "--- Testing www.$DOMAIN ---"
result=$(dig @localhost www.$DOMAIN +short)
if [ -n "$result" ]; then
    echo "✅ $result"
else
    echo "❌ Tidak ada hasil"
fi

echo "--- Testing ftp.$DOMAIN ---"
result=$(dig @localhost ftp.$DOMAIN +short)
if [ -n "$result" ]; then
    echo "✅ $result"
else
    echo "❌ Tidak ada hasil"
fi

# 3. Test reverse lookup (PTR records)
log "3. Testing reverse lookup (PTR records):"
echo "--- Testing reverse for $IP_ADDRESS ---"
result=$(dig @localhost -x $IP_ADDRESS +short)
if [ -n "$result" ]; then
    echo "✅ $result"
else
    echo "❌ Tidak ada hasil"
fi

# 4. Test MX record
log "4. Testing MX record:"
echo "--- Testing MX for $DOMAIN ---"
dig @localhost $DOMAIN MX +short

# 5. Test NS record
log "5. Testing NS record:"
echo "--- Testing NS for $DOMAIN ---"
dig @localhost $DOMAIN NS +short

# 6. Test CNAME records
log "6. Testing CNAME records:"
echo "--- Testing webserver.$DOMAIN (CNAME) ---"
dig @localhost webserver.$DOMAIN CNAME +short

# 7. Test zone file syntax
log "7. Testing zone file syntax:"
if [ -f "/etc/bind/zones/db.$DOMAIN" ]; then
    echo "--- Testing forward zone syntax ---"
    named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN
else
    warning "File zone /etc/bind/zones/db.$DOMAIN tidak ditemukan"
fi

# 8. Test configuration syntax
log "8. Testing configuration syntax:"
echo "--- Testing named.conf.local ---"
named-checkconf /etc/bind/named.conf.local

# 9. Test listening ports
log "9. Testing listening ports:"
echo "--- Checking port 53 ---"
netstat -tulpn | grep :53 || ss -tulpn | grep :53

# 10. Test from external perspective
log "10. Testing from localhost:"
echo "--- Testing nslookup ---"
nslookup www.$DOMAIN localhost

# 11. Performance test
log "11. Performance test:"
echo "--- Testing query time ---"
time dig @localhost www.$DOMAIN >/dev/null 2>&1

echo ""
log "🎉 DNS TEST COMPLETE"
echo ""
echo "=== QUICK TEST COMMANDS ==="
echo "dig @localhost www.$DOMAIN"
echo "nslookup $DOMAIN localhost"
echo "systemctl status $SERVICE_NAME"