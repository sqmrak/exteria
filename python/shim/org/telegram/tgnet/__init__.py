"""org.telegram.tgnet"""

import struct

from java.lang import Object


class RequestDelegate(Object):
    """a plugin class implements run(response, error)"""
    _jinterface = True


class ConnectionsManager(Object):
    """the link of the android client to the server. sendRequest takes the requests the app can make for a plugin (see requests.py), nothing else"""

    _instances = {}

    @staticmethod
    def getInstance(account=0):
        if account not in ConnectionsManager._instances:
            ConnectionsManager._instances[account] = ConnectionsManager()
        return ConnectionsManager._instances[account]

    def getCurrentTime(self):
        """the time of the server in seconds; the clock of the phone is the one the app corrects its requests with"""
        import time
        return int(time.time())

    def sendRequest(self, request, delegate, *_flags):
        """the answer reaches delegate.run(response, error), or the delegate when it is a function, once"""
        from org.telegram.tgnet import requests
        run = getattr(delegate, "run", None) or delegate
        return requests.send(request, lambda response, error: run(response, error))


class TLObject(Object):
    """base of the records of the telegram schema"""


class SerializedData(Object):
    """the stream a record writes itself to: the bytes the android client would put on the wire, so what a plugin serializes can be read back and checked"""

    def __init__(self):
        self._bytes = bytearray()

    def writeInt32(self, value):
        self._bytes += struct.pack("<i", _int(value, 32))

    def writeInt64(self, value):
        self._bytes += struct.pack("<q", _int(value, 64))

    def writeByteArray(self, data):
        """a TL string or bytes: one length byte below 254, else 0xFE and three, padded to four bytes"""
        data = bytes(data)
        if len(data) < 254:
            self._bytes.append(len(data))
            used = 1 + len(data)
        elif len(data) < 1 << 24:
            self._bytes += bytes([254]) + len(data).to_bytes(3, "little")
            used = 4 + len(data)
        else:
            raise ValueError("a TL string is shorter than 16 MiB")
        self._bytes += data + b"\0" * (-used % 4)

    def writeString(self, value):
        self.writeByteArray(str(value).encode("utf-8"))

    def getBytes(self):
        return bytes(self._bytes)


def _int(value, bits):
    """a java int or long: a python int that wrapped the way two's complement does, as the android client sees it"""
    value = int(value) & ((1 << bits) - 1)
    return value - (1 << bits) if value >> (bits - 1) else value


