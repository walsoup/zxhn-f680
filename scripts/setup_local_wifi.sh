#!/bin/sh
# Configure local broadcast Wi-Fi (SSID & Password) on ZTE ZXHN F680
# Run from a root shell on the ONT.
#
# Usage:
#   ./scripts/setup_local_wifi.sh <SSID> <PASSWORD> [BAND]
#   BAND: "both" (default), "2.4", or "5"

set -eu

if [ "$#" -lt 2 ]; then
    echo "Usage:"
    echo "  $0 <SSID> <PASSWORD> [BAND]"
    echo ""
    echo "Bands: both (default), 2.4, 5"
    echo "Examples:"
    echo "  $0 'Repeater_WiFi' 'SecretPass123' both"
    echo "  $0 'Repeater_5G' 'SecretPass123' 5"
    exit 1
fi

SSID="$1"
PSK="$2"
BAND="${3:-both}"

apply_2g() {
    echo "[*] Updating 2.4 GHz AP (wlan0)..."
    iwpriv wlan0 set AuthMode=WPA2PSK
    iwpriv wlan0 set EncrypType=AES
    iwpriv wlan0 set SSID="$SSID"
    iwpriv wlan0 set WPAPSK="$PSK"
    echo "[+] 2.4 GHz AP updated: SSID='$SSID'"
}

apply_5g() {
    SSID_5G="$SSID"
    # If applying to both, optionally append _5G if not already present
    if [ "$BAND" = "both" ] && ! echo "$SSID" | grep -iq "5G"; then
        SSID_5G="${SSID}_5G"
    fi

    echo "[*] Updating 5.0 GHz AP (wlan4)..."
    iwpriv wlan4 set AuthMode=WPA2PSK
    iwpriv wlan4 set EncrypType=AES
    iwpriv wlan4 set SSID="$SSID_5G"
    iwpriv wlan4 set WPAPSK="$PSK"
    echo "[+] 5.0 GHz AP updated: SSID='$SSID_5G'"
}

case "$BAND" in
    2|2.4|2g|2G)
        apply_2g
        ;;
    5|5.0|5g|5G)
        apply_5g
        ;;
    both|all|*)
        apply_2g
        apply_5g
        ;;
esac

echo ""
echo "[+] Local Wi-Fi configuration applied successfully!"
