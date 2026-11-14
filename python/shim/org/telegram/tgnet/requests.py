"""send_request for the requests a plugin may make: read Saved Messages, find the newest or the oldest song of a chat, read the saved music of a profile and change
the one of the person, delete messages of Saved Messages, and tell the server another device model, system version and app version. python cannot send a request to telegram on ios and the core keeps the tl layer to itself, so each of the request classes below is
turned into one narrow operation of the app (exteria_plugin_account.m) and its answer into the records of the android client. any other request
is refused by name, so a plugin that needs more fails where it asks and does not hang waiting for an answer that never comes

an operation names the account it works on by the signed in person; a chat or a user is named by its id and must be in the chat list of the app, which the app checks"""

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


def _dialog_of(peer, what):
    """the id of the android client for the chat a peer names: the person's own id for Saved Messages, the user id, or the plain id of a group or a channel with a minus.
    the app finds the access hash of a chat in its list, so only the id travels"""
    if isinstance(peer, (TLRPC.TL_inputPeerSelf, TLRPC.TL_inputUserSelf)):
        return _me()
    if isinstance(peer, (TLRPC.TL_inputPeerUser, TLRPC.TL_inputUser)):
        return int(peer.user_id)
    if isinstance(peer, TLRPC.TL_inputPeerChat):
        return -int(peer.chat_id)
    if isinstance(peer, TLRPC.TL_inputPeerChannel):
        return -int(peer.channel_id)
    raise NotImplementedError("%s needs a chat the app knows, not %s" % (what, type(peer).__name__))


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


def _message_rows(payload, dialog):
    """the messages of a page of the open chat as the records of the android client: a service message is its own class, since the server refuses some of them"""
    answer = TLRPC.TL_messages_messages()
    for row in payload.get("messages", ()):
        kind = TLRPC.TL_messageService if row.get("service") else TLRPC.TL_message
        answer.messages.add(kind(id=int(row["id"]), date=int(row.get("date", 0)), out=bool(row.get("out")), post=bool(row.get("post")), dialog_id=dialog))
    return answer


def _page(mode, peer, topic, offset_id, limit, what):
    """a page of the open chat, newest first: the app lists the chat it has open (the id must be its own), the whole chat or the messages of the account"""
    if not 1 <= limit <= HISTORY_LIMIT_MAX:
        raise ValueError("%s takes a limit of 1 to %d, not %d" % (what, HISTORY_LIMIT_MAX, limit))
    if offset_id < 0:
        raise ValueError("%s takes an offset_id of 0 or more" % what)
    dialog = _dialog_of(peer, what)
    return "chat_page", {"dialog": dialog, "topic": int(topic), "mode": mode, "offset_id": int(offset_id), "limit": int(limit)}, lambda payload: _message_rows(payload, dialog)


def _history(request):
    limit = int(request.limit)
    if request.offset_date or request.add_offset or request.max_id or request.min_id:
        raise NotImplementedError("messages.getHistory pages by offset_id only: offset_date, add_offset, max_id and min_id are 0")
    me = _me()
    saved = isinstance(request.peer, TLRPC.TL_inputPeerSelf) or (isinstance(request.peer, TLRPC.TL_inputPeerUser) and me and int(request.peer.user_id) == me)
    if saved and not request.offset_id:
        # the newest messages of Saved Messages need no open chat, and carry the documents of the songs a plugin reads
        if not 1 <= limit <= HISTORY_LIMIT_MAX:
            raise ValueError("messages.getHistory takes a limit of 1 to %d, not %d" % (HISTORY_LIMIT_MAX, limit))

        def parse(payload):
            answer = TLRPC.TL_messages_messages()
            for row in payload.get("messages", ()):
                message = TLRPC.TL_message(id=int(row["id"]), message=str(row.get("text", "")), date=int(row.get("date", 0)), out=True)
                if row.get("doc"):
                    message.media = TLRPC.TL_messageMediaDocument(document=_document_record(row["doc"]))
                answer.messages.add(message)
            return answer

        return "history", {"limit": limit}, parse
    return _page("all", request.peer, 0, int(request.offset_id), limit, "messages.getHistory")


