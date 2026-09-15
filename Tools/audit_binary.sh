#!/bin/sh
# Step 06 phase 6.6 — the "no private API, no ad framework" check from the
# checklist, on a built .app (Debug, or an exported archive's Payload/*.app).
#
#   Tools/audit_binary.sh path/to/Caroullage.app
#
# Lists every Mach-O the bundle ships (the app, its debug dylib when built for
# Debug, every .appex) with the frameworks each links, and fails if any links
# a PrivateFrameworks path, AdSupport or AppTrackingTransparency — or if otool
# cannot read it. A Debug test host also carries XCTest and preview dylibs;
# those are not the app's and are skipped. Run it on the archive before every
# submission; App Review runs the same scan.
set -eu
APP="${1:?usage: audit_binary.sh path/to/App.app}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
status=0
count=0
find "$APP" -type f \( -perm -u+x -o -name '*.dylib' \) | sort | while read -r bin; do
  case "$bin" in
    *.xctest/*|*/Frameworks/XC*|*/Frameworks/Testing.framework/*|*/Frameworks/libXCTest*|*__preview.dylib) continue ;;
  esac
  file "$bin" | grep -q 'Mach-O' || continue
  echo "== ${bin#$APP/}"
  if ! links=$(xcrun otool -L "$bin" 2>&1); then
    echo "   FAIL: otool could not read it: $links"; exit 1
  fi
  echo "$links" | tail -n +2 | awk '{print $1}' | sed 's|.*/||' | sort | tr '\n' ' '; echo
  if echo "$links" | grep -qE 'PrivateFrameworks|AdSupport|AppTrackingTransparency'; then
    echo "   FAIL: $(echo "$links" | grep -E 'PrivateFrameworks|AdSupport|AppTrackingTransparency')"; exit 1
  fi
  echo "   ok: no private, ad or tracking framework"
done
