# ATTACK SHARK X3 HID Protocol Reverse-Engineering

## Goal

Reverse-engineer the ATTACK SHARK X3 USB configuration protocol so it can be configured from Linux without Windows/Wine.

Primary goal: set arbitrary supported DPI values, especially **1000 DPI**.

Potential future goals:

* 6 DPI stages
* polling rate
* lift-off distance
* key response time
* ripple control
* angle snap
* motion sync
* sleep/deep sleep
* possibly RGB/battery/profile settings

## Hardware / USB identity

Linux identifies the mouse as:

```text
Bus 003 Device 004: ID 1d57:fa61 Xenta USB Gaming Mouse
```

USB VID/PID:

```text
VID = 0x1d57
PID = 0xfa61
```

USB descriptors report:

```text
manufacturer: Beken
product: USB Gaming Mouse
```

This is an ATTACK SHARK X3 / Beken-family device despite the generic Xenta/Beken USB identification.

## 2.4G wireless receiver (`1d57:fa60`)

The mouse also ships with a 2.4G wireless receiver that uses the **same
protocol** (same Beken chipset, identical HID interface layout). macOS
identifies it as:

```text
2.4G Wireless Device:
  USB Vendor ID:   0x1d57
  USB Product ID:  0xfa60
  USB Product Version: 0x0113
```

`hidapi` enumeration of the receiver (`hid_enumerate(0x1d57, 0)`):

```text
PID fa60 | usage 0001/0006 | intf=0   (keyboard)
PID fa60 | usage 0001/0080 | intf=2   <-- config interface (System Control)
PID fa60 | usage 000c/0001 | intf=2
PID fa60 | usage 000a/0000 | intf=2
PID fa60 | usage 000b/0000 | intf=2
PID fa60 | usage 0001/0002 | intf=1   (mouse)
PID fa60 | usage 0001/0001 | intf=1
PID fa60 | usage 0001/0006 | intf=3   (keyboard)
```

This is byte-for-byte the same structure as the wired mouse: the configuration
interface is interface 2, usage page `0x01` / usage `0x80`, and reports
`0x04`/`0x05`/`0x06` (offsets, encodings, checksums) work exactly as documented
below. The Flutter app (`x3_device.dart` `_isX3`) and `x3ctl.py`
(`enumerate_x3`) both accept PIDs `0xfa61` (wired) and `0xfa60` (wireless).

**macOS difference vs the wired mouse (verified live, 2026-08-15):**

* The **wired** mouse (`0xfa61`) is seized by macOS: opening the config
  interface fails with `kIOReturnExclusiveAccess`, and the input interfaces
  with `kIOReturnNotPermitted` — no user app can open it on macOS.
* The **wireless receiver** (`0xfa60`) is *not* seized on its config
  interface: interface 2 (usage `0x01/0x80`) opens fine on macOS; only the
  input interfaces are blocked (`kIOReturnNotPermitted`).
* End-to-end verified: connecting to the receiver on macOS and sending report
  `0x04` (default profile) + `0x06` (polling) + `0x05` (power) all succeed.
  Feature reads still time out on this device (expected).

## HID interfaces

Python `hid.enumerate()` produced:

```text
interface: 0 path: /dev/hidraw6 usage_page: 0x1 usage: 0x6
interface: 1 path: /dev/hidraw5 usage_page: 0x1 usage: 0x2
interface: 1 path: /dev/hidraw5 usage_page: 0x1 usage: 0x1
interface: 2 path: /dev/hidraw4 usage_page: 0x1 usage: 0x80
interface: 2 path: /dev/hidraw4 usage_page: 0xc usage: 0x1
interface: 2 path: /dev/hidraw4 usage_page: 0xa usage: 0x0
interface: 2 path: /dev/hidraw4 usage_page: 0xb usage: 0x0
interface: 3 path: /dev/hidraw3 usage_page: 0x1 usage: 0x6
```

