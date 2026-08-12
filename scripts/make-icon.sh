#!/bin/bash
# Regenerate AppIcon.icns from icons/gen_icon.swift (1024px master).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/icons/build"
SET="$D/AppIcon.iconset"

mkdir -p "$SET"
swift "$ROOT/icons/gen_icon.swift" "$D/icon_1024.png"

sips -z 16 16   "$D/icon_1024.png" --out "$SET/icon_16x16.png"       >/dev/null
sips -z 32 32   "$D/icon_1024.png" --out "$SET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32   "$D/icon_1024.png" --out "$SET/icon_32x32.png"       >/dev/null
sips -z 64 64   "$D/icon_1024.png" --out "$SET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128 "$D/icon_1024.png" --out "$SET/icon_128x128.png"     >/dev/null
sips -z 256 256 "$D/icon_1024.png" --out "$SET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256 "$D/icon_1024.png" --out "$SET/icon_256x256.png"     >/dev/null
sips -z 512 512 "$D/icon_1024.png" --out "$SET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512 "$D/icon_1024.png" --out "$SET/icon_512x512.png"     >/dev/null
cp "$D/icon_1024.png" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$D/AppIcon.icns"
echo "AppIcon.icns 已生成: $D/AppIcon.icns"
