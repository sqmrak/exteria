"""android.content"""

import posixpath

from java.lang import IllegalArgumentException, Object, SecurityException

from android.content.prefs import SharedPreferences  # noqa: F401  the class is android.content.SharedPreferences


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
    NOTIFICATION_SERVICE = "notification"
    ALARM_SERVICE = "alarm"
    NSD_SERVICE = "servicediscovery"
    MODE_PRIVATE = 0

    def getCacheDir(self):
        """the one folder of the app a plugin writes to: the app may clear it, and photos and sounds are taken from it only"""
        from app.exteraless.plugins import PythonBridge
        from java.io import File
        return File(PythonBridge.getCacheDir())

    getFilesDir = getCacheDir

    def getCodeCacheDir(self):
        """where a plugin keeps the read-only copy of a dex file it loads, inside the one folder a plugin may write to"""
        import os
        from java.io import File
        folder = File(self.getCacheDir(), "code_cache")
        os.makedirs(folder.getAbsolutePath(), exist_ok=True)
        return folder

    def getContentResolver(self):
        return ContentResolver()

    def getApplicationContext(self):
        return self

    def getPackageName(self):
        # plugins are written for the exteraGram client and key their settings and checks on its package name
        return "com.exteragram.messenger"

    def getClassLoader(self):
        """the loader a dex loader names as its parent: the vm answers the classes of the shims and of java through it"""
        from dexvm.jloader import SYSTEM
        return SYSTEM

    def getResources(self):
        from android.content.res import Resources
        return Resources.getSystem()

    def getPackageManager(self):
        from android.content.pm import PackageManager
        return PackageManager(self.getPackageName())

    def getDrawable(self, resource_id):
        return self.getResources().getDrawable(resource_id)

    def getApplicationInfo(self):
        return ApplicationInfo(self)

    def getSharedPreferences(self, name, mode=0):
        from android.content.prefs import SharedPreferences, open_store
        if name is None or not name or "/" in name or "\\" in name or name in (".", ".."):
            raise IllegalArgumentException("File %s contains a path separator" % (name,))
        return SharedPreferences(open_store(posixpath.join(self.getFilesDir().getPath(), "shared_prefs", name + ".json")))

    def getDir(self, name, mode=0):
        from java.io import File
        folder = File(self.getFilesDir(), name)
        folder.mkdirs()
        return folder

    def getDatabasePath(self, name):
        from java.io import File
        return File(File(self.getFilesDir(), "databases"), name)

    def openOrCreateDatabase(self, name, mode=0, factory=None, *_handler):
        from android.database.sqlite import SQLiteDatabase
        return SQLiteDatabase.openOrCreateDatabase(self.getDatabasePath(name), factory)

    def deleteDatabase(self, name):
        from android.database.sqlite import SQLiteDatabase
        return SQLiteDatabase.deleteDatabase(self.getDatabasePath(name))

    def databaseList(self):
        import os
        from dexvm import runtime
        folder = self.getDatabasePath("x").getParent()
        array = runtime.new_array("[Ljava/lang/String;", 0)
        if folder and os.path.isdir(folder):
            array.extend(n for n in sorted(os.listdir(folder)) if not n.endswith(("-journal", "-wal", "-shm")))
        return array

    def getExternalFilesDir(self, kind=None):
        return self.getFilesDir()

    def getExternalCacheDir(self):
        return self.getCacheDir()


class ApplicationInfo(Object):
    FLAG_DEBUGGABLE = 2

    def __init__(self, context):
        self.packageName = context.getPackageName()
        self.dataDir = context.getFilesDir().getPath()
        self.targetSdkVersion = 33
        self.flags = 0
        self.nativeLibraryDir = ""
        self.sourceDir = ""


class DialogInterface:
    class OnKeyListener:
        pass

    class OnClickListener:
        pass

    class OnDismissListener:
        pass

    class OnCancelListener:
        pass

    class OnShowListener:
        pass


