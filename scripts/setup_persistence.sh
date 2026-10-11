#!/bin/sh
# Setup boot-time persistence for ZTE ZXHN F680 5GHz Bridge Repeater.
# Run from a root shell on the ONT.
#
# All persistent files are saved strictly in /userconfig (/dev/mtdblock5).
# NEVER writes to raw /dev/mtd* partitions.

set -eu

if [ "$#" -lt 3 ]; then
    echo "Usage:"
    echo "  $0 <SSID> <PASSWORD> <CHANNEL> [GATEWAY]"
    echo ""
    echo "Example:"
    echo "  $0 'MyHome5G' 'SecretPassword' 36 192.168.11.1"
    exit 1
fi

SSID="$1"
PSK="$2"
CHANNEL="$3"
GATEWAY="${4:-192.168.11.1}"
MWDS="${MWDS:-0}"

if [ ! -d "/userconfig" ]; then
    echo "[-] Error: /userconfig directory not found. Are you on the ONT root shell?"
    exit 1
fi

echo "[*] Creating persistent configuration in /userconfig..."

# Create secure configuration file
CONFIG_FILE="/userconfig/repeater_wifi.conf"
cat <<EOF > "$CONFIG_FILE"
# ZTE F680 Repeater Configuration
UPSTREAM_SSID="$SSID"
UPSTREAM_PSK="$PSK"
UPSTREAM_CHANNEL="$CHANNEL"
GATEWAY="$GATEWAY"
MWDS="$MWDS"
EOF
chmod 600 "$CONFIG_FILE"
echo "[+] Saved credentials to $CONFIG_FILE"

# Create launcher script in /userconfig
RUNNER_FILE="/userconfig/run_repeater.sh"
cat <<'EOF' > "$RUNNER_FILE"
#!/bin/sh
if [ -f /userconfig/repeater_wifi.conf ]; then
    . /userconfig/repeater_wifi.conf
    
    # Wait for MediaTek wireless drivers to initialize
    sleep 8
    
    ifconfig apcli0 0.0.0.0 2>/dev/null || true
    ip route del "$GATEWAY" dev apcli0 2>/dev/null || true
    ip neigh flush all 2>/dev/null || true
    
    ifconfig apcli0 up 2>/dev/null || true
    APCLI_MAC=$(ifconfig apcli0 2>/dev/null | awk '/HWaddr/ {print $5}')
    if [ -z "$APCLI_MAC" ]; then
        APCLI_MAC=$(ip link show apcli0 2>/dev/null | awk '/ether/ {print $2}')
    fi
    
    iwpriv wlan4 set Channel="$UPSTREAM_CHANNEL"
    brctl addif br0 apcli0 2>/dev/null || true
    
    if [ -n "$APCLI_MAC" ]; then
        ifconfig br0 hw ether "$APCLI_MAC"
    fi
    ip route replace default via "$GATEWAY" dev br0 2>/dev/null || true
    
    ebtables -F 2>/dev/null || true
    ebtables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -I FORWARD -j ACCEPT 2>/dev/null || true
    
    iwpriv apcli0 set ApCliMWDS="$MWDS"
    iwpriv apcli0 set ApCliEnable=0
    iwpriv apcli0 set ApCliAuthMode=WPA2PSK
    iwpriv apcli0 set ApCliEncrypType=AES
    iwpriv apcli0 set ApCliSsid="$UPSTREAM_SSID"
    iwpriv apcli0 set ApCliWPAPSK="$UPSTREAM_PSK"
    iwpriv apcli0 set ApCliEnable=1
fi
EOF
chmod +x "$RUNNER_FILE"
echo "[+] Created persistent runner: $RUNNER_FILE"

# Append or create autorun hook in /userconfig/autorun.sh
AUTORUN="/userconfig/autorun.sh"
if [ ! -f "$AUTORUN" ]; then
    cat <<'EOF' > "$AUTORUN"
#!/bin/sh
# ZTE F680 boot initialization
EOF
    chmod +x "$AUTORUN"
fi

if ! grep -q "/userconfig/run_repeater.sh" "$AUTORUN"; then
    echo "/userconfig/run_repeater.sh &" >> "$AUTORUN"
    echo "[+] Hooked runner into $AUTORUN"
else
    echo "[*] Hook already present in $AUTORUN"
fi

echo ""
echo "[+] Persistence configuration completed!"
echo "    The repeater bridge will automatically start on ONT boot."
