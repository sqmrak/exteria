"""android.os"""

import sys
import time
import threading

from java.lang import Object


class _Queue:
    """the messages and runnables of one looper in the order of their time"""

    def __init__(self):
        self.items = []
        self.cond = threading.Condition()
        self.sequence = 0
        self.quit = False

    def add(self, when, entry):
        with self.cond:
            self.sequence += 1
            self.items.append((when, self.sequence, entry))
            self.items.sort(key=lambda item: (item[0], item[1]))
            self.cond.notify_all()


class Looper(Object):
    """the main looper hands its work to the app's thread (PluginServices.runOnUiThread); a looper made by Looper.prepare() or a
    HandlerThread has a queue of its own that loop() runs"""

    _main = None
    _local = threading.local()

    def __init__(self, thread=None, main=False):
        self._thread = thread
        self._is_main = main
        self._queue = None if main else _Queue()

    @staticmethod
    def getMainLooper():
        if Looper._main is None:
            Looper._main = Looper(threading.main_thread(), True)
        return Looper._main

    @staticmethod
    def prepare(*_quit_allowed):
        if getattr(Looper._local, "looper", None) is not None:
            raise RuntimeError("Only one Looper may be created per thread")
        Looper._local.looper = Looper(threading.current_thread())

    prepareMainLooper = prepare

    @staticmethod
    def myLooper():
        found = getattr(Looper._local, "looper", None)
        if found is not None:
            return found
        return Looper.getMainLooper() if threading.current_thread() is threading.main_thread() else None

    @staticmethod
    def myQueue():
        return Looper.myLooper().getQueue()

    @staticmethod
    def loop():
        looper = getattr(Looper._local, "looper", None)
        if looper is None:
            raise RuntimeError("No Looper; Looper.prepare() wasn't called on this thread.")
        looper._run()

    def _run(self):
        queue = self._queue
        while True:
            with queue.cond:
                while True:
                    if queue.quit and not queue.items:
                        return
                    if queue.quit:
                        queue.items.clear()
                        return
                    if not queue.items:
                        queue.cond.wait()
                        continue
                    when, _, entry = queue.items[0]
                    wait = when - time.monotonic()
                    if wait > 0:
                        queue.cond.wait(wait)
                        continue
                    queue.items.pop(0)
                    break
            entry()

    def _post(self, entry, delay_ms):
        """run entry() on the thread of this looper after the delay"""
        if self._is_main:
            from app.exteraless.plugins import PluginServices
            PluginServices.runOnUiThread(entry, max(0, int(delay_ms)))
        else:
            self._queue.add(time.monotonic() + max(0, int(delay_ms)) / 1000.0, entry)

    def getQueue(self):
        return MessageQueue(self)

    def getThread(self):
        return self._thread

    def isCurrentThread(self):
        return threading.current_thread() is self._thread

    def quit(self):
        if self._is_main:
            raise RuntimeError("Main thread not allowed to quit.")
        with self._queue.cond:
            self._queue.quit = True
            self._queue.items.clear()
            self._queue.cond.notify_all()

    def quitSafely(self):
        if self._is_main:
            raise RuntimeError("Main thread not allowed to quit.")
        with self._queue.cond:
            self._queue.quit = True
            self._queue.cond.notify_all()


class MessageQueue(Object):
    class IdleHandler:
        """a program implements queueIdle()"""

    def __init__(self, looper):
        self._looper = looper

    def isIdle(self):
        return True

    def addIdleHandler(self, handler):
        self._idle = getattr(self, "_idle", []) + [handler]

    def removeIdleHandler(self, handler):
        self._idle = [h for h in getattr(self, "_idle", []) if h is not handler]


