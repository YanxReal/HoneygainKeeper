#!/bin/bash
# ============================================================================
#  Empaqueta HoneygainKeeper para un GitHub Release: DMG + ZIP en dist/.
#  Uso: ./scripts/package.sh   (o `make dist`, que compila Release antes)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="build/DerivedData/Build/Products/Release/HoneygainKeeper.app"
DIST="dist"

if [ ! -d "$APP_PATH" ]; then
  echo "⏳ No hay build Release; compilando…"
  make release
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
NAME="HoneygainKeeper-$VERSION"
mkdir -p "$DIST"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# --- DMG (arrastrar y soltar en Aplicaciones) ---
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$NAME.dmg"
hdiutil create -volname "HoneygainKeeper" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DIST/$NAME.dmg"

# --- ZIP (app suelta, preservando metadatos y firma con ditto) ---
rm -f "$DIST/$NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$DIST/$NAME.zip"

# --- Checksums (verificación manual tras la descarga) ---
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)

echo "✅ $DIST/$NAME.dmg"
echo "✅ $DIST/$NAME.zip"
echo "✅ $DIST/SHA256SUMS.txt"
