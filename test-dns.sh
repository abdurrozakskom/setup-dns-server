#!/bin/bash

# Script untuk testing DNS Server - FIXED VERSION

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Variables - harus sama dengan setup-dns-server.sh
DOMAIN="example.com"
IP_ADDRESS="192.168.1.10"

# Determine service name
if systemctl is-active --quiet named; then
    SERVICE_NAME="named"
elif systemctl is-active --quiet bind9; then
    SERVICE_NAME="bind9"
else
    SERVICE_NAME="named"
fi

echo "=== DNS SERVER TEST SUITE ==="
echo "Domain: $DOMAIN"
echo "IP Address: $IP_ADDRESS"
echo "Service: $SERVICE_NAME"
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
dig @localhost ns1.$DOMAIN +short
echo "--- Testing www.$DOMAIN ---"
dig @localhost www.$DOMAIN +short
echo "--- Testing ftp.$DOMAIN ---"
dig @localhost ftp.$DOMAIN +short
echo "--- Testing mail.$DOMAIN ---"
dig @localhost mail.$DOMAIN +short

# 3. Test reverse lookup (PTR records)
log "3. Testing reverse lookup (PTR records):"
echo "--- Testing reverse for $IP_ADDRESS ---"
dig @localhost -x $IP_ADDRESS +short

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
echo "--- Testing fileserver.$DOMAIN (CNAME) ---"
dig @localhost fileserver.$DOMAIN CNAME +short

# 7. Test SOA record
log "7. Testing SOA record:"
echo "--- Testing SOA for $DOMAIN ---"
dig @localhost $DOMAIN SOA +short

# 8. Test zone file syntax
log "8. Testing zone file syntax:"
echo "--- Testing forward zone syntax ---"
named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN
echo "--- Testing reverse zone syntax ---"
named-checkzone 1.168.192.in-addr.arpa /etc/bind/zones/db.1.168.192

# 9. Test configuration syntax
log "9. Testing configuration syntax:"
echo "--- Testing named.conf.local ---"
named-checkconf /etc/bind/named.conf.local

# 10. Test listening ports
log "10. Testing listening ports:"
echo "--- Checking port 53 ---"
netstat -tulpn | grep :53 || ss -tulpn | grep :53

# 11. Test from external perspective
log "11. Testing from localhost:"
echo "--- Testing nslookup ---"
nslookup www.$DOMAIN localhost
echo "--- Testing host command ---"
host www.$DOMAIN localhost

# 12. Performance test
log "12. Performance test:"
echo "--- Testing query time ---"
time dig @localhost www.$DOMAIN >/dev/null 2>&1

echo ""
log "🎉 DNS TEST COMPLETE"
echo ""
echo "=== QUICK TEST COMMANDS ==="
echo "dig @localhost www.$DOMAIN"
echo "nslookup $DOMAIN localhost"
echo "systemctl status $SERVICE_NAME"
echo "journalctl -u $SERVICE_NAME -n 10"