class Message(Object):
    _pool = []
    _pool_lock = threading.Lock()

    def __init__(self):
        self.what = 0
        self.arg1 = 0
        self.arg2 = 0
        self.obj = None
        self.replyTo = None
        self.target = None
        self.callback = None
        self._data = None
        self._when = 0

    @staticmethod
    def obtain(first=None, what=None, arg1=None, arg2=None, obj=None):
        """obtain(), obtain(msg), obtain(handler), obtain(handler, what), obtain(handler, what, obj), obtain(handler, what, arg1, arg2[, obj]),
        obtain(handler, callback)"""
        with Message._pool_lock:
            message = Message._pool.pop() if Message._pool else Message()
        if isinstance(first, Message):
            message.copyFrom(first)
            return message
        if first is None:
            return message
        message.target = first
        if callable(what) and not isinstance(what, int):
            message.callback = what
        elif what is not None:
            message.what = what
            if arg1 is not None and arg2 is None and not isinstance(arg1, int):
                message.obj = arg1
            elif arg1 is not None:
                message.arg1, message.arg2 = arg1, arg2 if arg2 is not None else 0
                message.obj = obj
        return message

    def copyFrom(self, other):
        self.what, self.arg1, self.arg2, self.obj = other.what, other.arg1, other.arg2, other.obj
        self.replyTo = other.replyTo
        self._data = Bundle(other._data) if other._data is not None else None

    def setData(self, bundle):
        self._data = bundle

    def getData(self):
        if self._data is None:
            self._data = Bundle()
        return self._data

    def peekData(self):
        return self._data

    def setTarget(self, handler):
        self.target = handler

    def getTarget(self):
        return self.target

    def getCallback(self):
        return self.callback

    def getWhen(self):
        return self._when

    def sendToTarget(self):
        if self.target is None:
            raise RuntimeError("Message has no target")
        self.target.sendMessage(self)

    def recycle(self):
        self.what = self.arg1 = self.arg2 = 0
        self.obj = self.target = self.callback = self.replyTo = self._data = None
        with Message._pool_lock:
            if len(Message._pool) < 50:
                Message._pool.append(self)

    def isAsynchronous(self):
        return False

    def toString(self):
        return "{ what=%d obj=%s target=%s }" % (self.what, self.obj, type(self.target).__name__ if self.target else "null")


class Handler(Object):
    class Callback:
        """a program implements handleMessage(msg) and returns true when it took the message"""

    def __init__(self, first=None, second=None, *_flags):
        self._looper = None
        self._callback = None
        for argument in (first, second):
            if isinstance(argument, Looper):
                self._looper = argument
            elif argument is not None and not isinstance(argument, bool):
                self._callback = argument
        if self._looper is None:
            # a thread without a looper posts to the main one, which is where plugin code that builds a Handler anywhere expects it to go
            self._looper = Looper.myLooper() or Looper.getMainLooper()
        self._entries_list = []

    @staticmethod
    def _entries():
        return _pending

    @staticmethod
    def createAsync(looper, callback=None):
        return Handler(looper, callback)

    def getLooper(self):
        return self._looper

    def handleMessage(self, message):
        return None

    def dispatchMessage(self, message):
        if message.callback is not None:
            run = getattr(message.callback, "run", None)
            (run if run is not None else message.callback)()
            return
        if self._callback is not None:
            handle = getattr(self._callback, "handleMessage", None)
            if (handle if handle is not None else self._callback)(message):
                return
        self.handleMessage(message)

    def _schedule(self, kind, payload, delay, token=None):
        entry = {"kind": kind, "payload": payload, "live": True, "token": token, "handler": self}

        def fire():
            if not entry["live"]:
                return
            entry["live"] = False
            for pool in (_pending, self._entries_list):
                try:
                    pool.remove(entry)
                except ValueError:
                    pass
            if kind == "run":
                run = getattr(payload, "run", None)
                (run if run is not None else payload)()
            else:
                self.dispatchMessage(payload)
                payload.recycle()

        _pending.append(entry)
        self._entries_list.append(entry)
        self._looper._post(fire, delay)
        return True

    def post(self, runnable):
        return self.postDelayed(runnable, 0)

    def postAtFrontOfQueue(self, runnable):
        return self.postDelayed(runnable, 0)

    def postDelayed(self, runnable, delay=0, *token):
        if isinstance(delay, (str, object)) and not isinstance(delay, (int, float)):
            runnable, token, delay = runnable, (delay,), token[0] if token else 0
        return self._schedule("run", runnable, delay, token[0] if token else None)

    def postAtTime(self, runnable, first, second=None):
        uptime = second if second is not None else first
        token = first if second is not None else None
        return self._schedule("run", runnable, int(uptime) - int(time.monotonic() * 1000), token)

    def sendMessage(self, message):
        return self.sendMessageDelayed(message, 0)

    def sendMessageAtFrontOfQueue(self, message):
        return self.sendMessageDelayed(message, 0)

    def sendMessageDelayed(self, message, delay):
        message.target = self
        message._when = int(time.monotonic() * 1000) + max(0, int(delay))
        return self._schedule("message", message, delay)

    def sendMessageAtTime(self, message, uptime):
        return self.sendMessageDelayed(message, int(uptime) - int(time.monotonic() * 1000))

    def sendEmptyMessage(self, what):
        return self.sendEmptyMessageDelayed(what, 0)

    def sendEmptyMessageDelayed(self, what, delay):
        message = Message.obtain(self, what)
        return self.sendMessageDelayed(message, delay)

    def sendEmptyMessageAtTime(self, what, uptime):
        return self.sendMessageAtTime(Message.obtain(self, what), uptime)

    def obtainMessage(self, what=None, arg1=None, arg2=None, obj=None):
        return Message.obtain(self, what, arg1, arg2, obj) if what is not None else Message.obtain(self)

    def hasMessages(self, what, obj=None):
        return any(e["live"] and e["kind"] == "message" and e["payload"].what == what and (obj is None or e["payload"].obj is obj)
                   for e in self._entries_list)

    def hasCallbacks(self, runnable):
        return any(e["live"] and e["kind"] == "run" and e["payload"] == runnable for e in self._entries_list)

    def _cancel(self, test):
        for entry in list(self._entries_list):
            if entry["live"] and test(entry):
                entry["live"] = False
                for pool in (_pending, self._entries_list):
                    try:
                        pool.remove(entry)
                    except ValueError:
                        pass

    def removeMessages(self, what, obj=None):
        self._cancel(lambda e: e["kind"] == "message" and e["payload"].what == what and (obj is None or e["payload"].obj is obj))

    def removeCallbacks(self, runnable, token=None):
        self._cancel(lambda e: e["kind"] == "run" and e["payload"] == runnable and (token is None or e["token"] is token))

    def removeCallbacksAndMessages(self, token=None):
        self._cancel(lambda e: token is None or e["token"] is token or (e["kind"] == "message" and e["payload"].obj is token))

    def getMessageName(self, message):
        return str(message.what)

    def toString(self):
        return "Handler (%s) {%x}" % (type(self).__name__, id(self) & 0xFFFFFF)


