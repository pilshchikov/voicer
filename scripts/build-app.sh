#!/bin/zsh
# Usage: scripts/build-app.sh [--install]
# Set SIGN_IDENTITY to a stable code signing identity so macOS keeps the Accessibility
# grant across rebuilds. Ad-hoc signing ("-") changes identity on every build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)

APP=build/Voicer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Voicer" "$APP/Contents/MacOS/Voicer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for bundle in "$BIN"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Voicer || true
  rm -rf /Applications/Voicer.app
  cp -R "$APP" /Applications/Voicer.app
  open /Applications/Voicer.app
  echo "Installed to /Applications/Voicer.app"
fi
