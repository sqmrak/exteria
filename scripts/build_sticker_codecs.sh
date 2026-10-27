#!/usr/bin/env bash
set -euo pipefail

: "${EXTERIA_TC:?set EXTERIA_TC to the ios toolchain bin directory}"
: "${EXTERIA_SDK_V7:?set EXTERIA_SDK_V7 to the armv7 sdk}"
: "${EXTERIA_SDK_V64:?set EXTERIA_SDK_V64 to the arm64 sdk}"
: "${EXTERIA_FFMPEG_SOURCE:?set EXTERIA_FFMPEG_SOURCE to ffmpeg 7.1.1 source}"
: "${EXTERIA_LIBVPX_SOURCE:?set EXTERIA_LIBVPX_SOURCE to libvpx 1.15.0 source}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${EXTERIA_VIDEO_BUILD:-$ROOT/build/video-ios}"
JOBS="${EXTERIA_JOBS:-4}"
mkdir -p "$STAGE"
STAGE="$(cd "$STAGE" && pwd)"
for source in "$EXTERIA_FFMPEG_SOURCE" "$EXTERIA_LIBVPX_SOURCE"; do
    test -f "$source/configure" || { echo "missing codec source: $source" >&2; exit 1; }
done
for slice in armv7 arm64; do
    if [[ "$slice" == armv7 ]]; then sdk="$EXTERIA_SDK_V7"; minimum=5.0; arch=arm; cpu=armv7;
    else sdk="$EXTERIA_SDK_V64"; minimum=7.0; arch=aarch64; cpu=generic; fi
    prefix="$STAGE/$slice"
    target_flags="-target $slice-apple-ios$minimum -isysroot $sdk -O2 -fPIC"
    # the ios 6 assert.h lacks the C11 spelling, while clang supports the intrinsic
    if [[ "$slice" == armv7 ]]; then target_flags="$target_flags -Dstatic_assert=_Static_assert"; fi
    mkdir -p "$prefix" "$STAGE/build-$slice-vpx" "$STAGE/build-$slice-ffmpeg"
    (
        cd "$STAGE/build-$slice-vpx"
        if [[ -f Makefile ]]; then make clean; fi
        # vp8 encode and decode serve the video calls, the stickers need only the vp9 decoder
        CC="$EXTERIA_TC/clang" CXX="$EXTERIA_TC/clang++" AR="$EXTERIA_TC/llvm-ar" LD="$EXTERIA_TC/clang" \
        CFLAGS="$target_flags" LDFLAGS="$target_flags -B$EXTERIA_TC" \
        "$EXTERIA_LIBVPX_SOURCE/configure" --target=generic-gnu --prefix="$prefix" \
            --extra-cflags="$target_flags" --extra-cxxflags="$target_flags -std=c++14 -stdlib=libc++ -fno-exceptions -fno-rtti -D_LIBCPP_DISABLE_AVAILABILITY" --enable-vp8 --enable-vp9 --disable-vp9-encoder --enable-realtime-only \
            --disable-vp9-highbitdepth --disable-examples --disable-tools --disable-docs --disable-unit-tests \
            --disable-webm-io --disable-libyuv --disable-multithread --enable-pic
        make -j"$JOBS" HAVE_GNU_STRIP=no
        # GNU strip rewrites a Mach-O archive's symbol index into an unreadable GNU index
        cp libvpx_g.a libvpx.a
        make install HAVE_GNU_STRIP=no
    )
    (
        cd "$STAGE/build-$slice-ffmpeg"
        if [[ -f ffbuild/config.mak ]]; then make distclean; fi
        PKG_CONFIG_PATH="$prefix/lib/pkgconfig" "$EXTERIA_FFMPEG_SOURCE/configure" \
            --prefix="$prefix" --target-os=darwin --arch="$arch" --cpu="$cpu" --enable-cross-compile \
            --cc="$EXTERIA_TC/clang" --cxx="$EXTERIA_TC/clang++" --ar="$EXTERIA_TC/llvm-ar" --ranlib="$EXTERIA_TC/llvm-ranlib" \
            --nm="$EXTERIA_TC/nm" --extra-cflags="$target_flags" --extra-ldflags="$target_flags -B$EXTERIA_TC" \
            --disable-everything --disable-autodetect --disable-asm --disable-network --disable-programs \
            --disable-doc --disable-debug --disable-swscale --disable-swresample --disable-avfilter --disable-avdevice \
            --disable-postproc --enable-pic --enable-small --enable-static --disable-shared --enable-libvpx \
            --enable-decoder=libvpx_vp9 --enable-demuxer=matroska --enable-parser=vp9 --pkg-config-flags=--static
        grep -q '^#define CONFIG_LIBVPX_VP9_DECODER 1$' config_components.h || { echo "ffmpeg did not enable the VP9 decoder" >&2; exit 1; }
        make -j"$JOBS"
        make install
    )
    cp "$EXTERIA_FFMPEG_SOURCE/COPYING.LGPLv2.1" "$prefix/FFmpeg-LGPLv2.1.txt"
    cp "$EXTERIA_LIBVPX_SOURCE/LICENSE" "$prefix/libvpx-license.txt"
    "$EXTERIA_TC/lipo" -info "$prefix/lib/libavcodec.a" "$prefix/lib/libavformat.a" "$prefix/lib/libavutil.a" "$prefix/lib/libvpx.a"
done
