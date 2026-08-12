#!/bin/bash
# Tests for DailyLog (daily max temp logging).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/DailyLog.swift" "$ROOT/tests/test_dailylog.swift" -o "$TMP/test_dailylog"
"$TMP/test_dailylog"
