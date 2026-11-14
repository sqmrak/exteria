# plugins

a plugin is a python file in the exteraGram plugin format. the app runs it with cpython 3.11 and the sdk of [exteraless](https://github.com/exteraless/exteraless) (`third_party/exteraless`, local changes in its `PATCHES`). the sdk reaches the app through `app.exteraless.plugins.PythonBridge`, `PluginServices` and `java.jclass`. `python/shim` supplies all three for ios, and the android classes a plugin imports.

nothing here has run on a phone unless a line says so. see [not run on a phone](#not-run-on-a-phone).

## use

- put a `.plugin`, `.py` or `.elyx` file in `Documents/Plugins`, then import it in settings, plugins, or open a `.plugin` from a chat. import copies the file and never turns it on
- the page lists every file (64 at most, 4 MiB each) with the permissions it needs, or why it was refused
- the switch is tied to the sha-256 of the file: a changed file is off until it is turned on again
- three failed calls in a row switch the plugin off, and the page shows the last traceback
- a tap on a running plugin opens its page of settings, if it has `create_settings()`
- the interpreter starts at launch when a plugin is on, else when the page opens, and stays up
- limits: hooks 400 ms, a queued call or a settings click 5 s, loading 20 s. a python loop is stopped with `TimeoutError`, a call blocked in c is not
- log: `Library/Caches/exteria-plugins.log`, the last 128 KiB
- a plugin that does not load shows a window with the reason: missing android classes, a missing library, a feature the app lacks, or the last error line. `python/shim/exteria_diagnose.py` reads the whole source to tell. a dex file or a class loader is no reason by itself

## permissions

`messages.read`, `messages.send`, `network`, `files`, `intents`, `settings`, `hooks`, `native`. the keys in `__permissions__` plus what `capability_scan.py` finds in the code. turning the plugin on grants them.

they are shown, not enforced: a plugin is python in the process of the app. install only what you read. a plugin writes in `Documents/Plugins/.data/<id>` and `Library/Caches/exteria-plugin-files`.

## works

core

- `BasePlugin`, `HookResult`, `HookStrategy`, `AppEvent`, `MenuItemData`, settings, `log`
- hooks: `on_plugin_load`, `on_plugin_unload`, `on_app_event`, `on_send_message_hook` (text, reply and quote), `on_update_hook("TL_updateNewMessage")`, and `hook_method` on `ChatMessageCell.setMessageContent` to change the text a chat shows. text over 16 KiB skips plugins
- settings pages: `Header`, `Divider`, `Text`, `Switch`, `Selector`, `Input`, `Slider`, `EditText`
- dialogs, bulletins and toasts of the app
- message menu items, `NotificationCenter.didReceiveNewMessages`, the open chat, `send_text`, photos by `sendMessage(params)`, `MediaPlayer` for a file
- worker threads: a call into the app is handed to the main thread and waits up to 10 s
- `Browser.openUrl` (`org.telegram.messenger.browser`) opens http, https and tg addresses through the link router of the app, so the browser chosen in settings applies. other schemes are refused

views

- android views in an overlay: `View`, layouts, `TextView`, `ImageView`, drawables, animations, touches, accelerometer
- a view that overrides `onDraw` is painted by a software rasterizer (shapes, paths, strokes, gradients, clips, layers, Porter-Duff, bitmaps made by python) into a bitmap the app shows on the layer of the view. it is python, so it suits icons and small views, not animation
- `Canvas.drawText` asks the app (`ui.text_image`) for the line as a coverage mask in the font of the app and tints it with the paint (color, shader, alpha, underline, strike, mode, an unblurred shadow). one line at a time
- `View.setRenderEffect` with `RenderEffect.createBlurEffect` or `createChainEffect`: `ExteriaPluginView` draws the view and its children into a picture (a quarter size, 512 points a side at most), blurs it with the stack blur of the app and shows it over the real layers, which stay under it for touches
  - the picture is taken when the effect is set and when a property of the view changes, so a child that changes alone shows blurred from the next change
  - a translucent background shows twice, radii in x and y are drawn as the larger one
  - `offset`, `color filter`, `blend mode`, `shader` and `bitmap` effects raise `UnsupportedOperationException` naming the kind

settings tab

- hooks on `SettingsActivity.createView`, `onResume`, `onPause`
- a picture under the rows: `getFragmentView()` is the root, an `ImageView` added at 0 shows there, `setColorFilter(PorterDuffColorFilter)` dims it
- see-through cards: a `ColorMatrixColorFilter` that scales alpha on `listView.sectionBackgroundPaint`
- `listView` has no row views, `getChildCount()` is 0. modern style only, the classic table has no background behind it

bottom bar

- `MainTabsActivity` (`org.telegram.ui`, found by `find_class` or by `LaunchActivity.getActionBarLayout().getFragmentStack()` while the main screen is up) has `tabs`, four views for the slots in the order the person set
- `setText`, `setOnClickListener`, `setOnLongClickListener` and an icon set with `setImageDrawable` on the `ImageView` inside a tab go to the bar (`app/platform/exteria_plugin_tabs.m`). the bar keeps them across rebuilds and drops them when the last plugin goes
- a tap on a slot with a listener goes to the plugin and the app does not open the screen. the profile tab keeps its photo and takes a title only
- hooks on `createView` and `onResume` run when the bar is built and when the main screen appears
- the only icon is `files_music` (`Resources.getIdentifier`, `Context.getDrawable`), a symbol the app draws. any other drawable raises `TypeError`

pictures

- `startActivityForResult` with `ACTION_OPEN_DOCUMENT`, `GET_CONTENT` or `PICK` of `image/*` opens the photo library, the answer is `LaunchActivity.onActivityResult` (hook it)
- the picture is kept as a `file:` address in `Library/Application Support/exteria-plugin-pictures` (the four newest stay). only `ContentResolver.openInputStream` on such an address opens it
- `BitmapFactory.decodeStream` decodes to 2048 on the long side. `Bitmap.createScaledBitmap`, `copy` and `Utilities.stackBlurBitmap(bitmap, 0..254)` work on it in the app, its pixels cannot be read from python

music

- `MediaController`: `playMessage`, `cleanupPlayer`, `pauseMessage` (a hook runs before the app starts or pauses a song), `audioPlayer`, `audioVolume`, `getPlaylist`, `playNextMessage`, `VideoPlayer` (position, volume, `releasePlayer`), and the music settings of `SharedConfig`
- `audioPlayer = None` takes the player of the song out, so it plays on while the next song starts. that is how a crossfade works
- `UItem.asSlideView` on a plugin page is a row of choices
- no visualizer, no volume animation on pause, `audioFocus` is always the full focus (`python/shim/org/telegram/messenger/music.py`)
- `MessagesController.getUser`, `getChat`, `getInputPeer` and `getInputUser` answer for the people and chats of the chat list the app holds, and give an empty peer or `None` for the rest
- `send_request` takes `messages.search` with the music filter, no text and a limit of 1, from the newest song (`offset_id` 0) or the oldest (`offset_id` 1, `add_offset` -1), and `users.getSavedMusic` for a user of the chat list
- `MessageObject(account, message, True, True)`, `MediaController.setPlaylist`, `getPlaylist().clear()`, `addAll`, `cleanup` and `playMessage` start such songs in the music player of the app, which fetches them. `MessagesController.SavedMusicList` holds the song of the profile it was set up with and loads no more

cleaning a chat

- `CHAT_ACTION_MENU` items are rows of the three dots of an open chat (up to 4) and of the plugins page
- `get_last_fragment()` in a chat is a `ChatActivity` with `getDialogId` (android id: a user positive, a group or channel the plain id with a minus), `getTopicId`, `getCurrentChat`, `getMessagesController`, `getConnectionsManager`, `getUserConfig`. `getChatMode`, `getSavedDialogId` and `getMergeDialogId` are 0, `getCurrentEncryptedChat` is `None`
- `getCurrentChat` reports a channel or supergroup, `creator`, and `admin_rights.delete_messages` for an administrator of a broadcast channel (the app does not know the real rights)
- `ConnectionsManager.sendRequest` (or `send_request`) takes, for the open chat only: `messages.getHistory` and `messages.getReplies` by `offset_id` (up to 100 messages a page), `messages.search` with no filter and `from_id` the account (also in a topic), `messages.deleteMessages` and `channels.deleteMessages` of 1 to 100 ids
- a row carries id, date, out, post and whether it is a service message. `res.count` is 0
- the delete answer says `pts_count` as many ids as were sent and `pts` 0. a deleted message leaves the kept copies and the open screen at once, so `MessagesController.deleteMessages`, `processNewDifferenceParams` and the storage queue of `MessagesStorage` have nothing to do
- a group gives no rights to the app, so only the messages of the account are offered there
- saved dialogs of Saved Messages and the merged history of a migrated group are not cleaned
- a loading dialog (`AlertDialogBuilder.ALERT_TYPE_LOADING`) is the native `progress.show` with title, text, bar and buttons, moved by `setMessage` and `set_progress`
- `Context.getPackageManager().getPackageInfo(...).versionName` is `android.content.pm.EXTERAGRAM_API` (13.1.1), the level the shims were run against, which plugins compare with `__min_version__`

python

- `requests`, `websocket`, `certifi` (https trusts `python/cacert.pem`), `socket`, `ssl`, `hashlib`, `json`, `zlib`, `threading`
- `__requirements__` is met by the bundle only. `mutagen` and `yt-dlp` are in it (`python/lib`, 15 MB of bytecode, pinned in `third_party/python/wheels.sha256`)
- `pyexpat`, `xml.etree`, `bz2`, `lzma` and `sqlite3` are in the bundle, built static from bzip2 1.0.8, xz 5.4.6 and sqlite 3.46.1 (`third_party/python/sources.sha256`, `ext-<arch>` of `scripts/build_python.sh`, linked as `libexteria_pyext.a` after libpython), plus the expat of cpython
- missing: `_decimal` (the pure python one runs), `_uuid` (`uuid` works without it), `ctypes`
- `subprocess`, `os.posix_spawn`, `os.spawn` and `os.system` start programs of the device with `posix_spawn`, since the app cannot fork (`python/shim/_posixsubprocess.py`). only for a plugin with the `native` permission (the sdk refused them to every plugin, see `third_party/exteraless/PATCHES`)
  - `stdin`, `stdout`, `stderr`, `env`, `pass_fds`, `close_fds`, `process_group` and `cwd` work. `preexec_fn`, `start_new_session`, `umask`, `user` and `group` fail with `ENOSYS`
  - `cwd` goes through `/bin/sh`, which changes into the directory and execs the program (so `argv[0]` of the child is its path). without a shell the error names `/bin/sh`. `os.system` needs it too
  - the program runs with the rights of the app (`mobile`). `os.exec`, `os.fork` and `os.startfile` stay refused

`.elyx`

- archives and libraries over them. zwylib loads: settings, cache files, the asyncio loop, commands, hooks on the shims, reflection, xposed-style hooks on methods of the shims, `PluginsController`
- the pickers `GroupCreateActivity` and `DialogsActivity` open the chat picker of the app and call `onFragmentDestroy` when the person goes back. `select()` with chats ticked in advance is refused
- its `Requests` (beyond the requests listed above) and its autoupdater do not work

## dex

`dalvik.system` has file and memory class loaders over the python dex runtime (`python/shim/dexvm`, [dexvm.md](dexvm.md)). a loaded class has `call_static(name, *args)` and `new_instance(*args)`. `Class.forName(name, initialize, loader)` uses the loader given, and `Context.getClassLoader()` is the parent a plugin names for `InMemoryDexClassLoader`.

- java: `java.lang`, collections, `java.io`, `java.nio` (buffers, charset coders, `Files`), `java.util.stream`, `java.time`, `java.text` (`DecimalFormat`, `MessageFormat`), `org.json`, `JsonReader`, `JsonWriter`, atomics, `jar` manifests, `Handler`, `Looper`, `HandlerThread`
- dates: `Calendar` and `SimpleDateFormat`, english names only
- net: `java.net` and `javax.net.ssl`. sockets and `HttpURLConnection` are the python ones, tls is checked against the bundled roots, and a trust-all manager or host name verifier from a plugin does not relax that
- crypto: `Cipher` (AES ECB, CBC, CTR, GCM and RSA, in python, for small data), `Signature` (RSA), PBKDF2
- sqlite: `SQLiteDatabase` and `SQLiteOpenHelper` over the sqlite3 of the bundle
- android: `SharedPreferences`, `Log`, `Resources`, `Path`, `Matrix`, `PathMeasure`, `Rect`, spans
- zip: `ZipFile` and `ZipEntry` list and read entries without extracting. archive and entry limit 64 MiB, 4096 entries at most. `ZipInputStream`, `ZipOutputStream` and jar signature checks are not implemented
- call sites: `invoke-custom` links `LambdaMetafactory` (lambdas, method references, `altMetafactory` with markers and bridges), `StringConcatFactory` and any bootstrap method of the program. method handles work with `insertArguments`, `dropArguments`, `filterArguments`, `filterReturnValue`, `guardWithTest`, `permuteArguments`, `catchException`, `invokeExact`, `invoke` and `asType` conversions
- `Vibrator.hasVibrator()` is false, processes cannot be started

## does not work

- request hooks, `on_updates_hook`, and any `send_request` beyond those named in this file (the core keeps the tl layer out of python)
- `hook_all_constructors`, intent handlers
- `androidx.*`, `org.telegram.*` and `android.*` outside the shim, drawn text and video surfaces: the import fails naming the class
- dex plugins that hook or subclass screens of the android client: `ChatMessageCell`, `ChatActivityEnterView`, `StarGiftSheet`, `EmojiPacksAlert`, `AvatarSpan`, `MessageObject$GroupedMessages`, `MediaDataController`, `ActionBarMenuItem`, `Components.Paint`. the app draws those screens itself, so the load fails naming the class. 14 of the 46 catalog payloads fail this way
- `wp` and `unlim_accounts` need the android client. `exitFy_v2` loads an arm64 android `.so`
- `Canvas.drawTextRun`, `drawTextOnPath`, `drawPicture`, `Path.op`
- `os.fork`, `multiprocessing`, `ctypes`. haptics and sound effects do nothing
- the views of the app itself: a plugin sees only its own, and the root of the settings page

## exteria only

- `ImageView.setNativeSurface(name)`, `refreshSurface()`: frames a native module publishes (`core/pyhost/exteria_surface.h`)
- `exteria_sheet.present(...)`: a sheet like the one of the browser, with a native surface and touch keys

## host

`core/pyhost` is plain c: `exteria_pyhost_init`, `exteria_pyhost_call(module, func, json_args, timeout_ms, ...)` and `_exteria.service(name, json)`, which python uses to ask the app. entry points are in `python/shim/exteria_host.py`. uikit is served on the main thread only.

services are answered in:

- `app/platform/exteria_plugins.m` (`plugin_service`)
- `app/platform/exteria_plugin_ui.m`: `ui.*`, `sensor.*`, `theme.*`, `app.*`, `chat.*`, `sheet.*`, `bitmap.*`, `page.*`, `account.*`
- `exteria_plugin_audio.m`: `audio.open|start|stop|release`
- `exteria_plugin_music.m`: `music.state|entry|peek|start|pause|cleanup|detach|player`. the music player of `app/media` asks `exteria_host.music_play` and `music_pause` before a song starts or pauses
- `exteria_plugin_account.m`: `account.history|saved_music|save_music|delete|send_audio`, answered by `exteria_host.account_result`. the song upload has a `music` kind in `core/chats/exteria_messages.c`
- `exteria_plugin_bitmap.m`: `bitmap.decode|scale|crop|encode|copy|blur|release`, the blur is `core/media/exteria_stack_blur.c`
- `exteria_plugin_story.m`: `story.publish|forget`, and `account.story_post`

also `hook.display.add|remove`, `chat.rebuild`, `chat.send_photo`, `files.cache`, `app.current` (kind `settings` on the settings tab), `app.pick_image`, `app.pick_root`, `app.pick_time` (the wheel of `app/ui/shared/exteria_date_time_picker.m`, answered by `exteria_host.time_picked`), `page.cards`, `app.language`, `app.version`, `ui.alert` (with a `field` the answer comes back as `alert_result`).

## checked

with the real plugin file, a local server and the stand-in app of `tests/python/fakeapp.py`. 46 payloads of the exteraGram catalog were run through `exteria_host.load` against the stand-in app: 29 load.

- `qrcode`, `edge_tts_voiceover`, `zwylib.elyx`, `quoteReply`, `LocalEdictor`: load and work
- `settings_wallpaper`: picker, blur, dimming and see-through cards
- `message_cleaner` (`EXTERIA_MESSAGE_CLEANER`) and `music_tab` (`EXTERIA_MUSIC_TAB`): run with their real files
- `playlist_to_profile`: its libraries are in the bundle and its calls reach the app. `send_request` takes four requests and refuses any other by name:
  - `messages.getHistory` of Saved Messages (the newest 1 to 100, no offsets)
  - `users.getSavedMusic` of oneself (page after page up to the limit asked)
  - `account.saveMusic` (no `after_id`)
  - `messages.deleteMessages` of Saved Messages
- `send_audio` to Saved Messages runs the send hooks of the plugins over a document (they set title, performer, duration) and the app uploads it as a song
- the cover helper works with `BitmapFactory.decodeFile`, `Bitmap.createBitmap(source, x, y, w, h)`, `createScaledBitmap` and `compress` into a `FileOutputStream` in the plugin files folder
- gaps: the rounded cover of the progress panel is not drawn (no `BitmapShader` or `Canvas.drawRoundRect` over a picture), buttons have no ripple (`RippleDrawable` is its content), `setEllipsize` is kept but the label cuts at the line limit without a mark
- `device_fingerprint_spoofer`: `invokeWithLayer(initConnection(help.getNearestDc))` reaches the app
  - the record is serialized, read back and checked field by field. only `device_model`, `system_version` and `app_version` are taken (api id, lang pack and language fields stay the app's, the layer must be its own)
  - the app tells the server with its next request and keeps the texts until it restarts. the stand-in `Build` profile (`Apple` + `iPhone`) means the way back to the real device
  - the start hooks do not work (`ConnectionsManager` does not exist, so the app sends the real texts until the plugin applies its profile, a few seconds after load) and neither does the editor in the devices screen (`RecyclerListView` and `SessionsActivity` are android views). the status of the plugin says so
  - the media connections keep the real texts
- `zwyCrossfade`: against the stand-in music player, a tap on next and the end of a song take the old player out, fade it down while the new song fades in, and release it
- `story_scheduler` (`EXTERIA_STORY_SCHEDULER`, 12 tests): the story screen builds the page a plugin hooks (`StoryPrivacyBottomSheet.Page`, `bind`, `updateButton`)
  - the plugin puts its button under the audience pill, and a long press on publish opens its wheel (`AlertsCreator.createScheduleDatePickerDialog`, `DatePickerDialog` and `TimePickerDialog` use the same wheel)
  - a story about to go up is offered to `StoriesController.uploadStory` first, and a hook that sets a result holds it back. the plugin publishes it later through `account.story_post` (the file must lie in the temp folder or the plugins folder)
  - an audience that names people stays in the app under a number while python holds the story, 64 stories at most. a story restored after a restart has none and goes to everyone, as the plugin's own notes say
  - pictures only: a video, a channel or a group is refused by name (`MediaMetadataRetriever` too). the app publishes without `pinned` and `period`
  - the app must be running at the due time, and ios stops it in the background, so a story waits until the app is open again
  - `BasePlugin.logger` was added to the vendored sdk for it
- `audiovizualizer_plugin.elyx`: loads. its `VisualizerEngine` dex class loads through `DexClassLoader` from the code cache folder (`Context.getCodeCacheDir()`, inside the plugin files folder), and `install`, `configure` and `uninstall` answer through reflection. the plugin finds the dex next to `__file__`, which the sdk sets now. no audio level reaches it, the app has no visualizer
- `pixel_eyes`: loads its core from `InMemoryDexClassLoader` and builds its settings page. it failed on `Double.valueOf(String)` until the dex runtime got it (`Float`, `Short` and `Byte` too)
- `deleted_gift_sender`: loads, and `org.telegram.tgnet.tl.TL_stars` has `TL_starGift`, `TL_starGifts`, `TL_starGiftsNotModified` and `Tl_starsRating` as plain records. the response of `getStarGifts` never reaches python, so the plugin shows no gifts
- refused: `unlim_accounts` (java bytecode and a native library for the account limit of the android client), `ios_like_selection` (screens of the android client: `ChatActionCell`, `ChannelAdminLogActivity`, `ReactionsContainerLayout`, `ActionRow`), `meeow_reswaga.elyx` (android views, 7.6 MB)

## not run on a phone

host tests and a build for both slices are all that backs these. each needs a device pass:

- `message_cleaner` on a real chat, the bottom bar, `music_tab`
- `settings_wallpaper`: the page, the picker and the layer
- `playlist_to_profile`: download by yt-dlp, upload, `saveMusic`
- `device_fingerprint_spoofer`: whether the server shows the new device in the devices screen
- `zwyCrossfade`: a second `AVPlayer` next to the first, the volume of `AVPlayer` (ios 7 on), the audio mix that stands in for it on ios 5 and 6, the quiet start of a song while the plugin sets its volume
- `story_scheduler`: the button and the long press on the story screen, the wheel over it, the publish at the due time, the time zone of the phone in `datetime` (python takes the epoch and the parts from the app, not from its own clock)
- `audiovizualizer_plugin.elyx`: the drawing of the bars
- the pickers of zwylib, `onFragmentDestroy`
- `RenderEffect`, the software rasterizer, `Canvas.drawText` glyph look, dex runtime as a whole
- `mutagen` and `yt-dlp` import with the device stdlib, no download or tag write was run
- the static extensions (`pyexpat`, `bz2`, `lzma`, `sqlite3`) are checked for symbols and for the imports of the ios 5 runtime, not run

## build and test

`scripts/build_python.sh` builds cpython for armv7 (ios 5) and arm64 (ios 7) and stages `python/` (stdlib as bytecode, shim, sdk, ca bundle) for the app. run it again after a change in `python/shim` or `third_party/exteraless`, or the app keeps the old copy.

it needs `EXTERIA_PYTHON_TARBALL` (Python-3.11.9.tar.xz), `EXTERIA_PYTHON_CACERT` (cacert.pem), `EXTERIA_PYTHON_WHEELS` (a directory with the wheels of `third_party/python/wheels.sha256`, checked by hash), the openssl prefixes and the toolchain variables of the app build.

```bash
make -C tests test \
  EXTERIA_PYTHON_HOST_PREFIX=<cpython 3.11 prefix> EXTERIA_PYTHON_STDLIB=<its Lib directory> \
  EXTERIA_PYTHON_HOST=<python3.11>
```

`test` runs the c tests, the interpreter host and the python tests.
