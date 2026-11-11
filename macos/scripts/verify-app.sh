#!/bin/bash
# Verify a distributable bundle, including its macOS floor and back-deployed runtime.
set -euo pipefail
APP="${1:?Usage: verify-app.sh /path/to/Diskat.app}"
BIN="$APP/Contents/MacOS/Diskat"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

case "${ARCH:-universal}" in
  universal) lipo "$BIN" -verify_arch arm64 x86_64 ;;
  x86_64|arm64) test "$(lipo -archs "$BIN")" = "$ARCH" ;;
  *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac

otool -arch all -l "$BIN" | awk -v minimum="$MIN_OS" '
  $1 == "minos" { found = 1; if ($2 != minimum) mismatch = 1 }
  END { if (!found || mismatch) exit 1 }
'
if otool -L "$BIN" | grep -q '@rpath/libswift_Concurrency.dylib'; then
  test -f "$APP/Contents/Frameworks/libswift_Concurrency.dylib"
  otool -l "$BIN" | grep -q '@executable_path/../Frameworks'
fi
codesign --verify --deep --strict --verbose=1 "$APP"
echo "Verified: $(lipo -archs "$BIN"), macOS $MIN_OS+"
