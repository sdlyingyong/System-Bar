#!/bin/bash
# Tests for Cleaner (trash + cache cleanup).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/Cleaner.swift" "$ROOT/tests/test_cleaner.swift" -o "$TMP/test_cleaner"
"$TMP/test_cleaner"