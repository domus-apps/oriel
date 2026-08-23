#!/bin/bash
# Appends a release entry to appcast.xml (the Sparkle update feed).
#
# Usage: appcast-add.sh <version> <build> <signature-attrs>
#   version          marketing version, no leading v (e.g. 1.1.0)
#   build            CFBundleVersion of the release (CI run number)
#   signature-attrs  sign_update's output for the release zip, verbatim:
#                    sparkle:edSignature="..." length="..."
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$1
BUILD=$2
SIGNATURE_ATTRS=$3

ITEM=$(mktemp)
cat > "$ITEM" <<EOF
    <item>
      <title>Oriel v$VERSION</title>
      <link>https://github.com/domus-apps/oriel/releases/tag/v$VERSION</link>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/domus-apps/oriel/releases/download/v$VERSION/Oriel.zip"
        $SIGNATURE_ATTRS
        type="application/octet-stream"/>
    </item>
EOF

awk -v itemfile="$ITEM" '
  /<\/channel>/ { while ((getline line < itemfile) > 0) print line }
  { print }
' appcast.xml > appcast.xml.new
mv appcast.xml.new appcast.xml
rm "$ITEM"

echo "Added v$VERSION (build $BUILD) to appcast.xml"