**Important:** `/dev/hidraw4` is interface 2 and is the configuration interface.

## Relevant HID descriptor

Interface 2 begins:

```text
05 01 09 80 A1 01
85 01
...
85 02
...
85 03
...
85 04 95 33 B1 01
85 05 95 0C B1 01
85 06 95 08 B1 01
85 07 95 07 B1 01
85 08 95 3A B1 01
85 09 95 3F B1 01
85 0A 95 07 B1 01
85 0B 95 07 B1 01
85 0C 95 05 B1 01
85 10 95 07 B1 01
85 A0 95 07 B1 01
85 22 95 83 B1 01
85 23 95 83 B1 01
85 24 95 07 B1 01
85 25 95 0C B1 01
85 26 95 08 B1 01
85 27 95 07 B1 01
85 28 95 83 B1 01
85 29 95 80 B1 01
85 2A 95 82 B1 01
85 2B 95 07 B1 01
85 2C 95 03 B1 01
85 2D 95 66 B1 01
85 2E 95 04 B1 01
```

These are HID Feature Reports.

Report ID `0x04` is:

```text
95 33
```

= 51-byte payload.

Including the report ID, the USB transfer is 52 bytes.

## Important discovery: configuration write

Using the Windows VM with USB passthrough + Wireshark/USBPcap, we captured an X3 configuration write.

Wireshark identified:

```text
USBHID SET_REPORT Request
```

The relevant USB setup bytes were:

```text
21 09 04 03 02 00 34 00
```

Interpretation:

```text
0x21 = HID class, host-to-device
0x09 = SET_REPORT
0x04 = report ID 4
0x03 = Feature report
0x02 0x00 = interface 2
0x34 0x00 = 52 bytes
```

This exactly matches the HID descriptor's report ID 4 / 51-byte payload.

### Captured configuration payload

The actual report data observed was:

```text
04 38 01 00 00 3f 00 00 0e 18 31 63 c7 8f
00 00 00 00 00 00 01 00 00 01 ff 00 00 00
ff 00 00 00 ff ff ff 00 00 ff ff ff 00 ff ff
40 00 ff ff ff 01 0f 85
```

The first byte is the HID report ID `0x04`.

The remaining 51 bytes are the configuration payload.

## X3 software capabilities observed

Official Windows configuration software exposes:

* 6 DPI stages
* DPI range 50–26000
* DPI increment = 50
* polling rate: 125 / 250 / 500 / 1000 Hz
* sleep time
* deep sleep time
* lift-off distance: 1mm / 2mm
* key response time slider
* ripple control boolean
* angle snap boolean
* motion sync boolean
* battery state / charging
* button settings (may be Windows-side remapping)

DPI values cannot be arbitrary integers; UI quantizes to 50-DPI increments. Therefore 1000 DPI is directly supported.

## HID feature read attempt

Python package uses newer API:

```python
hid.Device(...)
```

Opening `/dev/hidraw4` works.

However, blindly calling:

```python
get_feature_report(1, 256)
get_feature_report(2, 256)
```

returned:

```text
ioctl (GFEATURE): Connection timed out
```

Therefore do NOT blindly probe feature reports further.

The captured Windows `SET_REPORT` is the reliable source of truth.

## Next objective

Perform differential captures to identify fields in report `0x04`.

Recommended experiment:

### Capture A

Set DPI stage 1 = 750, Apply.

Record the `SET_REPORT` payload.

### Capture B

Set DPI stage 1 = 800, Apply.

Record the `SET_REPORT` payload.

### Capture C

Set DPI stage 1 = 1000, Apply.

Record the `SET_REPORT` payload.

Compare the three payloads byte-by-byte.

Expected numeric representations to look for:

```text
750  = 0x02EE
800  = 0x0320
1000 = 0x03E8
```

Possible little-endian byte patterns:

```text
750  -> EE 02
800  -> 20 03
1000 -> E8 03
```

