#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Dropform.app/Contents/Info.plist)
arch=$(lipo -archs dist/Dropform.app/Contents/MacOS/Dropform)
[[ "$arch" == arm64 ]] || { print -u2 'Expected an arm64 release build'; exit 1; }
codesign --verify --deep --strict dist/Dropform.app
stage=$(mktemp -d "${TMPDIR:-/tmp}/dropform-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto dist/Dropform.app "$stage/Dropform.app"
ln -s /Applications "$stage/Applications"
cp "releases/v${version}.md" "$stage/Installation and release notes.txt"
mkdir -p dist/release
base="Dropform-${version}-macOS-arm64"
hdiutil create -volname "Dropform ${version}" -srcfolder "$stage" -ov -format UDZO "dist/release/${base}.dmg"
ditto -c -k --sequesterRsrc --keepParent dist/Dropform.app "dist/release/${base}.zip"
(cd dist/release && shasum -a 256 "${base}.dmg" "${base}.zip" > SHA256SUMS.txt)
hdiutil verify "dist/release/${base}.dmg"
unzip -tq "dist/release/${base}.zip"
