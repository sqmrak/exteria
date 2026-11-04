import json
import os
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLUGINS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "plugins")

import fakeapp  # noqa: E402

fake = fakeapp.fake
fake.plugins_dir = PLUGINS
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
import java  # noqa: E402


class PluginHost(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        fake.menu.clear()
        self.path = os.path.join(PLUGINS, "upper.plugin")

    def tearDown(self):
        exteria_host.unload("upper")

    def test_reads_metadata(self):
        meta = exteria_host.metadata(self.path)
        self.assertTrue(meta["ok"])
        self.assertEqual(meta["meta"]["id"], "upper")
        self.assertEqual(meta["meta"]["name"], "Upper")

    def test_scans_the_permissions_a_plugin_needs(self):
        self.assertEqual(exteria_host.capabilities(self.path), {"messages.send": ["on_send_message"]})

    def test_loads_and_runs_hooks(self):
        result = exteria_host.load(self.path, "upper")
        self.assertTrue(result["ok"], result)
        self.assertIn(("hook.send.add", {"plugin": "upper", "priority": 0}), fake.calls)
        self.assertEqual(fake.settings[("upper", "loaded")], "true")
        self.assertEqual(fake.menu[0]["text"], "Upper")
        out = exteria_host.send_message_hook("upper", 0, {"message": "hello", "peer": 5})
        self.assertEqual(out, {"strategy": "MODIFY", "params": {"message": "HELLO", "peer": 5}})
        self.assertEqual(exteria_host.send_message_hook("upper", 0, {"message": "stop"})["strategy"], "CANCEL")

    def test_menu_click_reaches_the_callback(self):
        exteria_host.load(self.path, "upper")
        exteria_host.menu_click("upper", "item1", {"n": 7})
        self.assertEqual(fake.settings[("upper", "clicked")], "7")
        with self.assertRaises(LookupError):
            exteria_host.menu_click("upper", "nope", {})

    def test_app_events_are_logged(self):
        exteria_host.load(self.path, "upper")
        exteria_host.app_event("upper", "app_pause")
        logs = [d["message"] for n, d in fake.calls if n == "log"]
        self.assertIn("event PAUSE", logs)

    def test_unknown_plugin_passes(self):
        self.assertEqual(exteria_host.send_message_hook("ghost", 0, {"message": "x"}), {"strategy": "DEFAULT"})

    def test_runtime_directories_are_known_before_any_plugin_runs(self):
        from extera_utils import audit_gate
        self.assertIsNotNone(audit_gate._runtime_prefixes)
        stdlib = os.path.realpath(os.path.dirname(os.__file__))
        self.assertTrue(audit_gate._is_runtime_file(os.path.join(stdlib, "random.py")))
        self.assertFalse(audit_gate._is_runtime_file("/etc/hosts"))

    def test_runtime_directories_survive_a_path_the_sandbox_will_not_resolve(self):
        from unittest import mock
        from extera_utils import audit_gate
        stdlib = os.path.dirname(os.__file__)
        saved = audit_gate._runtime_prefixes
        audit_gate._runtime_prefixes = None
        try:
            with mock.patch.object(os.path, "realpath", side_effect=OSError("denied")):
                self.assertTrue(audit_gate._is_runtime_file(os.path.join(stdlib, "random.pyc")))
                self.assertFalse(audit_gate._is_runtime_file(os.path.join(stdlib, *([".."] * 20), "etc", "hosts")))
        finally:
            audit_gate._runtime_prefixes = saved

    def test_runtime_directories_accept_frozen_os_without_a_file(self):
        from unittest import mock
        from extera_utils import audit_gate
        saved = audit_gate._runtime_prefixes
        audit_gate._runtime_prefixes = None
        try:
            with mock.patch.dict(os.__dict__):
                del os.__file__
                self.assertIn(sys.prefix.rstrip(os.sep) or os.sep, audit_gate._runtime_paths())
                self.assertTrue(audit_gate._is_runtime_file(os.path.join(sys.prefix, "random.pyc")))
                self.assertFalse(audit_gate._is_runtime_file("/etc/hosts"))
        finally:
            audit_gate._runtime_prefixes = saved

    def test_bad_plugin_is_refused(self):
        with tempfile.NamedTemporaryFile("w", suffix=".plugin", delete=False) as f:
            f.write("def broken(:\n")
        try:
            refused = exteria_host.metadata(f.name)
            self.assertFalse(refused["ok"])
            self.assertIn("syntax error", refused["error"])
        finally:
            os.unlink(f.name)

    def test_unknown_java_class_is_an_error_a_plugin_can_catch(self):
        with self.assertRaises(java.ClassNotFoundException):
            java.jclass("org.telegram.messenger.NoSuchThing")
        self.assertIsNotNone(java.jclass("app.exteraless.plugins.PythonBridge"))


if __name__ == "__main__":
    unittest.main()