Do not assume this representation; confirm from differential captures.

Once DPI is identified, repeat for:

* polling 125 -> 1000
* LOD 1mm -> 2mm
* ripple OFF -> ON
* angle snap OFF -> ON
* motion sync OFF -> ON
* key response minimum -> maximum

## Desired final Linux implementation

Prefer Python + `hidapi`.

The target API should eventually be something like:

```bash
python3 x3ctl.py --dpi 1000
```

or:

```bash
python3 x3ctl.py --dpi-stage 1 --dpi 1000
```

The implementation should send HID Feature Report `0x04` through interface 2 (`/dev/hidraw4`) using the discovered 52-byte configuration structure.

Potential Python API:

```python
import hid

dev = hid.Device(path=b"/dev/hidraw4")
dev.send_feature_report(config_bytes)
dev.close()
```

However, **do not send modified reports yet**. First determine:

1. field offsets
2. encoding
3. checksum/CRC
4. whether the entire 51-byte structure must be rewritten
5. whether an additional "save/apply" command is required

The captured payload ends with:

```text
01 0f 85
```

The final byte `0x85` may be a checksum/CRC/status field, but this is unconfirmed.

## Key reverse-engineering strategy

Do NOT brute-force writes.

Use Windows official software + USBPcap/Wireshark to capture controlled changes.

For every experiment:

1. Start capture.
2. Change exactly one setting.
3. Click Apply/Save.
4. Stop capture.
5. Extract the host -> device `SET_REPORT` request.
6. Compare payloads byte-by-byte.
7. Identify changed offsets.
8. Test hypotheses only after enough differential evidence exists.

The most important discovery so far is:

**The X3 configuration software writes a 51-byte HID Feature Report ID `0x04` to HID interface 2.**

That is the protocol entry point to reverse-engineer.

## WebHID investigation tool

`x3tool.html` is a self-contained WebHID page for reading/writing the device
configuration and running the differential analysis described above.

### Run it

WebHID requires a secure context (localhost/HTTPS). Python is required:

```powershell
choco install python -y            # if not already installed
py -m http.server 8000 --directory C:\Users\dad\Desktop\shark
```

Then open `http://localhost:8000/x3tool.html` in Chrome or Edge and click Connect.

### End-user config page: `x3config.html`

`x3config.html` is a friendly WebHID UI for day-to-day configuration — no hex
knowledge needed. Same server: `http://localhost:8000/x3config.html`.

* 6 DPI stages (50–26000, 50-step) with an "active stage" selector
* polling rate (125/250/500/1000 Hz), lift-off distance, ripple, angle snap,
  motion sync, sleep time, deep sleep (1–60 min), key response time
* **Apply** sends feature reports `0x04` (DPI/flags), `0x05` (sleep/key) and
  `0x06` (polling) with the correct dual checksums
* tries to read the current config on connect (times out on most units — the
  form then starts from the default/saved profile)
* save/load config as JSON; settings are remembered in the page until reload

**macOS/Chrome**: report `0x04` IS exposed (51 B) — but under **intf 3, usage
`0x0B/0x00`**, while the **System Control collection (`0x01/0x80`) is empty**.
`sendFeatureReport(0x04, …)` still fails (`Failed to write the feature report`).
Evidence strongly suggests the **firmware only accepts config writes via the
System Control (`0x01/0x80`) collection** — native `hidapi` on Windows only
worked when we opened exactly that `Col01` path — and WebHID cannot address it
(empty on macOS, missing on Windows). So WebHID writes are likely impossible on
every OS for this device.

The page logs every collection on connect, tries an **output-report fallback**,
and on failure prints the equivalent native command. **Use the native tool** —
`x3ctl.py` (hidapi) works on macOS, Windows and Linux, and the page has a
"Copy x3ctl.py command" button that generates the exact `set` invocation from
your current settings.

### Features

