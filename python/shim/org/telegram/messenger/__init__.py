"""org.telegram.messenger: the helpers of the android app that plugins call, answered by the host app"""

from android import _ui
from java.lang import Object
from java.util import ArrayList
from org.telegram.messenger.music import MediaController, SharedConfig  # noqa: F401
from org.telegram.tgnet import TLRPC


class _ScreenMeta(type):
    @property
    def statusBarHeight(cls):
        return int(_ui.screen().get("top", 0))

    @property
    def navigationBarHeight(cls):
        return int(_ui.screen().get("bottom", 0))

    @property
    def displaySize(cls):
        from android.graphics import Point
        screen = _ui.screen()
        return Point(int(screen["w"]), int(screen["h"]))

    @property
    def density(cls):
        return 1.0


class AndroidUtilities(metaclass=_ScreenMeta):
    # one dp is one point on ios, so a size in dp is already a size in points
    @staticmethod
    def dp(value):
        return int(round(float(value)))

    @staticmethod
    def dpf2(value):
        return float(value)

    @staticmethod
    def bold():
        from android.graphics import Typeface
        return Typeface.DEFAULT_BOLD

    @staticmethod
    def isTablet():
        return bool(_ui.screen().get("tablet", False))

    @staticmethod
    def runOnUIThread(runnable, delay=0):
        from android.os import Handler
        Handler().postDelayed(runnable, delay)

    @staticmethod
    def cancelRunOnUIThread(runnable):
        from android.os import Handler
        Handler().removeCallbacks(runnable)


class _LoaderMeta(type):
    @property
    def applicationContext(cls):
        from android.app import activity
        return activity()


class ApplicationLoader(metaclass=_LoaderMeta):
    @staticmethod
    def getFilesDirFixed():
        """the folder of the app a plugin may write pictures to before it sends them"""
        from app.exteraless.plugins import PythonBridge
        from java.io import File
        return File(PythonBridge.getCacheDir())


class DispatchQueue(Object):
    """a named worker thread. runnables run in order, each after its delay; an exception goes to the plugin log and the
    queue goes on. ui objects are not touched from here: calls into the app are handed to the main thread (see _mainthread)"""

    def __init__(self, name="queue"):
        import heapq
        import threading
        self._name = str(name)
        self._heap = []
        self._order = 0
        self._cond = threading.Condition()
        self._thread = threading.Thread(target=self._loop, name=self._name, daemon=True)
        self._heapq = heapq
        self._thread.start()

    def postRunnable(self, runnable, delay=0):
        import time
        with self._cond:
            self._order += 1
            self._heapq.heappush(self._heap, (time.monotonic() + max(0, int(delay)) / 1000.0, self._order, runnable))
            self._cond.notify()
        return True

    def _loop(self):
        import time
        while True:
            with self._cond:
                while not self._heap or self._heap[0][0] > time.monotonic():
                    wait = self._heap[0][0] - time.monotonic() if self._heap else None
                    self._cond.wait(wait)
                _due, _order, runnable = self._heapq.heappop(self._heap)
            try:
                run = getattr(runnable, "run", None)
                (run if run is not None else runnable)()
            except BaseException:
                import traceback
                from android_utils import log
                log("queue %s: %s" % (self._name, traceback.format_exc()))


class UserConfig(Object):
    selectedAccount = 0
    # the app keeps one signed in account
    MAX_ACCOUNT_COUNT = 1
    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in UserConfig._instances:
            UserConfig._instances[account] = UserConfig(account)
        return UserConfig._instances[account]

    def __init__(self, account):
        self._account = account

    def getCurrentUser(self):
        data = _ui.ask("app.me") or {}
        return TLRPC.User(id=data.get("id", 0), first_name=data.get("first_name", ""),
                          last_name=data.get("last_name", ""), username=data.get("username", ""))

    def getClientUserId(self):
        return (_ui.ask("app.me") or {}).get("id", 0)

    def isClientActivated(self):
        return self._account == 0 and bool(self.getClientUserId())


