"""the bottom bar as a plugin sees it (MainTabsActivity), and the music_tab plugin over the stand-in app: it retitles the second tab, takes its tap and
plays the newest or oldest song of a chat or the song of a profile. EXTERIA_MUSIC_TAB names the file of the real plugin"""

import json
import os
import shutil
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402
from org.telegram.tgnet import TLRPC, requests  # noqa: E402
from org.telegram.ui import MainTabsActivity  # noqa: E402

PLUGINS = None
_saved = {}


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-tabs-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def song(number):
    return {"id": 2000 + number, "access_hash": 5, "dc": 2, "file_ref": "%02x" % number, "size": 100 + number, "name": "s%d.mp3" % number,
            "mime": "audio/mpeg", "title": "T%d" % number, "performer": "P%d" % number, "duration": 60 + number, "thumb": False}


def song_message(number, doc=None):
    return {"id": number, "text": "", "date": number, "doc": doc or song(number)}


def settle(until, timeout=3):
    end = time.time() + timeout
    while time.time() < end:
        # the main thread of the app: queued calls (run_on_ui_thread) and the answers of the account
        while fake.timers:
            exteria_host.run_token(fake.timers.pop(0)[0])
        fake.deliver()
        if until():
            return True
        time.sleep(0.005)
    return False


class Tabs(unittest.TestCase):
    def setUp(self):
        fake.tabs.clear()
        MainTabsActivity._single.clear()

    def test_a_tab_is_retitled_and_given_an_icon_and_listeners(self):
        from android.view import View
        from java import jclass
        tab = MainTabsActivity.instance().tabs[1]
        tab.setText("Music")
        self.assertEqual(fake.tabs[1]["title"], "Music")
        context = jclass("org.telegram.messenger.ApplicationLoader").applicationContext
        resources = context.getResources()
        number = resources.getIdentifier("files_music", "drawable", context.getPackageName())
        self.assertNotEqual(number, 0)
        self.assertEqual(resources.getIdentifier("nothing_here", "drawable", context.getPackageName()), 0)
        image = tab.getChildAt(0)
        image.setImageDrawable(context.getDrawable(number).mutate())
        self.assertEqual(fake.tabs[1]["icon"], "music")
        self.assertEqual((fake.tabs[1]["click"], fake.tabs[1]["hold"]), (False, False))
        taps = []
        tab.setOnClickListener(View.OnClickListener())
        tab.setOnClickListener(lambda view: taps.append(view))
        tab.setOnLongClickListener(None)
        self.assertEqual((fake.tabs[1]["click"], fake.tabs[1]["hold"]), (True, False))
        exteria_host.tab_event(1, "click")
        self.assertEqual(taps, [tab])
        exteria_host.tab_event(1, "hold")
        self.assertEqual(taps, [tab])

    def test_the_bar_has_the_icons_of_the_app_only(self):
        from android.graphics.drawable import ColorDrawable
        with self.assertRaises(TypeError):
            MainTabsActivity.instance().tabs[1].getChildAt(0).setImageDrawable(ColorDrawable(0))

    def test_the_main_screen_is_in_the_fragment_stack_while_the_bar_is_up(self):
        from org.telegram.ui import LaunchActivity
        stack = LaunchActivity.instance.getActionBarLayout().getFragmentStack()
        self.assertEqual(stack.get(0).getClass().getSimpleName(), "MainTabsActivity")
        fake.tabs_up = False
        try:
            self.assertEqual(LaunchActivity.instance.getActionBarLayout().getFragmentStack().size(), 0)
        finally:
            fake.tabs_up = True

    def test_the_events_of_the_bar_reach_the_hooks(self):
        seen = []
        activity = MainTabsActivity.instance()
        activity.createView = lambda context: seen.append("create")
        activity.onResume = lambda: seen.append("resume")
        exteria_host.fragment_event("tabs", "create", 0, 0)
        exteria_host.fragment_event("tabs", "resume", 0, 0)
        self.assertEqual(seen, ["create", "resume"])
        with self.assertRaises(ValueError):
            exteria_host.fragment_event("tabs", "pause", 0, 0)


