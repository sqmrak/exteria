"""send_request for the requests a plugin may make: read Saved Messages, read and change the saved music of the profile, delete messages of Saved
Messages, and tell the server another device model, system version and app version. python cannot send a request to telegram on ios and the core keeps the tl layer to itself, so each of the request classes below is
turned into one narrow operation of the app (exteria_plugin_account.m) and its answer into the records of the android client. any other request
is refused by name, so a plugin that needs more fails where it asks and does not hang waiting for an answer that never comes

an operation names the account it works on by the signed in person only; a request that names another chat or user is refused"""

import struct
import threading

from android import _ui
from android.os import Build
from java.lang import Integer
from java.util import ArrayList
from org.telegram.tgnet import SerializedData, TLObject, TLRPC

HISTORY_LIMIT_MAX = 100
MUSIC_PAGE = 30
MUSIC_LIMIT_MAX = 500

_lock = threading.Lock()
_pending = {}
_next = [0]

_ERROR_CODES = (("FLOOD_WAIT", 420), ("AUTH_KEY", 401), ("SESSION", 401), ("INTERNAL", 500), ("TIMEOUT", 500))


def _error(text):
    name = str(text)
    code = next((code for prefix, code in _ERROR_CODES if name.startswith(prefix)), 400)
    return TLRPC.TL_error(code=code, text=name)


def _me():
    return int((_ui.ask("app.me") or {}).get("id") or 0)


def _require_myself(peer, what):
    """Saved Messages and the profile of the signed in person: the self peer, or the user of the person's own id"""
    me = _me()
    if isinstance(peer, (TLRPC.TL_inputPeerSelf, TLRPC.TL_inputUserSelf)):
        return
    if isinstance(peer, (TLRPC.TL_inputPeerUser, TLRPC.TL_inputUser)) and me and int(peer.user_id) == me:
        return
    raise NotImplementedError("%s works on the signed in person only" % what)


def _document_record(doc):
    record = TLRPC.TL_document(id=int(doc["id"]), access_hash=int(doc["access_hash"]), dc_id=int(doc.get("dc", 0)), size=int(doc.get("size", 0)),
                               mime_type=str(doc.get("mime", "")), file_reference=bytes.fromhex(doc.get("file_ref", "")))
    if doc.get("name"):
        record.attributes.add(TLRPC.TL_documentAttributeFilename(file_name=str(doc["name"])))
    if doc.get("title") or doc.get("performer") or doc.get("duration"):
        flags = (1 if doc.get("title") else 0) | (2 if doc.get("performer") else 0)
        record.attributes.add(TLRPC.TL_documentAttributeAudio(flags=flags, duration=int(doc.get("duration", 0)), title=str(doc.get("title", "")),
                                                              performer=str(doc.get("performer", ""))))
    if doc.get("thumb"):
        # the app only says that the server made a thumbnail, which is what a plugin asks
        record.thumbs.add(TLRPC.PhotoSize(type="m"))
    return record


def _history(request):
    _require_myself(request.peer, "messages.getHistory")
    limit = int(request.limit)
    if not 1 <= limit <= HISTORY_LIMIT_MAX:
        raise ValueError("messages.getHistory takes a limit of 1 to %d, not %d" % (HISTORY_LIMIT_MAX, limit))
    if request.offset_id or request.offset_date or request.add_offset or request.max_id or request.min_id:
        raise NotImplementedError("messages.getHistory reads the newest messages only: offset_id, offset_date, add_offset, max_id and min_id are 0")

    def parse(payload):
        answer = TLRPC.TL_messages_messages()
        for row in payload.get("messages", ()):
            message = TLRPC.TL_message(id=int(row["id"]), message=str(row.get("text", "")), date=int(row.get("date", 0)), out=True)
            if row.get("doc"):
                message.media = TLRPC.TL_messageMediaDocument(document=_document_record(row["doc"]))
            answer.messages.add(message)
        return answer

    return "history", {"limit": limit}, parse


