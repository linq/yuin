#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${1:-release}"
app_version="${APP_VERSION:-$(cat VERSION)}"
build_number="${APP_BUILD_NUMBER:-5}"
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ ! "$app_version" =~ $version_pattern || ! "$build_number" =~ ^[0-9]+$ ]]; then
  printf 'APP_VERSION must be X.Y.Z and APP_BUILD_NUMBER must be numeric.\n' >&2
  exit 1
fi
build_args=(-c "$configuration")
case "${APP_ARCH:-native}" in
  native) ;;
  universal) build_args+=(--arch arm64 --arch x86_64) ;;
  arm64|x86_64) build_args+=(--arch "$APP_ARCH") ;;
  *) printf 'APP_ARCH must be native, universal, arm64 or x86_64.\n' >&2; exit 1 ;;
esac
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app="$PWD/dist/Yuin.app"
# Reuse the previous bundle; retain its bundle identifier and data/preferences.
if [[ ! -d "$app" && -d "$PWD/dist/MyMusic.app" ]]; then
  mv "$PWD/dist/MyMusic.app" "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace executables atomically so a running instance keeps its original mapped binary.
for executable in MyMusic MusicSourceHost; do
  staging="$(mktemp "$app/Contents/MacOS/.${executable}.XXXXXX")"
  cp "$bin_dir/$executable" "$staging"
  chmod 755 "$staging"
  mv -f "$staging" "$app/Contents/MacOS/$executable"
done
# ditto merges the resource bundle while preserving its directory structure.
ditto "$bin_dir/MyMusic_MusicSourceHost.bundle" "$app/Contents/Resources/MyMusic_MusicSourceHost.bundle"
ditto "$bin_dir/MyMusic_MusicCore.bundle" "$app/Contents/Resources/MyMusic_MusicCore.bundle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
<key>CFBundleIdentifier</key><string>local.mymusic.mac</string>
<key>CFBundleName</key><string>Yuin</string>
<key>CFBundleDisplayName</key><string>Yuin</string>
<key>CFBundleExecutable</key><string>MyMusic</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccentColorName</key><string>AccentColor</string>
<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
xcrun actool --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --output-format human-readable-text "$PWD/assets/Appearance.xcassets"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $app_version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/zh-Hans.lproj"
cat > "$app/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "Yuin";
"CFBundleDisplayName" = "Yuin";
STRINGS
cat > "$app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "余音";
"CFBundleDisplayName" = "余音";
STRINGS
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$PWD/assets/branding/yuin-icon.svg"
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/Licenses"
cp docs/licenses/LX-Music-Apache-2.0.txt "$app/Contents/Resources/Licenses/"
cp docs/THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Licenses/"
codesign --force --sign - --timestamp=none "$app/Contents/MacOS/MusicSourceHost"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
