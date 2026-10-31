#!/bin/bash
# Packages build/Open Code Hub.app into build/OpenCodeHub-<version>.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Open Code Hub.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist")}"
DMG="$ROOT/build/OpenCodeHub-$VERSION.dmg"
STAGE="$(mktemp -d)"

[ -d "$APP" ] || { echo "build the app first: ./scripts/build-app.sh" >&2; exit 1; }

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<'TXT'
Open Code Hub

Drag the app into Applications.

This build is ad-hoc signed, not notarised. First launch:
  right-click the app -> Open -> Open
or:
  xattr -dr com.apple.quarantine "/Applications/Open Code Hub.app"
TXT

rm -f "$DMG"
hdiutil create -volname "Open Code Hub" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
