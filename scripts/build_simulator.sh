#!/usr/bin/env bash
# builds Exteria.app for the iOS Simulator on a Mac with Xcode and zips it, as Appetize and simctl take it: openssl,
# libvpx and ffmpeg for each architecture of the simulator, the app through scripts/app-sim.mk, one binary of both.
# EXTERIA_API_ID and EXTERIA_API_HASH are the telegram api credentials, as for the device build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCAL="${EXTERIA_SIM_LOCAL:-$ROOT/local/sim}"
OUT="${EXTERIA_SIM_BUILD:-$ROOT/build/sim}"
MIN="${EXTERIA_SIM_MIN:-14.0}"
ARCHS="${EXTERIA_SIM_ARCHS:-arm64 x86_64}"
JOBS="$(sysctl -n hw.ncpu)"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
FFMPEG_VERSION=7.1.1
LIBVPX_VERSION=1.15.0

log() { printf '\n== %s\n' "$*"; }
die() { echo "$*" >&2; exit 1; }

: "${EXTERIA_API_ID:?set EXTERIA_API_ID}"
: "${EXTERIA_API_HASH:?set EXTERIA_API_HASH}"

log "toolchain"
TC="$LOCAL/toolchain/bin"
mkdir -p "$TC"
for tool in clang clang++ lipo otool nm ar ranlib; do ln -sfn "$(xcrun -f "$tool")" "$TC/$tool"; done
ln -sfn "$(xcrun -f ar)" "$TC/llvm-ar"
ln -sfn "$(xcrun -f ranlib)" "$TC/llvm-ranlib"
echo "$SDK"
command -v pkg-config >/dev/null || brew install pkg-config

fetch() {
    local url="$1" file="$2"
    mkdir -p "$LOCAL/src"
    [[ -f "$LOCAL/src/$file" ]] || curl -fsSL --retry 3 -o "$LOCAL/src/$file" "$url"
}
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" "openssl-$OPENSSL_VERSION.tar.gz"
[[ "$(shasum -a 256 "$LOCAL/src/openssl-$OPENSSL_VERSION.tar.gz" | cut -d' ' -f1)" == "$OPENSSL_SHA256" ]] || die "openssl tarball digest mismatch"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "ffmpeg-$FFMPEG_VERSION.tar.xz"
fetch "https://github.com/webmproject/libvpx/archive/refs/tags/v$LIBVPX_VERSION.tar.gz" "libvpx-$LIBVPX_VERSION.tar.gz"
for archive in "openssl-$OPENSSL_VERSION.tar.gz" "ffmpeg-$FFMPEG_VERSION.tar.xz" "libvpx-$LIBVPX_VERSION.tar.gz"; do
    dir="$LOCAL/src/${archive%.tar.*}"
    [[ -d "$dir" ]] || tar -xf "$LOCAL/src/$archive" -C "$LOCAL/src"
done

