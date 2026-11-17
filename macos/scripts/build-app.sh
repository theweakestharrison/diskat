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
# Options: ARCH=universal (default), x86_64, or arm64; OUT=dist.
# VERSION defaults to 1.1.0, BUILD to the commit count; CONFIG=release or debug.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIG="${CONFIG:-release}"
OUT="${OUT:-dist}"
APP="$OUT/Diskat.app"
DMG="$OUT/Diskat-$VERSION.dmg"
case "${ARCH:-universal}" in
  universal) ARCHS=(--arch arm64 --arch x86_64) ;;
  x86_64|arm64) ARCHS=(--arch "$ARCH") ;;
  *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac
export MACOSX_DEPLOYMENT_TARGET
MACOSX_DEPLOYMENT_TARGET="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"

if [ ! -f Resources/AppIcon.icns ]; then
  swift run -c release make-icon Resources/AppIcon.icns
fi

swift build -c "$CONFIG" --product Diskat "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" --product Diskat "${ARCHS[@]}" --show-bin-path)/Diskat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Diskat"
if ! otool -l "$APP/Contents/MacOS/Diskat" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/Diskat"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Big Sur needs the back-deployed Swift concurrency runtime bundled with the app.
mkdir -p "$APP/Contents/Frameworks"
SWIFT_LIB_ARGS=()
BACKDEPLOY_LIBS="$(dirname "$(xcrun --find swift)")/../lib/swift-5.5/macosx"
if [ -d "$BACKDEPLOY_LIBS" ]; then
  SWIFT_LIB_ARGS=(--source-libraries "$BACKDEPLOY_LIBS")
fi
xcrun swift-stdlib-tool --copy --scan-executable "$APP/Contents/MacOS/Diskat" \
  --platform macosx --destination "$APP/Contents/Frameworks" "${SWIFT_LIB_ARGS[@]}"
for LIB in "$APP"/Contents/Frameworks/*.dylib; do
  [ -e "$LIB" ] || continue
  if [ -n "${SIGN_ID:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$LIB"
  else
    codesign --force --sign - "$LIB"
  fi
done

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
ARCH="${ARCH:-universal}" scripts/verify-app.sh "$APP"

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
