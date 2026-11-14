"""java.io file readers and writers, RandomAccessFile, java.nio.file (Path, Paths, Files) and the zip streams

every path goes through policy.check_path, so FILE_ROOTS of an embedding holds for all of them. Path is a thin value over
a string: the operations a program needs to name, join and walk files, not the whole FileSystem provider interface"""

import os
import shutil
import struct
import zipfile
import zlib

from . import policy, runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jio import (File, FileInputStream, FileOutputStream, InputStream, InputStreamReader, OutputStream,
                  OutputStreamWriter, _check_range, io_error, open_file, to_java_bytes, to_py_bytes)
from .jlang import Object, jstr, pystr
from .jmap import ArrayList
from .jutil import PyIterator, check_nonnull, iterate


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


_define("""
java.nio.file.FileSystemException java.io.IOException
java.nio.file.NoSuchFileException java.nio.file.FileSystemException
java.nio.file.FileAlreadyExistsException java.nio.file.FileSystemException
java.nio.file.DirectoryNotEmptyException java.nio.file.FileSystemException
java.nio.file.NotDirectoryException java.nio.file.FileSystemException
java.nio.file.AccessDeniedException java.nio.file.FileSystemException
java.nio.file.InvalidPathException java.lang.IllegalArgumentException
java.io.InterruptedIOException java.io.IOException
""")


@host_class("java.io.FileReader")
class FileReader(InputStreamReader):
    def __init__(self, target, charset="utf-8"):
        InputStreamReader.__init__(self, FileInputStream(check_nonnull(target)), charset)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init1(self, target):
        FileReader.__init__(self, target)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/nio/charset/Charset;)V")
    @jmethod("<init>", "(Ljava/io/File;Ljava/nio/charset/Charset;)V")
    def _init2(self, target, charset):
        FileReader.__init__(self, target, charset)


@host_class("java.io.FileWriter")
class FileWriter(OutputStreamWriter):
    def __init__(self, target, append=False, charset="utf-8"):
        OutputStreamWriter.__init__(self, FileOutputStream(check_nonnull(target), bool(append)), charset)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init1(self, target):
        FileWriter.__init__(self, target)

    @jmethod("<init>", "(Ljava/lang/String;Z)V")
    @jmethod("<init>", "(Ljava/io/File;Z)V")
    def _init2(self, target, append):
        FileWriter.__init__(self, target, append)


