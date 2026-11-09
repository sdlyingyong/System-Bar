#!/bin/bash
# Tests for ProcMonitor (process scan + force kill).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ProcMonitor 会向 MemoryCleaner 喂内存快照，需一并编译
swiftc -O "$ROOT/app/MemoryCleaner.swift" "$ROOT/app/ProcMonitor.swift" \
    "$ROOT/tests/test_procmon.swift" -o "$TMP/test_procmon" -framework AppKit
"$TMP/test_procmon"