* Connect via WebHID (VID `0x1d57` / PID `0xfa61`); auto-detects config
  interface 2 (usage 0x01/0x80) and shows expected report-`0x04` payload size.
* **Dump collections**: lists every top-level collection WebHID actually exposes
  (usage + all feature/input/output report IDs with sizes) and reports whether
  report `0x04` is reachable. Use this when writes fail.
* Raw terminal: send/read HID feature reports (report ID editable, default `04`,
  dropdown of exposed IDs). Optionally send as an **OUTPUT report**.
  Reads may time out on this device — expected.
* Capture slots (A/B/C/...): paste one captured `SET_REPORT` payload per slot,
  auto-strip the leading report-ID byte, see byte count vs descriptor-expected.
* Diff engine: byte-by-byte comparison across slots with LE u16/u32
  interpretation — highlights exactly which offsets changed between captures.
* DPI/field scanner: finds every LE u16/u32 in the DPI range (50–26000, step 50)
  in the current payload, so the DPI field can be located quickly.
* Byte-grid editor: click a byte to select a 2-byte range, insert/delete bytes,
  live diff-vs-baseline highlight.
* **DPI writer**: stage + DPI input using the correct firmware encoding
  (byte = DPI/50 − 1, carry for stage 5) with automatic checksum.
* **Fix checksum** button (reports 0x04/0x05/0x06) and a live **Decoded report**
  panel that interprets the current payload (DPI, LOD, flags, active stage,
  sleep/key, polling).
* Slots/editor persist to localStorage; export/import JSON.

### IMPORTANT: WebHID on Windows does not see the config interface — use `x3ctl.py`

Verified on Windows: WebHID connects to the mouse but the config collection
(usage `0x01/0x80`) is **not** among the exposed collections, and sending
feature report `0x04` fails with `Failed to write the feature report` (Chrome
errors out when the report ID is not present in any exposed collection).

**However, native `hidapi` reaches it.** `python3 x3ctl.py enumerate` shows
Windows exposes interface 2 (`MI_02`) as four top-level collections; the config
one is **`Col01`** (usage `0x01/0x80`, System Control) — the first collection in
the interface-2 descriptor, and where report `0x04` lives.

On Windows, the baseline write works:

```powershell
py x3ctl.py baseline     # → OK: write succeeded
```

Feature reads still time out (`read error`), matching the Linux GFEATURE
timeout. WebHID may still expose the config interface on Linux (Chrome uses the
same stack as `hidraw`, which shows all four interfaces), but the native tool
now works on both OSes, so prefer it for the actual experiments.

## Native fallback: `x3ctl.py` (Python + hidapi)

`hidapi` enumerates every HID interface on both Windows and Linux, so it reaches
the config collection even where WebHID cannot.

```powershell
pip install hidapi        # Trezor bindings (hid.device()) — also supports: pip install hid
```

```bash
python3 x3ctl.py enumerate                    # find the config collection (Col01 on Windows)
python3 x3ctl.py baseline                     # send the captured baseline as report 0x04 (VERIFIED works)
python3 x3ctl.py read 04                      # try a feature read (times out on this device)
python3 x3ctl.py send 04 38 01 00 00 3f ...   # send an arbitrary payload
python3 x3ctl.py decode 04 <hex>              # interpret a captured payload
python3 x3ctl.py set --dpi 1000               # set DPI on the active stage (multiple of 50)
python3 x3ctl.py set --stage 1 --dpi 1000     # set DPI on a specific stage
python3 x3ctl.py set --lod 2 --ripple 1 --angle 1 --motion 1
python3 x3ctl.py set --polling 1000           # report 0x06
python3 x3ctl.py set --sleep 4.5 --deep 25 --key 6   # report 0x05
python3 x3ctl.py set --dpi 1000 --dry-run     # print payload without sending
```

`set` computes the checksum automatically. Use `--dry-run` to inspect the
payload before sending.

## Protocol decode (differential captures, 2026-08-14)

