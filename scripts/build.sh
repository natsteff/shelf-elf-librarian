#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/cache
swift build -c release --cache-path "$PWD/.build/cache" --disable-sandbox
.build/release/SafetyChecks
destinationApp="$PWD/../Shelf Elf Librarian.app"
# Always assemble a fresh bundle; do not retain resources from earlier branding.
bundleStage=$(mktemp -d "$PWD/.build/bundle.XXXXXX")
app="$bundleStage/Shelf Elf Librarian.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/LibraryFiler "$app/Contents/MacOS/LibraryFiler"
cp Info.plist "$app/Contents/Info.plist"
# Build a standard macOS icon family from the supplied original artwork.
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Branding/App-Icon-v3.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    sips -z "$pixels" "$pixels" Branding/App-Icon-v3.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/package-icon.py "$iconset" "$app/Contents/Resources/AppIcon-v3.icns"
sips -g format "$app/Contents/Resources/AppIcon-v3.icns"
cp Branding/In-App-Logo.png Branding/Minimal.png Branding/README-Logo.png "$app/Contents/Resources/"
cp Branding/Header-Portrait-White.png "$app/Contents/Resources/Header-Icon.png"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
file "$app/Contents/MacOS/LibraryFiler"
if [[ -e "$destinationApp" ]]; then
    mv "$destinationApp" "$bundleStage/Previous Shelf Elf.app"
fi
mv "$app" "$destinationApp"
touch "$destinationApp"
print "Built $destinationApp"