class NativeByteBuffer(Object):
    """the byte buffer of the android client, little endian, with the cursor (position) and the end (limit) of a java ByteBuffer and the TL reads
    and writes on it. NativeByteBuffer(size) allocates, NativeByteBuffer(True) only counts the bytes that are written (length() tells how many).
    a read that runs past the limit raises RuntimeException when the caller asked for exceptions and answers zero or None when not; a write past
    the capacity raises. a buffer is at most MAX_SIZE bytes, and one that was given back with reuse() cannot be used"""

    MAX_SIZE = 64 * 1024 * 1024
    BOOL_TRUE = 0x997275B5
    BOOL_FALSE = 0xBC799737

    def __init__(self, size_or_calc=0):
        from java.lang import IllegalArgumentException
        self._calc = size_or_calc is True
        size = 0 if self._calc else int(size_or_calc)
        if size < 0 or size > NativeByteBuffer.MAX_SIZE:
            raise IllegalArgumentException("a buffer of %d bytes is not possible, the limit is %d" % (size, NativeByteBuffer.MAX_SIZE))
        self._data = bytearray(size)
        self._counted = 0
        self._position = 0
        self._limit = size
        self._given_back = False

    def _live(self):
        if self._given_back:
            from java.lang import IllegalStateException
            raise IllegalStateException("the buffer was given back with reuse()")

    def _fail(self, what, exception):
        if exception:
            from java.lang import RuntimeException
            raise RuntimeException("read %s error" % what)

    def _take(self, count, what, exception):
        """count bytes from the cursor, or None after the failure the caller asked for"""
        self._live()
        if count < 0 or self._position + count > self._limit:
            self._fail(what, exception)
            return None
        chunk = bytes(self._data[self._position:self._position + count])
        self._position += count
        return chunk

    def _put(self, raw):
        self._live()
        if self._calc:
            self._counted += len(raw)
            return
        if self._position + len(raw) > self._limit:
            from java.lang import RuntimeException
            raise RuntimeException("buffer overflow: %d bytes at %d of %d" % (len(raw), self._position, self._limit))
        self._data[self._position:self._position + len(raw)] = raw
        self._position += len(raw)

    @staticmethod
    def _octets(values):
        """the bytes of a java byte[] (signed ints), of bytes, or of another buffer's content"""
        if isinstance(values, (bytes, bytearray, memoryview)):
            return bytes(values)
        return bytes(int(v) & 0xFF for v in values)

    def position(self, new=None):
        self._live()
        if new is None:
            return self._position
        if new < 0 or new > self._limit:
            from java.lang import IllegalArgumentException
            raise IllegalArgumentException("position %d is outside 0..%d" % (new, self._limit))
        self._position = int(new)
        return self

    getPosition = position

    def limit(self, new=None):
        self._live()
        if new is None:
            return self._limit
        if new < 0 or new > len(self._data):
            from java.lang import IllegalArgumentException
            raise IllegalArgumentException("limit %d is outside 0..%d" % (new, len(self._data)))
        self._limit = int(new)
        self._position = min(self._position, self._limit)
        return self

    def capacity(self):
        self._live()
        return len(self._data)

    def length(self):
        """the bytes counted by a counting buffer, else the limit"""
        self._live()
        return self._counted if self._calc else self._limit

    def remaining(self):
        self._live()
        return self._limit - self._position

    def hasRemaining(self):
        return self.remaining() > 0

    def rewind(self):
        self._live()
        self._position = 0
        return self

    def flip(self):
        self._live()
        self._limit = self._position
        self._position = 0
        return self

    def compact(self):
        self._live()
        rest = bytes(self._data[self._position:self._limit])
        self._data[:len(rest)] = rest
        self._position = len(rest)
        self._limit = len(self._data)
        return self

    def skip(self, count):
        self._live()
        if self._position + int(count) > self._limit or count < 0:
            from java.lang import RuntimeException
            raise RuntimeException("skip past the limit")
        self._position += int(count)

    def reuse(self):
        self._given_back = True
        self._data = bytearray()

    def writeInt32(self, value):
        self._put(struct.pack("<i", _int(value, 32)))

    def writeInt64(self, value):
        self._put(struct.pack("<q", _int(value, 64)))

    def writeBool(self, value):
        self.writeInt32(NativeByteBuffer.BOOL_TRUE if value else NativeByteBuffer.BOOL_FALSE)

    def writeByte(self, value):
        self._put(bytes([int(value) & 0xFF]))

    def writeDouble(self, value):
        self._put(struct.pack("<d", float(value)))

    def writeBytes(self, values, offset=None, count=None):
        if isinstance(values, NativeByteBuffer):
            values._live()
            self._put(bytes(values._data[values._position:values._limit]))
            return
        raw = self._octets(values)
        if offset is not None:
            raw = raw[int(offset):int(offset) + int(count)]
        self._put(raw)

    writeByteBuffer = writeBytes

    def writeByteArray(self, values, offset=None, count=None):
        """a TL string or bytes: one length byte below 254, else 0xFE and three, padded to four bytes"""
        raw = self._octets(values)
        if offset is not None:
            raw = raw[int(offset):int(offset) + int(count)]
        if len(raw) < 254:
            head = bytes([len(raw)])
        elif len(raw) < 1 << 24:
            head = bytes([254]) + len(raw).to_bytes(3, "little")
        else:
            from java.lang import IllegalArgumentException
            raise IllegalArgumentException("a TL string is shorter than 16 MiB")
        self._put(head + raw + b"\0" * (-(len(head) + len(raw)) % 4))

    def writeString(self, value):
        self.writeByteArray(str(value).encode("utf-8"))

    def readInt32(self, exception=False):
        raw = self._take(4, "int32", exception)
        return struct.unpack("<i", raw)[0] if raw is not None else 0

    def readUint32(self, exception=False):
        raw = self._take(4, "uint32", exception)
        return struct.unpack("<I", raw)[0] if raw is not None else 0

    def readInt64(self, exception=False):
        raw = self._take(8, "int64", exception)
        return struct.unpack("<q", raw)[0] if raw is not None else 0

    def readBool(self, exception=False):
        code = self.readUint32(exception)
        if code == NativeByteBuffer.BOOL_TRUE:
            return True
        if code != NativeByteBuffer.BOOL_FALSE and exception:
            from java.lang import RuntimeException
            raise RuntimeException("Not bool value!")
        return False

    def readByte(self, exception=False):
        raw = self._take(1, "byte", exception)
        return struct.unpack("<b", raw)[0] if raw is not None else 0

    def readDouble(self, exception=False):
        raw = self._take(8, "double", exception)
        return struct.unpack("<d", raw)[0] if raw is not None else 0.0

    def readData(self, count, exception=False):
        """count bytes as a java byte[] (signed ints)"""
        raw = self._take(int(count), "data", exception)
        return [b - 256 if b > 127 else b for b in raw] if raw is not None else None

    def readBytes(self, target, *rest):
        """readBytes(byte[] target, exception) and readBytes(byte[] target, offset, count, exception): fills the list in place"""
        offset, count, exception = (0, len(target), rest[0] if rest else False) if len(rest) < 3 else rest
        raw = self._take(int(count), "bytes", exception)
        if raw is None:
            return
        for index, value in enumerate(raw):
            target[int(offset) + index] = value - 256 if value > 127 else value

    def readByteArray(self, exception=False):
        """a TL string or bytes as a java byte[]"""
        head = self._take(1, "byte array", exception)
        if head is None:
            return None
        size = head[0]
        used = 1
        if size >= 254:
            extra = self._take(3, "byte array", exception)
            if extra is None:
                return None
            size, used = int.from_bytes(extra, "little"), 4
        raw = self._take(size, "byte array", exception)
        if raw is None:
            return None
        padding = -(used + size) % 4
        if self._take(padding, "byte array", exception) is None:
            return None
        return [b - 256 if b > 127 else b for b in raw]

    def readString(self, exception=False):
        values = self.readByteArray(exception)
        return bytes(v & 0xFF for v in values).decode("utf-8", "replace") if values is not None else ""
