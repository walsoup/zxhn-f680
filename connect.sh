#!/usr/bin/env bash
# One-click ZTE ZXHN F680 Root Shell Launcher
# Exploits FactoryModeAuth to unlock Telnet and spawns an interactive root shell.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/tools/auto_telnet.py"

# Select Python environment
PYTHON_BIN=""
if [ -x "$DIR/.venv/bin/python3" ]; then
    PYTHON_BIN="$DIR/.venv/bin/python3"
elif [ -x "$DIR/venv/bin/python3" ]; then
    PYTHON_BIN="$DIR/venv/bin/python3"
elif [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python3" ]; then
    PYTHON_BIN="$VIRTUAL_ENV/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    echo "[-] Error: python3 not found." >&2
    exit 1
fi

# Verify dependencies
if ! "$PYTHON_BIN" -c "import requests, pexpect; from Crypto.Cipher import AES" 2>/dev/null; then
    echo "[-] Required Python dependencies not found in $PYTHON_BIN." >&2
    echo "    Please install them via:" >&2
    echo "      python3 -m venv .venv" >&2
    echo "      source .venv/bin/activate" >&2
    echo "      pip install -r requirements.txt" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT" "$@"
