#!/bin/bash
# Runs the unit tests. (Command Line Tools alone can't run Swift Testing —
# full Xcode is required.)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --build-tests

# Xcode 26's build system stages binary-target frameworks (Sparkle) next to
# the products but not into PackageFrameworks/, which is the rpath it writes
# into test bundles — so the tests die in dlopen. Symlink it into place.
for products in .build/out/Products/*; do
    if [[ -d "$products/Sparkle.framework" ]]; then
        mkdir -p "$products/PackageFrameworks"
        ln -sfn ../Sparkle.framework "$products/PackageFrameworks/Sparkle.framework"
    fi
done

swift test --skip-build "$@"