Field maps below were derived from one-at-a-time captures (DPI, flags, polling,
sleep/deep, key response). All are verified against the capture table.

### Report `0x04` — main config (51-byte payload, report ID stripped)

| offset | field                        | encoding                                           |
| ------ | ---------------------------- | -------------------------------------------------- |
| 0, 1   | header                       | `38 01` (constant)                                 |
| 2      | lift-off distance            | 0 = 1 mm, 1 = 2 mm                                 |
| 3      | ripple control               | 0/1                                                |
| 4      | constant                     | `3f`                                               |
| 5      | angle snap                   | 0/1                                                |
| 6      | motion sync                  | 0/1                                                |
| 7 + i  | DPI stage i, low byte        | `byte = (DPI/50 − 1) & 0xFF`                       |
| 15 + i | DPI stage i, high/carry byte | `(DPI/50 − 1) >> 8` (nonzero only for DPI > 12800) |
| 23     | active DPI stage             | 1-based (mode 0 → `01`, mode 3 → `04`)             |
| 49     | checksum high                | `(sum of bytes 1..48) >> 8`                        |
| 50     | checksum low                 | `(sum of bytes 0..48 + 0xC7) & 0xFF`               |

DPI value = `((low | (high << 8)) + 1) * 50`.  Each stage is a 16-bit value:
`750 → 0E 00`, `800 → 0F 00`, `1000 → 13 00`, `11600 → E7 00`,
`1250 → 18 00`, `5000 → 63 00`, `10000 → C7 00`, `18100 → 69 01`,
`20000 → 8F 01`, `26000 → 07 02`, `50 → 00 00`.

### Report `0x05` — sleep / deep sleep / key response (12-byte payload)

| offset   | field        | encoding                                                            |
| -------- | ------------ | ------------------------------------------------------------------- |
| 0, 1     | header       | `0f 01` (constant)                                                  |
| 3, 4, 10 | deep sleep   | `value = (n<<4) \| 8`, `[3]=value>>8`, `[4]=value&0xFF`, `[10]=1/2` |
| 8        | sleep time   | minutes × 2 (2 min → `04`, 4.5 → `09`, 30 → `3C`)                   |
| 9        | key response | ms ÷ 2 (6 ms → `03`, 24 → `0C`, 50 → `19`)                          |
| 11       | checksum     | `(sum of bytes 0..9 + 0xF0) & 0xFF`                                 |

Deep sleep is a stepped-linear map (verified at 5/10/13/25/27/60 min):

```text
n = deep + 48   (deep ≤ 15)        value = (n << 4) | 8
n = deep + 288  (16 ≤ deep ≤ 30)   [3] = value >> 8, [4] = value & 0xFF
n = deep + 768  (deep > 30)         [10] = 1 (≤30) or 2 (>30)
```

Examples: `5 → 03 58`, `10 → 03 a8`, `13 → 03 d8`, `25 → 13 98`, `27 → 13 b8`, `60 → 33 c8`.

The `>30` range is verified only at 60 min — the `+768` offset may need one
more capture (e.g. 45 min) to confirm.

### Report `0x06` — polling rate (9-byte payload)

| offset | field        | encoding                                                     |
| ------ | ------------ | ------------------------------------------------------------ |
| 0, 1   | header       | `09 01` (constant)                                           |
| 2      | polling code | `code = 1000 / Hz` — 1000→`01`, 500→`02`, 250→`04`, 125→`08` |
| 3      | complement   | `0xFF − code`                                                |
| 4..8   | padding      | `00`                                                         |

### Report `0x08` — button map / remapping (59 bytes total, incl. report ID)

Seven captures from the official software's button settings (one action
changed per capture). Structure verified against all seven:

