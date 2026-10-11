# ZTE ZXHN F680 as a 5 GHz wireless bridge

Notes and a shell script for using a **ZTE ZXHN F680 V6.0** (`ZTEGF680V60`) as a portable 5 GHz bridge repeater.

Tested on Orange Morocco firmware `ZTEGF680606MA` (boot `V6.0.20P10N1`). The 2.4 GHz radio cannot join another network. The 5 GHz radio can.

## Hardware

| Radio | Chipset | Interfaces | Role |
| :--- | :--- | :--- | :--- |
| 2.4 GHz | MediaTek MT7603E | `wlan0`–`wlan3` | Access point only. The shipped driver has no client mode. |
| 5 GHz | MediaTek MT7615E | `wlan4`–`wlan7`, `apcli0` | Access point plus repeater client on `apcli0`. |

`apcli0` is the interface that associates to an upstream access point. `wlan4` and `apcli0` share one radio, so `wlan4` has to sit on the upstream channel before the client connects.

## Before you bridge

Orange Morocco ships these ONTs at `192.168.11.1` with DHCP on. If the upstream router uses that same address, the bridge will talk to itself.

1. In the web UI, open **Local Network → LAN → IPv4**.
2. Set the LAN address to `192.168.11.200`.
3. Turn the DHCP server off.
4. Apply.

Change that address in the web UI. Setting `br0` with `ifconfig` leaves `cspd` on the old address, and `httpd` then answers `400 Bad Request`.

## Connect

From a root shell on the ONT:

```sh
wlandiagcli scan 1
```

That lists 5 GHz networks with SSID, BSSID, channel, and RSSI. Then:

```sh
UPSTREAM_SSID="your-ssid" \
UPSTREAM_PSK="your-password" \
UPSTREAM_CHANNEL=36 \
APCLI_MAC="xx:xx:xx:xx:xx:xx" \
GATEWAY=192.168.11.1 \
./scripts/bridge.sh
```

`APCLI_MAC` is the hardware address of `apcli0` (`ifconfig apcli0`). The upstream AP only accepts LAN traffic from that station address, so the script copies it onto `br0`.

What the script does:

1. Clears any address and stale routes on `apcli0`.
2. Brings `apcli0` up, sets `wlan4` to the upstream channel, and adds `apcli0` to `br0`.
3. Copies the `apcli0` MAC onto `br0`. In 3-address mode the upstream AP only accepts frames from the station MAC that completed the handshake.
4. Accepts bridge forwarding.
5. Sets WPA2-PSK/AES and enables the client. `ApCliMWDS=1` is for repeating another ZTE. Use `MWDS=0` for a normal access point.
6. Waits 5 seconds. The 4-way handshake takes about 3 seconds; pinging sooner fails.

BusyBox on this firmware has no `arp` binary (`ip neigh` instead). `ping -I` wants an IPv4 address, not an interface name. Inside the bridge, `apcli0` stays at `0.0.0.0`.

## What this repo does not include

No firmware image, no decrypted config, no web or Wi-Fi passwords, and no factory-mode login helper. Those stay on the device you already administer.

## License

MIT. See [LICENSE](LICENSE).
