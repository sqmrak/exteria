"""PluginsController, PythonPluginsEngine and Plugin of exteraGram over the plugin registry of the sdk.

the registry of the host is the plugin loader: a plugin it holds is loaded, and loaded is what enabled means here, since
the app switches a plugin on by loading it. zwylib and its neighbours reach the plugins through these classes and hook
setPluginEnabled and unloadPlugin of them, so the host calls through them too: that is how a library learns that a plugin
went away"""

import os
import threading

from extera_utils import plugin_loader
from java.lang import Object
from java.util.concurrent import ConcurrentHashMap

PYTHON = "python"
PLUGIN_EXTENSIONS = (".plugin", ".py", ".elyx", ".eaf")


class _PluginError(Exception):
    def getMessage(self):
        return str(self)


class Plugin(Object):
    def __init__(self, plugin_id):
        self._id = plugin_id
        self._error = None

    def _record(self):
        return plugin_loader.plugins.get(self._id)

    def _field(self, name):
        record = self._record()
        value = getattr(record.instance, name, None) if record is not None and record.instance is not None else None
        return None if value is None else str(value)

    def getId(self):
        return self._id

    def getName(self):
        return self._field("name")

    def getVersion(self):
        return self._field("version")

    def getAuthor(self):
        return self._field("author")

    def getDescription(self):
        return self._field("description")

    def getEngine(self):
        return PYTHON

    def isEnabled(self):
        return self._id in plugin_loader.plugins

    def getError(self):
        return self._error

    def setError(self, error):
        self._error = error

    def _icon(self):
        icon = self._field("icon") or ""
        pack, _, index = icon.partition("/")
        return (pack, int(index)) if pack and index.isdigit() else (None, -1)

    def getPack(self):
        return self._icon()[0]

    def getIndex(self):
        return self._icon()[1]


class PythonPluginsEngine(Object):
    def __init__(self):
        self._paths = {}

    @property
    def pluginInstances(self):
        instances = ConcurrentHashMap()
        for plugin_id, record in list(plugin_loader.plugins.items()):
            instances.put(plugin_id, record.instance)
        return instances

    def isPlugin(self, file, _context=None):
        return str(file.getName()).lower().endswith(PLUGIN_EXTENSIONS)

    def loadPlugin(self, plugin_id, path):
        """remembers where the file of a plugin is; it runs when setPluginEnabled turns it on"""
        self._paths[plugin_id] = path

    def setPluginEnabled(self, plugin_id, enabled, _callback=None):
        """loads or unloads a plugin; the answer of a load is the json of the plugin loader, which tells why a plugin refused"""
        if not enabled:
            self.unloadPlugin(plugin_id)
            return None
        path = self._paths.get(plugin_id)
        if path is None:
            raise LookupError("no file known for plugin " + plugin_id)
        return plugin_loader.load_plugin(path, plugin_id)

    def unloadPlugin(self, plugin_id):
        plugin_loader.unload_plugin(plugin_id)
        PluginsController.getInstance()._drop_hooks(plugin_id)

    def loadPluginFromFile(self, *_args):
        raise NotImplementedError("a plugin file is added by the person in the plugins page, not by python")


class PluginsController(Object):
    _instance = None
    _guard = threading.Lock()

    def __init__(self):
        self._engines = ConcurrentHashMap()
        self._engines.put(PYTHON, PythonPluginsEngine())
        self._hooks = {}

    @staticmethod
    def getInstance():
        with PluginsController._guard:
            if PluginsController._instance is None:
                PluginsController._instance = PluginsController()
            return PluginsController._instance

    @staticmethod
    def getEngines():
        return PluginsController.getInstance()._engines

    @staticmethod
    def getPlugins():
        return PluginsController.getInstance().plugins

    @property
    def plugins(self):
        known = ConcurrentHashMap()
        for plugin_id in list(plugin_loader.plugins):
            known.put(plugin_id, Plugin(plugin_id))
        return known

    def setPluginEnabled(self, plugin_id, enabled, callback=None):
        return self._engines.get(PYTHON).setPluginEnabled(plugin_id, enabled, callback)

    def loadPluginSettings(self, plugin_id):
        from app.exteraless.plugins import PythonBridge
        PythonBridge.reloadSettingsScreen(plugin_id)

    def addXposedHook(self, plugin_id, unhook):
        self._hooks.setdefault(plugin_id, []).append(unhook)

    def removeXposedHook(self, plugin_id, unhook):
        remaining = self._hooks.get(plugin_id, [])
        if unhook in remaining:
            remaining.remove(unhook)
        unhook.unhook()

    def _drop_hooks(self, plugin_id):
        """a plugin that is gone leaves no callback of its own on a method"""
        for unhook in self._hooks.pop(plugin_id, []):
            unhook.unhook()