| offset | field       | encoding                                                  |
| ------ | ----------- | --------------------------------------------------------- |
| 0      | report ID   | `08`                                                      |
| 1      | length      | `3b` = 59 (total packet length)                           |
| 2      | sub-command | `01` (constant)                                           |
| 3..56  | 18 rows × 3 | each row = `[code] 00 [param]` (first byte = action code) |
| 57     | tail        | `00` (constant)                                           |
| 58     | checksum    | `(sum of bytes 0..57 + 0xBC) & 0xFF`                      |

Checksum verified on all seven captures (`cf c2 e4 c1 c2 c5 c4`).

Rows and confirmed software-button mapping (from the "forward" baseline):

| row    | code  | button (official software)               |
| ------ | ----- | ---------------------------------------- |
| 1      | 02    | button 1 (left) — default left click     |
| 2      | 03    | button 2 (right) — default right click   |
| 3      | 04    | button 3 (middle) — default middle click |
| 4      | 0d    |                                          |
| 5      | 3c    |                                          |
| 6      | 0f    |                                          |
| 7      | 06    | button 4 (side) — default forward        |
| 8      | 05    | button 5 (side) — default back           |
| 9      | 3c    |                                          |
| 10..16 | 01 ×7 | default / no-change action               |
| 17     | 0a    |                                          |
| 18     | 09    |                                          |

Decoded action codes (so far):

| code | action         | code | action            |
| ---- | -------------- | ---- | ----------------- |
| 01   | default / none | 06   | forward           |
| 02   | left click     | 07   | double click      |
| 03   | right click    | 10   | fire (param `03`) |
| 04   | middle click   | 25   | browser home      |
| 05   | back           |      |                   |

Diffs (note: the official software keeps state, so later captures accumulate
earlier changes — e.g. the left/right swap from "1 → right click" is still
present in the "3 → double click" capture):

| software setting        | packet change                                   |
| ----------------------- | ----------------------------------------------- |
| button 4 → forward      | row 7 = `06` (also the baseline)                |
| button 4 → fire         | row 7 = `10 00 03` (code `10`, param byte `03`) |
| button 2 → browser home | row 2 code = `25`                               |
| button 2 → left click   | row 2 code = `02`                               |
| button 1 → right click  | row 1 = `03`, row 2 = `02` (left/right swap)    |
| button 3 → double click | row 3 code = `07`                               |
| button 5 → middle click | row 8 code = `04`                               |

### How the actions are emitted (HID output reports)

When a remapped button is pressed, the firmware replays one or more **output
HID reports** (not the config interface). Confirmed so far:

| action         | output reports                         | meaning                              |
| -------------- | -------------------------------------- | ------------------------------------ |
| browser home   | `02 23 02` then `02 00 00`             | Consumer usage `0x0223` (AC Home), press + release |

So "browser home" is a momentary press of the HID **Consumer → Home** key
(report ID `0x02`, usage `0x0223`, little-endian `23 02`), released with an
empty report `02 00 00`. The other actions presumably emit similar standard
HID reports (buttons, media keys, keyboard) — capturing those while pressing
each remapped button would confirm the full action-code → HID-usage mapping.

Open questions for 0x08:

* Rows 4, 5, 6, 9–18 are not yet tied to a physical button (codes `0d 3c 0f
  01×7 0a 09` are unlabelled).
* The `03` param byte for "fire" — macro speed / repeat count? Need a couple
  more fire/macro captures.
* Full action-code table unknown — many actions (keyboard keys, macros,
  volume, etc.) beyond the nine decoded so far.

### Open questions

* **Deep sleep > 30 min**: `+768` offset verified only at 60 min.
* All other fields are now decoded and verified (DPI, flags, LOD, active stage,
  polling, sleep, key response, checksums).

## Native fallback: `x3ctl.py` details (RESOLVED)

The original README capture was **50 bytes** after the report ID — it was
missing a single `00` padding byte. The full 51-byte structure was confirmed by
the differential capture table (52 bytes on the wire, matching the descriptor).
The tools now use the verified 51-byte payload.
