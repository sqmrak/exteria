"""java.io and the parts of java.nio the vm needs: streams, readers, writers, File, ByteBuffer, charsets

files are the real files of the process. policy.check_path is called before a path is opened, created, listed or
deleted, so an embedding that wants a sandbox installs its roots there; by default every path the process may use is
allowed. bytes are java bytes (signed ints in a [B), text is utf-16 code units"""

import codecs
import os

from . import policy, runtime
from .api import host_class, jmethod, jstatic
from .jfunc import jstring
from .jlang import Object, _charset_name, jstr, pystr
from .jutil import check_nonnull


def to_py_bytes(array, offset=0, length=None):
    if length is None:
        length = len(array) - offset
    return bytes(b & 0xFF for b in array[offset:offset + length])


def to_java_bytes(data):
    array = runtime.new_array("[B", 0)
    array.extend(b - 256 if b > 127 else b for b in data)
    return array


def io_error(message, name="java.io.IOException"):
    runtime.throw_new(name, message)


def _check_range(array, offset, length):
    if array is None:
        runtime.npe()
    if offset < 0 or length < 0 or offset + length > len(array):
        runtime.throw_new("java.lang.IndexOutOfBoundsException", "length=%d; regionStart=%d; regionLength=%d" % (
            len(array), offset, length))


@host_class("java.io.Closeable", interface=True, interfaces=("java.lang.AutoCloseable",))
class Closeable:
    __slots__ = ()


@host_class("java.io.Flushable", interface=True)
class Flushable:
    __slots__ = ()


@host_class("java.io.InputStream", interfaces=("java.io.Closeable",))
class InputStream(Object):
    def __init__(self):
        pass

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("read", "()I")
    def read_byte(self):
        raise NotImplementedError

    @jmethod("read", "([B)I")
    @jmethod("read", "([BII)I")
    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        first = self.read_byte()
        if first == -1:
            return -1
        buffer[offset] = (first + 128 & 0xFF) - 128
        count = 1
        while count < length:
            value = self.read_byte()
            if value == -1:
                break
            buffer[offset + count] = (value + 128 & 0xFF) - 128
            count += 1
        return count

    @jmethod("readAllBytes", "()[B")
    def readAllBytes(self):
        out = bytearray()
        chunk = runtime.new_array("[B", 8192)
        while True:
            count = self.read(chunk, 0, 8192)
            if count < 0:
                return to_java_bytes(out)
            out += to_py_bytes(chunk, 0, count)

    @jmethod("skip", "(J)J")
    def skip(self, count):
        skipped = 0
        while skipped < count and self.read_byte() != -1:
            skipped += 1
        return skipped

    @jmethod("available", "()I")
    def available(self):
        return 0

    @jmethod("close", "()V")
    def close(self):
        return None

    @jmethod("markSupported", "()Z")
    def markSupported(self):
        return 0

    @jmethod("transferTo", "(Ljava/io/OutputStream;)J")
    def transferTo(self, out):
        data = self.readAllBytes()
        out.write(data, 0, len(data))
        return len(data)


@host_class("java.io.OutputStream", interfaces=("java.io.Closeable", "java.io.Flushable"))
class OutputStream(Object):
    def __init__(self):
        pass

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("write", "(I)V")
    def write_byte(self, value):
        raise NotImplementedError

    @jmethod("write", "([B)V")
    @jmethod("write", "([BII)V")
    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        for index in range(offset, offset + length):
            self.write_byte(buffer[index])

    @jmethod("flush", "()V")
    def flush(self):
        return None

    @jmethod("close", "()V")
    def close(self):
        return None


@host_class("java.io.ByteArrayInputStream")
class ByteArrayInputStream(InputStream):
    def __init__(self, data=None, offset=0, length=None):
        self._data = bytes(b & 0xFF for b in data) if data is not None else b""
        if length is not None:
            self._data = self._data[:offset + length]
        self._pos = offset
        self._mark = offset

    @jmethod("<init>", "([B)V")
    def _init(self, data):
        ByteArrayInputStream.__init__(self, check_nonnull(data))

    @jmethod("<init>", "([BII)V")
    def _init_range(self, data, offset, length):
        ByteArrayInputStream.__init__(self, check_nonnull(data), offset, length)

    def read_byte(self):
        if self._pos >= len(self._data):
            return -1
        value = self._data[self._pos]
        self._pos += 1
        return value

    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        if self._pos >= len(self._data):
            return -1
        chunk = self._data[self._pos:self._pos + length]
        self._pos += len(chunk)
        buffer[offset:offset + len(chunk)] = [b - 256 if b > 127 else b for b in chunk]
        return len(chunk)

    def available(self):
        return len(self._data) - self._pos

    def markSupported(self):
        return 1

    @jmethod("mark", "(I)V")
    def mark(self, limit):
        self._mark = self._pos

    @jmethod("reset", "()V")
    def reset(self):
        self._pos = self._mark


