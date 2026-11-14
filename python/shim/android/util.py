"""android.util"""


class TypedValue:
    COMPLEX_UNIT_PX = 0
    COMPLEX_UNIT_DIP = 1
    COMPLEX_UNIT_SP = 2

    @staticmethod
    def applyDimension(unit, value, metrics=None):
        # one dp is one point on ios, one sp the same
        return float(value)


class DisplayMetrics:
    density = 1.0
    scaledDensity = 1.0
    densityDpi = 160
    widthPixels = 0
    heightPixels = 0


import sys as _sys
import threading as _threading
from collections import OrderedDict as _OrderedDict

from java.lang import IllegalArgumentException as _IllegalArgumentException
from java.lang import Object as _Object


def _java_bytes(data):
    """the bytes of a byte[] of the vm, of a python bytes or of a str, as python bytes"""
    if isinstance(data, (bytes, bytearray)):
        return bytes(data)
    if isinstance(data, str):
        return data.encode("utf-8")
    return bytes(value & 0xFF for value in data)


def _to_array(data):
    from dexvm.jio import to_java_bytes
    return to_java_bytes(data)


class Log(_Object):
    """lines go to stderr as `P/tag: message`, the shape of logcat; the app keeps stderr in its log"""

    VERBOSE = 2
    DEBUG = 3
    INFO = 4
    WARN = 5
    ERROR = 6
    ASSERT = 7
    _LETTERS = {2: "V", 3: "D", 4: "I", 5: "W", 6: "E", 7: "A"}

    @staticmethod
    def println(priority, tag, message):
        line = "%s/%s: %s\n" % (Log._LETTERS.get(priority, "?"), tag, message)
        _sys.stderr.write(line)
        return len(line)

    @staticmethod
    def _log(priority, tag, message, error):
        text = "null" if message is None else str(message)
        if error is not None:
            text += "\n" + Log.getStackTraceString(error)
        return Log.println(priority, tag, text)

    @staticmethod
    def v(tag, message, error=None):
        return Log._log(2, tag, message, error)

    @staticmethod
    def d(tag, message, error=None):
        return Log._log(3, tag, message, error)

    @staticmethod
    def i(tag, message, error=None):
        return Log._log(4, tag, message, error)

    @staticmethod
    def w(tag, message, error=None):
        return Log._log(5, tag, message, error)

    @staticmethod
    def e(tag, message, error=None):
        return Log._log(6, tag, message, error)

    @staticmethod
    def wtf(tag, message, error=None):
        return Log._log(7, tag, message, error)

    @staticmethod
    def isLoggable(tag, level):
        return level >= Log.INFO

    @staticmethod
    def getStackTraceString(error):
        if error is None:
            return ""
        text = error.toString() if hasattr(error, "toString") else "%s: %s" % (type(error).__name__, error)
        cause = error.getCause() if hasattr(error, "getCause") else error.__cause__
        while cause is not None:
            text += "\nCaused by: " + (cause.toString() if hasattr(cause, "toString") else "%s: %s" % (type(cause).__name__, cause))
            cause = cause.getCause() if hasattr(cause, "getCause") else cause.__cause__
        return text


class Base64(_Object):
    DEFAULT = 0
    NO_PADDING = 1
    NO_WRAP = 2
    CRLF = 4
    URL_SAFE = 8
    NO_CLOSE = 16

    @staticmethod
    def _encode(data, flags):
        import base64
        raw = base64.urlsafe_b64encode(data) if flags & Base64.URL_SAFE else base64.b64encode(data)
        text = raw.decode("ascii")
        if flags & Base64.NO_PADDING:
            text = text.rstrip("=")
        if not flags & Base64.NO_WRAP:
            ending = "\r\n" if flags & Base64.CRLF else "\n"
            lines = [text[index:index + 76] for index in range(0, len(text), 76)]
            text = ending.join(lines) + (ending if lines else "")
        return text

    @staticmethod
    def encodeToString(data, first, second=None, third=None):
        if third is None:
            return Base64._encode(_java_bytes(data), first)
        return Base64._encode(_java_bytes(data)[first:first + second], third)

    @staticmethod
    def encode(data, first, second=None, third=None):
        return _to_array(Base64.encodeToString(data, first, second, third).encode("ascii"))

    @staticmethod
    def decode(data, first, second=None, third=None):
        import base64
        import binascii
        raw = _java_bytes(data)
        flags = first
        if third is not None:
            raw = raw[first:first + second]
            flags = third
        # android ignores whitespace and accepts missing padding, which python's strict decoder refuses
        raw = b"".join(raw.split())
        raw += b"=" * (-len(raw) % 4)
        try:
            decoded = base64.urlsafe_b64decode(raw) if flags & Base64.URL_SAFE else base64.b64decode(raw, validate=True)
        except (binascii.Error, ValueError) as error:
            raise _IllegalArgumentException("bad base-64") from error
        return _to_array(decoded)


