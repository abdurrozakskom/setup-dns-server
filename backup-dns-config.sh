#!/bin/bash

# Script untuk backup konfigurasi DNS

BACKUP_DIR="/root/dns-backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Membuat backup konfigurasi DNS..."

mkdir -p $BACKUP_DIR/$DATE

# Backup semua file konfigurasi
cp -r /etc/bind $BACKUP_DIR/$DATE/
cp /etc/resolv.conf $BACKUP_DIR/$DATE/

# Buat archive
tar -czf $BACKUP_DIR/dns_backup_$DATE.tar.gz -C $BACKUP_DIR/$DATE .

echo "Backup selesai: $BACKUP_DIR/dns_backup_$DATE.tar.gz"

# Hapus folder temporary
rm -rf $BACKUP_DIR/$DATE

# Tampilkan info backup
echo "File yang di-backup:"
tar -tzf $BACKUP_DIR/dns_backup_$DATE.tar.gz