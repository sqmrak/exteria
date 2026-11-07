"""entry points the app calls through exteria_pyhost_call. arguments and results are plain json values, so the c side
never touches a python object. the plugin loader of the exteraless sdk does the real work; this module only turns
its java facing shapes into dictionaries.

objects that exteraGram hands to hooks as java objects (send params, tl updates) reach a plugin as Record: attribute
access over a dictionary, with assignments kept so a hook can change them and return them in a HookResult"""

import functools
import json
import os
import sys

from android import _ui
from extera_utils import audit_gate, plugin_loader

# https from python: the sockets are the system's, the trust is the bundle shipped next to the stdlib, the one place a plugin's ssl context looks
_cacert = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cacert.pem")
if os.path.isfile(_cacert):
    os.environ.setdefault("SSL_CERT_FILE", _cacert)

# an .elyx archive that is a library (zwylib) is imported by its neighbours as a top level package, and the runtime links its
# files at <plugins>/ElyxPlugins/<id>. the folder is made now: a path that is missing when the first import looks at it is
# remembered as missing for good
def _elyx_libraries():
    from app.exteraless.plugins import PythonBridge
    root = os.path.join(str(PythonBridge.getPluginsDir()), "ElyxPlugins")
    os.makedirs(root, exist_ok=True)
    if root not in sys.path:
        sys.path.append(root)


_elyx_libraries()

# the gate lists the directories of the runtime lazily, on the first file a plugin opens. by then a plugin context is active, and on the
# phone /Applications is a symlink: realpath calls readlink, the gate refuses it for a plugin without the files permission, the
# error is swallowed and the list stays empty for good, so `import random` in a plugin fails. built here, outside any plugin, it is complete
audit_gate._runtime_paths()


def _flushed(function):
    """a view tree changes inside a plugin call and reaches uikit when the call ends"""

    @functools.wraps(function)
    def run(*args):
        try:
            return function(*args)
        finally:
            _ui.flush()

    return run


class Record:
    def __init__(self, data):
        for key, value in data.items():
            setattr(self, key, _wrap(value))

    def to_dict(self):
        return {key: _unwrap(value) for key, value in self.__dict__.items() if not key.startswith("_")}

    def __repr__(self):
        return "Record(%s)" % ", ".join("%s=%r" % item for item in self.to_dict().items())


def _wrap(value):
    if isinstance(value, dict):
        return Record(value)
    if isinstance(value, list):
        return [_wrap(item) for item in value]
    return value


def _unwrap(value):
    if isinstance(value, Record):
        return value.to_dict()
    if isinstance(value, list):
        return [_unwrap(item) for item in value]
    return value


def metadata(path):
    return json.loads(plugin_loader.read_metadata_json(path))


def capabilities(path):
    return json.loads(plugin_loader.scan_capabilities_json(path))


def _controller():
    from app.exteraless.plugins.controller import PluginsController
    return PluginsController.getInstance()


@_flushed
def load(path, plugin_id):
    # through the controller, so a library that hooks setPluginEnabled hears of every plugin the host starts
    controller = _controller()
    controller.getEngines().get("python").loadPlugin(plugin_id, path)
    result = json.loads(controller.setPluginEnabled(plugin_id, True))
    if not result.get("ok"):
        import exteria_diagnose
        result["why"] = exteria_diagnose.explain(path, result.get("error"))
    return result


@_flushed
def unload(plugin_id):
    _controller().setPluginEnabled(plugin_id, False)
    from app.exteraless.plugins import forget_plugin
    forget_plugin(plugin_id)
    if not plugin_loader.plugins:
        # a plugin that crashed in its unload hook leaves its views on the overlay
        from android.app import activity
        from org.telegram.ui import reset_pages
        activity()._decor.removeAllViews()
        reset_pages()


@_flushed
def app_event(plugin_id, event):
    plugin_loader.call_app_event(plugin_id, event)


def _outcome(result, field):
    if result is None:
        return {"strategy": "DEFAULT"}
    value = result.value
    return {"strategy": str(result.strategy), field: _unwrap(value) if value is not None else None}


class _SendParams(Record):
    """the params of a send hook as exteraGram gives them: replyToMsg is a MessageObject (None without a reply) and replyQuote
    the ReplyQuote the reply carries (None for a plain reply). a hook that sets either, or changes them, is heard by the app"""

    replyToMsg = None
    replyQuote = None


def _send_params(params):
    from org.telegram.messenger import MessageObject
    from org.telegram.tgnet import TLRPC
    from org.telegram.ui import ChatActivity
    record = _SendParams({key: params[key] for key in ("message", "peer") if key in params})
    reply = int(params.get("replyToMsg") or 0)
    if reply:
        owner = TLRPC.Message(id=reply, message=str(params.get("replyText", "")), dialog_id=int(params.get("peer", 0)))
        record.replyToMsg = MessageObject(owner, owner.dialog_id)
    if params.get("quote"):
        record.replyQuote = ChatActivity.ReplyQuote(record.replyToMsg, str(params["quote"]), max(0, int(params.get("quoteOffset", 0))))
    return record


