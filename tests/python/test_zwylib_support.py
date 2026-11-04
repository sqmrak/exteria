"""what a library such as zwylib needs of the host: reflection over the shims, xposed hooks on them, the plugin controller and
the hooks it fires, python subclasses of shim classes, and an .elyx library that neighbours import. zwylib itself is loaded
when EXTERIA_ZWYLIB names its .elyx file"""

import json
import os
import shutil
import sys
import tempfile
import threading
import time
import unittest
import warnings
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


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-zwylib-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def pump(until, seconds=5):
    end = time.time() + seconds
    while time.time() < end:
        while fake.timers:
            token, _delay = fake.timers.pop(0)
            exteria_host.run_token(token)
        if until():
            return True
        time.sleep(0.01)
    return False


def logged():
    return [data["message"] for name, data in list(fake.calls) if name == "log"]


class Reflection(unittest.TestCase):
    def test_a_class_knows_its_name_and_its_methods(self):
        from java.lang import Class
        from org.telegram.messenger import LocaleController
        cls = LocaleController.getClass()
        self.assertIsInstance(cls, Class)
        self.assertEqual(cls.getName(), "org.telegram.messenger.LocaleController")
        self.assertEqual(cls.getSimpleName(), "LocaleController")
        self.assertEqual(cls.getSuperclass().getName(), "java.lang.Object")
        self.assertEqual(LocaleController.getInstance().getClass(), cls)
        names = [method.getName() for method in cls.getDeclaredMethods()]
        self.assertIn("applyLanguage", names)
        self.assertNotIn("__init__", names)

    def test_a_registered_class_keeps_its_java_name(self):
        from java import jclass
        controller = jclass("app.exteraless.plugins.PluginsController")
        self.assertEqual(controller.getClass().getName(), "app.exteraless.plugins.PluginsController")

    def test_method_counts_invokes_and_misses(self):
        from java.lang import NoSuchMethodException
        from org.telegram.messenger import LocaleController
        cls = LocaleController.getClass()
        method = cls.getDeclaredMethod("applyLanguage")
        self.assertEqual(method.getParameterCount(), 1)
        self.assertEqual(method.getDeclaringClass(), cls)
        method.invoke(LocaleController.getInstance(), "en")
        with self.assertRaises(NoSuchMethodException):
            cls.getDeclaredMethod("nope")

    def test_java_exception_is_named_like_java(self):
        from java.lang import Exception as JavaException
        error = JavaException("boom")
        self.assertEqual(error.getMessage(), "boom")
        self.assertEqual(type(error).__name__, "Exception")


class Target:
    """a class of the shims to hook"""

    def add(self, a, b):
        return a + b

    @staticmethod
    def twice(value):
        return value * 2

    def fail(self):
        raise ValueError("original")


class Xposed(unittest.TestCase):
    def setUp(self):
        from java.lang import Class
        self.cls = Class._of(Target)
        self.hooks = []

    def tearDown(self):
        for hook in self.hooks:
            hook.unhook()

    def hook(self, name, before=None, after=None, priority=0):
        from de.robv.android.xposed import XC_MethodHook, XposedBridge

        class Callback(XC_MethodHook):
            pass

        Callback.priority = priority
        if before:
            Callback.beforeHookedMethod = lambda self, param: before(param)
        if after:
            Callback.afterHookedMethod = lambda self, param: after(param)
        unhook = XposedBridge.hookMethod(self.cls.getDeclaredMethod(name), Callback())
        self.hooks.append(unhook)
        return unhook

    def test_before_changes_arguments_and_after_changes_the_result(self):
        self.hook("add", before=lambda p: p.args.__setitem__(1, 10), after=lambda p: p.setResult(p.getResult() * 2))
        self.assertEqual(Target().add(1, 2), 22)

    def test_before_result_skips_the_original_and_the_callbacks_after_it(self):
        seen = []
        self.hook("add", before=lambda p: p.setResult(99), priority=10)
        self.hook("add", before=lambda p: seen.append("low"))
        self.assertEqual(Target().add(1, 2), 99)
        self.assertEqual(seen, [])

    def test_higher_priority_runs_first(self):
        order = []
        self.hook("add", before=lambda p: order.append("low"), priority=1)
        self.hook("add", before=lambda p: order.append("high"), priority=5)
        Target().add(1, 2)
        self.assertEqual(order, ["high", "low"])

    def test_after_sees_the_throwable_of_the_original(self):
        caught = []
        self.hook("fail", after=lambda p: caught.append(p.getThrowable()))
        with self.assertRaises(ValueError):
            Target().fail()
        self.assertEqual(str(caught[0]), "original")

    def test_a_failing_callback_does_not_break_the_call(self):
        def broken(_param):
            raise RuntimeError("callback")
        self.hook("add", before=broken)
        self.assertEqual(Target().add(1, 2), 3)
        self.assertTrue(any("xposed: before callback" in line for line in logged()))

    def test_static_methods_and_unhook(self):
        unhook = self.hook("twice", after=lambda p: p.setResult(p.getResult() + 1))
        self.assertEqual(Target.twice(4), 9)
        unhook.unhook()
        self.assertEqual(Target.twice(4), 8)
        self.assertNotIn("twice", [k[1] for k in __import__("de.robv.android.xposed", fromlist=["x"]).XposedBridge._chains])

    def test_hooking_keeps_the_signature_reflection_reports(self):
        self.hook("add")
        self.assertEqual(self.cls.getDeclaredMethod("add").getParameterCount(), 2)


