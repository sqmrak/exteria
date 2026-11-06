# plugins

a plugin is a python file in the exteraGram plugin format. the app runs it with cpython 3.11 and the sdk of [exteraless](https://github.com/exteraless/exteraless) (`third_party/exteraless`, local changes listed in its `PATCHES`). the sdk reaches the app through `app.exteraless.plugins.PythonBridge`, `PluginServices` and `java.jclass`; `python/shim` supplies all three for ios, and the android classes a plugin imports.

## use

- put a `.plugin`, `.py` or `.elyx` file in `Documents/Plugins`, import it in settings, plugins, or open a `.plugin` from a chat. import copies the file and never turns it on
- the page lists every file (64 at most, 4 MiB each) with the permissions it needs, or why it was refused
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
- the settings tab as a page: hooks on `SettingsActivity.createView`, `onResume`, `onPause`, a picture under the rows (`getFragmentView()` is the root, an `ImageView` added at 0 shows there, `setColorFilter(PorterDuffColorFilter)` dims it) and see-through cards (a `ColorMatrixColorFilter` that scales alpha on `listView.sectionBackgroundPaint`). `listView` has no row views, `getChildCount()` is 0. the modern style only, the classic table has no background behind it
- pictures: `startActivityForResult` of `ACTION_OPEN_DOCUMENT`, `GET_CONTENT` or `PICK` of `image/*` opens the photo library, the answer is `LaunchActivity.onActivityResult` (hook it). the picture is kept as a `file:` address in `Library/Application Support/exteria-plugin-pictures` (the four newest stay) and only `ContentResolver.openInputStream` on such an address opens. `BitmapFactory.decodeStream` decodes it in the app to 2048 on the long side; `Bitmap.createScaledBitmap`, `copy`, `Utilities.stackBlurBitmap(bitmap, 0..254)` work on it in the app, its pixels cannot be read from python
- the music player: `MediaController` with `playMessage`, `cleanupPlayer` and `pauseMessage` (a hook on them runs before the app starts or pauses a song), `audioPlayer`, `audioVolume`, `getPlaylist`, `playNextMessage`, `VideoPlayer` (position, volume, `releasePlayer`) and the music settings of `SharedConfig`. `audioPlayer = None` takes the player of the song out so it plays on while the next song starts, which is how a crossfade works. `UItem.asSlideView` in a plugin page is a row of choices. no visualizer, no volume animation on pause, `audioFocus` is always the full focus (`python/shim/org/telegram/messenger/music.py`)
- message menu items, `NotificationCenter.didReceiveNewMessages`, the open chat, `send_text`, photos by `sendMessage(params)`, `MediaPlayer` for a file
- `requests`, `websocket`, `certifi` (https trusts `python/cacert.pem`), `socket`, `ssl`, `hashlib`, `json`, `zlib`, `threading`. `__requirements__` is met by the bundle only: `mutagen` and `yt-dlp` are in it (python/lib, 15 MB of bytecode, pinned in `third_party/python/wheels.sha256`). they import with the device stdlib; no download or tag write was run on a phone, `pyexpat`, `xml.etree`, `bz2`, `lzma` and `sqlite3` are in the bundle now, built static from bzip2 1.0.8, xz 5.4.6 and sqlite 3.46.1 (`third_party/python/sources.sha256`, `ext-<arch>` of `scripts/build_python.sh`, linked as `libexteria_pyext.a` after libpython), and the bundled expat of cpython. built for both slices and checked for symbols and the imports of the ios 5 runtime, not run on a phone. missing still: `_decimal` (the pure python one runs), `_uuid` (`uuid` works without it), `ctypes`
- worker threads: calls into the app are handed to the main thread and wait up to 10 s
- `.elyx` archives and libraries over them. zwylib loads: settings, cache files, the asyncio loop, commands, hooks on the shims, reflection, xposed-style hooks on the methods of the shims, `PluginsController`. the pickers `GroupCreateActivity` and `DialogsActivity` open the chat picker of the app and call `onFragmentDestroy` when the person goes back (not run on a phone); `select()` with chats ticked in advance is refused. its `Requests` (beyond the four requests above) and autoupdater do not work

## does not work

- request hooks and `on_updates_hook`, and any `send_request` but the four of `playlist_to_profile` above and the device profile of `device_fingerprint_spoofer` below (the core keeps the tl layer out of python)
- `hook_all_constructors`, intent handlers, progress dialogs
- `androidx.*`, `org.telegram.*` and `android.*` outside the shim, drawn text and video surfaces: the import fails naming the class
- java code (`.dex`), `fork`, `subprocess`, `ctypes`. haptics and sound effects do nothing
- the views of the app itself: a plugin sees only its own, and the root of the settings page

## exteria only

- `ImageView.setNativeSurface(name)`, `refreshSurface()`: frames a native module publishes (`core/pyhost/exteria_surface.h`)
- `exteria_sheet.present(...)`: a sheet like the browser's with a native surface and touch keys

## host

`core/pyhost` is plain c: `exteria_pyhost_init`, `exteria_pyhost_call(module, func, json_args, timeout_ms, ...)` and `_exteria.service(name, json)`, which python uses to ask the app. services are answered in `app/platform/exteria_plugins.m` (`plugin_service`) and `app/platform/exteria_plugin_ui.m` (`ui.*`, `sensor.*`, `theme.*`, `app.*`, `chat.*`, `sheet.*`, `bitmap.*`, `page.*`, `account.*`), sound in `exteria_plugin_audio.m`. entry points are in `python/shim/exteria_host.py`. uikit is served on the main thread only.

services: `hook.display.add|remove`, `chat.rebuild`, `chat.send_photo`, `files.cache`, `audio.open|start|stop|release`, `app.current` (kind `settings` on the settings tab), `app.pick_image`, `app.pick_root`, `music.state|entry|peek|start|pause|cleanup|detach|player` (`exteria_plugin_music.m`, the music player of `app/media`, which asks `exteria_host.music_play` and `music_pause` before a song starts or pauses), `account.history|saved_music|save_music|delete|send_audio` (`exteria_plugin_account.m`, answered by `exteria_host.account_result`; the song upload has a `music` kind in `core/chats/exteria_messages.c`), `bitmap.decode|scale|crop|encode|copy|blur|release` (`exteria_plugin_bitmap.m`, the blur is `core/media/exteria_stack_blur.c`), `story.publish|forget` (`exteria_plugin_story.m`) and `account.story_post`, `app.pick_time` (the wheel of `app/ui/shared/exteria_date_time_picker.m`, answered by `exteria_host.time_picked`), `page.cards`, `app.language`, `app.version`, `ui.alert` (with a `field`, the answer comes back as `alert_result`).

## checked

with the real file, a local server and the stand-in app of `tests/python/fakeapp.py`. none was run on a phone.

- load and work: `qrcode`, `edge_tts_voiceover`, `zwylib.elyx`, `quoteReply`, `LocalEdictor`, `settings_wallpaper` (picker, blur, dimming and see-through cards, through the stand-in app. the page, the picker and the layer were not run on a phone)
- `playlist_to_profile`: its libraries are in the bundle and its calls reach the app, through the stand-in app. `send_request` takes four requests and refuses any other by name: `messages.getHistory` of Saved Messages (the newest 1 to 100, no offsets), `users.getSavedMusic` of oneself (read page after page up to the limit asked), `account.saveMusic` (no `after_id`) and `messages.deleteMessages` of Saved Messages. `send_audio` to Saved Messages runs the send hooks of the plugins over a document (they set the audio attribute: title, performer, duration) and the app uploads it as a song. the cover helper works with `BitmapFactory.decodeFile`, `Bitmap.createBitmap(source, x, y, w, h)`, `createScaledBitmap` and `compress` into a `FileOutputStream` in the plugin files folder. no download by yt-dlp, no upload and no `saveMusic` was run on a phone. the rounded cover of its progress panel is not drawn (no `BitmapShader` or `Canvas.drawRoundRect` over a picture), buttons have no ripple (`RippleDrawable` is its content) and `setEllipsize` is kept but the label cuts at the line limit without a mark
- `device_fingerprint_spoofer`: loads and its `invokeWithLayer(initConnection(help.getNearestDc))` reaches the app. the record is serialized, read back and checked field by field, and only `device_model`, `system_version` and `app_version` are taken (the api id, the lang pack and the language fields stay the app's, and the layer must be its own); the app tells the server with its next request and keeps the texts until it restarts, and the profile of the stand-in `Build` (`Apple` + `iPhone`) means the way back to the real device. `Class.forName`, `UserConfig.isClientActivated` and `LocaleController.getSystemLocaleStringIso639` are shims now. not available: the start hooks (`ConnectionsManager` does not exist, so the app sends the real texts until the plugin applies its profile, a few seconds after it loads) and the editor in the devices screen (`RecyclerListView` and `SessionsActivity` are android views), both shown in the status of the plugin. the media connections of the app keep the real texts. not run on a phone or against Telegram: whether the server shows the new device in the devices screen
- `zwyCrossfade` runs against the stand-in music player: a tap on next and the end of a song take the old player out, fade it down while the new song fades in, and release it; settings show as rows of choices. not run on a phone: a second `AVPlayer` playing next to the first, the volume of `AVPlayer` (ios 7 on) and the audio mix that stands in for it on ios 5 and 6, and the quiet start of a song while the plugin sets its volume
- `story_scheduler`: the story screen builds the page a plugin hooks (`StoryPrivacyBottomSheet.Page`, `bind`, `updateButton`), so the plugin puts its button under the audience pill and a long press on publish opens its wheel (`AlertsCreator.createScheduleDatePickerDialog`; `DatePickerDialog` and `TimePickerDialog` use the same wheel). a story about to go up is offered to `StoriesController.uploadStory` first, a hook that sets a result holds it back, and the plugin publishes it later through `account.story_post` (the file must lie in the temp folder or the plugins folder). an audience that names people stays in the app under a number while python holds the story, at most 64 stories; a story restored after a restart has none and goes to everyone, as in the plugin's own notes. pictures only: a video, a channel or a group is refused by name (`MediaMetadataRetriever` too), and the app publishes without `pinned` and `period`. the app must be running at the time, and ios stops it in the background, so a story waits until the app is open again. host-tested with the real file (12 tests, `EXTERIA_STORY_SCHEDULER`). not run on a phone: the button and the long press on the story screen, the wheel over it, the publish at the due time, and the zone of the phone in `datetime` (python takes the epoch and the parts from the app, not from its own clock). `BasePlugin.logger` was added to the vendored sdk for it (`third_party/exteraless/PATCHES`)
- refused: `unlim_accounts` (java bytecode and a native library for the account limit of the android client, which the app does not have), `cactus_export`, `zwyNoForwardLimit`, `audiovizualizer_plugin.elyx` (java bytecode), `deleted_gift_sender` (tl requests), `ios_like_selection`, `meeow_reswaga.elyx` (android views, 7.6 MB)

## build and test

`scripts/build_python.sh` builds cpython for armv7 (ios 5) and arm64 (ios 7) and stages `python/` (stdlib as bytecode, shim, sdk, ca bundle) for the app. run it again after a change in `python/shim` or `third_party/exteraless`, or the app keeps the old copy. it needs `EXTERIA_PYTHON_TARBALL` (Python-3.11.9.tar.xz), `EXTERIA_PYTHON_CACERT` (cacert.pem), `EXTERIA_PYTHON_WHEELS` (a directory with the wheels of `third_party/python/wheels.sha256`, checked by hash), the openssl prefixes and the toolchain variables of the app build.

```bash
make -C tests test \
  EXTERIA_PYTHON_HOST_PREFIX=<cpython 3.11 prefix> EXTERIA_PYTHON_STDLIB=<its Lib directory> \
  EXTERIA_PYTHON_HOST=<python3.11>
```

`test` runs the c tests, the interpreter host and the python tests.
