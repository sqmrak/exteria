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

    def __init__(self, owner, dialog_id=0):
        self.messageOwner = owner
        self._dialog = dialog_id
        self.messageText = owner.message
        # the text of a message with media is its caption, and the app keeps both in one text
        self.caption = None

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
        return self._track is not None and self._track.get("kind") == "music"

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

    def getUser(self, user_id):
        return None

    def getStoriesController(self):
        from org.telegram.ui.Stories import StoriesController
        return StoriesController.getInstance()


def _needs_requests(owner, name):
    def refuse(self, *_args, **_kwargs):
        raise NotImplementedError("%s.%s sends or reads telegram requests, which plugins cannot do on ios" % (owner, name))
    refuse.__name__ = name
    return refuse


for _name in ("getChat", "getInputPeer", "getInputChannel", "processUpdates", "loadChannelAdmins", "deleteMessages"):
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

    getConnectionsManager = _needs_requests("AccountInstance", "getConnectionsManager")
    getFileLoader = _needs_requests("AccountInstance", "getFileLoader")

    def getNotificationCenter(self):
        return NotificationCenter.getInstance(self._account)


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

    isChannel = _needs_requests("ChatObject", "isChannel")