@host_class("java.io.ByteArrayOutputStream")
class ByteArrayOutputStream(OutputStream):
    def __init__(self, size=32):
        self._buf = bytearray()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, size=32):
        ByteArrayOutputStream.__init__(self, size)

    def write_byte(self, value):
        self._buf.append(value & 0xFF)

    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._buf += to_py_bytes(buffer, offset, length)

    @jmethod("toByteArray", "()[B")
    def toByteArray(self):
        return to_java_bytes(self._buf)

    @jmethod("size", "()I")
    def size(self):
        return len(self._buf)

    @jmethod("reset", "()V")
    def reset(self):
        self._buf.clear()

    @jmethod("toString", "()Ljava/lang/String;")
    @jmethod("toString", "(Ljava/lang/String;)Ljava/lang/String;")
    def toString(self, charset=None):
        return jstr(bytes(self._buf).decode(_charset_name(charset) if charset else "utf-8", "replace"))


class _PathBase(Object):
    pass


@host_class("java.io.File", interfaces=("java.io.Serializable", "java.lang.Comparable"))
class File(Object):
    separator = "/"
    separatorChar = ord("/")
    pathSeparator = ":"

    def __init__(self, first=None, second=None):
        if second is None:
            path = pystr(first) if first is not None else runtime.npe()
        else:
            parent = first.getPath() if isinstance(first, File) else first
            path = os.path.join(pystr(parent), pystr(second)) if parent else "/" + pystr(second)
        self._path = path

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, path):
        File.__init__(self, path)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;Ljava/lang/String;)V")
    def _init2(self, parent, child):
        File.__init__(self, parent, child)

    def _access(self, mode):
        policy.check_path(self._path, mode)
        return self._path

    @jmethod("getPath", "()Ljava/lang/String;")
    def getPath(self):
        return jstr(self._path)

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return jstr(os.path.basename(self._path.rstrip("/")))

    @jmethod("getParent", "()Ljava/lang/String;")
    def getParent(self):
        parent = os.path.dirname(self._path.rstrip("/"))
        return jstr(parent) if parent else None

    @jmethod("getParentFile", "()Ljava/io/File;")
    def getParentFile(self):
        parent = self.getParent()
        return File(parent) if parent is not None else None

    @jmethod("isAbsolute", "()Z")
    def isAbsolute(self):
        return 1 if self._path.startswith("/") else 0

    @jmethod("getCanonicalFile", "()Ljava/io/File;")
    def getCanonicalFile(self):
        return File(os.path.realpath(self._path))

    @jmethod("toPath", "()Ljava/nio/file/Path;")
    def toPath(self):
        from .jfiles import Path
        return Path(self._path)

    @jmethod("setLastModified", "(J)Z")
    def setLastModified(self, millis):
        try:
            os.utime(self._access("write"), (millis / 1000.0, millis / 1000.0))
            return 1
        except OSError:
            return 0

    @jmethod("setReadable", "(Z)Z")
    @jmethod("setReadable", "(ZZ)Z")
    def setReadable(self, flag, owner_only=True):
        return self._chmod(0o444 if owner_only is False else 0o400, flag)

    @jmethod("setWritable", "(Z)Z")
    @jmethod("setWritable", "(ZZ)Z")
    def setWritable(self, flag, owner_only=True):
        return self._chmod(0o222 if owner_only is False else 0o200, flag)

    def _chmod(self, bits, flag):
        try:
            mode = os.stat(self._access("write")).st_mode & 0o7777
            os.chmod(self._path, mode | bits if flag else mode & ~bits)
            return 1
        except OSError:
            return 0

    @jstatic("createTempFile", "(Ljava/lang/String;Ljava/lang/String;)Ljava/io/File;")
    @jstatic("createTempFile", "(Ljava/lang/String;Ljava/lang/String;Ljava/io/File;)Ljava/io/File;")
    def createTempFile(prefix, suffix, directory=None):
        import tempfile
        if prefix is None or len(prefix) < 3:
            runtime.throw_new("java.lang.IllegalArgumentException", "Prefix string too short")
        folder = directory._path if directory is not None else None
        if folder is not None:
            policy.check_path(folder, "write")
        try:
            handle, name = tempfile.mkstemp(suffix=".tmp" if suffix is None else suffix, prefix=prefix, dir=folder)
        except OSError as error:
            runtime.throw_new("java.io.IOException", str(error))
        os.close(handle)
        return File(name)

    @jmethod("getAbsolutePath", "()Ljava/lang/String;")
    def getAbsolutePath(self):
        return jstr(os.path.abspath(self._path))

    @jmethod("getAbsoluteFile", "()Ljava/io/File;")
    def getAbsoluteFile(self):
        return File(self.getAbsolutePath())

    @jmethod("getCanonicalPath", "()Ljava/lang/String;")
    def getCanonicalPath(self):
        return jstr(os.path.realpath(self._path))

    @jmethod("exists", "()Z")
    def exists(self):
        return 1 if os.path.exists(self._access("stat")) else 0

    @jmethod("isFile", "()Z")
    def isFile(self):
        return 1 if os.path.isfile(self._access("stat")) else 0

    @jmethod("isDirectory", "()Z")
    def isDirectory(self):
        return 1 if os.path.isdir(self._access("stat")) else 0

    @jmethod("length", "()J")
    def length(self):
        try:
            return os.path.getsize(self._access("stat"))
        except OSError:
            return 0

    @jmethod("lastModified", "()J")
    def lastModified(self):
        try:
            return int(os.path.getmtime(self._access("stat")) * 1000)
        except OSError:
            return 0

    @jmethod("canRead", "()Z")
    def canRead(self):
        return 1 if os.access(self._access("stat"), os.R_OK) else 0

    @jmethod("canWrite", "()Z")
    def canWrite(self):
        return 1 if os.access(self._access("stat"), os.W_OK) else 0

    @jmethod("mkdir", "()Z")
    def mkdir(self):
        try:
            os.mkdir(self._access("write"))
            return 1
        except OSError:
            return 0

    @jmethod("mkdirs", "()Z")
    def mkdirs(self):
        try:
            os.makedirs(self._access("write"))
            return 1
        except OSError:
            return 0

    @jmethod("createNewFile", "()Z")
    def createNewFile(self):
        try:
            handle = os.open(self._access("write"), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o666)
        except FileExistsError:
            return 0
        except OSError as error:
            io_error(str(error))
        os.close(handle)
        return 1

    @jmethod("delete", "()Z")
    def delete(self):
        path = self._access("write")
        try:
            os.rmdir(path) if os.path.isdir(path) else os.remove(path)
            return 1
        except OSError:
            return 0

    @jmethod("renameTo", "(Ljava/io/File;)Z")
    def renameTo(self, other):
        try:
            os.rename(self._access("write"), other._access("write"))
            return 1
        except OSError:
            return 0

    @jmethod("list", "()[Ljava/lang/String;")
    def list(self):
        try:
            names = sorted(os.listdir(self._access("read")))
        except OSError:
            return None
        array = runtime.new_array("[Ljava/lang/String;", 0)
        array.extend(jstr(n) for n in names)
        return array

    @jmethod("listFiles", "()[Ljava/io/File;")
    def listFiles(self):
        names = self.list()
        if names is None:
            return None
        array = runtime.new_array("[Ljava/io/File;", 0)
        array.extend(File(self, n) for n in names)
        return array

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return jstr(self._path)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, File) and other._path == self._path else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._path) ^ 1234321

    @jmethod("compareTo", "(Ljava/io/File;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return (self._path > other._path) - (self._path < other._path)


def open_file(path, mode):
    """open a path through the policy; java errors for the failures a program handles"""
    policy.check_path(path, "write" if "w" in mode or "a" in mode or "+" in mode else "read")
    try:
        return open(path, mode)
    except FileNotFoundError:
        runtime.throw_new("java.io.FileNotFoundException", "%s (No such file or directory)" % path)
    except IsADirectoryError:
        runtime.throw_new("java.io.FileNotFoundException", "%s (Is a directory)" % path)
    except PermissionError:
        runtime.throw_new("java.io.FileNotFoundException", "%s (Permission denied)" % path)
    except OSError as error:
        runtime.throw_new("java.io.FileNotFoundException", "%s (%s)" % (path, error.strerror or error))


@host_class("java.io.FileInputStream")
class FileInputStream(InputStream):
    def __init__(self, target):
        self._f = open_file(target._path if isinstance(target, File) else pystr(target), "rb")

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init(self, target):
        FileInputStream.__init__(self, check_nonnull(target))

    def read_byte(self):
        data = self._f.read(1)
        return data[0] if data else -1

    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        data = self._f.read(length)
        if not data:
            return -1
        buffer[offset:offset + len(data)] = [b - 256 if b > 127 else b for b in data]
        return len(data)

    def available(self):
        try:
            return max(os.fstat(self._f.fileno()).st_size - self._f.tell(), 0)
        except OSError:
            return 0

    def close(self):
        self._f.close()


@host_class("java.io.FileOutputStream")
class FileOutputStream(OutputStream):
    def __init__(self, target, append=False):
        self._f = open_file(target._path if isinstance(target, File) else pystr(target), "ab" if append else "wb")

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init(self, target):
        FileOutputStream.__init__(self, check_nonnull(target))

    @jmethod("<init>", "(Ljava/lang/String;Z)V")
    @jmethod("<init>", "(Ljava/io/File;Z)V")
    def _init_append(self, target, append):
        FileOutputStream.__init__(self, check_nonnull(target), bool(append))

    def write_byte(self, value):
        self._f.write(bytes((value & 0xFF,)))

    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._f.write(to_py_bytes(buffer, offset, length))

    def flush(self):
        self._f.flush()

    def close(self):
        self._f.close()


@host_class("java.io.FilterInputStream")
class FilterInputStream(InputStream):
    def __init__(self, source):
        self._in = source

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    def _init(self, source):
        FilterInputStream.__init__(self, source)

    def read_byte(self):
        return self._in.read_byte() if hasattr(self._in, "read_byte") else self._in.read()

    def available(self):
        return self._in.available()

    def close(self):
        self._in.close()


@host_class("java.io.BufferedInputStream")
class BufferedInputStream(FilterInputStream):
    @jmethod("<init>", "(Ljava/io/InputStream;I)V")
    def _init_size(self, source, size):
        FilterInputStream.__init__(self, source)

    def read(self, buffer, offset=0, length=None):
        return self._in.read(buffer, offset, length) if length is not None else self._in.read(buffer)


@host_class("java.io.FilterOutputStream")
class FilterOutputStream(OutputStream):
    def __init__(self, sink):
        self._out = sink

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    def _init(self, sink):
        FilterOutputStream.__init__(self, sink)

    def write_byte(self, value):
        self._out.write_byte(value)

    def write(self, buffer, offset=0, length=None):
        self._out.write(buffer, offset, length) if length is not None else self._out.write(buffer)

    def flush(self):
        self._out.flush()

    def close(self):
        self._out.close()


@host_class("java.io.BufferedOutputStream")
class BufferedOutputStream(FilterOutputStream):
    @jmethod("<init>", "(Ljava/io/OutputStream;I)V")
    def _init_size(self, sink, size):
        FilterOutputStream.__init__(self, sink)


@host_class("java.io.DataInputStream", interfaces=("java.io.DataInput",))
class DataInputStream(FilterInputStream):
    def _take(self, count):
        data = bytearray()
        for _ in range(count):
            value = self._in.read_byte()
            if value == -1:
                runtime.throw_new("java.io.EOFException", None)
            data.append(value)
        return bytes(data)

    @jmethod("readInt", "()I")
    def readInt(self):
        return int.from_bytes(self._take(4), "big", signed=True)

    @jmethod("readLong", "()J")
    def readLong(self):
        return int.from_bytes(self._take(8), "big", signed=True)

    @jmethod("readShort", "()S")
    def readShort(self):
        return int.from_bytes(self._take(2), "big", signed=True)

    @jmethod("readUnsignedShort", "()I")
    def readUnsignedShort(self):
        return int.from_bytes(self._take(2), "big")

    @jmethod("readByte", "()B")
    def readByte(self):
        return int.from_bytes(self._take(1), "big", signed=True)

    @jmethod("readUnsignedByte", "()I")
    def readUnsignedByte(self):
        return self._take(1)[0]

    @jmethod("readBoolean", "()Z")
    def readBoolean(self):
        return 1 if self._take(1)[0] else 0

    @jmethod("readChar", "()C")
    def readChar(self):
        return int.from_bytes(self._take(2), "big")

    @jmethod("readFloat", "()F")
    def readFloat(self):
        return runtime.bits_to_float(int.from_bytes(self._take(4), "big", signed=True))

    @jmethod("readDouble", "()D")
    def readDouble(self):
        return runtime.bits_to_double(int.from_bytes(self._take(8), "big", signed=True))

    @jmethod("readFully", "([B)V")
    def readFully(self, buffer):
        data = self._take(len(buffer))
        buffer[:] = [b - 256 if b > 127 else b for b in data]

    @jmethod("readUTF", "()Ljava/lang/String;")
    def readUTF(self):
        size = int.from_bytes(self._take(2), "big")
        from .format import decode_mutf8
        raw = self._take(size)
        units = decode_mutf8(raw + b"\0", 0, len(raw) + 1, len(_mutf8_units(raw)))
        return units


def _mutf8_units(raw):
    count = 0
    index = 0
    while index < len(raw):
        lead = raw[index]
        index += 1 if lead < 0x80 else 2 if lead & 0xE0 == 0xC0 else 3
        count += 1
    return range(count)


host_class("java.io.DataInput", interface=True)(type("DataInput", (), {"__slots__": ()}))


@host_class("java.io.DataOutputStream", interfaces=("java.io.DataOutput",))
class DataOutputStream(FilterOutputStream):
    def _put(self, data):
        for byte in data:
            self._out.write_byte(byte)

    @jmethod("writeInt", "(I)V")
    def writeInt(self, value):
        self._put((value & 0xFFFFFFFF).to_bytes(4, "big"))

    @jmethod("writeLong", "(J)V")
    def writeLong(self, value):
        self._put((value & 0xFFFFFFFFFFFFFFFF).to_bytes(8, "big"))

    @jmethod("writeShort", "(I)V")
    @jmethod("writeChar", "(I)V")
    def writeShort(self, value):
        self._put((value & 0xFFFF).to_bytes(2, "big"))

    @jmethod("writeByte", "(I)V")
    def writeByte(self, value):
        self._put(bytes((value & 0xFF,)))

    @jmethod("writeBoolean", "(Z)V")
    def writeBoolean(self, value):
        self._put(bytes((1 if value else 0,)))

    @jmethod("writeFloat", "(F)V")
    def writeFloat(self, value):
        self._put((runtime.float_bits(value) & 0xFFFFFFFF).to_bytes(4, "big"))

    @jmethod("writeDouble", "(D)V")
    def writeDouble(self, value):
        self._put((runtime.double_bits(value) & 0xFFFFFFFFFFFFFFFF).to_bytes(8, "big"))

    @jmethod("writeUTF", "(Ljava/lang/String;)V")
    def writeUTF(self, text):
        from .format import encode_mutf8
        raw = encode_mutf8(text)
        if len(raw) > 65535:
            runtime.throw_new("java.io.UTFDataFormatException", "encoded string too long")
        self._put(len(raw).to_bytes(2, "big") + raw)


host_class("java.io.DataOutput", interface=True)(type("DataOutput", (), {"__slots__": ()}))


@host_class("java.io.Reader", interfaces=("java.io.Closeable",))
class Reader(Object):
    def __init__(self):
        pass

    @jmethod("read", "()I")
    def read_char(self):
        raise NotImplementedError

    @jmethod("read", "([C)I")
    @jmethod("read", "([CII)I")
    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        count = 0
        while count < length:
            if count and not self.ready():
                break
            value = self.read_char()
            if value == -1:
                break
            buffer[offset + count] = value
            count += 1
        return count if count or length == 0 else -1

    @jmethod("close", "()V")
    def close(self):
        return None

    @jmethod("ready", "()Z")
    def ready(self):
        return 1


@host_class("java.io.StringReader")
class StringReader(Reader):
    def __init__(self, text):
        self._s = text
        self._pos = 0

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, text):
        StringReader.__init__(self, check_nonnull(text))

    def read_char(self):
        if self._pos >= len(self._s):
            return -1
        value = ord(self._s[self._pos])
        self._pos += 1
        return value

    def ready(self):
        return 1


