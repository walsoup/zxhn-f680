#!/bin/sh
# Site survey helper for ZTE ZXHN F680
# Run from a root shell on the ONT.
#
# Usage:
#   ./scripts/scan.sh       # Scans 5 GHz (Card 1 / MT7615E - Repeater capable)
#   ./scripts/scan.sh 2.4   # Scans 2.4 GHz (Card 0 / MT7603E - AP only)

BAND="${1:-5}"

case "$BAND" in
    2|2.4|2g|2G|2ghz|2GHz|0)
        CARD=0
        LABEL="2.4 GHz (MT7603E)"
        ;;
    5|5.0|5g|5G|5ghz|5GHz|1)
        CARD=1
        LABEL="5 GHz (MT7615E - ApCli Supported)"
        ;;
    *)
        echo "[-] Error: Invalid band '$BAND'. Specify '2.4' or '5'." >&2
        exit 1
        ;;
esac

echo "================================================================="
echo " Scanning $LABEL Wi-Fi Networks..."
echo "================================================================="

if command -v wlandiagcli >/dev/null 2>&1; then
    wlandiagcli scan "$CARD"
    echo ""
    echo "[*] Tip: Note the SSID and Channel of your target network."
    echo "    Then bridge with: ./scripts/bridge.sh <SSID> <PASSWORD> <CHANNEL>"
else
    echo "[-] Error: 'wlandiagcli' command not found. Are you on the ONT root shell?"
    exit 1
fi
