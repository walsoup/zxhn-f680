# ZTE ZXHN F680 — Configuration Encryption & Secrets Recovery

Technical guide to ZTE's proprietary AES configuration container (`config.bin`), payload types, key derivation algorithms, and secret extraction.

---

## 1. Overview: `config.bin` vs `db_user_cfg.xml`

ZTE ONTs store persistent user settings in an XML document named `db_user_cfg.xml` (located in flash at `/userconfig/cfg/db_user_cfg.xml`).

When exported via the Web GUI (**Management & Diagnosis** → **System Management** → **User Configuration Management**), the router packages and encrypts the XML file into a binary container named `config.bin`.

---

## 2. Binary Container Structure

The `config.bin` file consists of a **128-byte header** followed by encrypted payload data:

```
+------------------------------------------------------------------+
| ZTE Header (128 Bytes)                                           |
|  - Magic Signature (e.g. "ZXHN F680" or "ZTE")                   |
|  - Header Version / Payload Type (e.g. Type 4: AES-CBC)          |
|  - Uncompressed Length & CRC32 Checksum                          |
+------------------------------------------------------------------+
| Encrypted & Compressed Payload (AES-CBC + Zlib Deflate)          |
+------------------------------------------------------------------+
```

---

## 3. Cryptographic Key Derivation (Payload Type 4)

On modern firmware releases (`ZTEGF680606MA`), ZTE uses **Payload Type 4** encryption, where the AES cipher keys are uniquely bound to the specific physical device:

* **Cipher:** AES-128-CBC or AES-256-CBC.
* **Initialization Vector (IV):**
  ```
  ZTE%FN$GponNJ025
  ```
* **Key Derivation Material:**
  The AES key is constructed by concatenating a known vendor prefix with the router's hardware identifiers:
  1. **Base MAC Address:** In lowercase without colons (e.g. `001122334455`).
  2. **GPON Serial Number:** From barcode / label (e.g. `ZTEG01234567`).

---

## 4. Recoverable Secrets from Decrypted Config

Once decrypted to standard XML, `config.xml` exposes all internal credentials in plain text:

### 1. Web GUI SuperAdmin Credentials
```xml
<Row>
    <DM name="Username" val="support"/>
    <DM name="Password" val="<SuperAdminPassword>"/>
    <DM name="Right" val="1"/>
</Row>
```

### 2. Wi-Fi Pre-Shared Keys
```xml
<Row>
    <DM name="ESSID" val="Home_5G_Network"/>
    <DM name="KeyPassphrase" val="<SecretWiFiPassword>"/>
    <DM name="BeaconType" val="11i"/>
</Row>
```

### 3. TR-069 Remote Management (ACS)
```xml
<Row>
    <DM name="URL" val="http://acs.operator.example:7547"/>
    <DM name="Username" val="tr069_user"/>
    <DM name="Password" val="..."/>
</Row>
```

### 4. VoIP / SIP Telecom Credentials
Contains SIP proxy servers, subscriber phone numbers, and SIP authentication passwords.

---

## 5. Safe Configuration Re-encryption Workflow

To modify settings (such as permanent Telnet, custom LAN IP, or bridge settings) without root shell access:
1. Download `config.bin` from the Web GUI.
2. Decrypt using the device MAC and GPON SN with `zte-config-utility`.
3. Edit the desired XML parameters in `config.xml`.
4. Re-encrypt with the same key, IV, and header signature.
5. Upload back via the Web GUI and reboot.
