#!/bin/sh
# Repeater Watchdog & Auto-Reconnect Daemon for ZTE ZXHN F680
# Runs in background on ONT to detect disconnects and restore the bridge.
#
# Usage:
#   ./scripts/repeater_watchdog.sh &
# Or run once:
#   ./scripts/repeater_watchdog.sh --once

set -u

CONFIG_FILE="/userconfig/repeater_wifi.conf"
INTERVAL="${CHECK_INTERVAL:-30}"
MAX_FAILURES=3
FAIL_COUNT=0
RUN_ONCE=0

if [ "${1:-}" = "--once" ]; then
    RUN_ONCE=1
fi

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Watchdog] $*"
}

check_and_heal() {
    # 1. Load active configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        log_msg "Warning: $CONFIG_FILE not found. Run ./scripts/setup_persistence.sh first."
        return 1
    fi
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"

    GATEWAY="${GATEWAY:-192.168.11.1}"

    # 2. Probe Gateway connectivity
    if ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        if [ "$FAIL_COUNT" -gt 0 ]; then
            log_msg "Gateway $GATEWAY restored! Repeater link healthy."
            FAIL_COUNT=0
        fi
        return 0
    fi

    FAIL_COUNT=$((FAIL_COUNT + 1))
    log_msg "Warning: Gateway $GATEWAY unreachable ($FAIL_COUNT/$MAX_FAILURES probe failures)."

    if [ "$FAIL_COUNT" -lt "$MAX_FAILURES" ]; then
        return 1
    fi

    # 3. Connection lost: trigger auto-reconnection
    log_msg "ALERT: Link down confirmed. Initiating automatic healing..."

    # Check if apcli0 is up
    ifconfig apcli0 up 2>/dev/null || true

    # Reset bridge MAC clone just in case
    APCLI_MAC=$(ifconfig apcli0 2>/dev/null | awk '/HWaddr/ {print $5}')
    if [ -n "$APCLI_MAC" ]; then
        ifconfig br0 hw ether "$APCLI_MAC" 2>/dev/null || true
    fi

    # Ensure channel matches
    if [ -n "${UPSTREAM_CHANNEL:-}" ]; then
        iwpriv wlan4 set Channel="$UPSTREAM_CHANNEL" 2>/dev/null || true
    fi

    # Bounce ApCli interface
    log_msg "Bouncing apcli0 association..."
    iwpriv apcli0 set ApCliEnable=0 2>/dev/null || true
    sleep 1
    iwpriv apcli0 set ApCliEnable=1 2>/dev/null || true

    log_msg "Waiting 6 seconds for WPA2 renegotiation..."
    sleep 6

    # Verify recovery
    if ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        log_msg "SUCCESS: Repeater bridge recovered and reconnected!"
        FAIL_COUNT=0
        return 0
    fi

    log_msg "Reconnection attempt failed. Upstream AP may be offline or channel shifted."
    FAIL_COUNT=0
    return 1
}

# Main loop
log_msg "Starting ZTE F680 Repeater Watchdog (Interval: ${INTERVAL}s)..."

while true; do
    check_and_heal || true
    if [ "$RUN_ONCE" -eq 1 ]; then
        break
    fi
    sleep "$INTERVAL"
done
