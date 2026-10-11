# ZTE ZXHN F680 — Internal Diagnostic CLI & Engineering Commands

Reference guide to undocumented ZTE internal engineering tools extracted from the F680 firmware dump: `sendcmd`, `wlandiagcli`, `setmac`, and private `iwpriv` commands.

---

## 1. `sendcmd` — ZTE Middleware IPC Control Tool

`sendcmd` sends IPC debug messages via Unix domain sockets in `/var/tmp/` directly to ZTE middleware daemons (such as `cspd` on socket `1`).

### Syntax
```sh
sendcmd <AppID> <Module> <Command> [Arguments...]
```
* On this firmware, `sendcmd 1` targets `cspd`.

---

### Wireless Diagnostics (`wlan_mgr`)

| Command | Description |
| :--- | :--- |
| `sendcmd 1 wlan_mgr show pcidev` | Displays detected PCI Wi-Fi chips, bus IDs, and driver bindings. |
| `sendcmd 1 wlan_mgr show cfghistory` | Dumps runtime configuration change logs. |
| `sendcmd 1 wlan_mgr show dataforward` | Inspects data forwarding queues and bridge drop counters. |
| `sendcmd 1 wlan_mgr show wlandb` | Dumps the in-memory wireless state database. |
| `sendcmd 1 wlan_mgr show ssidinfo` | Dumps all configured SSIDs, authentication modes, and radio mappings. |
| `sendcmd 1 wlan_mgr show stainfo 1` | **Lists connected 5 GHz clients** (MAC, RSSI, MCS rate, uptime). |
| `sendcmd 1 wlan_mgr show stainfo 0` | Lists connected 2.4 GHz clients. |
| `sendcmd 1 wlan_mgr show channelinfo 1` | Displays 5 GHz channel list, noise floor, and DFS status. |
| `sendcmd 1 wlan_mgr show noise 1` | Dumps RF noise floor for Card 1. |
| `sendcmd 1 wlan_mgr show assochistory 1` | **Dumps association & handshake failure logs** for `apcli0`. |
| `sendcmd 1 wlan_mgr show currenttemp 1` | **Reports chip temperature** of the MT7615E in °C. |
| `sendcmd 1 wlan_mgr show currenttemp 0` | Reports chip temperature of the MT7603E in °C. |
| `sendcmd 1 wlan_mgr show pkgcount` | Global packet RX/TX counters per wireless interface. |

---

### DHCP & Network Inspection

| Command | Description |
| :--- | :--- |
| `sendcmd 1 dhcps srvinfo` | Shows running DHCP server status and IP pool allocation. |
| `sendcmd 1 dhcp6s show6s` | Shows DHCPv6 server state and delegated prefixes. |
| `sendcmd 1 dhcp4c start` | Manually restarts the DHCP client on WAN interfaces. |

---

### Configuration Database Inspection (`DB`)

The router maintains an in-memory database managed by `cspd`.

| Command | Description |
| :--- | :--- |
| `sendcmd 1 DB p DevInfo` | Dumps hardware version, serial, and firmware info. |
| `sendcmd 1 DB p User` | **Dumps web login accounts and privilege levels.** |
| `sendcmd 1 DB p Wlan` | Dumps all wireless profiles and credentials. |
| `sendcmd 1 DB p LanHost` | Dumps active LAN clients table. |
| `sendcmd 1 DB p WanInfo` | Dumps all WAN connections and VLAN tags. |
| `sendcmd 1 DB save` | Commits changes made in memory back to flash configuration. |

---

## 2. `wlandiagcli` — Wi-Fi Site Survey & Health CLI

A friendly command-line wrapper built by ZTE on top of `wlan_mgr`:

```sh
# Scan surrounding 5 GHz networks (SSID, BSSID, Channel, RSSI)
wlandiagcli scan 1

# Scan surrounding 2.4 GHz networks
wlandiagcli scan 0

# Show current operational channels and radio summary
wlandiagcli show basicinfo

# Inspect client association history (Crucial when debugging apcli0 connection)
wlandiagcli show assochistory 1
```

---

## 3. `setmac` — Low-Level Hardware TagParam Manager

`setmac` reads and writes directly to **`mtd3` (`"parameter tags"` partition)**. These parameters define factory calibration, MAC addresses, and hardware serial numbers.

### Syntax
```sh
setmac <action> [<TagID>] [<HexValue>]
```
* **Action `1`:** Dumps all current TagParams on the router.
* **Action `2 <TagID>`:** Reads the specific TagParam by ID.
* **Action `3 <TagID> <Value>`:** Writes a TagParam (⚠️ Use with extreme care).

### TagParam Dictionary

| Tag Name | Description |
| :--- | :--- |
| `PONMAC` | Base factory MAC address for the ONT. |
| `MAC1` – `MAC8` | Interface MAC addresses assigned to LAN, WAN, and Wi-Fi. |
| `GPONSN` | GPON Serial Number (12 alphanumeric chars, e.g. `ZTEG01234567`). |
| `GPONPWD` | GPON PLOAM registration password. |
| `ADMINNAME` | Web GUI SuperAdmin username (default: `support`). |
| `ADMINPASSWD` | Web GUI SuperAdmin factory password. |
| `USERPASSWD` | Standard Web GUI user password. |
| `PSKKEY1` – `PSKKEY8` | Factory pre-shared Wi-Fi keys for SSIDs 1 through 8. |
| `WLANCALIBRATION` | Raw RF power calibration and factory tuning matrix. |
| `SOFTVER` | Shipped software version string. |

---

## 4. MediaTek Private IOCTL (`iwpriv`) Commands

These private driver commands are passed directly to `wlan0` (2.4G), `wlan4` (5G), and `apcli0` (Repeater):

### Repeater Client (`apcli0`)
```sh
# Enable/Disable repeater client
iwpriv apcli0 set ApCliEnable=0
iwpriv apcli0 set ApCliEnable=1

# Set authentication and cipher
iwpriv apcli0 set ApCliAuthMode=WPA2PSK
iwpriv apcli0 set ApCliEncrypType=AES

# Set network credentials
iwpriv apcli0 set ApCliSsid="<SSID>"
iwpriv apcli0 set ApCliWPAPSK="<PASSWORD>"

# Enable/Disable MediaTek Wireless Distribution System (MWDS)
iwpriv apcli0 set ApCliMWDS=0   # 0 = Standard APs; 1 = Repeating another ZTE ONT
```

### Access Points (`wlan0` / `wlan4`)
```sh
# Tune operating channel (must match upstream AP on wlan4!)
iwpriv wlan4 set Channel=36

# Change broadcast SSID & password
iwpriv wlan4 set SSID="MyNewSSID_5G"
iwpriv wlan4 set WPAPSK="MyNewPassword"

# Adjust transmit power percentage (1 to 100)
iwpriv wlan4 set TxPower=100
iwpriv wlan0 set TxPower=100

# Inspect low-level driver stats
iwpriv wlan4 stat
iwpriv wlan4 show driverinfo
```
