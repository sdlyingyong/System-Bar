#!/bin/bash
# Tests for memory cleaner (LeakPolicy + MemoryCleaner).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O \
    "$ROOT/app/MemoryCleaner.swift" \
    "$ROOT/app/ProcMonitor.swift" \
    "$ROOT/tests/test_memcleaner.swift" \
    -o "$TMP/test_memcleaner" -framework AppKit
"$TMP/test_memcleaner"