class ClipData(Object):
    """text put on the clipboard: a label and items, of which the clipboard of the app takes the first one's text"""

    class Item(Object):
        def __init__(self, text=None):
            self._text = None if text is None else str(text)

        def getText(self):
            return self._text

        def coerceToText(self, context=None):
            return self._text if self._text is not None else ""

    def __init__(self, label, mime_types=None, item=None):
        self._label = None if label is None else str(label)
        self._items = [item] if item is not None else []

    @staticmethod
    def newPlainText(label, text):
        if text is None:
            from java.lang import NullPointerException
            raise NullPointerException("a plain text clip needs a text")
        return ClipData(label, ["text/plain"], ClipData.Item(text))

    def getItemCount(self):
        return len(self._items)

    def getItemAt(self, index):
        return self._items[index]

    def addItem(self, item):
        self._items.append(item)

    def getDescription(self):
        return self._label


class ClipboardManager(Object):
    """the system clipboard. a plugin may put text on it; reading it back is refused, as the pasteboard is shared with every app on the phone and
    a plugin has no permission for it"""

    _instance = None

    @staticmethod
    def _get():
        if ClipboardManager._instance is None:
            ClipboardManager._instance = ClipboardManager()
        return ClipboardManager._instance

    def setPrimaryClip(self, clip):
        from java.lang import IllegalArgumentException, NullPointerException
        if clip is None:
            raise NullPointerException("clip == null")
        if clip.getItemCount() < 1 or clip.getItemAt(0).getText() is None:
            raise IllegalArgumentException("only a clip with a text item can be put on the clipboard")
        from android import _ui
        try:
            _ui.ask("app.clipboard_set", text=clip.getItemAt(0).getText())
        except RuntimeError as error:
            raise IllegalArgumentException(str(error)) from error

    def setText(self, text):
        self.setPrimaryClip(ClipData.newPlainText("text", text))

    def _refuse(self):
        from java.lang import SecurityException
        raise SecurityException("a plugin cannot read the clipboard, it is shared with every app on the phone")

    def hasPrimaryClip(self):
        self._refuse()

    def getPrimaryClip(self):
        self._refuse()

    def getText(self):
        self._refuse()


class ContentValues(Object):
    """a map of column names to values for the database: it holds what was put, with the type of the put call"""

    def __init__(self, source=None):
        self._values = {}
        if isinstance(source, ContentValues):
            self._values = dict(source._values)

    def _items(self):
        from android.database import _plain
        return [(k, _plain(v)) for k, v in self._values.items()]

    def put(self, key, value):
        self._values[key] = value

    putNull = lambda self, key: self.put(key, None)

    def putAll(self, other):
        self._values.update(other._values)

    def get(self, key):
        return self._values.get(key)

    def _as(self, key, convert):
        from android.database import _plain
        value = _plain(self._values.get(key))
        if value is None:
            return None
        try:
            return convert(value)
        except (ValueError, TypeError):
            return None

    def getAsString(self, key):
        return self._as(key, lambda v: v if isinstance(v, str) else ("true" if v is True else "false" if v is False else str(v)))

    def getAsLong(self, key):
        return self._as(key, lambda v: int(float(v)) if isinstance(v, str) else int(v))

    getAsInteger = getAsShort = getAsByte = getAsLong

    def getAsDouble(self, key):
        return self._as(key, float)

    getAsFloat = getAsDouble

    def getAsBoolean(self, key):
        return self._as(key, lambda v: bool(v) if not isinstance(v, str) else v.lower() in ("true", "1"))

    def getAsByteArray(self, key):
        from dexvm.jio import to_java_bytes
        value = self._as(key, lambda v: v)
        return to_java_bytes(value) if isinstance(value, bytes) else None

    def containsKey(self, key):
        return key in self._values

    def remove(self, key):
        self._values.pop(key, None)

    def clear(self):
        self._values.clear()

    def size(self):
        return len(self._values)

    def isEmpty(self):
        return not self._values

    def keySet(self):
        from dexvm.jmap import LinkedHashSet
        result = LinkedHashSet()
        for key in self._values:
            result.add(key)
        return result

    def valueSet(self):
        from dexvm.jmap import LinkedHashSet, SimpleEntry
        result = LinkedHashSet()
        for key, value in self._values.items():
            result.add(SimpleEntry(key, value))
        return result

    def equals(self, other):
        return isinstance(other, ContentValues) and other._values == self._values

    def toString(self):
        return " ".join("%s=%s" % (k, v) for k, v in self._values.items())


