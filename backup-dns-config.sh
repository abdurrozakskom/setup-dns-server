#!/bin/bash

# Script untuk backup konfigurasi DNS - INTERAKTIF VERSION

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

# Function untuk input interaktif
get_backup_input() {
    echo -e "${BLUE}"
    echo "================================================"
    echo "         BACKUP DNS SERVER - INPUT INTERAKTIF   "
    echo "================================================"
    echo -e "${NC}"
    
    # Default backup directory
    DEFAULT_BACKUP_DIR="/root/dns-backup"
    
    read -p "Masukkan directory backup [$DEFAULT_BACKUP_DIR]: " BACKUP_DIR
    BACKUP_DIR=${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}
    
    # Tanya apakah include data testing
    read -p "Include data testing (dig, nslookup results)? (y/n) [y]: " INCLUDE_TESTING
    INCLUDE_TESTING=${INCLUDE_TESTING:-y}
    
    # Tanya apakah cleanup backup lama
    read -p "Bersihkan backup lama (simpan 5 terbaru)? (y/n) [y]: " CLEANUP_OLD
    CLEANUP_OLD=${CLEANUP_OLD:-y}
    
    echo -e "${GREEN}"
    echo "================================================"
    echo "               SETTING BACKUP                   "
    echo "================================================"
    echo "Backup Directory : $BACKUP_DIR"
    echo "Include Testing  : $INCLUDE_TESTING"
    echo "Cleanup Old      : $CLEANUP_OLD"
    echo "================================================"
    echo -e "${NC}"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    error "Script harus dijalankan sebagai root user"
    exit 1
fi

# Dapatkan input dari user
get_backup_input

# Backup configuration
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="dns_backup_$DATE.tar.gz"

log "Memulai backup konfigurasi DNS Server..."

# Create backup directory
mkdir -p $BACKUP_DIR/$DATE

log "Backup file konfigurasi BIND9..."

# Backup BIND9 configuration files
cp -r /etc/bind $BACKUP_DIR/$DATE/
cp /etc/resolv.conf $BACKUP_DIR/$DATE/

# Backup zone files jika ada
if [ -d "/etc/bind/zones" ]; then
    cp -r /etc/bind/zones $BACKUP_DIR/$DATE/
fi

# Backup service status
systemctl status named > $BACKUP_DIR/$DATE/service-status-named.txt 2>/dev/null
systemctl status bind9 > $BACKUP_DIR/$DATE/service-status-bind9.txt 2>/dev/null

# Backup process info
ps aux | grep -E "[n]amed|bind" > $BACKUP_DIR/$DATE/process-info.txt 2>/dev/null

# Backup listening ports
netstat -tulpn | grep :53 > $BACKUP_DIR/$DATE/listening-ports.txt 2>/dev/null
ss -tulpn | grep :53 >> $BACKUP_DIR/$DATE/listening-ports.txt 2>/dev/null

# Backup test results jika diminta
if [[ $INCLUDE_TESTING =~ ^[Yy]$ ]]; then
    log "Menambahkan data testing..."
    dig @localhost localhost > $BACKUP_DIR/$DATE/dig-test-localhost.txt 2>/dev/null
    dig @localhost example.com > $BACKUP_DIR/$DATE/dig-test-example.txt 2>/dev/null 2>/dev/null
fi

# Cari domain dari konfigurasi
DOMAIN_INFO="Tidak terdeteksi"
if [ -f "/etc/bind/named.conf.local" ]; then
    DOMAIN_INFO=$(grep -oP 'zone "\K[^"]+' /etc/bind/named.conf.local | grep -v -E '^(\.|localhost|.*\.arpa)$' | head -1)
    if [ -z "$DOMAIN_INFO" ]; then
        DOMAIN_INFO="Tidak terdeteksi"
    fi
fi

# Create info file
cat > $BACKUP_DIR/$DATE/backup-info.txt << EOF
DNS Backup Information
======================
Backup Date: $(date)
Hostname: $(hostname)
Domain: $DOMAIN_INFO

Files Backed Up:
- /etc/bind/
- /etc/resolv.conf
- /etc/bind/zones/ (jika ada)
- Service status
- Process information
- Network ports
EOF

if [[ $INCLUDE_TESTING =~ ^[Yy]$ ]]; then
    echo "- Testing results" >> $BACKUP_DIR/$DATE/backup-info.txt
fi

cat >> $BACKUP_DIR/$DATE/backup-info.txt << EOF

Restore Instructions:
1. Extract: tar -xzf $BACKUP_FILE -C /
2. Restore config: cp -r /etc/bind/* /etc/bind/
3. Restore resolv.conf: cp /etc/resolv.conf /etc/resolv.conf
4. Restart service: systemctl restart named
5. Validate: named-checkconf /etc/bind/named.conf.local
EOF

# Create archive
log "Membuat archive backup..."
tar -czf $BACKUP_DIR/$BACKUP_FILE -C $BACKUP_DIR/$DATE . >/dev/null 2>&1

if [ $? -eq 0 ]; then
    log "✅ Backup berhasil dibuat: $BACKUP_DIR/$BACKUP_FILE"
else
    error "❌ Gagal membuat backup archive"
    exit 1
fi

# Verify archive
log "Memverifikasi archive..."
if tar -tzf $BACKUP_DIR/$BACKUP_FILE >/dev/null 2>&1; then
    log "✅ Archive verified successfully"
else
    error "❌ Archive verification failed"
    exit 1
fi

# Create checksum
md5sum $BACKUP_DIR/$BACKUP_FILE > $BACKUP_DIR/$BACKUP_FILE.md5
log "✅ Checksum created: $BACKUP_DIR/$BACKUP_FILE.md5"

# Cleanup temporary directory
rm -rf $BACKUP_DIR/$DATE

# Show backup info
echo ""
log "=== BACKUP INFORMATION ==="
echo "Backup File: $BACKUP_DIR/$BACKUP_FILE"
echo "Size: $(du -h $BACKUP_DIR/$BACKUP_FILE | cut -f1)"
echo "MD5: $(cat $BACKUP_DIR/$BACKUP_FILE.md5 | cut -d' ' -f1)"
echo "Domain: $DOMAIN_INFO"
echo ""

# List existing backups
log "Backup yang tersedia:"
ls -la $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | tail -5

# Cleanup old backups jika diminta
if [[ $CLEANUP_OLD =~ ^[Yy]$ ]]; then
    BACKUP_COUNT=$(ls -1 $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | wc -l)
    if [ $BACKUP_COUNT -gt 5 ]; then
        log "Membersihkan backup lama (menyimpan 5 terbaru)..."
        ls -t $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f
    fi
fi

echo ""
log "🎉 BACKUP COMPLETE"
echo ""
echo "=== RESTORE COMMANDS ==="
echo "# Extract backup:"
echo "tar -xzf $BACKUP_DIR/$BACKUP_FILE -C /"
echo ""
echo "# Restore configuration:"
echo "cp -r /etc/bind/* /etc/bind/"
echo "cp /etc/resolv.conf /etc/resolv.conf"
echo "systemctl restart named"
echo ""
echo "# Verify restore:"
echo "named-checkconf /etc/bind/named.conf.local"
echo "systemctl status named"