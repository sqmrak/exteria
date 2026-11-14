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
: "${EXTERIA_PYTHON_WHEELS:?set EXTERIA_PYTHON_WHEELS to a directory with the wheels of third_party/python/wheels.sha256}"
: "${EXTERIA_PYTHON_SOURCES:?set EXTERIA_PYTHON_SOURCES to a directory with the archives of third_party/python/sources.sha256}"
test -s "$EXTERIA_PYTHON_CACERT" || { echo "missing $EXTERIA_PYTHON_CACERT" >&2; exit 1; }
root0="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$EXTERIA_PYTHON_SOURCES" && grep -v '^#' "$root0/third_party/python/sources.sha256" | sha256sum -c --quiet -) || { echo "bad or missing archive in $EXTERIA_PYTHON_SOURCES" >&2; exit 1; }

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
# _decimal (python falls back to _pydecimal), _uuid, and _posixsubprocess, which needs fork(), marked unavailable in the arm64 sdk: python/shim/_posixsubprocess.py
# starts the programs of subprocess with posix_spawn instead. _bz2, _lzma, pyexpat, _elementtree and _sqlite3 are dropped from the list of the
# configure step and given back below, with the flags and the libraries of this build
drop='^(_testbuffer|_testinternalcapi|_testcapi|_testclinic|_xxtestfuzz|_testimportmultiple|_testmultiphase|_ctypes_test|xxlimited|xxlimited_35|nis|_scproxy|_xxsubinterpreters|audioop|_bz2|_lzma|termios|_posixshmem|_multiprocessing|syslog|_posixsubprocess|_decimal|pyexpat|_elementtree|_uuid|_sqlite3) '

