#!/bin/sh
# keeps a copy of a built binary under build/symbols, named by the build ids of its slices, so a crash log that names a build can be read later.
# the id a crash log prints is the LC_UUID of the slice, as 32 hex digits
set -eu
binary="$1"
toolchain="${EXTERIA_TC:?set EXTERIA_TC}"
name=""
for arch in armv7 arm64; do
    id=$("$toolchain/otool" -arch "$arch" -l "$binary" | awk '/LC_UUID/ {found = 1} found && /uuid/ {print $2; exit}' | tr -d '-' | tr 'A-F' 'a-f')
    [ -n "$id" ] || { echo "no uuid for $arch in $binary" >&2; exit 1; }
    name="$name-$id"
done
directory="$(dirname "$0")/../build/symbols"
mkdir -p "$directory"
cp "$binary" "$directory/Exteria$name"
