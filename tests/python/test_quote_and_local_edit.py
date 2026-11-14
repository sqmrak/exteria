"""the host side of a reply with a quote, of the words a plugin shows for a message, of the dialog with a field, and of the reason a plugin
did not load. the plugins here are small ones that do what quoteReply and LocalEdictor do; the real two run when the folder of
EXTERIA_ZWYLIB holds them"""

import json
import os
import shutil
import sys
import tempfile
import time
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402

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

QUOTE = HEADER + '''
from base_plugin import BasePlugin, HookResult, HookStrategy
from org.telegram.ui import ChatActivity


class Quote(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook()

    def on_send_message_hook(self, account, params):
        self.set_setting("seen_reply", None if params.replyToMsg is None else params.replyToMsg.getId())
        self.set_setting("seen_quote", None if params.replyQuote is None else params.replyQuote.text)
        if params.replyToMsg is None or params.replyQuote is not None:
            return HookResult()
        params.replyQuote = getattr(ChatActivity.ReplyQuote, "from")(params.replyToMsg)
        return HookResult(strategy=HookStrategy.MODIFY, params=params)
'''

CLEAR = HEADER + '''
from base_plugin import BasePlugin, HookResult, HookStrategy


class Clear(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook()

    def on_send_message_hook(self, account, params):
        params.replyQuote = None
        return HookResult(strategy=HookStrategy.MODIFY, params=params)
'''

EDIT = HEADER + '''
from base_plugin import BasePlugin, MenuItemData, MenuItemType, MethodHook
from android_utils import run_on_ui_thread
from hook_utils import find_class
from android.widget import EditText, LinearLayout
from ui.alert import AlertDialogBuilder
from client_utils import get_last_fragment

edits = {}


class Shown(MethodHook):
    def before_hooked_method(self, param):
        message = param.args[0]
        new = edits.get(message.getId())
        if new:
            message.applyNewText(new)


class Edit(BasePlugin):
    def on_plugin_load(self):
        cell = find_class("org.telegram.ui.Cells.ChatMessageCell")
        for method in cell.getClass().getDeclaredMethods():
            if method.getName() == "setMessageContent":
                self.hook_method(method, Shown(), priority=30)
        self.add_menu_item(MenuItemData(menu_type=MenuItemType.MESSAGE_CONTEXT_MENU, text="Edit", on_click=self.ask))
        self.add_menu_item(MenuItemData(menu_type=MenuItemType.CHAT_ACTION_MENU, text="Reset", on_click=lambda ctx: edits.clear()))

    def ask(self, context):
        message = context["message"]
        activity = get_last_fragment().getParentActivity()
        layout = LinearLayout(activity)
        field = EditText(activity)
        field.setText(message.messageText)
        field.setHint("New text")
        layout.addView(field)
        builder = AlertDialogBuilder(activity)
        builder.set_title("Edit")
        builder.set_view(layout)
        builder.set_positive_button("Save", lambda d, w: edits.__setitem__(message.getId(), field.getText().toString()))
        builder.set_negative_button("Cancel", lambda d, w: None)
        run_on_ui_thread(builder.show)
'''

LABELLED = HEADER + '''
from base_plugin import BasePlugin
from android.widget import EditText, LinearLayout, TextView
from ui.alert import AlertDialogBuilder
from client_utils import get_last_fragment


class Labelled(BasePlugin):
    def on_plugin_load(self):
        activity = get_last_fragment().getParentActivity()
        layout = LinearLayout(activity)
        layout.addView(TextView(activity))
        layout.addView(EditText(activity))
        try:
            AlertDialogBuilder(activity).set_view(layout)
        except NotImplementedError as error:
            self.set_setting("refused", str(error))
'''


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-quote-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def write(plugin_id, source):
    path = os.path.join(PLUGINS, plugin_id + ".plugin")
    with open(path, "w") as handle:
        handle.write(source % {"id": plugin_id} if "%(id)s" in source else source)
    return path


def pump(until, seconds=3):
    end = time.time() + seconds
    while time.time() < end:
        while fake.timers:
            token, _delay = fake.timers.pop(0)
            exteria_host.run_token(token)
        if until():
            return True
        time.sleep(0.01)
    return False


def asked(name):
    return [data for call, data in fake.calls if call == name]