class Pair(_Object):
    def __init__(self, first, second):
        self.first = first
        self.second = second

    @staticmethod
    def create(first, second):
        return Pair(first, second)

    def equals(self, other):
        return isinstance(other, Pair) and other.first == self.first and other.second == self.second

    def hashCode(self):
        return hash((self.first, self.second)) & 0x7FFFFFFF

    def toString(self):
        return "Pair{%s %s}" % (self.first, self.second)


class SparseArray(_Object):
    """an int to object map ordered by key"""

    def __init__(self, capacity=10):
        self._items = {}

    def put(self, key, value):
        self._items[key] = value

    append = put

    def get(self, key, fallback=None):
        return self._items.get(key, fallback)

    def delete(self, key):
        self._items.pop(key, None)

    remove = delete

    def clear(self):
        self._items.clear()

    def size(self):
        return len(self._items)

    def _keys(self):
        return sorted(self._items)

    def keyAt(self, index):
        keys = self._keys()
        if not 0 <= index < len(keys):
            raise IndexError("index %d, size %d" % (index, len(keys)))
        return keys[index]

    def valueAt(self, index):
        return self._items[self.keyAt(index)]

    def setValueAt(self, index, value):
        self._items[self.keyAt(index)] = value

    def indexOfKey(self, key):
        keys = self._keys()
        return keys.index(key) if key in self._items else -1

    def indexOfValue(self, value):
        for index, key in enumerate(self._keys()):
            if self._items[key] is value:
                return index
        return -1

    def contains(self, key):
        return key in self._items

    def clone(self):
        copy = type(self)()
        copy._items = dict(self._items)
        return copy


class SparseIntArray(SparseArray):
    def get(self, key, fallback=0):
        return self._items.get(key, fallback)


class SparseLongArray(SparseIntArray):
    pass


class SparseBooleanArray(SparseArray):
    def get(self, key, fallback=False):
        return self._items.get(key, fallback)


class LruCache(_Object):
    """a size-bounded map that drops the least recently used entry; sizeOf can be overridden and entryRemoved is called"""

    def __init__(self, max_size):
        if max_size <= 0:
            raise _IllegalArgumentException("maxSize <= 0")
        self._max = max_size
        self._map = _OrderedDict()
        self._size = 0
        self._lock = _threading.RLock()
        self._hits = self._misses = self._puts = self._evictions = 0

    def sizeOf(self, key, value):
        return 1

    def create(self, key):
        return None

    def entryRemoved(self, evicted, key, old, new):
        return None

    def get(self, key):
        if key is None:
            raise TypeError("key == null")
        with self._lock:
            if key in self._map:
                self._map.move_to_end(key)
                self._hits += 1
                return self._map[key]
            self._misses += 1
        created = self.create(key)
        if created is None:
            return None
        with self._lock:
            previous = self._map.get(key)
            if previous is None:
                self._store(key, created)
            else:
                created = previous
        if previous is not None:
            self.entryRemoved(False, key, created, previous)
            return previous
        self.trimToSize(self._max)
        return created

    def _store(self, key, value):
        self._map[key] = value
        self._size += self._measure(key, value)

    def _measure(self, key, value):
        size = self.sizeOf(key, value)
        if size < 0:
            raise _IllegalArgumentException("Negative size: %s=%s" % (key, value))
        return size

    def put(self, key, value):
        if key is None or value is None:
            raise TypeError("key == null || value == null")
        with self._lock:
            self._puts += 1
            previous = self._map.get(key)
            if key in self._map:
                self._size -= self._measure(key, previous)
            self._map[key] = value
            self._map.move_to_end(key)
            self._size += self._measure(key, value)
        if previous is not None:
            self.entryRemoved(False, key, previous, value)
        self.trimToSize(self._max)
        return previous

    def remove(self, key):
        with self._lock:
            if key not in self._map:
                return None
            previous = self._map.pop(key)
            self._size -= self._measure(key, previous)
        self.entryRemoved(False, key, previous, None)
        return previous

    def trimToSize(self, max_size):
        while True:
            with self._lock:
                if self._size < 0 or (not self._map and self._size != 0):
                    raise RuntimeError("sizeOf is reporting inconsistent results")
                if self._size <= max_size or not self._map:
                    return
                key, value = next(iter(self._map.items()))
                del self._map[key]
                self._size -= self._measure(key, value)
                self._evictions += 1
            self.entryRemoved(True, key, value, None)

    def evictAll(self):
        self.trimToSize(-1)

    def resize(self, max_size):
        if max_size <= 0:
            raise _IllegalArgumentException("maxSize <= 0")
        with self._lock:
            self._max = max_size
        self.trimToSize(max_size)

    def size(self):
        return self._size

    def maxSize(self):
        return self._max

    def hitCount(self):
        return self._hits

    def missCount(self):
        return self._misses

    def putCount(self):
        return self._puts

    def evictionCount(self):
        return self._evictions

    def snapshot(self):
        from dexvm.jmap import LinkedHashMap
        copy = LinkedHashMap()
        with self._lock:
            for key, value in self._map.items():
                copy.put(key, value)
        return copy


