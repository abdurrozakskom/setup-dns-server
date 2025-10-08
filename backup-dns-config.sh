#!/bin/bash

# Script untuk backup konfigurasi DNS - FIXED VERSION

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

# Check root
if [ "$EUID" -ne 0 ]; then
    error "Script harus dijalankan sebagai root user"
    exit 1
fi

# Backup configuration
BACKUP_DIR="/root/dns-backup"
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

# Backup test results
dig @localhost localhost > $BACKUP_DIR/$DATE/dig-test-localhost.txt 2>/dev/null

# Create info file
cat > $BACKUP_DIR/$DATE/backup-info.txt << EOF
DNS Backup Information
======================
Backup Date: $(date)
Hostname: $(hostname)
Domain: example.com (edit sesuai kebutuhan)

Files Backed Up:
- /etc/bind/
- /etc/resolv.conf
- /etc/bind/zones/ (jika ada)
- Service status
- Process information
- Network ports

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

# List backup contents
log "File yang di-backup:"
tar -tzf $BACKUP_DIR/$BACKUP_FILE | head -20

# Show backup info
echo ""
log "=== BACKUP INFORMATION ==="
echo "Backup File: $BACKUP_DIR/$BACKUP_FILE"
echo "Size: $(du -h $BACKUP_DIR/$BACKUP_FILE | cut -f1)"
echo "MD5: $(cat $BACKUP_DIR/$BACKUP_FILE.md5 | cut -d' ' -f1)"
echo ""

# List existing backups
log "Backup yang tersedia:"
ls -la $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | tail -5

# Cleanup old backups (keep last 10)
BACKUP_COUNT=$(ls -1 $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | wc -l)
if [ $BACKUP_COUNT -gt 10 ]; then
    log "Membersihkan backup lama (menyimpan 10 terbaru)..."
    ls -t $BACKUP_DIR/dns_backup_*.tar.gz 2>/dev/null | tail -n +11 | xargs rm -f
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