class Search(unittest.TestCase):
    def setUp(self):
        fake.saved.update(messages=[], music=[], next_id=100, calls=[], errors={}, inbox=[], chat_music={}, profile_music={})
        fake.peers = {-500, 600}

    def send(self, request):
        box = {}
        requests.send(request, lambda response, error: box.update(response=response, error=error))
        self.assertTrue(settle(lambda: box))
        return box["response"], box["error"]

    def request(self, peer, offset_id=0, add_offset=0, limit=1):
        request = TLRPC.TL_messages_search()
        request.peer, request.limit, request.offset_id, request.add_offset = peer, limit, offset_id, add_offset
        request.filter = TLRPC.TL_inputMessagesFilterMusic()
        return request

    def test_the_newest_and_the_oldest_song_of_a_chat(self):
        fake.saved["chat_music"][-500] = [song_message(3), song_message(1), song_message(2)]
        response, error = self.send(self.request(TLRPC.TL_inputPeerChat(chat_id=500)))
        self.assertIsNone(error)
        self.assertEqual([m.id for m in response.messages], [3])
        self.assertEqual(response.messages.get(0).media.document.id, 2003)
        response, _ = self.send(self.request(TLRPC.TL_inputPeerChat(chat_id=500), 1, -1))
        self.assertEqual([m.id for m in response.messages], [1])
        self.assertEqual(fake.saved["calls"][-1][1], {"dialog": -500, "first": True, "token": fake.saved["calls"][-1][1]["token"]})

    def test_saved_messages_and_a_chat_without_songs(self):
        response, error = self.send(self.request(TLRPC.TL_inputPeerSelf()))
        self.assertIsNone(error)
        self.assertEqual(response.messages.size(), 0)

    def test_a_chat_the_app_does_not_know_is_an_error_of_the_server(self):
        response, error = self.send(self.request(TLRPC.TL_inputPeerChat(chat_id=999)))
        self.assertIsNone(response)
        self.assertEqual((error.text, error.code), ("PEER_ID_INVALID", 400))

    def test_what_the_app_cannot_search_is_refused_and_nothing_is_sent(self):
        wrong = self.request(TLRPC.TL_inputPeerSelf())
        wrong.filter = None
        cases = [wrong, self.request(TLRPC.TL_inputPeerSelf(), limit=2), self.request(TLRPC.TL_inputPeerSelf(), 5, 0),
                 self.request(TLRPC.TL_inputPeerEmpty())]
        text = self.request(TLRPC.TL_inputPeerSelf())
        text.q = "x"
        cases.append(text)
        for request in cases:
            with self.assertRaises(NotImplementedError):
                requests.send(request, lambda *_: None)
        self.assertEqual(fake.saved["calls"], [])

    def test_the_music_of_the_profile_of_a_known_user(self):
        fake.saved["profile_music"][600] = [song(7), song(8)]
        request = TLRPC.TL_getSavedMusic()
        request.id = TLRPC.TL_inputUser(user_id=600)
        request.limit = 1
        response, error = self.send(request)
        self.assertIsNone(error)
        self.assertIsInstance(response, TLRPC.TL_savedMusic)
        self.assertEqual([d.id for d in response.documents], [2007])
        self.assertEqual(fake.saved["calls"][-1][1]["user"], 600)
        request.id = TLRPC.TL_inputUser(user_id=601)
        self.assertEqual(self.send(request)[1].text, "USER_ID_INVALID")

    def test_the_peers_of_the_controller_follow_the_chat_list(self):
        from org.telegram.messenger import MessagesController
        controller = MessagesController.getInstance()
        self.assertEqual(controller.getUser(600).id, 600)
        self.assertIsNone(controller.getUser(601))
        self.assertEqual(controller.getChat(500).id, 500)
        self.assertIsNone(controller.getChat(600))
        self.assertIsInstance(controller.getInputPeer(fake.me), TLRPC.TL_inputPeerSelf)
        self.assertIsInstance(controller.getInputPeer(-500), TLRPC.TL_inputPeerChat)
        self.assertIsInstance(controller.getInputPeer(-1), TLRPC.TL_inputPeerEmpty)
        self.assertIsNone(controller.getInputUser(601))


@unittest.skipUnless(os.environ.get("EXTERIA_MUSIC_TAB"), "set EXTERIA_MUSIC_TAB to the file of the plugin")
class RealPlugin(unittest.TestCase):
    def setUp(self):
        fake.tabs.clear()
        fake.played.clear()
        fake.settings.clear()
        fake.peers = {-500, 600}
        fake.saved.update(messages=[], music=[], next_id=100, calls=[], errors={}, inbox=[], chat_music={}, profile_music={})
        path = os.path.join(PLUGINS, "music_tab.plugin")
        shutil.copy(os.environ["EXTERIA_MUSIC_TAB"], path)
        lib = os.environ.get("EXTERIA_PYTHON_LIB")
        if lib:
            sys.path.insert(0, lib)
        self.result = exteria_host.load(path, "music_tab")
        self.assertTrue(self.result["ok"], self.result)
        # the plugin patches the bar from a call queued for the main thread
        self.assertTrue(settle(lambda: 1 in fake.tabs))

    def tearDown(self):
        exteria_host.unload("music_tab")

    def configure(self, **values):
        for key, value in values.items():
            fake.settings[("music_tab", key)] = json.dumps(value)

    def tap(self):
        exteria_host.tab_event(1, "click")

    def test_loading_patches_the_bar_that_is_up(self):
        self.assertTrue(settle(lambda: 1 in fake.tabs))
        self.assertEqual((fake.tabs[1]["title"], fake.tabs[1]["icon"], fake.tabs[1]["click"], fake.tabs[1]["hold"]), ("Музыка", "music", True, False))

    def test_a_bar_built_later_is_patched_by_its_events(self):
        fake.tabs.clear()
        exteria_host.fragment_event("tabs", "create", 0, 0)
        self.assertEqual(fake.tabs[1]["title"], "Музыка")

    def test_a_tap_plays_the_newest_song_of_saved_messages(self):
        fake.saved["chat_music"][fake.me] = [song_message(1), song_message(2)]
        self.tap()
        self.assertTrue(settle(lambda: fake.played))
        played = fake.played[-1]
        self.assertEqual((played["index"], [d["id"] for d in played["docs"]]), (0, [2002]))
        self.assertEqual((played["docs"][0]["title"], played["docs"][0]["file_ref"], played["docs"][0]["mime"]), ("T2", "02", "audio/mpeg"))

    def test_the_first_song_of_another_chat(self):
        self.configure(chat_source=1, chat_id="-100500", music_order=1)
        fake.saved["chat_music"][-500] = [song_message(4), song_message(3)]
        self.tap()
        self.assertTrue(settle(lambda: fake.played))
        self.assertEqual([d["id"] for d in fake.played[-1]["docs"]], [2003])

    def test_a_song_of_a_profile(self):
        self.configure(chat_source=1, chat_id="600", music_source=1)
        fake.saved["profile_music"][600] = [song(9)]
        self.tap()
        self.assertTrue(settle(lambda: fake.played))
        self.assertEqual([d["id"] for d in fake.played[-1]["docs"]], [2009])


if __name__ == "__main__":
    unittest.main()
