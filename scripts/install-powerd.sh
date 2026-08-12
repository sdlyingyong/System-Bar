#!/bin/bash
# Install menutemp-powerd as a root LaunchDaemon to read SMC PSTR
# (whole-machine power). Requires sudo (one password entry).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/menutemp-powerd"
DEST="/usr/local/bin/menutemp-powerd"
PLIST="/Library/LaunchDaemons/com.menutemp.powerd.plist"

echo "==> 编译 powerd..."
mkdir -p "$ROOT/build"
clang -O2 -framework IOKit -framework CoreFoundation "$ROOT/helper/powerd.c" -o "$BIN"

echo "==> 以 root 自测读取 PSTR（整机功耗）..."
SELF_TEST="$("$BIN" --once 2>&1)"
echo "    结果: $SELF_TEST"
if ! echo "$SELF_TEST" | grep -qE '^power=[0-9]'; then
    echo "!! 读取失败（可能此机型 root 也无权限），未安装。"
    exit 1
fi

echo "==> 安装到 $DEST..."
install -m 755 "$BIN" "$DEST"

echo "==> 安装 LaunchDaemon..."
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.menutemp.powerd</string>
	<key>ProgramArguments</key>
	<array>
		<string>${DEST}</string>
		<string>-i</string>
		<string>2</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
sleep 2

echo "==> 守护进程状态:"
launchctl print system/com.menutemp.powerd 2>/dev/null | grep -E "state|pid" | head -3 || echo "    (launchctl 查询失败，进程可能未启动)"
echo "==> 当前整机功耗文件:"
cat /tmp/menutemp_power 2>/dev/null || echo "    (文件未生成)"
echo "==> 完成。菜单栏 App 的「整机功耗」现在会读取真实值。"
