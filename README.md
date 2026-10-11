# ZTE ZXHN F680 5 GHz Wireless Bridge & Repeater Toolkit

Hardware notes, reverse-engineering findings, and automated tooling for converting an ISP-locked **ZTE ZXHN F680 V6.0** (`ZTEGF680V60`) GPON ONT into a high-performance, portable **5 GHz wireless bridge repeater**.

Tested on Orange Morocco firmware `ZTEGF680606MA` (boot `V6.0.20P10N1`).

---

## Hardware Overview

The F680 features two separate Wi-Fi chipsets on distinct PCI buses:

| Card | PCI ID | Chipset | Interfaces | Repeater Capable? |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `0000 14c37603` | MediaTek MT7603E (2.4 GHz 802.11b/g/n 2x2) | `wlan0`–`wlan3` | ❌ **No.** The driver (`mt7603e_ap.ko`) is compiled in AP-only mode without client/ApCli support. |
| **1** | `0100 14c37615` | MediaTek MT7615E (5 GHz 802.11a/n/ac 4x4 MU-MIMO) | `wlan4`–`wlan7`, `apcli0` | ✅ **Yes.** Supports wireless client association, bridging, and 4-address frame repeating via `apcli0`. |

> [!NOTE]
> **Shared RF Synthesizer:** `wlan4` (the local 5 GHz AP) and `apcli0` (the repeater client) share one radio synthesizer. The channel of `wlan4` must be explicitly tuned to the upstream AP's operating channel before `apcli0` associates.

---

## Repository Structure

```
zxhn-f680/
├── connect.sh                   # One-click host script: unlocks backdoor & opens root shell
├── requirements.txt             # Host Python dependencies (requests, pexpect, pycryptodome)
├── LICENSE                      # MIT License
├── README.md                    # Main documentation & getting started guide
├── docs/                        # Deep reverse-engineering architecture guides
│   ├── HARDWARE_ARCHITECTURE.md # Flash MTD map, dual PCI radios, serial UART pinout
│   ├── INTERNAL_COMMANDS.md     # sendcmd, wlandiagcli, setmac TagParams, iwpriv IOCTLs
│   ├── EASYMESH_NETSPHERE.md    # Multi-AP mesh architecture, multiapd, MWDS 4-address mode
│   ├── THINKLUA_AND_WEB_ARCHITECTURE.md # ThinkLua framework, unauthenticated endpoints, RAM overlays
│   └── CONFIG_ENCRYPTION_AND_SECRETS.md # config.bin AES key derivation, payload types, secrets
├── scripts/
│   ├── bridge.sh                # Associates apcli0, clones MAC, bridges to br0
│   ├── scan.sh                  # Site-survey helper (wlandiagcli scan wrapper)
│   ├── status.sh                # Real-time health dashboard (signals, MAC clone check, clients)
│   ├── repeater_watchdog.sh     # Auto-healing daemon that detects dropouts & reconnects
│   ├── setup_local_wifi.sh      # Customizes local broadcast SSIDs/passwords on wlan0 & wlan4
│   ├── disable_tr069.sh         # Neutralizes ISP CWMP remote management / ACS overrides
│   ├── setup_persistence.sh     # Boot persistence installer (/userconfig/autorun.sh)
│   ├── setmac_helper.sh         # Safe read-only viewer for hardware TagParams
│   └── unhide_web_scanner.sh    # RAM overlay (mount -o bind) to expose ThinkLua 5GHz scan GUI
└── tools/
    ├── auto_telnet.py           # Automated exploit & interactive pexpect telnet launcher
    └── zte_factorymode.py       # Standalone implementation of ZTE FactoryMode handshake
```

---

## Quick Start Guide

### 1. Host Setup (Your PC)

Install dependencies for the host connection tools:

```bash
# Optional: create a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install requirements (requests, pexpect, pycryptodome)
pip install -r requirements.txt

# Ensure standard telnet client is installed
sudo apt install telnet   # Debian/Ubuntu
# or: brew install telnet # macOS
```

### 2. Configure ONT LAN IP (Prevent Subnet Collision)

Orange Morocco configures every ONT default gateway to `192.168.11.1` with DHCP Server enabled. If you bridge this ONT to another Orange network on that same address, the device will loopback ping traffic to itself and cause severe ARP conflicts.

1. Connect your PC to the F680's Wi-Fi or LAN port.
2. Open the Web GUI at `http://192.168.11.1`.
3. Log in with admin credentials (e.g. `support` / `<AdminPassword>`).
4. Navigate to **Local Network** → **LAN** → **IPv4**:
   - Change **LAN IP Address** to `192.168.11.200`.
   - Set **DHCP Server** to **Off**.
   - Click **Apply**.

> [!WARNING]
> **Do not change LAN IP via `ifconfig br0` in a root shell!** The internal middleware daemon `cspd` does not track raw `ifconfig` IP changes, causing `httpd` to reject incoming HTTP requests with `400 Bad Request`. Always change LAN IP via the Web GUI.

---

### 3. Open Root Shell (`connect.sh`)

Standard Telnet on port 23 drops into **Mode 0 (Restricted Shell)**, where basic commands (`cp`, `df`, `mount`, and file redirection `>`) fail with `/bin/sh: Access Denied.`

Use `./connect.sh` to trigger the `webFac` HTTP challenge-response backdoor, retrieve dynamic root credentials, and drop directly into an unrestricted **Mode 2 (Dev/Root)** `#` prompt:

