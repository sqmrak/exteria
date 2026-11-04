# plugins

a plugin is a python file in the exteraGram plugin format. the app runs it with cpython 3.11 and the sdk of [exteraless](https://github.com/exteraless/exteraless) (`third_party/exteraless`, local changes listed in its `PATCHES`). the sdk reaches the app through `app.exteraless.plugins.PythonBridge`, `PluginServices` and `java.jclass`; `python/shim` supplies all three for ios, and the android classes a plugin imports.

## use

- put a `.plugin`, `.py` or `.elyx` file in `Documents/Plugins`, import it in settings, plugins, or open a `.plugin` from a chat. import copies the file and never turns it on
- the page lists every file (64 at most, 1 MiB each) with the permissions it needs, or why it was refused
- the switch is tied to the sha-256 of the file: a changed file is off until it is turned on again
- three failed calls in a row switch the plugin off, and the page shows the last traceback
- a tap on a running plugin opens its page of settings, if it has `create_settings()`
- the interpreter starts at launch when a plugin is on, else when the page opens, and stays up
- limits: hooks 400 ms, a queued call or a settings click 5 s, loading 20 s. a python loop is stopped with `TimeoutError`, a call blocked in c is not
- log: `Library/Caches/exteria-plugins.log`, the last 128 KiB
- a plugin that does not load shows a window with the reason (java code, missing android classes, a missing library, or the last error line). `python/shim/exteria_diagnose.py` reads the whole source to tell

## permissions

`messages.read`, `messages.send`, `network`, `files`, `intents`, `settings`, `hooks`, `native`: the keys in `__permissions__` plus what `capability_scan.py` finds in the code. turning the plugin on grants them. they are shown, not enforced: a plugin is python in the process of the app. install only what you read. a plugin writes in `Documents/Plugins/.data/<id>` and `Library/Caches/exteria-plugin-files`.

## works

- `BasePlugin`, `HookResult`, `HookStrategy`, `AppEvent`, `MenuItemData`, settings, `log`
- hooks: `on_plugin_load`, `on_plugin_unload`, `on_app_event`, `on_send_message_hook` (text, reply and quote), `on_update_hook("TL_updateNewMessage")`, and `hook_method` on `ChatMessageCell.setMessageContent` to change the text a chat shows. text over 16 KiB skips plugins
- settings pages: `Header`, `Divider`, `Text`, `Switch`, `Selector`, `Input`, `Slider`, `EditText`
- dialogs, bulletins and toasts of the app; android views in an overlay (`View`, layouts, `TextView`, `ImageView`, drawables, `Bitmap`/`Canvas`/`Paint` rectangles, animations, touches, accelerometer)
- message menu items, `NotificationCenter.didReceiveNewMessages`, the open chat, `send_text`, photos by `sendMessage(params)`, `MediaPlayer` for a file
- `requests`, `websocket`, `certifi` (https trusts `python/cacert.pem`), `socket`, `ssl`, `hashlib`, `json`, `zlib`, `threading`. `__requirements__` is met by the bundle only
- worker threads: calls into the app are handed to the main thread and wait up to 10 s
- `.elyx` archives and libraries over them. zwylib loads: settings, cache files, the asyncio loop, commands, hooks on the shims, reflection, xposed-style hooks on the methods of the shims, `PluginsController`. its `Requests`, autoupdater, `DialogPicker` and android-view dialogs do not work

## does not work

- request hooks and `on_updates_hook` (the core keeps tl requests out of python)
- `hook_all_constructors`, intent handlers, progress dialogs
- `androidx.*`, `org.telegram.*` and `android.*` outside the shim, drawn text and video surfaces: the import fails naming the class
- java code (`.dex`), `fork`, `subprocess`, `ctypes`, `sqlite3`, `pyexpat`. haptics and sound effects do nothing
- the views of the app itself: a plugin sees only its own

## exteria only

- `ImageView.setNativeSurface(name)`, `refreshSurface()`: frames a native module publishes (`core/pyhost/exteria_surface.h`)
- `exteria_sheet.present(...)`: a sheet like the browser's with a native surface and touch keys

## host

`core/pyhost` is plain c: `exteria_pyhost_init`, `exteria_pyhost_call(module, func, json_args, timeout_ms, ...)` and `_exteria.service(name, json)`, which python uses to ask the app. services are answered in `app/platform/exteria_plugins.m` (`plugin_service`) and `app/platform/exteria_plugin_ui.m` (`ui.*`, `sensor.*`, `theme.*`, `app.*`, `chat.*`, `sheet.*`), sound in `exteria_plugin_audio.m`. entry points are in `python/shim/exteria_host.py`. uikit is served on the main thread only.

services: `hook.display.add|remove`, `chat.rebuild`, `chat.send_photo`, `files.cache`, `audio.open|start|stop|release`, `app.current`, `app.language`, `app.version`, `ui.alert` (with a `field`, the answer comes back as `alert_result`).

## checked

with the real file, a local server and the stand-in app of `tests/python/fakeapp.py`. none was run on a phone.

- load and work: `qrcode`, `edge_tts_voiceover`, `zwylib.elyx`, `quoteReply`, `LocalEdictor`
- refused: `cactus_export`, `zwyNoForwardLimit`, `audiovizualizer_plugin.elyx` (java bytecode), `deleted_gift_sender` (tl requests), `ios_like_selection`, `meeow_reswaga.elyx` (android views, 7.6 MB)

## build and test

`scripts/build_python.sh` builds cpython for armv7 (ios 5) and arm64 (ios 7) and stages `python/` (stdlib as bytecode, shim, sdk, ca bundle) for the app. run it again after a change in `python/shim` or `third_party/exteraless`, or the app keeps the old copy. it needs `EXTERIA_PYTHON_TARBALL` (Python-3.11.9.tar.xz), `EXTERIA_PYTHON_CACERT` (cacert.pem), the openssl prefixes and the toolchain variables of the app build.

```bash
make -C tests test \
  EXTERIA_PYTHON_HOST_PREFIX=<cpython 3.11 prefix> EXTERIA_PYTHON_STDLIB=<its Lib directory> \
  EXTERIA_PYTHON_HOST=<python3.11>
```

`test` runs the c tests, the interpreter host and the python tests.