def _replies(request):
    if request.offset_date or request.add_offset or request.max_id or request.min_id:
        raise NotImplementedError("messages.getReplies pages by offset_id only: offset_date, add_offset, max_id and min_id are 0")
    if int(request.msg_id) <= 0:
        raise ValueError("messages.getReplies needs the message that opens the topic")
    return _page("all", request.peer, int(request.msg_id), int(request.offset_id), int(request.limit), "messages.getReplies")


def _saved_music(request):
    owner = _dialog_of(request.id, "users.getSavedMusic")
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

    # the app gives the songs a page at a time, and the plugin stops at the first page shorter than the limit it asked for. the profile of the person is the
    # one the app reads when no user is named; the profile of another user must be in the chat list
    fields = {"offset": offset}
    if owner != _me():
        fields["user"] = owner
    return "saved_music", fields, parse, limit


def _own_messages(request):
    """messages.search with no filter and the account as sender: the messages the account wrote in the open chat, or in one topic of it"""
    if not isinstance(request.from_id, TLRPC.TL_inputPeerSelf):
        raise NotImplementedError("messages.search with no filter takes the account as the sender (from_id inputPeerSelf)")
    if request.q or request.min_date or request.max_date or request.max_id or request.min_id or request.add_offset:
        raise NotImplementedError("messages.search for the messages of the account takes no text, dates, id bounds or add_offset")
    return _page("mine", request.peer, int(request.top_msg_id or 0), int(request.offset_id), int(request.limit), "messages.search")


def _search(request):
    """messages.search for the newest song of a chat, or the oldest one (offset_id 1 with add_offset -1, how a client asks for the first message). a page of one
    message, the filter music and no text: the app has the one search of the shared audio of a chat"""
    if isinstance(request.filter, TLRPC.TL_inputMessagesFilterEmpty):
        return _own_messages(request)
    peer = _dialog_of(request.peer, "messages.search")
    if not isinstance(request.filter, TLRPC.TL_inputMessagesFilterMusic):
        raise NotImplementedError("messages.search takes the music filter or the empty one with the account as sender")
    if request.q or request.from_id is not None or request.top_msg_id or request.min_date or request.max_date or request.max_id or request.min_id:
        raise NotImplementedError("messages.search takes no text, sender, topic, dates or id bounds")
    if int(request.limit) != 1:
        raise NotImplementedError("messages.search returns one message, not a limit of %d" % int(request.limit))
    offset_id, add_offset = int(request.offset_id), int(request.add_offset)
    if (offset_id, add_offset) == (0, 0):
        first = False
    elif (offset_id, add_offset) == (1, -1):
        first = True
    else:
        raise NotImplementedError("messages.search starts at the newest song (offset_id 0, add_offset 0) or the oldest (offset_id 1, add_offset -1)")

    def parse(payload):
        answer = TLRPC.TL_messages_messages()
        for row in payload.get("messages", ()):
            message = TLRPC.TL_message(id=int(row["id"]), message=str(row.get("text", "")), date=int(row.get("date", 0)), dialog_id=peer)
            message.media = TLRPC.TL_messageMediaDocument(document=_document_record(row["doc"]))
            answer.messages.add(message)
        answer.count = answer.messages.size()
        return answer

    return "chat_music", {"dialog": peer, "first": first}, parse


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


def _delete_ids(request):
    ids = [int(one) for one in request.id]
    if not ids or len(ids) > 100 or any(one <= 0 for one in ids):
        raise ValueError("a delete request takes 1 to 100 message ids")
    return ids


def _affected(ids):
    # the app says how many it asked for; the server's pts is the core's own
    return lambda payload: TLRPC.TL_messages_affectedMessages(pts=0, pts_count=int(payload.get("count", len(ids))))


def _delete(request):
    ids = _delete_ids(request)
    return "delete", {"ids": ids, "revoke": bool(request.revoke)}, _affected(ids)


def _delete_in_channel(request):
    """channels.deleteMessages: the ids belong to the channel, which must be the chat that is open"""
    ids = _delete_ids(request)
    channel = request.channel
    if not isinstance(channel, TLRPC.TL_inputChannel) or int(channel.channel_id) <= 0:
        raise NotImplementedError("channels.deleteMessages needs the channel of the chat that is open")
    return "delete", {"ids": ids, "channel": -int(channel.channel_id)}, _affected(ids)


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
    TLRPC.TL_messages_search: _search,
    TLRPC.TL_messages_getReplies: _replies,
    TLRPC.TL_channels_deleteMessages: _delete_in_channel,
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