```bash
./connect.sh 192.168.11.200
```
*(If you haven't changed the IP yet, run `./connect.sh 192.168.11.1`)*

---

### 4. Scan & Connect to Upstream Wi-Fi (On Router)

Once inside the ONT root shell (`/ # `):

#### A. Run Site Survey
```sh
# Scan surrounding 5 GHz networks (SSID, BSSID, Channel, RSSI)
wlandiagcli scan 1
# or use helper:
./scripts/scan.sh
```

#### B. Bridge `apcli0` to Upstream Wi-Fi
Run `scripts/bridge.sh` with your network details:

```sh
./scripts/bridge.sh "YourWiFiSSID" "YourWiFiPassword" 36 192.168.11.1
```

Or pass via environment variables:
```sh
UPSTREAM_SSID="YourWiFiSSID" \
UPSTREAM_PSK="YourWiFiPassword" \
UPSTREAM_CHANNEL=36 \
GATEWAY=192.168.11.1 \
./scripts/bridge.sh
```

The script will automatically:
1. Clear stale routes and flush the neighbor table (`ip neigh flush all`).
2. Auto-detect `apcli0`'s hardware MAC address.
3. Tune `wlan4` to the upstream channel (e.g. `36`).
4. Add `apcli0` into the bridge (`brctl addif br0 apcli0`).
5. Clone `apcli0`'s MAC onto `br0` (required for 802.11 3-address mode).
6. Enable bridge packet forwarding (`ebtables` & `iptables`).
7. Associate `apcli0` with WPA2-PSK/AES.
8. Wait for the 4-way WPA2 handshake to complete.
9. Verify connectivity with gateway and internet ping tests.

---

## Technical Deep Dive & Key Learnings

### 1. The 802.11 3-Address Frame Trap
Standard Wi-Fi access points operate in **3-address frame mode**. When `apcli0` completes the WPA2 handshake, the upstream AP only accepts ethernet frames whose source MAC matches `apcli0`.

If `br0` retains its factory MAC (e.g. `00:11:22:33:44:55`), the upstream AP silently drops all outgoing LAN/bridge traffic. **Cloning `apcli0`'s MAC onto `br0` is mandatory**:
```sh
ifconfig br0 hw ether <APCLI_MAC>
```

### 2. MWDS (4-Address Mode)
- **Normal Wi-Fi Networks:** Set `MWDS=0`. This uses standard 3-address repeating compatible with any standard Wi-Fi router.
- **ZTE-to-ZTE Repeating:** Set `MWDS=1` (`ApCliMWDS=1`). The firmware natively supports MediaTek Wireless Distribution System (MWDS) 4-address frame forwarding when repeating another ZTE ONT.

### 3. WPA2 4-Way Handshake Timing
The MediaTek driver takes **~3.2 seconds** to negotiate encryption keys (`TX_EAPOL_PAIR_MSG_4` at 867 Mbps). Firing network commands immediately after setting `ApCliEnable=1` causes instant ping failure. Always enforce `sleep 5` before sending traffic.

### 4. BusyBox Firmware Quirks
- **No `arp` binary:** `/bin/arp` does not exist on this device. Always use `/bin/ip neigh` (`ip neigh show`, `ip neigh flush all`).
- **`ping -I` interface limitation:** BusyBox `ping -I` requires an IPv4 address (`-I 192.168.11.200`), not an interface name (`-I apcli0` produces `bad interface address`).
- **No bridge IP on `apcli0`:** Inside the bridge, `apcli0` must have no IP assigned (`0.0.0.0`).

### 5. Flash Partition Safety Rule
- **NEVER touch `/dev/mtd*`:** Root filesystem is read-only SquashFS. Writing raw MTD blocks over Wi-Fi risks bricking the device without serial UART recovery.
- **Persistent Storage:** All persistent user files belong strictly within `/userconfig` (`/dev/mtdblock5`).
- **Web UI Overlays:** Modify runtime UI files exclusively via RAM overlays (`tmpfs` or `mount -o bind`).

---

## Web UI Site Survey Unhiding

The firmware already contains native 5 GHz station scan pages:
- `/home/httpd/webmodules/modules/wlan_sta_scanap5g_t.lp`
- `/home/httpd/webmodules/modules/wlan_sta_scanap5g_js.lp`
- `/home/httpd/webmodules/modules/wlan_sta_wlan_profile_lua.lua`

Orange Morocco hides these pages in `/home/httpd/webmodules/config/dmenu_modifier.lua` (`CountryCode=198`).

To unhide this page in the Web GUI without altering flash memory, run:
```sh
./scripts/unhide_web_scanner.sh
```
This bind-mounts a modified copy in RAM (`/var/tmp/dmenu_modifier.lua`). After running, navigate to **Local Network** → **WLAN** in your browser.

---

## Boot Persistence

To make the repeater bridge survive reboots:
```sh
./scripts/setup_persistence.sh "YourWiFiSSID" "YourWiFiPassword" 36 192.168.11.1
```
This writes the configuration to `/userconfig/repeater_wifi.conf` and hooks into `/userconfig/autorun.sh`.

---

## Diagnostics & Troubleshooting

```sh
# View current operational radio channels
wlandiagcli show basicinfo

# Inspect client association history & failure codes
wlandiagcli show assochistory 1

# Check RX/TX packet counters on repeater interface
ifconfig apcli0

# Verify bridge interface membership
brctl show

# Inspect routing table and neighbor cache
ip route show
ip neigh show
```

---

## What Stays Out of This Repository

This repository contains clean, reusable tools and reverse-engineering documentation. It deliberately excludes:
- Proprietary ISP firmware dumps
- Decrypted configuration files (`config.bin` / `config.xml`)
- Personal serial numbers (GPON SN), MAC addresses, and passwords

---

## License

MIT. See [LICENSE](LICENSE) for details.
