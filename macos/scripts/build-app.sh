#!/bin/bash
# Đóng gói Diskat.app (universal: Apple Silicon + Intel) và Diskat-<phiên bản>.dmg vào macos/dist.
#
#   scripts/build-app.sh
#       Ký ad-hoc: chạy được trên máy này; máy khác sẽ bị Gatekeeper chặn lần đầu.
#   SIGN_ID="Developer ID Application: <Tên> (<TEAMID>)" scripts/build-app.sh
#       Ký bằng chứng chỉ Developer ID (hardened runtime) để phát hành.
#   SIGN_ID=... NOTARY_PROFILE=diskat scripts/build-app.sh
#       Thêm công chứng (notarize) và đóng dấu (staple) bản DMG. Tạo hồ sơ một lần bằng:
#       xcrun notarytool store-credentials diskat --apple-id <email> --team-id <TEAMID>
#
# Biến khác: VERSION (mặc định 1.0.0), BUILD (mặc định số commit), CONFIG (release | debug).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIG="${CONFIG:-release}"
OUT="${OUT:-dist}"
APP="$OUT/Diskat.app"
DMG="$OUT/Diskat-$VERSION.dmg"
ARCHS=(--arch arm64 --arch x86_64)

if [ ! -f Resources/AppIcon.icns ]; then
  swift run -c release make-icon Resources/AppIcon.icns
fi

swift build -c "$CONFIG" --product Diskat "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" --product Diskat "${ARCHS[@]}" --show-bin-path)/Diskat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Diskat"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

# DMG có lối tắt tới /Applications để kéo thả cài đặt
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Diskat" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo
echo "App: $APP ($(lipo -archs "$APP/Contents/MacOS/Diskat"))"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
