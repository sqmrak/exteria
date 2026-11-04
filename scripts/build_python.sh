#!/usr/bin/env bash
# builds libpython3.11.a for armv7 (ios 5) and arm64 (ios 7) with the extension modules linked in,
# and stages the pure python standard library the plugin host needs
set -euo pipefail

: "${EXTERIA_TC:?set EXTERIA_TC to the ios toolchain bin directory}"
: "${EXTERIA_SDK_V7:?set EXTERIA_SDK_V7 to a legacy iphoneos sdk}"
: "${EXTERIA_SDK_V64:?set EXTERIA_SDK_V64 to an arm64 iphoneos sdk}"
: "${EXTERIA_PYTHON_TARBALL:?set EXTERIA_PYTHON_TARBALL to Python-3.11.9.tar.xz}"
: "${EXTERIA_OPENSSL_V7:?set EXTERIA_OPENSSL_V7 to the armv7 openssl prefix}"
: "${EXTERIA_OPENSSL_V64:?set EXTERIA_OPENSSL_V64 to the arm64 openssl prefix}"
# the roots plugins trust for https: the mozilla bundle of curl.se, checked against its published sha-256 by whoever fetched it
: "${EXTERIA_PYTHON_CACERT:?set EXTERIA_PYTHON_CACERT to a cacert.pem}"
test -s "$EXTERIA_PYTHON_CACERT" || { echo "missing $EXTERIA_PYTHON_CACERT" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${EXTERIA_PYTHON_BUILD:-$root/build/python}"
sha=9b1e896523fc510691126c864406d9360a3d1e986acbda59cda57b5abda45b87
jobs="${EXTERIA_JOBS:-$(nproc)}"
# the host python must be 3.11 to run the freeze and regen steps of the cross build
host_py="${EXTERIA_PYTHON_HOST:-$out/host/install/bin/python3.11}"

echo "$sha  $EXTERIA_PYTHON_TARBALL" | sha256sum -c - >/dev/null || { echo "bad sha256 of $EXTERIA_PYTHON_TARBALL" >&2; exit 1; }
# the ios toolchain's cc cannot build host tools, keep it off the path of the host steps
host_path=/usr/local/bin:/usr/bin:/bin

src="$out/src"
if [ ! -f "$src/.patched" ]; then
  rm -rf "$src"
  mkdir -p "$src"
  tar -xJf "$EXTERIA_PYTHON_TARBALL" -C "$src" --strip-components=1
  patch -p1 -d "$src" < "$root/third_party/python/darwin-cross.patch"
  touch "$src/.patched"
fi

if [ ! -x "$host_py" ]; then
  mkdir -p "$out/host"
  (cd "$out/host" && PATH=$host_path "$src/configure" --prefix="$out/host/install" >configure.log 2>&1 \
    && PATH=$host_path make -j"$jobs" >make.log 2>&1 && PATH=$host_path make install >install.log 2>&1)
fi

# modules the plugin host does not want, or that need a library or a flag set the static link here does not carry:
# _decimal (python falls back to _pydecimal), pyexpat and _elementtree (bundled expat flags), _uuid, and _posixsubprocess,
# which needs fork(), marked unavailable in the arm64 sdk. subprocess is out for the same reason on both slices
drop='^(_testbuffer|_testinternalcapi|_testcapi|_testclinic|_xxtestfuzz|_testimportmultiple|_testmultiphase|_ctypes_test|xxlimited|xxlimited_35|nis|_scproxy|_xxsubinterpreters|audioop|_bz2|_lzma|termios|_posixshmem|_multiprocessing|syslog|_posixsubprocess|_decimal|pyexpat|_elementtree|_uuid) '

build_arch() {
  local name="$1" target="$2" sdk="$3" arch_cache="$4" openssl="$5"
  local dir="$out/$name"
  mkdir -p "$dir"
  cd "$dir"
  local cc="$EXTERIA_TC/clang -B$EXTERIA_TC -target $target -isysroot $sdk"
  # these are absent from the libsystem of ios 5 to 9, configure would find them in the newer sdk
  cat > config.site <<CFG
ac_cv_file__dev_ptmx=no
ac_cv_file__dev_ptc=no
ac_cv_buggy_getaddrinfo=no
ac_cv_func_sendfile=no
ac_cv_func_clock_gettime=no
ac_cv_func_clock_getres=no
ac_cv_func_clock_settime=no
ac_cv_func_getentropy=no
ac_cv_func_utimensat=no
ac_cv_func_futimens=no
ac_cv_func_preadv=no
ac_cv_func_pwritev=no
ac_cv_func_fdopendir=no
ac_cv_func_mkfifoat=no
ac_cv_func_mknodat=no
ac_cv_func_system=no
ac_cv_func_posix_spawn=yes
ac_cv_func_posix_spawnp=yes
$arch_cache
CFG
  # an empty pkg-config path keeps host libraries (libb2, zlib of the build machine) out of the ios build
  CONFIG_SITE="$PWD/config.site" PATH="$host_path:$EXTERIA_TC" PKG_CONFIG_LIBDIR=/nonexistent PKG_CONFIG_PATH= "$src/configure" \
    --host=arm-apple-darwin --build="$(uname -m)-unknown-linux-gnu" \
    --with-build-python="$host_py" --disable-shared --without-ensurepip --disable-ipv6 \
    --prefix="$dir/install" READELF=true \
    CC="$cc" CPP="$cc -E" AR="$EXTERIA_TC/llvm-ar" RANLIB="$EXTERIA_TC/llvm-ranlib" \
    CFLAGS="-O2" >configure.log 2>&1
  # link the extension modules into libpython: dlopen of .so modules is not an option inside the app.
  # makesetup reads Setup.local, so the static list goes there
  python3 - "$PWD/Modules/Setup.stdlib" "$PWD/Modules/Setup.local" "$drop" <<'PY'
import re, sys
src, dst, drop = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
out = ['*static*\n']
shared = False
for line in open(src):
    if line.strip() == '*shared*':
        shared = True
        continue
    if not shared or line.startswith('#') or not line.strip() or drop.match(line):
        continue
    out.append(line)
open(dst, 'w').write(''.join(out))
PY
  # ssl and the hashes of openssl: libssl and libcrypto come from the app's own link, the same static copies the core uses
  printf '_ssl _ssl.c -I%s/include\n_hashlib _hashopenssl.c -I%s/include\n' "$openssl" "$openssl" >> Modules/Setup.local
  PATH="$host_path:$EXTERIA_TC" make -j"$jobs" libpython3.11.a >make.log 2>&1
  test -s libpython3.11.a
}

# a library that is built stays; EXTERIA_PYTHON_REBUILD=1 builds both again, as a changed flag or patch needs
if [ "${EXTERIA_PYTHON_REBUILD:-0}" = 1 ] || [ ! -s "$out/armv7/libpython3.11.a" ]; then
  rm -rf "$out/armv7"
  build_arch armv7 armv7-apple-ios5.0 "$EXTERIA_SDK_V7" "" "$EXTERIA_OPENSSL_V7"
fi
if [ "${EXTERIA_PYTHON_REBUILD:-0}" = 1 ] || [ ! -s "$out/arm64/libpython3.11.a" ]; then
  rm -rf "$out/arm64"
  build_arch arm64 arm64-apple-ios7.0 "$EXTERIA_SDK_V64" "" "$EXTERIA_OPENSSL_V64"
fi

# one prefix per slice for the app build: headers (pyconfig.h differs by slice) and the static library
for arch in armv7 arm64; do
  prefix="$out/prefix-$arch"
  rm -rf "$prefix"
  mkdir -p "$prefix/include/python3.11" "$prefix/lib"
  cp -R "$src/Include/." "$prefix/include/python3.11/"
  cp "$out/$arch/pyconfig.h" "$prefix/include/python3.11/pyconfig.h"
  cp "$out/$arch/libpython3.11.a" "$prefix/lib/"
done

# what goes into the app bundle under python/: the pure python standard library without tests, gui and tools the app
# cannot run, the shim for the java side, and the exteraless sdk. the stdlib ships as bytecode only, the plugin side
# keeps its sources for tracebacks and its bytecode never checks them, since the files in a bundle do not change
bundle="$out/bundle/python"
rm -rf "$out/bundle"
mkdir -p "$bundle/stdlib" "$bundle/shim" "$bundle/sdk"
tar -C "$src/Lib" --exclude=test --exclude=tests --exclude=__pycache__ --exclude=idlelib --exclude=tkinter \
  --exclude=turtledemo --exclude=lib2to3 --exclude=ensurepip --exclude=site-packages --exclude=pydoc_data \
  --exclude=distutils --exclude=multiprocessing -cf - . | tar -C "$bundle/stdlib" -xf -
"$host_py" -m compileall -q -b -f "$bundle/stdlib"
find "$bundle/stdlib" -name '*.py' -delete
cp -R "$root/python/shim/." "$bundle/shim/"
cp -R "$root/third_party/exteraless/." "$bundle/sdk/"
cp "$EXTERIA_PYTHON_CACERT" "$bundle/cacert.pem"
rm -f "$bundle/sdk/PATCHES"
# bytecode that host runs left in the source tree is of another python and mtime checked, the bundle gets its own
find "$bundle/shim" "$bundle/sdk" -name __pycache__ -type d -prune -exec rm -rf {} +
"$host_py" -m compileall -q --invalidation-mode unchecked-hash "$bundle/shim" "$bundle/sdk"
echo "python: prefixes $out/prefix-armv7 $out/prefix-arm64, bundle $bundle"
