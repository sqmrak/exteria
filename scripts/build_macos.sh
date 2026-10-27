#!/usr/bin/env bash
# builds the core and the ios test binaries from a clean checkout on macOS: a local toolchain,
# openssl for both slices, then scripts/core-ios.mk. the app bundle needs EXTERIA_API_ID and EXTERIA_API_HASH
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCAL="${EXTERIA_LOCAL:-$ROOT/local}"
TC="$LOCAL/toolchain/bin"
SDK_V7="${EXTERIA_SDK_V7:-$HOME/theos/sdks/iPhoneOS5.1.sdk}"
SDK_V64="${EXTERIA_SDK_V64:-$HOME/theos/sdks/iPhoneOS15.5.sdk}"
OPENSSL_VERSION="${EXTERIA_OPENSSL_VERSION:-3.5.9}"
OPENSSL_SHA256="${EXTERIA_OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"
OPENSSL_URL="${EXTERIA_OPENSSL_URL:-https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz}"
JOBS="$(sysctl -n hw.ncpu)"

log() { printf '\n== %s\n' "$*"; }
die() { echo "$*" >&2; exit 1; }

log "toolchain wrappers"
CLT_BIN="$(dirname "$(xcrun -f clang)")"
[[ -x "$CLT_BIN/clang" ]] || die "no clang in $CLT_BIN, install the command line tools"
LDID="${EXTERIA_LDID:-$HOME/theos/bin/ldid}"
[[ -x "$LDID" ]] || LDID="$(command -v ldid || true)"
mkdir -p "$TC"
for tool in clang clang++ lipo otool nm; do
    [[ -e "$CLT_BIN/$tool" ]] && ln -sfn "$CLT_BIN/$tool" "$TC/$tool"
done
# the makefiles call llvm-ar, the system one is ar
ln -sfn "$CLT_BIN/ar" "$TC/llvm-ar"
if [[ -x "$LDID" ]]; then ln -sfn "$LDID" "$TC/ldid"; else echo "note: no ldid, the app bundle cannot be signed here"; fi

log "iphoneos sdks"
for sdk in "$SDK_V7" "$SDK_V64"; do
    [[ -f "$sdk/usr/include/stdlib.h" ]] || die "missing iphoneos sdk: $sdk"
    echo "$sdk"
done

TARBALL="$LOCAL/src/openssl-${OPENSSL_VERSION}.tar.gz"
SRC="$LOCAL/src/openssl-${OPENSSL_VERSION}"

fetch_openssl() {
    mkdir -p "$LOCAL/src"
    if [[ ! -f "$TARBALL" ]]; then
        curl -fsSL -o "$TARBALL.part" "$OPENSSL_URL"
        mv "$TARBALL.part" "$TARBALL"
    fi
    # a wrong digest means a damaged or replaced download, so the file goes and the build stops
    local actual
    actual="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
    if [[ "$actual" != "$OPENSSL_SHA256" ]]; then
        rm -f "$TARBALL"
        die "openssl tarball sha256 is $actual, expected $OPENSSL_SHA256"
    fi
    if [[ ! -d "$SRC" ]]; then tar -xzf "$TARBALL" -C "$LOCAL/src"; fi
}

# configure target, sdk and minimum ios version per slice; openssl takes the sysroot from
# CROSS_TOP/SDKs/CROSS_SDK, so each slice gets its own CROSS_TOP with a link to its sdk
build_openssl() {
    local slice="$1" sdk="$2" min="$3" configure="$4"
    local prefix="$LOCAL/openssl/$slice"
    if [[ -f "$prefix/lib/libcrypto.a" ]]; then
        log "openssl $slice already at $prefix"
        return
    fi
    log "openssl ${OPENSSL_VERSION} for $slice"
    fetch_openssl
    local cross="$LOCAL/ios-sdks/$slice"
    mkdir -p "$cross/SDKs"
    ln -sfn "$sdk" "$cross/SDKs/$(basename "$sdk")"
    # a stale build tree keeps objects from an older -mios-version-min, so it starts empty
    rm -rf "$SRC/build-$slice"
    mkdir -p "$SRC/build-$slice"
    cd "$SRC/build-$slice"
    CC=clang CROSS_COMPILE="$CLT_BIN/" CROSS_TOP="$cross" CROSS_SDK="$(basename "$sdk")" \
        ../Configure "$configure" no-shared no-tests no-apps --prefix="$prefix" --libdir=lib \
        -mios-version-min="$min" >/dev/null
    make -j"$JOBS" build_libs CROSS_TOP="$cross" CROSS_SDK="$(basename "$sdk")" >/dev/null
    make install_dev CROSS_TOP="$cross" CROSS_SDK="$(basename "$sdk")" >/dev/null
    cd "$ROOT"
    lipo -info "$prefix/lib/libcrypto.a"
}
build_openssl armv7 "$SDK_V7" 5.0 ios-cross
build_openssl arm64 "$SDK_V64" 7.0 ios64-cross

log "core library and test binaries"
export EXTERIA_TC="$TC"
export EXTERIA_SDK_V7="$SDK_V7"
export EXTERIA_SDK_V64="$SDK_V64"
export EXTERIA_OPENSSL_V7="$LOCAL/openssl/armv7"
export EXTERIA_OPENSSL_V64="$LOCAL/openssl/arm64"
make -f scripts/core-ios.mk inspect -j"$JOBS"
