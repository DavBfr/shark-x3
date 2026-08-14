#!/usr/bin/env python3
"""x3ctl.py — ATTACK SHARK X3 configuration tool (Python + hidapi).

Talks directly to HID interface 2 (the config interface) which the Windows
WebHID page often can NOT reach (Chrome-on-Windows only exposes some
interfaces of composite devices).  This script uses hidapi, which enumerates
every HID interface on both Windows and Linux, so it works where WebHID fails.

Required:  pip install hidapi        (package name on PyPI is "hidapi")
Optional on Linux: udev rule so /dev/hidraw4 is accessible to your user.

Commands:
  python3 x3ctl.py enumerate                      list interfaces
  python3 x3ctl.py read 04                        try GET_REPORT (feature) read
  python3 x3ctl.py baseline                       send the captured baseline config
  python3 x3ctl.py decode 04 <hex>                interpret a report payload
  python3 x3ctl.py send 04 <hex>                  send an arbitrary feature report
  python3 x3ctl.py set --dpi 1000                 set DPI on the active stage
  python3 x3ctl.py set --stage 0 --dpi 1000       set DPI on stage 0
  python3 x3ctl.py set --lod 2 --ripple 1 --angle 1 --motion 1
  python3 x3ctl.py set --active-stage 3
  python3 x3ctl.py set --polling 1000
  python3 x3ctl.py set --sleep 4.5 --deep 25 --key 6
  add --dry-run to print the payload without sending

Protocol (decoded from differential captures, 2026-08-14):
  report 0x04 (51 B): [2]=LOD(0/1) [3]=ripple [5]=angle [6]=motion
    DPI stage i: low byte at [7+i], high/carry byte at [15+i]; value = ((low|high<<8)+1)*50
    [23]=active stage (1-based)
    checksum: [49]=(sum bytes 1..48)>>8, [50]=(sum bytes 0..48 + 0xC7)&0xFF
  report 0x05 (12 B): [8]=sleep_min*2 [9]=key_ms/2 [11]=checksum=(sum[0:10]+0xF0)&0xFF
    deep sleep [3]/[4]/[10]: value=(n<<4)|8, n=deep+48(<=15)/deep+288(16-30)/deep+768(>30)
  report 0x06 (9 B): [2]=polling code = 1000/Hz (1000=01 500=02 250=04 125=08) [3]=0xFF-code
"""

import argparse
import sys

VID = 0x1D57
PID = 0xFA61
CONFIG_INTF = 2          # the configuration interface from the Linux enumeration
REPORT_ID = 0x04         # config feature report

# Baseline report-0x04 payload (report ID stripped) = row 2 of the differential
# capture table: mode 0, DPI 750/1250/2500/5000/10000/20000, polling 125,
# sleep 2, deep 10, LOD 1, key 6, ripple/angle/motion off. 51 bytes, checksum valid.
BASELINE = bytes([
    0x38, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x0e, 0x18, 0x35, 0x63, 0xc7, 0x8f,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0xff, 0x00, 0x00, 0x00,
    0xff, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0x00, 0x00, 0xff, 0xff, 0xff, 0x00, 0xff, 0xff,
    0x40, 0x00, 0xff, 0xff, 0xff, 0x01, 0x0f, 0x89,
])

# ---- report 0x04 payload field map (offsets) ----
F_LOD, F_RIPPLE, F_ANGLE, F_MOTION = 2, 3, 5, 6
F_DPI0 = 7              # stage i low byte at 7+i
F_DPI_HI = 15           # stage i high byte (carry) at 15+i
F_ACTIVE = 23           # active stage, 1-based
F_CHK_HI = 49           # checksum high byte = (sum bytes 1..48) >> 8
F_CHK04 = 50            # checksum low byte  = (sum bytes 0..48 + 0xC7) & 0xFF

# ---- report 0x05 payload field map ----
F5_DEEP_LO, F5_DEEP_HI, F5_DEEP_X = 3, 4, 10   # deep sleep, partial decode
F5_SLEEP, F5_KEY = 8, 9                         # sleep_min*2, key_ms/2
F5_CHK = 11

