"""a plugin's audio file on its way to Saved Messages: the send hooks of the plugins see it first, as they see a document on android, and
may set the audio attribute (title, performer, duration) or stop it; then the app uploads it"""

import os

from android import _ui
from java.lang import Object
from java.util import ArrayList
from org.telegram.tgnet import TLRPC, requests


class SendParams(Object):
    """what a send hook gets for a document: the caption in message, the file in path, and the document the upload will make"""

    def __init__(self, **fields):
        self.message = ""
        self.peer = 0
        self.path = ""
        self.document = None
        self.replyToMsg = None
        self.replyQuote = None
        for name, value in fields.items():
            setattr(self, name, value)


def _audio_attribute(document):
    for attribute in document.attributes:
        if "Audio" in type(attribute).__name__:
            return attribute
    return None


def send_audio(path, caption, mime, dialog_id):
    from android_utils import log
    from extera_utils import plugin_loader
    me = int((_ui.ask("app.me") or {}).get("id") or 0)
    if not me or dialog_id != me:
        raise NotImplementedError("a plugin can send a file to Saved Messages only")
    if not mime.startswith("audio/"):
        raise NotImplementedError("only an audio file can be sent, not %s" % (mime or "a file of no type"))
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    document = TLRPC.TL_document(size=os.path.getsize(path), mime_type=mime)
    document.attributes.add(TLRPC.TL_documentAttributeFilename(file_name=os.path.basename(path)))
    params = SendParams(message=caption or "", peer=dialog_id, path=path, document=document)
    for plugin_id in list(plugin_loader.plugins):
        result = plugin_loader.call_send_message_hook(plugin_id, 0, params)
        if result is not None and str(result.strategy) == "CANCEL":
            log("send_audio: %s stopped the file" % plugin_id)
            return
    song = _audio_attribute(params.document)
    title = str(getattr(song, "title", "") or "") if song is not None else ""
    performer = str(getattr(song, "performer", "") or "") if song is not None else ""
    seconds = int(getattr(song, "duration", 0) or 0) if song is not None else 0

    def done(error):
        if error is not None:
            log("send_audio: the app could not send %s: %s" % (os.path.basename(path), error))

    requests.submit("send_audio", {"path": path, "mime": mime, "caption": str(params.message or ""), "title": title, "performer": performer,
                                   "duration_ms": max(0, seconds) * 1000}, done)
