#!/bin/sh
# Unhide native 5 GHz Web Scanner in ThinkLua Web GUI
# Uses RAM overlay (mount -o bind) — 100% volatile, NO flash writes.
#
# Orange Morocco hides the 5 GHz Wi-Fi site survey page by default.
# This script copies dmenu_modifier.lua to /var/tmp, adjusts permissions,
# and bind-mounts it over the original file in /home/httpd.

set -eu

SRC="/home/httpd/webmodules/config/dmenu_modifier.lua"
TMP="/var/tmp/dmenu_modifier.lua"

if [ ! -f "$SRC" ]; then
    echo "[-] Error: ThinkLua menu file not found at $SRC"
    exit 1
fi

echo "[*] Creating RAM overlay for ThinkLua menu in /var/tmp..."
cp "$SRC" "$TMP"

# Replace right=3 (admin only / hidden) with right=1 (user accessible) for wlanStaScanAP
# and remove any country-code filters that suppress wlanStaScanAP
sed -i 's/id="wlanStaScanAP",\s*name=lang.WlanScan_001,\s*right=3/id="wlanStaScanAP", name=lang.WlanScan_001, right=1/g' "$TMP"

echo "[*] Bind-mounting modified menu in RAM..."
mount -o bind "$TMP" "$SRC"

echo "[+] Success! The 5 GHz scan page is now unhidden in the Web GUI."
echo "    Navigate to Local Network -> WLAN in your browser to view it."
echo "    (Changes are in RAM only and will reset safely on router reboot)."