def _send_outcome(result):
    outcome = _outcome(result, "params")
    changed = outcome.get("params")
    if isinstance(changed, dict):
        if "replyToMsg" in changed:
            reply = changed["replyToMsg"]
            changed["replyToMsg"] = int(reply.getId()) if hasattr(reply, "getId") else int(reply or 0)
        quote = changed.get("replyQuote", False)
        if quote is not False:
            changed["replyQuote"] = None if quote is None else {"text": str(quote.text), "offset": int(quote.start)}
    return outcome


@_flushed
def send_message_hook(plugin_id, account, params):
    return _send_outcome(plugin_loader.call_send_message_hook(plugin_id, account, _send_params(params)))


@_flushed
def update_hook(plugin_id, account, name, update):
    return _outcome(plugin_loader.call_update_hook(plugin_id, account, name, Record(update)), "update")


# the key of a row that stands for a UItem.asSlideView of the plugin; the page has no slider with stops of text, so the row is a list of choices
_SLIDE_KEY = "__slide:"


def _slide_rows(plugin_id, items):
    """a Custom row that holds a slide view becomes a row of choices. the header above it, if there is one, is its title, as the rows of a list
    of choices have theirs. the choice goes back to the callback of the view and is not stored here: the plugin keeps its own settings"""
    record = plugin_loader.plugins.get(plugin_id)
    shown = []
    for item in items:
        view = getattr(record.custom_views.get(item.get("view_id")), "item", None) if record and item.get("type") == "custom" else None
        if getattr(view, "kind", None) != "slide":
            shown.append(item)
            continue
        row = {"type": "selector", "key": _SLIDE_KEY + item["view_id"], "text": "", "items": list(view.choices), "value": view.chosen}
        if shown and shown[-1].get("type") == "header":
            row["text"] = shown.pop()["text"]
        shown.append(row)
    return shown


def settings(plugin_id):
    # the loader answers "null" for a plugin without a settings page, which is no rows and not a failure
    return _slide_rows(plugin_id, json.loads(plugin_loader.get_settings_json(plugin_id)) or [])


@_flushed
def setting_changed(plugin_id, key, value_json):
    if key.startswith(_SLIDE_KEY):
        record = plugin_loader.plugins.get(plugin_id)
        view = getattr(record.custom_views.get(key[len(_SLIDE_KEY):]), "item", None) if record else None
        choice = json.loads(value_json)
        if getattr(view, "kind", None) != "slide" or not isinstance(choice, int) or not 0 <= choice < len(view.choices):
            raise ValueError("%s is not a choice of a row of this plugin" % (value_json,))
        with plugin_loader.plugin_context(plugin_id):
            view.whenChose.run(choice)
        return
    plugin_loader.notify_setting_changed(plugin_id, key, value_json)


@_flushed
def setting_click(plugin_id, callback_id):
    plugin_loader.dispatch_setting_click(plugin_id, callback_id)


@_flushed
def menu_click(plugin_id, item_id, context):
    from app.exteraless import plugins as bridge
    shown = context.get("message") if isinstance(context, dict) else None
    if isinstance(shown, dict):
        # the item of a message menu gets the message as the android app gives it, a MessageObject over the raw message
        from org.telegram.messenger import MessageObject
        from org.telegram.tgnet import TLRPC
        owner = TLRPC.Message(id=int(shown.get("id", 0)), message=str(shown.get("text", "")), out=bool(shown.get("out")),
                              dialog_id=int(shown.get("dialog", 0)))
        context = dict(context, message=MessageObject(owner, owner.dialog_id))
    bridge.menu_click(plugin_id, item_id, context)
    from app.exteraless.plugins import display_hooks_active
    if display_hooks_active():
        # an item that resets or changes what a display hook says (an edit made on the phone only) shows at once
        _ui.ask("chat.rebuild")


@_flushed
def run_token(token):
    from app.exteraless import plugins as bridge
    bridge.run_token(token)


@_flushed
def touch(view_id, action, raw_x, raw_y, now):
    from android import view
    return bool(view.dispatch_touch(view_id, action, raw_x, raw_y, now))


@_flushed
def sensor(x, y, z, timestamp):
    from android.hardware import SensorManager
    SensorManager.instance()._deliver(x, y, z, timestamp)


@_flushed
def new_messages(account, dialog, messages):
    """messages the app received: [{"id", "text", "out"}]. plugins hear them as didReceiveNewMessages"""
    from java.util import ArrayList
    from org.telegram.messenger import MessageObject, NotificationCenter
    from org.telegram.tgnet import TLRPC
    objects = ArrayList()
    for item in messages:
        owner = TLRPC.Message(id=item.get("id", 0), message=item.get("text", ""), out=bool(item.get("out")),
                              dialog_id=dialog)
        objects.append(MessageObject(owner, dialog))
    NotificationCenter.getInstance(account).postNotificationName(NotificationCenter.didReceiveNewMessages, dialog, objects)


