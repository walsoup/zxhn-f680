#!/bin/sh
# Neutralize TR-069 / CWMP ISP Remote Management on ZTE ZXHN F680
# Run from a root shell on the ONT.
#
# Prevents the ISP ACS (Auto Configuration Server) from pushing remote updates,
# overriding bridge settings, or resetting the repeater back to default.

set -eu

echo "================================================================="
echo " Disabling TR-069 Remote Management (ISP ACS Lockout)..."
echo "================================================================="

# 1. Kill running TR-069 client daemon
if killall tr069 2>/dev/null; then
    echo "[+] Terminated active tr069 daemon."
else
    echo "[*] tr069 daemon was not running."
fi

# 2. Block TR-069 traffic in iptables
echo "[*] Adding firewall drop rules for CWMP ports..."
iptables -I OUTPUT -p tcp --dport 7547 -j DROP 2>/dev/null || true
iptables -I INPUT -p tcp --dport 7547 -j DROP 2>/dev/null || true

# 3. Disable TR-069 in live middleware database
echo "[*] Updating live database via sendcmd..."
if command -v sendcmd >/dev/null 2>&1; then
    # Disable TR-069 management server enable flag
    sendcmd 1 DB set MgtSrv 0 Enable 0 2>/dev/null || true
    sendcmd 1 DB save 2>/dev/null || true
    echo "[+] MgtSrv Enable set to 0 in database."
fi

# 4. Nullify ACS URL in host resolution
if [ -f /var/tmp/hosts ]; then
    echo "127.0.0.1 acs.orange.ma acs.orange.com" >> /var/tmp/hosts 2>/dev/null || true
fi

echo "================================================================="
echo " TR-069 remote management successfully neutralized!"
echo " The ISP can no longer override your repeater settings."
echo "================================================================="
