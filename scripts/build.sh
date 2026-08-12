#!/bin/bash
# Build System-Bar.app (helper + SwiftUI menu-bar app) into ./build
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/System-Bar.app"

mkdir -p "$OUT"

echo "[1/4] compiling smctemp helper..."
clang -O2 -Wall -framework CoreFoundation -framework IOKit -lIOReport \
    "$ROOT/helper/smctemp.c" -o "$OUT/smctemp"

echo "[2/4] compiling System-Bar app..."
swiftc -O -parse-as-library \
    "$ROOT/app/SystemBarApp.swift" "$ROOT/app/TempMonitor.swift" "$ROOT/app/Format.swift" "$ROOT/app/DailyLog.swift" "$ROOT/app/ProcMonitor.swift" \
    -o "$OUT/System-Bar" -framework SwiftUI -framework AppKit

echo "[3/4] assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
cp "$OUT/System-Bar" "$APP/Contents/MacOS/"
cp "$OUT/smctemp" "$APP/Contents/MacOS/"
if [ -f "$ROOT/icons/build/AppIcon.icns" ]; then
    cp "$ROOT/icons/build/AppIcon.icns" "$APP/Contents/Resources/"
fi

echo "[4/4] signing (ad-hoc)..."
codesign --force --sign - "$APP" 2>/dev/null

echo "Built: $APP"
