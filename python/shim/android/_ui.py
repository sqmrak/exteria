"""the link between the python view tree and the uikit views of the app.

every change a plugin makes to a view is queued as an operation and sent in one request when the entry point that
called python returns (see flush). the app applies them on the main thread. nothing here draws: layout is computed in
python (android semantics, so getWidth and getLocationInWindow answer as plugins expect), uikit only receives frames.

operations, as json lists:
  ["new", id, kind]            kind: view, text, edit, image, scroll
  ["set", id, {property: v}]   x y w h tx ty sx sy rot alpha vis touch, text color size bold gravity pad, bg, scale
  ["add", parent, child, index]
  ["rm", child]
  ["img", id, w, h, base64 rgba]
  ["anim", id, {property: v}, duration_ms, delay_ms, curve]
  ["stop", id]"""

import json

import _exteria
import _mainthread

ROOT = 0

_ops = []
_last_set = {}
_views = {}
_next_id = [0]
_flush_hooks = []


def new_id():
    _next_id[0] += 1
    return _next_id[0]


def register(view_id, view):
    _views[view_id] = view


def lookup(view_id):
    return _views.get(view_id)


def forget(view_id):
    _views.pop(view_id, None)


def emit(*op):
    _last_set.clear()
    _ops.append(list(op))


def set_props(view_id, props):
    """sets coalesce while nothing structural is queued between them"""
    last = _last_set.get(view_id)
    if last is not None:
        last.update(props)
        return
    entry = dict(props)
    _ops.append(["set", view_id, entry])
    _last_set[view_id] = entry


def on_flush(hook):
    _flush_hooks.append(hook)


def flush():
    for hook in list(_flush_hooks):
        hook()
    if not _ops:
        return
    batch = list(_ops)
    del _ops[:]
    _last_set.clear()
    _exteria.service("ui.apply", json.dumps({"ops": batch}))


def ask(name, **payload):
    return _mainthread.call(lambda: json.loads(_exteria.service(name, json.dumps(payload)) or "null"))


_screen = {}


def screen():
    """width, height, status bar and bottom inset of the window, in points"""
    if not _screen:
        _screen.update(ask("ui.screen"))
    return _screen


def refresh_screen():
    _screen.clear()
    return screen()


_text_cache = {}


def measure_text(text, size, bold, max_width):
    key = (text, size, bold, max_width)
    hit = _text_cache.get(key)
    if hit is None:
        reply = ask("ui.measure", text=text, size=size, bold=bold, width=max_width)
        hit = (int(reply["w"]), int(reply["h"]))
        if len(_text_cache) > 512:
            _text_cache.clear()
        _text_cache[key] = hit
    return hit
