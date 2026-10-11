# ZTE ZXHN F680 — ThinkLua Web Framework Architecture

Reverse engineering of ZTE's proprietary web stack (**ThinkLua**), route dispatching, authorization bypass via `hidden_table_conf.lua`, and RAM overlay techniques.

---

## 1. Web Architecture Overview

ZTE ONTs run a custom embedded Lua web server built on top of **Lua 5.1** and **CGILua**:

* **Web Root Directory:** `/home/httpd`
* **Core Framework:** `/home/httpd/thinklua`
* **Page Templates (`.lp`):** HTML mixed with Lua tags (`<% ... %>`).
* **Backend Data Logic (`.lua`):** Communicates with `cspd` middleware via internal CMAPI (`cmapi.getinst`, `cmapi.setinst`).
* **Menu Tree:** Declared dynamically in `/home/httpd/webmodules/config/dmenu_modifier.lua`.

---

## 2. Route Dispatching & The Unauthenticated Backdoor

Route definitions live in `/home/httpd/thinklua/page_mgr/hidden_table_conf.lua`:

```lua
local hiddenTable = {
    {basicType="view", urlPath="http2httpsRedirectPage.lp", fileName="../template/http2httpsRedirectPage.lp", needLogin=false},
    {basicType="data", urlPath="switchlang_entry", fileName="../view_assemble/lang_switch_data.lua", needLogin=false},
    {basicType="data", urlPath="captcha_data", fileName="../user_mgr/login_captcha_lua.lua", needLogin=false},
    -- Registered endpoints with needLogin=false bypass the login form completely!
}
```

### Key Route Parameters:
* `basicType="view"`: Serves an HTML/Lua template page (`.lp`).
* `basicType="data"`: Serves an AJAX JSON/XML data endpoint (`.lua`).
* `needLogin=false`: **Allows unauthenticated access.** Any browser can hit this endpoint without providing administrator credentials!
* `right=nil`: Bypasses privilege tier validation (Tier 1 SuperAdmin vs Tier 2 User).

---

## 3. How ISPs Hide Features (`dmenu_modifier.lua`)

The firmware contains extensive features that are deliberately suppressed by ISP operator profiles.

In `/home/httpd/webmodules/config/dmenu_modifier.lua`:
```lua
-- The 5 GHz Wi-Fi site survey page is hidden for Orange Morocco (CountryCode 198):
dmenu:newPage({
    id="wlanStaScanAP",
    name=lang.WlanScan_001,
    right=3,  -- Right=3 is hidden/installer mode
    areas={
        {area="wlan_sta_scanap2g_t.lp", backendFile="wlan_sta_wlan_profile_lua.lua"},
        {area="wlan_sta_scanap5g_t.lp", backendFile="wlan_sta_wlan_profile_lua.lua"},
    }
})
```

Because `right=3` exceeds normal user and admin tiers, the menu is never rendered in the navigation tree.

---

## 4. Modifying the Web GUI via Volatile RAM Overlays

Because `/home/httpd` resides on the read-only SquashFS partition (`/dev/mtd10`), runtime modifications must be performed in RAM using `mount -o bind`:

```sh
# 1. Copy the target file to RAM (/var/tmp)
cp /home/httpd/webmodules/config/dmenu_modifier.lua /var/tmp/dmenu_modifier.lua

# 2. Edit permissions or unhide menus in RAM
sed -i 's/right=3/right=1/g' /var/tmp/dmenu_modifier.lua

# 3. Bind-mount over the read-only rootfs
mount -o bind /var/tmp/dmenu_modifier.lua /home/httpd/webmodules/config/dmenu_modifier.lua
```

### Why this is 100% safe:
1. No flash erase cycles or writes to MTD.
2. Completely volatile: A reboot safely reverts all modifications to the pristine factory state.
3. Zero risk of bricking.

---

## 5. Serving a Custom Web Repeater Portal

By adding a custom entry to `/home/httpd/thinklua/page_mgr/hidden_table_conf.lua` with `needLogin=false`, you can mount a lightweight, mobile-friendly captive portal (e.g. `http://192.168.11.200/repeater.lp`) where coworkers can connect their phone, scan 5 GHz networks via AJAX, enter the Wi-Fi password, and bridge the router without needing Telnet access.
