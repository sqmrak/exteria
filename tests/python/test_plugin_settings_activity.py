"""PluginSettingsActivity: the screen of a plugin's settings that plugins open with presentFragment"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402,F401
from java import jclass  # noqa: E402
from java.lang import IllegalArgumentException, IllegalStateException, NullPointerException  # noqa: E402
from org.telegram.ui import BaseFragment  # noqa: E402


class SettingsScreen(unittest.TestCase):
    def setUp(self):
        fake.settings_opened.clear()
        self.Screen = jclass("com.exteragram.messenger.plugins.ui.PluginSettingsActivity")

    def test_the_import_plugins_use_gives_the_class(self):
        from com.exteragram.messenger.plugins.ui import PluginSettingsActivity
        self.assertIs(PluginSettingsActivity, self.Screen)

    def test_presenting_it_opens_the_page_of_the_plugin(self):
        class Named:
            def getId(self):
                return "shown"

        self.assertTrue(BaseFragment().presentFragment(self.Screen(Named())))
        self.assertTrue(BaseFragment().presentFragment(self.Screen.of("shown")))
        self.assertEqual(fake.settings_opened, ["shown", "shown"])
        self.assertEqual(self.Screen.of("shown").getPluginId(), "shown")

    def test_a_plugin_the_app_does_not_know_is_an_illegal_state(self):
        with self.assertRaises(IllegalStateException):
            BaseFragment().presentFragment(self.Screen.of("gone"))
        self.assertEqual(fake.settings_opened, [])

    def test_a_missing_or_wrong_plugin_is_refused_at_once(self):
        with self.assertRaises(NullPointerException):
            self.Screen(None)
        for bad in ("", 5, object()):
            with self.assertRaises(IllegalArgumentException):
                self.Screen(bad)


if __name__ == "__main__":
    unittest.main()