@host_class("java.io.InputStreamReader")
class InputStreamReader(Reader):
    """decodes the stream as it arrives: a read returns once the stream has handed over bytes, so a reader on a
    socket delivers a line without waiting for the peer to close"""

    def __init__(self, stream, charset="utf-8"):
        self._in = stream
        name = _charset_name(charset) if charset is not None else "utf-8"
        self._decoder = codecs.getincrementaldecoder(name)("replace")
        self._text = ""
        self._pos = 0
        self._eof = False
        self._chunk = runtime.new_array("[B", 8192)

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    def _init(self, stream):
        InputStreamReader.__init__(self, stream)

    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/nio/charset/Charset;)V")
    def _init_charset(self, stream, charset):
        InputStreamReader.__init__(self, stream, charset)

    def _fill(self):
        while self._pos >= len(self._text) and not self._eof:
            count = self._in.read(self._chunk, 0, len(self._chunk))
            if count < 0:
                self._text = jstr(self._decoder.decode(b"", True))
                self._eof = True
            else:
                self._text = jstr(self._decoder.decode(to_py_bytes(self._chunk, 0, count)))
            self._pos = 0

    def read_char(self):
        self._fill()
        if self._pos >= len(self._text):
            return -1
        value = ord(self._text[self._pos])
        self._pos += 1
        return value

    def ready(self):
        return 1 if self._pos < len(self._text) or (not self._eof and self._in.available() > 0) else 0

    def close(self):
        self._in.close()


