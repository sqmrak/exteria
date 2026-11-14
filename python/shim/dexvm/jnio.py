"""java.nio buffers and charset coders: ByteBuffer, CharBuffer, ShortBuffer, IntBuffer, LongBuffer, FloatBuffer,
DoubleBuffer, ByteOrder, CharsetDecoder, CharsetEncoder, CodingErrorAction and CoderResult

a ByteBuffer holds the byte[] it was made from or allocated with (array() answers that very array), so a write through
the buffer shows in the array and the other way round. a typed view (asIntBuffer) reads and writes the bytes of its
ByteBuffer in the order the ByteBuffer had when the view was made. a direct buffer is an ordinary heap buffer that
answers hasArray: a program that asks for the array of a direct buffer would fail on a device and works here.
buffer methods are found by name: the covariant return types of the java 9 api (position(int) answering a ByteBuffer)
need no second overload, and an overload set (get(), get(int), get(byte[])) is one python function that looks at what
it was given"""

import codecs
import struct

from . import runtime
from .api import host_class, jmethod, jstatic
from .jlang import Object, jstr, pystr, _charset_name
from .jutil import check_nonnull


def _define(table):
    from .api import lookup_host
    for line in table.strip().splitlines():
        name, parent = line.split()
        host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


_define("""
java.nio.ReadOnlyBufferException java.lang.UnsupportedOperationException
java.nio.InvalidMarkException java.lang.IllegalStateException
java.nio.charset.MalformedInputException java.nio.charset.CharacterCodingException
java.nio.charset.UnmappableCharacterException java.nio.charset.CharacterCodingException
""")


def _throw(name, message=None):
    runtime.throw_new(name, message)


def _signed(byte):
    return byte - 256 if byte > 127 else byte


@host_class("java.nio.ByteOrder", final=True)
class ByteOrder(Object):
    def __init__(self, name):
        self._name = name

    @jstatic("nativeOrder", "()Ljava/nio/ByteOrder;")
    def nativeOrder():
        return ByteOrder.LITTLE_ENDIAN

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._name


ByteOrder.BIG_ENDIAN = ByteOrder("BIG_ENDIAN")
ByteOrder.LITTLE_ENDIAN = ByteOrder("LITTLE_ENDIAN")


@host_class("java.nio.Buffer")
class Buffer(Object):
    """position, limit, capacity and mark; the element access is in the subclasses"""

    _readonly = False

    def _setup(self, capacity, position=0, limit=None):
        self._cap = capacity
        self._pos = position
        self._limit = capacity if limit is None else limit
        self._mark = -1

    def capacity(self):
        return self._cap

    def position(self, value=None):
        if value is None:
            return self._pos
        if value < 0 or value > self._limit:
            _throw("java.lang.IllegalArgumentException", "Bad position %d/%d" % (value, self._limit))
        self._pos = value
        if self._mark > value:
            self._mark = -1
        return self

    def limit(self, value=None):
        if value is None:
            return self._limit
        if value < 0 or value > self._cap:
            _throw("java.lang.IllegalArgumentException", "Bad limit (capacity %d): %d" % (self._cap, value))
        self._limit = value
        if self._pos > value:
            self._pos = value
        if self._mark > value:
            self._mark = -1
        return self

    def mark(self):
        self._mark = self._pos
        return self

    def reset(self):
        if self._mark < 0:
            _throw("java.nio.InvalidMarkException")
        self._pos = self._mark
        return self

    def clear(self):
        self._pos = 0
        self._limit = self._cap
        self._mark = -1
        return self

    def flip(self):
        self._limit = self._pos
        self._pos = 0
        self._mark = -1
        return self

    def rewind(self):
        self._pos = 0
        self._mark = -1
        return self

    def remaining(self):
        return max(self._limit - self._pos, 0)

    def hasRemaining(self):
        return 1 if self._pos < self._limit else 0

    def isReadOnly(self):
        return 1 if self._readonly else 0

    def isDirect(self):
        return 0

    def hasArray(self):
        return 0 if self._readonly else 1

    def _next(self, count, error="java.nio.BufferUnderflowException"):
        """the index of the next count elements, moving the position past them"""
        if self._limit - self._pos < count:
            _throw(error)
        index = self._pos
        self._pos += count
        return index

    def _index(self, index, count=1):
        if index < 0 or index + count > self._limit:
            _throw("java.lang.IndexOutOfBoundsException")
        return index

    def _writable(self):
        if self._readonly:
            _throw("java.nio.ReadOnlyBufferException")


