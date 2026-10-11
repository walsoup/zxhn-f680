# ZTE ZXHN F680 — EasyMesh & NetSphere Architecture

Reverse engineering of ZTE's proprietary Multi-AP mesh architecture (**NetSphere**) and the underlying `multiapd` (IEEE 1905.1) daemon discovered in the F680 firmware.

---

## 1. Overview: What is ZTE NetSphere?

ZTE **NetSphere** is the operator-grade implementation of the **Wi-Fi Alliance EasyMesh (Multi-AP)** standard found on modern ZTE ZXHN ONTs. It coordinates seamless client roaming (802.11k/v), unified SSID synchronization, band steering, and wireless backhaul forwarding between multiple access points.

In the F680 firmware dump, this subsystem is orchestrated by:
* Daemon: `/bin/multiapd` (IEEE 1905.1 protocol controller)
* ThinkLua Web Backend: `/home/httpd/webmodules/modules/wlan_NetSphere_Mode_lua.lua`
* Configuration Objects: `OBJ_NETSPHERE_MAP_ID`, `OBJ_MAP_MASTER_ID`, `OBJ_TEMP_DOMAIN_BS`

---

## 2. Operating Modes (`multiapd`)

The `multiapd` binary supports two distinct operational roles:

```
                  +--------------------------------+
                  | Upstream Root ONT / Gateway   |
                  | Mode: MESH.CONTROLLER          |
                  +---------------+----------------+
                                  |
              Wireless Backhaul   | (4-Address Frames via MWDS)
             or Ethernet (Cat5e)  |
                                  |
                  +---------------v----------------+
                  | ZTE ZXHN F680 (Repeater)       |
                  | Mode: MESH.AGENT               |
                  +--------------------------------+
```

### 1. `MESH.CONTROLLER` (Multi-AP Controller)
* Runs on the primary Internet gateway ONT.
* Maintains the global topology table.
* Pushes unified SSID and security credentials to all agents.
* Coordinates Band Steering (`EnBandSteer=1`) based on client RSSI thresholds (`BsRssiLmt24G`, `BsRssiLmt5G`).

### 2. `MESH.AGENT` (Multi-AP Agent)
* Runs on extender nodes and repeaters.
* Automatically establishes wireless backhaul over 5 GHz using `apcli0`.
* Synchronizes its broadcast APs (`wlan0` 2.4G and `wlan4` 5G) to match the controller.
* Reports connected station RSSI values back to the controller for intelligent roaming.

---

## 3. The Role of MWDS (MediaTek Wireless Distribution System)

In standard 802.11 wireless connections, client frames use **3-address headers** (`Source`, `Destination`, `BSSID`). Standard APs reject frames with a source MAC that does not match the authenticated client station.

To overcome this without MAC cloning, MediaTek implemented **MWDS (4-address mode)**:
* In `dump/var/tmp/mt7615e.dat`, the driver defaults to:
  ```ini
  ApMWDS=1;1;1;1;1;1;1;1
  ApCliMWDS=1
  ```
* When `ApCliMWDS=1`, the 5 GHz client encapsulates full 4-address 802.11 frames (`Source`, `Destination`, `Transmitter`, `Receiver`).
* **ZTE-to-ZTE Repeating:** If your upstream router is another ZTE ONT with EasyMesh enabled, leaving `ApCliMWDS=1` allows every downstream device (laptops, phones) to keep their genuine MAC addresses across the bridge without MAC cloning on `br0`.
* **Standard 3rd-Party Repeating:** If connecting to a normal home router (e.g. Asus, TP-Link, Netgear), MWDS must be set to `0` (`iwpriv apcli0 set ApCliMWDS=0`), and `br0` must clone `apcli0`'s MAC.

---

## 4. Enabling NetSphere / EasyMesh Mode

In the ThinkLua management database:

```lua
-- CMAPI object parameters for OBJ_NETSPHERE_MAP_ID
local PARA = {
    "Mode",    -- 0: Disable, 1: Controller, 2: Agent
    "Enable"   -- 1: Enabled
}
```

To configure via the live database in root shell:
```sh
# Set EasyMesh Mode to Agent (2)
sendcmd 1 DB set OBJ_NETSPHERE_MAP_ID 0 Mode 2
sendcmd 1 DB set OBJ_NETSPHERE_MAP_ID 0 Enable 1

# Commit to flash
sendcmd 1 DB save
```
