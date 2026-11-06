"""org.telegram.tgnet.TLRPC: the few records plugins read. fields are plain attributes"""

from java.lang import Object
from java.util import ArrayList


class _Record(Object):
    _FIELDS = {}

    def __init__(self, **fields):
        for name, default in self._FIELDS.items():
            setattr(self, name, default)
        for name, value in fields.items():
            setattr(self, name, value)


class User(_Record):
    _FIELDS = {"id": 0, "first_name": "", "last_name": "", "username": "", "self": False}


class Chat(_Record):
    _FIELDS = {"id": 0, "title": ""}


class PhotoSize(_Record):
    _FIELDS = {"type": "", "w": 0, "h": 0, "size": 0}


class Photo(_Record):
    _FIELDS = {"id": 0, "dc_id": 0, "sizes": ()}


class Document(_Record):
    _FIELDS = {"id": 0, "dc_id": 0, "mime_type": "", "file_name": "", "size": 0}


class Message(_Record):
    _FIELDS = {"id": 0, "message": "", "out": False, "date": 0, "dialog_id": 0, "from_id": 0, "attachPath": ""}


# python cannot send a request to telegram on ios, so these records are only what a plugin builds or tests against: a
# response never arrives as one of them. zwylib names them in the signatures of its request helpers when it loads
class Updates(_Record):
    pass


class TL_updates(Updates):
    _FIELDS = {"updates": (), "users": (), "chats": (), "date": 0, "seq": 0}


def __getattr__(name):
    """LAYER is the one of the app, which it asks the core for"""
    if name == "LAYER":
        from android import _ui
        return int(_ui.ask("app.protocol")["layer"])
    raise AttributeError("module %r has no attribute %r" % (__name__, name))


class TL_help_getNearestDc(_Record):
    """the request a plugin carries its initConnection on: it asks for nothing, the metadata is the point"""
    CONSTRUCTOR = 0x1FB33026

    def serializeToStream(self, stream):
        stream.writeInt32(self.CONSTRUCTOR)


class TL_error(_Record):
    _FIELDS = {"code": 0, "text": ""}


class MessageMedia(_Record):
    _FIELDS = {"photo": None, "document": None}


class messages_Messages(_Record):
    _FIELDS = {"messages": (), "chats": (), "users": (), "count": 0}


class TL_channels_channelParticipant(_Record):
    _FIELDS = {"participant": None, "chats": (), "users": ()}


# the requests a plugin may send (see requests.py) and the answers it gets: Saved Messages and the saved music of the profile. a list field
# is an ArrayList, as on android, so a plugin can add to it and walk it with size() and get()
class TLObject_(_Record):
    pass


class InputPeer(_Record):
    pass


class TL_inputPeerSelf(InputPeer):
    pass


class TL_inputPeerUser(InputPeer):
    _FIELDS = {"user_id": 0, "access_hash": 0}


class InputUser(_Record):
    pass


class TL_inputUserSelf(InputUser):
    pass


class TL_inputUser(InputUser):
    _FIELDS = {"user_id": 0, "access_hash": 0}


class InputDocument(_Record):
    pass


class TL_inputDocument(InputDocument):
    _FIELDS = {"id": 0, "access_hash": 0, "file_reference": b""}


class TL_messages_getHistory(_Record):
    _FIELDS = {"peer": None, "offset_id": 0, "offset_date": 0, "add_offset": 0, "limit": 0, "max_id": 0, "min_id": 0, "hash": 0}


class TL_users_getSavedMusic(_Record):
    _FIELDS = {"id": None, "offset": 0, "limit": 0, "hash": 0}


class TL_account_saveMusic(_Record):
    _FIELDS = {"flags": 0, "unsave": False, "id": None, "after_id": None}


class TL_messages_deleteMessages(_Record):
    _FIELDS = {"flags": 0, "revoke": False}

    def __init__(self, **fields):
        super().__init__(**fields)
        self.id = fields.get("id", ArrayList())


class TL_documentAttributeFilename(_Record):
    _FIELDS = {"file_name": ""}


class TL_documentAttributeAudio(_Record):
    _FIELDS = {"flags": 0, "voice": False, "duration": 0, "title": "", "performer": "", "waveform": b""}


class TL_document(Document):
    _FIELDS = dict(Document._FIELDS, access_hash=0, file_reference=b"", date=0)

    def __init__(self, **fields):
        super().__init__(**fields)
        self.attributes = fields.get("attributes", ArrayList())
        self.thumbs = fields.get("thumbs", ArrayList())


class TL_messageMediaDocument(MessageMedia):
    pass


class TL_message(Message):
    _FIELDS = dict(Message._FIELDS, media=None)


class TL_messages_messages(messages_Messages):
    def __init__(self, **fields):
        super().__init__(**fields)
        self.messages = fields.get("messages", ArrayList())


class TL_users_savedMusic(_Record):
    _FIELDS = {"count": 0}

    def __init__(self, **fields):
        super().__init__(**fields)
        self.documents = fields.get("documents", ArrayList())


class TL_boolTrue(_Record):
    pass


class TL_messages_affectedMessages(_Record):
    _FIELDS = {"pts": 0, "pts_count": 0}
