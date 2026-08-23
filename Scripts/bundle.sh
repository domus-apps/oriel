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

# Ad-hoc signature: keeps the TCC (Accessibility) grant stable across rebuilds
# on this machine. Replace with a Developer ID identity for distribution.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run:  open $APP"
