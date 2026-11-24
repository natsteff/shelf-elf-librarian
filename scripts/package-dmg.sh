#!/bin/zsh
# Package the already-built main application; never include local settings or work records.
set -eu
cd "${0:A:h}/.."
app="$PWD/outputs/Shelf Elf Librarian.app"
[[ -d "$app" ]] || { print -u2 'Run scripts/build.sh first.'; exit 1; }
codesign --verify --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
label=$(/usr/libexec/PlistBuddy -c 'Print :ShelfElfReleaseLabel' "$app/Contents/Info.plist")
releaseSlug=$(print -r -- "$label" | tr '[:upper:] ' '[:lower:]-')
[[ "$version" == [0-9]* && "$releaseSlug" == beta-[0-9]* ]] || { print -u2 'Review the release version/label before packaging.'; exit 1; }
releaseDir="$PWD/outputs/releases/$releaseSlug"
mkdir -p "$releaseDir"
dmg="$releaseDir/Shelf-Elf-Librarian-$version-$releaseSlug-arm64.dmg"
[[ ! -e "$dmg" ]] || { print -u2 "Refusing to overwrite $dmg"; exit 1; }
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app" "$stage/Shelf Elf Librarian.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Install and Upgrade.txt" <<'TEXT'
Shelf Elf Librarian — Install or upgrade

1. Quit every running copy of Shelf Elf Librarian.
2. Drag Shelf Elf Librarian onto Applications. Choose Replace for an upgrade.
3. Eject this disk image, then open Shelf Elf Librarian from Applications.
4. Confirm the version in the app header and check your profiles and settings.

Before upgrading, use Tools > Export Settings in your existing app to save a
portable backup. The main app retains the same bundle identifier and settings
storage between releases. Replacing the application does not reset settings.
Do not use a Fresh Install Test edition as your regular app; it has separate data.

This beta is ad hoc signed, not Developer ID signed or notarized. macOS may
require approval in System Settings > Privacy & Security. No automatic updater
is included. Download future updates from the repository's GitHub Releases page
and repeat these steps. Full license and usage notice are included in the app.
TEXT
hdiutil create -volname "Shelf Elf $label" -srcfolder "$stage" -format UDZO -ov "$dmg"
hdiutil verify "$dmg"
(cd "$releaseDir" && shasum -a 256 "${dmg:t}" > SHA256SUMS.txt)
print "Packaged $dmg"
