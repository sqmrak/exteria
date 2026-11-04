"""BasePlugin.hook_method and hook_all_methods over the xposed of the shims (de/robv/android/xposed): the id the sdk keeps for an
unhook stands for the Unhook of the bridge. a method of a class the shims do not have cannot be hooked, since the class is not
there to ask for it.

one method is also the host's own call: ChatMessageCell.setMessageContent, which the app makes for every message it lays out
(exteria_host.display_messages). the app is told when a plugin hooks it, so it does not ask python about every message of
every chat while nobody listens"""

import json
import threading

from de.robv.android.xposed import XposedBridge
from java.lang import Class

_lock = threading.Lock()
_unhooks = {}
_counter = [0]
_display = {}


def _is_display(member):
    from org.telegram.ui.Cells import ChatMessageCell
    return member.getDeclaringClass()._py is ChatMessageCell and member.getName() == "setMessageContent"


def display_hooks_active():
    from org.telegram.ui.Cells import ChatMessageCell
    return (ChatMessageCell, "setMessageContent") in XposedBridge._chains


def _tell_app(plugin_id, on):
    from app.exteraless.plugins import PythonBridge
    PythonBridge.setDisplayHook(plugin_id, on)


def hook(plugin_id, member, handler, priority, filters_json):
    from app.exteraless.plugins.controller import PluginsController
    from app.exteraless.plugins.xposed import PyMethodHook
    if filters_json:
        filters = json.loads(filters_json)
        if filters.get("before") or filters.get("after"):
            raise NotImplementedError("hook filters are not available on ios")
    unhook = XposedBridge.hookMethod(member, PyMethodHook(plugin_id, handler, int(priority)))
    PluginsController.getInstance().addXposedHook(plugin_id, unhook)
    with _lock:
        _counter[0] += 1
        key = "hook%d" % _counter[0]
        _unhooks[key] = (unhook, plugin_id, _is_display(member))
        if _unhooks[key][2]:
            _display[plugin_id] = _display.get(plugin_id, 0) + 1
            first = _display[plugin_id] == 1
        else:
            first = False
    if first:
        _tell_app(plugin_id, True)
    return key


def hook_all(plugin_id, target, name, handler, priority, filters_json):
    declaring = target if isinstance(target, Class) else Class._of(target)
    methods = [method for method in declaring.getDeclaredMethods() if method.getName() == name]
    return json.dumps([hook(plugin_id, method, handler, priority, filters_json) for method in methods])


def unhook(key):
    with _lock:
        entry = _unhooks.pop(str(key), None)
        if entry is None:
            return
        last = False
        if entry[2]:
            _display[entry[1]] -= 1
            last = _display[entry[1]] == 0
    entry[0].unhook()
    if last:
        _tell_app(entry[1], False)
