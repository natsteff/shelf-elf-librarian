#!/bin/zsh
set -eu
cd "${0:A:h}/.."
python3 scripts/prepare-screenshot-demo.py
sourceApp="$PWD/outputs/Shelf Elf Librarian.app"
demoApp="$PWD/outputs/Shelf Elf Screenshot Demo.app"
if [[ -d "$demoApp" ]]; then
    mv "$demoApp" "$PWD/.build/Previous Screenshot Demo-$(date +%s).app"
fi
cp -R "$sourceApp" "$demoApp"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.LibraryFiler.screenshot-demo.fresh-test' "$demoApp/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ShelfElfScreenshotRoot string /private/tmp/Shelf Elf Demo' "$demoApp/Contents/Info.plist"
codesign --force --sign - "$demoApp"
codesign --verify --strict "$demoApp"
print "Built $demoApp (separate screenshot-only profiles, preferences and journal)"
