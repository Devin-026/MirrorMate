#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_arch="${1:-$(uname -m)}"
case "$task_arch" in arm64|x86_64) ;; *) echo 'Usage: scripts/build-app.sh [arm64|x86_64]'; exit 1 ;; esac
swift build --product MirrorMate -c release --arch "$task_arch"
task_bin="$(swift build --product MirrorMate -c release --arch "$task_arch" --show-bin-path)"
task_app="dist/MirrorMate.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" dist/MirrorMate.iconset
cp "$task_bin/MirrorMate" "$task_app/Contents/MacOS/MirrorMate"
swift scripts/make-icon.swift dist/icon-1024.png
for task_size in 16 32 128 256 512; do
    sips -z "$task_size" "$task_size" dist/icon-1024.png --out "dist/MirrorMate.iconset/icon_${task_size}x${task_size}.png" >/dev/null
    task_retina=$((task_size * 2))
    sips -z "$task_retina" "$task_retina" dist/icon-1024.png --out "dist/MirrorMate.iconset/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
iconutil -c icns dist/MirrorMate.iconset -o "$task_app/Contents/Resources/MirrorMate.icns"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MirrorMate</string>
<key>CFBundleIdentifier</key><string>org.mirrormate.app</string>
<key>CFBundleName</key><string>MirrorMate</string>
<key>CFBundleDisplayName</key><string>MirrorMate</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>MirrorMate</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key><string>© 2026 MirrorMate contributors. MIT License.</string>
</dict></plist>
PLIST
# Ad-hoc signing is for a local/community build. It is not Developer ID notarization.
codesign --force --sign - "$task_app"
codesign --verify --strict "$task_app"
task_zip="dist/MirrorMate-0.1.2-${task_arch}.zip"
ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_zip"
(cd dist; shasum -a 256 "MirrorMate-0.1.2-${task_arch}.zip" > "MirrorMate-0.1.2-${task_arch}.zip.sha256")
echo "Built $task_zip"
