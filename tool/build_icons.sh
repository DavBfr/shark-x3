#!/usr/bin/env bash
#
# build_icons.sh — Build platform app icons + a Flutter PNG asset
# from assets/icon/shark_x3.svg.
#
# Requires:
#   * rsvg-convert   (brew install librsvg)
#   * ImageMagick    (brew install imagemagick)  -> `magick` (IM7) or `convert`
#
# Outputs:
#   macOS   macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16..1024}.png
#   Windows windows/runner/resources/app_icon.ico  (multi-resolution 16–256)
#   Linux   linux/runner/resources/app_icon.png     (256x256)
#   Flutter assets/icon.png                          (1024x1024)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SVG="$ROOT/assets/icon/shark_x3.svg"

# --- Helpers ---------------------------------------------------------------

die() {
  echo "error: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    case "$1" in
      rsvg-convert) echo "error: rsvg-convert not found — install with: brew install librsvg" >&2 ;;
      *)            echo "error: $1 not found" >&2 ;;
    esac
    exit 1
  }
}

render() { # render <size> <out.png>
  local size="$1" out="$2"
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$out"
}

# --- Tool checks -----------------------------------------------------------

need rsvg-convert

if command -v magick >/dev/null 2>&1; then
  IM=(magick)
elif command -v convert >/dev/null 2>&1; then
  IM=(convert)
else
  die "ImageMagick not found — install with: brew install imagemagick"
fi

[[ -f "$SVG" ]] || die "source SVG not found: $SVG"

# --- Build -----------------------------------------------------------------

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# macOS: AppIcon.appiconset — PNGs named to match the existing Contents.json.
MAC_ICONS="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  render "$size" "$MAC_ICONS/app_icon_${size}.png"
  echo "macOS    app_icon_${size}.png"
done

# Windows: multi-resolution .ico (largest first is fine; Windows picks by size).
WIN_ICO="$ROOT/windows/runner/resources/app_icon.ico"
for size in 256 128 64 48 32 24 16; do
  render "$size" "$TMP/win_${size}.png"
done
"${IM[@]}" \
  "$TMP/win_256.png" "$TMP/win_128.png" "$TMP/win_64.png" \
  "$TMP/win_48.png"  "$TMP/win_32.png"  "$TMP/win_24.png" "$TMP/win_16.png" \
  "$WIN_ICO"
echo "Windows  app_icon.ico"

# Linux: 256x256 PNG (path the Flutter Linux template expects).
LINUX_ICON="$ROOT/linux/runner/resources/app_icon.png"
mkdir -p "$(dirname "$LINUX_ICON")"
render 256 "$LINUX_ICON"
echo "Linux    app_icon.png (256x256)"

# Flutter asset: 1024x1024 PNG.
render 1024 "$ROOT/assets/icon.png"
echo "Flutter  assets/icon.png (1024x1024)"

echo "Done."