@host_class("java.io.BufferedReader")
class BufferedReader(Reader):
    def __init__(self, source, size=8192):
        self._r = source

    @jmethod("<init>", "(Ljava/io/Reader;)V")
    @jmethod("<init>", "(Ljava/io/Reader;I)V")
    def _init(self, source, size=8192):
        BufferedReader.__init__(self, check_nonnull(source))

    _skip_lf = False

    def read_char(self):
        return self._next_char()

    def _next_char(self):
        value = self._r.read_char()
        if self._skip_lf:
            self._skip_lf = False
            if value == 10:
                value = self._r.read_char()
        return value

    def ready(self):
        return self._r.ready()

    @jmethod("readLine", "()Ljava/lang/String;")
    def readLine(self):
        chars = []
        while True:
            value = self._next_char()
            if value == -1:
                return "".join(chars) if chars else None
            if value == 10:
                return "".join(chars)
            if value == 13:
                # a \r ends the line; a \n right after it belongs to the same terminator
                self._skip_lf = True
                return "".join(chars)
            chars.append(chr(value))

    def close(self):
        self._r.close()


@host_class("java.io.Writer", interfaces=("java.io.Closeable", "java.io.Flushable"))
class Writer(Object):
    def __init__(self):
        pass

    @jmethod("write", "(I)V")
    def write_char(self, value):
        self.write_text(chr(value & 0xFFFF))

    def write_text(self, text):
        raise NotImplementedError

    @jmethod("write", "(Ljava/lang/String;)V")
    @jmethod("write", "([C)V")
    def write(self, text):
        self.write_text(text if isinstance(text, str) else "".join(map(chr, text)))

    @jmethod("append", "(Ljava/lang/CharSequence;)Ljava/io/Writer;")
    def append(self, text):
        self.write_text(jstring(text))
        return self

    @jmethod("flush", "()V")
    def flush(self):
        return None

    @jmethod("close", "()V")
    def close(self):
        return None


