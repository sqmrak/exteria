"""more of the public java api that the other library modules leave out: java.util.Spliterator and StreamSupport, the
annotation enums, Scanner, AbstractSequentialList, SimpleTimeZone, the missing java.util.concurrent classes and field
updaters, InheritableThreadLocal, permissions, the elliptic curve and PSS key specs, Destroyable, SNI names and
ServerSocketFactory. each class does what the jdk class does; tests/fixtures/dex/src/Api2.java prints the same text on a jvm"""

import itertools
import re
import threading
import time

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jequals, jhash
from .jlang import Object, jstr
from .jtimeapi import _make_enum
from .jutil import AbstractCollection, AbstractList, AbstractQueue, PyIterator, check_nonnull, iterate, no_such_element


def _taken(name):
    from . import api
    return name in api._classes or api._lazy.get(name, "dexvm.jmore") != "dexvm.jmore"


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        if not _taken(name):
            host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


def _interfaces(names, parents=()):
    for name in names.split():
        if not _taken(name):
            host_class(name, interface=True, interfaces=tuple(parents))(
                type(name.rsplit(".", 1)[1], (), {"__slots__": ()}))


def _seconds(timeout, unit):
    return unit.toNanos(timeout) / 1e9


_define("""
java.lang.annotation.AnnotationFormatError java.lang.Error
java.lang.annotation.AnnotationTypeMismatchException java.lang.RuntimeException
javax.security.auth.DestroyFailedException java.lang.Exception
""")
_interfaces("""java.lang.annotation.Retention java.lang.annotation.Target java.lang.annotation.Documented
java.lang.annotation.Inherited java.lang.annotation.Repeatable java.lang.annotation.Native""",
            ("java.lang.annotation.Annotation",))

_interfaces("""dalvik.annotation.AnnotationDefault dalvik.annotation.EnclosingClass dalvik.annotation.EnclosingMethod
dalvik.annotation.InnerClass dalvik.annotation.MemberClasses dalvik.annotation.MethodParameters dalvik.annotation.NestHost
dalvik.annotation.NestMembers dalvik.annotation.PermittedSubclasses dalvik.annotation.Record dalvik.annotation.Signature
dalvik.annotation.SourceDebugExtension dalvik.annotation.Throws dalvik.annotation.optimization.CriticalNative
dalvik.annotation.optimization.FastNative dalvik.annotation.optimization.NeverCompile dalvik.annotation.optimization.NeverInline""",
            ("java.lang.annotation.Annotation",))

ElementType = _make_enum("java.lang.annotation.ElementType", [
    "TYPE", "FIELD", "METHOD", "PARAMETER", "CONSTRUCTOR", "LOCAL_VARIABLE", "ANNOTATION_TYPE", "PACKAGE",
    "TYPE_PARAMETER", "TYPE_USE", "MODULE", "RECORD_COMPONENT"])
RetentionPolicy = _make_enum("java.lang.annotation.RetentionPolicy", ["SOURCE", "CLASS", "RUNTIME"])
ResolverStyle = _make_enum("java.time.format.ResolverStyle", ["STRICT", "SMART", "LENIENT"])
SignStyle = _make_enum("java.time.format.SignStyle", ["NORMAL", "ALWAYS", "NEVER", "NOT_NEGATIVE", "EXCEEDS_PAD"])


@host_class("java.util.Spliterator", interface=True)
class Spliterator:
    ORDERED, DISTINCT, SORTED, SIZED, NONNULL, IMMUTABLE, CONCURRENT, SUBSIZED = 16, 1, 4, 64, 256, 1024, 4096, 16384
    __slots__ = ()

    @jmethod("getExactSizeIfKnown", "()J")
    def getExactSizeIfKnown(self):
        return self.estimateSize() if self.characteristics() & Spliterator.SIZED else -1

    @jmethod("hasCharacteristics", "(I)Z")
    def hasCharacteristics(self, mask):
        return 1 if self.characteristics() & mask == mask else 0

    @jmethod("getComparator", "()Ljava/util/Comparator;")
    def getComparator(self):
        runtime.throw_new("java.lang.IllegalStateException", None)

    @jmethod("forEachRemaining", "(Ljava/util/function/Consumer;)V")
    def forEachRemaining(self, action):
        while self.tryAdvance(action):
            pass

    @jmethod("trySplit", "()Ljava/util/Spliterator;")
    def trySplit(self):
        return None


