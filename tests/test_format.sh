#!/bin/bash
# Tests for menu-bar formatting helpers (Format.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/Format.swift" "$ROOT/tests/test_format.swift" -o "$TMP/test_format"
"$TMP/test_format"