class Controller(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        self.path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "plugins", "upper.plugin")
        self.hooks = []

    def tearDown(self):
        for hook in self.hooks:
            hook.unhook()
        exteria_host.unload("upper")

    def hook(self, cls, name, before):
        from base_plugin import MethodHook
        from de.robv.android.xposed import XposedBridge
        from app.exteraless.plugins.xposed import PyMethodHook

        class Handler(MethodHook):
            pass

        Handler.before_hooked_method = lambda self, param: before(param)
        method = cls.getClass().getDeclaredMethod(name)
        unhook = XposedBridge.hookMethod(method, PyMethodHook("test", Handler()))
        self.hooks.append(unhook)
        return unhook

    def test_the_host_loads_and_unloads_through_the_controller(self):
        from app.exteraless.plugins.controller import PluginsController, PythonPluginsEngine
        toggles = []
        unloads = []
        self.hook(PluginsController, "setPluginEnabled", lambda p: toggles.append((p.args[0], p.args[1])))
        self.hook(PythonPluginsEngine, "unloadPlugin", lambda p: unloads.append(p.args[0]))
        self.assertTrue(exteria_host.load(self.path, "upper")["ok"])
        self.assertEqual(toggles, [("upper", True)])
        exteria_host.unload("upper")
        self.assertEqual(toggles, [("upper", True), ("upper", False)])
        self.assertEqual(unloads, ["upper"])

    def test_the_controller_lists_the_loaded_plugins(self):
        from app.exteraless.plugins.controller import PluginsController
        controller = PluginsController.getInstance()
        self.assertFalse(controller.plugins.containsKey("upper"))
        exteria_host.load(self.path, "upper")
        plugin = controller.plugins.get("upper")
        self.assertEqual(plugin.getName(), "Upper")
        self.assertEqual(plugin.getVersion(), "1.0")
        self.assertEqual(plugin.getAuthor(), "test")
        self.assertEqual(plugin.getEngine(), "python")
        self.assertTrue(plugin.isEnabled())
        self.assertIn("upper", [str(key) for key in controller.plugins.keySet().toArray()])
        instances = PluginsController.getEngines().get("python").pluginInstances
        self.assertIs(instances.get("upper"), plugin_loader.plugins["upper"].instance)

    def test_a_refused_plugin_still_answers_with_its_reason(self):
        result = exteria_host.load(os.path.join(PLUGINS, "missing.plugin"), "missing")
        self.assertFalse(result["ok"])

    def test_engine_knows_plugin_files(self):
        from app.exteraless.plugins.controller import PluginsController
        from java.io import File
        engine = PluginsController.getEngines().get("python")
        self.assertTrue(engine.isPlugin(File("a.plugin"), None))
        self.assertTrue(engine.isPlugin(File("a.elyx"), None))
        self.assertFalse(engine.isPlugin(File("a.txt"), None))
        with self.assertRaises(NotImplementedError):
            engine.loadPluginFromFile("a.plugin", None, None, None)

    def test_hooks_of_a_plugin_go_with_it(self):
        from app.exteraless.plugins.controller import PluginsController
        from de.robv.android.xposed import XposedBridge
        controller = PluginsController.getInstance()
        exteria_host.load(self.path, "upper")
        unhook = XposedBridge.hookMethod(Controller.target_method(), self.callback())
        controller.addXposedHook("upper", unhook)
        self.assertIn(("setPluginEnabled"), [key[1] for key in XposedBridge._chains])
        exteria_host.unload("upper")
        self.assertNotIn("setPluginEnabled", [key[1] for key in XposedBridge._chains])

    @staticmethod
    def target_method():
        from app.exteraless.plugins.controller import PluginsController
        return PluginsController.getClass().getDeclaredMethod("setPluginEnabled")

    @staticmethod
    def callback():
        from de.robv.android.xposed import XC_MethodHook
        return XC_MethodHook()

    def test_a_library_is_told_when_the_language_changes(self):
        from org.telegram.messenger import LocaleController
        heard = []
        self.hook(LocaleController, "applyLanguage", lambda p: heard.append(p.args[0]))
        fake.language = "ru"
        try:
            self.assertEqual(LocaleController.getInstance().getCurrentLocaleInfo().pluralLangCode, "ru")
            exteria_host.language_changed()
        finally:
            fake.language = "en"
        self.assertEqual(heard, ["ru"])

    def test_the_client_version_is_the_one_of_the_app(self):
        from org.telegram.messenger import BuildVars
        self.assertEqual(BuildVars.BUILD_VERSION_STRING, "1.0")


