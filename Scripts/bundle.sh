#!/bin/bash
# Builds a standalone Oriel.app at build/Oriel.app.
# The bundle gets its own Accessibility permission entry, separate from the
# `swift run` dev flow (where the permission belongs to your terminal).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Oriel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Oriel "$APP/Contents/MacOS/Oriel"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Compile the Icon Composer document (Assets/AppIcon.icon) into Assets.car —
# on macOS 26+ the system renders the icon's Liquid Glass appearance live,
# including the dark/clear/tinted variants — plus a fallback AppIcon.icns
# rendered from the same layers.
ICONBUILD=$(mktemp -d)
xcrun actool Assets/AppIcon.icon --compile "$ICONBUILD" \
    --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "$ICONBUILD/partial.plist" \
    --output-format human-readable-text --errors > /dev/null
cp "$ICONBUILD/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ICONBUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONBUILD"

# With CODESIGN_IDENTITY set (e.g. "Developer ID Application"), produce a
# distributable, notarization-ready signature (hardened runtime + timestamp).
# Otherwise fall back to ad-hoc, which keeps the TCC (Accessibility) grant
# stable across rebuilds on this machine.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "Run:  open $APP"
