"""the message_cleaner plugin over the stand-in app: the menu of a chat, its list of the messages of the open chat, the deletes and the progress panel.
EXTERIA_MESSAGE_CLEANER names the file of the real plugin"""

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


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-cleaner-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def pump(until, timeout=15):
    """the main thread of the app: queued calls, the answers of the account"""
    end = time.time() + timeout
    while time.time() < end:
        while fake.timers:
            exteria_host.run_token(fake.timers.pop(0)[0])
        fake.deliver()
        if until():
            return True
        time.sleep(0.01)
    return False


def message(number, out):
    return {"id": number, "date": number, "out": out, "post": False, "service": False}


@unittest.skipUnless(os.environ.get("EXTERIA_MESSAGE_CLEANER"), "set EXTERIA_MESSAGE_CLEANER to the file of the plugin")
class RealPlugin(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.menu.clear()
        fake.progress.clear()
        fake.progress_log.clear()
        fake.chat.update(messages=[message(n, n % 2 == 1) for n in range(1, 251)], log=[], errors={})
        fake.saved.update(messages=[], calls=[], errors={}, inbox=[])
        fake.current = {"kind": "chat", "dialog": 600, "signed": 600, "peer_kind": 1, "topic": 0, "chat": {"id": 600, "title": "Ann"}, "user": {"id": 600}}
        path = os.path.join(PLUGINS, "message_cleaner.plugin")
        shutil.copy(os.environ["EXTERIA_MESSAGE_CLEANER"], path)
        result = exteria_host.load(path, "message_cleaner")
        self.assertTrue(result["ok"], result)

    def tearDown(self):
        exteria_host.unload("message_cleaner")

    def asked(self, name):
        return [data for call, data in fake.calls if call == name]

    def click_menu(self):
        self.assertEqual([item["menu_type"] for item in fake.menu], ["CHAT_ACTION_MENU"])
        exteria_host.menu_click("message_cleaner", "item1", {})

    def answer(self, name, index, count=1):
        self.assertTrue(pump(lambda: len(self.asked(name)) >= count))
        exteria_host.alert_result(self.asked(name)[count - 1]["token"], index)

    def logs(self):
        """what the plugin wrote to its log, for the failure message of a test"""
        return "\n".join(str(data.get("message")) for name, data in fake.calls if name == "log" and "MessageCleaner" in str(data.get("message")))

    def finished(self):
        return len(self.asked("ui.alert")) >= 2

    def test_the_menu_item_of_a_chat_is_added(self):
        self.assertEqual((fake.menu[0]["text"], fake.menu[0]["menu_type"]), ("Clean messages", "CHAT_ACTION_MENU"))

    def test_my_messages_in_a_private_chat_are_deleted_and_the_others_stay(self):
        self.click_menu()
        self.answer("ui.choose", 0)
        # the confirmation of a private chat: cancel, only for me, for both
        self.answer("ui.alert", 2)
        self.assertTrue(pump(self.finished), fake.chat["log"][-3:])
        remaining = [m["id"] for m in fake.chat["messages"]]
        self.assertEqual(remaining, [n for n in range(1, 251) if n % 2 == 0])
        deletes = [data for kind, data in fake.chat["log"] if kind == "delete"]
        self.assertTrue(deletes and all(len(d["ids"]) <= 100 and d["revoke"] for d in deletes))
        pages = [data for kind, data in fake.chat["log"] if kind == "page"]
        self.assertTrue(all(p["mode"] == "mine" and p["dialog"] == 600 and p["limit"] == 100 for p in pages))
        self.assertIn("Deleted 125", self.asked("ui.alert")[1]["message"])
        self.assertEqual(fake.progress, {}, "the panel was left on the screen")

    def test_only_for_me_does_not_revoke(self):
        fake.chat["messages"] = [message(n, True) for n in range(1, 6)]
        self.click_menu()
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 1)
        self.assertTrue(pump(self.finished), self.logs())
        self.assertEqual(fake.chat["messages"], [], self.logs())
        self.assertTrue(all(not d["revoke"] for kind, d in fake.chat["log"] if kind == "delete"))

    def test_the_progress_panel_has_a_title_a_bar_and_the_buttons_of_the_plugin(self):
        self.click_menu()
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 2)
        self.assertTrue(pump(lambda: any(name == "progress.show" for name, _ in fake.progress_log)))
        shown = next(data for name, data in fake.progress_log if name == "progress.show")
        self.assertTrue(shown["title"].startswith("Cleaning: Ann"), shown)
        self.assertEqual(shown["buttons"], ["Stop", "Hide"])
        self.assertTrue(pump(self.finished), self.logs())
        self.assertTrue(any(name == "progress.update" for name, _ in fake.progress_log))

    def test_stop_ends_the_job_with_what_was_done(self):
        self.click_menu()
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 2)
        self.assertTrue(pump(lambda: fake.progress))
        token = next(iter(fake.progress))
        exteria_host.alert_result(token, 0)
        self.assertTrue(pump(self.finished), self.logs())
        self.assertIn("stopped", self.asked("ui.alert")[1]["message"].lower())

    def test_a_server_error_stops_the_job_with_its_reason(self):
        fake.chat["errors"]["delete"] = "CHAT_ADMIN_REQUIRED"
        self.click_menu()
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 2)
        self.assertTrue(pump(self.finished), self.logs())
        self.assertIn("No admin right", self.asked("ui.alert")[1]["message"])

    def test_a_chat_without_my_messages_says_so(self):
        fake.chat["messages"] = [message(n, False) for n in range(1, 4)]
        self.click_menu()
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 2)
        self.assertTrue(pump(self.finished), self.logs())
        self.assertIn("no messages here", self.asked("ui.alert")[1]["message"].lower())

    def test_all_the_messages_of_a_topic_are_listed_through_replies(self):
        fake.current = {"kind": "chat", "dialog": 700, "signed": -700, "peer_kind": 3, "topic": 12, "chat": {"id": 700, "title": "Forum"}, "admin": True}
        fake.chat["messages"] = [message(n, n % 2 == 1) for n in range(13, 20)]
        self.click_menu()
        self.assertTrue(pump(lambda: self.asked("ui.choose")))
        items = self.asked("ui.choose")[0]["items"]
        self.assertEqual(items[0], "Only my messages")
        self.assertEqual(len(items), 1, "no right to delete everything is known in a supergroup")
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 1)
        self.assertTrue(pump(self.finished), self.logs())
        pages = [data for kind, data in fake.chat["log"] if kind == "page"]
        self.assertTrue(all(p["topic"] == 12 and p["dialog"] == -700 for p in pages), pages)

    def test_an_administrator_deletes_every_post_of_a_channel_by_the_channel(self):
        fake.current = {"kind": "chat", "dialog": 800, "signed": -800, "peer_kind": 3, "topic": 0, "broadcast": True, "admin": True, "chat": {"id": 800, "title": "News"}}
        fake.chat["messages"] = [dict(message(n, False), post=True) for n in range(1, 8)]
        self.click_menu()
        self.assertTrue(pump(lambda: self.asked("ui.choose")))
        self.assertEqual(self.asked("ui.choose")[0]["items"], ["All posts in the channel"])
        self.answer("ui.choose", 0)
        self.answer("ui.alert", 1)
        self.assertTrue(pump(self.finished), self.logs())
        self.assertEqual(fake.chat["messages"], [], self.logs())
        deletes = [data for kind, data in fake.chat["log"] if kind == "delete"]
        self.assertTrue(deletes and all(d.get("channel") == -800 for d in deletes))
        pages = [data for kind, data in fake.chat["log"] if kind == "page"]
        self.assertTrue(all(p["mode"] == "all" for p in pages))

    def test_a_member_of_a_channel_is_told_only_admins_can(self):
        fake.current = {"kind": "chat", "dialog": 800, "signed": -800, "peer_kind": 3, "topic": 0, "broadcast": True, "admin": False, "chat": {"id": 800, "title": "News"}}
        self.click_menu()
        self.assertTrue(pump(lambda: any(call == "app.notice" or call.startswith("ui.") for call, _ in fake.calls[-3:])))
        self.assertEqual(self.asked("ui.choose"), [])
        self.assertEqual(fake.chat["log"], [])


if __name__ == "__main__":
    unittest.main()