class UserObject:
    @staticmethod
    def getUserName(user):
        """the name the android client shows: first and last name, else the user name"""
        if user is None:
            return ""
        name = " ".join(part for part in (getattr(user, "first_name", ""), getattr(user, "last_name", "")) if part)
        return name or str(getattr(user, "username", "") or "")

    @staticmethod
    def getFirstName(user, *_ignored):
        return getattr(user, "first_name", "") if user is not None else ""

    @staticmethod
    def isUserSelf(user):
        return bool(getattr(user, "self", False)) if user is not None else False


class MessageObject(Object):
    # the layouts the android client caches for the text; a plugin that changes the text resets them, here there is none to reset
    textLayout = None
    captionLayout = None
    currentAccount = 0
    # what the music player says of a song that is the message (org.telegram.messenger.music), None for a message of a chat
    _track = None

    def __init__(self, *args):
        """(message, dialog_id) as the app builds it for a hook, or (account, message, generate_layout, check_media) as a plugin builds one of its own"""
        if args and isinstance(args[0], int):
            owner = args[1]
            dialog_id = getattr(owner, "dialog_id", 0)
        else:
            owner, dialog_id = args[0], (args[1] if len(args) > 1 else 0)
        self.messageOwner = owner
        self._dialog = dialog_id
        self.messageText = owner.message
        # the text of a message with media is its caption, and the app keeps both in one text
        self.caption = None

    def getDocument(self):
        """the document of a message with a file, None for the rest"""
        media = getattr(self.messageOwner, "media", None)
        return getattr(media, "document", None) if media is not None else None

    def applyNewText(self, text):
        self.messageOwner.message = str(text)
        self.messageText = str(text)

    def getId(self):
        return self.messageOwner.id

    def getDialogId(self):
        return self._dialog

    def isOut(self):
        return bool(self.messageOwner.out)

    def isVoice(self):
        return self._track is not None and self._track.get("kind") == "voice"

    def isMusic(self):
        if self._track is not None:
            return self._track.get("kind") == "music"
        document = self.getDocument()
        audio = [a for a in document.attributes if type(a).__name__ == "TL_documentAttributeAudio"] if document is not None else []
        return bool(audio) and not audio[0].voice

    def shouldEncryptPhotoOrVideo(self):
        # only a secret chat protects its files like that, and the music player plays the songs of the cloud
        return False

    def isRoundVideo(self):
        return False


