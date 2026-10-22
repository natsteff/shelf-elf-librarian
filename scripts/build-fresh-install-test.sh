#!/bin/zsh
set -eu
cd "${0:A:h}/.."
sourceApp="$PWD/outputs/Shelf Elf Librarian.app"
testApp="$PWD/outputs/Shelf Elf Librarian Fresh Install Test.app"
[[ -d "$sourceApp" ]]
# Only replaces this generated artifact; test settings live in a separate support folder and preference suite.
if [[ -d "$testApp" ]]; then mv "$testApp" "$PWD/.build/Previous Fresh Install Test-$(date +%s).app"; fi
cp -R "$sourceApp" "$testApp"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.LibraryFiler.Alpha.fresh-test' "$testApp/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Shelf Elf Fresh Install Test' "$testApp/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Shelf Elf Fresh Install Test' "$testApp/Contents/Info.plist"
codesign --force --sign - "$testApp"
codesign --verify --strict "$testApp"
print "Built $testApp (separate preferences, profiles and history)"
