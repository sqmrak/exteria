"""java.util odds and ends: Properties, StringTokenizer, BitSet, Timer and TimerTask, EnumMap, EnumSet and the set that
Collections.newSetFromMap makes"""

import heapq
import itertools
import threading
import time

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jstring
from .jlang import Object, jstr
from .jmap import HashMap, AbstractSet, TreeMap, TreeSet
from .jutil import PyIterator, check_nonnull, iterate, no_such_element


class MapBackedSet(AbstractSet):
    """a Set whose elements are the keys of a Map"""

    def __init__(self, backing):
        self._m = backing

    @jmethod("size", "()I")
    def size(self):
        return self._m.size()

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return self._m.isEmpty()

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        return self._m.containsKey(item)

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        from .jlang import Boolean
        return 1 if self._m.put(item, Boolean.TRUE) is None else 0

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove(self, item):
        return 1 if self._m.remove(item) is not None else 0

    @jmethod("clear", "()V")
    def clear(self):
        self._m.clear()

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return self._m.keySet().iterator()


host_class("java.util.Collections$SetFromMap", interfaces=("java.util.Set",))(MapBackedSet)


@host_class("java.util.Properties", interfaces=("java.util.Map",), superclass="java.util.Hashtable")
class Properties(lookup_host("java.util.Hashtable").py):
    def __init__(self, defaults=None):
        HashMap.__init__(self)
        self._defaults = defaults

    @jmethod("<init>", "()V")
    def _init0(self):
        Properties.__init__(self)

    @jmethod("<init>", "(Ljava/util/Properties;)V")
    def _init1(self, defaults):
        Properties.__init__(self, defaults)

    @jmethod("setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;")
    def setProperty(self, key, value):
        return self.put(check_nonnull(key), check_nonnull(value))

    @jmethod("getProperty", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("getProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    def getProperty(self, key, fallback=None):
        value = self.get(key)
        if value.__class__ is not str:
            value = self._defaults.getProperty(key) if self._defaults is not None else None
        return fallback if value is None else value

    @jmethod("stringPropertyNames", "()Ljava/util/Set;")
    def stringPropertyNames(self):
        from .jmap import TreeSet as _Tree
        names = _Tree()
        for key in self._names():
            names.add(key)
        return names

    def _names(self):
        seen = []
        if self._defaults is not None:
            seen.extend(iterate(self._defaults.stringPropertyNames()))
        for key in iterate(self.keySet()):
            if key.__class__ is str and self.get(key).__class__ is str and key not in seen:
                seen.append(key)
        return seen

    @jmethod("propertyNames", "()Ljava/util/Enumeration;")
    def propertyNames(self):
        return PyIterator(self._names())

    @jmethod("load", "(Ljava/io/InputStream;)V")
    @jmethod("load", "(Ljava/io/Reader;)V")
    def load(self, source):
        if hasattr(source, "read_char"):
            chars = []
            while True:
                value = source.read_char()
                if value == -1:
                    break
                chars.append(chr(value))
            text = "".join(chars)
        else:
            text = bytes(b & 0xFF for b in source.readAllBytes()).decode("latin-1")
        for key, value in _parse_properties(text):
            self.put(jstr(key), jstr(value))

    @jmethod("store", "(Ljava/io/OutputStream;Ljava/lang/String;)V")
    @jmethod("store", "(Ljava/io/Writer;Ljava/lang/String;)V")
    def store(self, sink, comments):
        lines = []
        if comments is not None:
            lines.append("#" + comments)
        lines.append("#" + time.strftime("%a %b %d %H:%M:%S UTC %Y", time.gmtime()))
        for key in iterate(self.keySet()):
            lines.append(_escape(jstring(key), True) + "=" + _escape(jstring(self.get(key)), False))
        text = "\n".join(lines) + "\n"
        if hasattr(sink, "write_text"):
            sink.write_text(text)
        else:
            from .jio import to_java_bytes
            data = to_java_bytes(text.encode("latin-1", "backslashreplace"))
            sink.write(data, 0, len(data))
        sink.flush()


def _escape(text, key):
    out = []
    for index, char in enumerate(text):
        if char in "\\":
            out.append("\\\\")
        elif char == " " and (key or index == 0):
            out.append("\\ ")
        elif char in "=:#!" and key:
            out.append("\\" + char)
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif char == "\t":
            out.append("\\t")
        elif ord(char) > 126 or ord(char) < 32:
            out.append("\\u%04X" % ord(char))
        else:
            out.append(char)
    return "".join(out)


def _logical_lines(text):
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    pending = None
    for line in lines:
        if pending is None:
            line = line.lstrip(" \t\f")
            if not line or line[0] in "#!":
                continue
        else:
            line = pending + line.lstrip(" \t\f")
        slashes = len(line) - len(line.rstrip("\\"))
        if slashes % 2:
            pending = line[:-1]
            continue
        pending = None
        yield line
    if pending is not None:
        yield pending


def _unescape(text):
    out = []
    pos = 0
    while pos < len(text):
        char = text[pos]
        pos += 1
        if char != "\\" or pos >= len(text):
            out.append(char)
            continue
        char = text[pos]
        pos += 1
        if char == "u":
            digits = text[pos:pos + 4]
            if len(digits) < 4 or not all(c in "0123456789abcdefABCDEF" for c in digits):
                runtime.throw_new("java.lang.IllegalArgumentException", "Malformed \\uxxxx encoding.")
            out.append(chr(int(digits, 16)))
            pos += 4
        else:
            out.append({"t": "\t", "n": "\n", "r": "\r", "f": "\f"}.get(char, char))
    return "".join(out)


def _parse_properties(text):
    for line in _logical_lines(text):
        pos = 0
        while pos < len(line) and line[pos] not in "=: \t\f":
            pos += 2 if line[pos] == "\\" else 1
        key = line[:pos]
        rest = line[pos:].lstrip(" \t\f")
        if rest[:1] in ("=", ":"):
            rest = rest[1:].lstrip(" \t\f")
        yield _unescape(key), _unescape(rest)


@host_class("java.util.StringTokenizer", interfaces=("java.util.Enumeration",))
class StringTokenizer(Object):
    def __init__(self, text, delimiters=" \t\n\r\f", return_delims=False):
        self._text = check_nonnull(text)
        self._delims = delimiters
        self._ret = bool(return_delims)
        self._pos = 0

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Z)V")
    def _init(self, text, delimiters=" \t\n\r\f", return_delims=False):
        StringTokenizer.__init__(self, text, delimiters, return_delims)

    def _skip(self, pos):
        if self._ret:
            return pos
        while pos < len(self._text) and self._text[pos] in self._delims:
            pos += 1
        return pos

    def _scan(self, pos):
        start = pos
        while pos < len(self._text) and self._text[pos] not in self._delims:
            pos += 1
        if self._ret and pos == start and pos < len(self._text):
            pos += 1
        return pos

    @jmethod("hasMoreTokens", "()Z")
    @jmethod("hasMoreElements", "()Z")
    def hasMoreTokens(self):
        return 1 if self._skip(self._pos) < len(self._text) else 0

    @jmethod("nextToken", "()Ljava/lang/String;")
    @jmethod("nextToken", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("nextElement", "()Ljava/lang/Object;")
    def nextToken(self, delimiters=None):
        if delimiters is not None:
            self._delims = delimiters
        start = self._skip(self._pos)
        if start >= len(self._text):
            no_such_element()
        end = self._scan(start)
        self._pos = end
        return self._text[start:end]

    @jmethod("countTokens", "()I")
    def countTokens(self):
        count, pos = 0, self._pos
        while True:
            pos = self._skip(pos)
            if pos >= len(self._text):
                return count
            pos = self._scan(pos)
            count += 1


@host_class("java.util.BitSet", interfaces=("java.lang.Cloneable", "java.io.Serializable"))
class BitSet(Object):
    def __init__(self, size=64):
        if size < 0:
            runtime.throw_new("java.lang.NegativeArraySizeException", "nbits < 0: %d" % size)
        self._v = 0
        self._words = max(1, (size + 63) // 64)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, size=64):
        BitSet.__init__(self, size)

    @staticmethod
    def _check(index):
        if index < 0:
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "bitIndex < 0: %d" % index)

    @staticmethod
    def _range(start, end):
        if start < 0 or end < 0 or start > end:
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "fromIndex: %d, toIndex: %d" % (start, end))
        return ((1 << (end - start)) - 1) << start

    @jmethod("set", "(I)V")
    def set(self, first, second=None, third=None):
        """python callers: set(i), set(i, flag), set(from, to) and set(from, to, flag); dex callers reach the exact overloads"""
        if second is None:
            BitSet._check(first)
            self._v |= 1 << first
        elif third is None and isinstance(second, bool):
            self.set_flag(first, second)
        else:
            self.set_range(first, second, True if third is None else third)

    @jmethod("set", "(IZ)V")
    def set_flag(self, index, value):
        BitSet._check(index)
        self._v = self._v | (1 << index) if value else self._v & ~(1 << index)

    @jmethod("set", "(II)V")
    @jmethod("set", "(IIZ)V")
    def set_range(self, start, end, value=1):
        mask = BitSet._range(start, end)
        self._v = self._v | mask if value else self._v & ~mask

    @jmethod("clear", "()V")
    @jmethod("clear", "(I)V")
    @jmethod("clear", "(II)V")
    def clear(self, first=None, second=None):
        if first is None:
            self._v = 0
        elif second is None:
            BitSet._check(first)
            self._v &= ~(1 << first)
        else:
            self._v &= ~BitSet._range(first, second)

    @jmethod("flip", "(I)V")
    @jmethod("flip", "(II)V")
    def flip(self, first, second=None):
        BitSet._check(first)
        self._v ^= (1 << first) if second is None else BitSet._range(first, second)

    @jmethod("get", "(I)Z")
    @jmethod("get", "(II)Ljava/util/BitSet;")
    def get(self, first, second=None):
        BitSet._check(first)
        if second is None:
            return 1 if self._v >> first & 1 else 0
        result = BitSet()
        result._v = (self._v >> first) & ((1 << (second - first)) - 1) if second >= first else 0
        return result

    @jmethod("cardinality", "()I")
    def cardinality(self):
        return bin(self._v).count("1")

    @jmethod("length", "()I")
    def length(self):
        return self._v.bit_length()

    @jmethod("size", "()I")
    def size(self):
        return max(self._words, (self._v.bit_length() + 63) // 64) * 64

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 0 if self._v else 1

    @jmethod("nextSetBit", "(I)I")
    def nextSetBit(self, start):
        BitSet._check(start)
        rest = self._v >> start
        if not rest:
            return -1
        return start + ((rest & -rest).bit_length() - 1)

    @jmethod("nextClearBit", "(I)I")
    def nextClearBit(self, start):
        BitSet._check(start)
        rest = ~(self._v >> start)
        return start + ((rest & -rest).bit_length() - 1)

    @jmethod("previousSetBit", "(I)I")
    def previousSetBit(self, start):
        if start < 0:
            return -1
        masked = self._v & ((1 << (start + 1)) - 1)
        return masked.bit_length() - 1

    @jmethod("and", "(Ljava/util/BitSet;)V")
    def and_(self, other):
        self._v &= other._v

    @jmethod("or", "(Ljava/util/BitSet;)V")
    def or_(self, other):
        self._v |= other._v

    @jmethod("xor", "(Ljava/util/BitSet;)V")
    def xor(self, other):
        self._v ^= other._v

    @jmethod("andNot", "(Ljava/util/BitSet;)V")
    def andNot(self, other):
        self._v &= ~other._v

    @jmethod("intersects", "(Ljava/util/BitSet;)Z")
    def intersects(self, other):
        return 1 if self._v & other._v else 0

    @jmethod("toByteArray", "()[B")
    def toByteArray(self):
        from .jio import to_java_bytes
        return to_java_bytes(self._v.to_bytes((self._v.bit_length() + 7) // 8, "little"))

    @jmethod("toLongArray", "()[J")
    def toLongArray(self):
        array = runtime.new_array("[J", 0)
        for index in range((self._v.bit_length() + 63) // 64):
            array.append(runtime.wrap64(self._v >> (64 * index) & 0xFFFFFFFFFFFFFFFF))
        return array

    @jstatic("valueOf", "([B)Ljava/util/BitSet;")
    @jstatic("valueOf", "([J)Ljava/util/BitSet;")
    def valueOf(array):
        result = BitSet()
        if array.jtype.descriptor == "[B":
            result._v = int.from_bytes(bytes(b & 0xFF for b in array), "little")
        else:
            for index, word in enumerate(array):
                result._v |= (word & 0xFFFFFFFFFFFFFFFF) << (64 * index)
        return result

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        copy = BitSet()
        copy._v, copy._words = self._v, self._words
        return copy

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, BitSet) and other._v == self._v else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        h = 1234
        words = [self._v >> (64 * i) & 0xFFFFFFFFFFFFFFFF for i in range((self._v.bit_length() + 63) // 64)]
        for i in range(len(words) - 1, -1, -1):
            h ^= words[i] * (i + 1)
        h &= 0xFFFFFFFFFFFFFFFF
        return runtime.wrap32((h >> 32) ^ h)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "{" + ", ".join(str(i) for i in range(self._v.bit_length()) if self._v >> i & 1) + "}"


@host_class("java.util.TimerTask", interfaces=("java.lang.Runnable",))
class TimerTask(Object):
    _cancelled = False
    _scheduled = False
    _last = 0
    _period = 0

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("run", "()V")
    def run(self):
        return None

    @jmethod("cancel", "()Z")
    def cancel(self):
        was = self._scheduled and not self._cancelled
        self._cancelled = True
        return 1 if was else 0

    @jmethod("scheduledExecutionTime", "()J")
    def scheduledExecutionTime(self):
        return self._last


@host_class("java.util.Timer")
class Timer(Object):
    """one thread that runs the tasks in the order of their times; a task that throws ends the timer, as in java"""

    _counter = itertools.count()

    def __init__(self, first=None, second=None):
        name = first if isinstance(first, str) else "Timer-%d" % next(Timer._counter)
        daemon = bool(second if second is not None else (first if isinstance(first, (bool, int)) and first is not None
                                                          and not isinstance(first, str) else False))
        self._heap = []
        self._cond = threading.Condition()
        self._dead = False
        self._seq = itertools.count()
        self._thread = threading.Thread(target=self._loop, name=name, daemon=daemon)
        self._thread.start()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Z)V")
    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Z)V")
    def _init(self, first=None, second=None):
        Timer.__init__(self, first, second)

    def _loop(self):
        while True:
            with self._cond:
                while True:
                    if self._dead and not self._heap:
                        return
                    if self._dead:
                        self._heap.clear()
                        return
                    while self._heap and self._heap[0][2]._cancelled:
                        heapq.heappop(self._heap)
                    if not self._heap:
                        self._cond.wait()
                        continue
                    due, _, task = self._heap[0]
                    wait = due - time.time()
                    if wait > 0:
                        self._cond.wait(wait)
                        continue
                    heapq.heappop(self._heap)
                    if task._period:
                        task._last = int(due * 1000)
                        nxt = due + task._period / 1000.0 if task._fixed else time.time() + task._period / 1000.0
                        heapq.heappush(self._heap, (nxt, next(self._seq), task))
                    break
            task._last = int(due * 1000)
            try:
                task.run()
            except BaseException:
                with self._cond:
                    self._dead = True
                    self._heap.clear()
                raise

    def _add(self, task, delay, period, fixed):
        if delay < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Negative delay.")
        if period < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Non-positive period.")
        with self._cond:
            if self._dead:
                runtime.throw_new("java.lang.IllegalStateException", "Timer already cancelled.")
            if task._scheduled or task._cancelled:
                runtime.throw_new("java.lang.IllegalStateException", "Task already scheduled or cancelled")
            task._scheduled = True
            task._period = period
            task._fixed = fixed
            heapq.heappush(self._heap, (time.time() + delay / 1000.0, next(self._seq), task))
            self._cond.notify()

    @jmethod("schedule", "(Ljava/util/TimerTask;J)V")
    @jmethod("schedule", "(Ljava/util/TimerTask;JJ)V")
    def schedule(self, task, delay, period=0):
        self._add(task, delay, period, False)

    @jmethod("scheduleAtFixedRate", "(Ljava/util/TimerTask;JJ)V")
    def scheduleAtFixedRate(self, task, delay, period):
        if period <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Non-positive period.")
        self._add(task, delay, period, True)

    @jmethod("cancel", "()V")
    def cancel(self):
        with self._cond:
            self._dead = True
            self._heap.clear()
            self._cond.notify()

    @jmethod("purge", "()I")
    def purge(self):
        with self._cond:
            before = len(self._heap)
            self._heap[:] = [e for e in self._heap if not e[2]._cancelled]
            heapq.heapify(self._heap)
            return before - len(self._heap)


class _Ordinal(Object):
    def compare(self, a, b):
        return a._ordinal - b._ordinal


def _constants(enum_class):
    constants = check_nonnull(enum_class).getEnumConstants()
    if constants is None:
        runtime.throw_new("java.lang.ClassCastException", enum_class.getName() + " not an enum")
    return list(constants)


@host_class("java.util.EnumMap", interfaces=("java.util.Map",))
class EnumMap(TreeMap):
    def __init__(self, source=None):
        TreeMap.__init__(self, _Ordinal())
        if source is not None and not hasattr(source, "getEnumConstants"):
            for entry in iterate(source.entrySet()):
                self.put(entry.getKey(), entry.getValue())

    @jmethod("<init>", "(Ljava/lang/Class;)V")
    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init(self, source):
        EnumMap.__init__(self, source)

    def put(self, key, value):
        return TreeMap.put(self, check_nonnull(key), value)


@host_class("java.util.EnumSet", interfaces=("java.util.Set",))
class EnumSet(TreeSet):
    def __init__(self):
        TreeSet.__init__(self, _Ordinal())

    @jstatic("noneOf", "(Ljava/lang/Class;)Ljava/util/EnumSet;")
    def noneOf(enum_class):
        _constants(enum_class)
        result = EnumSet()
        result._class = enum_class
        return result

    @jstatic("allOf", "(Ljava/lang/Class;)Ljava/util/EnumSet;")
    def allOf(enum_class):
        result = EnumSet.noneOf(enum_class)
        for item in _constants(enum_class):
            result.add(item)
        return result

    @jstatic("of", "(Ljava/lang/Enum;)Ljava/util/EnumSet;")
    @jstatic("of", "(Ljava/lang/Enum;Ljava/lang/Enum;)Ljava/util/EnumSet;")
    @jstatic("of", "(Ljava/lang/Enum;Ljava/lang/Enum;Ljava/lang/Enum;)Ljava/util/EnumSet;")
    @jstatic("of", "(Ljava/lang/Enum;Ljava/lang/Enum;Ljava/lang/Enum;Ljava/lang/Enum;)Ljava/util/EnumSet;")
    @jstatic("of", "(Ljava/lang/Enum;[Ljava/lang/Enum;)Ljava/util/EnumSet;")
    def of(first, *rest):
        result = EnumSet.noneOf(check_nonnull(first).getDeclaringClass())
        for item in (first,) + tuple(x for r in rest for x in (r if isinstance(r, list) else [r])):
            result.add(item)
        return result

    @jstatic("range", "(Ljava/lang/Enum;Ljava/lang/Enum;)Ljava/util/EnumSet;")
    def range(low, high):
        if low._ordinal > high._ordinal:
            runtime.throw_new("java.lang.IllegalArgumentException", "%s > %s" % (low._name, high._name))
        result = EnumSet.noneOf(low.getDeclaringClass())
        for item in _constants(low.getDeclaringClass()):
            if low._ordinal <= item._ordinal <= high._ordinal:
                result.add(item)
        return result

    @jstatic("copyOf", "(Ljava/util/Collection;)Ljava/util/EnumSet;")
    @jstatic("copyOf", "(Ljava/util/EnumSet;)Ljava/util/EnumSet;")
    def copyOf(source):
        items = list(iterate(source))
        if not items:
            if hasattr(source, "_class"):
                return EnumSet.noneOf(source._class)
            runtime.throw_new("java.lang.IllegalArgumentException", "Collection is empty")
        result = EnumSet.noneOf(items[0].getDeclaringClass())
        for item in items:
            result.add(item)
        return result

    @jstatic("complementOf", "(Ljava/util/EnumSet;)Ljava/util/EnumSet;")
    def complementOf(source):
        result = EnumSet.noneOf(source._class)
        for item in _constants(source._class):
            if not source.contains(item):
                result.add(item)
        return result

    def clone(self):
        copy = EnumSet.noneOf(self._class)
        for item in iterate(self):
            copy.add(item)
        return copy
