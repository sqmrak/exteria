# contributing to exteria

how to build exteria and how to work in it. user features are in [README.md](README.md), plugins in [docs/plugins.md](docs/plugins.md), languages in [docs/languages.md](docs/languages.md).

## rules

- the baseline is real ios 5 on armv7, not a header that compiles with a low deployment target. arm64 starts at ios 7. one binary carries both slices
- objective-c uses manual reference counting. `retain`, `release`, `autorelease` and copied blocks are written by hand, `[super dealloc]` goes last. do not turn on arc
- a background thread that makes objects needs its own autorelease pool. uikit is touched on the main thread only
- an api newer than ios 5 is absent until a runtime check says otherwise: class, selector or symbol lookup, weak link, a fallback. do not send a selector because the sdk declares it
- logic that can be tested without uikit goes in `core/` as c99. uikit, controllers and platform glue go in `app/`
- no stubs, no silent no-ops, no ignored return values. a failure is returned, logged where it happened or shown
- no tls or certificate checks weakened to make something work
- a fallback needs a named failure it covers and a bound on its attempts
- every change that fixes a bug comes with a test that fails without it
- comments are english, lowercase, short, say why and not what, no final period, no dashes
- commit messages are lowercase and imperative, one line

## layout

```
app/        objective-c: controllers, views, platform glue
core/       c99: protocol, state, layout rules, parsers, no uikit
python/     the android and java shims that plugins import
third_party vendored libraries, built from source
resources/  icons, fonts, sounds, strings, pems
schemas/    tl schemas the generator reads
scripts/    builds and packaging
tests/      host tests: c, python, video
tools/      asset generators and the tl generator
docs/       languages, plugins, dex runtime, light mode
local/      credentials.env, never committed
```

in `app/`:

- `lifecycle`: delegate, passcode lock, notifications, updater, crash log
- `net`: the objective-c face of the core: `exteria_session*.m` (one file per area of the api), models, caches, call engines, shiro
- `features`: screens, by area (`chats`, `auth`, `calls`, `stories`, `settings` and so on)
- `ui/shared`, `ui/classic`: views, theme, symbols, text layout. classic is the ios 5 and 6 look
- `media`: players, recorders, editors, viewers
- `platform`: settings stores, audio session, keychain, plugin host services
- `translate`: translator backends and language packs

## backend

the backend is the c core in `core/`. it is one static set of files, linked into the app and into the host tests. it has no uikit and no objective-c.

- `tl`: generated serializers and parsers, made from `schemas/*.tl` by `tools/tlgen.py` (`make generate`, `make check-generated`)
- `mtproto`: transports (tcp, mtproto proxy with `dd` and `ee` secrets, fake tls, socks5), handshake, keys, message framing, file transfer
- `crypto`, `auth`: aes, sha, srp, dh, passcode, login by phone and qr
- `client`: the rpc client over mtproto. one entry point for the app
- `updates`: update state, gaps, difference
- `storage`, `session`: the sqlite account db and the sealed `session-N.bin` files
- `chats`: dialogs, messages, media, profiles, stories, reactions, bots, stats. most of the logic the screens show
- `layout`: pure layout and rules for lists, text, motion, qr, welcome screens
- `calls`, `tgcalls`: voip: rtp, vp8, stun, turn, ice, srtp, sctp, group calls
- `media`, `video`, `emoji`, `notify`: id3, lrc, geo, photo edit, flac, vp8, yuv, emoji data, notification rules
- `shiro`: the vpn. wireguard to warp, a small tcp/ip stack, dns, https for the warp account
- `pyhost`, `dexnative`: cpython host for plugins and the native part of the dex runtime
- `base`: status codes, arena, byte buffers, release check, zip

how a call goes: a screen asks `ExteriaSession` (`app/net`), which calls the core client, which builds a tl request, sends it over mtproto and returns a status. the answer is parsed in the core into a plain struct, and the session turns it into a model for the screen. results come back on the main thread.

the core returns specific statuses (`exteria_status.h`), not booleans. a function that writes a buffer takes its capacity. lengths from the network are capped before an allocation.

## build

needs a linux or macos host, the ios toolchain (clang with ldid), two sdks, openssl for both slices, and cpython for both slices.

env, all overrideable, none has a default path:

- `EXTERIA_TC`: toolchain `bin` directory
- `EXTERIA_SDK_V7`: legacy sdk for the armv7 link (ios 6.1 works)
- `EXTERIA_SDK_V64`: current sdk for arm64
- `EXTERIA_OPENSSL_V7`, `EXTERIA_OPENSSL_V64`: openssl prefixes
- `EXTERIA_VIDEO_V7`, `EXTERIA_VIDEO_V64`: ffmpeg and libvpx prefixes (from `EXTERIA_FFMPEG_SOURCE` and `EXTERIA_LIBVPX_SOURCE`, see `resources/licenses/video_stickers.txt`)
- `EXTERIA_PYTHON_V7`, `EXTERIA_PYTHON_V64`, `EXTERIA_PYTHON_BUNDLE`: made by `scripts/build_python.sh`
- `EXTERIA_LDID`: set it in its own assignment after `EXTERIA_TC`, since it defaults to `$EXTERIA_TC/ldid`
- `EXTERIA_CRT_V7`: optional crt for the armv7 link
- `EXTERIA_API_ID`, `EXTERIA_API_HASH`: from `local/credentials.env`, `source` it before `make`. they go into a generated header in `build/` and never into the repository