_pending = []


class HandlerThread(Object):
    """a thread that runs a looper: start() it, then make a Handler on getLooper()"""

    def __init__(self, name="HandlerThread", priority=0):
        self._name = name
        self._looper = None
        self._ready = threading.Condition()
        self._thread = threading.Thread(target=self._run, name=name, daemon=True)

    def _run(self):
        Looper.prepare()
        with self._ready:
            self._looper = Looper.myLooper()
            self._ready.notify_all()
        self.onLooperPrepared()
        Looper.loop()

    def onLooperPrepared(self):
        return None

    def start(self):
        self._thread.start()

    def run(self):
        self._run()

    def getLooper(self):
        if not self._thread.is_alive():
            return None
        with self._ready:
            while self._looper is None:
                self._ready.wait()
        return self._looper

    def quit(self):
        looper = self.getLooper()
        if looper is None:
            return False
        looper.quit()
        return True

    def quitSafely(self):
        looper = self.getLooper()
        if looper is None:
            return False
        looper.quitSafely()
        return True

    def getName(self):
        return self._name

    def getThreadId(self):
        return self._thread.ident

    def isAlive(self):
        return self._thread.is_alive()

    def join(self, timeout=None):
        self._thread.join(None if timeout is None else timeout / 1000.0)

    def interrupt(self):
        return None


class Bundle(Object):
    """a map of typed values; the put and get methods share one dictionary"""

    def __init__(self, other=None):
        self._values = dict(other._values) if isinstance(other, Bundle) else {}

    def _put(self, key, value):
        self._values[key] = value

    putInt = putBoolean = putString = putFloat = putLong = putDouble = _put

    def get(self, key, default=None):
        return self._values.get(key, default)

    def _typed(self, key, default, expected):
        value = self._values.get(key)
        return value if type(value) in expected else default

    def getInt(self, key, default=0):
        return self._typed(key, default, (int,))

    getLong = getInt

    def getBoolean(self, key, default=False):
        return self._typed(key, default, (bool,))

    def getString(self, key, default=None):
        return self._typed(key, default, (str,))

    def getFloat(self, key, default=0.0):
        return self._typed(key, default, (float,))

    getDouble = getFloat

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


