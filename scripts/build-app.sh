#!/bin/bash
# Builds "build/Open Code Hub.app".
#
# Two paths:
#   xcodegen + xcodebuild  — the native Xcode target (assets, entitlements,
#                            resource copying, signing). Used when xcodegen is
#                            installed; that is what CI does.
#   SwiftPM fallback       — swift build plus a hand-assembled bundle, for a
#                            machine with only the Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Support/Info.plist" 2>/dev/null || echo 1.1.0)}"
UNIVERSAL="${UNIVERSAL:-0}"
APP_NAME="Open Code Hub"
BUNDLE="$ROOT/build/$APP_NAME.app"
CAP="$(printf '%s' "$CONFIG" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

command -v swift >/dev/null 2>&1 || { echo "swift not found. Install Xcode or the Command Line Tools." >&2; exit 1; }

mkdir -p "$ROOT/build"
rm -rf "$BUNDLE"

build_with_xcodebuild() {
  echo "==> Generating Xcode project"
  ( cd "$ROOT" && xcodegen generate --spec project.yml --quiet )

  local archs=()
  if [ "$UNIVERSAL" = "1" ]; then
    archs=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  fi

  echo "==> xcodebuild ($CAP)"
  xcodebuild \
    -project "$ROOT/OpenCodeHub.xcodeproj" \
    -scheme OpenCodeHub \
    -configuration "$CAP" \
    -derivedDataPath "$ROOT/.build/xcode" \
    CONFIGURATION_BUILD_DIR="$ROOT/build" \
    MARKETING_VERSION="$VERSION" \
    "${archs[@]}" \
    build | tail -n 20
}

build_with_swiftpm() {
  echo "==> xcodegen not found; building with SwiftPM"
  local bin
  if [ "$UNIVERSAL" = "1" ]; then
    swift build -c "$CONFIG" --arch arm64 --arch x86_64 --package-path "$ROOT"
    bin="$ROOT/.build/apple/Products/$CAP/OpenCodeHub"
  else
    swift build -c "$CONFIG" --package-path "$ROOT"
    bin="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/OpenCodeHub"
  fi
  [ -x "$bin" ] || { echo "missing binary at $bin" >&2; exit 1; }

  echo "==> Assembling bundle by hand"
  mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
  cp "$bin" "$BUNDLE/Contents/MacOS/$APP_NAME"
  chmod 755 "$BUNDLE/Contents/MacOS/$APP_NAME"
  cp "$ROOT/Support/Info.plist" "$BUNDLE/Contents/Info.plist"
  printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || true

  if [ -f "$ROOT/Support/AppIcon.png" ] && command -v iconutil >/dev/null 2>&1; then
    local iconset="$ROOT/.build/AppIcon.iconset"
    rm -rf "$iconset" && mkdir -p "$iconset"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
      set -- $spec
      sips -z "$1" "$1" "$ROOT/Support/AppIcon.png" --out "$iconset/$2.png" >/dev/null 2>&1
    done
    iconutil -c icns "$iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  fi

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true
  fi
}

if command -v xcodegen >/dev/null 2>&1 && [ -f "$ROOT/project.yml" ]; then
  build_with_xcodebuild
else
  build_with_swiftpm
fi

[ -d "$BUNDLE" ] || { echo "build did not produce $BUNDLE" >&2; exit 1; }

echo "==> Verifying"
BIN_PATH="$BUNDLE/Contents/MacOS/$APP_NAME"
[ -x "$BIN_PATH" ] || { echo "missing executable $BIN_PATH" >&2; exit 1; }
lipo -archs "$BIN_PATH" 2>/dev/null || file "$BIN_PATH"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE/Contents/Info.plist"
codesign --verify --verbose=1 "$BUNDLE" 2>&1 | sed 's/^/    /' || true

echo "==> Built $BUNDLE ($(du -sh "$BUNDLE" | cut -f1), $VERSION)"
echo "    open \"$BUNDLE\""
