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
    # channel is a broadcast channel or a supergroup (the android TL_channel), megagroup the supergroup; admin_rights is a record with delete_messages, None for a member
    _FIELDS = {"id": 0, "title": "", "creator": False, "channel": False, "megagroup": False, "broadcast": False, "admin_rights": None}


class TL_chatAdminRights(_Record):
    _FIELDS = {"delete_messages": False}


class PhotoSize(_Record):
    _FIELDS = {"type": "", "w": 0, "h": 0, "size": 0}


class Photo(_Record):
    _FIELDS = {"id": 0, "dc_id": 0, "sizes": ()}


class Document(_Record):
    _FIELDS = {"id": 0, "dc_id": 0, "mime_type": "", "file_name": "", "size": 0}


class Message(_Record):
    _FIELDS = {"id": 0, "message": "", "out": False, "post": False, "date": 0, "dialog_id": 0, "from_id": 0, "attachPath": ""}


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


class MessagesFilter(_Record):
    pass


class InputPeer(_Record):
    pass


class TL_inputPeerSelf(InputPeer):
    pass


class TL_inputPeerUser(InputPeer):
    _FIELDS = {"user_id": 0, "access_hash": 0}


class TL_inputPeerChat(InputPeer):
    _FIELDS = {"chat_id": 0}


class TL_inputPeerChannel(InputPeer):
    _FIELDS = {"channel_id": 0, "access_hash": 0}


class TL_inputPeerEmpty(InputPeer):
    pass


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


class TL_inputChannel(_Record):
    _FIELDS = {"channel_id": 0, "access_hash": 0}


class TL_inputMessagesFilterEmpty(MessagesFilter):
    pass


class TL_messages_getReplies(_Record):
    _FIELDS = {"peer": None, "msg_id": 0, "offset_id": 0, "offset_date": 0, "add_offset": 0, "limit": 0, "max_id": 0, "min_id": 0, "hash": 0}


class TL_channels_deleteMessages(_Record):
    _FIELDS = {"channel": None}

    def __init__(self, **fields):
        super().__init__(**fields)
        self.id = fields.get("id", ArrayList())


class TL_users_getSavedMusic(_Record):
    _FIELDS = {"id": None, "offset": 0, "limit": 0, "hash": 0}


class TL_inputMessagesFilterMusic(MessagesFilter):
    pass


class TL_messages_search(_Record):
    _FIELDS = {"flags": 0, "peer": None, "q": "", "from_id": None, "top_msg_id": 0, "filter": None, "min_date": 0, "max_date": 0, "offset_id": 0,
               "add_offset": 0, "limit": 0, "max_id": 0, "min_id": 0, "hash": 0}


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


class TL_messageService(Message):
    """a service message (a member joined, a pin, a title change): the cleaner tells it from a message with text because the server refuses some of them"""


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


# the names the android client gives the saved music request and its answer
TL_getSavedMusic = TL_users_getSavedMusic
TL_savedMusic = TL_users_savedMusic


class TL_boolTrue(_Record):
    pass


class TL_messages_affectedMessages(_Record):
    _FIELDS = {"pts": 0, "pts_count": 0}
