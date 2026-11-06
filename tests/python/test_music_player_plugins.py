"""the music player as plugins see it: MediaController with its private fields, the hooks on playMessage, cleanupPlayer and pauseMessage that run before the music
player of the app acts, the players of VideoPlayer that are taken out and faded, and the rows of a slide view. the stand-in app (fakeapp.Music) follows the rules of
exteria_plugin_music.m. the real zwyCrossfade runs when EXTERIA_ZWYLIB and EXTERIA_CROSSFADE name the files"""

import json
import os
import shutil
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402

PLUGINS = None
_saved = {}

SONGS = [{"key": "k%d" % i, "kind": "music", "title": "song %d" % i, "performer": "p", "name": "s%d.mp3" % i, "duration": 30, "size": 1000, "path": ""}
         for i in range(3)]

HEADER = '''
__id__ = "%(id)s"
__name__ = "%(id)s"
__description__ = "test"
__author__ = "test"
__version__ = "1.0"
__min_version__ = "11.9.0"
__icon__ = "msg_edit"
'''


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-music-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def pump(until, seconds=6):
    """runs the timers the plugins queued, each when its delay is up (the app runs them on the main thread), until the condition holds"""
    end = time.time() + seconds
    waiting = []
    while time.time() < end:
        now = time.time()
        while fake.timers:
            token, delay = fake.timers.pop(0)
            waiting.append((now + delay / 1000.0, token))
        due = [item for item in waiting if item[0] <= now]
        waiting = [item for item in waiting if item[0] > now]
        for _when, token in sorted(due):
            exteria_host.run_token(token)
        if until():
            return True
        time.sleep(0.002)
    return False


