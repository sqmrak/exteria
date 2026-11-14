"""the requests a plugin may send (Saved Messages, the saved music of the profile), and an audio file sent to Saved Messages with the attributes
a send hook sets. the app is the stand-in of fakeapp.py; the real playlist_to_profile plugin runs its own helpers over it when
EXTERIA_PLAYLIST_PLUGIN names its file"""

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
from java.lang import Integer  # noqa: E402
from org.telegram.tgnet import TLRPC, requests  # noqa: E402

PLUGINS = None
_saved = {}

HEADER = '''
__id__ = "%(id)s"
__name__ = "%(id)s"
__description__ = "test"
__author__ = "test"
__version__ = "1.0"
__min_version__ = "11.9.0"
__icon__ = "msg_edit"
'''

TAGGER = HEADER + '''
from base_plugin import BasePlugin, HookResult, HookStrategy
from org.telegram.tgnet import TLRPC


class Tagger(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook()

    def on_send_message_hook(self, account, params):
        document = params.document
        self.set_setting("seen", [params.path.rsplit("/", 1)[-1], document.mime_type, int(document.size), params.peer])
        if "stop" in params.path:
            return HookResult(strategy=HookStrategy.CANCEL)
        audio = TLRPC.TL_documentAttributeAudio()
        audio.flags = 3
        audio.duration = 215
        audio.title = "Название"
        audio.performer = "Artist"
        document.attributes.add(audio)
        return HookResult(strategy=HookStrategy.MODIFY, params=params)
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


def song(number, **fields):
    doc = {"id": 1000 + number, "access_hash": 5, "dc": 2, "file_ref": "%02x" % number, "size": 100 + number, "name": "s%d.mp3" % number, "mime": "audio/mpeg",
           "title": "T%d" % number, "performer": "P%d" % number, "duration": 60 + number, "thumb": number % 2 == 0}
    doc.update(fields)
    return doc


def call(request, timeout=3):
    """send a request and wait for the answer the way a plugin thread does"""
    done = threading.Event()
    box = {}

    def callback(response, error):
        box["response"], box["error"] = response, error
        done.set()

    requests.send(request, callback)
    end = time.time() + timeout
    while not done.is_set() and time.time() < end:
        if not fake.deliver():
            time.sleep(0.005)
    if not done.is_set():
        raise AssertionError("no answer")
    return box["response"], box["error"]


def history(limit=10):
    request = TLRPC.TL_messages_getHistory()
    request.peer = TLRPC.TL_inputPeerUser(user_id=fake.me)
    request.limit = limit
    return request


def saved_music(limit=100, offset=0):
    request = TLRPC.TL_users_getSavedMusic()
    request.id = TLRPC.TL_inputUserSelf()
    request.limit, request.offset = limit, offset
    return request


class Requests(unittest.TestCase):
    def setUp(self):
        fake.saved.update(messages=[], music=[], next_id=100, calls=[], errors={}, inbox=[])
        fake.calls.clear()

    def test_the_newest_messages_of_saved_messages_come_with_their_documents(self):
        fake.saved["messages"] = [{"id": 5, "text": "hello", "date": 7}, {"id": 6, "text": "cap", "date": 8, "doc": song(2)}]
        response, error = call(history(10))
        self.assertIsNone(error)
        messages = list(response.messages)
        self.assertEqual([m.id for m in messages], [6, 5])
        self.assertIsNone(messages[1].media)
        document = messages[0].media.document
        self.assertEqual((document.id, document.access_hash, document.size, document.mime_type), (1002, 5, 102, "audio/mpeg"))
        self.assertEqual(document.file_reference, bytes([2]))
        names = [type(a).__name__ for a in document.attributes]
        self.assertEqual(names, ["TL_documentAttributeFilename", "TL_documentAttributeAudio"])
        audio = document.attributes.get(1)
        self.assertEqual((audio.title, audio.performer, audio.duration), ("T2", "P2", 62))
        self.assertEqual(document.thumbs.size(), 1)
        self.assertEqual(call(history(10))[0].messages.get(0).message, "cap")

    def test_a_document_the_server_made_no_thumbnail_for_has_none(self):
        fake.saved["messages"] = [{"id": 6, "text": "", "date": 8, "doc": song(3)}]
        document = call(history(5))[0].messages.get(0).media.document
        self.assertEqual(list(document.thumbs), [])

    def test_the_newest_messages_of_saved_messages_are_read_without_an_open_chat_and_the_limit_is_bounded(self):
        for peer in (None, TLRPC.InputPeer()):
            request = history()
            request.peer = peer
            with self.assertRaises(NotImplementedError):
                requests.send(request, lambda *_: None)
        for limit in (0, 101, -1):
            with self.assertRaises(ValueError):
                requests.send(history(limit), lambda *_: None)
        # a window that is not the newest page is read from the open chat, by offset_id only
        for field in ("offset_date", "add_offset", "max_id", "min_id"):
            request = history()
            setattr(request, field, 5)
            with self.assertRaises(NotImplementedError):
                requests.send(request, lambda *_: None)
        self.assertEqual(fake.saved["calls"], [])
        request = history()
        request.peer = TLRPC.TL_inputPeerSelf()
        self.assertIsNone(call(request)[1])
        self.assertEqual(fake.saved["calls"][-1][0], "history")
        paged = history()
        paged.offset_id = 50
        requests.send(paged, lambda *_: None)
        self.assertEqual(fake.saved["calls"][-1][0], "chat_page")

    def test_the_saved_music_is_read_page_after_page_up_to_the_limit_the_plugin_asked_for(self):
        fake.saved["music"] = [song(n) for n in range(65)]
        response, error = call(saved_music(100))
        self.assertIsNone(error)
        self.assertEqual(response.count, 65)
        self.assertEqual([d.id for d in response.documents], [1000 + n for n in range(65)])
        self.assertEqual([c[1]["offset"] for c in fake.saved["calls"]], [0, 30, 60])
        fake.saved["calls"][:] = []
        response, _ = call(saved_music(40))
        self.assertEqual(len(response.documents), 40)
        self.assertEqual([c[1]["offset"] for c in fake.saved["calls"]], [0, 30])

    def test_an_empty_profile_has_no_songs_and_one_page_is_asked(self):
        response, error = call(saved_music(100))
        self.assertIsNone(error)
        self.assertEqual((response.count, list(response.documents)), (0, []))
        self.assertEqual(len(fake.saved["calls"]), 1)

    def test_a_song_is_put_on_the_profile_and_taken_off_it(self):
        fake.saved["messages"] = [{"id": 9, "text": "", "date": 1, "doc": song(4)}]
        document = call(history(5))[0].messages.get(0).media.document
        save = TLRPC.TL_account_saveMusic()
        save.id = TLRPC.TL_inputDocument(id=document.id, access_hash=document.access_hash, file_reference=document.file_reference)
        response, error = call(save)
        self.assertIsNone(error)
        self.assertIsInstance(response, TLRPC.TL_boolTrue)
        op, data = fake.saved["calls"][-1]
        self.assertEqual((op, data["unsave"], data["doc"]), ("save_music", False, {"id": 1004, "access_hash": 5, "dc": 0, "file_ref": "04"}))
        self.assertEqual([d["id"] for d in fake.saved["music"]], [1004])
        unsave = TLRPC.TL_account_saveMusic()
        unsave.flags, unsave.unsave, unsave.id = 1, True, save.id
        self.assertIsNone(call(unsave)[1])
        self.assertTrue(fake.saved["calls"][-1][1]["unsave"])
        self.assertEqual(fake.saved["music"], [])
        # the flag alone, as the android client sets it, is enough
        flagged = TLRPC.TL_account_saveMusic()
        flagged.flags, flagged.id = 1, save.id
        call(flagged)
        self.assertTrue(fake.saved["calls"][-1][1]["unsave"])

    def test_a_song_cannot_be_put_after_another_or_named_by_something_else(self):
        save = TLRPC.TL_account_saveMusic()
        save.id = TLRPC.TL_inputDocument(id=1, access_hash=2, file_reference=b"x")
        save.after_id = TLRPC.TL_inputDocument(id=3)
        with self.assertRaises(NotImplementedError):
            requests.send(save, lambda *_: None)
        save.after_id = None
        save.id = TLRPC.InputDocument()
        with self.assertRaises(NotImplementedError):
            requests.send(save, lambda *_: None)

    def test_messages_of_saved_messages_are_deleted_by_id(self):
        fake.saved["messages"] = [{"id": 1, "text": "a", "date": 1}, {"id": 2, "text": "b", "date": 1}]
        request = TLRPC.TL_messages_deleteMessages()
        request.id.add(Integer(2))
        request.revoke = True
        response, error = call(request)
        self.assertIsNone(error)
        self.assertIsInstance(response, TLRPC.TL_messages_affectedMessages)
        self.assertEqual(fake.saved["calls"][-1], ("delete", {"token": fake.saved["calls"][-1][1]["token"], "ids": [2], "revoke": True}))
        self.assertEqual([m["id"] for m in fake.saved["messages"]], [1])
        for ids in ([], [0], [-3], list(range(1, 102))):
            bad = TLRPC.TL_messages_deleteMessages()
            for one in ids:
                bad.id.add(Integer(one))
            with self.assertRaises(ValueError):
                requests.send(bad, lambda *_: None)

    def test_a_failure_of_the_app_reaches_the_plugin_as_an_error_with_a_code(self):
        for text, code in (("FLOOD_WAIT_12", 420), ("DOCUMENT_INVALID", 400), ("AUTH_KEY_UNREGISTERED", 401), ("INTERNAL", 500)):
            fake.saved["errors"]["history"] = text
            response, error = call(history())
            self.assertIsNone(response)
            self.assertEqual((error.text, error.code), (text, code))

    def test_any_other_request_is_refused_by_name_and_nothing_is_sent(self):
        class TL_account_deleteAccount(TLRPC._Record):
            pass

        with self.assertRaises(NotImplementedError) as raised:
            requests.send(TL_account_deleteAccount(), lambda *_: None)
        self.assertIn("TL_account_deleteAccount", str(raised.exception))
        self.assertEqual(fake.saved["calls"], [])

    def test_send_request_of_the_sdk_passes_the_refusal_on(self):
        import client_utils
        with self.assertRaises(NotImplementedError) as raised:
            client_utils.send_request(TLRPC.TL_error(), lambda *_: None)
        self.assertIn("TL_error", str(raised.exception))

    def test_an_answer_for_a_request_nobody_waits_for_is_ignored(self):
        requests.account_result(987654, None, {})


class Audio(unittest.TestCase):
    def setUp(self):
        fake.saved.update(messages=[], music=[], next_id=100, calls=[], errors={}, inbox=[])
        fake.settings.clear()
        self.cache = tempfile.mkdtemp(prefix="exteria-song-")
        self.path = os.path.join(self.cache, "song.mp3")
        with open(self.path, "wb") as handle:
            handle.write(b"x" * 321)
        path = os.path.join(PLUGINS, "tagger.plugin")
        with open(path, "w") as handle:
            handle.write(TAGGER % {"id": "tagger"})
        self.assertTrue(exteria_host.load(path, "tagger")["ok"])

    def tearDown(self):
        exteria_host.unload("tagger")
        shutil.rmtree(self.cache, ignore_errors=True)

    def wait_sent(self):
        start = time.time()
        while time.time() - start < 3.0:
            # send_audio hands the work to the ui thread of the app, which is a token this thread runs
            due, fake.timers[:] = list(fake.timers), []
            for token, _delay in due:
                exteria_host.run_token(token)
            fake.deliver()
            if fake.saved["messages"]:
                return fake.saved["messages"][-1]
            time.sleep(0.01)
        raise AssertionError("nothing was sent")

    def test_a_song_goes_to_saved_messages_with_what_the_send_hook_set(self):
        from client_utils import send_audio
        send_audio(fake.me, self.path, caption="Artist — Название")
        message = self.wait_sent()
        op, data = [c for c in fake.saved["calls"] if c[0] == "send_audio"][0]
        self.assertEqual((data["title"], data["performer"], data["duration_ms"], data["mime"], data["caption"]),
                         ("Название", "Artist", 215000, "audio/mpeg", "Artist — Название"))
        self.assertEqual(data["path"], self.path)
        self.assertEqual(message["doc"]["title"], "Название")
        import json
        self.assertEqual(json.loads(fake.settings[("tagger", "seen")]), ["song.mp3", "audio/mpeg", 321, fake.me])

    def test_a_hook_that_cancels_stops_the_file_before_the_app_hears_of_it(self):
        from client_utils import send_audio
        stopped = os.path.join(self.cache, "stop.mp3")
        shutil.copy(self.path, stopped)
        send_audio(fake.me, stopped, caption="x")
        due, fake.timers[:] = list(fake.timers), []
        for token, _delay in due:
            exteria_host.run_token(token)
        fake.deliver()
        self.assertEqual([c for c in fake.saved["calls"] if c[0] == "send_audio"], [])

    def test_only_audio_to_saved_messages_is_sent(self):
        from org.telegram.messenger import SendMessagesHelper
        with self.assertRaises(NotImplementedError):
            SendMessagesHelper.prepareSendingDocument(None, self.path, self.path, None, "", "audio/mpeg", fake.me + 1)
        with self.assertRaises(NotImplementedError):
            SendMessagesHelper.prepareSendingDocument(None, self.path, self.path, None, "", "application/zip", fake.me)
        with self.assertRaises(FileNotFoundError):
            SendMessagesHelper.prepareSendingDocument(None, self.path + ".gone", self.path, None, "", "audio/mpeg", fake.me)
        self.assertEqual(fake.saved["calls"], [])

    def test_a_failed_send_is_logged_and_not_raised(self):
        from org.telegram.messenger.documents import send_audio
        fake.saved["errors"]["send_audio"] = "FILE_INVALID"
        send_audio(self.path, "c", "audio/mpeg", fake.me)
        fake.deliver()
        lines = [d["message"] for c, d in list(fake.calls) if c == "log" and "could not send" in d.get("message", "")]
        self.assertTrue(lines and "FILE_INVALID" in lines[0])


def worked(function):
    """what a plugin does on its own thread, while this thread answers for the app"""
    box = {}

    def run():
        try:
            box["value"] = function()
        except BaseException as error:
            box["error"] = error

    thread = threading.Thread(target=run)
    thread.start()
    end = time.time() + 20
    while thread.is_alive() and time.time() < end:
        due, fake.timers[:] = list(fake.timers), []
        for token, _delay in due:
            exteria_host.run_token(token)
        if not fake.deliver():
            time.sleep(0.005)
    thread.join(1)
    if "error" in box:
        raise box["error"]
    return box["value"]


@unittest.skipUnless(os.environ.get("EXTERIA_PLAYLIST_PLUGIN"), "set EXTERIA_PLAYLIST_PLUGIN to the file of the plugin")
class RealPlugin(unittest.TestCase):
    """the helpers of playlist_to_profile over the stand-in app: find a message it sent, save and clear songs, delete a message"""

    def setUp(self):
        fake.saved.update(messages=[], music=[], next_id=100, calls=[], errors={}, inbox=[])
        self.path = os.path.join(PLUGINS, "playlist_to_profile.plugin")
        shutil.copy(os.environ["EXTERIA_PLAYLIST_PLUGIN"], self.path)
        lib = os.environ.get("EXTERIA_PYTHON_LIB")
        if lib:
            sys.path.insert(0, lib)
        self.assertTrue(exteria_host.load(self.path, "playlist_to_profile")["ok"])
        import gc
        self.plugin = next(o for o in gc.get_objects() if not isinstance(o, type) and hasattr(type(o), "_find_new_audio") and hasattr(type(o), "_save_music"))

    def tearDown(self):
        exteria_host.unload("playlist_to_profile")

    def test_it_finds_the_message_it_sent_and_puts_the_song_on_the_profile(self):
        fake.saved["messages"] = [{"id": 90, "text": "old", "date": 1}]
        self.assertEqual(worked(self.plugin._max_msg_id), 90)
        fake.saved["messages"].append({"id": 91, "text": "A — T", "date": 2, "doc": song(7, name="s.mp3", size=777)})
        document, mid = worked(lambda: self.plugin._find_new_audio(after_id=90, caption="A — T", size=777, name="s.mp3", timeout=5))
        self.assertEqual(mid, 91)
        self.assertEqual(document.id, 1007)
        ok, error = worked(lambda: self.plugin._save_music(document))
        self.assertEqual((ok, error), (True, None))
        self.assertEqual([d["id"] for d in fake.saved["music"]], [1007])
        self.assertEqual(len(worked(self.plugin._get_profile_music_documents)), 1)
        worked(lambda: self.plugin._delete_message(91))
        self.assertEqual([m["id"] for m in fake.saved["messages"]], [90])

    def test_it_clears_the_whole_profile_music_over_several_pages(self):
        # the plugin waits 0.35 s between two removals, so a few more than one page of 30 is as long as this test can be
        fake.saved["music"] = [song(n) for n in range(34)]
        self.assertEqual(len(worked(self.plugin._get_profile_music_documents)), 34)
        self.assertEqual(worked(self.plugin._clear_profile_music), 34)
        self.assertEqual(fake.saved["music"], [])


if __name__ == "__main__":
    unittest.main()