class Proxies(unittest.TestCase):
    def test_a_python_subclass_of_a_shim_class(self):
        from extera_utils.classes import Base, java_subclass, joverride, super
        from java.util import ArrayList

        @java_subclass(ArrayList)
        class Loud(Base):
            @joverride()
            def add(self, item):
                return super().add(item.upper())

        loud = Loud.new_instance()
        loud.java.add("a")
        loud.java.add("b")
        self.assertEqual(list(loud.java), ["A", "B"])
        self.assertIs(Loud.from_java(loud.java), loud)
        self.assertEqual(Loud.java_class().getSuperclass().getName(), "java.util.ArrayList")

    def test_a_subclass_of_a_nested_class_and_a_field_it_cannot_have(self):
        from app.exteraless.plugins.models import CustomSetting
        from extera_utils.classes import Base, java_subclass, jfield

        @java_subclass(CustomSetting.Factory)
        class Factory(Base):
            pass

        self.assertIsNotNone(Factory.new_instance().java)

        @java_subclass(CustomSetting.Factory)
        class WithField(Base):
            count = jfield("int", default=0)

        with self.assertRaises(RuntimeError) as raised:
            WithField.new_instance()
        self.assertIn("jfield", str(raised.exception))

    def test_requests_to_telegram_fail_with_their_reason(self):
        from org.telegram.messenger import AccountInstance, MessagesController
        with self.assertRaises(NotImplementedError) as raised:
            MessagesController.getInstance(0).getInputPeer(5)
        self.assertIn("telegram requests", str(raised.exception))
        with self.assertRaises(NotImplementedError):
            AccountInstance.getInstance(0).getConnectionsManager()
        from android.app import activity
        with self.assertRaises(NotImplementedError):
            activity().openMessage(1, 2, None, None, 0, -1, None, None)

    def test_a_custom_row_factory_is_recorded_once_per_class(self):
        from org.telegram.ui.Components import UItem

        class Factory:
            pass

        before = len(UItem.UItemFactory.factories)
        UItem.UItemFactory.setup(Factory())
        UItem.UItemFactory.setup(Factory())
        self.assertEqual(len(UItem.UItemFactory.factories), before + 1)
        item = UItem.ofFactory(Factory)
        self.assertIs(item.factory, Factory)
        row = UItem.asRoundCheckbox(-1, "text").setChecked(True).pad()
        self.assertEqual((row.kind, row.text, row.checked, row.padded), ("round_checkbox", "text", True, True))


