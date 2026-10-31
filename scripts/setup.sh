#!/bin/bash
# Verifies the build toolchain, validates Package.swift and resolves the
# SwiftPM graph. Safe to run repeatedly; it never installs anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    -h|--help)
      echo "usage: scripts/setup.sh [--check-only]"
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

fail() { printf '  ✗ %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }

echo "OpenCode Hub — dependency setup"
echo

# 1. Toolchain ---------------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
  fail "swift not found. Install Xcode 15+ or: xcode-select --install"
fi

SWIFT_LINE="$(swift --version 2>&1 | head -n 1)"
VER="$(printf '%s' "$SWIFT_LINE" | sed -n 's/.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
[ -n "$VER" ] || fail "could not read the Swift version from: $SWIFT_LINE"

MAJOR="${VER%% *}"
MINOR="${VER##* }"
if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -lt 9 ]; }; then
  fail "Swift $MAJOR.$MINOR is too old; 5.9 or newer is required"
fi
ok "Swift $MAJOR.$MINOR ($SWIFT_LINE)"

if xcode-select -p >/dev/null 2>&1; then
  ok "developer dir: $(xcode-select -p)"
else
  fail "no developer directory. Run: sudo xcode-select --switch /Applications/Xcode.app"
fi

if SDK="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)"; then
  ok "macOS SDK $SDK"
else
  warn "could not query the macOS SDK (xcrun)"
fi

echo
echo "Package manifest"

# 2. Manifest ----------------------------------------------------------------
cd "$ROOT"
swift package dump-package >/dev/null 2>/tmp/och-dump.err \
  || fail "Package.swift is invalid: $(cat /tmp/och-dump.err)"
ok "Package.swift parses"

# 3. Dependency graph --------------------------------------------------------
if [ -f Package.resolved ]; then
  COUNT="$(grep -c '"identity"' Package.resolved || true)"
  ok "Package.resolved present ($COUNT pinned packages)"
else
  ok "no external Swift packages (nothing to pin)"
fi

swift package resolve >/dev/null 2>/tmp/och-resolve.err \
  || fail "swift package resolve failed: $(cat /tmp/och-resolve.err)"
ok "dependency graph resolved"

echo
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Check-only run complete."
  exit 0
fi

# 4. Build -------------------------------------------------------------------
echo "Building (debug)"
swift build -c debug 2>&1 | tail -n 5
ok "swift build succeeded"

echo
echo "Next:"
echo "  make app     # release build wrapped in build/OpenCode Hub.app"
echo "  make dmg     # compressed disk image"
echo "  make check   # debug build, the real compile gate"
