#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

release_version="${1:-$(cat VERSION)}"
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$'
if [[ ! "$release_version" =~ $version_pattern ]]; then
  printf 'Release version must be X.Y.Z or X.Y.Z-prerelease.\n' >&2
  exit 1
fi

APP_VERSION="${release_version%%-*}" APP_ARCH=universal ./scripts/build-app.sh release
app="$PWD/dist/Yuin.app"
for executable in MyMusic MusicSourceHost; do
  for architecture in arm64 x86_64; do
    lipo "$app/Contents/MacOS/$executable" -verify_arch "$architecture"
  done
done
python3 scripts/verify-app.py "$app"

release_dir="$PWD/dist/releases"
mkdir -p "$release_dir"
asset_name="Yuin-${release_version}-universal"
zip="$release_dir/$asset_name.zip"
dmg="$release_dir/$asset_name.dmg"

# ditto preserves the application bundle's executable modes and symlinks.
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
dmg_stage="$(mktemp -d "$PWD/.build/yuin-dmg.XXXXXX")"
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$app" "$dmg_stage/Yuin.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname Yuin -srcfolder "$dmg_stage" -format UDZO -ov -o "$dmg"
hdiutil verify "$dmg"
(
  cd "$release_dir"
  shasum -a 256 "$asset_name.zip" "$asset_name.dmg" > "$asset_name.sha256"
  shasum -a 256 -c "$asset_name.sha256"
)
printf 'Packaged: %s\n' "$zip" "$dmg" "$release_dir/$asset_name.sha256"