class MessagesController(Object):
    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in MessagesController._instances:
            MessagesController._instances[account] = MessagesController()
        return MessagesController._instances[account]

    def isDialogMuted(self, dialog_id, topic_id=0):
        return bool((_ui.ask("app.muted", dialog=int(dialog_id)) or {}).get("value"))

    @staticmethod
    def _open(dialog_id):
        """what the app says of the chat that is open when it has this id: the chat on screen is always known, whatever the chat list holds"""
        current = _ui.ask("app.current") or {}
        if current.get("kind") == "chat" and int(current.get("signed", current.get("dialog", 0))) == int(dialog_id):
            return current
        return None

    @staticmethod
    def _known(dialog_id):
        if MessagesController._open(dialog_id) is not None:
            return True
        return bool((_ui.ask("peer.known", dialog=int(dialog_id)) or {}).get("value"))

    def getUser(self, user_id):
        """the user of the chat list with this id, or the person; None for one the app has no chat with"""
        user_id = int(user_id)
        if user_id <= 0 or not self._known(user_id):
            return None
        open_chat = self._open(user_id)
        title = str((open_chat or {}).get("chat", {}).get("title", ""))
        return TLRPC.User(id=user_id, first_name=title)

    def getChat(self, chat_id):
        """the group or channel of the chat list with this plain id, None when the app has none"""
        chat_id = int(chat_id)
        if chat_id <= 0 or not self._known(-chat_id):
            return None
        open_chat = self._open(-chat_id)
        return TLRPC.Chat(id=chat_id, title=str((open_chat or {}).get("chat", {}).get("title", "")))

    def getInputPeer(self, dialog_id):
        """the peer a request names for a chat of the list; an empty peer when the app does not have it, as the android client answers. the app finds the access hash
        itself, so only the id is carried. a negative id is a group or a channel, the app tells which"""
        dialog_id = int(dialog_id)
        if dialog_id == int((_ui.ask("app.me") or {}).get("id") or 0):
            return TLRPC.TL_inputPeerSelf()
        if not self._known(dialog_id):
            return TLRPC.TL_inputPeerEmpty()
        if dialog_id > 0:
            return TLRPC.TL_inputPeerUser(user_id=dialog_id)
        return TLRPC.TL_inputPeerChat(chat_id=-dialog_id)

    def getInputUser(self, user_id):
        user_id = int(user_id)
        if user_id == int((_ui.ask("app.me") or {}).get("id") or 0):
            return TLRPC.TL_inputUserSelf()
        return TLRPC.TL_inputUser(user_id=user_id) if user_id > 0 and self._known(user_id) else None

    class SavedMusicList(Object):
        """the songs of the profile of a user a plugin plays from. the android list loads the rest of the profile after the first song; this one holds the
        song it was set up with"""

        def __init__(self, account, dialog_id):
            self._account = account
            self._dialog = int(dialog_id)
            self.list = ArrayList()

        def setup(self, document):
            message = TLRPC.TL_message(dialog_id=self._dialog)
            message.media = TLRPC.TL_messageMediaDocument(document=document)
            self.list.clear()
            self.list.add(MessageObject(self._account, message, True, True))

    def getStoriesController(self):
        from org.telegram.ui.Stories import StoriesController
        return StoriesController.getInstance()


def _needs_requests(owner, name):
    def refuse(self, *_args, **_kwargs):
        raise NotImplementedError("%s.%s sends or reads telegram requests, which plugins cannot do on ios" % (owner, name))
    refuse.__name__ = name
    return refuse


for _name in ("processUpdates", "loadChannelAdmins"):
    setattr(MessagesController, _name, _needs_requests("MessagesController", _name))


class NotificationCenter(Object):
    didReceiveNewMessages = 1

    class NotificationCenterDelegate:
        """a plugin class implements didReceivedNotification(id, account, *args)"""

    _instances = {}
    _global = None

    @staticmethod
    def getInstance(account=0):
        if account not in NotificationCenter._instances:
            NotificationCenter._instances[account] = NotificationCenter()
        return NotificationCenter._instances[account]

    @staticmethod
    def getGlobalInstance():
        if NotificationCenter._global is None:
            NotificationCenter._global = NotificationCenter()
        return NotificationCenter._global

    def __init__(self):
        self._observers = []

    def addObserver(self, delegate, notification_id):
        entry = (delegate, int(notification_id))
        if not any(d is delegate and i == entry[1] for d, i in self._observers):
            self._observers.append(entry)

    def removeObserver(self, delegate, notification_id):
        self._observers = [(d, i) for d, i in self._observers if not (d is delegate and i == int(notification_id))]

    def postNotificationName(self, notification_id, *args):
        for delegate, wanted in list(self._observers):
            if wanted == notification_id:
                delegate.didReceivedNotification(notification_id, 0, list(args))