order:

```bash
bash scripts/build_python.sh        # cpython, shim, sdk, ca bundle. again after a change in python/ or third_party/exteraless
bash scripts/build_sticker_codecs.sh
make test
make ipa
make deb                             # optional, wraps the ipa for /var/jb
```

output: `build/ios/Exteria-v<version>.ipa`, `build/ios/exteria_<version>.deb`. a full `make app` after a header change takes about ten minutes.

after the build, check the artifact and not only the exit code:

- `make app-unsigned`, then `make inspect-unsigned`: both slices, deployment targets, linked frameworks, ios 5 imports (needs `EXTERIA_SDK_V5` and `EXTERIA_SDK_V6`)
- `lipo -info build/ios/Exteria.app/Exteria` shows armv7 and arm64
- `unzip -l` on the ipa, `dpkg-deb -c` on the deb: layout, permissions, `Info.plist` version
- the version in `packaging/Info.plist`, the file names and the release tag agree. do not bump it outside a release

## test

```bash
make test
make -C tests test \
  EXTERIA_PYTHON_HOST_PREFIX=<cpython 3.11 prefix> EXTERIA_PYTHON_STDLIB=<its Lib directory> \
  EXTERIA_PYTHON_HOST=<python3.11>
make sanitize        # the c tests under asan and ubsan
make test-video      # decoders under sanitizers, needs ffmpeg libraries, pkg-config, libvpx
make test-icons
```

- c tests are `tests/core/test_*.c`, one binary each, built with `-Wall -Wextra -Werror -Wconversion`. they use fake servers (`fake_mt_server.c`, `fake_tcp_server.c`) on local sockets and byte vectors, never a public service
- python tests are `tests/python`, run by cpython 3.11 against a stand-in for the app (`fakeapp.py`)
- the iphone toolchain on `PATH` breaks host builds (`gcc` becomes its clang, `--gdwarf-5` fails). run host tests with `PATH=/usr/local/bin:/usr/bin:/bin make CC=gcc -j8 test` from `tests/`
- tests prove the host side. what needs a real device is said in the commit and in the docs, not assumed

## add a feature

1. read the code around it, and the nearest screen that does something similar
2. put the parsing and the rules in `core/` with a test, then wire the objective-c side
3. `make generate` when a tl schema changed, and commit the generated tables with it
4. strings go in `resources/localization/en.lproj` first, then `ru.lproj`. a missing key falls back to english
5. icons come from `tools/make_assets.py`, svg sources in `tools/material` and `tools/symbols`. do not hand edit generated pngs
6. build both slices. a header change rebuilds a lot, run it in the background
7. update `README.md` or `docs/` when a user can see the change

## device

jailbroken devices only. the ipa is signed with ldid.

```bash
scp -r build/ios/Exteria.app root@<device-ip>:/Applications/
ssh root@<device-ip> 'chown -R mobile:wheel /Applications/Exteria.app && su mobile -c uicache'
```

- the owner is `mobile:wheel`. a root-owned bundle breaks the icon change on ios 6, since the app rewrites its own `Info.plist` as `mobile`
- on ios 5 and 6 run `/Applications/Exteria.app/Exteria --system-notifications on` before `uicache`, then respring (see the install section of the readme)
- old sshd needs `-o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 -o Ciphers=+aes128-cbc,aes256-cbc` on the command line, and `scp -O`. keep these out of `~/.ssh/config`
- crash log: `/var/mobile/Library/Caches/exteria-crash.log`. system reports: `/var/mobile/Library/Logs/CrashReporter`
- a tester's `build <hex>` line is the `LC_UUID` of the slice. match it with `llvm-dwarfdump --uuid` on the binary of that exact build, then `python3 scripts/symbolicate_crash.py crash.log /path/to/Exteria --arch armv7`
- keep the ipa or deb of every build you hand out, or the crash cannot be named later

## plugins

python and the shims live in `python/shim`, the sdk in `third_party/exteraless` (changes in its `PATCHES`), the host in `core/pyhost`, the services in `app/platform/exteria_plugin*.m`. [docs/plugins.md](docs/plugins.md) lists what works, what does not and what was never run on a phone. a new shim class comes with a test in `tests/python`, and its line in that file.

## do not

- commit `build/`, `local/credentials.env`, objects or stage directories
- bump a version, rewrite a checksum or publish a release outside a release
- edit `third_party` without a line in the matching `PATCHES` or notice
- raise the minimum ios version or drop armv7 to avoid a compatibility problem
- keep an old workaround next to its replacement
