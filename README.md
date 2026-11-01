# exteria

<p align="center">
  <img src="docs/banner.png" alt="exteria">
</p>

<p align="center"><b>native telegram for old iphones and ipads: ios 5 and up, calls with video, stories, folders, its own vpn</b></p>

> [!NOTE]
> the ipa is signed with ldid, so it installs on a jailbroken device.

## devices

- armv7: ios 5 and later
- arm64: ios 7 and later
- iphone and ipad, one binary with both slices

## features

- chats, folders, archive, stories, polls, reactions, custom emoji
- stickers: static, animated and video
- voice notes, round videos, gifs, files, albums, flac music
- location picker and nearby places, OpenStreetMap previews
- calls: voice and video (vp8); voice chats of groups and channels, audio only
- translator: telegram, services and ai
- passcode lock, several accounts, login by phone or qr
- keeps deleted and edited messages on the phone, if you ask for it
- ayumoments: copies of protected messages from chats the account can read
- two looks: modern, and classic with the glossy ios 5 and 6 style and a hue of your own (ios 5 to 10)
- `.tgios-theme` files in the modern look
- plugins, power saver, local notifications
- russian, english

## themes

open a `.tgios-theme` file in Exteria, or copy it to Documents and choose it in chat settings. a `t.me/addtheme/<slug>` link works too. the preview shows both bubbles before applying.

- limits: 256 KiB, 512 values, 16 nesting levels
- colors reach the lists, bars, search, tabs, chat input and bubbles; missing values use the Exteria palette
- gradients of up to four colors are drawn static; wallpaper slugs, patterns and motion are not reproduced
- classic has its own palette

## shiro

the vpn of the app and of no other app: a wireguard tunnel to cloudflare warp inside the process.

- the button is in the chat list
- only telegram links and the udp of calls go through it, ipv4 only
- with the vpn on, connections wait for the tunnel and never fall back to the direct path
- the warp account is made on the first start over tls checked against `resources/shiro/roots.pem`

## proxy

add a `tg://proxy`, `tg://socks`, `t.me/proxy` or `t.me/socks` link on the welcome screen or in more settings.

- mtproto: plain, `dd` and `ee` secrets; socks5: username and password
- up to 64 links, kept in the keychain or in `Application Support/Exteria/proxy-link`
- telegram connections use the proxy, through shiro when it is on; calls and web pages do not

## plugins

user extensions and scripts that expand the standard features of exteria. lua 5.4 files in `Documents/Plugins`, listed in settings. a plugin runs after the person turns it on and confirms its permissions. the switch is tied to the sha-256 of the file, and three failed calls in a row switch it off.

```lua
return {
  name = "no-spam",
  permissions = { "messages.read", "messages.modify" },
  on_message = function(m)
    if m.text:find("spam", 1, true) then return false end
  end,
}
```

- `on_message(m)`: a message of someone else before it is drawn; nil leaves it, false hides it, a string shows another text
- `on_send(m)`: a text before it goes out; false stops it, a string is sent instead
- `on_event(name)`: `start`, `stop`, `pause` or `resume`
- at least one hook is needed; `text` needs `messages.read`, false and strings need `messages.modify`
- `log(text)` writes to the device log
- sandbox: base functions, string, table, math and utf8; no io, os, load or require
- limits: 64 KiB script, 200000 vm instructions per call, 2 MiB of memory, 16 KiB text

the host is `core/plugins`, the hooks into the chat are `app/platform/exteria_plugins.m`.

## build

```bash
make test
bash scripts/build_sticker_codecs.sh
make ipa
```

needs `EXTERIA_TC EXTERIA_SDK_V7 EXTERIA_SDK_V64 EXTERIA_OPENSSL_V7 EXTERIA_OPENSSL_V64 EXTERIA_LDID`, optional `EXTERIA_CRT_V7`. api id and hash come from `local/credentials.env` (`EXTERIA_API_ID`, `EXTERIA_API_HASH`). output: `build/ios/Exteria-v<version>.ipa`.

- `make test-video`: video decoders under asan and ubsan, needs ffmpeg libraries, pkg-config and libvpx
- `make app-unsigned`, then `make inspect-unsigned`: both slices, deployment targets, frameworks and ios 5 imports; needs `EXTERIA_SDK_V5` and `EXTERIA_SDK_V6`
- video stickers and calls link static ffmpeg and libvpx: set `EXTERIA_FFMPEG_SOURCE`, `EXTERIA_LIBVPX_SOURCE`, `EXTERIA_VIDEO_V7` and `EXTERIA_VIDEO_V64`, see `resources/licenses/video_stickers.txt`

## install

```bash
scp -r build/ios/Exteria.app root@<device-ip>:/Applications/
ssh root@<device-ip> 'chown -R mobile:wheel /Applications/Exteria.app && su mobile -c uicache'
```

the owner must be `mobile:wheel`, or the app cannot change its own icon on ios 6.

## updates

on start the app asks `api.github.com` for the latest release and shows a notice when its tag is newer. a release needs `Exteria-v<version>.ipa` and `Exteria-v<version>.ipa.sha256`, the tag is `v<version>`.

- the update replaces the files of the running bundle on a writable jailbreak install in `/Applications` or `/var/jb/Applications`; other installs open the release page
- the ipa must match its digest, or nothing is installed
- limits: 128 MiB, 4096 entries, four https redirects to github hosts

## paths

- accounts: `Library/Application Support/Exteria/exteria-<id>.db`
- warp account: `Library/Application Support/Exteria/shiro.account`
- crash log: `/var/mobile/Library/Caches/exteria-crash.log`
- call trace: `/var/mobile/Documents/exteria-call-trace.log`
- frame log: `Library/Caches/exteria-perf.log`, on with `defaults write com.sqmrak.exteria exteria.perf -bool YES`

to resolve app frames in a copied crash log, use the executable of the exact reported build and architecture (needs `llvm-objdump` and `llvm-addr2line`):

```bash
python3 scripts/symbolicate_crash.py crash.log /path/to/Exteria --arch armv7
```

## license

[exteria license](LICENSE). rights already granted under [gpl v3](LICENSE.gpl-3.0) remain in effect. the emoji pack is apple artwork and is not licensed for redistribution, see `resources/emoji/NOTICE.txt`. fonts, codecs and sounds keep their licenses in `resources/licenses` and `resources/fonts`.
