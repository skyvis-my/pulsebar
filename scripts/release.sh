#!/bin/zsh
# Builds Pulsebar, zips it, publishes a GitHub release, and points the Homebrew cask at it.
# Usage: ./scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: release.sh <version>}
REPO=skyvis-my/pulsebar
TAP=skyvis-my/homebrew-tap
ZIP=build/Pulsebar-$VERSION.zip

VERSION=$VERSION ./scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/Pulsebar.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Pulsebar $VERSION" --generate-notes

# GitHub takes a little while to serve a new asset; bump the cask only once the zip downloads intact.
URL="https://github.com/$REPO/releases/download/v$VERSION/Pulsebar-$VERSION.zip"
for _ in {1..30}; do
  [[ "$(curl -sfL "$URL" | shasum -a 256 | cut -d' ' -f1)" == "$SHA" ]] && break
  sleep 2
done

# Update the cask in the tap.
TMP=$(mktemp -d)
gh repo clone "$TAP" "$TMP" -- --quiet
sed -i '' -E "s/version \"[^\"]+\"/version \"$VERSION\"/; s/sha256 \"[^\"]+\"/sha256 \"$SHA\"/" "$TMP/Casks/pulsebar.rb"
git -C "$TMP" commit -qam "pulsebar $VERSION"
git -C "$TMP" push -q
rm -rf "$TMP"
echo "Released $VERSION ($SHA)"