class _Sink(Object):
    """the Consumer a tryAdvance fills"""

    def __init__(self):
        self.value = None
        self.full = False

    def accept(self, value):
        self.value = value
        self.full = True


@host_class("java.util.Spliterators$IteratorSpliterator", interfaces=("java.util.Spliterator",))
class IteratorSpliterator(Object):
    def __init__(self, iterator, size, flags):
        self._it = iterator
        self._size = size
        self._flags = flags | (Spliterator.SIZED | Spliterator.SUBSIZED if size >= 0 else 0)
        self._known = size >= 0

    def tryAdvance(self, action):
        check_nonnull(action)
        if self._it.hasNext():
            action.accept(self._it.next())
            if self._known:
                self._size -= 1
            return 1
        return 0

    def forEachRemaining(self, action):
        check_nonnull(action)
        while self._it.hasNext():
            action.accept(self._it.next())
            if self._known:
                self._size -= 1

    def trySplit(self):
        return None

    def estimateSize(self):
        return self._size if self._known else 0x7FFFFFFFFFFFFFFF

    def characteristics(self):
        return self._flags

    def getExactSizeIfKnown(self):
        return self._size if self._known else -1

    def hasCharacteristics(self, mask):
        return 1 if self._flags & mask == mask else 0

    def getComparator(self):
        runtime.throw_new("java.lang.IllegalStateException", None)


@host_class("java.util.Spliterators$AbstractSpliterator", interfaces=("java.util.Spliterator",))
class AbstractSpliterator(Object):
    """the base a program extends: it supplies tryAdvance, this class the rest"""

    def __init__(self, size=0x7FFFFFFFFFFFFFFF, flags=0):
        self._size = size
        self._flags = flags

    @jmethod("<init>", "(JI)V")
    def _init(self, size, flags):
        AbstractSpliterator.__init__(self, size, flags | Spliterator.SUBSIZED if flags & Spliterator.SIZED else flags)

    @jmethod("trySplit", "()Ljava/util/Spliterator;")
    def trySplit(self):
        return None

    @jmethod("estimateSize", "()J")
    def estimateSize(self):
        return self._size

    @jmethod("characteristics", "()I")
    def characteristics(self):
        return self._flags

    @jmethod("forEachRemaining", "(Ljava/util/function/Consumer;)V")
    def forEachRemaining(self, action):
        while self.tryAdvance(action):
            pass

    @jmethod("getExactSizeIfKnown", "()J")
    def getExactSizeIfKnown(self):
        return self._size if self._flags & Spliterator.SIZED else -1

    @jmethod("hasCharacteristics", "(I)Z")
    def hasCharacteristics(self, mask):
        return 1 if self.characteristics() & mask == mask else 0

    @jmethod("getComparator", "()Ljava/util/Comparator;")
    def getComparator(self):
        runtime.throw_new("java.lang.IllegalStateException", None)


class _SpliteratorIterator(Object):
    """Spliterators.iterator: a java Iterator over a Spliterator"""

    def __init__(self, spliterator):
        self._s = spliterator
        self._sink = _Sink()
        self._ready = False

    def hasNext(self):
        if not self._ready:
            self._sink.full = False
            self._ready = bool(self._s.tryAdvance(self._sink))
        return 1 if self._ready else 0

    def next(self):
        if not self.hasNext():
            no_such_element()
        self._ready = False
        return self._sink.value


host_class("java.util.Spliterators$Adapter", interfaces=("java.util.Iterator",))(_SpliteratorIterator)


@host_class("java.util.Spliterators", final=True)
class Spliterators(Object):
    @jstatic("emptySpliterator", "()Ljava/util/Spliterator;")
    def emptySpliterator():
        return IteratorSpliterator(PyIterator([]), 0, 0)

    @jstatic("spliterator", "(Ljava/util/Collection;I)Ljava/util/Spliterator;")
    def spliterator_collection(collection, flags):
        return IteratorSpliterator(check_nonnull(collection).iterator(), collection.size(), flags)

    @jstatic("spliterator", "(Ljava/util/Iterator;JI)Ljava/util/Spliterator;")
    def spliterator_iterator(iterator, size, flags):
        return IteratorSpliterator(check_nonnull(iterator), size, flags)

    @jstatic("spliterator", "([Ljava/lang/Object;I)Ljava/util/Spliterator;")
    def spliterator_array(array, flags):
        return IteratorSpliterator(PyIterator(list(check_nonnull(array))), len(array), flags)

    @jstatic("spliteratorUnknownSize", "(Ljava/util/Iterator;I)Ljava/util/Spliterator;")
    def spliteratorUnknownSize(iterator, flags):
        return IteratorSpliterator(check_nonnull(iterator), -1, flags)

    @jstatic("iterator", "(Ljava/util/Spliterator;)Ljava/util/Iterator;")
    def iterator(spliterator):
        return _SpliteratorIterator(check_nonnull(spliterator))


