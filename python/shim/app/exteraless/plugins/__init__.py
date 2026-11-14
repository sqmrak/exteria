"""PythonBridge and PluginServices of the exteraless app, over the services of the ios host.

every call is one request to the app through _exteria.service(name, json). the names and payloads are listed in
docs/plugins.md. a request the app refuses comes back as PermissionError, LookupError, ValueError or
NotImplementedError, see core/pyhost"""

import json
import sys
import threading

import _exteria
import _mainthread

from java import _registry

SDK_VERSION = "1.0.0"


def _ask_here(name, **payload):
    reply = _exteria.service(name, json.dumps(payload, ensure_ascii=False))
    return json.loads(reply) if reply else None


def _ask(name, **payload):
    return _mainthread.call(lambda: _ask_here(name, **payload))


def _value(name, **payload):
    reply = _ask(name, **payload)
    return reply.get("value") if isinstance(reply, dict) else None


_menu_callbacks = {}


def forget_plugin(plugin_id):
    """the menu items of a plugin that is switched off: their callbacks would keep its objects alive and could still be called"""
    for key in [key for key in _menu_callbacks if key[0] == plugin_id]:
        del _menu_callbacks[key]


_tokens = {}
_token_lock = threading.Lock()
_next_token = [1]


class PythonBridge:
    @staticmethod
    def getSetting(plugin_id, key):
        return _value("settings.get", plugin=plugin_id, key=key)

    @staticmethod
    def setSetting(plugin_id, key, json_value, reload_settings):
        _ask("settings.set", plugin=plugin_id, key=key, value=json_value, reload=bool(reload_settings))

    @staticmethod
    def exportSettings(plugin_id):
        return _value("settings.export", plugin=plugin_id) or "{}"

    @staticmethod
    def importSettings(plugin_id, json_text, reload_settings):
        _ask("settings.import", plugin=plugin_id, value=json_text, reload=bool(reload_settings))

    @staticmethod
    def replaceSettings(plugin_id, json_text):
        _ask("settings.replace", plugin=plugin_id, value=json_text)

    @staticmethod
    def log(plugin_id, message):
        _ask("log", plugin=plugin_id, level="I", message=str(message))

    @staticmethod
    def logStream(plugin_id, level, message):
        _ask("log", plugin=plugin_id, level=str(level), message=str(message))

    @staticmethod
    def addRequestHook(plugin_id, request_name, match_substring, priority):
        _ask("hook.request.add", plugin=plugin_id, name=request_name, substring=bool(match_substring),
             priority=int(priority))

    @staticmethod
    def addSendMessageHook(plugin_id, priority):
        _ask("hook.send.add", plugin=plugin_id, priority=int(priority))

    @staticmethod
    def removeRequestHook(plugin_id, request_name):
        _ask("hook.request.remove", plugin=plugin_id, name=request_name)

    @staticmethod
    def removeSendMessageHook(plugin_id):
        _ask("hook.send.remove", plugin=plugin_id)

    @staticmethod
    def addMenuItem(plugin_id, json_menu_item, on_click):
        item_id = _value("menu.add", plugin=plugin_id, item=json.loads(json_menu_item))
        if on_click is not None and item_id:
            _menu_callbacks[(plugin_id, item_id)] = on_click
        return item_id

    @staticmethod
    def removeMenuItem(plugin_id, item_id):
        _menu_callbacks.pop((plugin_id, item_id), None)
        _ask("menu.remove", plugin=plugin_id, id=item_id)

    @staticmethod
    def hasPermission(plugin_id, permission):
        return bool(_value("permission.has", plugin=plugin_id, permission=permission))

    @staticmethod
    def checkPermission(plugin_id, permission, what):
        return bool(_value("permission.check", plugin=plugin_id, permission=permission, what=what))

    @staticmethod
    def isUnsafeMode():
        return bool(_value("permission.unsafe"))

    @staticmethod
    def getPluginsDir():
        return _value("plugins.dir")

    @staticmethod
    def getCacheDir():
        """the folder the app may clear, and the only one a plugin can send photos from"""
        return _value("files.cache")

    @staticmethod
    def getSdkVersion():
        return SDK_VERSION

    @staticmethod
    def setDisplayHook(plugin_id, on):
        """a plugin hooks, or stops hooking, the call the host makes for each message it lays out"""
        _ask("hook.display.add" if on else "hook.display.remove", plugin=plugin_id)

    @staticmethod
    def reloadSettingsScreen(plugin_id):
        _ask("settings.reload", plugin=plugin_id)


def menu_click(plugin_id, item_id, context):
    """called by the app when a plugin menu item is tapped; context is a dict, the message of a message menu already a MessageObject"""
    callback = _menu_callbacks.get((plugin_id, item_id))
    if callback is None:
        raise LookupError("no menu callback for %s/%s" % (plugin_id, item_id))
    callback(context or {})


