#!/bin/zsh
# Builds a release binary, wraps it in build/Relay.app and zips it.
set -euo pipefail
cd "$(dirname "$0")"

# One binary for both Apple Silicon and Intel Macs.
archs=(--arch arm64 --arch x86_64)
swift build -c release "${archs[@]}" --product Relay
bin="$(swift build -c release "${archs[@]}" --show-bin-path)/Relay"

# The app draws its own icon.
iconset="build/AppIcon.iconset"
rm -rf "$iconset" build/Relay.app
mkdir -p "$iconset"
"$bin" --render-icon build/icon-1024.png
for size in 16 32 128 256 512; do
    sips -z $size $size build/icon-1024.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o build/AppIcon.icns
rm -rf "$iconset"

app="build/Relay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Relay"
mv build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
rm -f build/icon-1024.png

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Relay</string>
    <key>CFBundleDisplayName</key><string>Relay</string>
    <key>CFBundleIdentifier</key><string>local.relay</string>
    <key>CFBundleExecutable</key><string>Relay</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Signed with the local "Relay Local Signing" certificate when the keychain has it, so the
# app keeps the same identity from build to build and macOS keeps its Accessibility
# permission. Without the certificate the signature is ad-hoc and the permission has to be
# granted again after every build. Either way, sharing the app with other people needs a
# Developer ID signature and notarization instead.
identity="Relay Local Signing"
if security find-identity -p codesigning | grep -q "\"$identity\""; then
    # Hardened runtime, as notarization will require, so the app is always tested with it on.
    codesign --force --options runtime --sign "$identity" "$app"
else
    codesign --force --sign - "$app"
fi

# A zip that keeps the bundle's signature and attributes intact, for copying elsewhere.
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="build/Relay-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "Built $app and $zip"