@host_class("java.io.RandomAccessFile", interfaces=("java.io.Closeable", "java.io.DataInput", "java.io.DataOutput"))
class RandomAccessFile(Object):
    def __init__(self, target, mode):
        if mode not in ("r", "rw", "rws", "rwd"):
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal mode \"%s\" must be one of \"r\", \"rw\", "
                              "\"rws\", or \"rwd\"" % mode)
        path = target._path if isinstance(target, File) else pystr(target)
        if mode == "r":
            self._f = open_file(path, "rb")
        else:
            try:
                self._f = open_file(path, "r+b")
            except lookup_host("java.io.FileNotFoundException").py:
                if os.path.exists(path):
                    raise
                self._f = open_file(path, "w+b")
        self._read_only = mode == "r"

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;Ljava/lang/String;)V")
    def _init(self, target, mode):
        RandomAccessFile.__init__(self, check_nonnull(target), mode)

    def _take(self, count):
        data = self._f.read(count)
        if len(data) < count:
            runtime.throw_new("java.io.EOFException", None)
        return data

    @jmethod("read", "()I")
    def read_byte(self):
        data = self._f.read(1)
        return data[0] if data else -1

    @jmethod("read", "([B)I")
    @jmethod("read", "([BII)I")
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

    @jmethod("readFully", "([B)V")
    @jmethod("readFully", "([BII)V")
    def readFully(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        data = self._take(length)
        buffer[offset:offset + length] = [b - 256 if b > 127 else b for b in data]

    def _write(self, data):
        if self._read_only:
            io_error("Bad file descriptor")
        self._f.write(data)

    @jmethod("write", "(I)V")
    def write_byte(self, value):
        self._write(bytes((value & 0xFF,)))

    @jmethod("write", "([B)V")
    @jmethod("write", "([BII)V")
    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._write(to_py_bytes(buffer, offset, length))

    @jmethod("seek", "(J)V")
    def seek(self, position):
        if position < 0:
            io_error("offset < 0: %d" % position)
        self._f.seek(position)

    @jmethod("getFilePointer", "()J")
    def getFilePointer(self):
        return self._f.tell()

    @jmethod("length", "()J")
    def length(self):
        return os.fstat(self._f.fileno()).st_size

    @jmethod("setLength", "(J)V")
    def setLength(self, size):
        if self._read_only:
            io_error("Bad file descriptor")
        self._f.truncate(size)
        if self._f.tell() > size:
            self._f.seek(size)

    @jmethod("skipBytes", "(I)I")
    def skipBytes(self, count):
        if count <= 0:
            return 0
        position = self._f.tell()
        end = min(position + count, self.length())
        self._f.seek(end)
        return end - position

    @jmethod("close", "()V")
    def close(self):
        self._f.close()

    def _int(self, size, fmt):
        return struct.unpack(">" + fmt, self._take(size))[0]

    @jmethod("readInt", "()I")
    def readInt(self):
        return self._int(4, "i")

    @jmethod("readLong", "()J")
    def readLong(self):
        return self._int(8, "q")

    @jmethod("readShort", "()S")
    def readShort(self):
        return self._int(2, "h")

    @jmethod("readUnsignedShort", "()I")
    def readUnsignedShort(self):
        return self._int(2, "H")

    @jmethod("readByte", "()B")
    def readByte(self):
        return self._int(1, "b")

    @jmethod("readUnsignedByte", "()I")
    def readUnsignedByte(self):
        return self._int(1, "B")

    @jmethod("readBoolean", "()Z")
    def readBoolean(self):
        return 1 if self._take(1)[0] else 0

    @jmethod("readChar", "()C")
    def readChar(self):
        return self._int(2, "H")

    @jmethod("readFloat", "()F")
    def readFloat(self):
        return self._int(4, "f")

    @jmethod("readDouble", "()D")
    def readDouble(self):
        return self._int(8, "d")

    @jmethod("readLine", "()Ljava/lang/String;")
    def readLine(self):
        chars = bytearray()
        while True:
            data = self._f.read(1)
            if not data:
                return jstr(chars.decode("latin-1")) if chars else None
            if data == b"\n":
                return jstr(chars.decode("latin-1"))
            if data == b"\r":
                follow = self._f.read(1)
                if follow and follow != b"\n":
                    self._f.seek(-1, 1)
                return jstr(chars.decode("latin-1"))
            chars += data

    @jmethod("writeInt", "(I)V")
    def writeInt(self, value):
        self._write(struct.pack(">i", runtime.wrap32(value)))

    @jmethod("writeLong", "(J)V")
    def writeLong(self, value):
        self._write(struct.pack(">q", runtime.wrap64(value)))

    @jmethod("writeShort", "(I)V")
    @jmethod("writeChar", "(I)V")
    def writeShort(self, value):
        self._write((value & 0xFFFF).to_bytes(2, "big"))

    @jmethod("writeByte", "(I)V")
    def writeByte(self, value):
        self._write(bytes((value & 0xFF,)))

    @jmethod("writeBoolean", "(Z)V")
    def writeBoolean(self, value):
        self._write(b"\x01" if value else b"\x00")

    @jmethod("writeFloat", "(F)V")
    def writeFloat(self, value):
        self._write(struct.pack(">f", value))

    @jmethod("writeDouble", "(D)V")
    def writeDouble(self, value):
        self._write(struct.pack(">d", value))

    @jmethod("writeBytes", "(Ljava/lang/String;)V")
    def writeBytes(self, text):
        self._write(bytes(ord(c) & 0xFF for c in text))

    @jmethod("writeChars", "(Ljava/lang/String;)V")
    def writeChars(self, text):
        self._write(b"".join((ord(c) & 0xFFFF).to_bytes(2, "big") for c in text))


@host_class("java.nio.file.Path", interfaces=("java.lang.Comparable",))
class Path(Object):
    def __init__(self, text):
        if "\0" in text:
            runtime.throw_new("java.nio.file.InvalidPathException", "Nul character not allowed: " + text)
        self._p = os.path.normpath(text) if text else ""
        if text.startswith("//") and not text.startswith("///"):
            self._p = "/" + self._p.lstrip("/")

    @jstatic("of", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/nio/file/Path;")
    def of(first, more=None):
        return Paths.get(first, more)

    @jmethod("toFile", "()Ljava/io/File;")
    def toFile(self):
        return File(self._p)

    @jmethod("getFileName", "()Ljava/nio/file/Path;")
    def getFileName(self):
        name = os.path.basename(self._p)
        return Path(name) if name else None

    @jmethod("getParent", "()Ljava/nio/file/Path;")
    def getParent(self):
        parent = os.path.dirname(self._p)
        if not parent or parent == self._p:
            return None
        return Path(parent)

    @jmethod("getRoot", "()Ljava/nio/file/Path;")
    def getRoot(self):
        return Path("/") if self._p.startswith("/") else None

    @jmethod("isAbsolute", "()Z")
    def isAbsolute(self):
        return 1 if self._p.startswith("/") else 0

    @jmethod("toAbsolutePath", "()Ljava/nio/file/Path;")
    def toAbsolutePath(self):
        return Path(os.path.abspath(self._p))

    @jmethod("normalize", "()Ljava/nio/file/Path;")
    def normalize(self):
        return Path(os.path.normpath(self._p))

    @jmethod("resolve", "(Ljava/lang/String;)Ljava/nio/file/Path;")
    @jmethod("resolve", "(Ljava/nio/file/Path;)Ljava/nio/file/Path;")
    def resolve(self, other):
        text = other if isinstance(other, str) else other._p
        return Path(text if text.startswith("/") else (os.path.join(self._p, text) if self._p else text))

    @jmethod("resolveSibling", "(Ljava/lang/String;)Ljava/nio/file/Path;")
    def resolveSibling(self, other):
        parent = self.getParent()
        return Path(other) if parent is None else parent.resolve(other)

    @jmethod("relativize", "(Ljava/nio/file/Path;)Ljava/nio/file/Path;")
    def relativize(self, other):
        return Path(os.path.relpath(other._p, self._p or "."))

    @jmethod("startsWith", "(Ljava/lang/String;)Z")
    @jmethod("startsWith", "(Ljava/nio/file/Path;)Z")
    def startsWith(self, other):
        text = other if isinstance(other, str) else other._p
        return 1 if self._p == text or self._p.startswith(text.rstrip("/") + "/") else 0

    @jmethod("endsWith", "(Ljava/lang/String;)Z")
    @jmethod("endsWith", "(Ljava/nio/file/Path;)Z")
    def endsWith(self, other):
        text = other if isinstance(other, str) else other._p
        return 1 if self._p == text or self._p.endswith("/" + text) else 0

    @jmethod("getNameCount", "()I")
    def getNameCount(self):
        return len([part for part in self._p.split("/") if part])

    @jmethod("getName", "(I)Ljava/nio/file/Path;")
    def getName(self, index):
        parts = [part for part in self._p.split("/") if part]
        if not 0 <= index < len(parts):
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        return Path(parts[index])

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return PyIterator([Path(part) for part in self._p.split("/") if part])

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return jstr(self._p)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Path) and other._p == self._p else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._p)

    @jmethod("compareTo", "(Ljava/nio/file/Path;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return (self._p > other._p) - (self._p < other._p)


@host_class("java.nio.file.Paths", final=True)
class Paths(Object):
    @jstatic("get", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/nio/file/Path;")
    def get(first, more=None):
        parts = [check_nonnull(first)] + [part for part in (more or ()) if part]
        return Path("/".join(p for p in parts if p))


class _Option(Object):
    def __init__(self, name):
        self._name = name

    def toString(self):
        return self._name

    def name(self):
        return self._name


def _options(owner, names):
    for name in names:
        setattr(owner, name, _Option(name))


@host_class("java.nio.file.StandardOpenOption", final=True)
class StandardOpenOption(Object):
    pass


_options(StandardOpenOption, "READ WRITE APPEND TRUNCATE_EXISTING CREATE CREATE_NEW DELETE_ON_CLOSE SYNC DSYNC".split())


@host_class("java.nio.file.StandardCopyOption", final=True)
class StandardCopyOption(Object):
    pass


_options(StandardCopyOption, "REPLACE_EXISTING COPY_ATTRIBUTES ATOMIC_MOVE".split())


def _names(options):
    return {o._name for o in (options or ()) if isinstance(o, _Option)}


def _path_of(path):
    policy.check_path(path._p, "access")
    return path._p


def _fs_error(error, path):
    if isinstance(error, FileNotFoundError):
        runtime.throw_new("java.nio.file.NoSuchFileException", path)
    if isinstance(error, FileExistsError):
        runtime.throw_new("java.nio.file.FileAlreadyExistsException", path)
    if isinstance(error, NotADirectoryError):
        runtime.throw_new("java.nio.file.NotDirectoryException", path)
    if isinstance(error, PermissionError):
        runtime.throw_new("java.nio.file.AccessDeniedException", path)
    if isinstance(error, OSError) and error.errno == 39:
        runtime.throw_new("java.nio.file.DirectoryNotEmptyException", path)
    runtime.throw_new("java.io.IOException", str(error))


@host_class("java.nio.file.Files", final=True)
class Files(Object):
    @jstatic("exists", "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Z")
    def exists(path, options=None):
        return 1 if os.path.exists(_path_of(path)) else 0

    @jstatic("notExists", "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Z")
    def notExists(path, options=None):
        return 0 if os.path.exists(_path_of(path)) else 1

    @jstatic("isDirectory", "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Z")
    def isDirectory(path, options=None):
        return 1 if os.path.isdir(_path_of(path)) else 0

    @jstatic("isRegularFile", "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Z")
    def isRegularFile(path, options=None):
        return 1 if os.path.isfile(_path_of(path)) else 0

    @jstatic("isReadable", "(Ljava/nio/file/Path;)Z")
    def isReadable(path):
        return 1 if os.access(_path_of(path), os.R_OK) else 0

    @jstatic("isWritable", "(Ljava/nio/file/Path;)Z")
    def isWritable(path):
        return 1 if os.access(_path_of(path), os.W_OK) else 0

    @jstatic("size", "(Ljava/nio/file/Path;)J")
    def size(path):
        try:
            return os.path.getsize(_path_of(path))
        except OSError as error:
            _fs_error(error, path._p)

    @jstatic("readAllBytes", "(Ljava/nio/file/Path;)[B")
    def readAllBytes(path):
        try:
            with open(_path_of(path), "rb") as handle:
                return to_java_bytes(handle.read())
        except OSError as error:
            _fs_error(error, path._p)

    @jstatic("readString", "(Ljava/nio/file/Path;)Ljava/lang/String;")
    def readString(path):
        try:
            with open(_path_of(path), "rb") as handle:
                return jstr(handle.read().decode("utf-8"))
        except OSError as error:
            _fs_error(error, path._p)
        except UnicodeDecodeError:
            runtime.throw_new("java.nio.charset.MalformedInputException", "Input length = 1")

    @jstatic("readAllLines", "(Ljava/nio/file/Path;)Ljava/util/List;")
    def readAllLines(path):
        text = Files.readString(path)
        parts = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        if parts and parts[-1] == "":
            parts.pop()
        lines = ArrayList()
        for line in parts:
            lines.add(line)
        return lines

    @jstatic("write", "(Ljava/nio/file/Path;[B[Ljava/nio/file/OpenOption;)Ljava/nio/file/Path;")
    def write(path, data, options=None):
        names = _names(options)
        mode = "ab" if "APPEND" in names else "wb"
        if "CREATE_NEW" in names and os.path.exists(path._p):
            runtime.throw_new("java.nio.file.FileAlreadyExistsException", path._p)
        try:
            with open(_path_of(path), mode) as handle:
                handle.write(to_py_bytes(data))
        except OSError as error:
            _fs_error(error, path._p)
        return path

    @jstatic("writeString", "(Ljava/nio/file/Path;Ljava/lang/CharSequence;[Ljava/nio/file/OpenOption;)Ljava/nio/file/Path;")
    def writeString(path, text, options=None):
        data = pystr(text if isinstance(text, str) else text.toString()).encode("utf-8")
        return Files.write(path, to_java_bytes(data), options)

    @jstatic("createFile", "(Ljava/nio/file/Path;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;")
    def createFile(path, attributes=None):
        try:
            with open(_path_of(path), "xb"):
                pass
        except OSError as error:
            _fs_error(error, path._p)
        return path

    @jstatic("createDirectory", "(Ljava/nio/file/Path;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;")
    def createDirectory(path, attributes=None):
        try:
            os.mkdir(_path_of(path))
        except OSError as error:
            _fs_error(error, path._p)
        return path

    @jstatic("createDirectories", "(Ljava/nio/file/Path;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;")
    def createDirectories(path, attributes=None):
        try:
            os.makedirs(_path_of(path), exist_ok=True)
        except OSError as error:
            _fs_error(error, path._p)
        return path

    @jstatic("delete", "(Ljava/nio/file/Path;)V")
    def delete(path):
        target = _path_of(path)
        try:
            os.rmdir(target) if os.path.isdir(target) and not os.path.islink(target) else os.remove(target)
        except OSError as error:
            _fs_error(error, path._p)

    @jstatic("deleteIfExists", "(Ljava/nio/file/Path;)Z")
    def deleteIfExists(path):
        if not os.path.lexists(_path_of(path)):
            return 0
        Files.delete(path)
        return 1

    @jstatic("copy", "(Ljava/nio/file/Path;Ljava/nio/file/Path;[Ljava/nio/file/CopyOption;)Ljava/nio/file/Path;")
    def copy(source, target, options=None):
        if os.path.exists(_path_of(target)) and "REPLACE_EXISTING" not in _names(options):
            runtime.throw_new("java.nio.file.FileAlreadyExistsException", target._p)
        try:
            shutil.copyfile(_path_of(source), target._p) if not os.path.isdir(source._p) else os.mkdir(target._p)
        except OSError as error:
            _fs_error(error, source._p)
        return target

    @jstatic("move", "(Ljava/nio/file/Path;Ljava/nio/file/Path;[Ljava/nio/file/CopyOption;)Ljava/nio/file/Path;")
    def move(source, target, options=None):
        if os.path.exists(_path_of(target)) and "REPLACE_EXISTING" not in _names(options):
            runtime.throw_new("java.nio.file.FileAlreadyExistsException", target._p)
        try:
            os.replace(_path_of(source), target._p)
        except OSError as error:
            _fs_error(error, source._p)
        return target

    @jstatic("list", "(Ljava/nio/file/Path;)Ljava/util/stream/Stream;")
    def list(path):
        try:
            names = sorted(os.listdir(_path_of(path)))
        except OSError as error:
            _fs_error(error, path._p)
        from .jstream import Stream
        return Stream.from_items([Path(os.path.join(path._p, n)) for n in names])

    @jstatic("createTempFile", "(Ljava/lang/String;Ljava/lang/String;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;")
    def createTempFile(prefix, suffix, attributes=None):
        import tempfile
        handle, name = tempfile.mkstemp(suffix=suffix if suffix is not None else ".tmp", prefix=prefix or "")
        os.close(handle)
        return Path(name)

    @jstatic("newInputStream", "(Ljava/nio/file/Path;[Ljava/nio/file/OpenOption;)Ljava/io/InputStream;")
    def newInputStream(path, options=None):
        try:
            return FileInputStream(File(_path_of(path)))
        except lookup_host("java.io.FileNotFoundException").py:
            runtime.throw_new("java.nio.file.NoSuchFileException", path._p)

    @jstatic("newOutputStream", "(Ljava/nio/file/Path;[Ljava/nio/file/OpenOption;)Ljava/io/OutputStream;")
    def newOutputStream(path, options=None):
        return FileOutputStream(File(_path_of(path)), "APPEND" in _names(options))

    @jstatic("getLastModifiedTime", "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Ljava/nio/file/attribute/FileTime;")
    def getLastModifiedTime(path, options=None):
        runtime.throw_new("java.lang.UnsupportedOperationException", "FileTime is not implemented by this runtime")


@host_class("java.util.zip.ZipOutputStream", interfaces=("java.io.Closeable",))
class ZipOutputStream(OutputStream):
    """entries are collected in memory and written to the sink when the stream is finished or closed"""

    STORED = 0
    DEFLATED = 8
    MAX_BYTES = 64 * 1024 * 1024

    def __init__(self, sink, charset=None):
        self._sink = sink
        self._entries = []
        self._current = None
        self._data = bytearray()
        self._total = 0
        self._closed = False
        self._method = ZipOutputStream.DEFLATED
        self._level = -1
        self._comment = None

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/nio/charset/Charset;)V")
    def _init(self, sink, charset=None):
        ZipOutputStream.__init__(self, check_nonnull(sink), charset)

    @jmethod("setLevel", "(I)V")
    def setLevel(self, level):
        if level < -1 or level > 9:
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid compression level")
        self._level = level

    @jmethod("setMethod", "(I)V")
    def setMethod(self, method):
        self._method = method

    @jmethod("setComment", "(Ljava/lang/String;)V")
    def setComment(self, comment):
        self._comment = comment

    @jmethod("putNextEntry", "(Ljava/util/zip/ZipEntry;)V")
    def putNextEntry(self, entry):
        if self._closed:
            io_error("Stream closed")
        self.closeEntry()
        names = [e[0] for e in self._entries]
        if entry._name in names:
            runtime.throw_new("java.util.zip.ZipException", "duplicate entry: " + entry._name)
        self._current = entry
        self._data = bytearray()

    @jmethod("closeEntry", "()V")
    def closeEntry(self):
        if self._current is not None:
            self._entries.append((self._current._name, bytes(self._data), self._current))
            self._current = None
            self._data = bytearray()

    def _add(self, data):
        if self._current is None:
            runtime.throw_new("java.util.zip.ZipException", "no current ZIP entry")
        self._total += len(data)
        if self._total > ZipOutputStream.MAX_BYTES:
            io_error("archive is larger than %d bytes" % ZipOutputStream.MAX_BYTES)
        self._data += data

    def write_byte(self, value):
        self._add(bytes((value & 0xFF,)))

    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._add(to_py_bytes(buffer, offset, length))

    @jmethod("finish", "()V")
    def finish(self):
        if self._closed:
            return
        self.closeEntry()
        import io
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, data, entry in self._entries:
                info = zipfile.ZipInfo(pystr(name))
                info.compress_type = zipfile.ZIP_STORED if self._method == 0 else zipfile.ZIP_DEFLATED
                info.date_time = (1980, 1, 1, 0, 0, 0)
                archive.writestr(info, data, compresslevel=None if self._level < 0 else self._level)
            if self._comment is not None:
                archive.comment = pystr(self._comment).encode("utf-8")
        raw = buffer.getvalue()
        self._sink.write(to_java_bytes(raw), 0, len(raw))
        self._closed = True

    @jmethod("flush", "()V")
    def flush(self):
        return None

    @jmethod("close", "()V")
    def close(self):
        if not self._closed:
            self.finish()
        self._sink.close()


@host_class("java.util.zip.ZipInputStream", interfaces=("java.io.Closeable",))
class ZipInputStream(InputStream):
    """the archive is read whole (at most 64 MiB) when the first entry is asked for"""

    def __init__(self, source, charset=None):
        self._src = source
        self._names = None
        self._archive = None
        self._index = -1
        self._cur = None
        self._pos = 0

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/nio/charset/Charset;)V")
    def _init(self, source, charset=None):
        ZipInputStream.__init__(self, check_nonnull(source), charset)

    def _load(self):
        if self._archive is not None:
            return
        import io
        limit = 64 * 1024 * 1024
        data = bytearray()
        chunk = runtime.new_array("[B", 65536)
        while True:
            count = self._src.read(chunk, 0, 65536)
            if count < 0:
                break
            data += to_py_bytes(chunk, 0, count)
            if len(data) > limit:
                runtime.throw_new("java.util.zip.ZipException", "archive is larger than %d bytes" % limit)
        try:
            self._archive = zipfile.ZipFile(io.BytesIO(bytes(data)))
        except zipfile.BadZipFile as error:
            runtime.throw_new("java.util.zip.ZipException", str(error))
        self._names = self._archive.infolist()
        if len(self._names) > 4096:
            runtime.throw_new("java.util.zip.ZipException", "archive has more than 4096 entries")

    @jmethod("getNextEntry", "()Ljava/util/zip/ZipEntry;")
    def getNextEntry(self):
        from .jzip import ZipEntry
        self._load()
        self._index += 1
        if self._index >= len(self._names):
            self._cur = None
            return None
        info = self._names[self._index]
        if info.file_size > 64 * 1024 * 1024:
            runtime.throw_new("java.util.zip.ZipException", "entry is larger than 64 MiB")
        try:
            self._cur = self._archive.read(info)
        except (zipfile.BadZipFile, zlib.error, RuntimeError) as error:
            runtime.throw_new("java.util.zip.ZipException", str(error))
        self._pos = 0
        return ZipEntry(jstr(info.filename), info)

    @jmethod("closeEntry", "()V")
    def closeEntry(self):
        self._cur = None

    def read_byte(self):
        if self._cur is None or self._pos >= len(self._cur):
            return -1
        value = self._cur[self._pos]
        self._pos += 1
        return value

    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        if self._cur is None or self._pos >= len(self._cur):
            return -1
        data = self._cur[self._pos:self._pos + length]
        self._pos += len(data)
        buffer[offset:offset + len(data)] = [b - 256 if b > 127 else b for b in data]
        return len(data)

    def available(self):
        return 1 if self._cur is not None and self._pos < len(self._cur) else 0

    def close(self):
        self._src.close()