# ---- report 0x06 polling codes: code = 1000 / Hz ----
POLL_CODE = {1000: 0x01, 500: 0x02, 250: 0x04, 125: 0x08}


def chk04(p):
    """Two checksum bytes for report 0x04:
    [49] = (sum of bytes 1..48) >> 8   (carry of the data sum)
    [50] = (sum of bytes 0..48 + 0xC7) & 0xFF
    Returns (hi, lo)."""
    return (sum(p[1:49]) >> 8) & 0xFF, (sum(p[0:49]) + 0xC7) & 0xFF


def chk05(p):
    """Checksum byte [11] of report 0x05 = (sum of bytes 0..9) + 0xF0 mod 256."""
    return (sum(p[0:10]) + 0xF0) & 0xFF


def dpi_to_bytes(dpi):
    """Encode a DPI value (multiple of 50) into (lo, hi) bytes.
    byte = (DPI/50 - 1) & 0xFF, hi = carry (only used for stage 5 / DPI > 12800)."""
    if dpi % 50 != 0:
        sys.exit(f"DPI must be a multiple of 50 (got {dpi})")
    v = dpi // 50 - 1
    return v & 0xFF, (v >> 8) & 0xFF


def dpi_from_bytes(lo, hi=0):
    return ((lo | (hi << 8)) + 1) * 50


def build_report04(dpi=None, stage=None, lod=None, ripple=None,
                   angle=None, motion=None, active=None):
    """Build a report-0x04 payload from the baseline with the given changes.
    DPI stage i: low byte at 7+i, high/carry byte at 15+i; value = ((low|high<<8)+1)*50."""
    p = bytearray(BASELINE)
    if dpi is not None:
        if stage is None:
            stage = p[F_ACTIVE] - 1          # default to the currently active stage
        if not (0 <= stage <= 5):
            sys.exit(f"stage must be 0..5 (got {stage})")
        lo, hi = dpi_to_bytes(dpi)
        p[F_DPI0 + stage] = lo
        p[F_DPI_HI + stage] = hi
        if hi:
            print(f"note: stage {stage} DPI needs a carry byte (0x{hi:02x} at 0x{F_DPI_HI + stage:02x})")
    if lod is not None:
        p[F_LOD] = 1 if lod == 2 else 0
    if ripple is not None:
        p[F_RIPPLE] = 1 if ripple else 0
    if angle is not None:
        p[F_ANGLE] = 1 if angle else 0
    if motion is not None:
        p[F_MOTION] = 1 if motion else 0
    if active is not None:
        if not (0 <= active <= 5):
            sys.exit(f"active-stage must be 0..5 (got {active})")
        p[F_ACTIVE] = active + 1
    hi, lo = chk04(p)
    p[F_CHK_HI], p[F_CHK04] = hi, lo
    return bytes(p)


def deep_sleep_bytes(deep):
    """Encode deep sleep minutes into report-0x05 bytes [3],[4],[10].
    Stepped mapping (verified against 5/10/13/25/27/60 min captures):
      value = (n << 4) | 8   where n = deep + 48   (deep <= 15)
                                      n = deep + 288 (16 <= deep <= 30)
                                      n = deep + 768 (deep > 30, only 60 verified)
      [10] = 1 for deep <= 30, else 2."""
    deep = int(round(deep))
    if deep <= 15:
        n = deep + 48
    elif deep <= 30:
        n = deep + 288
    else:
        n = deep + 768
    v = (n << 4) | 8
    return (v >> 8) & 0xFF, v & 0xFF, (1 if deep <= 30 else 2)


def deep_from_bytes(lo, hi, x):
    v = (lo << 8) | hi
    n = v >> 4
    if n > 0x13E:      # deep > 30 (offset 768)
        return n - 768
    if n > 0x3F:       # deep 16..30 (offset 288)
        return n - 288
    return n - 48      # deep <= 15 (offset 48)


