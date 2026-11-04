"""org.telegram.tgnet.TLRPC: the few records plugins read. fields are plain attributes"""

from java.lang import Object


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
    _FIELDS = {"id": 0, "message": "", "out": False, "date": 0, "dialog_id": 0, "from_id": 0}


# python cannot send a request to telegram on ios, so these records are only what a plugin builds or tests against: a
# response never arrives as one of them. zwylib names them in the signatures of its request helpers when it loads
class Updates(_Record):
    pass


class TL_updates(Updates):
    _FIELDS = {"updates": (), "users": (), "chats": (), "date": 0, "seq": 0}


class TL_error(_Record):
    _FIELDS = {"code": 0, "text": ""}


class MessageMedia(_Record):
    _FIELDS = {"photo": None, "document": None}


class messages_Messages(_Record):
    _FIELDS = {"messages": (), "chats": (), "users": (), "count": 0}


class TL_channels_channelParticipant(_Record):
    _FIELDS = {"participant": None, "chats": (), "users": ()}
