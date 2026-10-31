#!/bin/bash
# Packages build/OpenCode Hub.app into a compressed DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/OpenCode Hub.app"
VERSION="${VERSION:-1.0.0}"
OUT="$ROOT/build/OpenCodeHub-$VERSION.dmg"

[ -d "$APP" ] || { echo "Build the app first: ./scripts/build-app.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "OpenCode Hub" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "==> $OUT"