@host_class("java.io.StringWriter")
class StringWriter(Writer):
    def __init__(self, size=16):
        self._parts = []

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, size=16):
        StringWriter.__init__(self)

    def write_text(self, text):
        self._parts.append(text)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "".join(self._parts)

    @jmethod("getBuffer", "()Ljava/lang/StringBuffer;")
    def getBuffer(self):
        from .jlang import StringBuffer
        buffer = StringBuffer.__new__(StringBuffer)
        buffer._parts = ["".join(self._parts)]
        return buffer


@host_class("java.io.OutputStreamWriter")
class OutputStreamWriter(Writer):
    def __init__(self, stream, charset="utf-8"):
        self._out = stream
        self._charset = _charset_name(charset) if charset is not None else "utf-8"

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    def _init(self, stream):
        OutputStreamWriter.__init__(self, stream)

    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/nio/charset/Charset;)V")
    def _init_charset(self, stream, charset):
        OutputStreamWriter.__init__(self, stream, charset)

    def write_text(self, text):
        data = pystr(text).encode(self._charset, "replace")
        self._out.write(to_java_bytes(data), 0, len(data))

    def flush(self):
        self._out.flush()

    def close(self):
        self._out.close()


@host_class("java.io.BufferedWriter")
class BufferedWriter(Writer):
    def __init__(self, sink, size=8192):
        self._w = sink

    @jmethod("<init>", "(Ljava/io/Writer;)V")
    @jmethod("<init>", "(Ljava/io/Writer;I)V")
    def _init(self, sink, size=8192):
        BufferedWriter.__init__(self, check_nonnull(sink))

    def write_text(self, text):
        self._w.write_text(text)

    @jmethod("newLine", "()V")
    def newLine(self):
        self._w.write_text("\n")

    def flush(self):
        self._w.flush()

    def close(self):
        self._w.close()


