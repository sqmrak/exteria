"""zwylib reads <plugins>/<id>.py for every plugin, while the app keeps a plugin as <id>.plugin: the open of the sandbox gives the second for the first"""

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

from extera_utils import plugin_loader  # noqa: E402


class OpenAlias(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="exteria-alias-")
        self.saved = (fake.plugins_dir, plugin_loader._plugins_dir_cached)
        fake.plugins_dir = self.dir
        plugin_loader._plugins_dir_cached = None
        with open(os.path.join(self.dir, "doom.plugin"), "w") as handle:
            handle.write("# doom\n")
        with open(os.path.join(self.dir, "both.plugin"), "w") as handle:
            handle.write("# plugin\n")
        with open(os.path.join(self.dir, "both.py"), "w") as handle:
            handle.write("# py\n")

    def tearDown(self):
        fake.plugins_dir, plugin_loader._plugins_dir_cached = self.saved
        shutil.rmtree(self.dir, ignore_errors=True)

    def alias(self, name, mode="r"):
        return plugin_loader._plugin_file_alias(os.path.join(self.dir, name), mode)

    def test_a_missing_py_of_an_installed_plugin_is_its_plugin_file(self):
        self.assertEqual(self.alias("doom.py"), os.path.join(self.dir, "doom.plugin"))
        self.assertEqual(self.alias("doom.py", "rb"), os.path.join(self.dir, "doom.plugin"))

    def test_nothing_else_changes(self):
        # a py that exists, a plugin that is not installed, a write, another folder, another extension, and a path that is no text
        self.assertEqual(self.alias("both.py"), os.path.join(self.dir, "both.py"))
        self.assertEqual(self.alias("gone.py"), os.path.join(self.dir, "gone.py"))
        self.assertEqual(self.alias("doom.py", "w"), os.path.join(self.dir, "doom.py"))
        self.assertEqual(self.alias("doom.py", "a"), os.path.join(self.dir, "doom.py"))
        self.assertEqual(self.alias("doom.py", "r+"), os.path.join(self.dir, "doom.py"))
        self.assertEqual(self.alias("doom.txt"), os.path.join(self.dir, "doom.txt"))
        other = os.path.join(self.dir, "sub", "doom.py")
        self.assertEqual(plugin_loader._plugin_file_alias(other, "r"), other)
        self.assertEqual(plugin_loader._plugin_file_alias(7, "r"), 7)


if __name__ == "__main__":
    unittest.main()
