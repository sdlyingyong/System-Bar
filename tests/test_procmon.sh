#!/bin/bash
# Tests for ProcMonitor (process scan + force kill).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/ProcMonitor.swift" "$ROOT/tests/test_procmon.swift" -o "$TMP/test_procmon"
"$TMP/test_procmon"
