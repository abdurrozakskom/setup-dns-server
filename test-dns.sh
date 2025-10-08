#!/bin/bash

# Script untuk testing DNS Server

DOMAIN="example.com"
IP_ADDRESS="192.168.1.10"

echo "=== TESTING DNS SERVER ==="

echo "1. Testing forward lookup (A records):"
dig @localhost ns1.$DOMAIN +short
dig @localhost www.$DOMAIN +short
dig @localhost ftp.$DOMAIN +short

echo ""
echo "2. Testing reverse lookup (PTR records):"
dig @localhost -x $IP_ADDRESS +short

echo ""
echo "3. Testing MX record:"
dig @localhost $DOMAIN MX +short

echo ""
echo "4. Testing NS record:"
dig @localhost $DOMAIN NS +short

echo ""
echo "5. Testing CNAME records:"
dig @localhost webserver.$DOMAIN CNAME +short

echo ""
echo "6. Checking BIND9 service status:"
systemctl status bind9 --no-pager -l

echo ""
echo "7. Checking zone files syntax:"
named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN
named-checkzone 1.168.192.in-addr.arpa /etc/bind/zones/db.1.168.192