def build_report05(sleep=None, deep=None, key=None):
    """Build a report-0x05 payload."""
    p = bytearray([0x0f, 0x01, 0x00, 0x03, 0xa8, 0x00, 0x00, 0xff, 0x09, 0x03, 0x01, 0x00])
    if sleep is not None:
        p[F5_SLEEP] = int(round(sleep * 2))
    if key is not None:
        p[F5_KEY] = int(round(key / 2))
    if deep is not None:
        if not (0 < deep <= 60):
            sys.exit(f"deep must be 1..60 (got {deep})")
        p[F5_DEEP_LO], p[F5_DEEP_HI], p[F5_DEEP_X] = deep_sleep_bytes(deep)
    p[F5_CHK] = chk05(p)
    return bytes(p)


def build_report06(polling):
    if polling not in POLL_CODE:
        sys.exit(f"polling must be one of {sorted(POLL_CODE)} (got {polling})")
    code = POLL_CODE[polling]
    return bytes([0x09, 0x01, code, (0xFF - code) & 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])


def decode04(p):
    if len(p) < 51:
        return f"(report 0x04 needs 51 bytes, got {len(p)})"
    dpi = [dpi_from_bytes(p[F_DPI0 + i], p[F_DPI_HI + i]) for i in range(6)]
    hi, lo = chk04(p)
    cs_ok = p[F_CHK_HI] == hi and p[F_CHK04] == lo
    return (
        f"LOD={2 if p[F_LOD] else 1}mm ripple={p[F_RIPPLE]} angle={p[F_ANGLE]} "
        f"motion={p[F_MOTION]}\n"
        f"DPI stages: {dpi}   active stage={p[F_ACTIVE] - 1}\n"
        f"checksum[49:50]=0x{p[F_CHK_HI]:02x}{p[F_CHK04]:02x} "
        f"(computed 0x{hi:02x}{lo:02x}) {'OK' if cs_ok else 'BAD'}"
    )


def decode05(p):
    if len(p) < 12:
        return f"(report 0x05 needs 12 bytes, got {len(p)})"
    cs_ok = p[F5_CHK] == chk05(p)
    deep = deep_from_bytes(p[F5_DEEP_LO], p[F5_DEEP_HI], p[F5_DEEP_X])
    return (
        f"sleep={p[F5_SLEEP] / 2:g} min  key_response={p[F5_KEY] * 2} ms  "
        f"deep_sleep={deep} min (bytes {p[F5_DEEP_LO]:02x}{p[F5_DEEP_HI]:02x}/{p[F5_DEEP_X]:02x})\n"
        f"checksum=0x{p[F5_CHK]:02x} {'OK' if cs_ok else 'BAD'}"
    )


def decode06(p):
    if len(p) < 4:
        return f"(report 0x06 needs 9 bytes, got {len(p)})"
    code = p[2]
    poll = next((k for k, v in POLL_CODE.items() if v == code), f"?({code:02x})")
    return f"polling={poll} Hz  (code 0x{code:02x}, check 0x{p[3]:02x})"


def decode_payload(report_id, payload):
    if report_id == 0x04:
        return decode04(payload)
    if report_id == 0x05:
        return decode05(payload)
    if report_id == 0x06:
        return decode06(payload)
    return f"(no decoder for report 0x{report_id:02x})"


def load_hid():
    try:
        import hid
        return hid
    except ImportError:
        sys.exit("hidapi not installed.\n  Install one of:\n    pip install hidapi      (Trezor bindings, open via hid.device())\n    pip install hid         (apmorton bindings, open via hid.Device())")


def open_device(hid, path):
    """Open a device by path, supporting both hid python packages."""
    if hasattr(hid, "Device"):     # 'hid' package (apmorton, used in the README)
        return hid.Device(path=path)
    if hasattr(hid, "device"):     # 'hidapi' package (Trezor)
        d = hid.device()
        d.open_path(path)
        return d
    raise RuntimeError("unrecognized hid module: " + repr(hid))


