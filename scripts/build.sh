#!/usr/bin/env bash
# Builds FastUtils.app without Xcode: SwiftPM binary + hand-assembled bundle + codesign.
#
#   scripts/build.sh              release build into build/FastUtils.app
#   scripts/build.sh --debug      debug build (lldb can attach)
#   scripts/build.sh --install    also copy to /Applications and (re)launch
#   scripts/build.sh --run        launch from build/ and stream app logs (Ctrl+C to stop)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="FastUtils"
BUNDLE_ID="com.yahor.FastUtils"
IDENTITY="FastUtils Dev"
CONFIG="release"
INSTALL=0
RUN=0

for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --install) INSTALL=1 ;;
        --run) RUN=1 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

echo "▸ swift build ($CONFIG, arm64)"
# CLT has no XCTest/Developer frameworks dir; the linker warns about it — harmless.
# The filter must not hide a failed build: otherwise the previous binary would be packaged.
set +e
swift build -c "$CONFIG" --arch arm64 2>&1 | grep -v "search path '/Library/Developer/CommandLineTools/Developer"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
[[ $BUILD_STATUS -eq 0 ]] || { echo "✘ swift build failed (exit $BUILD_STATUS)" >&2; exit "$BUILD_STATUS"; }
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || { echo "Build failed: $BIN_DIR/$APP_NAME not found" >&2; exit 1; }

APP="build/$APP_NAME.app"
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# SwiftPM resource bundles of dependencies (e.g. KeyboardShortcuts), if any.
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

ENTITLEMENTS="Resources/$APP_NAME.entitlements"
if [[ "$CONFIG" == "debug" ]]; then
    ENTITLEMENTS="build/debug.entitlements"
    cp "Resources/$APP_NAME.entitlements" "$ENTITLEMENTS"
    plutil -insert com\\.apple\\.security\\.get-task-allow -bool true "$ENTITLEMENTS"
fi

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    SIGN="$IDENTITY"
else
    SIGN="-"
    echo "⚠️  Identity \"$IDENTITY\" not found — ad-hoc signing. Permissions will reset on every build." >&2
    echo "   Run scripts/create-signing-cert.sh once to fix this." >&2
fi
echo "▸ codesign ($SIGN)"
codesign --force --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN" "$APP"
codesign --verify --strict "$APP"

if [[ $INSTALL -eq 1 ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    open "/Applications/$APP_NAME.app"
elif [[ $RUN -eq 1 ]]; then
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
    open "$APP"
    echo "▸ Streaming logs (Ctrl+C to stop)"
    exec log stream --style compact --level debug --predicate "subsystem == \"$BUNDLE_ID\""
fi

echo "✔ $APP"