def _vm_map():
    from dexvm.jmap import HashMap
    return HashMap


def _make_array_map():
    from dexvm.jfunc import jequals
    HashMap = _vm_map()

    class ArrayMap(HashMap):
        """a Map with positions: the key and value at an index follow the iteration order of the map"""

        def __init__(self, source=None):
            HashMap.__init__(self, source if source is not None and not isinstance(source, int) else None)

        def _keys_list(self):
            from dexvm.jutil import iterate
            return list(iterate(self.keySet()))

        def keyAt(self, index):
            keys = self._keys_list()
            if not 0 <= index < len(keys):
                raise IndexError("index %d, size %d" % (index, len(keys)))
            return keys[index]

        def valueAt(self, index):
            return self.get(self.keyAt(index))

        def setValueAt(self, index, value):
            key = self.keyAt(index)
            old = self.get(key)
            self.put(key, value)
            return old

        def indexOfKey(self, key):
            keys = self._keys_list()
            for position, candidate in enumerate(keys):
                if jequals(candidate, key):
                    return position
            return -1

        def indexOfValue(self, value):
            for position, key in enumerate(self._keys_list()):
                held = self.get(key)
                if jequals(held, value):
                    return position
            return -1

        def removeAt(self, index):
            return self.remove(self.keyAt(index))

        def append(self, key, value):
            self.put(key, value)

        def ensureCapacity(self, n):
            return None

        def putAll(self, other):
            HashMap.putAll(self, other)

    return ArrayMap


def _make_array_set():
    from dexvm.jfunc import jequals
    from dexvm.jmap import HashSet

    class ArraySet(HashSet):
        def __init__(self, source=None):
            HashSet.__init__(self, source if source is not None and not isinstance(source, int) else None)

        def _list(self):
            from dexvm.jutil import iterate
            return list(iterate(self))

        def valueAt(self, index):
            items = self._list()
            if not 0 <= index < len(items):
                raise IndexError("index %d, size %d" % (index, len(items)))
            return items[index]

        def indexOf(self, value):
            for position, item in enumerate(self._list()):
                if jequals(item, value):
                    return position
            return -1

        def removeAt(self, index):
            value = self.valueAt(index)
            self.remove(value)
            return value

        def append(self, value):
            self.add(value)

        def ensureCapacity(self, n):
            return None

    return ArraySet


_cache = {}


def __getattr__(name):
    if name == "ArrayMap":
        return _cache.setdefault(name, _make_array_map())
    if name == "ArraySet":
        return _cache.setdefault(name, _make_array_set())
    raise AttributeError(name)


class LongSparseArray(SparseArray):
    pass