class Player(unittest.TestCase):
    def setUp(self):
        fake.music.reset(SONGS)
        from org.telegram.messenger import MediaController
        self.controller = MediaController.getInstance()
        self.controller._detached = 0

    def tearDown(self):
        from de.robv.android.xposed import XposedBridge
        for chain in list(XposedBridge._chains.values()):
            for entry in list(chain.entries):
                entry[2].unhook()

    def test_the_fields_a_plugin_reflects_on_are_there_and_typed(self):
        from org.telegram.messenger import MediaController
        clazz = MediaController.getClass()
        for name in ("audioPlayer", "audioVolume", "audioVolumeAnimator", "reporter", "audioFocus", "shuffledPlaylist", "forceLoopCurrentPlaylist"):
            clazz.getDeclaredField(name).setAccessible(True)
        volume = clazz.getDeclaredField("audioVolume")
        volume.setFloat(self.controller, 0.25)
        self.assertEqual((volume.getFloat(self.controller), volume.get(self.controller)), (0.25, 0.25))
        self.assertEqual(clazz.getDeclaredField("audioFocus").getInt(self.controller), 2)
        self.assertFalse(clazz.getDeclaredField("forceLoopCurrentPlaylist").getBoolean(self.controller))
        self.assertEqual([m.getName() for m in clazz.getDeclaredMethods() if m.getName() in ("playMessage", "cleanupPlayer", "pauseMessage")].count("playMessage"), 1)
        self.assertEqual(clazz.getName(), "org.telegram.messenger.MediaController")

    def test_the_playlist_is_in_the_order_of_the_android_client(self):
        self.assertEqual((self.controller.getPlaylist().size(), self.controller.getPlayingMessageObjectNum()), (3, -1))
        fake.music.start(0)
        playlist = self.controller.getPlaylist()
        # the next song is the one before the current: the first song of the app is the last of the list
        self.assertEqual([playlist.get(i).getId() for i in range(3)], [2, 1, 0])
        self.assertEqual(self.controller.getPlayingMessageObjectNum(), 2)
        self.assertEqual(playlist.get(self.controller.getPlayingMessageObjectNum() - 1).getId(), 1)
        message = self.controller.getPlayingMessageObject()
        self.assertTrue(message.isMusic() and not message.isVoice() and not message.shouldEncryptPhotoOrVideo())
        with self.assertRaises(IndexError):
            playlist.get(3)

    def test_the_settings_of_the_player_are_read_when_asked(self):
        from org.telegram.messenger import SharedConfig
        self.assertEqual((SharedConfig.shuffleMusic, SharedConfig.repeatMode, SharedConfig.playOrderReversed, SharedConfig.streamMedia), (False, 0, False, True))
        fake.music.shuffle, fake.music.repeat = True, 2
        self.assertEqual((SharedConfig.shuffleMusic, SharedConfig.repeatMode), (True, 2))

    def test_a_secret_chat_is_told_by_its_bits(self):
        from org.telegram.messenger import DialogObject
        for dialog, encrypted in ((5, False), (-1001234567890, False), (0x4000000000000005, True), (-0x3FFFFFFFFFFFFFFF, False), (0, False)):
            self.assertIs(DialogObject.isEncryptedDialog(dialog), encrypted, hex(dialog))

    def test_cast_and_the_file_of_a_song(self):
        from java import jclass
        from org.telegram.messenger import FileLoader
        self.assertFalse(jclass("org.telegram.ui.CastSync").isActive())
        fake.music.start(0)
        message = self.controller.getPlayingMessageObject()
        self.assertFalse(FileLoader.getInstance(0).getPathToMessage(message.messageOwner).exists())
        path = os.path.join(PLUGINS, "song.mp3")
        with open(path, "wb") as handle:
            handle.write(b"x")
        from org.telegram.messenger.music import _message_of
        there = _message_of(dict(SONGS[0], index=0, path=path))
        self.assertTrue(FileLoader.getInstance(0).getPathToMessage(there.messageOwner).exists())

    def test_without_a_hook_the_app_starts_the_song_itself(self):
        fake.music.app_starts(1)
        self.assertEqual(fake.music.log, [("start", 1)])

    def test_a_hook_runs_before_the_app_starts_a_song_and_can_stop_it(self):
        from de.robv.android.xposed import XC_MethodHook, XposedBridge
        seen = []

        class Hook(XC_MethodHook):
            def beforeHookedMethod(self, param):
                seen.append(("before", param.args[0].getId(), param.thisObject.getPlayingMessageObject()))
                if param.args[0].getId() == 2:
                    param.setResult(False)

            def afterHookedMethod(self, param):
                seen.append(("after", param.args[0].getId(), param.getResult()))

        from org.telegram.messenger import MediaController
        XposedBridge.hookMethod(MediaController.getClass().getDeclaredMethod("playMessage"), Hook())
        fake.music.app_starts(0)
        self.assertEqual(fake.music.log, [("start", 0)])
        self.assertEqual([item[:2] for item in seen], [("before", 0), ("after", 0)])
        self.assertIsNone(seen[0][2])
        self.assertTrue(seen[1][2])
        seen[:] = []
        fake.music.app_starts(2)
        # a before callback that sets a result skips the original; the after callbacks of the hooks that ran still hear it, as in xposed
        self.assertEqual((fake.music.log, [item[:2] for item in seen], seen[1][2]), ([("start", 0)], [("before", 2), ("after", 2)], False))

    def test_a_hook_on_pauseMessage_runs_before_the_app_pauses(self):
        from de.robv.android.xposed import XC_MethodHook, XposedBridge
        from org.telegram.messenger import MediaController
        seen = []

        class Hook(XC_MethodHook):
            def afterHookedMethod(self, param):
                seen.append(param.getResult())

        fake.music.start(0)
        fake.music.app_pauses()
        self.assertEqual(fake.music.state, "paused")
        fake.music.state = "playing"
        XposedBridge.hookMethod(MediaController.getClass().getDeclaredMethod("pauseMessage"), Hook())
        fake.music.app_pauses()
        self.assertEqual((fake.music.state, seen), ("paused", [True]))

    def test_a_player_taken_out_plays_on_until_it_is_released(self):
        fake.music.start(0)
        player = self.controller.audioPlayer
        self.assertTrue(player.isPlaying() and player.equals(self.controller.audioPlayer))
        self.controller.audioPlayer = None
        self.assertIsNone(self.controller.audioPlayer)
        player.setVolume(0.5)
        self.assertEqual(fake.music.ghosts[player._id]["volume"], 0.5)
        self.controller.cleanupPlayer(True, True, False, False)
        self.controller.playMessage(self.controller.getPlaylist().get(1))
        self.assertEqual(fake.music.playback, 2)
        fresh = self.controller.audioPlayer
        self.assertFalse(fresh.equals(player))
        player.releasePlayer(True)
        self.assertEqual(fake.music.ghosts, {})
        with self.assertRaises(RuntimeError):
            player.setVolume(0)
        with self.assertRaises(NotImplementedError):
            self.controller.audioPlayer = fresh
        with self.assertRaises(NotImplementedError):
            self.controller.playMessage(type(self.controller.getPlayingMessageObject())(self.controller.getPlayingMessageObject().messageOwner, 0))

    def test_playNextMessage_follows_the_repeat_mode(self):
        fake.music.start(2)
        self.assertFalse(self.controller.playNextMessage())
        fake.music.repeat = 1
        self.assertTrue(self.controller.playNextMessage())
        self.assertEqual(fake.music.index, 0)