TRIMMED = r'''
import importlib.abc, sys
sys.path.insert(0, sys.argv[1])
# the extensions the device bundle does not build (scripts/build_python.sh, drop) and the stdlib folders it leaves out
BLOCK = {"_lzma", "_bz2", "_decimal", "pyexpat", "_elementtree", "_uuid", "_multiprocessing", "multiprocessing", "termios", "syslog"}

class Block(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path=None, target=None):
        if name.partition(".")[0] in BLOCK:
            raise ImportError("not in the device bundle: " + name)

sys.meta_path.insert(0, Block())
import asyncio, threading
loop = asyncio.new_event_loop()
threading.Thread(target=lambda: (asyncio.set_event_loop(loop), loop.run_forever()), daemon=True).start()

async def answer():
    await asyncio.sleep(0.01)
    return 5

print(asyncio.run_coroutine_threadsafe(answer(), loop).result(5))
import subprocess
try:
    subprocess.run(["true"])
except OSError as error:
    print("no process:", error.errno)
'''


class DeviceStdlib(unittest.TestCase):
    def test_asyncio_imports_without_the_extensions_the_bundle_leaves_out(self):
        # zwylib runs its tasks on an asyncio loop, and asyncio imports subprocess, which needs _posixsubprocess (no fork on ios)
        # not subprocess: the shim of _posixsubprocess is first on the path of this process too
        read, write = os.pipe()
        pid = os.posix_spawn(sys.executable, [sys.executable, "-I", "-c", TRIMMED, os.path.join(ROOT, "python", "shim")], os.environ,
                             file_actions=[(os.POSIX_SPAWN_DUP2, write, 1), (os.POSIX_SPAWN_DUP2, write, 2), (os.POSIX_SPAWN_CLOSE, read)])
        os.close(write)
        with os.fdopen(read) as pipe:
            output = pipe.read()
        _pid, status = os.waitpid(pid, 0)
        self.assertEqual(status, 0, output)
        self.assertEqual(output.split(), ["5", "no", "process:", "38"])


class Versions(unittest.TestCase):
    def test_versions_order_like_pep_440(self):
        from packaging.version import InvalidVersion, Version
        table = [("3.0.0", "3.0.0", 0), ("3.0", "3.0.0", 0), ("12.10.6", "12.5.1", 1), ("2.0.6", "2.0.10", -1),
                 ("1.0.0rc1", "1.0.0", -1), ("1.0.0.dev1", "1.0.0a1", -1), ("1.0.0", "1.0.0.post1", -1),
                 ("1.0.0b2", "1.0.0a9", 1), ("v1.2", "1.2.0", 0), ("1.0+local", "1.0", 0)]
        for left, right, expected in table:
            with self.subTest(left=left, right=right):
                self.assertEqual((Version(left) > Version(right)) - (Version(left) < Version(right)), expected)
        for bad in ("", "x", "1..2", "1.0 beta two"):
            with self.subTest(bad=bad):
                with self.assertRaises(InvalidVersion):
                    Version(bad)

    def test_deprecated_warns_and_calls_through(self):
        from typing_extensions import deprecated

        @deprecated("old")
        def old():
            return 7

        with warnings.catch_warnings(record=True) as seen:
            warnings.simplefilter("always")
            self.assertEqual(old(), 7)
        self.assertEqual(len(seen), 1)


LIBRARY = {
    "metainfo.yml": "id: minilib\nname: MiniLib\ndescription: a library\nauthor: test\nversion: '1.0.0'\n",
    "refmap.yml": "metainfo: metainfo.yml\nmain: src/main.py\n",
    "__init__.py": 'if __name__ == "minilib":\n    from .src.api import *\n',
    "src/__init__.py": "",
    "src/api.py": '''
import os.path
import sys

import file_utils


def caller_id():
    """the plugin behind the calling file, found the way zwylib finds it: by the ElyxPlugins segment or the name of the file"""
    root = file_utils.get_plugins_dir()
    frame = sys._getframe(1)
    while frame is not None:
        path = frame.f_code.co_filename
        if root in path:
            if "ElyxPlugins" in path:
                return path.split("ElyxPlugins/")[1].split("/")[0]
            return os.path.splitext(path)[0].split("/")[-1]
        frame = frame.f_back
    return None
''',
    "src/main.py": '''
import sys

from base_plugin import BasePlugin
from minilib.src import api


class MiniLib(BasePlugin):
    def on_plugin_load(self):
        self.set_setting("owner", api.caller_id())
        self.set_setting("file", sys._getframe().f_code.co_filename)
''',
}

