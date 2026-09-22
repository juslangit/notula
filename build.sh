#!/usr/bin/env bash
# Builds Notula.app into ./build and signs it so macOS will remember its permissions.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

echo "→ compiling"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Notula"

APP="$ROOT/build/Notula.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notula"
cp "$ROOT/tools/pipeline.sh" "$APP/Contents/Resources/pipeline.sh"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Point the app at the editable copy of the script, so changing it needs no rebuild.
/usr/libexec/PlistBuddy -c "Delete :NSPipelinePlaceholder" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NotulaPipeline string $ROOT/tools/pipeline.sh" "$APP/Contents/Info.plist"

# Sign with the local certificate if it exists. This is what makes the microphone
# and screen permissions survive a rebuild: an ad-hoc signature identifies the app
# by the hash of its own bytes, so every rebuild looks like a different app and
# macOS asks all over again. A certificate keeps the identity fixed.
IDENTITY="Notula Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier com.luqman.notula "$APP"
else
  echo "⚠️  no signing certificate — macOS will ask for permission again after every"
  echo "   rebuild. Run ./tools/make-signing-cert.sh once to stop that."
  codesign --force --sign - --identifier com.luqman.notula "$APP"
fi
echo "→ built $APP"
