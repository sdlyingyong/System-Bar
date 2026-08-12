#!/bin/bash
# Build System-Bar.app, install to /Applications, register login auto-start.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/System-Bar.app"
DEST="/Applications/System-Bar.app"
LA="$HOME/Library/LaunchAgents/com.system-bar.app.plist"

echo "==> 1/4 构建..."
"$ROOT/scripts/build.sh" >/dev/null

echo "==> 2/4 停止正在运行的实例（含旧名 MenuTemp）..."
pkill -f "System-Bar.app/Contents/MacOS/System-Bar" 2>/dev/null || true
pkill -f "MenuTemp.app/Contents/MacOS/MenuTemp" 2>/dev/null || true
pkill -x smctemp 2>/dev/null || true
sleep 1

echo "==> 3/4 安装到 $DEST"
rm -rf "$DEST" /Applications/MenuTemp.app
cp -R "$SRC" "$DEST"

echo "==> 4/4 注册登录自启 (LaunchAgent)..."
mkdir -p "$HOME/Library/LaunchAgents"
rm -f "$HOME/Library/LaunchAgents/com.menutemp.app.plist"
cat > "$LA" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.system-bar.app</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>${DEST}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
launchctl unload "$LA" 2>/dev/null || true
launchctl load "$LA"

echo "==> 启动..."
open "$DEST"
sleep 3
if pgrep -f "$DEST/Contents/MacOS/System-Bar" >/dev/null; then
    echo "✅ 安装成功，System-Bar 已在菜单栏运行: $DEST"
else
    echo "⚠️ 进程未检测到，请检查"
fi