NEIGHBOUR = '''
__id__ = "neighbour"
__name__ = "Neighbour"
__description__ = "uses minilib"
__author__ = "test"
__version__ = "1.0"
__min_version__ = "11.9.0"
__icon__ = "msg_edit"

import minilib
from base_plugin import BasePlugin


class Neighbour(BasePlugin):
    def on_plugin_load(self):
        self.set_setting("owner", minilib.caller_id())
        self.set_setting("library", minilib.__file__)
'''


def build_library(path, files=LIBRARY):
    with zipfile.ZipFile(path, "w") as archive:
        for name, text in files.items():
            archive.writestr(name, text)


class ElyxLibrary(unittest.TestCase):
    def setUp(self):
        fake.calls.clear()
        fake.settings.clear()
        self.archive = os.path.join(PLUGINS, "minilib.elyx")
        self.neighbour = os.path.join(PLUGINS, "neighbour.plugin")
        build_library(self.archive)
        with open(self.neighbour, "w") as f:
            f.write(NEIGHBOUR)

    def tearDown(self):
        exteria_host.unload("neighbour")
        exteria_host.unload("minilib")
        for name in list(sys.modules):
            if name == "minilib" or name.startswith("minilib."):
                del sys.modules[name]

    def test_the_entry_module_runs_from_the_elyx_plugins_link(self):
        result = exteria_host.load(self.archive, "minilib")
        self.assertTrue(result["ok"], result)
        run_from = fake.settings[("minilib", "file")].strip('"')
        self.assertIn(os.sep.join(["ElyxPlugins", "minilib", "src", "main.py"]), run_from)
        # the setting is written by the plugin itself, not by a plugin called main
        self.assertEqual(json.loads(fake.settings[("minilib", "owner")]), "minilib")
        self.assertFalse([key for key in fake.settings if key[0] == "main"])

    def test_the_owner_of_a_file_under_the_link_is_its_plugin(self):
        exteria_host.load(self.archive, "minilib")
        path = os.path.join(PLUGINS, "ElyxPlugins", "minilib", "src", "api.py")
        self.assertEqual(plugin_loader._resolve_owner(path), "minilib")

    def test_a_neighbour_imports_the_library_as_a_package(self):
        self.assertTrue(exteria_host.load(self.archive, "minilib")["ok"])
        result = exteria_host.load(self.neighbour, "neighbour")
        self.assertTrue(result["ok"], result)
        self.assertEqual(json.loads(fake.settings[("neighbour", "owner")]), "neighbour")
        self.assertIn(os.sep.join(["ElyxPlugins", "minilib"]), json.loads(fake.settings[("neighbour", "library")]))

    def test_reloading_the_library_replaces_its_modules(self):
        self.assertTrue(exteria_host.load(self.archive, "minilib")["ok"])
        exteria_host.unload("minilib")
        for name in list(sys.modules):
            if name == "minilib" or name.startswith("minilib."):
                del sys.modules[name]
        build_library(self.archive, dict(LIBRARY, **{"src/api.py": LIBRARY["src/api.py"] + "\nVERSION = 2\n"}))
        self.assertTrue(exteria_host.load(self.archive, "minilib")["ok"])
        import minilib
        self.assertEqual(minilib.VERSION, 2)


NEEDS_ZWYLIB = unittest.skipUnless(os.environ.get("EXTERIA_ZWYLIB"), "set EXTERIA_ZWYLIB to the zwylib .elyx file")

