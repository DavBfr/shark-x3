# ATTACK SHARK X3 Configuration tool

A desktop-only Flutter app that configures the X3 through the local `hid`
plugin. Single scrolling page aimed at
regular users, with plain-English explanations for every setting (tap the `?`
on any setting for more detail).

## Features

* **Connect** — finds the mouse (VID `0x1d57` / PID `0xfa61`) and opens the
  configuration interface (System Control collection, usage `0x01/0x80`) *by
  path*, which is the only way the firmware accepts config writes.
* **Sensitivity (DPI)** — 6 stages with the factory defaults and LED colors:
  `800 red · 1600 green (default active) · 2400 blue · 3200 cyan · 5000 yellow
  · 26000 purple`. Each stage has an active selector, a slider (50–26000, 50
  steps) and quick presets; the card header shows the active stage's color.
* **Mouse response** — polling rate (125/250/500/1000 Hz), lift-off distance
  (1/2 mm), ripple control, angle snap, motion sync.
* **Power & battery** — sleep time (0.5–30 min), deep sleep (1–60 min), key
  response time (1–50 ms).
* **Apply (differential)** — the mouse can't report its own settings (reads
  time out), so the app keeps the last successful apply in
  shared_preferences. The first Apply sends everything (reports `0x04` →
  `0x06` → `0x05` with correct dual checksums); afterwards only the reports
  whose settings changed are sent, with live success/partial/failure feedback.
* **Profiles** — the current setup is auto-saved (via `shared_preferences`) on
  every change and restored on launch; save/load named profiles from the
  "Profiles" menu; "Reset to defaults" restores the factory profile.
* **No read-back** — this mouse cannot report its current settings, so the
  app never tries to read it; it relies on the stored last-applied profile as
  the source of truth for what is on the mouse.

## Run it

```bash
flutter run -d linux        # needs libhidapi-hidraw.so.0
flutter run -d windows      # download hidapi.dll during build
flutter run -d macos
```

Tests: `flutter test` (protocol round-trips + checksums verified against the
captured baseline and the README tables).

## How it maps to the protocol

* `lib/src/x3_protocol.dart` — pure-Dart codec ported 1:1 from `x3ctl.py`
  (build `0x04`/`0x05`/`0x06`, dual checksums, DPI + deep-sleep encoding,
  decoders). No Flutter dependency, fully unit-tested.
* `lib/src/x3_profile.dart` — profile model, factory defaults + LED colors,
  JSON round-tripping, value clamping.
* `lib/src/x3_device.dart` — wraps the `hid` plugin: enumerate → pick the
  config collection → `openPath()` → send feature reports. A best-effort read
  is kept only for diagnostics — this mouse can't report its settings.
* `lib/src/x3_prefs.dart` — `shared_preferences` persistence.
* `lib/src/x3_settings_page.dart` + `lib/src/widgets/*` — the UI.

## hid plugin extension

The stock `hid` plugin opens devices by VID/PID, which cannot target the X3's
config interface. The local `hid/` package was extended with:

* `HidDevice.path` and `HidDevice.interfaceNumber` (now populated from
  enumeration), and
* `HidDevice.openPath(String path)` — wraps the already-bound
  `hid_open_path` FFI call, so the exact config collection can be opened.

Rebuild the plugin's macOS pod if the deployment-target warning appears after
updating `hid/macos/hid.podspec` (target was raised from 10.11 to 10.13).
