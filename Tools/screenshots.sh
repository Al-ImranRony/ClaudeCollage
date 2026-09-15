#!/bin/sh
# Step 06 phase 6.7 — the App Store screenshot matrix.
#
#   Tools/screenshots.sh [device ...]          # default: the two below
#   LANGUAGES="en ja" Tools/screenshots.sh     # a subset of the eleven
#
# For each device and language: boots the simulator, runs
# AppStoreScreenshotUITests with SCREENSHOT_LANGUAGE set (the test launches
# the app in that language with -ScreenshotMode, which fills the editors with
# the bundled sample photography), exports the attachments, and frames each
# scene with its caption from Marketing/Screenshots/captions.json into
# Marketing/Screenshots/<device>/<lang>/<n>-<scene>.png — the exact device
# pixel size App Store Connect wants. Never run alongside another simulator
# job. Output is gitignored; upload from the folder.
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
LANGUAGES="${LANGUAGES:-en es fr de pt-BR ja ko zh-Hans hi it ar}"
DEVICES="$*"
[ -n "$DEVICES" ] || DEVICES="iPhone 16 Pro Max|iPad Pro 13-inch (M4)"
WORK="${SCREENSHOT_WORK:-$(mktemp -d)}"
OUT="Marketing/Screenshots"
mkdir -p "$WORK"

xcodegen generate >/dev/null
echo "$DEVICES" | tr '|' '\n' | while read -r device; do
  [ -n "$device" ] || continue
  slug=$(echo "$device" | tr -c 'A-Za-z0-9\n' '-' | sed 's/-*$//')
  udid=$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')
  [ -n "$udid" ] || { echo "no simulator named '$device'"; exit 1; }
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  for lang in $LANGUAGES; do
    bundle="$WORK/$slug-$lang.xcresult"
    rm -rf "$bundle" "$WORK/$slug-$lang"
    echo "== $device · $lang"
    # TEST_RUNNER_* reaches the test runner's environment only when set in
    # xcodebuild's own environment — as a trailing argument it is a build
    # setting, and the app launches in English with the right captions.
    TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" xcodebuild test -project Caroullage.xcodeproj \
      -scheme "Caroullage (Dev)" -destination "id=$udid" \
      -only-testing:CaroullageUITests/AppStoreScreenshotUITests -derivedDataPath "$WORK/dd" \
      -resultBundlePath "$bundle" > "$WORK/$slug-$lang.log" 2>&1 \
      || { echo "   test failed — see $WORK/$slug-$lang.log"; continue; }
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$WORK/$slug-$lang" >/dev/null 2>&1
    python3 - "$WORK/$slug-$lang" "$OUT/$slug/$lang" "$lang" <<'PY'
import json, os, subprocess, sys
src, out, lang = sys.argv[1], sys.argv[2], sys.argv[3]
captions = json.load(open('Marketing/Screenshots/captions.json'))
manifest = json.load(open(os.path.join(src, 'manifest.json')))
for t in manifest:
    for a in t.get('attachments', []):
        n = a.get('suggestedHumanReadableName', '')
        if not n.startswith('store-'): continue
        scene = n.split('_')[0][len('store-'):]          # "2-shapes"
        caption = captions.get(scene, {}).get(lang) or captions.get(scene, {}).get('en', '')
        subprocess.run(['swift', 'Tools/ScreenshotFramer/main.swift', os.path.join(src, a['exportedFileName']),
                        caption, os.path.join(out, scene + '.png')], check=True)
        print('   ', os.path.join(out, scene + '.png'))
PY
  done
done
echo "done → $OUT"