class SendMessagesHelper(Object):
    class SendMessageParams(Object):
        def __init__(self):
            self.message = ""
            self.peer = 0
            self.replyToMsg = None
            self.entities = None

        @staticmethod
        def of(text, peer, *_ignored):
            params = SendMessagesHelper.SendMessageParams()
            params.message = text
            params.peer = int(peer)
            return params

    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in SendMessagesHelper._instances:
            SendMessagesHelper._instances[account] = SendMessagesHelper()
        return SendMessagesHelper._instances[account]

    def generatePhotoSizes(self, path, _uri=None):
        """the android app returns a TL photo with its sizes; here the file itself stands for the photo, and the app
        decodes it when it is sent. None for a file that is missing or empty, as the android one"""
        import os
        return str(path) if os.path.isfile(path) and os.path.getsize(path) > 0 else None

    @staticmethod
    def prepareSendingDocument(_account, path, _original, _uri, caption, mime, dialog_id, *_rest):
        """a file to Saved Messages, which is the one chat the app can send a plugin's file to. a song carries the title, the performer and the duration
        a plugin sets on the document in its send hook, as it does on android"""
        from org.telegram.messenger.documents import send_audio
        send_audio(str(path), caption, str(mime or ""), int(dialog_id))

    def sendMessage(self, params):
        reply = params.replyToMsg
        reply_id = reply.getId() if hasattr(reply, "getId") else (reply if isinstance(reply, int) else 0)
        if getattr(params, "photo", None) is not None:
            _ui.ask("chat.send_photo", peer=int(params.peer), path=str(params.path), caption=str(getattr(params, "caption", None) or ""),
                    reply=int(reply_id))
            return
        _ui.ask("chat.send", peer=int(params.peer), text=str(params.message or ""), reply=int(reply_id))


class AccountInstance(Object):
    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in AccountInstance._instances:
            AccountInstance._instances[account] = AccountInstance(account)
        return AccountInstance._instances[account]

    def __init__(self, account):
        self._account = account

    def getSendMessagesHelper(self):
        return SendMessagesHelper.getInstance(self._account)

    def getMessagesController(self):
        return MessagesController.getInstance(self._account)

    def getUserConfig(self):
        return UserConfig.getInstance(self._account)

    def getConnectionsManager(self):
        from org.telegram.tgnet import ConnectionsManager
        return ConnectionsManager.getInstance(self._account)

    getFileLoader = _needs_requests("AccountInstance", "getFileLoader")

    def getNotificationCenter(self):
        return NotificationCenter.getInstance(self._account)


def _local_only(self, *_args, **_kwargs):
    """the app drops a message from its kept copies and from the open screen when the delete request it sends for a plugin is answered, so the call that does it
    on android has nothing left to do here"""


def _input_channel(chat):
    """the channel a request names, from a chat record of a channel; None for a chat that is not one"""
    return TLRPC.TL_inputChannel(channel_id=int(chat.id)) if chat is not None and getattr(chat, "channel", False) else None


MessagesController.getInputChannel = staticmethod(_input_channel)
MessagesController.deleteMessages = _local_only
# the counters the server numbers its updates with are the core's, a plugin that moves them on has nothing to move
MessagesController.processNewDifferenceParams = _local_only


class _Topics(Object):
    def findTopic(self, _chat_id, _topic_id):
        """the title of a topic is known to the app's topics screen only"""
        return None


MessagesController.getTopicsController = lambda self: _Topics()


class MessagesStorage(Object):
    """the database of the android client. the app keeps its own copies and cleans them when a delete request is answered; what a plugin posts to the storage
    queue runs on a queue of its own, the way it runs there"""

    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in MessagesStorage._instances:
            MessagesStorage._instances[account] = MessagesStorage()
        return MessagesStorage._instances[account]

    def __init__(self):
        self._queue = None

    def getStorageQueue(self):
        if self._queue is None:
            self._queue = DispatchQueue("storage")
        return self._queue


class _AnyResource(type):
    """the ids of android resources: no resource exists here, a plugin that asks for one by name gets 0, which the notices ignore"""

    def __getattr__(cls, name):
        if name.startswith("__"):
            raise AttributeError(name)
        return 0


class R:
    class raw(metaclass=_AnyResource):
        pass