def run_token(token):
    """called by the app on the main thread for a callable queued with runOnUiThread"""
    with _token_lock:
        fn = _tokens.pop(int(token), None)
    if fn is None:
        return
    # a call queued by a plugin that fails must not unwind into the app's main queue
    try:
        fn()
    except Exception:
        import traceback
        print("[exteria] a function queued with runOnUiThread failed\n" + traceback.format_exc(), file=sys.stderr)


class _Runnable:
    def __init__(self, fn):
        self._fn = fn

    def run(self):
        self._fn()

    __call__ = run


class PluginServices:
    """the part of the java side the sdk calls: ui thread helpers, the proxy classes of the shims (proxy.py) and hooks on their
    methods (hooks.py). constructor hooks and intent handlers have no counterpart on ios and fail loudly, a plugin that needs
    them is not portable"""

    @staticmethod
    def sendRequest(_account, request, callback):
        """the requests of org.telegram.tgnet.requests; any other fails by name"""
        from org.telegram.tgnet import requests
        return requests.send(request, callback)

    @staticmethod
    def runOnUiThread(fn, delay_ms=0):
        with _token_lock:
            token = _next_token[0]
            _next_token[0] += 1
            _tokens[token] = fn
        # the app queues a token on its own main queue, so any thread may ask
        _ask_here("ui.run", token=token, delay=int(delay_ms))

    @staticmethod
    def postRunnable(queue, fn, delay_ms=0):
        queue.postRunnable(fn, int(delay_ms))

    @staticmethod
    def runnable(fn):
        return _Runnable(fn)

    @staticmethod
    def _unsupported(*_args, **_kwargs):
        raise NotImplementedError("not available on ios")

    hookAllConstructors = _unsupported
    registerIntentHandler = unregisterIntentHandler = _unsupported
    # the app has no way to hand a file that was opened in it to a plugin, so FilesController.register says so and not AttributeError
    registerFileHandler = unregisterFileHandler = _unsupported

    @staticmethod
    def hookMethod(plugin_id, member, handler, priority, filters_json):
        from app.exteraless.plugins import hooks
        return hooks.hook(plugin_id, member, handler, priority, filters_json)

    @staticmethod
    def hookAllMethods(plugin_id, target, name, handler, priority, filters_json):
        from app.exteraless.plugins import hooks
        return hooks.hook_all(plugin_id, target, name, handler, priority, filters_json)

    @staticmethod
    def unhook(key):
        from app.exteraless.plugins import hooks
        hooks.unhook(key)

    @staticmethod
    def generateProxyClass(owner, spec_json):
        from app.exteraless.plugins import proxy
        return proxy.generate(owner, spec_json)

    @staticmethod
    def getProxyError():
        from app.exteraless.plugins import proxy
        return proxy.error()

    @staticmethod
    def getProxyClass(key):
        from app.exteraless.plugins import proxy
        return proxy.proxy_class(key)

    @staticmethod
    def newProxyInstance(owner, key, signature, args, peer):
        from app.exteraless.plugins import proxy
        return proxy.new_instance(owner, key, signature, args, peer)

    @staticmethod
    def invokeSuper(key, proxy_object, py_key, args):
        from app.exteraless.plugins import proxy
        return proxy.invoke_super(key, proxy_object, py_key, args)


_registry.register("app.exteraless.plugins.PythonBridge", PythonBridge)
_registry.register("app.exteraless.plugins.PluginServices", PluginServices)

for _name, _attribute in (("PluginsController", "PluginsController"), ("Plugin", "Plugin"), ("PythonPluginsEngine", "PythonPluginsEngine")):
    _registry.register_lazy("app.exteraless.plugins." + _name, "app.exteraless.plugins.controller", _attribute)
_registry.register_lazy("app.exteraless.plugins.xposed.PyMethodHook", "app.exteraless.plugins.xposed", "PyMethodHook")
_registry.register_lazy("app.exteraless.plugins.xposed.PyMethodReplacement", "app.exteraless.plugins.xposed", "PyMethodReplacement")
_registry.register_lazy("app.exteraless.plugins.models.CustomSetting", "app.exteraless.plugins.models", "CustomSetting")
_registry.register_lazy("app.exteraless.plugins.PluginsConstants", "base_plugin", "PluginsConstants")
_registry.register_lazy("app.exteraless.plugins.ui.PluginSettingsActivity", "app.exteraless.plugins.ui", "PluginSettingsActivity")
_registry.register_lazy("com.exteragram.messenger.ExteraConfig", "app.exteraless.compat", "ExteraConfig")
_registry.register_lazy("com.exteragram.messenger.utils.AppUtils", "app.exteraless.compat", "AppUtils")
_registry.register_lazy("com.exteragram.messenger.utils.chats.ChatUtils", "app.exteraless.compat", "ChatUtils")


def display_hooks_active():
    from app.exteraless.plugins import hooks
    return hooks.display_hooks_active()
