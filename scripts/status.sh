#!/bin/sh
# Real-time Status & Diagnostic Dashboard for ZTE ZXHN F680 Repeater
# Run from a root shell on the ONT.

set -u

# Terminal colors (if supported)
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

echo "=================================================================="
echo -e "${BOLD}${CYAN}      ZTE ZXHN F680 — Repeater Status Dashboard${RESET}"
echo "=================================================================="

# 1. System Info
UPTIME=$(uptime 2>/dev/null | awk -F'( |,|:)+' '{if ($7=="min") print $6" mins"; else print $6" hours, "$7" mins"}')
MEM_FREE=$(free 2>/dev/null | awk '/Mem:/ {printf "%.1f MB / %.1f MB", $4/1024, $2/1024}')
echo -e "${BOLD}System:${RESET} Uptime: ${UPTIME:-N/A} | Free RAM: ${MEM_FREE:-N/A}"

# 2. Bridge & LAN Configuration
BR0_IP=$(ifconfig br0 2>/dev/null | awk '/inet addr:/ {print $2}' | cut -d: -f2)
BR0_MAC=$(ifconfig br0 2>/dev/null | awk '/HWaddr/ {print $5}')
APCLI_MAC=$(ifconfig apcli0 2>/dev/null | awk '/HWaddr/ {print $5}')
GATEWAY=$(ip route show default 2>/dev/null | awk '/default via/ {print $3}')

echo ""
echo -e "${BOLD}[Bridge & Local Network]${RESET}"
echo "  Bridge (br0) IP:      ${BR0_IP:-None}"
echo "  Bridge (br0) MAC:     ${BR0_MAC:-None}"
echo "  Client (apcli0) MAC:  ${APCLI_MAC:-None}"

if [ -n "$BR0_MAC" ] && [ -n "$APCLI_MAC" ]; then
    if [ "$BR0_MAC" = "$APCLI_MAC" ]; then
        echo -e "  MAC Clone Status:     ${GREEN}OK (br0 matches apcli0)${RESET}"
    else
        echo -e "  MAC Clone Status:     ${RED}WARNING (br0 does not match apcli0! 3-address frames may drop)${RESET}"
    fi
fi

echo "  Active Gateway:       ${GATEWAY:-None}"

# 3. 5GHz Repeater Client (apcli0) Status
echo ""
echo -e "${BOLD}[5GHz Repeater Link (apcli0)]${RESET}"
if ifconfig apcli0 2>/dev/null | grep -q "UP"; then
    APCLI_RX=$(ifconfig apcli0 2>/dev/null | awk '/RX packets:/ {print $2}' | cut -d: -f2)
    APCLI_TX=$(ifconfig apcli0 2>/dev/null | awk '/TX packets:/ {print $2}' | cut -d: -f2)
    echo "  Interface State:      ${GREEN}UP${RESET} (RX: ${APCLI_RX:-0} pkts | TX: ${APCLI_TX:-0} pkts)"
else
    echo -e "  Interface State:      ${RED}DOWN${RESET}"
fi

# Radio Channel from wlan4
CH_5G=$(iwpriv wlan4 get Channel 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
echo "  5GHz Radio Channel:   ${CH_5G:-Unknown}"

# Check ping connectivity
echo ""
echo -e "${BOLD}[Connectivity Tests]${RESET}"
if [ -n "$GATEWAY" ] && ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
    GW_PING=$(ping -c 1 -W 2 "$GATEWAY" 2>/dev/null | awk -F/ '/rtt/ {print $5}')
    echo -e "  Gateway ($GATEWAY):    ${GREEN}Connected${RESET} (${GW_PING:-0} ms)"
else
    echo -e "  Gateway (${GATEWAY:-N/A}):    ${RED}Unreachable${RESET}"
fi

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    DNS_PING=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null | awk -F/ '/rtt/ {print $5}')
    echo -e "  Internet (8.8.8.8):   ${GREEN}Connected${RESET} (${DNS_PING:-0} ms)"
else
    echo -e "  Internet (8.8.8.8):   ${RED}No Internet Access${RESET}"
fi

# 4. Local Wi-Fi Access Points
echo ""
echo -e "${BOLD}[Local Access Points]${RESET}"
SSID_2G=$(iwpriv wlan0 get SSID 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
SSID_5G=$(iwpriv wlan4 get SSID 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
echo "  2.4 GHz AP (wlan0):   SSID: \"${SSID_2G:-Default}\""
echo "  5.0 GHz AP (wlan4):   SSID: \"${SSID_5G:-Default}\""

# 5. Connected Clients
echo ""
echo -e "${BOLD}[Active Connected Clients]${RESET}"
CLIENT_COUNT=0
if command -v ip >/dev/null 2>&1; then
    ip neigh show dev br0 2>/dev/null | grep -E "REACHABLE|STALE|DELAY" | while read -r line; do
        CLIENT_IP=$(echo "$line" | awk '{print $1}')
        CLIENT_MAC=$(echo "$line" | awk '{print $5}')
        if [ "$CLIENT_IP" != "$GATEWAY" ]; then
            echo "  Client: IP: $CLIENT_IP | MAC: $CLIENT_MAC"
            CLIENT_COUNT=$((CLIENT_COUNT + 1))
        fi
    done
fi
if [ "$CLIENT_COUNT" -eq 0 ]; then
    echo "  (No active downstream clients detected on br0)"
fi

echo "=================================================================="