@host_class("java.util.stream.StreamSupport", final=True)
class StreamSupport(Object):
    @jstatic("stream", "(Ljava/util/Spliterator;Z)Ljava/util/stream/Stream;")
    def stream(spliterator, parallel):
        from .jstream import BaseStream
        check_nonnull(spliterator)

        def pull():
            sink = _Sink()
            while True:
                sink.full = False
                if not spliterator.tryAdvance(sink):
                    return
                yield sink.value
        return BaseStream.from_items(pull(), "obj")

    @jstatic("stream", "(Ljava/util/function/Supplier;IZ)Ljava/util/stream/Stream;")
    def stream_supplier(supplier, characteristics, parallel):
        return StreamSupport.stream(supplier.get(), parallel)


def _default_spliterator(self):
    flags = Spliterator.SIZED | Spliterator.SUBSIZED if hasattr(self, "size") else 0
    if hasattr(self, "size"):
        return IteratorSpliterator(self.iterator(), self.size(), 0)
    return IteratorSpliterator(self.iterator(), -1, 0)


for _name in ("java.lang.Iterable", "java.util.Collection"):
    _py = lookup_host(_name).py
    if "spliterator" not in vars(_py):
        _py.spliterator = jmethod("spliterator", "()Ljava/util/Spliterator;")(_default_spliterator)


@host_class("java.lang.InheritableThreadLocal")
class InheritableThreadLocal(lookup_host("java.lang.ThreadLocal").py):
    """a thread started while this one holds a value gets childValue(value) as its starting value"""

    _all = None

    def __init__(self):
        lookup_host("java.lang.ThreadLocal").py.__init__(self)
        import weakref
        if InheritableThreadLocal._all is None:
            InheritableThreadLocal._all = weakref.WeakSet()
            runtime.THREAD_START_HOOKS.append(InheritableThreadLocal._capture)
        InheritableThreadLocal._all.add(self)

    @jmethod("<init>", "()V")
    def _init(self):
        InheritableThreadLocal.__init__(self)

    @jmethod("childValue", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def childValue(self, parent):
        return parent

    @staticmethod
    def _capture():
        held = [(local, local.childValue(local._local.value)) for local in list(InheritableThreadLocal._all)
                if hasattr(local._local, "value")]

        def apply():
            for local, value in held:
                local._local.value = value
        return apply


@host_class("java.util.AbstractSequentialList")
class AbstractSequentialList(AbstractList):
    """a list a program writes by giving listIterator(index) and size(): the indexed operations walk that iterator"""

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("get", "(I)Ljava/lang/Object;")
    def get(self, index):
        iterator = self.listIterator(index)
        if not iterator.hasNext():
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "Index: %d" % index)
        return iterator.next()

    @jmethod("set", "(ILjava/lang/Object;)Ljava/lang/Object;")
    def set(self, index, item):
        iterator = self.listIterator(index)
        old = iterator.next()
        iterator.set(item)
        return old

    @jmethod("add", "(ILjava/lang/Object;)V")
    def add_at(self, index, item):
        self.listIterator(index).add(item)

    @jmethod("remove", "(I)Ljava/lang/Object;")
    def remove_at(self, index):
        iterator = self.listIterator(index)
        old = iterator.next()
        iterator.remove()
        return old

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return self.listIterator(0)

    @jmethod("listIterator", "()Ljava/util/ListIterator;")
    def listIterator_start(self):
        return self.listIterator(0)


@host_class("java.util.FormattableFlags", final=True)
class FormattableFlags(Object):
    LEFT_JUSTIFY, UPPERCASE, ALTERNATE = 1, 2, 4