def _saved_music(request):
    _require_myself(request.id, "users.getSavedMusic")
    limit = int(request.limit)
    if not 1 <= limit <= MUSIC_LIMIT_MAX:
        raise ValueError("users.getSavedMusic takes a limit of 1 to %d, not %d" % (MUSIC_LIMIT_MAX, limit))
    offset = int(request.offset)
    if offset < 0:
        raise ValueError("users.getSavedMusic takes an offset of 0 or more")

    def parse(payload):
        answer = TLRPC.TL_users_savedMusic(count=int(payload.get("count", 0)))
        for doc in payload.get("documents", ()):
            answer.documents.add(_document_record(doc))
        return answer

    # the app gives the songs a page at a time, and the plugin stops at the first page shorter than the limit it asked for
    return "saved_music", {"offset": offset}, parse, limit


def _document_of(input_document):
    if not isinstance(input_document, TLRPC.TL_inputDocument):
        raise NotImplementedError("account.saveMusic takes an inputDocument")
    return {"id": int(input_document.id), "access_hash": int(input_document.access_hash), "dc": 0,
            "file_ref": bytes(input_document.file_reference or b"").hex()}


def _save_music(request):
    if request.after_id is not None:
        raise NotImplementedError("account.saveMusic cannot put a song after another one (after_id)")
    unsave = bool(request.unsave) or bool(int(request.flags) & 1)
    return "save_music", {"doc": _document_of(request.id), "unsave": unsave}, lambda payload: TLRPC.TL_boolTrue()


def _delete(request):
    ids = [int(one) for one in request.id]
    if not ids or len(ids) > 100 or any(one <= 0 for one in ids):
        raise ValueError("messages.deleteMessages takes 1 to 100 message ids")
    return "delete", {"ids": ids, "revoke": bool(request.revoke)}, lambda payload: TLRPC.TL_messages_affectedMessages()


_INVOKE_WITH_LAYER = 0xDA9B0D0D
_INIT_CONNECTION = 0xC1CD5EA9


class _Wire:
    """the bytes a record wrote, read back field by field; a read past the end or a left over byte is a request the app does not know"""

    def __init__(self, data):
        self._data = data
        self._at = 0

    def _take(self, size):
        if self._at + size > len(self._data):
            raise NotImplementedError("the request ends before its fields do")
        chunk = self._data[self._at:self._at + size]
        self._at += size
        return chunk

    def u32(self):
        return struct.unpack("<I", self._take(4))[0]

    def i32(self):
        return struct.unpack("<i", self._take(4))[0]

    def string(self):
        first = self._take(1)[0]
        if first < 254:
            size, used = first, 1
        elif first == 254:
            size, used = int.from_bytes(self._take(3), "little"), 4
        else:
            raise NotImplementedError("the request has a string with a length byte of 255")
        text = self._take(size)
        self._take(-(used + size) % 4)
        return text.decode("utf-8")

    def end(self):
        if self._at != len(self._data):
            raise NotImplementedError("the request has more fields than the app knows")