SLIDE = HEADER + '''
from base_plugin import BasePlugin
from ui.settings import Header, Custom, Text
from java import jarray
from java.lang import String
from org.telegram.ui.Components import UItem
from org.telegram.messenger import Utilities

class Pick(Utilities.Callback):
    def __init__(self, plugin):
        super().__init__()
        self.plugin = plugin

    def run(self, index):
        self.plugin.set_setting("chosen", index)


class Slides(BasePlugin):
    def create_settings(self):
        item = UItem.asSlideView(jarray(String)(["off", "1", "2"]), 1, Pick(self))
        return [Header("Duration"), Custom(item=item), Text(text="tap", on_click=lambda v: None), Custom(item=item)]
'''


class SlideRows(unittest.TestCase):
    def test_a_slide_view_is_a_row_of_choices_and_its_answer_reaches_the_callback(self):
        path = os.path.join(PLUGINS, "slides.plugin")
        with open(path, "w") as handle:
            handle.write(SLIDE % {"id": "slides"})
        self.assertTrue(exteria_host.load(path, "slides")["ok"])
        try:
            rows = exteria_host.settings("slides")
            self.assertEqual([row["type"] for row in rows], ["selector", "text", "selector"])
            self.assertEqual((rows[0]["text"], rows[0]["items"], rows[0]["value"]), ("Duration", ["off", "1", "2"], 1))
            self.assertTrue(rows[0]["key"].startswith("__slide:"))
            self.assertEqual(rows[2]["text"], "")
            exteria_host.setting_changed("slides", rows[0]["key"], "2")
            self.assertEqual(json.loads(fake.settings[("slides", "chosen")]), 2)
            self.assertNotIn(("slides", rows[0]["key"]), fake.settings)
            for wrong in ("3", "-1", '"1"', "null"):
                with self.assertRaises(ValueError):
                    exteria_host.setting_changed("slides", rows[0]["key"], wrong)
        finally:
            exteria_host.unload("slides")


CROSSFADE = os.environ.get("EXTERIA_CROSSFADE")
ZWYLIB = os.environ.get("EXTERIA_ZWYLIB")