class LocaleController(Object):
    """the language of the app. applyLanguage is the call the host makes when the person changes it, after the change is
    in force; the body has nothing to do, a plugin hooks the call to learn of it"""

    class LocaleInfo(Object):
        def __init__(self, plural_lang_code):
            self.pluralLangCode = plural_lang_code

        def getLangCode(self):
            return self.pluralLangCode

    _instance = None

    @staticmethod
    def getInstance():
        if LocaleController._instance is None:
            LocaleController._instance = LocaleController()
        return LocaleController._instance

    @staticmethod
    def getSystemLocaleStringIso639():
        """the language the app runs in, the one it also tells the server"""
        return str(_ui.ask("app.language")["value"])

    def getCurrentLocale(self):
        """the language the person chose in the app, as the Locale of the android client names it"""
        from java.util import Locale
        return Locale(str(_ui.ask("app.language")["value"]))

    def getCurrentLocaleInfo(self):
        return LocaleController.LocaleInfo(str(_ui.ask("app.language")["value"]))

    def applyLanguage(self, language_code):
        pass


class _BuildMeta(type):
    @property
    def BUILD_VERSION_STRING(cls):
        return str(_ui.ask("app.version")["value"])


class BuildVars(metaclass=_BuildMeta):
    """the version is the one of exteria, not of exteraGram: a plugin that wants a newer client than this app says so"""


class Utilities(Object):
    class Callback(Object):
        """a plugin class implements run(argument)"""
        _jinterface = True

    class Callback2(Object):
        """a plugin class implements run(first, second)"""
        _jinterface = True

    class Callback3(Object):
        """a plugin class implements run(first, second, third)"""
        _jinterface = True

    class Callback4(Object):
        """a plugin class implements run(first, second, third, fourth)"""
        _jinterface = True

    class Callback5(Object):
        """a plugin class implements run(first, second, third, fourth, fifth)"""
        _jinterface = True

    class CallbackReturn(Object):
        """a plugin class implements run(argument) and returns the result"""
        _jinterface = True

    BLUR_RADIUS_MAX = 254

    @staticmethod
    def stackBlurBitmap(bitmap, radius):
        """blurs a picture decoded by BitmapFactory in place, in the app: the pixels are not in python. a radius of 0 changes nothing"""
        from android.graphics import _NativeBitmap
        if not isinstance(bitmap, _NativeBitmap):
            raise NotImplementedError("only a picture decoded by BitmapFactory can be blurred")
        radius = int(radius)
        if not 0 <= radius <= Utilities.BLUR_RADIUS_MAX:
            raise ValueError("the blur radius is 0 to %d, not %d" % (Utilities.BLUR_RADIUS_MAX, radius))
        if radius:
            bitmap._blur(radius)


class DialogObject(Object):
    @staticmethod
    def isEncryptedDialog(dialog_id):
        """a secret chat has the bit 62 set and the sign bit clear, as the android client numbers its dialogs"""
        dialog_id = int(dialog_id)
        return bool(dialog_id & 0x4000000000000000) and not dialog_id & 0x8000000000000000


class FileLoader(Object):
    """the names and the choices of the file loader of the android app, which need no network. the cache name of a file is the
    key a download is announced under, so any name works as long as the same media always has the same one"""

    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in FileLoader._instances:
            FileLoader._instances[account] = FileLoader()
        return FileLoader._instances[account]

    def getPathToMessage(self, owner):
        """where the file of a message is: the path the app gave it, or a file that is not there. the app keeps no other copies by message"""
        from java.io import File
        return File(str(getattr(owner, "attachPath", "") or "/nonexistent"))

    @staticmethod
    def getClosestPhotoSizeWithSize(sizes, side, *_ignored):
        """the size whose longer side is nearest to the side asked for; None when there is none with a size"""
        best, best_distance = None, None
        for size in sizes or ():
            longer = max(int(size.w), int(size.h))
            if longer <= 0:
                continue
            distance = abs(int(side) - longer)
            if best is None or distance < best_distance:
                best, best_distance = size, distance
        return best

    @staticmethod
    def getAttachFileName(attachment, *_ignored):
        if isinstance(attachment, TLRPC.Document):
            name = str(attachment.file_name or "")
            ext = name.rsplit(".", 1)[1] if "." in name else str(attachment.mime_type or "").rpartition("/")[2]
            return "%d_%d%s" % (attachment.dc_id, attachment.id, "." + ext if 0 < len(ext) <= 16 and ext.isalnum() else "")
        if isinstance(attachment, TLRPC.Photo):
            largest = FileLoader.getClosestPhotoSizeWithSize(attachment.sizes, 100000)
            if largest is None:
                raise ValueError("the photo has no size to name a file after")
            return "%d_%s.jpg" % (attachment.id, largest.type)
        raise TypeError("not a document or a photo: %r" % (attachment,))


