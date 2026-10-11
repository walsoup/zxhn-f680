#!/bin/sh
# Bridge a ZXHN F680's 5 GHz client (apcli0) to an upstream AP.
# Run from a root shell on the ONT. Does not touch wlan0/wlan4 admin state
# beyond setting the shared 5 GHz channel.

set -eu

: "${UPSTREAM_SSID:?set UPSTREAM_SSID}"
: "${UPSTREAM_PSK:?set UPSTREAM_PSK}"
: "${UPSTREAM_CHANNEL:?set UPSTREAM_CHANNEL}"

GATEWAY="${GATEWAY:-192.168.11.1}"
: "${APCLI_MAC:?set APCLI_MAC to the apcli0 hardware address}"
MWDS="${MWDS:-1}"

ifconfig apcli0 0.0.0.0
ip route del "$GATEWAY" dev apcli0 2>/dev/null || true
ip route del 192.168.11.0/24 dev apcli0 2>/dev/null || true
ip neigh flush all

ifconfig apcli0 up
iwpriv wlan4 set Channel="$UPSTREAM_CHANNEL"
brctl addif br0 apcli0 2>/dev/null || true

ifconfig br0 hw ether "$APCLI_MAC"
ip route replace default via "$GATEWAY" dev br0

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

echo "Waiting 5 seconds for the WPA2 handshake..."
sleep 5

ping -c 3 "$GATEWAY"
ping -c 3 8.8.8.8
