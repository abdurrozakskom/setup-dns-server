# DNS Server Setup dengan BIND9 pada Debian
Script otomatis untuk mengkonfigurasi DNS Server menggunakan BIND9 pada sistem operasi Debian Linux.

---

## 📋 Prerequisites
Sistem Operasi: Debian 10/11/12
- Akses root/sudo
- Koneksi internet (untuk download packages)
- Domain name yang akan dikonfigurasi

## 🛠️ File Script
Repository ini berisi beberapa script:
- setup-dns-server.sh - Script utama untuk instalasi dan konfigurasi
- test-dns.sh - Script untuk testing konfigurasi DNS
- backup-dns-config.sh - Script untuk backup konfigurasi

---

## ⚙️ Konfigurasi
1. Edit Variabel Konfigurasi
Sebelum menjalankan script, edit variabel berikut di file setup-dns-server.sh:
```bash
DOMAIN="example.com"          # Ganti dengan domain Anda
IP_ADDRESS="192.168.1.10"     # Ganti dengan IP server Anda
REVERSE_ZONE="1.168.192"      # Ganti dengan network portion IP (balik urutan)
NAMESERVERS=("ns1.$DOMAIN" "ns2.$DOMAIN")
EMAIL="admin.$DOMAIN"
```
**Contoh:**
Jika IP server adalah 192.168.100.5 dan domain company.local:
```bash
DOMAIN="company.local"
IP_ADDRESS="192.168.100.5"
REVERSE_ZONE="100.168.192"
```
2. Buat Script Executable
```bash
chmod +x setup-dns-server.sh
chmod +x test-dns.sh
chmod +x backup-dns-config.sh
```
## 🚀 Instalasi dan Konfigurasi
Jalankan Script Utama
```bash
./setup-dns-server.sh
```
### Apa yang dilakukan script:
- Update package list sistem
- Install BIND9 dan utilities
- Backup konfigurasi original
- Buat forward zone (A records, CNAME, MX)
- Buat reverse zone (PTR records)
- Konfigurasi firewall (jika UFW aktif)
- Validasi syntax konfigurasi
- Restart service BIND9
- Update resolv.conf

## ✅ Testing Konfigurasi
Jalankan Script Testing
```bash
./test-dns.sh
```
## 💾 Backup Konfigurasi
Buat Backup
```bash
./backup-dns-config.sh
```
Backup akan disimpan di: /root/dns-backup/dns_backup_[timestamp].tar.gz

## 📁 Struktur File Konfigurasi
```bash
/etc/bind/
├── named.conf.local          # Konfigurasi zones
├── named.conf.options        # Options global
└── zones/
    ├── db.example.com        # Forward zone file
    └── db.1.168.192          # Reverse zone file
```

## 🔧 Record yang Dibuat Otomatis
### Forward Zone (A Records)
- @ (domain) → IP_ADDRESS
- ns1 → IP_ADDRESS
- ns2 → IP_ADDRESS
- www → IP_ADDRESS
- ftp → IP_ADDRESS
- mail → IP_ADDRESS
- server → IP_ADDRESS

### CNAME Records
- webserver → www
- fileserver → ftp

### MX Record
- @ MX 10 → mail.example.com

### Reverse Zone (PTR Records)
- Semua IP mengarah ke hostnames yang sesuai

## 🐛 Troubleshooting
### Check Syntax Konfigurasi
```bash
named-checkconf /etc/bind/named.conf.local
named-checkzone example.com /etc/bind/zones/db.example.com
```
### Check Logs
```bash
journalctl -u bind9 -f
tail -f /var/log/syslog | grep named
```
### Restart Service
```bash
systemctl restart bind9
systemctl status bind9
```
### Reset ke Default
```bash
# Restore dari backup
cp /etc/bind/named.conf.local.backup /etc/bind/named.conf.local
cp /etc/bind/named.conf.options.backup /etc/bind/named.conf.options
systemctl restart bind9
```