class ComponentName(Object):
    def __init__(self, package, class_name=None):
        if class_name is None:
            package, class_name = package.getPackageName(), class_name if class_name else str(package)
        self._p, self._c = package, class_name

    def getPackageName(self):
        return self._p

    def getClassName(self):
        return self._c

    def getShortClassName(self):
        return self._c[len(self._p):] if self._c.startswith(self._p + ".") else self._c

    def flattenToString(self):
        return self._p + "/" + self._c

    def flattenToShortString(self):
        return self._p + "/" + self.getShortClassName()

    @staticmethod
    def unflattenFromString(text):
        package, _, name = text.partition("/")
        if not name:
            return None
        return ComponentName(package, package + name if name.startswith(".") else name)

    def equals(self, other):
        return isinstance(other, ComponentName) and (other._p, other._c) == (self._p, self._c)

    def hashCode(self):
        return hash((self._p, self._c)) & 0x7FFFFFFF

    def toString(self):
        return "ComponentInfo{%s/%s}" % (self._p, self._c)


class ActivityNotFoundException(RuntimeError):
    pass


class OperationApplicationException(Exception):
    pass


class ComponentCallbacks:
    """a program implements onConfigurationChanged(newConfig) and onLowMemory()"""


class ComponentCallbacks2(ComponentCallbacks):
    TRIM_MEMORY_COMPLETE = 80
    TRIM_MEMORY_MODERATE = 60
    TRIM_MEMORY_BACKGROUND = 40
    TRIM_MEMORY_UI_HIDDEN = 20
    TRIM_MEMORY_RUNNING_CRITICAL = 15
    TRIM_MEMORY_RUNNING_LOW = 10
    TRIM_MEMORY_RUNNING_MODERATE = 5


class ContextWrapper(Context):
    """a Context that hands every call to the one it wraps"""

    def __init__(self, base=None):
        self._base = base

    def attachBaseContext(self, base):
        self._base = base

    def getBaseContext(self):
        return self._base

    def __getattr__(self, name):
        base = self.__dict__.get("_base")
        if base is None or name.startswith("__"):
            raise AttributeError(name)
        return getattr(base, name)


class IntentFilter(Object):
    def __init__(self, action=None):
        self._actions = [action] if isinstance(action, str) else []
        self._categories = []
        self._schemes = []
        self._priority = 0

    def addAction(self, action):
        self._actions.append(action)

    def countActions(self):
        return len(self._actions)

    def getAction(self, index):
        return self._actions[index]

    def hasAction(self, action):
        return action in self._actions

    def addCategory(self, category):
        self._categories.append(category)

    def hasCategory(self, category):
        return category in self._categories

    def addDataScheme(self, scheme):
        self._schemes.append(scheme)

    def setPriority(self, priority):
        self._priority = priority

    def getPriority(self):
        return self._priority

    def matchAction(self, action):
        return action in self._actions


class BroadcastReceiver(Object):
    """a program extends it and implements onReceive(context, intent); the app sends no system broadcasts, so a receiver is called only by code
    that calls onReceive itself"""

    def onReceive(self, context, intent):
        raise NotImplementedError("onReceive")

    def isOrderedBroadcast(self):
        return False

    def isInitialStickyBroadcast(self):
        return False

    def goAsync(self):
        return None

    def getResultCode(self):
        return getattr(self, "_code", -1)

    def setResultCode(self, code):
        self._code = code


class UriMatcher(Object):
    NO_MATCH = -1

    def __init__(self, code):
        self._code, self._rules = code, []

    def addURI(self, authority, path, code):
        self._rules.append((authority, [p for p in (path or "").split("/") if p], code))

    def match(self, uri):
        segments = list(uri.getPathSegments()) if hasattr(uri, "getPathSegments") else [p for p in (uri.getPath() or "").split("/") if p]
        for authority, pattern, code in self._rules:
            if authority != uri.getAuthority() or len(pattern) != len(segments):
                continue
            if all(p in ("#", "*") and (p == "*" or s.isdigit()) or p == s for p, s in zip(pattern, segments)):
                return code
        return self._code


class ContentUris(Object):
    @staticmethod
    def parseId(uri):
        last = uri.getLastPathSegment()
        return -1 if last is None else int(last)

    @staticmethod
    def withAppendedId(uri, value):
        from android.net import Uri
        return Uri(uri.toString().rstrip("/") + "/" + str(int(value)))

    @staticmethod
    def appendId(builder, value):
        return builder.appendPath(str(int(value)))
