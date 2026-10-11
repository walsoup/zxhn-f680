# ZTE ZXHN F680 — Hardware Architecture & Flash Map

Deep reverse-engineering specification of the ZTE ZXHN F680 V6.0 (`ZTEGF680V60`) hardware, RF architecture, flash partitions, and serial recovery pinout.

---

## 1. System-on-Chip (SoC) & Platform Specs

* **CPU Architecture:** ARMv7 Dual-Core Processor (32-bit little-endian, ARM EABI5).
* **RAM:** 256 MB DDR3 SDRAM.
* **Storage:** 128 MB SPI Flash (NAND / NOR).
* **Ethernet Switch:** 4x Gigabit Ethernet Ports (10/100/1000 Mbps) backed by internal switch driver `/kmodule/switch.ko` and `netdriver.ko`.
* **PON Interface:** GPON (ITU-T G.984) optical transceiver via `gpondrv.ko` and `zte_gpon.ko`.
* **USB Ports:** 2x USB 2.0 Host interfaces (`dwc2` OTG controller).
* **VoIP FXS:** 2x RJ11 Telephone ports powered by onboard DSP (`dsp_dev.ko`, `voip_codec.ko`).

---

## 2. Dual Wi-Fi Chipset Architecture

The ONT features two separate discrete MediaTek wireless chips connected via PCI:

```
                      +-----------------------------+
                      |   ARMv7 Dual-Core System   |
                      +--------------+--------------+
                                     | (PCI Bus)
            +------------------------+------------------------+
            | PCI 0000 14c37603                               | PCI 0100 14c37615
  +---------v----------+                            +---------v----------+
  | MediaTek MT7603E   |                            | MediaTek MT7615E   |
  | 2.4 GHz 802.11b/g/n|                            | 5 GHz 802.11a/n/ac |
  | 2x2 MIMO (300 Mbps)|                            | 4x4 MU-MIMO (1733) |
  +---------+----------+                            +---------+----------+
            |                                                 |
  +---------v----------+                            +---------v----------+
  | Access Point Only  |                            | AP + Repeater Port |
  | (wlan0 - wlan3)    |                            | (wlan4-7 + apcli0) |
  +--------------------+                            +--------------------+
```

### Card 0: MediaTek MT7603E (2.4 GHz)
* **PCI ID:** `0000 14c37603`
* **Driver Module:** `/kmodule/mt7603e_ap.ko`
* **Config Profile:** `/var/tmp/mt7603e.dat` (or `/etc/Wireless/RT2860AP/RT2860AP.dat`)
* **MIMO Configuration:** 2T2R (2x2 MIMO), up to 300 Mbps (40 MHz HT).
* **Operating Interfaces:** `wlan0` (Primary AP), `wlan1`–`wlan3` (Multi-SSID).
* **Limitation:** The kernel driver module was compiled strictly with `AP_MODE=1` without `APCLI_SUPPORT`. It **cannot** associate to upstream Wi-Fi networks as a client.

### Card 1: MediaTek MT7615E (5 GHz)
* **PCI ID:** `0100 14c37615`
* **Driver Module:** `/kmodule/mt7615e_ap.ko`
* **Config Profile:** `/var/tmp/mt7615e.dat`
* **MIMO Configuration:** 4T4R (4x4 MU-MIMO), up to 1733 Mbps (80 MHz VHT).
* **Advanced Features Enabled in Driver:**
  - **MU-MIMO:** `MUTxRxEnable=1`
  - **Beamforming:** Implicit (`ITxBfEn=1`) and Explicit (`ETxBfEnCond=1`).
  - **Channel Width:** 80 MHz (`VHT_BW=1`).
  - **Fast Roaming & Steering:** 802.11k (`RRMEnable=1`) and 802.11v (`WNMEnable=1`).
  - **MWDS:** 4-address frame forwarding (`ApMWDS=1`, `ApCliMWDS=1`).
* **Operating Interfaces:** `wlan4`–`wlan7` (APs) and **`apcli0`** (Repeater Client).
* **RF Synthesizer Constraint:** Because `wlan4` and `apcli0` run on the same physical radio transceiver, `wlan4` must be on the exact same channel as the upstream AP before `apcli0` can associate.

---

