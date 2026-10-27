#!/bin/zsh
# Builds Orbit.app into ./build. Pass --install to copy it to /Applications and open it.
#
# Signs with $ORBIT_SIGN_IDENTITY, else $NOVA_SIGN_IDENTITY (your "Apple Development: …"
# certificate), else ad hoc.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release

APP=build/Orbit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Orbit" "$APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: build AppIcon.icns from the 1024px PNG.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${ORBIT_SIGN_IDENTITY:-${NOVA_SIGN_IDENTITY:--}}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Orbit 2>/dev/null || true
    rm -rf /Applications/Orbit.app
    cp -R "$APP" /Applications/
    open /Applications/Orbit.app
    echo "Installed and opened /Applications/Orbit.app"
fi
