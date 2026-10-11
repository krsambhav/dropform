#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/dropform-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
npm --prefix ui run build
swift build -c release --disable-sandbox -debug-info-format none
mkdir -p dist/Dropform.app/Contents/MacOS dist/Dropform.app/Contents/Resources dist/Dropform.iconset
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/icon.swift dist/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" dist/icon.png --out "dist/Dropform.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" dist/icon.png --out "dist/Dropform.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - <<'ICON'
import pathlib, struct
chunks = []
for kind, name in [(b'ic07', 'icon_128x128.png'), (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'), (b'ic10', 'icon_512x512@2x.png')]:
    data = pathlib.Path('dist/Dropform.iconset', name).read_bytes()
    chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
pathlib.Path('dist/Dropform.app/Contents/Resources/Dropform.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
ICON
mkdir -p dist/Dropform.app/Contents/Resources/Workbench
cp ui/dist/index.html dist/Dropform.app/Contents/Resources/Workbench/index.html
cp -R LICENSES dist/Dropform.app/Contents/Resources/
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox)
cp "$BIN_DIR/Dropform" dist/Dropform.app/Contents/MacOS/Dropform
cat > dist/Dropform.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Dropform</string>
<key>CFBundleIdentifier</key><string>local.dropform.app</string>
<key>CFBundleIconFile</key><string>Dropform</string>
<key>CFBundleName</key><string>Dropform</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - dist/Dropform.app
printf 'Built dist/Dropform.app\n'