## 3. MTD Flash Memory Layout

The 128 MB SPI Flash layout is mapped as follows (`/proc/mtd`):

| Partition | Size | Erase Size | Name | Purpose | Mount / Device |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `mtd0` | `08000000` (128 MB) | `00020000` | `"whole flash"` | Entire raw flash chip | `/dev/mtd0` |
| `mtd1` | `00200000` (2 MB) | `00020000` | `"u-boot"` | U-Boot Bootloader & boot environment | `/dev/mtd1` |
| `mtd2` | `00400000` (4 MB) | `00020000` | `"others"` | NVRAM & system metadata | `/dev/mtd2` |
| `mtd3` | `00400000` (4 MB) | `00020000` | `"parameter tags"` | Hardware calibration, GPON SN, MACs | `/dev/mtd3` (managed via `setmac`) |
| `mtd4` | `00400000` (4 MB) | `00020000` | `"wlan"` | Wi-Fi EEPROM, MAC tables & calibration | `/dev/mtd4` |
| `mtd5` | `00800000` (8 MB) | `00020000` | `"usercfg"` | **Persistent user configuration** | Mounted at `/userconfig` (`/dev/mtdblock5`) |
| `mtd6` | `00400000` (4 MB) | `00020000` | `"middleware"` | ISP middleware & provisioning assets | `/dev/mtd6` |
| `mtd7` | `02800000` (40 MB) | `00020000` | `"kernel0"` | Primary OS Kernel image | `/dev/mtd7` |
| `mtd8` | `02800000` (40 MB) | `00020000` | `"kernel1"` | Secondary / fallback OS Kernel image | `/dev/mtd8` |
| `mtd9` | `00a00000` (10 MB) | `00020000` | `"usercustom"` | ISP customization package | Mounted at `/usercustom` |
| `mtd10`| `027e0000` (39.8 MB)| `00020000` | `"rootfs"` | Read-only SquashFS root filesystem | Mounted at `/` (Read-Only) |

> [!CAUTION]
> **Flash Safety Rules:**
> 1. The root filesystem (`/dev/mtd10`) is SquashFS and **strictly read-only**.
> 2. **Never** write to raw `/dev/mtd*` over Wi-Fi. A single corrupt block in `kernel0` or `u-boot` will brick the board without serial recovery.
> 3. All user persistence must live in `/userconfig` (`mtd5`).

---

## 4. Boot Sequence & Initialization Flow

1. **U-Boot:** Loads kernel from `mtd7` (`kernel0`) or `mtd8` (`kernel1`).
2. **Linux Kernel:** Mounts `/dev/mtd10` (SquashFS) as `/`.
3. **Init (`/etc/init.d/rcS`):**
   - Loads base patches: `insmod /kmodule/patch.ko`.
   - Reads hardware parameters: `. /etc/default/S00tagparam`.
   - Mounts `/userconfig`: `. /etc/default/S01userconfig`.
   - Runs `/etc/rcS.d/S99modules`: Loads optical driver (`gpondrv.ko`), ethernet switch (`switch.ko`), and starts networking.
   - Loads MediaTek Wi-Fi modules: `mt7603e_ap.ko` and `mt7615e_ap.ko`.
   - Starts middleware daemons: `cspd`, `httpd`, `multiapd`, `wland`.

---

## 5. Serial UART Header & Pinout (Unbricking / Debug)

If a bad configuration ever renders the router unreachable over Wi-Fi/Ethernet, a 3.3V USB-to-UART TTL adapter can be connected to the onboard 4-pin header:

* **Baud Rate:** `115200`
* **Data Bits:** `8`
* **Parity:** `None`
* **Stop Bits:** `1`
* **Flow Control:** `None`

### Pinout (4-Pin Header near CPU/Flash):

```
       [Pin 1]   [Pin 2]   [Pin 3]   [Pin 4]
        VCC       GND       TX        RX
       (3.3V)            (Router)  (Router)
       [DO NOT]   [GND]     [RX of]   [TX of]
       [CONNECT]          [Adapter] [Adapter]
```

> [!TIP]
> **Serial Connection Tip:** Connect only **GND**, **TX**, and **RX** to your USB-UART adapter. Leave the 3.3V VCC pin disconnected to avoid backpowering the board.