class LongSparseLongArray(SparseIntArray):
    pass


class Printer:
    """a program implements println(text)"""


class LogPrinter(_Object):
    def __init__(self, priority, tag):
        self._priority, self._tag = priority, tag

    def println(self, text):
        Log.println(self._priority, self._tag, text)


class PrintStreamPrinter(_Object):
    def __init__(self, stream):
        self._s = stream

    def println(self, text):
        self._s.println(text)


class PrintWriterPrinter(PrintStreamPrinter):
    pass


class StringBuilderPrinter(_Object):
    def __init__(self, builder):
        self._b = builder

    def println(self, text):
        self._b.append(text)
        self._b.append("\n")


class AndroidException(Exception):
    pass


class AndroidRuntimeException(RuntimeError):
    pass


class TimeFormatException(RuntimeError):
    pass


class MalformedJsonException(IOError):
    pass


class NoSuchPropertyException(RuntimeError):
    pass


class AttributeSet:
    """the attributes of a view in a layout file; there are no layout files, so no program is handed one"""


class LayoutDirection:
    LTR = 0
    RTL = 1
    INHERIT = 2
    LOCALE = 3


class StateSet:
    WILD_CARD = []
    NOTHING = [0]

    @staticmethod
    def isWildCard(states):
        return len(states) == 0 or states[0] == 0 and False

    @staticmethod
    def stateSetMatches(spec, states):
        if states is None:
            return all(s <= 0 for s in spec) if False else not any(s > 0 for s in spec)
        for item in spec:
            if item == 0:
                continue
            wanted = item > 0
            present = abs(item) in states if isinstance(states, (list, tuple, set)) else abs(item) == states
            if wanted != present:
                return False
        return True


class Patterns:
    import re as _re
    WEB_URL = _re.compile(r"(?:https?://|www\.)[^\s<>\"']+", _re.I)
    EMAIL_ADDRESS = _re.compile(r"[a-zA-Z0-9+._%\-]{1,256}@[a-zA-Z0-9][a-zA-Z0-9\-]{0,64}(?:\.[a-zA-Z0-9][a-zA-Z0-9\-]{0,25})+")
    PHONE = _re.compile(r"(?:\+?\d[\d\-\s().]{4,}\d)")
    IP_ADDRESS = _re.compile(r"(?:(?:25[0-5]|2[0-4][0-9]|[0-1]?[0-9]{1,2})\.){3}(?:25[0-5]|2[0-4][0-9]|[0-1]?[0-9]{1,2})")
    DOMAIN_NAME = _re.compile(r"(?:[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}\.)+[a-zA-Z]{2,63}")


class TimeUtils:
    @staticmethod
    def formatDuration(milliseconds, builder=None):
        text = "0" if milliseconds == 0 else ("%+d" % 0)
        seconds, ms = divmod(abs(int(milliseconds)), 1000)
        minutes, seconds = divmod(seconds, 60)
        hours, minutes = divmod(minutes, 60)
        days, hours = divmod(hours, 24)
        parts = []
        for value, unit in ((days, "d"), (hours, "h"), (minutes, "m"), (seconds, "s"), (ms, "ms")):
            if value:
                parts.append("%d%s" % (value, unit))
        text = ("-" if milliseconds < 0 else "+") + "".join(parts) if parts else "0"
        if builder is not None:
            builder.append(text)
        return text