CLIENT = '''
__id__ = "zwyclient"
__name__ = "ZwyClient"
__description__ = "uses zwylib"
__author__ = "test"
__version__ = "1.0"
__min_version__ = "11.9.0"
__icon__ = "msg_edit"

import zwylib
from base_plugin import BasePlugin

S = zwylib.SettingEntry("answer", "42")
L = zwylib.locales_controller.generate_locale_class({"en": {"hello": "hello {name}"}, "ru": {"hello": "privet {name}"}})


class Client(BasePlugin):
    def on_plugin_load(self):
        zwylib.add_autoupdater_task(1234, 5)
        zwylib.async_manager.run_task(self.later())
        self.set_setting("entry_owner", S.plugin_id)

    async def later(self):
        self.set_setting("async_ran", True)
'''


@NEEDS_ZWYLIB
class Zwylib(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fake.calls.clear()
        fake.settings.clear()
        cls.client = os.path.join(PLUGINS, "zwyclient.plugin")
        with open(cls.client, "w") as f:
            f.write(CLIENT)
        result = exteria_host.load(os.environ["EXTERIA_ZWYLIB"], "zwylib")
        assert result["ok"], result

    @classmethod
    def tearDownClass(cls):
        exteria_host.unload("zwyclient")
        exteria_host.unload("zwylib")

    def test_the_hooks_on_the_plugin_engine_are_in_place(self):
        from de.robv.android.xposed import XposedBridge
        names = sorted(key[1] for key in XposedBridge._chains)
        self.assertEqual(names, ["applyLanguage", "setPluginEnabled", "unloadPlugin"])

    def test_commands_run_on_the_send_hook(self):
        out = exteria_host.send_message_hook("zwylib", 0, {"message": ".zwylib cmds", "peer": 5, "replyToMsg": 0})
        self.assertEqual(out["strategy"], "MODIFY_FINAL")
        self.assertIn("zwylib cmds test", out["params"]["message"])
        self.assertEqual(exteria_host.send_message_hook("zwylib", 0, {"message": "hello"})["strategy"], "DEFAULT")

    def test_settings_of_the_library_belong_to_the_library(self):
        self.assertTrue(exteria_host.settings("zwylib"))
        self.assertFalse([key for key in fake.settings if key[0] == "main"])

    def test_a_client_plugin_uses_the_library_and_is_cleaned_up_after(self):
        import zwylib
        self.assertTrue(exteria_host.load(self.client, "zwyclient")["ok"])
        self.assertEqual(json.loads(fake.settings[("zwyclient", "entry_owner")]), "zwyclient")
        self.assertTrue(pump(lambda: ("zwyclient", "async_ran") in fake.settings))
        self.assertIn("zwyclient", [task.plugin_id for task in zwylib._state.autoupdater.tasks])
        self.assertEqual(zwylib.locales_controller.generate_locale_class({"en": {"hello": "hi {name}"}}).hello(name="x"), "hi x")
        exteria_host.unload("zwyclient")
        self.assertNotIn("zwyclient", [task.plugin_id for task in zwylib._state.autoupdater.tasks])

    def test_the_locale_follows_the_language_of_the_app(self):
        import zwylib
        table = zwylib.locales_controller.generate_locale_class({"en": {"hello": "hello"}, "ru": {"hello": "privet"}})
        self.assertEqual(table.hello, "hello")
        fake.language = "ru"
        try:
            exteria_host.language_changed()
            self.assertEqual(table.hello, "privet")
        finally:
            fake.language = "en"
            exteria_host.language_changed()

    def test_a_request_to_telegram_fails_loudly_and_does_not_hang(self):
        import zwylib
        future = zwylib.async_manager.run_task(zwylib.Requests.get_message(-100, 1))
        self.assertTrue(pump(future.done))
        self.assertTrue(any("telegram requests" in line for line in logged()))

    def test_unloading_and_loading_again_leaves_one_set_of_hooks(self):
        from de.robv.android.xposed import XposedBridge
        exteria_host.unload("zwylib")
        self.assertEqual(XposedBridge._chains, {})
        self.assertTrue(exteria_host.load(os.environ["EXTERIA_ZWYLIB"], "zwylib")["ok"])
        self.assertEqual(len(XposedBridge._chains), 3)


if __name__ == "__main__":
    unittest.main()
