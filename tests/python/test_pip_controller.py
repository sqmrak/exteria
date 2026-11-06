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


class Wheels(unittest.TestCase):
    """the libraries of third_party/python/wheels.sha256 sit in python/lib of the bundle, which is on sys.path of the app. a requirement
    line of a plugin names the distribution, and the module has another spelling"""

    def test_the_distribution_names_of_the_wheels_find_their_modules(self):
        import tempfile
        with tempfile.TemporaryDirectory() as lib:
            for module in ("yt_dlp", "mutagen"):
                os.makedirs(os.path.join(lib, module))
                open(os.path.join(lib, module, "__init__.py"), "w").close()
            sys.path.insert(0, lib)
            try:
                pip_controller.ensure_requirements("p", ["yt-dlp", "mutagen>=1.45", "yt_dlp"])
            finally:
                sys.path.remove(lib)
        with self.assertRaises(RuntimeError) as raised:
            pip_controller.ensure_requirements("p", ["yt-dlp-not-bundled"])
        self.assertIn("yt-dlp-not-bundled", str(raised.exception))

    def test_every_wheel_of_the_list_has_a_pinned_hash_and_a_pypi_name(self):
        listed = [line.split() for line in open(os.path.join(ROOT, "third_party", "python", "wheels.sha256")) if line.strip() and not line.startswith("#")]
        self.assertTrue(listed)
        for digest, wheel in listed:
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertTrue(wheel.endswith("-py3-none-any.whl"), wheel)


if __name__ == "__main__":
    unittest.main()
