#!/bin/sh
# Safe hardware Parameter Tag viewer for ZTE ZXHN F680
# Run from a root shell on the ONT.
#
# Reads mtd3 ("parameter tags") via setmac in READ-ONLY mode.

set -u

if ! command -v setmac >/dev/null 2>&1; then
    echo "[-] Error: 'setmac' binary not found. Are you running on the ONT root shell?"
    exit 1
fi

echo "=================================================================="
echo " ZTE ZXHN F680 — Hardware Parameter Tags (Read-Only)"
echo "=================================================================="

# Dump all tags
setmac 1 2>/dev/null

echo "=================================================================="
echo " Tip: To inspect a specific TagID, run: setmac 2 <TagID>"
echo "=================================================================="