@host_class("java.io.PrintWriter")
class PrintWriter(Writer):
    def __init__(self, target, autoflush=False):
        if isinstance(target, Writer):
            self._w = target
        else:
            self._w = OutputStreamWriter(target)

    @jmethod("<init>", "(Ljava/io/Writer;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/Writer;Z)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Z)V")
    def _init(self, target, autoflush=False):
        PrintWriter.__init__(self, check_nonnull(target), autoflush)

    def write_text(self, text):
        self._w.write_text(text)

    @jmethod("println", "()V")
    def _println0(self):
        self._w.write_text("\n")

    @jmethod("println", "(Ljava/lang/String;)V")
    @jmethod("println", "(Ljava/lang/Object;)V")
    def println(self, value):
        self._w.write_text(jstring(value) + "\n")

    @jmethod("println", "(I)V")
    @jmethod("println", "(J)V")
    def println_int(self, value):
        self._w.write_text(str(value) + "\n")

    @jmethod("print", "(Ljava/lang/String;)V")
    @jmethod("print", "(Ljava/lang/Object;)V")
    def print(self, value):
        self._w.write_text(jstring(value))

    @jmethod("print", "(I)V")
    @jmethod("print", "(J)V")
    def print_int(self, value):
        self._w.write_text(str(value))

    def flush(self):
        self._w.flush()

    def close(self):
        self._w.close()


