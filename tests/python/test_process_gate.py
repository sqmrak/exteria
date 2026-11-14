"""the audit gate of the sdk with the local change that lets a plugin start a program with the native permission (third_party/exteraless/PATCHES): the
events of a started process are decided by that permission, and os.exec, which would replace the app, stays refused"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from extera_utils import audit_gate  # noqa: E402


class Loader:
    """what the gate asks of the plugin loader, with the permissions of the plugin set by the test"""
    PERM_NATIVE = "native"
    PERM_FILES = "files"
    PERM_NETWORK = "network"

    def __init__(self, granted):
        self.granted = set(granted)
        self.denied = []

    def plugin_frame_owner(self):
        return "probe"

    def unsafe_mode(self):
        return False

    def has_permission(self, permission, plugin_id=None):
        return permission in self.granted

    def require_permission(self, permission, what, detail=None, plugin_id=None):
        if permission not in self.granted:
            raise PermissionError("plugin %r is not allowed to %s: missing the %r permission" % (plugin_id, what, permission))

    def log_denial(self, plugin_id, event, what):
        self.denied.append(event)


EVENTS = [("os.system", ("true",)), ("os.posix_spawn", ("/bin/true", ["true"], {})), ("os.spawn", ("P_NOWAIT", "/bin/true", ["true"])),
          ("subprocess.Popen", ("/bin/true", ["true"], None, None))]


class ProcessGate(unittest.TestCase):
    def setUp(self):
        audit_gate.clear_plugin("probe")

    def test_a_plugin_with_the_native_permission_may_start_a_program(self):
        loader = Loader({"native"})
        for event, args in EVENTS:
            with self.subTest(event=event):
                audit_gate._check(event, args, loader)
        journal = audit_gate.get_journal("probe")
        self.assertEqual([entry["event"] for entry in journal], [event for event, _ in EVENTS])
        self.assertTrue(all(entry["allowed"] and entry["category"] == "process" for entry in journal))

    def test_a_plugin_without_it_is_refused_and_the_attempt_is_recorded(self):
        loader = Loader(set())
        for event, args in EVENTS:
            with self.subTest(event=event):
                with self.assertRaises(PermissionError):
                    audit_gate._check(event, args, loader)
        self.assertTrue(all(not entry["allowed"] for entry in audit_gate.get_journal("probe")))
        self.assertEqual(audit_gate.get_profile("probe")["process"], {"allowed": 0, "denied": len(EVENTS)})

    def test_the_detail_of_a_popen_without_an_executable_is_its_arguments(self):
        audit_gate._check("subprocess.Popen", (None, ["true", "-x"], None, None), Loader({"native"}))
        self.assertIn("true", audit_gate.get_journal("probe")[-1]["detail"])

    def test_replacing_the_process_stays_refused_even_with_the_permission(self):
        loader = Loader({"native", "files", "network"})
        with self.assertRaises(PermissionError):
            audit_gate._check("os.exec", ("/bin/true", ["true"]), loader)
        self.assertEqual(loader.denied, ["os.exec"])

    def test_the_process_events_are_watched(self):
        for event, _ in EVENTS:
            self.assertIn(event, audit_gate._WATCHED)


if __name__ == "__main__":
    unittest.main()