def find_config(devices):
    """Pick the config collection. Windows splits interface 2 into 4 top-level
    collections (Col01..Col04); report 0x04 lives in the System Control one
    (usage page 0x01 / usage 0x80), which is the first collection in the
    interface-2 descriptor. Prefer that, then fall back to interface 2."""
    for d in devices:
        if d.get("usage_page") == 0x01 and d.get("usage") == 0x80:
            return d
    for d in devices:
        if d.get("interface_number") == CONFIG_INTF:
            return d
    return None


def cmd_enumerate(hid):
    devs = hid.enumerate(VID, PID)
    if not devs:
        sys.exit("No ATTACK SHARK X3 (1d57:fa61) found. Check it is plugged in / permissions.")
    print(f"Found {len(devs)} interface(s) for 1d57:fa61:")
    for i, d in enumerate(devs):
        mark = "  <-- CONFIG" if (d.get("interface_number") == CONFIG_INTF or
                                  (d.get("usage_page") == 0x01 and d.get("usage") == 0x80)) else ""
        print(f"  [{i}] intf={d.get('interface_number')} usage={d.get('usage_page'):#04x}/{d.get('usage'):#04x} "
              f"path={d.get('path')!r}{mark}")
    cfg = find_config(devs)
    if cfg:
        print(f"\nConfig interface path: {cfg.get('path')!r}")
    else:
        print("\nNo config interface (intf 2 / usage 0x01:0x80) found in enumeration.")


def cmd_read(hid, report_id):
    devs = hid.enumerate(VID, PID)
    cfg = find_config(devs)
    if not cfg:
        sys.exit("Config interface not found in enumeration.")
    dev = open_device(hid, cfg["path"])
    print(f"GET_REPORT feature #{report_id:02x} on {cfg['path']!r} ...")
    try:
        data = dev.get_feature_report(report_id, 256)
        print("Read OK: " + " ".join(f"{b:02x}" for b in data))
    except Exception as e:
        print(f"Read FAILED: {e}")
        print("(This device frequently times out on feature reads — expected.)")
    finally:
        dev.close()


def cmd_send(hid, report_id, payload):
    if len(payload) > 0 and payload[0] == report_id:
        # user included the report id as first byte; strip it
        payload = payload[1:]
        print(f"(stripped leading report id byte)")
    devs = hid.enumerate(VID, PID)
    cfg = find_config(devs)
    if not cfg:
        sys.exit("Config interface not found in enumeration.")
    frame = bytes([report_id]) + bytes(payload)
    print(f"SET_REPORT feature #{report_id:02x} · {len(payload)} payload bytes "
          f"({len(frame)} on wire) → {cfg['path']!r}")
    if len(payload) != 51:
        print(f"WARNING: payload is {len(payload)} bytes; descriptor says report 0x04 is 51 bytes.")
    dev = open_device(hid, cfg["path"])
    try:
        dev.send_feature_report(frame)
        print("OK: write succeeded.")
    except Exception as e:
        print(f"FAILED: {e}")
    finally:
        dev.close()


def cmd_set(hid, args):
    """Build the requested reports and send them (or --dry-run print)."""
    changed04 = args.dpi is not None or args.lod is not None or args.ripple is not None or \
                args.angle is not None or args.motion is not None or args.active_stage is not None
    changed05 = args.sleep is not None or args.deep is not None or args.key is not None
    if not changed04 and args.polling is None and not changed05:
        sys.exit("nothing to set — use e.g. --dpi 1000, --lod 2, --polling 1000, ...")

    if args.dpi_stage is not None:
        if args.stage is not None:
            sys.exit("give only one of --stage / --dpi-stage")
        args.stage = args.dpi_stage - 1

    jobs = []
    if changed04:
        jobs.append((REPORT_ID, build_report04(
            dpi=args.dpi, stage=args.stage,
            lod=args.lod, ripple=args.ripple, angle=args.angle,
            motion=args.motion, active=args.active_stage)))
    if args.polling is not None:
        jobs.append((0x06, build_report06(args.polling)))
    if changed05:
        jobs.append((0x05, build_report05(sleep=args.sleep, deep=args.deep, key=args.key)))

    for rid, payload in jobs:
        print(f"report 0x{rid:02x}: {decode_payload(rid, payload)}")
        print(f"  hex: {payload.hex(' ')}")
        if args.dry_run:
            print("  [dry-run — not sent]")
        else:
            cmd_send(hid, rid, payload)