# bzip2, xz and sqlite from source, static, for one slice: the libraries of the sdks are missing on ios 5 (liblzma) or older than python 3.11 asks (sqlite).
# the objects end up in libexteria_pyext.a, which the app links after libpython
build_ext() {
  local name="$1" cc="$2"
  local ext="$out/ext-$name"
  rm -rf "$ext"
  mkdir -p "$ext/bzip2" "$ext/sqlite" "$ext/xz"
  tar -xzf "$EXTERIA_PYTHON_SOURCES/bzip2-1.0.8.tar.gz" -C "$ext/bzip2" --strip-components=1
  (cd "$ext/bzip2" && for f in blocksort huffman crctable randtable compress decompress bzlib; do $cc -O2 -D_FILE_OFFSET_BITS=64 -c $f.c -o $f.o; done \
    && "$EXTERIA_TC/llvm-ar" rcs libbz2.a blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o)
  "$host_py" - "$EXTERIA_PYTHON_SOURCES/sqlite-amalgamation-3460100.zip" "$ext/sqlite" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for info in archive.infolist():
        base = info.filename.rsplit("/", 1)[-1]
        if base in ("sqlite3.c", "sqlite3.h", "sqlite3ext.h"):
            with open(sys.argv[2] + "/" + base, "wb") as out:
                out.write(archive.read(info))
PY
  # no extension loading (dlopen is not an option in the app), one connection per thread unless python asks otherwise
  (cd "$ext/sqlite" && $cc -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_USE_URI=1 -DSQLITE_ENABLE_FTS5=1 \
    -DSQLITE_ENABLE_RTREE=1 -c sqlite3.c -o sqlite3.o && "$EXTERIA_TC/llvm-ar" rcs libsqlite3.a sqlite3.o)
  tar -xJf "$EXTERIA_PYTHON_SOURCES/xz-5.4.6.tar.xz" -C "$ext/xz" --strip-components=1
  # threads off: python's _lzma uses the single thread coders, and ios 5 has no use for a thread pool in a decoder
  (cd "$ext/xz" && PATH="$host_path:$EXTERIA_TC" ./configure --host=arm-apple-darwin --build="$(uname -m)-unknown-linux-gnu" --disable-shared --enable-static \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --disable-nls --disable-threads --disable-assembler \
    CC="$cc" AR="$EXTERIA_TC/llvm-ar" RANLIB="$EXTERIA_TC/llvm-ranlib" CFLAGS="-O2" >configure.log 2>&1 \
    && PATH="$host_path:$EXTERIA_TC" make -C src/liblzma -j"$jobs" >make.log 2>&1)
  test -s "$ext/xz/src/liblzma/.libs/liblzma.a"
  printf 'create %s/libexteria_pyext.a\naddlib %s/bzip2/libbz2.a\naddlib %s/sqlite/libsqlite3.a\naddlib %s/xz/src/liblzma/.libs/liblzma.a\nsave\nend\n' \
    "$ext" "$ext" "$ext" "$ext" | "$EXTERIA_TC/llvm-ar" -M
}

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
  build_ext "$name" "$cc"
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
  # the modules the drop list took out, with the bundled expat and the libraries built above. makesetup takes any line with an equals sign for a macro, so
  # the module name of _sqlite3 comes in through a header that is force included
  printf '#define MODULE_NAME "sqlite3"\n' > "$out/ext-$name/sqlite/exteria_module_name.h"
  printf '%s\n' \
    "_bz2 _bz2module.c -I$dir/../ext-$name/bzip2" \
    "_lzma _lzmamodule.c -I$dir/../ext-$name/xz/src/liblzma/api" \
    'pyexpat pyexpat.c expat/xmlparse.c expat/xmlrole.c expat/xmltok.c -I$(srcdir)/Modules/expat -DUSE_PYEXPAT_CAPI -DXML_DEV_URANDOM' \
    '_elementtree _elementtree.c -I$(srcdir)/Modules/expat -DUSE_PYEXPAT_CAPI' \
    "_sqlite3 _sqlite/blob.c _sqlite/connection.c _sqlite/cursor.c _sqlite/microprotocols.c _sqlite/module.c _sqlite/prepare_protocol.c _sqlite/row.c _sqlite/statement.c _sqlite/util.c -I$dir/../ext-$name/sqlite -Xcompiler -include -Xcompiler $dir/../ext-$name/sqlite/exteria_module_name.h" \
    >> Modules/Setup.local
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
  cp "$out/ext-$arch/libexteria_pyext.a" "$prefix/lib/"
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
# the libraries a plugin may import, from wheels whose hashes are pinned in the repository. bytecode only, like the stdlib: yt-dlp is 22 MB of source
mkdir -p "$bundle/lib"
(cd "$EXTERIA_PYTHON_WHEELS" && grep -v '^#' "$root/third_party/python/wheels.sha256" | sha256sum -c --quiet -)
grep -v '^#' "$root/third_party/python/wheels.sha256" | while read -r _hash wheel; do
  "$host_py" - "$EXTERIA_PYTHON_WHEELS/$wheel" "$bundle/lib" <<'PY'
import sys, zipfile
wheel, target = sys.argv[1:3]
with zipfile.ZipFile(wheel) as archive:
    for info in archive.infolist():
        name = info.filename
        # the code and the licenses; scripts, man pages and completions of the .data folder are not needed
        if name.startswith("/") or ".." in name.split("/") or ".data/" in name or name.endswith("/"):
            continue
        if ".dist-info/" in name and "/licenses/" not in name and not name.rsplit("/", 1)[-1].startswith("LICENSE"):
            continue
        archive.extract(info, target)
PY
done
"$host_py" -m compileall -q -b -f "$bundle/lib"
find "$bundle/lib" -name '*.py' -delete
rm -f "$bundle/sdk/PATCHES"
# bytecode that host runs left in the source tree is of another python and mtime checked, the bundle gets its own
find "$bundle/shim" "$bundle/sdk" -name __pycache__ -type d -prune -exec rm -rf {} +
"$host_py" -m compileall -q --invalidation-mode unchecked-hash "$bundle/shim" "$bundle/sdk"
echo "python: prefixes $out/prefix-armv7 $out/prefix-arm64, bundle $bundle"