@unittest.skipUnless(CROSSFADE and ZWYLIB, "set EXTERIA_ZWYLIB and EXTERIA_CROSSFADE to the zwylib .elyx and the zwyCrossfade .plugin")
class Crossfade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fake.calls.clear()
        fake.settings.clear()
        assert exteria_host.load(ZWYLIB, "zwylib")["ok"]
        cls.path = os.path.join(PLUGINS, "zwyCrossfade.plugin")
        shutil.copy(CROSSFADE, cls.path)
        result = exteria_host.load(cls.path, "zwyCrossfade")
        assert result["ok"], result

    @classmethod
    def tearDownClass(cls):
        exteria_host.unload("zwyCrossfade")
        exteria_host.unload("zwylib")

    def setUp(self):
        fake.music.reset(SONGS)
        fake.timers.clear()
        from org.telegram.messenger import MediaController
        MediaController.getInstance()._detached = 0

    def test_its_settings_are_rows_of_choices_and_a_selector(self):
        rows = exteria_host.settings("zwyCrossfade")
        slides = [row for row in rows if row.get("key", "").startswith("__slide:")]
        self.assertEqual([row["items"] for row in slides], [["1", "2", "3", "5", "8", "12"], ["Off", "1", "2", "3", "4", "5"]])
        self.assertEqual([row["value"] for row in slides], [3, 1])
        self.assertEqual(len([row for row in rows if row["type"] == "selector"]), 3)
        self.assertFalse([row for row in rows if row["type"] == "custom"])
        exteria_host.setting_changed("zwyCrossfade", slides[0]["key"], "5")
        self.assertEqual(json.loads(fake.settings[("zwyCrossfade", "auto_duration_sec")]), 12)
        exteria_host.setting_changed("zwyCrossfade", slides[0]["key"], "3")
        self.assertEqual(json.loads(fake.settings[("zwyCrossfade", "auto_duration_sec")]), 5)

    def test_a_tap_on_next_fades_the_old_song_out_while_the_new_one_fades_in(self):
        slides = [row for row in exteria_host.settings("zwyCrossfade") if row.get("key", "").startswith("__slide:")]
        exteria_host.setting_changed("zwyCrossfade", slides[1]["key"], "1")
        fake.music.app_starts(0)
        fake.music.position_ms = 10000
        fake.music.app_starts(1)
        self.assertEqual((fake.music.playback, fake.music.index), (2, 1))
        self.assertEqual(sorted(fake.music.ghosts), [1], "the old player was taken out and plays on")
        self.assertEqual(fake.music.volumes[0], (2, 0.0), "the new song starts silent")
        fake.music.position_ms = 200
        gone = pump(lambda: not fake.music.ghosts and fake.music.volume == 1.0, 6)
        self.assertTrue(gone, (fake.music.ghosts, fake.music.volume, fake.music.volumes[-4:]))
        old = [value for playback, value in fake.music.volumes if playback == 1]
        new = [value for playback, value in fake.music.volumes if playback == 2]
        self.assertTrue(len(old) >= 3 and old == sorted(old, reverse=True) and old[-1] < 0.5, old)
        self.assertTrue(len(new) >= 3 and new == sorted(new) and new[-1] == 1.0, new)
        self.assertEqual([item for item in fake.music.log if item[0] in ("detach", "release")], [("detach", 1), ("release", 1)])

    def test_a_song_that_nears_its_end_starts_the_next_one_by_itself(self):
        fake.music.app_starts(0)
        fake.music.position_ms = 29600
        started = pump(lambda: fake.music.playback == 2, 6)
        self.assertTrue(started, fake.music.log)
        self.assertEqual(fake.music.index, 1)
        self.assertEqual(sorted(fake.music.ghosts) in ([1], []), True)
        fake.music.position_ms = 100
        self.assertTrue(pump(lambda: not fake.music.ghosts and fake.music.volume == 1.0, 8), (fake.music.ghosts, fake.music.volume))

    def test_it_does_nothing_to_the_last_song_of_a_list_that_does_not_repeat(self):
        fake.music.app_starts(2)
        fake.music.position_ms = 29900
        pump(lambda: False, 0.4)
        self.assertEqual((fake.music.playback, fake.music.ghosts), (1, {}))


if __name__ == "__main__":
    unittest.main()
