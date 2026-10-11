#!/bin/sh
# Bridge ZTE ZXHN F680 5 GHz client (apcli0) to an upstream Wi-Fi network.
# Run from a root shell on the ONT.
#
# Usage:
#   ./scripts/bridge.sh <SSID> <PASSWORD> <CHANNEL> [GATEWAY]
# Or via environment variables:
#   UPSTREAM_SSID="MyWiFi" UPSTREAM_PSK="Secret123" UPSTREAM_CHANNEL=36 ./scripts/bridge.sh

set -eu

# Support positional parameters or environment variables
UPSTREAM_SSID="${1:-${UPSTREAM_SSID:-}}"
UPSTREAM_PSK="${2:-${UPSTREAM_PSK:-}}"
UPSTREAM_CHANNEL="${3:-${UPSTREAM_CHANNEL:-}}"
GATEWAY="${4:-${GATEWAY:-192.168.11.1}}"
MWDS="${MWDS:-0}"  # 0 = Standard APs; 1 = Repeating another ZTE ONT (4-address mode)

if [ -z "$UPSTREAM_SSID" ] || [ -z "$UPSTREAM_PSK" ] || [ -z "$UPSTREAM_CHANNEL" ]; then
    echo "================================================================="
    echo "  ZTE ZXHN F680 5GHz Bridge Repeater Setup"
    echo "================================================================="
    echo "Usage:"
    echo "  $0 <SSID> <PASSWORD> <CHANNEL> [GATEWAY]"
    echo ""
    echo "Examples:"
    echo "  $0 'MyHomeWiFi' 'SecretKey123' 36"
    echo "  $0 'Office_5G' 'OfficePass' 44 192.168.1.1"
    echo ""
    echo "Environment Variables (optional overrides):"
    echo "  MWDS=1         Enable 4-address mode (for ZTE-to-ZTE repeating)"
    echo "  APCLI_MAC=...  Manual MAC override for apcli0"
    echo "================================================================="
    exit 1
fi

echo "[*] Initializing 5GHz repeater for SSID: '$UPSTREAM_SSID' (Channel: $UPSTREAM_CHANNEL)..."

# 1. Clean up stale routes, IPs, and neighbor table
echo "[*] Cleaning up stale routes and neighbor cache..."
ifconfig apcli0 0.0.0.0 2>/dev/null || true
ip route del "$GATEWAY" dev apcli0 2>/dev/null || true
ip route del 192.168.11.0/24 dev apcli0 2>/dev/null || true
ip neigh flush all 2>/dev/null || true

# 2. Bring up apcli0 and auto-detect MAC if not specified
ifconfig apcli0 up 2>/dev/null || true

if [ -z "${APCLI_MAC:-}" ]; then
    APCLI_MAC=$(ifconfig apcli0 2>/dev/null | awk '/HWaddr/ {print $5}')
    if [ -z "$APCLI_MAC" ]; then
        APCLI_MAC=$(ip link show apcli0 2>/dev/null | awk '/ether/ {print $2}')
    fi
fi

if [ -z "$APCLI_MAC" ]; then
    echo "[-] Error: Could not determine apcli0 MAC address. Set APCLI_MAC manually."
    exit 1
fi
echo "[+] Detected apcli0 MAC address: $APCLI_MAC"

# 3. Match 5GHz RF synthesizer channel on wlan4 (shared with apcli0)
echo "[*] Tuning 5GHz radio (wlan4) to channel $UPSTREAM_CHANNEL..."
iwpriv wlan4 set Channel="$UPSTREAM_CHANNEL"

# 4. Attach apcli0 to the bridge
echo "[*] Adding apcli0 to bridge br0..."
brctl addif br0 apcli0 2>/dev/null || true

# 5. CRITICAL: Clone apcli0 MAC onto br0
# In 802.11 3-address mode, upstream AP only accepts frames matching authenticated station MAC
echo "[*] Cloning apcli0 MAC ($APCLI_MAC) onto br0..."
ifconfig br0 hw ether "$APCLI_MAC"
ip route replace default via "$GATEWAY" dev br0

# 6. Ensure bridge forwarding is not blocked
ebtables -F 2>/dev/null || true
ebtables -P FORWARD ACCEPT 2>/dev/null || true
iptables -I FORWARD -j ACCEPT 2>/dev/null || true

# 7. Configure WPA2-PSK and associate client interface
echo "[*] Configuring WPA2 credentials (MWDS=$MWDS)..."
iwpriv apcli0 set ApCliMWDS="$MWDS"
iwpriv apcli0 set ApCliEnable=0
iwpriv apcli0 set ApCliAuthMode=WPA2PSK
iwpriv apcli0 set ApCliEncrypType=AES
iwpriv apcli0 set ApCliSsid="$UPSTREAM_SSID"
iwpriv apcli0 set ApCliWPAPSK="$UPSTREAM_PSK"
iwpriv apcli0 set ApCliEnable=1

# 8. Wait for WPA2 4-way handshake (takes ~3.2 seconds)
echo "[*] Waiting 5 seconds for WPA2 4-way handshake to complete..."
sleep 5

# 9. Verify connection
echo "[*] Testing connectivity..."
GATEWAY_OK=0
INTERNET_OK=0

if ping -c 3 -W 2 "$GATEWAY" >/dev/null 2>&1; then
    GATEWAY_OK=1
    echo "[+] Gateway ($GATEWAY) reachable!"
else
    echo "[-] Warning: Gateway ($GATEWAY) did not respond to ping."
fi

if ping -c 3 -W 2 8.8.8.8 >/dev/null 2>&1; then
    INTERNET_OK=1
    echo "[+] Internet (8.8.8.8) reachable!"
else
    echo "[-] Warning: Internet (8.8.8.8) ping failed."
fi

echo "================================================================="
if [ "$GATEWAY_OK" -eq 1 ] || [ "$INTERNET_OK" -eq 1 ]; then
    echo "  >>> WIRELESS BRIDGE ACTIVE & RUNNING <<<"
    echo "  Clients connecting to this ONT's Wi-Fi or LAN ports"
    echo "  are now bridged to '$UPSTREAM_SSID'."
else
    echo "  Association failed or handshake incomplete."
    echo "  Check diagnostics with: wlandiagcli show assochistory 1"
fi
echo "================================================================="
