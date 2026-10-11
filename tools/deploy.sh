#!/usr/bin/env bash
# Deploy scripts from host PC to ZTE ZXHN F680 ONT via transient HTTP server.
#
# Usage:
#   ./tools/deploy.sh [ROUTER_IP] [PORT]
# Example:
#   ./tools/deploy.sh 192.168.11.200

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER_IP="${1:-192.168.11.1}"
PORT="${2:-8000}"

# Auto-detect host IP on the route to router
HOST_IP=$(ip route get "$ROUTER_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')

if [ -z "$HOST_IP" ]; then
    echo "[-] Error: Could not determine host IP address towards $ROUTER_IP." >&2
    echo "    Make sure you are connected to the router's Wi-Fi or LAN port." >&2
    exit 1
fi

echo "=================================================================="
echo " ZTE ZXHN F680 — Script Deployment Server"
echo "=================================================================="
echo "  Host IP:   $HOST_IP"
echo "  Router IP: $ROUTER_IP"
echo "  HTTP Port: $PORT"
echo "=================================================================="

# Start transient Python HTTP server serving the scripts directory
echo "[*] Launching local HTTP server for scripts/ on port $PORT..."
python3 -m http.server "$PORT" --directory "$DIR/scripts" >/dev/null 2>&1 &
HTTP_PID=$!

cleanup() {
    echo ""
    echo "[*] Shutting down deployment HTTP server (PID $HTTP_PID)..."
    kill "$HTTP_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 1

echo "[+] HTTP Server active at http://$HOST_IP:$PORT/"
echo ""
echo "------------------------------------------------------------------"
echo " Run this command in your ONT root shell (/ #) to download all scripts:"
echo "------------------------------------------------------------------"
echo ""
cat <<EOF
mkdir -p /tmp/scripts && cd /tmp/scripts && \\
for s in bridge.sh scan.sh status.sh repeater_watchdog.sh setup_local_wifi.sh disable_tr069.sh setup_persistence.sh setmac_helper.sh unhide_web_scanner.sh; do \\
  wget "http://$HOST_IP:$PORT/\$s" -O "/tmp/scripts/\$s" && chmod +x "/tmp/scripts/\$s"; \\
done && ls -la /tmp/scripts
EOF
echo ""
echo "------------------------------------------------------------------"
echo " Press Ctrl+C when finished to stop the server."
echo "------------------------------------------------------------------"

# Wait for user to finish
wait "$HTTP_PID" 2>/dev/null || true
