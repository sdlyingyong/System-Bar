#!/bin/bash
# Tests for popover dismiss policy (PopoverPolicy.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/PopoverPolicy.swift" "$ROOT/tests/test_popover.swift" -o "$TMP/test_popover"
"$TMP/test_popover"