@host_class("java.nio.charset.Charset", interfaces=("java.lang.Comparable",))
class Charset(Object):
    def __init__(self, name):
        self._name = name

    @jstatic("forName", "(Ljava/lang/String;)Ljava/nio/charset/Charset;")
    def forName(name):
        try:
            "".encode(_charset_name(name))
        except LookupError:
            runtime.throw_new("java.nio.charset.UnsupportedCharsetException", name)
        return Charset(name)

    @jstatic("defaultCharset", "()Ljava/nio/charset/Charset;")
    def defaultCharset():
        return StandardCharsets.UTF_8

    @jmethod("name", "()Ljava/lang/String;")
    @jmethod("displayName", "()Ljava/lang/String;")
    @jmethod("toString", "()Ljava/lang/String;")
    def name(self):
        return self._name

    @jstatic("isSupported", "(Ljava/lang/String;)Z")
    def isSupported(name):
        try:
            "".encode(_charset_name(name))
            return 1
        except LookupError:
            return 0

    @jmethod("newDecoder", "()Ljava/nio/charset/CharsetDecoder;")
    def newDecoder(self):
        from .jnio import CharsetDecoder
        return CharsetDecoder(self)

    @jmethod("newEncoder", "()Ljava/nio/charset/CharsetEncoder;")
    def newEncoder(self):
        from .jnio import CharsetEncoder
        return CharsetEncoder(self)

    @jmethod("canEncode", "()Z")
    def canEncode(self):
        return 1

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Charset) and other._name.lower() == self._name.lower() else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return hash(self._name.lower()) & 0x7FFFFFFF

    @jmethod("compareTo", "(Ljava/nio/charset/Charset;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        a, b = self._name.lower(), other._name.lower()
        return (a > b) - (a < b)


@host_class("java.nio.charset.StandardCharsets", final=True)
class StandardCharsets(Object):
    UTF_8 = Charset("UTF-8")
    US_ASCII = Charset("US-ASCII")
    ISO_8859_1 = Charset("ISO-8859-1")
    UTF_16 = Charset("UTF-16")
    UTF_16LE = Charset("UTF-16LE")
    UTF_16BE = Charset("UTF-16BE")
