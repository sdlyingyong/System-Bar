#!/bin/bash
# Tests for PanelDismiss (panel close-on-outside-click logic).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O "$ROOT/app/PanelDismiss.swift" "$ROOT/tests/test_paneldismiss.swift" \
    -o "$TMP/test_paneldismiss" -framework AppKit
"$TMP/test_paneldismiss"
