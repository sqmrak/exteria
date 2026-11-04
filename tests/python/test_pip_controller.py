import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import pip_controller  # noqa: E402


class Requirements(unittest.TestCase):
    def test_modules_of_the_bundle_are_provided(self):
        for name in ("websocket-client", "requests", "certifi", "PyYAML", "json", "Websocket_Client"):
            with self.subTest(name):
                self.assertTrue(pip_controller.is_provided(name))
        pip_controller.ensure_requirements("p", ["websocket-client>=1.0", "certifi", "requests; python_version>'3'"])

    def test_a_missing_package_fails_the_load_by_name_and_installs_nothing(self):
        self.assertFalse(pip_controller.is_provided("numpy-not-here"))
        with self.assertRaises(RuntimeError) as raised:
            pip_controller.ensure_requirements("p", ["certifi", "numpy-not-here==1.0", "other[extra]>=2"])
        self.assertIn("numpy-not-here, other", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
