"""android.content"""

import posixpath

from java.lang import IllegalArgumentException, Object, SecurityException


class Intent(Object):
    ACTION_OPEN_DOCUMENT = "android.intent.action.OPEN_DOCUMENT"
    ACTION_GET_CONTENT = "android.intent.action.GET_CONTENT"
    ACTION_PICK = "android.intent.action.PICK"
    ACTION_VIEW = "android.intent.action.VIEW"
    ACTION_SEND = "android.intent.action.SEND"
    CATEGORY_OPENABLE = "android.intent.category.OPENABLE"
    CATEGORY_DEFAULT = "android.intent.category.DEFAULT"
    EXTRA_TEXT = "android.intent.extra.TEXT"
    EXTRA_STREAM = "android.intent.extra.STREAM"
    FLAG_GRANT_READ_URI_PERMISSION = 1
    FLAG_GRANT_WRITE_URI_PERMISSION = 2
    FLAG_GRANT_PERSISTABLE_URI_PERMISSION = 0x40
    FLAG_ACTIVITY_NEW_TASK = 0x10000000

    def __init__(self, action=None, uri=None):
        if isinstance(action, Intent):
            raise NotImplementedError("copying an intent is not available")
        self._action = action
        self._data = uri
        self._type = None
        self._categories = []
        self._flags = 0
        self._extras = {}

    def setAction(self, action):
        self._action = action
        return self

    def getAction(self):
        return self._action

    def setData(self, uri):
        self._data = uri
        self._type = None
        return self

    def getData(self):
        return self._data

    def setType(self, mime):
        self._type = None if mime is None else str(mime).lower()
        self._data = None
        return self

    def setDataAndType(self, uri, mime):
        self._data = uri
        self._type = None if mime is None else str(mime).lower()
        return self

    def getType(self):
        return self._type

    def addCategory(self, category):
        if category not in self._categories:
            self._categories.append(category)
        return self

    def hasCategory(self, category):
        return category in self._categories

    def addFlags(self, flags):
        self._flags |= int(flags)
        return self

    def setFlags(self, flags):
        self._flags = int(flags)
        return self

    def getFlags(self):
        return self._flags

    def putExtra(self, name, value):
        self._extras[str(name)] = value
        return self

    def hasExtra(self, name):
        return name in self._extras

    def getStringExtra(self, name):
        value = self._extras.get(name)
        return value if isinstance(value, str) else None

    def getBooleanExtra(self, name, default=False):
        value = self._extras.get(name)
        return value if isinstance(value, bool) else default

    def getIntExtra(self, name, default=0):
        value = self._extras.get(name)
        return value if isinstance(value, int) and not isinstance(value, bool) else default


class _PickedStream(Object):
    """the bytes of a picture the person chose. only BitmapFactory reads it: the app decodes the file itself, so the picture never
    passes through python as bytes"""

    def __init__(self, path):
        self._path = path
        self._closed = False

    def read(self, *_args):
        raise NotImplementedError("a picture is read with BitmapFactory.decodeStream, not byte by byte")

    def close(self):
        self._closed = True


class ContentResolver(Object):
    """the pictures the person chose in the picker of the app (see Activity.startActivityForResult) are files of the app, and their
    file: addresses are the only ones that open. the app checks the path again before it reads it"""

    _root = []

    @staticmethod
    def _picks_root():
        if not ContentResolver._root:
            from android import _ui
            ContentResolver._root.append(str((_ui.ask("app.pick_root") or {}).get("value") or ""))
        return ContentResolver._root[0]

    def _path_of(self, uri):
        if uri is None:
            raise IllegalArgumentException("uri is null")
        if uri.getScheme() != "file" or uri.getAuthority():
            raise SecurityException("only the pictures the person chose are readable: " + uri.toString())
        path = uri.getPath() or ""
        root = self._picks_root()
        clean = posixpath.normpath(path)
        if not root or not path.startswith("/") or posixpath.dirname(clean) != posixpath.normpath(root) or clean != path:
            raise SecurityException("not a picture the person chose: " + uri.toString())
        return path

    def openInputStream(self, uri):
        return _PickedStream(self._path_of(uri))

    def takePersistableUriPermission(self, uri, flags):
        # the file is the app's own and stays until newer picks push it out, so the permission only has to be one that exists
        self._path_of(uri)
        if int(flags) & ~(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION):
            raise IllegalArgumentException("not a grant flag: %d" % int(flags))


class Context(Object):
    SENSOR_SERVICE = "sensor"
    WINDOW_SERVICE = "window"
    VIBRATOR_SERVICE = "vibrator"
    INPUT_METHOD_SERVICE = "input_method"
    CLIPBOARD_SERVICE = "clipboard"
    MODE_PRIVATE = 0

    def getCacheDir(self):
        """the one folder of the app a plugin writes to: the app may clear it, and photos and sounds are taken from it only"""
        from app.exteraless.plugins import PythonBridge
        from java.io import File
        return File(PythonBridge.getCacheDir())

    getFilesDir = getCacheDir

    def getContentResolver(self):
        return ContentResolver()


class DialogInterface:
    class OnClickListener:
        pass

    class OnDismissListener:
        pass

    class OnCancelListener:
        pass

    class OnShowListener:
        pass


class ClipData:
    @staticmethod
    def newPlainText(label, text):
        return ClipData()
