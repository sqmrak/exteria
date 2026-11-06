"""the stdlib on ios reports sys.platform == "darwin", which the linux host does not, and some of its modules take another path then: urllib.request imports
_scproxy, which the device bundle does not build and the shim stands in for. this process imports what plugins use with the platform set to darwin"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MODULES = ["urllib.request", "uuid", "shutil", "webbrowser", "sysconfig", "site", "platform", "posixpath", "asyncio", "ssl", "http.client", "tempfile",
           "logging", "socket", "zipfile", "tarfile", "importlib.metadata", "email", "json", "sqlite3", "xml.etree.ElementTree", "lzma", "bz2"]

CODE = r'''
import sys
sys.platform = "darwin"
sys.path.insert(0, sys.argv[1])
for name in sys.argv[2:]:
    __import__(name)
import urllib.request as request
print(callable(request.getproxies_macosx_sysconf))
'''


class DarwinStdlib(unittest.TestCase):
    def run_with(self, shim):
        """returncode, output: spawned without subprocess, which the shim of _posixsubprocess in this process cannot start"""
        args = [sys.executable, "-I", "-c", CODE, shim] + MODULES
        read, write = os.pipe()
        pid = os.posix_spawn(sys.executable, args, os.environ,
                             file_actions=[(os.POSIX_SPAWN_DUP2, write, 1), (os.POSIX_SPAWN_DUP2, write, 2), (os.POSIX_SPAWN_CLOSE, read)])
        os.close(write)
        with os.fdopen(read) as pipe:
            output = pipe.read()
        _pid, status = os.waitpid(pid, 0)
        return status, output

    def test_the_modules_plugins_use_import_and_urllib_finds_no_system_proxy(self):
        status, output = self.run_with(os.path.join(ROOT, "python", "shim"))
        self.assertEqual(status, 0, output[-1500:])
        self.assertEqual(output.split("\n")[0], "True")

    def test_without_the_stand_in_the_import_names_the_missing_module(self):
        # keeps the first test honest: the failure it guards against is real
        empty = os.path.join(ROOT, "tests", "python", "plugins")
        status, output = self.run_with(empty)
        self.assertNotEqual(status, 0)
        self.assertIn("_scproxy", output)


class SystemProxy(unittest.TestCase):
    """the answers of _scproxy over the system settings the app reads, which fakeapp.proxies stands in for"""

    def setUp(self):
        sys.path[:0] = [os.path.join(ROOT, "tests", "python"), os.path.join(ROOT, "python", "shim")]
        import fakeapp
        self.fake = fakeapp.fake
        self.saved = self.fake.proxies
        import _scproxy
        self.scproxy = _scproxy

    def tearDown(self):
        self.fake.proxies = self.saved

    def test_no_proxy_is_no_entry_and_no_exceptions(self):
        self.fake.proxies = {"exclude_simple": False, "exceptions": []}
        self.assertEqual(self.scproxy._get_proxies(), {})
        self.assertEqual(self.scproxy._get_proxy_settings(), {"exclude_simple": False, "exceptions": ()})

    def test_a_switched_on_scheme_is_an_http_url_with_its_port_when_it_has_one(self):
        self.fake.proxies = {"http": {"host": "10.0.0.5", "port": 8080}, "https": {"host": "proxy.local"}, "exclude_simple": True,
                             "exceptions": ["*.local", "10.0/16"]}
        self.assertEqual(self.scproxy._get_proxies(), {"http": "http://10.0.0.5:8080", "https": "http://proxy.local"})
        self.assertEqual(self.scproxy._get_proxy_settings(), {"exclude_simple": True, "exceptions": ("*.local", "10.0/16")})

    def test_urllib_takes_them_when_it_runs_as_on_ios(self):
        self.fake.proxies = {"http": {"host": "10.0.0.5", "port": 8080}, "exclude_simple": False, "exceptions": ["example.com"]}
        # urllib.request picks its macos functions at import, by the platform it sees
        platform, known = sys.platform, sys.modules.pop("urllib.request", None)
        sys.platform = "darwin"
        try:
            import urllib.request as request
            self.assertEqual(request.getproxies_macosx_sysconf(), {"http": "http://10.0.0.5:8080"})
            self.assertTrue(request.proxy_bypass_macosx_sysconf("example.com"))
            self.assertFalse(request.proxy_bypass_macosx_sysconf("other.org"))
        finally:
            sys.platform = platform
            sys.modules.pop("urllib.request", None)
            if known is not None:
                # the package keeps the module it imported last as its attribute, and requests holds on to the first one
                sys.modules["urllib.request"] = known
                import urllib
                urllib.request = known


if __name__ == "__main__":
    unittest.main()