def _input_mismatch(message=None):
    runtime.throw_new("java.util.InputMismatchException", message)


class _OutOfRange(Exception):
    """a token that is an integer but does not fit the type asked for: its text is the message of the java exception"""


_DEFAULT_DELIMITER = r"\p{javaWhitespace}+"
_CHUNK = 1024


@host_class("java.util.Scanner", interfaces=("java.util.Iterator", "java.io.Closeable"))
class Scanner(Object):
    """tokens and lines of a string, a file, a stream or a reader. a stream is read a block at a time as the scanner needs
    it. numbers follow the english locale: a plus or minus sign, digit groups of three after a comma"""

    def __init__(self, source, charset=None):
        from .jtext import Pattern
        self._Pattern = Pattern
        self._buf = ""
        self._pos = 0
        self._reader = None
        self._eof = True
        self._closed = False
        self._radix = 10
        self._delim = Pattern(_DEFAULT_DELIMITER, 0)
        self._source = source
        self._error = None
        if isinstance(source, str):
            self._buf = source
        elif hasattr(source, "read") and hasattr(source, "ready"):
            self._reader = source
            self._eof = False
        elif hasattr(source, "getAbsolutePath") or hasattr(source, "toFile"):
            from .jio import FileInputStream, InputStreamReader, File
            path = source if hasattr(source, "getAbsolutePath") else File(source.toString())
            self._reader = InputStreamReader(FileInputStream(path))
            self._eof = False
        else:
            from .jio import InputStreamReader
            self._reader = InputStreamReader(check_nonnull(source)) if charset is None else \
                InputStreamReader(source, charset)
            self._eof = False

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/lang/Readable;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    @jmethod("<init>", "(Ljava/nio/file/Path;)V")
    def _init(self, source):
        Scanner.__init__(self, check_nonnull(source))

    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/nio/charset/Charset;)V")
    def _init_charset(self, source, charset):
        Scanner.__init__(self, check_nonnull(source), charset)

    # input

    def _check(self):
        if self._closed:
            runtime.throw_new("java.lang.IllegalStateException", "Scanner closed")

    def _more(self):
        """one more block of input; False at the end"""
        if self._eof:
            return False
        array = runtime.new_array("[C", _CHUNK)
        count = self._reader.read(array, 0, _CHUNK)
        if count is None or count < 0:
            self._eof = True
            return False
        self._buf = self._buf[self._pos:] + "".join(chr(c) for c in array[:count])
        self._pos = 0
        return True

    def _token_bounds(self):
        """(start, end) of the next token in the buffer, reading as far as the token needs; None when there is none"""
        self._check()
        while True:
            start = self._pos
            match = self._delim._re.match(self._buf, start)
            if match and match.end() > start:
                start = match.end()
            if start >= len(self._buf):
                if self._more():
                    continue
                return None
            end = self._find_end(start)
            if end >= len(self._buf) and not self._eof and self._more():
                continue
            return (start, end)

    def _find_end(self, start):
        found = self._delim._re.search(self._buf, start)
        while found is not None and found.end() == found.start():
            found = self._delim._re.search(self._buf, found.end() + 1) if found.end() + 1 <= len(self._buf) else None
        return found.start() if found is not None else len(self._buf)

    # tokens

    def hasNext(self, pattern=None):
        bounds = self._token_bounds()
        if bounds is None:
            return 0
        if pattern is None:
            return 1
        return 1 if self._pattern(pattern)._re.fullmatch(self._buf[bounds[0]:bounds[1]]) else 0

    def _pattern(self, pattern):
        return self._Pattern(pattern, 0) if isinstance(pattern, str) else pattern

    def next(self, pattern=None):
        bounds = self._token_bounds()
        if bounds is None:
            no_such_element()
        token = self._buf[bounds[0]:bounds[1]]
        if pattern is not None and not self._pattern(pattern)._re.fullmatch(token):
            _input_mismatch()
        self._pos = bounds[1]
        return jstr(token)

    def _typed(self, parse):
        bounds = self._token_bounds()
        if bounds is None:
            no_such_element()
        token = self._buf[bounds[0]:bounds[1]]
        try:
            value = parse(token)
        except _OutOfRange as error:
            _input_mismatch(str(error))
        if value is None:
            _input_mismatch()
        self._pos = bounds[1]
        return value

    def _has_typed(self, parse):
        bounds = self._token_bounds()
        if bounds is None:
            return 0
        try:
            return 1 if parse(self._buf[bounds[0]:bounds[1]]) is not None else 0
        except _OutOfRange:
            return 0

    def _integer(self, bits, radix=None):
        radix = self._radix if radix is None else radix
        digits = "0123456789abcdefghijklmnopqrstuvwxyz"[:radix]

        def parse(token):
            text = token
            sign = 1
            if text[:1] in "+-" and len(text) > 1:
                sign = -1 if text[0] == "-" else 1
                text = text[1:]
            if radix == 10 and re.fullmatch(r"\d{1,3}(,\d{3})+", text):
                text = text.replace(",", "")
            if not text or any(c.lower() not in digits for c in text):
                return None
            value = sign * int(text, radix)
            if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
                raise _OutOfRange("For input string: \"%s\"%s" % (token, "" if radix == 10 else " under radix %d" % radix))
            return value
        return parse

    @jmethod("nextInt", "()I")
    @jmethod("nextInt", "(I)I")
    def nextInt(self, radix=None):
        return self._typed(self._integer(32, radix))

    @jmethod("nextLong", "()J")
    @jmethod("nextLong", "(I)J")
    def nextLong(self, radix=None):
        return self._typed(self._integer(64, radix))

    @jmethod("nextShort", "()S")
    @jmethod("nextShort", "(I)S")
    def nextShort(self, radix=None):
        return self._typed(self._integer(16, radix))

    @jmethod("nextByte", "()B")
    @jmethod("nextByte", "(I)B")
    def nextByte(self, radix=None):
        return self._typed(self._integer(8, radix))

    @jmethod("hasNextInt", "()Z")
    @jmethod("hasNextInt", "(I)Z")
    def hasNextInt(self, radix=None):
        return self._has_typed(self._integer(32, radix))

    @jmethod("hasNextLong", "()Z")
    @jmethod("hasNextLong", "(I)Z")
    def hasNextLong(self, radix=None):
        return self._has_typed(self._integer(64, radix))

    @jmethod("hasNextShort", "()Z")
    def hasNextShort(self, radix=None):
        return self._has_typed(self._integer(16, radix))

    @jmethod("hasNextByte", "()Z")
    def hasNextByte(self, radix=None):
        return self._has_typed(self._integer(8, radix))

    @staticmethod
    def _real(token):
        text = token
        if text in ("NaN", "+NaN", "-NaN"):
            return float("nan")
        if re.fullmatch(r"[+-]?Infinity", text):
            return float("-inf") if text[0] == "-" else float("inf")
        if re.fullmatch(r"[+-]?(\d{1,3}(,\d{3})+|\d+)(\.\d*)?([eE][+-]?\d+)?|[+-]?\.\d+([eE][+-]?\d+)?", text):
            return float(text.replace(",", ""))
        return None

    @jmethod("nextDouble", "()D")
    def nextDouble(self):
        return self._typed(self._real)

    @jmethod("nextFloat", "()F")
    def nextFloat(self):
        return runtime.f32(self._typed(self._real))

    @jmethod("hasNextDouble", "()Z")
    @jmethod("hasNextFloat", "()Z")
    def hasNextDouble(self):
        return self._has_typed(self._real)

    @staticmethod
    def _boolean(token):
        lowered = token.lower()
        return True if lowered == "true" else (False if lowered == "false" else None)

    @jmethod("nextBoolean", "()Z")
    def nextBoolean(self):
        return 1 if self._typed(self._boolean) else 0

    @jmethod("hasNextBoolean", "()Z")
    def hasNextBoolean(self):
        return self._has_typed(self._boolean)

    @jmethod("nextBigInteger", "()Ljava/math/BigInteger;")
    @jmethod("nextBigInteger", "(I)Ljava/math/BigInteger;")
    def nextBigInteger(self, radix=None):
        parse = self._integer(1 << 20, radix)
        return lookup_host("java.math.BigInteger").py(str(self._typed(parse)))

    @jmethod("hasNextBigInteger", "()Z")
    def hasNextBigInteger(self):
        return self._has_typed(self._integer(1 << 20))

    # lines

    @jmethod("hasNextLine", "()Z")
    def hasNextLine(self):
        self._check()
        return 1 if self._pos < len(self._buf) or self._more() else 0

    @jmethod("nextLine", "()Ljava/lang/String;")
    def nextLine(self):
        self._check()
        while True:
            match = re.compile(r"\r\n|[\n\r\u0085\u2028\u2029]").search(self._buf, self._pos)
            if match is not None and not (match.group() == "\r" and match.end() == len(self._buf) and not self._eof):
                line = self._buf[self._pos:match.start()]
                self._pos = match.end()
                return jstr(line)
            if self._more():
                continue
            if self._pos >= len(self._buf):
                runtime.throw_new("java.util.NoSuchElementException", "No line found")
            line = self._buf[self._pos:]
            self._pos = len(self._buf)
            return jstr(line)

    @jmethod("findInLine", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("findInLine", "(Ljava/util/regex/Pattern;)Ljava/lang/String;")
    def findInLine(self, pattern):
        self._check()
        while not re.search(r"[\n\r\u0085\u2028\u2029]", self._buf[self._pos:]) and self._more():
            pass
        rest = self._buf[self._pos:]
        end = re.search(r"\r\n|[\n\r\u0085\u2028\u2029]", rest)
        line = rest[:end.start()] if end else rest
        found = self._pattern(pattern)._re.search(line)
        if found is None:
            return None
        self._pos += found.end()
        return jstr(found.group())

    @jmethod("findWithinHorizon", "(Ljava/lang/String;I)Ljava/lang/String;")
    @jmethod("findWithinHorizon", "(Ljava/util/regex/Pattern;I)Ljava/lang/String;")
    def findWithinHorizon(self, pattern, horizon):
        self._check()
        while self._more():
            pass
        text = self._buf[self._pos:] if horizon == 0 else self._buf[self._pos:self._pos + horizon]
        found = self._pattern(pattern)._re.search(text)
        if found is None:
            return None
        self._pos += found.end()
        return jstr(found.group())

    @jmethod("skip", "(Ljava/lang/String;)Ljava/util/Scanner;")
    @jmethod("skip", "(Ljava/util/regex/Pattern;)Ljava/util/Scanner;")
    def skip(self, pattern):
        self._check()
        while self._more():
            pass
        found = self._pattern(pattern)._re.match(self._buf, self._pos)
        if found is None:
            no_such_element()
        self._pos = found.end()
        return self

    # configuration

    @jmethod("useDelimiter", "(Ljava/lang/String;)Ljava/util/Scanner;")
    @jmethod("useDelimiter", "(Ljava/util/regex/Pattern;)Ljava/util/Scanner;")
    def useDelimiter(self, pattern):
        self._delim = self._pattern(check_nonnull(pattern))
        return self

    @jmethod("delimiter", "()Ljava/util/regex/Pattern;")
    def delimiter(self):
        return self._delim

    @jmethod("useRadix", "(I)Ljava/util/Scanner;")
    def useRadix(self, radix):
        if not 2 <= radix <= 36:
            runtime.throw_new("java.lang.IllegalArgumentException", "radix:%d" % radix)
        self._radix = radix
        return self

    @jmethod("radix", "()I")
    def radix(self):
        return self._radix

    @jmethod("reset", "()Ljava/util/Scanner;")
    def reset(self):
        self._delim = self._Pattern(_DEFAULT_DELIMITER, 0)
        self._radix = 10
        return self

    @jmethod("close", "()V")
    def close(self):
        if not self._closed:
            self._closed = True
            if self._reader is not None and hasattr(self._reader, "close"):
                self._reader.close()

    @jmethod("ioException", "()Ljava/io/IOException;")
    def ioException(self):
        return self._error

    @jmethod("hasNext", "()Z")
    def _has_next_plain(self):
        return self.hasNext()

    @jmethod("tokens", "()Ljava/util/stream/Stream;")
    def tokens(self):
        from .jstream import BaseStream

        def run():
            while self.hasNext():
                yield self.next()
        return BaseStream.from_items(run(), "obj")

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "java.util.Scanner[delimiters=%s][position=%d][match valid=false][need input=false][source closed=%s]" \
            "[skipped=false][group separator=\\x{2c}][decimal separator=\\x{2e}][positive prefix=][negative prefix=" \
            "\\Q-\\E][positive suffix=][negative suffix=][NaN string=\\QNaN\\E][infinity string=\\Q\u221e\\E]" % (
                self._delim._source, self._pos, "true" if self._closed else "false")