class TimingLogger(_Object):
    def __init__(self, tag, label):
        self._tag, self._label, self._splits = tag, label, []
        self.reset()

    def reset(self, *_args):
        self._splits = [(_time_ns(), "begin")]

    def addSplit(self, label):
        self._splits.append((_time_ns(), label))

    def dumpToLog(self):
        Log.d(self._tag, self._label + ": begin")
        for (when, label), (previous, _) in zip(self._splits[1:], self._splits):
            Log.d(self._tag, "%s:      %d ms, %s" % (self._label, (when - previous) // 1000000, label))
        Log.d(self._tag, "%s: end, %d ms" % (self._label, (self._splits[-1][0] - self._splits[0][0]) // 1000000))


def _time_ns():
    import time
    return time.monotonic_ns()


class EventLog(_Object):
    @staticmethod
    def writeEvent(tag, *values):
        _sys.stderr.write("I/EventLog: %d %s\n" % (tag, values))
        return 0


class CloseGuard(_Object):
    def open(self, name):
        self._name = name

    def close(self):
        self._name = None

    def warnIfOpen(self):
        if getattr(self, "_name", None):
            Log.w("CloseGuard", "A resource was acquired at attached stack trace but never released: " + self._name)


class MutableBoolean(_Object):
    def __init__(self, value=False):
        self.value = value


class MutableInt(MutableBoolean):
    def __init__(self, value=0):
        self.value = value


MutableByte = MutableShort = MutableLong = MutableChar = MutableInt


class MutableFloat(MutableBoolean):
    def __init__(self, value=0.0):
        self.value = value


MutableDouble = MutableFloat


class Size(_Object):
    def __init__(self, width, height):
        self._w, self._h = int(width), int(height)

    def getWidth(self):
        return self._w

    def getHeight(self):
        return self._h

    @staticmethod
    def parseSize(text):
        for separator in ("*", "x"):
            if separator in text:
                w, h = text.split(separator, 1)
                try:
                    return Size(int(w), int(h))
                except ValueError:
                    break
        raise NumberFormatErrorFor(text)

    def equals(self, other):
        return isinstance(other, Size) and (other._w, other._h) == (self._w, self._h)

    def hashCode(self):
        return self._h ^ ((self._w << 16) | (self._w >> 16 & 0xFFFF))

    def toString(self):
        return "%dx%d" % (self._w, self._h)


class SizeF(_Object):
    def __init__(self, width, height):
        self._w, self._h = float(width), float(height)

    def getWidth(self):
        return self._w

    def getHeight(self):
        return self._h

    def equals(self, other):
        return isinstance(other, SizeF) and (other._w, other._h) == (self._w, self._h)

    def toString(self):
        return "%sx%s" % (self._w, self._h)


class NumberFormatErrorFor(ValueError):
    def __init__(self, text):
        ValueError.__init__(self, 'Invalid Size: "%s"' % text)


class Range(_Object):
    def __init__(self, lower, upper):
        if lower > upper:
            raise _IllegalArgumentException("lower must be less than or equal to upper")
        self._lo, self._hi = lower, upper

    @staticmethod
    def create(lower, upper):
        return Range(lower, upper)

    def getLower(self):
        return self._lo

    def getUpper(self):
        return self._hi

    def contains(self, value):
        if isinstance(value, Range):
            return self._lo <= value._lo and value._hi <= self._hi
        return self._lo <= value <= self._hi

    def clamp(self, value):
        return min(max(value, self._lo), self._hi)

    def intersect(self, other):
        lo, hi = max(self._lo, other._lo), min(self._hi, other._hi)
        if lo > hi:
            raise _IllegalArgumentException("ranges do not intersect")
        return Range(lo, hi)

    def extend(self, other):
        return Range(min(self._lo, other._lo), max(self._hi, other._hi))

    def equals(self, other):
        return isinstance(other, Range) and (other._lo, other._hi) == (self._lo, self._hi)

    def toString(self):
        return "[%s, %s]" % (self._lo, self._hi)


class Rational(_Object):
    NaN = None
    POSITIVE_INFINITY = None
    NEGATIVE_INFINITY = None
    ZERO = None

    def __init__(self, numerator, denominator):
        import math
        if denominator < 0:
            numerator, denominator = -numerator, -denominator
        if denominator == 0:
            self._n, self._d = (0, 0) if numerator == 0 else ((1, 0) if numerator > 0 else (-1, 0))
        else:
            g = math.gcd(abs(numerator), denominator) or 1
            self._n, self._d = numerator // g, denominator // g

    def getNumerator(self):
        return self._n

    def getDenominator(self):
        return self._d

    def isNaN(self):
        return self._d == 0 and self._n == 0

    def isInfinite(self):
        return self._d == 0 and self._n != 0

    def isFinite(self):
        return self._d != 0

    def isZero(self):
        return self._d != 0 and self._n == 0

    def doubleValue(self):
        if self._d == 0:
            return float("nan") if self._n == 0 else (float("inf") if self._n > 0 else float("-inf"))
        return self._n / self._d

    floatValue = doubleValue

    def intValue(self):
        return int(self.doubleValue()) if self._d else 0

    longValue = intValue

    @staticmethod
    def parseRational(text):
        if text == "NaN":
            return Rational.NaN
        if text in ("Infinity", "-Infinity"):
            return Rational.POSITIVE_INFINITY if text == "Infinity" else Rational.NEGATIVE_INFINITY
        for separator in (":", "/"):
            if separator in text:
                n, d = text.split(separator, 1)
                return Rational(int(n), int(d))
        raise NumberFormatErrorFor(text)

    def equals(self, other):
        return isinstance(other, Rational) and (other._n, other._d) == (self._n, self._d)

    def compareTo(self, other):
        a, b = self.doubleValue(), other.doubleValue()
        return (a > b) - (a < b)

    def toString(self):
        return "NaN" if self.isNaN() else ("Infinity" if self._d == 0 and self._n > 0 else ("-Infinity" if self._d == 0 else "%d/%d" % (self._n, self._d)))


Rational.NaN = Rational(0, 0)
Rational.POSITIVE_INFINITY = Rational(1, 0)
Rational.NEGATIVE_INFINITY = Rational(-1, 0)
Rational.ZERO = Rational(0, 1)


class Property(_Object):
    """a named value of an object: get(target) and set(target, value); a program extends it, or uses of(), FloatProperty and IntProperty"""

    def __init__(self, kind=None, name=None):
        self._kind, self._name = kind, name

    @staticmethod
    def of(owner, kind, name):
        return ReflectiveProperty(owner, kind, name)

    def getName(self):
        return self._name

    def getType(self):
        return self._kind

    def isReadOnly(self):
        return False

    def set(self, target, value):
        raise _IllegalArgumentException("property %s is read-only" % self._name)

    def get(self, target):
        raise NotImplementedError


class FloatProperty(Property):
    def __init__(self, name):
        Property.__init__(self, float, name)

    def set(self, target, value):
        self.setValue(target, value)


class IntProperty(Property):
    def __init__(self, name):
        Property.__init__(self, int, name)

    def set(self, target, value):
        self.setValue(target, value)


class ReflectiveProperty(Property):
    def __init__(self, owner, kind, name):
        Property.__init__(self, kind, name)
        capital = name[:1].upper() + name[1:]
        self._getter = next((n for n in ("get" + capital, "is" + capital, name) if hasattr(owner, n)), None)
        self._setter = "set" + capital if hasattr(owner, "set" + capital) else None
        if self._getter is None and self._setter is None:
            raise NoSuchPropertyException("No accessor method or field found for property with name " + name)

    def isReadOnly(self):
        return self._setter is None

    def get(self, target):
        return getattr(target, self._getter)()

    def set(self, target, value):
        if self._setter is None:
            raise _IllegalArgumentException("Property %s is read-only" % self._name)
        getattr(target, self._setter)(value)


class Base64InputStream(_Object):
    """decodes the base64 that an InputStream gives: the whole input is read on the first read"""

    def __init__(self, source, flags=0):
        self._source, self._flags, self._data, self._pos = source, flags, None, 0

    def _load(self):
        if self._data is None:
            raw = self._source.readAllBytes()
            decoded = Base64.decode(raw, self._flags)
            self._data = bytes(b & 0xFF for b in decoded)

    def read(self, buffer=None, offset=0, length=None):
        self._load()
        if buffer is None:
            if self._pos >= len(self._data):
                return -1
            self._pos += 1
            return self._data[self._pos - 1]
        length = len(buffer) - offset if length is None else length
        if self._pos >= len(self._data):
            return -1
        chunk = self._data[self._pos:self._pos + length]
        self._pos += len(chunk)
        buffer[offset:offset + len(chunk)] = [b - 256 if b > 127 else b for b in chunk]
        return len(chunk)

    def close(self):
        self._source.close()


class Base64OutputStream(_Object):
    """encodes what is written and writes the base64 to the sink when the stream is closed"""

    def __init__(self, sink, flags=0):
        self._sink, self._flags, self._buf = sink, flags, bytearray()

    def write(self, data, offset=0, length=None):
        if isinstance(data, int):
            self._buf.append(data & 0xFF)
        else:
            length = len(data) - offset if length is None else length
            self._buf += bytes(b & 0xFF for b in data[offset:offset + length])

    def flush(self):
        return None

    def close(self):
        text = Base64._encode(bytes(self._buf), self._flags).encode("ascii")
        array = _to_array(text)
        self._sink.write(array, 0, len(array))
        if not self._flags & Base64.NO_CLOSE:
            self._sink.close()


class AtomicFile(_Object):
    """a file that is replaced whole: startWrite() opens a temporary file, finishWrite() renames it over the file, failWrite() drops it"""

    def __init__(self, file):
        self._path = file.getPath()
        self._tmp = self._path + ".new"
        self._out = None

    def getBaseFile(self):
        from java.io import File
        return File(self._path)

    def startWrite(self, *_time):
        from java.io import FileOutputStream
        self._out = FileOutputStream(self._tmp)
        return self._out

    def finishWrite(self, stream):
        import os
        stream.flush()
        stream.close()
        os.replace(self._tmp, self._path)

    def failWrite(self, stream):
        import os
        try:
            stream.close()
        finally:
            if os.path.exists(self._tmp):
                os.remove(self._tmp)

    def openRead(self):
        from java.io import FileInputStream
        return FileInputStream(self._path)

    def readFully(self):
        stream = self.openRead()
        try:
            return stream.readAllBytes()
        finally:
            stream.close()

    def delete(self):
        import os
        for path in (self._path, self._tmp):
            if os.path.exists(path):
                os.remove(path)


class JsonToken(_Object):
    pass


for _index, _name in enumerate(("BEGIN_ARRAY", "END_ARRAY", "BEGIN_OBJECT", "END_OBJECT", "NAME", "STRING", "NUMBER", "BOOLEAN", "NULL", "END_DOCUMENT")):
    _token = JsonToken()
    _token._name, _token._ordinal = _name, _index
    _token.name = (lambda token: lambda: token._name)(_token)
    _token.toString = _token.name
    setattr(JsonToken, _name, _token)


class JsonReader(_Object):
    """a pull reader over a document that is parsed whole when the first token is asked for; the nesting is the one the document has"""

    def __init__(self, reader):
        self._reader = reader
        self._events = None
        self._pos = 0
        self._lenient = False

    def setLenient(self, flag):
        self._lenient = bool(flag)

    def isLenient(self):
        return self._lenient

    def _load(self):
        if self._events is not None:
            return
        import json
        chars = []
        while True:
            c = self._reader.read_char() if hasattr(self._reader, "read_char") else self._reader.read()
            if c == -1:
                break
            chars.append(chr(c))
        try:
            document = json.loads("".join(chars), parse_constant=lambda x: float(x.lower())) if chars else None
        except ValueError as error:
            raise MalformedJsonException(str(error))
        events = []

        def walk(value):
            if isinstance(value, dict):
                events.append(("BEGIN_OBJECT", None))
                for key, item in value.items():
                    events.append(("NAME", key))
                    walk(item)
                events.append(("END_OBJECT", None))
            elif isinstance(value, list):
                events.append(("BEGIN_ARRAY", None))
                for item in value:
                    walk(item)
                events.append(("END_ARRAY", None))
            elif value is None:
                events.append(("NULL", None))
            elif isinstance(value, bool):
                events.append(("BOOLEAN", value))
            elif isinstance(value, (int, float)):
                events.append(("NUMBER", value))
            else:
                events.append(("STRING", value))
        if document is not None:
            walk(document)
        events.append(("END_DOCUMENT", None))
        self._events = events

    def _peek_event(self):
        self._load()
        return self._events[self._pos]

    def peek(self):
        return getattr(JsonToken, self._peek_event()[0])

    def _expect(self, kind):
        event = self._peek_event()
        if event[0] != kind:
            raise IllegalStateExceptionFor("Expected %s but was %s" % (kind, event[0]))
        self._pos += 1
        return event[1]

    def beginObject(self):
        self._expect("BEGIN_OBJECT")

    def endObject(self):
        self._expect("END_OBJECT")

    def beginArray(self):
        self._expect("BEGIN_ARRAY")

    def endArray(self):
        self._expect("END_ARRAY")

    def hasNext(self):
        return self._peek_event()[0] not in ("END_OBJECT", "END_ARRAY", "END_DOCUMENT")

    def nextName(self):
        return self._expect("NAME")

    def nextString(self):
        event = self._peek_event()
        if event[0] == "NUMBER":
            self._pos += 1
            return str(event[1])
        return self._expect("STRING")

    def nextBoolean(self):
        return self._expect("BOOLEAN")

    def nextNull(self):
        self._expect("NULL")

    def nextInt(self):
        event = self._peek_event()
        if event[0] == "STRING":
            self._pos += 1
            return int(event[1])
        return int(self._expect("NUMBER"))

    nextLong = nextInt

    def nextDouble(self):
        event = self._peek_event()
        if event[0] == "STRING":
            self._pos += 1
            return float(event[1])
        return float(self._expect("NUMBER"))

    def skipValue(self):
        depth = 0
        while True:
            kind = self._peek_event()[0]
            if kind == "END_DOCUMENT":
                return
            self._pos += 1
            if kind in ("BEGIN_OBJECT", "BEGIN_ARRAY"):
                depth += 1
            elif kind in ("END_OBJECT", "END_ARRAY"):
                depth -= 1
            elif kind == "NAME":
                continue
            if depth <= 0:
                return

    def close(self):
        self._reader.close()


class IllegalStateExceptionFor(RuntimeError):
    pass


class _TextSink:
    """write(text) over a java Writer, which takes text through write_text in the vm and through write in a shim"""

    def __init__(self, writer):
        self._writer = writer

    def write(self, text):
        (self._writer.write_text if hasattr(self._writer, "write_text") else self._writer.write)(text)

    def flush(self):
        self._writer.flush()

    def close(self):
        self._writer.close()


class JsonWriter(_Object):
    def __init__(self, writer):
        self._w = _TextSink(writer)
        self._stack = []
        self._indent = ""
        self._lenient = False
        self._name = None
        self._first = True

    def setIndent(self, indent):
        self._indent = indent

    def setLenient(self, flag):
        self._lenient = bool(flag)

    def _newline(self):
        if self._indent:
            self._w.write("\n" + self._indent * len(self._stack))

    def _before(self):
        if self._stack:
            top = self._stack[-1]
            if top["kind"] == "object":
                if self._name is None:
                    raise IllegalStateExceptionFor("Nesting problem.")
                self._w.write(": " if self._indent else ":")
                self._name = None
                return
            if top["count"]:
                self._w.write(",")
            top["count"] += 1
            self._newline()

    def _open(self, kind, text):
        self._before()
        self._w.write(text)
        self._stack.append({"kind": kind, "count": 0})
        return self

    def _close(self, kind, text):
        if not self._stack or self._stack[-1]["kind"] != kind:
            raise IllegalStateExceptionFor("Nesting problem.")
        top = self._stack.pop()
        if top["count"]:
            self._newline()
        self._w.write(text)
        return self

    def beginObject(self):
        return self._open("object", "{")

    def endObject(self):
        return self._close("object", "}")

    def beginArray(self):
        return self._open("array", "[")

    def endArray(self):
        return self._close("array", "]")

    def name(self, name):
        if not self._stack or self._stack[-1]["kind"] != "object" or self._name is not None:
            raise IllegalStateExceptionFor("Nesting problem.")
        top = self._stack[-1]
        if top["count"]:
            self._w.write(",")
        top["count"] += 1
        self._newline()
        from dexvm.jjson import _quote
        self._w.write(_quote(name))
        self._name = name
        return self

    def value(self, value):
        from dexvm.jjson import _quote
        self._before()
        if value is None:
            self._w.write("null")
        elif isinstance(value, bool):
            self._w.write("true" if value else "false")
        elif isinstance(value, (int, float)):
            if isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))) and not self._lenient:
                raise _IllegalArgumentException("Numeric values must be finite, but was " + str(value))
            self._w.write(str(int(value)) if isinstance(value, float) and value == int(value) and abs(value) < 1e15 else repr(value) if isinstance(value, float) else str(value))
        else:
            self._w.write(_quote(str(value)))
        return self

    def nullValue(self):
        return self.value(None)

    def flush(self):
        self._w.flush()

    def close(self):
        if self._stack:
            raise IOError("Incomplete document")
        self._w.close()
