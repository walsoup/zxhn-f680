#!/bin/sh
# Real-time Status & Diagnostic Dashboard for ZTE ZXHN F680 Repeater
# Run from a root shell on the ONT (BusyBox ash compatible).

set -u

# Terminal colors (if supported)
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

printf "%s\n" "=================================================================="
printf "%b\n" "${BOLD}${CYAN}      ZTE ZXHN F680 — Repeater Status Dashboard${RESET}"
printf "%s\n" "=================================================================="

# 1. System Info
UPTIME=$(uptime 2>/dev/null | awk -F'( |,|:)+' '{if ($7=="min") print $6" mins"; else print $6" hours, "$7" mins"}')
MEM_FREE=$(free 2>/dev/null | awk '/Mem:/ {printf "%.1f MB / %.1f MB", $4/1024, $2/1024}')
printf "%b\n" "${BOLD}System:${RESET} Uptime: ${UPTIME:-N/A} | Free RAM: ${MEM_FREE:-N/A}"

# 2. Bridge & LAN Configuration
BR0_IP=$(ifconfig br0 2>/dev/null | awk '/inet addr:/ {print $2}' | cut -d: -f2)
BR0_MAC=$(ifconfig br0 2>/dev/null | awk '/HWaddr/ {print $5}')
APCLI_MAC=$(ifconfig apcli0 2>/dev/null | awk '/HWaddr/ {print $5}')
GATEWAY=$(ip route show default 2>/dev/null | awk '/default via/ {print $3}')

printf "\n"
printf "%b\n" "${BOLD}[Bridge & Local Network]${RESET}"
printf "  Bridge (br0) IP:      %s\n" "${BR0_IP:-None}"
printf "  Bridge (br0) MAC:     %s\n" "${BR0_MAC:-None}"
printf "  Client (apcli0) MAC:  %s\n" "${APCLI_MAC:-None}"

if [ -n "$BR0_MAC" ] && [ -n "$APCLI_MAC" ]; then
    if [ "$BR0_MAC" = "$APCLI_MAC" ]; then
        printf "%b\n" "  MAC Clone Status:     ${GREEN}OK (br0 matches apcli0)${RESET}"
    else
        printf "%b\n" "  MAC Clone Status:     ${RED}WARNING (br0 does not match apcli0! 3-address frames may drop)${RESET}"
    fi
fi

printf "  Active Gateway:       %s\n" "${GATEWAY:-None}"

# 3. 5GHz Repeater Client (apcli0) Status
printf "\n"
printf "%b\n" "${BOLD}[5GHz Repeater Link (apcli0)]${RESET}"
if ifconfig apcli0 2>/dev/null | grep -q "UP"; then
    APCLI_RX=$(ifconfig apcli0 2>/dev/null | awk '/RX packets:/ {print $2}' | cut -d: -f2)
    APCLI_TX=$(ifconfig apcli0 2>/dev/null | awk '/TX packets:/ {print $2}' | cut -d: -f2)
    printf "%b\n" "  Interface State:      ${GREEN}UP${RESET} (RX: ${APCLI_RX:-0} pkts | TX: ${APCLI_TX:-0} pkts)"
else
    printf "%b\n" "  Interface State:      ${RED}DOWN${RESET}"
fi

# Radio Channel from wlan4
CH_5G=$(iwpriv wlan4 get Channel 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
printf "  5GHz Radio Channel:   %s\n" "${CH_5G:-Unknown}"

# Check ping connectivity
printf "\n"
printf "%b\n" "${BOLD}[Connectivity Tests]${RESET}"
if [ -n "$GATEWAY" ] && ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
    GW_PING=$(ping -c 1 -W 2 "$GATEWAY" 2>/dev/null | awk -F/ '/rtt/ {print $5}')
    printf "%b\n" "  Gateway ($GATEWAY):    ${GREEN}Connected${RESET} (${GW_PING:-0} ms)"
else
    printf "%b\n" "  Gateway (${GATEWAY:-N/A}):    ${RED}Unreachable${RESET}"
fi

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    DNS_PING=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null | awk -F/ '/rtt/ {print $5}')
    printf "%b\n" "  Internet (8.8.8.8):   ${GREEN}Connected${RESET} (${DNS_PING:-0} ms)"
else
    printf "%b\n" "  Internet (8.8.8.8):   ${RED}No Internet Access${RESET}"
fi

# 4. Local Wi-Fi Access Points
printf "\n"
printf "%b\n" "${BOLD}[Local Access Points]${RESET}"
SSID_2G=$(iwpriv wlan0 get SSID 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
SSID_5G=$(iwpriv wlan4 get SSID 2>/dev/null | awk -F: '{print $2}' | tr -d ' \r\n')
printf "  2.4 GHz AP (wlan0):   SSID: \"%s\"\n" "${SSID_2G:-Default}"
printf "  5.0 GHz AP (wlan4):   SSID: \"%s\"\n" "${SSID_5G:-Default}"

# 5. Connected Clients (Avoid subshell variable loss)
printf "\n"
printf "%b\n" "${BOLD}[Active Connected Clients]${RESET}"
if command -v ip >/dev/null 2>&1; then
    NEIGH_DATA=$(ip neigh show dev br0 2>/dev/null | grep -E "REACHABLE|STALE|DELAY" || true)
    if [ -n "$NEIGH_DATA" ]; then
        echo "$NEIGH_DATA" | awk -v gw="${GATEWAY:-192.168.11.1}" '
            BEGIN { count = 0 }
            ($1 != gw) {
                printf "  Client: IP: %-15s | MAC: %s\n", $1, $5
                count++
            }
            END {
                if (count == 0) {
                    print "  (No active downstream clients detected on br0)"
                }
            }
        '
    else
        printf "  (No active downstream clients detected on br0)\n"
    fi
else
    printf "  ('ip' command not found)\n"
fi

printf "%s\n" "=================================================================="