class ImageLocation(Object):
    """where an image is loaded from: the size and the photo, or the document. no request is made from here"""

    def __init__(self, photo_size=None, photo=None, document=None):
        self.photoSize = photo_size
        self.photo = photo
        self.document = document

    @staticmethod
    def getForPhoto(photo_size, photo):
        if photo_size is None or photo is None:
            return None
        return ImageLocation(photo_size, photo, None)

    @staticmethod
    def getForDocument(document):
        return ImageLocation(None, None, document) if document is not None else None


class ChatObject(Object):
    @staticmethod
    def isDiscussionGroup(_account, chat_id):
        """whether the chat is the thread of comments under a channel post. only the chat that is open is known"""
        current = _ui.ask("app.current") or {}
        return bool(current.get("kind") == "chat" and abs(int(current.get("dialog", 0))) == abs(int(chat_id)) and current.get("discussion"))

    ACTION_DELETE_MESSAGES = 13

    @staticmethod
    def isChannel(chat):
        """a broadcast channel or a supergroup, what the android client calls a TL_channel"""
        return bool(getattr(chat, "channel", False))

    @staticmethod
    def isMonoForum(chat):
        """the app has no direct message dialogs of a channel"""
        return False

    @staticmethod
    def canUserDoAdminAction(chat, action):
        """the owner may do anything; an administrator is asked about the right the action needs. the app knows that a person administers a channel, not which rights they
        have, so an administrator of a channel counts as having delete_messages and the server answers CHAT_ADMIN_REQUIRED when it does not"""
        if chat is None:
            return False
        if getattr(chat, "creator", False):
            return True
        rights = getattr(chat, "admin_rights", None)
        if rights is None:
            return False
        if int(action) == ChatObject.ACTION_DELETE_MESSAGES:
            return bool(rights.delete_messages)
        return False


class FileLog(Object):
    """the log of the client: lines go to stderr, where the app keeps them"""

    @staticmethod
    def _write(level, message, error=None):
        import sys
        sys.stderr.write("%s/tmessages: %s\n" % (level, message))
        if error is not None:
            sys.stderr.write("%s\n" % (error,))

    @staticmethod
    def d(message, error=None):
        FileLog._write("D", message, error)

    @staticmethod
    def e(message, error=None):
        if error is None and not isinstance(message, str):
            FileLog._write("E", "", message)
        else:
            FileLog._write("E", message, error)

    @staticmethod
    def w(message, error=None):
        FileLog._write("W", message, error)


class MediaDataController(Object):
    """importable only: the stickers, reactions and emoji the android client loads for itself. getInstance(account) answers, so a plugin that
    names the class loads, and every call that would need that data raises NotImplementedError. the app keeps no TL records of sticker sets
    or reactions that python could read, and python cannot ask the server for them"""

    _instances = {}

    @staticmethod
    def getInstance(account=0):
        found = MediaDataController._instances.get(int(account))
        if found is None:
            found = MediaDataController._instances[int(account)] = MediaDataController()
        return found

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)

        def unavailable(*_arguments):
            raise NotImplementedError("MediaDataController.%s needs the sticker, reaction and emoji data of the android client, which the app does "
                                      "not give to plugins" % name)

        return unavailable
