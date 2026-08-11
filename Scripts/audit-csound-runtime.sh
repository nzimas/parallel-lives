#!/bin/sh
set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_directory="$project_directory/Sources/VascularMac/Resources/Runtime"
framework_directory="$runtime_directory/Frameworks/CsoundLib64.framework"

test -x "$runtime_directory/bin/csound"
test -f "$framework_directory/Versions/6.0/CsoundLib64"
test -f "$framework_directory/Versions/6.0/Resources/Opcodes64/librtauhal.dylib"

unexpected=$(find "$runtime_directory" -type f \( -perm -111 -o -name '*.dylib' \) -print0 \
    | xargs -0 -n1 otool -L \
    | awk '/^[[:space:]]+\// { print $1 }' \
    | grep -Ev '^(/usr/lib/|/System/Library/|/Library/Frameworks/CsoundLib64.framework/CsoundLib64$)' \
    || true)

if test -n "$unexpected"; then
    echo "Unexpected external dependencies:"
    echo "$unexpected"
    exit 1
fi

size=$(du -sh "$runtime_directory" | awk '{ print $1 }')
echo "Csound runtime audit passed ($size)"
