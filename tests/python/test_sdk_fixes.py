"""the corrections that came out of the reverse report of 2.2.0: a failing callback keeps its own error, a plugin without settings has an empty page, a color
is cut to an int the way chaquopy does it, metadata of an archive is read and not run, and the paths an archive names stay inside it"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import java  # noqa: E402
from android_utils import _plugin_mark  # noqa: E402
from app.exteraless import plugins as bridge  # noqa: E402
from elyx_runtime.assets import Assets, AssetNotFoundException  # noqa: E402
from elyx_runtime.metadata import parse_mapping_file  # noqa: E402
import exteria_host  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402


class CallbackMark(unittest.TestCase):
    def test_the_error_of_the_callback_passes_through(self):
        with self.assertRaises(ValueError):
            with _plugin_mark(lambda: None):
                raise ValueError("the callback failed")

    def test_a_callback_that_works_runs_once(self):
        ran = []
        with _plugin_mark(lambda: None):
            ran.append(1)
        self.assertEqual(ran, [1])


class IntCoercion(unittest.TestCase):
    def test_truncate_keeps_the_low_bits_as_a_signed_value(self):
        self.assertEqual(java.jint(0xFFE53935, truncate=True), 0xFFE53935 - (1 << 32))
        self.assertEqual(java.jint(5, truncate=True), 5)
        self.assertEqual(java.jshort(0x8000, truncate=True), -0x8000)
        self.assertEqual(java.jbyte(200, truncate=True), -56)

    def test_without_truncate_the_value_is_unchanged(self):
        self.assertEqual(java.jint(0xFFE53935), 0xFFE53935)


class SettingsPage(unittest.TestCase):
    def test_a_plugin_without_settings_has_no_rows(self):
        saved = plugin_loader.get_settings_json
        plugin_loader.get_settings_json = lambda plugin_id: "null"
        try:
            self.assertEqual(exteria_host.settings("nothing"), [])
        finally:
            plugin_loader.get_settings_json = saved


class Bridge(unittest.TestCase):
    def test_a_switched_off_plugin_loses_its_menu_callbacks(self):
        bridge._menu_callbacks[("gone", "a")] = lambda context: None
        bridge._menu_callbacks[("kept", "a")] = lambda context: None
        bridge.forget_plugin("gone")
        self.assertNotIn(("gone", "a"), bridge._menu_callbacks)
        self.assertIn(("kept", "a"), bridge._menu_callbacks)
        bridge.forget_plugin("kept")

    def test_a_queued_function_that_fails_does_not_reach_the_app(self):
        def fail():
            raise RuntimeError("queued")
        token = 987654
        with bridge._token_lock:
            bridge._tokens[token] = fail
        bridge.run_token(token)
        self.assertNotIn(token, bridge._tokens)

    def test_file_handlers_say_that_they_are_not_available(self):
        with self.assertRaises(NotImplementedError):
            bridge.PluginServices.registerFileHandler("p", "txt", "[]", "[]", False)
        with self.assertRaises(NotImplementedError):
            bridge.PluginServices.unregisterFileHandler("p", "secret")

    def test_clearing_the_settings_removes_the_keys(self):
        from elyx_runtime.settings import SettingsController
        controller = SettingsController("clearing")
        controller.set_setting("one", 1)
        controller.set_setting("two", "x")
        self.assertIsNotNone(fake.settings.get(("clearing", "one")))
        controller.clear_settings()
        self.assertFalse([key for key in fake.settings if key[0] == "clearing"])


class ArchiveMetadata(unittest.TestCase):
    def test_a_python_metainfo_is_read_and_not_run(self):
        os.environ.pop("EXTERIA_METADATA_RAN", None)
        source = b"import os\nos.environ['EXTERIA_METADATA_RAN'] = '1'\nname = 'a'\nitems = [1, 2]\ncomputed = 1 + 2\n_hidden = 'x'\n"
        mapping = parse_mapping_file("metainfo.py", source)
        self.assertEqual(mapping, {"name": "a", "items": [1, 2]})
        self.assertNotIn("EXTERIA_METADATA_RAN", os.environ)

    def test_a_python_file_with_a_syntax_error_is_refused(self):
        from elyx_runtime.errors import MetainfoError
        with self.assertRaises(MetainfoError):
            parse_mapping_file("metainfo.py", b"name = (")


class ArchivePaths(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="exteria-assets-")
        os.makedirs(os.path.join(self.root, "assets"))
        with open(os.path.join(self.root, "secret.txt"), "w") as handle:
            handle.write("outside")
        with open(os.path.join(self.root, "assets", "inside.txt"), "w") as handle:
            handle.write("inside")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_a_name_with_dots_does_not_leave_the_folder(self):
        assets = Assets(os.path.join(self.root, "assets"))
        self.assertTrue(assets.get("inside.txt"))
        for name in ("../secret.txt", "./inside.txt", "a/../../secret.txt"):
            with self.assertRaises(AssetNotFoundException):
                assets.get(name)


if __name__ == "__main__":
    unittest.main()