def _device_profile(request):
    """invokeWithLayer(initConnection(help.getNearestDc)), the way a plugin tells the server what device this session is. the record is serialized and the
    bytes are read back, so the request is checked as it would be on the wire and not as the plugin says it is. only the three device texts are taken:
    the api id, the language fields and the lang pack are the ones of the app, which a plugin cannot change"""
    stream = SerializedData()
    request.serializeToStream(stream)
    wire = _Wire(stream.getBytes())
    if wire.u32() != _INVOKE_WITH_LAYER:
        raise NotImplementedError("the request is not invokeWithLayer")
    layer = wire.i32()
    if wire.u32() != _INIT_CONNECTION:
        raise NotImplementedError("invokeWithLayer carries a query other than initConnection")
    if wire.i32() != 0:
        raise NotImplementedError("initConnection with a proxy or params is not supported")
    wire.i32()
    model, system, app = wire.string(), wire.string(), wire.string()
    for _ in range(3):
        wire.string()
    if wire.u32() != TLRPC.TL_help_getNearestDc.CONSTRUCTOR:
        raise NotImplementedError("initConnection carries a query other than help.getNearestDc")
    wire.end()
    if layer != TLRPC.LAYER:
        raise NotImplementedError("the layer %d is not the one of the app, %d" % (layer, TLRPC.LAYER))
    # the stand-in Build is what this device is for a plugin, so a plugin that gives the real profile back sends exactly that
    if model == str(Build.MANUFACTURER) + str(Build.MODEL):
        return "device_profile", {"restore": True}, lambda payload: TLRPC.TL_boolTrue()
    if not model or not system:
        raise ValueError("a device model and a system version are not empty")
    return "device_profile", {"model": model, "system": system, "app": app}, lambda payload: TLRPC.TL_boolTrue()


_HANDLERS = {
    TLRPC.TL_messages_getHistory: _history,
    TLRPC.TL_users_getSavedMusic: _saved_music,
    TLRPC.TL_account_saveMusic: _save_music,
    TLRPC.TL_messages_deleteMessages: _delete,
}


def _start(token, operation, payload):
    _ui.ask("account." + operation, token=token, **payload)


def send(request, callback):
    """the id of the request. callback(response, error) runs once, on the main thread, when the app has the answer"""
    handler = _HANDLERS.get(type(request))
    if handler is None and isinstance(request, TLObject) and callable(getattr(request, "serializeToStream", None)):
        handler = _device_profile
    if handler is None:
        raise NotImplementedError("the request %s cannot be sent from a plugin on ios, only %s can" % (
            type(request).__name__, ", ".join(sorted(cls.__name__ for cls in _HANDLERS))))
    planned = handler(request)
    operation, payload, parse = planned[:3]
    wanted = planned[3] if len(planned) > 3 else 0
    with _lock:
        _next[0] += 1
        token = _next[0]
        _pending[token] = {"parse": parse, "callback": callback, "wanted": wanted, "payload": dict(payload), "operation": operation, "got": None}
    try:
        _start(token, operation, payload)
    except BaseException:
        with _lock:
            _pending.pop(token, None)
        raise
    return token


def submit(operation, payload, done):
    """an operation of the app that is not a request of the android client (sending a song): done(error) runs once with the name of the failure or None"""
    with _lock:
        _next[0] += 1
        token = _next[0]
        _pending[token] = {"parse": lambda answer: answer, "callback": lambda answer, error: done(None if error is None else error.text), "wanted": 0,
                           "payload": dict(payload), "operation": operation, "got": None}
    try:
        _start(token, operation, payload)
    except BaseException:
        with _lock:
            _pending.pop(token, None)
        raise


def account_result(token, error, payload):
    """the app answered request token: error is the name of the failure or None"""
    with _lock:
        entry = _pending.get(int(token))
    if entry is None:
        return
    if error is None and entry["wanted"]:
        # a list that is not full yet asks for the next page, as the one request a plugin made
        got = entry["got"] = (entry["got"] or {"documents": [], "count": 0})
        got["documents"].extend(payload.get("documents", ()))
        got["count"] = int(payload.get("count", 0))
        if payload.get("documents") and len(got["documents"]) < got["count"] and len(got["documents"]) < entry["wanted"]:
            entry["payload"]["offset"] = int(entry["payload"]["offset"]) + len(payload["documents"])
            try:
                _start(int(token), entry["operation"], entry["payload"])
                return
            except Exception as failure:
                error = "INTERNAL: %s" % failure
        else:
            payload = {"documents": got["documents"][:entry["wanted"]], "count": got["count"]}
    with _lock:
        _pending.pop(int(token), None)
    from android_utils import safe_call
    if error is not None:
        safe_call(entry["callback"], None, _error(error))
        return
    safe_call(entry["callback"], entry["parse"](payload), None)