for arch in $ARCHS; do
    flags="-target $arch-apple-ios$MIN-simulator -isysroot $SDK"
    deps="$LOCAL/$arch"
    if [[ "$arch" == arm64 ]]; then ossl_target=darwin64-arm64-cc; ff_arch=aarch64; else ossl_target=darwin64-x86_64-cc; ff_arch=x86_64; fi

    if [[ ! -f "$deps/openssl/lib/libcrypto.a" ]]; then
        log "openssl $arch"
        rm -rf "$LOCAL/src/openssl-$OPENSSL_VERSION/build-$arch"
        mkdir -p "$LOCAL/src/openssl-$OPENSSL_VERSION/build-$arch"
        (
            cd "$LOCAL/src/openssl-$OPENSSL_VERSION/build-$arch"
            CC="$TC/clang $flags" ../Configure "$ossl_target" no-shared no-tests no-apps no-asm no-async \
                --prefix="$deps/openssl" --libdir=lib >/dev/null
            make -j"$JOBS" build_libs >/dev/null
            make install_dev >/dev/null
        )
    fi

    if [[ ! -f "$deps/video/lib/libvpx.a" ]]; then
        log "libvpx $arch"
        rm -rf "$LOCAL/build-$arch-vpx" && mkdir -p "$LOCAL/build-$arch-vpx"
        (
            cd "$LOCAL/build-$arch-vpx"
            CC="$TC/clang" CXX="$TC/clang++" AR="$TC/llvm-ar" LD="$TC/clang" \
            CFLAGS="$flags -O2 -fPIC" LDFLAGS="$flags" \
            "$LOCAL/src/libvpx-$LIBVPX_VERSION/configure" --target=generic-gnu --prefix="$deps/video" \
                --extra-cflags="$flags -O2 -fPIC" --extra-cxxflags="$flags -O2 -fPIC -std=c++14 -stdlib=libc++ -fno-exceptions -fno-rtti" \
                --enable-vp8 --enable-vp9 --disable-vp9-encoder --enable-realtime-only --disable-vp9-highbitdepth \
                --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-webm-io --disable-libyuv \
                --disable-multithread --enable-pic >/dev/null
            make -j"$JOBS" HAVE_GNU_STRIP=no >/dev/null
            cp libvpx_g.a libvpx.a
            make install HAVE_GNU_STRIP=no >/dev/null
        )
    fi

    if [[ ! -f "$deps/video/lib/libavcodec.a" ]]; then
        log "ffmpeg $arch"
        rm -rf "$LOCAL/build-$arch-ffmpeg" && mkdir -p "$LOCAL/build-$arch-ffmpeg"
        (
            cd "$LOCAL/build-$arch-ffmpeg"
            PKG_CONFIG_PATH="$deps/video/lib/pkgconfig" "$LOCAL/src/ffmpeg-$FFMPEG_VERSION/configure" \
                --prefix="$deps/video" --target-os=darwin --arch="$ff_arch" --cpu=generic --enable-cross-compile \
                --cc="$TC/clang" --cxx="$TC/clang++" --ar="$TC/llvm-ar" --ranlib="$TC/llvm-ranlib" --nm="$TC/nm" \
                --extra-cflags="$flags -O2 -fPIC -I$deps/video/include" --extra-ldflags="$flags -L$deps/video/lib" \
                --disable-everything --disable-autodetect --disable-asm --disable-network --disable-programs \
                --disable-doc --disable-debug --disable-swscale --disable-avfilter --disable-avdevice \
                --disable-postproc --enable-pic --enable-small --enable-static --disable-shared --enable-libvpx \
                --enable-swresample --enable-protocol=file --enable-decoder=libvpx_vp9,flac --enable-demuxer=matroska,flac \
                --enable-parser=vp9,flac --pkg-config-flags=--static >/dev/null
            grep -q '^#define CONFIG_LIBVPX_VP9_DECODER 1$' config_components.h || die "ffmpeg did not enable the VP9 decoder"
            make -j"$JOBS" >/dev/null
            make install >/dev/null
        )
    fi

    log "app $arch"
    make -f scripts/app-sim.mk sim-binary -j"$JOBS" \
        EXTERIA_TC="$TC" EXTERIA_SIM_ARCH="$arch" EXTERIA_SIM_MIN="$MIN" EXTERIA_SIM_SDK="$SDK" \
        EXTERIA_OPENSSL_V64="$deps/openssl" EXTERIA_VIDEO_V64="$deps/video" EXTERIA_IOS_BUILD="$OUT/$arch" \
        EXTERIA_API_ID="$EXTERIA_API_ID" EXTERIA_API_HASH="$EXTERIA_API_HASH"
done

log "bundle"
APP="$OUT/Exteria.app"
rm -rf "$APP"
mkdir -p "$APP"
binaries=()
for arch in $ARCHS; do binaries+=("$OUT/$arch/arm64/Exteria"); done
lipo -create "${binaries[@]}" -output "$APP/Exteria"
lipo -info "$APP/Exteria"
cp packaging/Info.plist "$APP/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$APP/Info.plist"; }
plist "Set :MinimumOSVersion $MIN"
plist "Delete :UIRequiredDeviceCapabilities" || true
plist "Delete :CFBundleSupportedPlatforms" || true
plist "Add :CFBundleSupportedPlatforms array"
plist "Add :CFBundleSupportedPlatforms:0 string iPhoneSimulator"
plist "Delete :DTPlatformName" || true
plist "Add :DTPlatformName string iphonesimulator"
plist "Delete :DTSDKName" || true
plist "Add :DTSDKName string iphonesimulator$(xcrun --sdk iphonesimulator --show-sdk-version)"
# shellcheck disable=SC2046
cp $(make -s -f scripts/app-sim.mk print-resources EXTERIA_TC="$TC" EXTERIA_SIM_SDK="$SDK") "$APP/"
mkdir -p "$APP/exteria-original-icons"
cp resources/icons/Icon*.png "$APP/exteria-original-icons/"
for dir in resources/localization/*.lproj; do mkdir -p "$APP/$(basename "$dir")" && cp "$dir/Localizable.strings" "$APP/$(basename "$dir")/"; done
codesign --force --sign - --timestamp=none "$APP/Exteria"
codesign --force --sign - --timestamp=none "$APP"

ZIP="$OUT/Exteria-simulator.zip"
rm -f "$ZIP"
(cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent Exteria.app "$ZIP")
log "done: $ZIP"
