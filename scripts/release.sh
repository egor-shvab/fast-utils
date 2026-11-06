#!/usr/bin/env bash
# Builds a release DMG: build/FastUtils-<version>.dmg with the app and an Applications link.
# The version comes from Resources/Info.plist (CFBundleShortVersionString).
#
#   scripts/release.sh
#
# Then: commit, `git tag v<version>`, push the tag and attach the DMG to a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="FastUtils"
IDENTITY="FastUtils Dev"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
DMG="build/$APP_NAME-$VERSION.dmg"

[[ -z "$(git status --porcelain)" ]] || echo "⚠️  Uncommitted changes: the DMG will not match any commit." >&2

scripts/build.sh

echo "▸ Packing $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "build/$APP_NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov "$DMG"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --timestamp=none --sign "$IDENTITY" "$DMG"
fi
hdiutil verify -quiet "$DMG"

echo "✔ $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