class Process:
    _started = int(time.monotonic() * 1000)

    @staticmethod
    def is64Bit():
        import sys
        return sys.maxsize > 2 ** 32

    @staticmethod
    def myPid():
        import os
        return os.getpid()

    @staticmethod
    def myUid():
        import os
        return os.getuid()

    @staticmethod
    def getStartElapsedRealtime():
        """the clock reading when the interpreter started: it runs from the first plugin, so uptime here is the time plugins have had"""
        return Process._started


class SystemClock:
    @staticmethod
    def uptimeMillis():
        return int(time.monotonic() * 1000)

    elapsedRealtime = uptimeMillis


class Build:
    class VERSION:
        SDK_INT = 33
        RELEASE = "13"

    MODEL = "iPhone"
    MANUFACTURER = "Apple"
    # the abis of the process the plugin runs in: arm64 on a 64 bit slice, armv7 on a 32 bit one
    SUPPORTED_64_BIT_ABIS = ["arm64-v8a"] if sys.maxsize > 2 ** 32 else []
    SUPPORTED_32_BIT_ABIS = ["armeabi-v7a"]
    SUPPORTED_ABIS = SUPPORTED_64_BIT_ABIS + SUPPORTED_32_BIT_ABIS


class Parcelable:
    """a program implements describeContents() and writeToParcel(parcel, flags); parcels themselves are not implemented"""

    CONTENTS_FILE_DESCRIPTOR = 1
    PARCELABLE_WRITE_RETURN_VALUE = 1

    class Creator:
        """a program implements createFromParcel(parcel) and newArray(size)"""


class BaseBundle(Bundle):
    pass


class PersistableBundle(Bundle):
    pass


class RemoteException(Exception):
    pass


class DeadObjectException(RemoteException):
    pass


class BadParcelableException(RuntimeError):
    pass


class OperationCanceledException(RuntimeError):
    pass


class NetworkOnMainThreadException(RuntimeError):
    pass


class IInterface:
    """a program implements asBinder()"""


class IBinder:
    FIRST_CALL_TRANSACTION = 1
    LAST_CALL_TRANSACTION = 0x00FFFFFF
    FLAG_ONEWAY = 1


class Binder(Object):
    """there are no other processes, so a Binder is an object that is its own endpoint and never crosses one"""

    def __init__(self):
        self._owner = None
        self._descriptor = None

    def attachInterface(self, owner, descriptor):
        self._owner, self._descriptor = owner, descriptor

    def queryLocalInterface(self, descriptor):
        return self._owner if descriptor == self._descriptor else None

    def getInterfaceDescriptor(self):
        return self._descriptor

    def isBinderAlive(self):
        return True

    pingBinder = isBinderAlive

    @staticmethod
    def getCallingPid():
        import os
        return os.getpid()

    @staticmethod
    def getCallingUid():
        import os
        return os.getuid()


class Environment(Object):
    MEDIA_MOUNTED = "mounted"
    MEDIA_UNMOUNTED = "unmounted"
    MEDIA_REMOVED = "removed"
    DIRECTORY_DOWNLOADS = "Download"
    DIRECTORY_PICTURES = "Pictures"
    DIRECTORY_DCIM = "DCIM"
    DIRECTORY_MUSIC = "Music"
    DIRECTORY_MOVIES = "Movies"
    DIRECTORY_DOCUMENTS = "Documents"

    @staticmethod
    def _root():
        from android.content import Context
        return Context().getFilesDir()

    @staticmethod
    def getExternalStorageState(*_path):
        return Environment.MEDIA_MOUNTED

    @staticmethod
    def getExternalStorageDirectory():
        """the files folder of the app: it is the only place a plugin may write"""
        return Environment._root()

    @staticmethod
    def getExternalStoragePublicDirectory(kind):
        from java.io import File
        folder = File(Environment._root(), str(kind))
        folder.mkdirs()
        return folder

    @staticmethod
    def getDataDirectory():
        return Environment._root()

    @staticmethod
    def getDownloadCacheDirectory():
        return Environment._root()

    @staticmethod
    def isExternalStorageEmulated(*_path):
        return True

    @staticmethod
    def isExternalStorageRemovable(*_path):
        return False