@host_class("java.nio.ByteBuffer", interfaces=("java.lang.Comparable",))
class ByteBuffer(Buffer):
    """bytes over a byte[] of the vm: the array, the offset of the buffer in it and the order of multi byte values"""

    def __init__(self, array, offset=0, capacity=None, position=0, limit=None):
        self._arr = array
        self._off = offset
        self._setup(len(array) - offset if capacity is None else capacity, position, limit)
        self._order = "big"
        self._readonly = False

    @jstatic("wrap", "([B)Ljava/nio/ByteBuffer;")
    @jstatic("wrap", "([BII)Ljava/nio/ByteBuffer;")
    def wrap(array, offset=0, length=None):
        check_nonnull(array)
        if length is None:
            return ByteBuffer(array)
        if offset < 0 or length < 0 or offset + length > len(array):
            _throw("java.lang.IndexOutOfBoundsException")
        return ByteBuffer(array, 0, len(array), offset, offset + length)

    @jstatic("allocate", "(I)Ljava/nio/ByteBuffer;")
    @jstatic("allocateDirect", "(I)Ljava/nio/ByteBuffer;")
    def allocate(size):
        if size < 0:
            _throw("java.lang.IllegalArgumentException", "capacity < 0: (%d < 0)" % size)
        return ByteBuffer(runtime.new_array("[B", size))

    def _raw(self, index, count):
        start = self._off + index
        return bytes(b & 0xFF for b in self._arr[start:start + count])

    def _store(self, index, data):
        self._writable()
        start = self._off + index
        self._arr[start:start + len(data)] = [_signed(b) for b in data]

    def array(self):
        if self._readonly:
            _throw("java.nio.ReadOnlyBufferException")
        return self._arr

    def arrayOffset(self):
        return self._off

    def order(self, order=None):
        if order is None:
            return ByteOrder.BIG_ENDIAN if self._order == "big" else ByteOrder.LITTLE_ENDIAN
        self._order = "little" if order is ByteOrder.LITTLE_ENDIAN else "big"
        return self

    def _view(self, position, limit, capacity=None):
        copy = ByteBuffer(self._arr, self._off, self._cap if capacity is None else capacity, position, limit)
        copy._order = "big"
        copy._readonly = self._readonly
        return copy

    def duplicate(self):
        copy = self._view(self._pos, self._limit)
        copy._mark = self._mark
        return copy

    def slice(self, index=None, length=None):
        if index is None:
            index, length = self._pos, self._limit - self._pos
        copy = ByteBuffer(self._arr, self._off + index, length)
        copy._readonly = self._readonly
        return copy

    def asReadOnlyBuffer(self):
        copy = self.duplicate()
        copy._readonly = True
        return copy

    def compact(self):
        self._writable()
        data = self._raw(self._pos, self._limit - self._pos)
        self._store(0, data)
        self._pos = len(data)
        self._limit = self._cap
        self._mark = -1
        return self

    def get(self, first=None, second=None, third=None):
        """get(), get(index), get(byte[]), get(byte[], offset, length), get(index, byte[]) and get(index, byte[], off, len)"""
        if first is None:
            return _signed(self._raw(self._next(1), 1)[0])
        if isinstance(first, int):
            if second is None:
                return _signed(self._raw(self._index(first), 1)[0])
            offset = 0 if third is None else third
            length = len(second) - offset
            data = self._raw(self._index(first, length), length)
            second[offset:offset + length] = [_signed(b) for b in data]
            return self
        offset = 0 if second is None else second
        length = len(first) - offset if third is None else third
        if offset < 0 or length < 0 or offset + length > len(first):
            _throw("java.lang.IndexOutOfBoundsException")
        data = self._raw(self._next(length), length)
        first[offset:offset + length] = [_signed(b) for b in data]
        return self

    def put(self, first, second=None, third=None, fourth=None):
        """put(byte), put(index, byte), put(byte[]), put(byte[], offset, length), put(ByteBuffer) and put(index, byte[]...)"""
        self._writable()
        if isinstance(first, ByteBuffer):
            count = first.remaining()
            if count > self.remaining():
                _throw("java.nio.BufferOverflowException")
            self._store(self._next(count, "java.nio.BufferOverflowException"), first._raw(first._pos, count))
            first._pos += count
            return self
        if isinstance(first, int):
            if second is None or isinstance(second, int):
                if second is None:
                    self._store(self._next(1, "java.nio.BufferOverflowException"), bytes((first & 0xFF,)))
                else:
                    self._store(self._index(first), bytes((second & 0xFF,)))
                return self
            offset = 0 if third is None else third
            length = len(second) - offset if fourth is None else fourth
            self._store(self._index(first, length), bytes(b & 0xFF for b in second[offset:offset + length]))
            return self
        offset = 0 if second is None else second
        length = len(first) - offset if third is None else third
        if offset < 0 or length < 0 or offset + length > len(first):
            _throw("java.lang.IndexOutOfBoundsException")
        self._store(self._next(length, "java.nio.BufferOverflowException"),
                    bytes(b & 0xFF for b in first[offset:offset + length]))
        return self

    def _read(self, fmt, size, index):
        where = self._next(size) if index is None else self._index(index, size)
        return struct.unpack((">" if self._order == "big" else "<") + fmt, self._raw(where, size))[0]

    def _write(self, fmt, size, index, value):
        self._writable()
        where = self._next(size, "java.nio.BufferOverflowException") if index is None else self._index(index, size)
        self._store(where, struct.pack((">" if self._order == "big" else "<") + fmt, value))
        return self

    def getShort(self, index=None):
        return self._read("h", 2, index)

    def getChar(self, index=None):
        return self._read("H", 2, index)

    def getInt(self, index=None):
        return self._read("i", 4, index)

    def getLong(self, index=None):
        return self._read("q", 8, index)

    def getFloat(self, index=None):
        return self._read("f", 4, index)

    def getDouble(self, index=None):
        return self._read("d", 8, index)

    def putShort(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("h", 2, index, runtime.wrap32(value) << 16 >> 16)

    def putChar(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("H", 2, index, ord(value) if isinstance(value, str) else value & 0xFFFF)

    def putInt(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("i", 4, index, runtime.wrap32(value))

    def putLong(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("q", 8, index, runtime.wrap64(value))

    def putFloat(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("f", 4, index, value)

    def putDouble(self, first, second=None):
        index, value = (None, first) if second is None else (first, second)
        return self._write("d", 8, index, value)

    def asShortBuffer(self):
        return _TypedView(ShortBuffer, self, "h", 2)

    def asCharBuffer(self):
        return _TypedView(CharBuffer, self, "H", 2)

    def asIntBuffer(self):
        return _TypedView(IntBuffer, self, "i", 4)

    def asLongBuffer(self):
        return _TypedView(LongBuffer, self, "q", 8)

    def asFloatBuffer(self):
        return _TypedView(FloatBuffer, self, "f", 4)

    def asDoubleBuffer(self):
        return _TypedView(DoubleBuffer, self, "d", 8)

    def to_bytes(self):
        """the remaining bytes without moving the position"""
        return self._raw(self._pos, self._limit - self._pos)

    def equals(self, other):
        return 1 if isinstance(other, ByteBuffer) and other.to_bytes() == self.to_bytes() else 0

    def compareTo(self, other):
        a, b = self.to_bytes(), check_nonnull(other).to_bytes()
        a, b = [_signed(x) for x in a], [_signed(x) for x in b]
        return (a > b) - (a < b)

    def hashCode(self):
        value = 1
        for byte in reversed(self.to_bytes()):
            value = runtime.wrap32(31 * value + _signed(byte))
        return value

    def toString(self):
        return "java.nio.%sByteBuffer[pos=%d lim=%d cap=%d]" % (
            "HeapReadOnly" if self._readonly else "Heap", self._pos, self._limit, self._cap)


_KINDS = {"h": ("[S", 2, "S"), "H": ("[C", 2, "C"), "i": ("[I", 4, "I"), "q": ("[J", 8, "J"), "f": ("[F", 4, "F"),
          "d": ("[D", 8, "D")}


class _Typed(Buffer):
    """a buffer of one element type over a list (allocate, wrap) or over the bytes of a ByteBuffer (a view); the subclass
    names the element format"""

    FMT = ""

    def _init_heap(self, array, offset, capacity, position, limit):
        self._arr = array
        self._off = offset
        self._bytes = None
        self._setup(capacity, position, limit)
        self._readonly = False

    def _get_at(self, index):
        if self._bytes is None:
            return self._arr[self._off + index]
        size = _KINDS[self.FMT][1]
        raw = self._bytes._raw(self._start + index * size, size)
        return struct.unpack((">" if self._order == "big" else "<") + self.FMT, raw)[0]

    def _put_at(self, index, value):
        self._writable()
        if self._bytes is None:
            self._arr[self._off + index] = value
            return
        size = _KINDS[self.FMT][1]
        self._bytes._store(self._start + index * size,
                           struct.pack((">" if self._order == "big" else "<") + self.FMT, value))

    def _coerce(self, value):
        return value

    def order(self):
        if self._bytes is None:
            return ByteOrder.LITTLE_ENDIAN
        return ByteOrder.BIG_ENDIAN if self._order == "big" else ByteOrder.LITTLE_ENDIAN

    def hasArray(self):
        return 1 if self._bytes is None and not self._readonly else 0

    def array(self):
        if self._bytes is not None or self._readonly:
            _throw("java.lang.UnsupportedOperationException")
        return self._arr

    def arrayOffset(self):
        return self._off if self._bytes is None else 0

    def get(self, first=None, second=None, third=None):
        if first is None:
            return self._get_at(self._next(1))
        if isinstance(first, int):
            if second is None:
                return self._get_at(self._index(first))
            offset = 0 if third is None else third
            length = len(second) - offset
            base = self._index(first, length)
            for i in range(length):
                second[offset + i] = self._get_at(base + i)
            return self
        offset = 0 if second is None else second
        length = len(first) - offset if third is None else third
        if offset < 0 or length < 0 or offset + length > len(first):
            _throw("java.lang.IndexOutOfBoundsException")
        base = self._next(length)
        for i in range(length):
            first[offset + i] = self._get_at(base + i)
        return self

    def put(self, first, second=None, third=None, fourth=None):
        self._writable()
        if isinstance(first, _Typed):
            count = first.remaining()
            if count > self.remaining():
                _throw("java.nio.BufferOverflowException")
            base = self._next(count, "java.nio.BufferOverflowException")
            source = first._next(count)
            for i in range(count):
                self._put_at(base + i, first._get_at(source + i))
            return self
        if isinstance(first, (list, tuple)):
            offset = 0 if second is None else second
            length = len(first) - offset if third is None else third
            base = self._next(length, "java.nio.BufferOverflowException")
            for i in range(length):
                self._put_at(base + i, first[offset + i])
            return self
        if second is None:
            self._put_at(self._next(1, "java.nio.BufferOverflowException"), self._coerce(first))
        else:
            self._put_at(self._index(first), self._coerce(second))
        return self

    def duplicate(self):
        copy = self._clone(self._pos, self._limit)
        copy._mark = self._mark
        return copy

    def slice(self):
        return self._clone(0, self._limit - self._pos, self._pos, self._limit - self._pos)

    def asReadOnlyBuffer(self):
        copy = self.duplicate()
        copy._readonly = True
        return copy

    def compact(self):
        self._writable()
        count = self.remaining()
        values = [self._get_at(self._pos + i) for i in range(count)]
        for i, value in enumerate(values):
            self._put_at(i, value)
        self._pos = count
        self._limit = self._cap
        self._mark = -1
        return self

    def _clone(self, position, limit, shift=0, capacity=None):
        copy = type(self).__new__(type(self))
        copy.__dict__.update(self.__dict__)
        copy._cap = self._cap - shift if capacity is None else capacity
        if self._bytes is None:
            copy._off = self._off + shift
        else:
            copy._start = self._start + shift * _KINDS[self.FMT][1]
        copy._pos, copy._limit, copy._mark = position, limit, -1
        if capacity is not None:
            copy._cap = capacity
        return copy

    def _values(self):
        return [self._get_at(self._pos + i) for i in range(self._limit - self._pos)]

    def equals(self, other):
        return 1 if isinstance(other, type(self)) and other._values() == self._values() else 0

    def compareTo(self, other):
        a, b = self._values(), check_nonnull(other)._values()
        return (a > b) - (a < b)

    def hashCode(self):
        value = 1
        for item in reversed(self._values()):
            value = runtime.wrap32(31 * value + int(item))
        return value

    def toString(self):
        return "java.nio.%s[pos=%d lim=%d cap=%d]" % (
            ("Heap" if self._bytes is None else "ByteBuffer") + type(self).__name__, self._pos, self._limit, self._cap)


class _TypedView:
    """the factory of a view of a ByteBuffer: it makes the buffer class asked for and points it at the bytes"""

    def __new__(cls, klass, source, fmt, size):
        view = klass.__new__(klass)
        count = source.remaining() // size
        view._arr = None
        view._off = 0
        view._bytes = source
        view._start = source._pos
        view._order = source._order
        view._setup(count)
        view._readonly = source._readonly
        return view


def _typed(name, fmt, code):
    descriptor = _KINDS[fmt][0]

    class Typed(_Typed):
        FMT = fmt

        def __init__(self, array=None, offset=0, capacity=None, position=0, limit=None):
            if array is not None:
                self._init_heap(array, offset, len(array) - offset if capacity is None else capacity, position, limit)

        @jstatic("wrap", "(%s)Ljava/nio/%s;" % (descriptor, name))
        @jstatic("wrap", "(%sII)Ljava/nio/%s;" % (descriptor, name))
        def wrap(array, offset=0, length=None):
            check_nonnull(array)
            if length is None:
                return Typed(array)
            if offset < 0 or length < 0 or offset + length > len(array):
                _throw("java.lang.IndexOutOfBoundsException")
            return Typed(array, 0, len(array), offset, offset + length)

        @jstatic("allocate", "(I)Ljava/nio/%s;" % name)
        def allocate(size):
            if size < 0:
                _throw("java.lang.IllegalArgumentException", "capacity < 0: (%d < 0)" % size)
            return Typed(runtime.new_array(descriptor, size))

    Typed.__name__ = Typed.__qualname__ = name
    return Typed


ShortBuffer = host_class("java.nio.ShortBuffer", interfaces=("java.lang.Comparable",))(_typed("ShortBuffer", "h", "S"))
IntBuffer = host_class("java.nio.IntBuffer", interfaces=("java.lang.Comparable",))(_typed("IntBuffer", "i", "I"))
LongBuffer = host_class("java.nio.LongBuffer", interfaces=("java.lang.Comparable",))(_typed("LongBuffer", "q", "J"))
FloatBuffer = host_class("java.nio.FloatBuffer", interfaces=("java.lang.Comparable",))(_typed("FloatBuffer", "f", "F"))
DoubleBuffer = host_class("java.nio.DoubleBuffer", interfaces=("java.lang.Comparable",))(
    _typed("DoubleBuffer", "d", "D"))
_CharBase = _typed("CharBuffer", "H", "C")


@host_class("java.nio.CharBuffer", interfaces=("java.lang.Comparable", "java.lang.CharSequence", "java.lang.Appendable"))
class CharBuffer(_CharBase):
    """a buffer of utf-16 code units that also reads as a CharSequence over what remains"""

    @staticmethod
    def _from_text(text):
        array = runtime.new_array("[C", 0)
        array.extend(ord(c) for c in text)
        buffer = CharBuffer(array)
        return buffer

    @jstatic("wrap", "([C)Ljava/nio/CharBuffer;")
    @jstatic("wrap", "([CII)Ljava/nio/CharBuffer;")
    @jstatic("wrap", "(Ljava/lang/CharSequence;)Ljava/nio/CharBuffer;")
    @jstatic("wrap", "(Ljava/lang/CharSequence;II)Ljava/nio/CharBuffer;")
    def wrap(source, start=None, end=None):
        if isinstance(source, list):
            if start is None:
                return CharBuffer(source)
            if start < 0 or end < 0 or start + end > len(source):
                _throw("java.lang.IndexOutOfBoundsException")
            return CharBuffer(source, 0, len(source), start, start + end)
        text = source if isinstance(source, str) else source.toString()
        buffer = CharBuffer._from_text(text)
        buffer._readonly = True
        if start is not None:
            buffer.position(start)
            buffer.limit(end)
        return buffer

    @jstatic("allocate", "(I)Ljava/nio/CharBuffer;")
    def allocate(size):
        if size < 0:
            _throw("java.lang.IllegalArgumentException", "capacity < 0: (%d < 0)" % size)
        return CharBuffer(runtime.new_array("[C", size))

    def put(self, first, second=None, third=None, fourth=None):
        if isinstance(first, str) and (second is None or isinstance(second, int)):
            if second is None:
                units = [ord(c) for c in first]
            else:
                units = [ord(c) for c in first[second:third]]
            return _Typed.put(self, units)
        return _Typed.put(self, first if not isinstance(first, str) else ord(first), second, third, fourth)

    def _text(self):
        return "".join(chr(self._get_at(self._pos + i)) for i in range(self._limit - self._pos))

    def toString(self):
        return jstr(self._text())

    def length(self):
        return self.remaining()

    def charAt(self, index):
        if index < 0 or index >= self.remaining():
            _throw("java.lang.IndexOutOfBoundsException")
        return self._get_at(self._pos + index)

    def isEmpty(self):
        return 1 if self.remaining() == 0 else 0

    def subSequence(self, start, end):
        if start < 0 or end > self.remaining() or start > end:
            _throw("java.lang.IndexOutOfBoundsException")
        return self._clone(self._pos + start, self._pos + end, 0, self._cap)

    def append(self, value, start=None, end=None):
        text = "null" if value is None else (chr(value) if isinstance(value, int) else (
            value if isinstance(value, str) else value.toString()))
        if start is not None:
            text = text[start:end]
        return self.put(text)


class CodingErrorAction(Object):
    def __init__(self, name):
        self._name = name

    def toString(self):
        return self._name


CodingErrorAction.IGNORE = CodingErrorAction("IGNORE")
CodingErrorAction.REPLACE = CodingErrorAction("REPLACE")
CodingErrorAction.REPORT = CodingErrorAction("REPORT")
host_class("java.nio.charset.CodingErrorAction", final=True)(CodingErrorAction)


class CoderResult(Object):
    def __init__(self, kind, length=0):
        self._kind = kind
        self._length = length

    def isUnderflow(self):
        return 1 if self._kind == "UNDERFLOW" else 0

    def isOverflow(self):
        return 1 if self._kind == "OVERFLOW" else 0

    def isError(self):
        return 1 if self._kind in ("MALFORMED", "UNMAPPABLE") else 0

    def isMalformed(self):
        return 1 if self._kind == "MALFORMED" else 0

    def isUnmappable(self):
        return 1 if self._kind == "UNMAPPABLE" else 0

    def length(self):
        if not self.isError():
            _throw("java.lang.UnsupportedOperationException")
        return self._length

    @staticmethod
    def malformedForLength(length):
        return CoderResult("MALFORMED", length)

    @staticmethod
    def unmappableForLength(length):
        return CoderResult("UNMAPPABLE", length)

    def throwException(self):
        if self._kind == "UNDERFLOW":
            _throw("java.nio.BufferUnderflowException")
        if self._kind == "OVERFLOW":
            _throw("java.nio.BufferOverflowException")
        _throw("java.nio.charset.MalformedInputException" if self._kind == "MALFORMED" else
               "java.nio.charset.UnmappableCharacterException", str(self._length))

    def toString(self):
        return self._kind if not self.isError() else "%s[%d]" % (self._kind, self._length)


CoderResult.UNDERFLOW = CoderResult("UNDERFLOW")
CoderResult.OVERFLOW = CoderResult("OVERFLOW")
host_class("java.nio.charset.CoderResult", final=True)(CoderResult)


class _Coder(Object):
    def __init__(self, charset, replacement):
        self._charset = charset
        self._malformed = CodingErrorAction.REPORT
        self._unmappable = CodingErrorAction.REPORT
        self._replacement = replacement

    def charset(self):
        return self._charset

    def onMalformedInput(self, action):
        self._malformed = check_nonnull(action)
        return self

    def onUnmappableCharacter(self, action):
        self._unmappable = check_nonnull(action)
        return self

    def malformedInputAction(self):
        return self._malformed

    def unmappableCharacterAction(self):
        return self._unmappable

    def reset(self):
        return self


@host_class("java.nio.charset.CharsetDecoder")
class CharsetDecoder(_Coder):
    def __init__(self, charset):
        _Coder.__init__(self, charset, "�")
        self._codec = _charset_name(charset)

    def replaceWith(self, text):
        self._replacement = text
        return self

    def replacement(self):
        return self._replacement

    def averageCharsPerByte(self):
        return 1.0

    def maxCharsPerByte(self):
        return 1.0

    def decode(self, source, target=None, end_of_input=True):
        if target is None:
            return self._decode_all(source)
        return self._decode_into(source, target, end_of_input)

    def _decode_all(self, source):
        data = source.to_bytes()
        try:
            text = data.decode(self._codec, "strict")
        except UnicodeDecodeError as error:
            if self._malformed is CodingErrorAction.REPORT:
                source._pos = source._limit
                _throw("java.nio.charset.MalformedInputException", str(max(error.end - error.start, 1)))
            text = data.decode(self._codec, "replace" if self._malformed is CodingErrorAction.REPLACE else "ignore")
            if self._malformed is CodingErrorAction.REPLACE and self._replacement != "�":
                text = text.replace("�", self._replacement)
        source._pos = source._limit
        return CharBuffer._from_text(jstr(text))

    def _decode_into(self, source, target, end_of_input):
        """decode what fits: the input moves past the bytes of every char written, and stays at the first byte of a char
        that is incomplete (underflow) or does not fit the output (overflow), so the caller can compact and go on"""
        decoder = codecs.getincrementaldecoder(self._codec)("strict")
        mark = source._pos
        while source._pos < source._limit:
            if not decoder.getstate()[0]:
                mark = source._pos
            byte = source._raw(source._pos, 1)
            try:
                produced = decoder.decode(byte, False)
            except UnicodeDecodeError:
                if self._malformed is CodingErrorAction.REPORT:
                    source._pos = mark
                    return CoderResult.malformedForLength(source._pos + 1 - mark)
                decoder.reset()
                produced = self._replacement if self._malformed is CodingErrorAction.REPLACE else ""
            units = jstr(produced)
            if len(units) > target.remaining():
                source._pos = mark
                return CoderResult.OVERFLOW
            source._pos += 1
            for char in units:
                target.put(ord(char))
        if decoder.getstate()[0]:
            source._pos = mark
            if end_of_input:
                return CoderResult.malformedForLength(source._limit - mark)
        return CoderResult.UNDERFLOW

    def flush(self, target):
        return CoderResult.UNDERFLOW


@host_class("java.nio.charset.CharsetEncoder")
class CharsetEncoder(_Coder):
    def __init__(self, charset):
        _Coder.__init__(self, charset, b"?")
        self._codec = _charset_name(charset)

    def replaceWith(self, data):
        self._replacement = bytes(b & 0xFF for b in data)
        return self

    def averageBytesPerChar(self):
        return 1.1 if self._codec.startswith("utf-8") else 1.0

    def maxBytesPerChar(self):
        return 3.0 if self._codec.startswith("utf-8") else 4.0 if self._codec.startswith("utf-16") else 1.0

    def canEncode(self, value):
        text = chr(value) if isinstance(value, int) else (value if isinstance(value, str) else value.toString())
        try:
            pystr(text).encode(self._codec, "strict")
            return 1
        except UnicodeEncodeError:
            return 0

    def encode(self, source, target=None, end_of_input=True):
        text = pystr(source._text())
        try:
            data = text.encode(self._codec, "strict")
        except UnicodeEncodeError as error:
            if self._unmappable is CodingErrorAction.REPORT:
                source._pos = source._limit
                _throw("java.nio.charset.UnmappableCharacterException", str(max(error.end - error.start, 1)))
            data = bytearray()
            for char in text:
                try:
                    data += char.encode(self._codec)
                except UnicodeEncodeError:
                    if self._unmappable is CodingErrorAction.REPLACE:
                        data += self._replacement
            data = bytes(data)
        source._pos = source._limit
        array = runtime.new_array("[B", 0)
        array.extend(_signed(b) for b in data)
        if target is None:
            return ByteBuffer.wrap(array)
        if len(data) > target.remaining():
            return CoderResult.OVERFLOW
        target.put(array)
        return CoderResult.UNDERFLOW

    def flush(self, target):
        return CoderResult.UNDERFLOW
