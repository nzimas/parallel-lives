#!/bin/sh
set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-release}
cd "$project_directory"
swift build -c "$configuration"
binary_directory=$(cd "$project_directory" && swift build -c "$configuration" --show-bin-path)
app_bundle="$project_directory/dist/ParallelLives.app"
temporary_bundle="$project_directory/dist/ParallelLives.app.building"

rm -rf "$temporary_bundle"
mkdir -p "$temporary_bundle/Contents/MacOS"
mkdir -p "$temporary_bundle/Contents/Resources"

ditto "$binary_directory/Vascular" "$temporary_bundle/Contents/MacOS/ParallelLives"
ditto "$project_directory/Packaging/Info.plist" "$temporary_bundle/Contents/Info.plist"
ditto \
    "$project_directory/Packaging/ParallelLives.icns" \
    "$temporary_bundle/Contents/Resources/ParallelLives.icns"
ditto \
    "$binary_directory/Vascular_VascularMac.bundle" \
    "$temporary_bundle/Contents/Resources/Vascular_VascularMac.bundle"

printf 'APPL????' > "$temporary_bundle/Contents/PkgInfo"
codesign --force --deep --sign - "$temporary_bundle"
codesign --verify --deep --strict "$temporary_bundle"

if test -d "$app_bundle"; then
    rm -rf "$app_bundle"
fi
mv "$temporary_bundle" "$app_bundle"

echo "$app_bundle"
