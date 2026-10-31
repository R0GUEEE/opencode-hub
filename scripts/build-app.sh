#!/bin/bash
# Builds .build/<config>/OpenCodeHub and wraps it in a real .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="OpenCode Hub"
BUNDLE="$ROOT/build/$APP_NAME.app"
VERSION="${VERSION:-1.0.0}"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift was not found. Install Xcode or the Command Line Tools." >&2
  exit 1
fi

UNIVERSAL="${UNIVERSAL:-0}"
CAP="$(printf "%s" "$CONFIG" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Building universal ($CONFIG)"
  swift build -c "$CONFIG" --arch arm64 --arch x86_64 --package-path "$ROOT"
  BIN="$ROOT/.build/apple/Products/$CAP/OpenCodeHub"
else
  echo "==> Building ($CONFIG)"
  swift build -c "$CONFIG" --package-path "$ROOT"
  BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/OpenCodeHub"
fi
BIN_DIR="$(dirname "$BIN")"
[ -x "$BIN" ] || { echo "Missing binary at $BIN" >&2; exit 1; }

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/OpenCodeHub"
cp "$ROOT/Support/Info.plist" "$BUNDLE/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || true

# SwiftPM resource bundles are looked up in Contents/Resources by Bundle.module.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$BUNDLE/Contents/Resources/"
done
shopt -u nullglob

printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 \
    && echo "==> Ad-hoc signed" \
    || echo "!!  Ad-hoc signing failed; the app still runs locally" >&2
fi

echo "==> Built $BUNDLE"
echo "    open \"$BUNDLE\""