@_flushed
def screen_changed():
    """the window turned or resized"""
    from android.app import activity
    _ui.refresh_screen()
    activity()._decor._request_layout()


@_flushed
def sheet_closed(sheet_id):
    """the person closed a sheet a plugin opened"""
    import exteria_sheet
    exteria_sheet._closed(sheet_id)


@_flushed
def sheet_ended(sheet_id):
    """the surface of a sheet stopped running by itself"""
    import exteria_sheet
    exteria_sheet._ended(sheet_id)


@_flushed
def language_changed():
    """the person chose another language of the app"""
    from org.telegram.messenger import LocaleController
    LocaleController.getInstance().applyLanguage(str(_ui.ask("app.language")["value"]))


_display_cell = []


@_flushed
def display_messages(chat, items):
    """the messages the app is about to lay out, [{"id", "text", "out"}]: what the hooks on ChatMessageCell.setMessageContent make
    of each. the answer holds the text of the messages a hook changed, by id"""
    from android.app import activity
    from org.telegram.messenger import MessageObject
    from org.telegram.tgnet import TLRPC
    from org.telegram.ui.Cells import ChatMessageCell
    if not _display_cell:
        _display_cell.append(ChatMessageCell(activity()))
    changed = {}
    for item in items:
        owner = TLRPC.Message(id=int(item["id"]), message=str(item["text"]), out=bool(item.get("out")), dialog_id=int(chat))
        message = MessageObject(owner, int(chat))
        _display_cell[0].setMessageContent(message)
        if message.messageText is not None and str(message.messageText) != item["text"]:
            changed[str(item["id"])] = str(message.messageText)
    return changed


@_flushed
def pick_result(token, chosen):
    """the person chose chats in the picker of the app: chosen is [{id, kind}]"""
    from org.telegram.ui import _pick_result
    _pick_result(token, chosen)


@_flushed
def music_play(index):
    """a song is about to start in the music player: True when a plugin that hooks playMessage has started it"""
    from org.telegram.messenger.music import play_routed
    return play_routed(index)


@_flushed
def music_pause():
    """a song is about to be paused in the music player: True when a plugin that hooks pauseMessage has paused it"""
    from org.telegram.messenger.music import pause_routed
    return pause_routed()


@_flushed
def pick_cancelled(token):
    """the person went back from the picker of the app without choosing"""
    from org.telegram.ui import _pick_cancelled
    _pick_cancelled(token)


@_flushed
def time_picked(token, chosen):
    """the person answered the wheel of a date or a time a plugin asked for: chosen is [epoch, year, month, day, hour, minute], or None after Cancel"""
    from android.app import _time_picked
    _time_picked(token, chosen)


@_flushed
def story_page():
    """the story screen holds a picture: the words of the button a plugin put beside publish, {"title"}, or None"""
    from org.telegram.ui.Stories.recorder import story_page
    return story_page()


@_flushed
def story_schedule(long_press):
    """the button of a plugin beside publish was tapped, or publish was held"""
    from org.telegram.ui.Stories.recorder import story_schedule
    story_schedule(bool(long_press))


@_flushed
def story_intercept(path, caption, token):
    """a story is about to go up: the plugins that hook StoriesController.uploadStory may hold it back. {"taken", "keep"}"""
    from org.telegram.ui.Stories.recorder import story_intercept
    return story_intercept(str(path), str(caption), int(token))


@_flushed
def alert_result(token, index, text=""):
    """the person answered a dialog a plugin showed; text is what a field in it held"""
    from org.telegram.ui.ActionBar import _alert_result
    from app.exteraless.plugins import display_hooks_active
    _alert_result(token, index, text)
    if display_hooks_active():
        # a hook that shows other words for a message may have been told something by the answer: the chat is laid out again
        _ui.ask("chat.rebuild")


@_flushed
def fragment_event(page, event, width, height):
    """a page of the app that plugins hook was built ("create"), came on screen ("resume"), went away ("pause") or changed its size
    ("layout"); width and height are the size of its layer in points. only the settings tab is such a page"""
    if page != "settings":
        raise ValueError("no such page: %r" % (page,))
    from org.telegram.ui import SettingsActivity
    SettingsActivity.instance()._event(str(event), int(width), int(height))


@_flushed
def activity_result(request_code, result_code, address):
    """the picker a plugin opened with startActivityForResult answered: result_code is Activity.RESULT_OK or RESULT_CANCELED, address the
    file: address of the chosen picture, empty when the person cancelled. the hooks on LaunchActivity.onActivityResult take it from here"""
    from android.content import Intent
    from android.net import Uri
    from org.telegram.ui import LaunchActivity
    data = Intent().setData(Uri.parse(address)) if address else None
    LaunchActivity.instance.onActivityResult(int(request_code), int(result_code), data)


@_flushed
def account_result(token, error, payload):
    """the app answered a request a plugin sent with send_request (see org/telegram/tgnet/requests.py): error is the name of the failure or None"""
    from org.telegram.tgnet import requests
    requests.account_result(token, error, payload)
