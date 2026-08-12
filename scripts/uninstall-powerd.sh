#!/bin/bash
# Remove menutemp-powerd LaunchDaemon. Requires sudo.
set -euo pipefail

PLIST="/Library/LaunchDaemons/com.menutemp.powerd.plist"
DEST="/usr/local/bin/menutemp-powerd"

echo "==> 停止并卸载守护进程..."
launchctl bootout system/com.menutemp.powerd 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true

echo "==> 删除文件..."
rm -f "$PLIST" "$DEST" /tmp/menutemp_power

echo "==> 已卸载。"
