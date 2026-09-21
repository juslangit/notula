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

codesign --force --sign - --identifier com.luqman.notula "$APP"
echo "→ built $APP"