class CancellationSignal(Object):
    class OnCancelListener:
        """a program implements onCancel()"""

    def __init__(self):
        self._cancelled = False
        self._listener = None

    def isCanceled(self):
        return self._cancelled

    def throwIfCanceled(self):
        if self._cancelled:
            raise OperationCanceledException()

    def cancel(self):
        if self._cancelled:
            return
        self._cancelled = True
        if self._listener is not None:
            listener, self._listener = self._listener, None
            call = getattr(listener, "onCancel", None)
            (call if call is not None else listener)()

    def setOnCancelListener(self, listener):
        self._listener = listener
        if self._cancelled and listener is not None:
            self.cancel_now = True
            self._listener = None
            call = getattr(listener, "onCancel", None)
            (call if call is not None else listener)()


class UserHandle(Object):
    def __init__(self, user_id=0):
        self._id = user_id

    @staticmethod
    def myUserId():
        return 0

    @staticmethod
    def getUserHandleForUid(uid):
        return UserHandle(uid // 100000)

    def getIdentifier(self):
        return self._id


class VibrationEffect(Object):
    DEFAULT_AMPLITUDE = -1
    EFFECT_CLICK = 0
    EFFECT_DOUBLE_CLICK = 1
    EFFECT_TICK = 2
    EFFECT_HEAVY_CLICK = 5

    def __init__(self, kind, data):
        self._kind, self._data = kind, data

    @staticmethod
    def createOneShot(milliseconds, amplitude):
        if milliseconds <= 0:
            raise ValueError("timing must be positive")
        return VibrationEffect("oneshot", (milliseconds, amplitude))

    @staticmethod
    def createWaveform(timings, *rest):
        return VibrationEffect("waveform", (list(timings),) + rest)

    @staticmethod
    def createPredefined(effect_id):
        return VibrationEffect("predefined", effect_id)

    def getDuration(self):
        return self._data[0] if self._kind == "oneshot" else -1


class Vibrator(Object):
    """the device has a vibration motor, but the app has no service that drives it: hasVibrator says so, and vibrate refuses
    instead of pretending to buzz"""

    def hasVibrator(self):
        return False

    def hasAmplitudeControl(self):
        return False

    def cancel(self):
        return None

    def vibrate(self, *_args):
        raise NotImplementedError("the app has no service that drives the vibration motor, check hasVibrator() first")


class VibratorManager(Object):
    def getDefaultVibrator(self):
        return Vibrator()


class PowerManager(Object):
    PARTIAL_WAKE_LOCK = 1
    SCREEN_DIM_WAKE_LOCK = 6
    SCREEN_BRIGHT_WAKE_LOCK = 10
    FULL_WAKE_LOCK = 26

    class WakeLock(Object):
        """held is tracked and nothing else: the process of an ios app is kept alive by the system, not by a lock"""

        def __init__(self, tag):
            self._tag, self._count, self._counted = tag, 0, True

        def acquire(self, *_timeout):
            self._count += 1

        def release(self, *_flags):
            if self._count:
                self._count -= 1

        def isHeld(self):
            return self._count > 0

        def setReferenceCounted(self, flag):
            self._counted = bool(flag)

    def newWakeLock(self, levels, tag):
        return PowerManager.WakeLock(tag)

    def isInteractive(self):
        return True

    isScreenOn = isInteractive

    def isPowerSaveMode(self):
        return False

    def isIgnoringBatteryOptimizations(self, package):
        return True


class Debug(Object):
    @staticmethod
    def isDebuggerConnected():
        return sys.gettrace() is not None

    @staticmethod
    def waitingForDebugger():
        return False

    @staticmethod
    def getNativeHeapSize():
        return 0

    getNativeHeapAllocatedSize = getNativeHeapFreeSize = getNativeHeapSize

    @staticmethod
    def threadCpuTimeNanos():
        return time.thread_time_ns()

    @staticmethod
    def startMethodTracing(*_args):
        raise NotImplementedError("method tracing is not available")

    stopMethodTracing = startMethodTracing


class Trace(Object):
    """tracing with no listening tracer is what an android build answers when nobody records: begin and end have no effect"""

    TRACE_TAG_APP = 1 << 12

    @staticmethod
    def isEnabled():
        return False

    @staticmethod
    def beginSection(name):
        return None

    @staticmethod
    def endSection():
        return None

    @staticmethod
    def beginAsyncSection(name, cookie):
        return None

    @staticmethod
    def endAsyncSection(name, cookie):
        return None

    @staticmethod
    def setCounter(name, value):
        return None


class StrictMode(Object):
    """policies are kept and nothing is enforced: there is no strict mode to violate"""

    class ThreadPolicy(Object):
        LAX = None

        class Builder(Object):
            def __init__(self, source=None):
                self._flags = set()

            def __getattr__(self, name):
                if name.startswith(("detect", "permit", "penalty")):
                    def collect(*_args):
                        self._flags.add(name)
                        return self
                    return collect
                raise AttributeError(name)

            def build(self):
                policy = StrictMode.ThreadPolicy()
                policy._flags = set(self._flags)
                return policy

    class VmPolicy(Object):
        LAX = None

        class Builder(Object):
            def __init__(self, source=None):
                self._flags = set()

            def __getattr__(self, name):
                if name.startswith(("detect", "permit", "penalty")):
                    def collect(*_args):
                        self._flags.add(name)
                        return self
                    return collect
                raise AttributeError(name)

            def build(self):
                policy = StrictMode.VmPolicy()
                policy._flags = set(self._flags)
                return policy

    _thread = None
    _vm = None

    @staticmethod
    def setThreadPolicy(policy):
        StrictMode._thread = policy

    @staticmethod
    def getThreadPolicy():
        return StrictMode._thread or StrictMode.ThreadPolicy()

    @staticmethod
    def setVmPolicy(policy):
        StrictMode._vm = policy

    @staticmethod
    def getVmPolicy():
        return StrictMode._vm or StrictMode.VmPolicy()

    @staticmethod
    def allowThreadDiskReads():
        return StrictMode.getThreadPolicy()

    allowThreadDiskWrites = allowThreadDiskReads


class LocaleList(Object):
    def __init__(self, *locales):
        self._items = list(locales)

    @staticmethod
    def getDefault():
        from java.util import Locale
        return LocaleList(Locale.getDefault())

    @staticmethod
    def getAdjustedDefault():
        return LocaleList.getDefault()

    def size(self):
        return len(self._items)

    def get(self, index):
        return self._items[index] if 0 <= index < len(self._items) else None

    def isEmpty(self):
        return not self._items

    def toLanguageTags(self):
        return ",".join(item.toLanguageTag() for item in self._items)


class FileUtils(Object):
    @staticmethod
    def copy(source, target, *_rest):
        total = 0
        while True:
            chunk = source.read(65536)
            if not chunk:
                return total
            target.write(chunk)
            total += len(chunk)


class ParcelFileDescriptor(Object):
    MODE_READ_ONLY = 0x10000000
    MODE_WRITE_ONLY = 0x20000000
    MODE_READ_WRITE = 0x30000000
    MODE_CREATE = 0x08000000
    MODE_TRUNCATE = 0x04000000
    MODE_APPEND = 0x02000000

    def __init__(self, handle, path):
        self._h, self._path, self._closed = handle, path, False

    @staticmethod
    def open(file, mode):
        import os
        from java.io import FileNotFoundException
        path = file.getPath()
        flags = os.O_RDONLY if mode & 0x30000000 == ParcelFileDescriptor.MODE_READ_ONLY else (
            os.O_WRONLY if mode & 0x30000000 == ParcelFileDescriptor.MODE_WRITE_ONLY else os.O_RDWR)
        if mode & ParcelFileDescriptor.MODE_CREATE:
            flags |= os.O_CREAT
        if mode & ParcelFileDescriptor.MODE_TRUNCATE:
            flags |= os.O_TRUNC
        if mode & ParcelFileDescriptor.MODE_APPEND:
            flags |= os.O_APPEND
        try:
            return ParcelFileDescriptor(os.open(path, flags, 0o600), path)
        except OSError as error:
            raise FileNotFoundError(str(error)) if False else FileNotFoundException("%s: %s" % (path, error))

    def getFd(self):
        return self._h

    def detachFd(self):
        handle, self._h = self._h, -1
        self._closed = True
        return handle

    def getStatSize(self):
        import os
        return os.fstat(self._h).st_size

    def close(self):
        import os
        if not self._closed:
            self._closed = True
            os.close(self._h)


class ResultReceiver(Object):
    def __init__(self, handler=None):
        self._handler = handler

    def send(self, code, data):
        if self._handler is not None:
            self._handler.post(lambda: self.onReceiveResult(code, data))
        else:
            self.onReceiveResult(code, data)

    def onReceiveResult(self, code, data):
        return None


class Messenger(Object):
    def __init__(self, target):
        self._target = target

    def send(self, message):
        message.replyTo = None
        self._target.sendMessage(message)

    def getBinder(self):
        return Binder()