class Quote(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        self.path = write("quoter", QUOTE)
        self.assertTrue(exteria_host.load(self.path, "quoter")["ok"])

    def tearDown(self):
        exteria_host.unload("quoter")
        exteria_host.unload("clearer")

    def send(self, **params):
        return exteria_host.send_message_hook("quoter", 0, dict({"message": "hi", "peer": 5, "replyToMsg": 0}, **params))

    def test_a_message_without_a_reply_has_no_reply_object(self):
        self.assertEqual(self.send(), {"strategy": "DEFAULT"})
        self.assertEqual(json.loads(fake.settings[("quoter", "seen_reply")]), None)

    def test_a_reply_carries_the_words_of_the_answered_message_as_a_quote(self):
        out = self.send(replyToMsg=7, replyText="the full text")
        self.assertEqual(out, {"strategy": "MODIFY", "params": {"message": "hi", "peer": 5, "replyToMsg": 7,
                                                                  "replyQuote": {"text": "the full text", "offset": 0}}})
        self.assertEqual(json.loads(fake.settings[("quoter", "seen_reply")]), 7)

    def test_a_quote_the_person_chose_is_seen_and_kept(self):
        out = self.send(replyToMsg=7, replyText="the full text", quote="full", quoteOffset=4)
        self.assertEqual(out, {"strategy": "DEFAULT"})
        self.assertEqual(json.loads(fake.settings[("quoter", "seen_quote")]), "full")

    def test_a_long_text_is_cut_at_the_limit_of_telegram_and_not_inside_a_pair(self):
        out = self.send(replyToMsg=7, replyText="a" * 2000)
        self.assertEqual(len(out["params"]["replyQuote"]["text"]), 1024)
        # an emoji is two utf-16 units: the 1024th unit would be its first half
        out = self.send(replyToMsg=7, replyText="a" * 1023 + "\U0001F600")
        self.assertEqual(out["params"]["replyQuote"]["text"], "a" * 1023)

    def test_a_plugin_may_clear_the_quote(self):
        clear = write("clearer", CLEAR)
        self.assertTrue(exteria_host.load(clear, "clearer")["ok"])
        out = exteria_host.send_message_hook("clearer", 0, {"message": "hi", "peer": 5, "replyToMsg": 7, "replyText": "x", "quote": "x", "quoteOffset": 0})
        self.assertEqual(out["params"]["replyQuote"], None)

    def test_the_comments_of_a_post_are_known_for_the_open_chat_only(self):
        from org.telegram.messenger import ChatObject
        fake.current = {"kind": "chat", "dialog": -100, "discussion": True}
        try:
            self.assertTrue(ChatObject.isDiscussionGroup(0, 100))
            self.assertFalse(ChatObject.isDiscussionGroup(0, 101))
            fake.current = {"kind": "chat", "dialog": -100, "discussion": False}
            self.assertFalse(ChatObject.isDiscussionGroup(0, 100))
        finally:
            fake.current = {"kind": "chat", "dialog": 777, "user": {"id": 777, "first_name": "Ann"}}


class LocalEdit(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        fake.menu.clear()
        self.path = write("editor", EDIT)
        self.assertTrue(exteria_host.load(self.path, "editor")["ok"])

    def tearDown(self):
        exteria_host.unload("editor")
        exteria_host.unload("labelled")

    def shown(self, *messages):
        return exteria_host.display_messages(5, [{"id": i, "text": text, "out": False} for i, text in messages])

    def edit(self, message_id, text):
        calls = len(fake.calls)
        exteria_host.menu_click("editor", "item1", {"message": {"id": message_id, "text": "original", "out": True, "dialog": 5}})
        self.assertTrue(pump(lambda: any(name == "ui.alert" for name, _ in fake.calls[calls:])))
        alert = [data for name, data in fake.calls[calls:] if name == "ui.alert"][0]
        exteria_host.alert_result(alert["token"], alert["buttons"].index("Save"), text)
        return alert

    def test_the_app_is_told_when_a_plugin_hooks_the_display_of_messages(self):
        self.assertEqual(asked("hook.display.add"), [{"plugin": "editor"}])
        exteria_host.unload("editor")
        self.assertEqual(asked("hook.display.remove"), [{"plugin": "editor"}])
        self.assertEqual(self.shown((1, "a")), {})

    def test_the_dialog_holds_the_text_of_the_message_in_a_field(self):
        alert = self.edit(2, "changed")
        self.assertEqual(alert["field"], {"initial": "original", "placeholder": "New text"})
        self.assertEqual(alert["buttons"], ["Cancel", "Save"])

    def test_what_the_person_typed_is_what_the_hook_shows(self):
        self.edit(2, "changed")
        self.assertEqual(self.shown((1, "a"), (2, "original")), {"2": "changed"})

    def test_the_chat_is_laid_out_again_after_the_answer_and_after_a_menu_item(self):
        calls = len(fake.calls)
        self.edit(2, "changed")
        self.assertIn("chat.rebuild", [name for name, _ in fake.calls[calls:]])
        calls = len(fake.calls)
        exteria_host.menu_click("editor", "item2", {})
        self.assertIn("chat.rebuild", [name for name, _ in fake.calls[calls:]])
        self.assertEqual(self.shown((2, "original")), {})

    def test_cancel_changes_nothing(self):
        calls = len(fake.calls)
        exteria_host.menu_click("editor", "item1", {"message": {"id": 2, "text": "original", "out": True, "dialog": 5}})
        pump(lambda: any(name == "ui.alert" for name, _ in fake.calls[calls:]))
        alert = [data for name, data in fake.calls[calls:] if name == "ui.alert"][0]
        exteria_host.alert_result(alert["token"], alert["buttons"].index("Cancel"), "ignored")
        self.assertEqual(self.shown((2, "original")), {})

    def test_the_actions_of_the_chat_menu_are_listed_with_the_others(self):
        self.assertEqual([item["type"] if "type" in item else item.get("menu_type") for item in fake.menu], ["MESSAGE_CONTEXT_MENU", "CHAT_ACTION_MENU"])

    def test_a_dialog_with_more_than_one_field_is_refused_in_words(self):
        write("labelled", LABELLED)
        self.assertTrue(exteria_host.load(os.path.join(PLUGINS, "labelled.plugin"), "labelled")["ok"])
        self.assertIn("one text field", json.loads(fake.settings[("labelled", "refused")]))


def build_archive(path, files):
    with zipfile.ZipFile(path, "w") as archive:
        for name, text in files.items():
            archive.writestr(name, text)


class WhyNotLoaded(unittest.TestCase):
    def explain(self, source, error=""):
        import exteria_diagnose
        path = os.path.join(PLUGINS, "diagnosed.plugin")
        with open(path, "w") as handle:
            handle.write(source)
        return exteria_diagnose.explain(path, error)

    def test_a_loader_in_the_source_is_not_a_reason(self):
        why = self.explain("from dalvik.system import InMemoryDexClassLoader\nloader = InMemoryDexClassLoader\n", "ValueError: broken")
        self.assertEqual(why, {"kind": "other", "detail": "ValueError: broken"})

    def test_a_dex_in_an_archive_is_not_a_reason(self):
        import exteria_diagnose
        path = os.path.join(PLUGINS, "withdex.elyx")
        build_archive(path, {"main.py": "x = 1\n", "classes.dex": "dex\n035"})
        self.assertEqual(exteria_diagnose.explain(path, "ValueError: broken"), {"kind": "other", "detail": "ValueError: broken"})

    def test_a_class_the_dex_program_lacks_is_named(self):
        why = self.explain("x = 1\n", "java.lang.NoClassDefFoundError: org/telegram/ui/Components/Paint")
        self.assertEqual((why["kind"], why["classes"]), ("android", ["org.telegram.ui.Components.Paint"]))

    def test_android_classes_the_app_lacks_are_counted(self):
        why = self.explain("from android.widget import LinearLayout\nfrom android.graphics import RenderEffect, RuntimeShader\n"
                           "from org.telegram.ui.Components import ChatActivityEnterView\n")
        self.assertEqual(why["kind"], "android")
        self.assertEqual((why["missing"], why["total"]), (2, 4))
        self.assertEqual(why["classes"], ["android.graphics.RuntimeShader", "org.telegram.ui.Components.ChatActivityEnterView"])

    def test_a_missing_library_is_a_library_and_not_android(self):
        why = self.explain("import somelib\n", "ModuleNotFoundError: No module named 'somelib'")
        self.assertEqual((why["kind"], why["classes"]), ("library", ["somelib"]))

    def test_a_feature_without_an_equivalent_is_named(self):
        why = self.explain("x = 1\n", "NotImplementedError: org.telegram.ui.GroupCreateActivity is not available on ios")
        self.assertEqual((why["kind"], why["classes"]), ("feature", ["org.telegram.ui.GroupCreateActivity"]))

    def test_anything_else_keeps_the_first_line_of_the_error(self):
        why = self.explain("x = 1\n", "\nValueError: broken\nmore")
        self.assertEqual(why, {"kind": "other", "detail": "ValueError: broken"})

    def test_traceback_shows_the_exception_instead_of_the_header(self):
        error = 'Traceback (most recent call last):\n  File "/private/var/Exteria.app/python/shim/exteria_host.py", line 25\nValueError: broken\n'
        self.assertEqual(self.explain("x = 1\n", error), {"kind": "other", "detail": "ValueError: broken"})

    def test_a_class_held_in_a_variable_is_named(self):
        import exteria_diagnose
        path = os.path.join(PLUGINS, "held.plugin")
        with open(path, "w") as handle:
            handle.write('layout = "org.telegram.ui.Components.ChatActivityEnterView"\ninner = "org.telegram.ui.Components.ChatActivityEnterView$Holder"\n'
                         'permission = "android.permission.CAMERA"\naction = "android.intent.action.VIEW"\nword = "org.telegram"\n')
        notice = exteria_diagnose.unavailable(path)
        self.assertEqual(notice["kind"], "android")
        self.assertEqual(notice["classes"], ["org.telegram.ui.Components.ChatActivityEnterView", "org.telegram.ui.Components.ChatActivityEnterView$Holder"])
        self.assertEqual((notice["missing"], notice["total"]), (2, 2))

    def test_a_plugin_that_names_only_what_the_app_has_gets_no_notice(self):
        import exteria_diagnose
        path = os.path.join(PLUGINS, "complete.plugin")
        with open(path, "w") as handle:
            handle.write("from android.widget import LinearLayout\nx = 1\n")
        self.assertIsNone(exteria_diagnose.unavailable(path))

    def test_the_host_adds_a_notice_to_a_load_that_worked(self):
        path = write("hollow", HEADER + 'from base_plugin import BasePlugin\nclass H(BasePlugin):\n    target = "org.telegram.ui.Components.SharedMediaLayout"\n')
        result = exteria_host.load(path, "hollow")
        self.assertTrue(result["ok"])
        self.assertEqual(result["notice"]["classes"], ["org.telegram.ui.Components.SharedMediaLayout"])

    def test_the_host_adds_the_reason_to_a_refused_load(self):
        path = write("lacking", HEADER + "from android.graphics import RuntimeShader\n")
        result = exteria_host.load(path, "lacking")
        self.assertFalse(result["ok"])
        self.assertEqual(result["why"]["kind"], "android")
        self.assertEqual(result["why"]["classes"], ["android.graphics.RuntimeShader"])
        self.assertIn("ok", exteria_host.load(write("fine", HEADER + "from base_plugin import BasePlugin\nclass F(BasePlugin):\n    pass\n"), "fine"))
        exteria_host.unload("fine")


REAL = os.path.join(os.path.dirname(os.environ.get("EXTERIA_ZWYLIB", "")), "quoteReply.plugin")


@unittest.skipUnless(os.environ.get("EXTERIA_ZWYLIB") and os.path.isfile(REAL) and os.path.isfile(os.path.join(os.path.dirname(REAL), "LocalEdictor.plugin")),
                     "set EXTERIA_ZWYLIB to the zwylib .elyx beside quoteReply.plugin and LocalEdictor.plugin")
class RealPlugins(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fake.calls.clear()
        fake.settings.clear()
        fake.menu.clear()
        folder = os.path.dirname(REAL)
        for name in ("quoteReply.plugin", "LocalEdictor.plugin"):
            shutil.copy(os.path.join(folder, name), PLUGINS)
        assert exteria_host.load(os.environ["EXTERIA_ZWYLIB"], "zwylib")["ok"]
        assert exteria_host.load(os.path.join(PLUGINS, "quoteReply.plugin"), "quoteReply")["ok"]
        assert exteria_host.load(os.path.join(PLUGINS, "LocalEdictor.plugin"), "LocalEdictor")["ok"]

    @classmethod
    def tearDownClass(cls):
        for plugin_id in ("LocalEdictor", "quoteReply", "zwylib"):
            exteria_host.unload(plugin_id)

    def test_quote_reply_quotes_a_reply_and_leaves_a_plain_message(self):
        out = exteria_host.send_message_hook("quoteReply", 0, {"message": "hi", "peer": 5, "replyToMsg": 9, "replyText": "words"})
        self.assertEqual(out["params"]["replyQuote"], {"text": "words", "offset": 0})
        self.assertEqual(exteria_host.send_message_hook("quoteReply", 0, {"message": "hi", "peer": 5, "replyToMsg": 0}), {"strategy": "DEFAULT"})
        self.assertFalse([line for line in [d["message"] for n, d in fake.calls if n == "log"] if "AttributeError" in line])

    def test_local_edictor_edits_a_message_on_the_phone(self):
        calls = len(fake.calls)
        item = [i for i, m in enumerate(fake.menu, 1) if m.get("menu_type") == "MESSAGE_CONTEXT_MENU"][0]
        exteria_host.menu_click("LocalEdictor", "item%d" % item, {"message": {"id": 4, "text": "before", "out": False, "dialog": 5}})
        self.assertTrue(pump(lambda: any(n == "ui.alert" for n, _ in fake.calls[calls:])))
        alert = [d for n, d in fake.calls[calls:] if n == "ui.alert"][0]
        self.assertEqual(alert["field"]["initial"], "before")
        exteria_host.alert_result(alert["token"], len(alert["buttons"]) - 1, "after")
        self.assertEqual(exteria_host.display_messages(5, [{"id": 4, "text": "before", "out": False}]), {"4": "after"})
        reset = [i for i, m in enumerate(fake.menu, 1) if m.get("menu_type") == "CHAT_ACTION_MENU"][0]
        exteria_host.menu_click("LocalEdictor", "item%d" % reset, {})
        self.assertEqual(exteria_host.display_messages(5, [{"id": 4, "text": "before", "out": False}]), {})


if __name__ == "__main__":
    unittest.main()