def parse_hex(s):
    s = s.replace("0x", " ").replace(",", " ")
    toks = s.split()
    if len(toks) == 1 and len(toks[0]) > 2:
        toks = [toks[0][i:i + 2] for i in range(0, len(toks[0]), 2)]
    out = []
    for t in toks:
        if len(t) != 2:
            sys.exit(f"bad hex token: {t!r}")
        out.append(int(t, 16))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description="ATTACK SHARK X3 config tool (hidapi)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("enumerate", help="list HID interfaces of the device")

    r = sub.add_parser("read", help="try GET_REPORT (feature) read")
    r.add_argument("report_id", type=lambda s: int(s, 16), help="report id in hex, e.g. 04")

    s = sub.add_parser("send", help="send a feature report")
    s.add_argument("report_id", type=lambda s: int(s, 16), help="report id in hex, e.g. 04")
    s.add_argument("hex", nargs="?", help="payload hex (no leading report id), e.g. '38 01 00 00 3f ...'")

    b = sub.add_parser("baseline", help="send the captured baseline config payload as report 0x04")
    b.add_argument("--report-id", type=lambda s: int(s, 16), default=REPORT_ID)

    d = sub.add_parser("decode", help="interpret a captured payload")
    d.add_argument("report_id", type=lambda s: int(s, 16), help="report id in hex, e.g. 04")
    d.add_argument("hex", help="payload hex (may include leading report id byte; it is stripped)")

    st = sub.add_parser("set", help="set settings and send the config reports")
    st.add_argument("--dpi", type=int, help="DPI value (must be a multiple of 50)")
    st.add_argument("--stage", type=int, help="DPI stage 0..5 (default: currently active stage)")
    st.add_argument("--dpi-stage", type=int, help="DPI stage 1..6 (alias for --stage, 1-based)")
    st.add_argument("--lod", type=int, choices=[1, 2], help="lift-off distance in mm")
    st.add_argument("--ripple", type=int, choices=[0, 1], help="ripple control")
    st.add_argument("--angle", type=int, choices=[0, 1], help="angle snap")
    st.add_argument("--motion", type=int, choices=[0, 1], help="motion sync")
    st.add_argument("--active-stage", type=int, help="which DPI stage is active (0..5)")
    st.add_argument("--polling", type=int, choices=[125, 250, 500, 1000], help="polling rate Hz")
    st.add_argument("--sleep", type=float, help="sleep time in minutes (report 0x05)")
    st.add_argument("--deep", type=int, help="deep sleep in minutes 1..60 (report 0x05)")
    st.add_argument("--key", type=int, help="key response time in ms (report 0x05)")
    st.add_argument("--dry-run", action="store_true", help="print payloads without sending")

    args = ap.parse_args()
    hid = load_hid()

    if args.cmd == "enumerate":
        cmd_enumerate(hid)
    elif args.cmd == "read":
        cmd_read(hid, args.report_id)
    elif args.cmd == "send":
        if not args.hex:
            sys.exit("send requires a hex payload (or use 'baseline')")
        cmd_send(hid, args.report_id, parse_hex(args.hex))
    elif args.cmd == "baseline":
        cmd_send(hid, args.report_id, BASELINE)
    elif args.cmd == "decode":
        payload = parse_hex(args.hex)
        if payload and payload[0] == args.report_id:
            payload = payload[1:]
        print(decode_payload(args.report_id, payload))
    elif args.cmd == "set":
        cmd_set(hid, args)


if __name__ == "__main__":
    main()
