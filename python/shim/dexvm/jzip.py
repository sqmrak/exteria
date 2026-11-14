"""random access to zip files for dex code; entries are read without extracting paths"""

import os
import zipfile
import zlib

from . import runtime
from .api import host_class, jmethod
from .jio import File, InputStream, _check_range, open_file
from .jlang import Object, jstr, pystr
from .jutil import PyIterator, check_nonnull

MAX_ARCHIVE = 64 * 1024 * 1024
MAX_ENTRY = 64 * 1024 * 1024
MAX_ENTRIES = 4096


def zip_error(error):
    runtime.throw_new("java.util.zip.ZipException", str(error))


@host_class("java.util.zip.ZipEntry")
class ZipEntry(Object):
    def __init__(self, name, info=None):
        self._name = jstr(check_nonnull(name))
        self._info = info

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, name):
        ZipEntry.__init__(self, name)

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("setSize", "(J)V")
    @jmethod("setCompressedSize", "(J)V")
    @jmethod("setCrc", "(J)V")
    @jmethod("setMethod", "(I)V")
    def setMetadata(self, value):
        """the size, crc and method of an entry that is written are taken from the data when the archive is finished, so a
        program that sets them for a STORED entry sets what the writer computes anyway"""
        if value < -1:
            runtime.throw_new("java.lang.IllegalArgumentException", "invalid entry value")

    @jmethod("isDirectory", "()Z")
    def isDirectory(self):
        return int(self._name.endswith("/"))

    @jmethod("getSize", "()J")
    def getSize(self):
        return self._info.file_size if self._info is not None else -1

    @jmethod("getCompressedSize", "()J")
    def getCompressedSize(self):
        return self._info.compress_size if self._info is not None else -1

    @jmethod("getCrc", "()J")
    def getCrc(self):
        return self._info.CRC if self._info is not None else -1

    @jmethod("getMethod", "()I")
    def getMethod(self):
        return self._info.compress_type if self._info is not None else -1

    @jmethod("getComment", "()Ljava/lang/String;")
    def getComment(self):
        if self._info is None or not self._info.comment:
            return None
        return jstr(self._info.comment.decode("utf-8", "replace"))

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._name


@host_class("java.util.zip.ZipFile$ZipFileInputStream")
class _EntryStream(InputStream):
    def __init__(self, owner, stream):
        self._owner = owner
        self._stream = stream
        self._closed = False

    def _read(self, size):
        if self._closed:
            runtime.throw_new("java.io.IOException", "stream closed")
        try:
            return self._stream.read(size)
        except (zipfile.BadZipFile, EOFError, OSError, RuntimeError, zlib.error) as error:
            zip_error(error)

    @jmethod("read", "()I")
    def read_byte(self):
        data = self._read(1)
        return data[0] if data else -1

    @jmethod("read", "([B)I")
    @jmethod("read", "([BII)I")
    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(check_nonnull(buffer))
        _check_range(buffer, offset, length)
        if not length:
            return 0
        data = self._read(length)
        if not data:
            return -1
        buffer[offset:offset + len(data)] = [byte if byte < 128 else byte - 256 for byte in data]
        return len(data)

    @jmethod("close", "()V")
    def close(self):
        if not self._closed:
            self._closed = True
            self._owner._streams.discard(self)
            self._stream.close()


@host_class("java.util.zip.ZipFile", interfaces=("java.io.Closeable",))
class ZipFile(Object):
    OPEN_READ = 1

    def __init__(self, target):
        target = check_nonnull(target)
        name = target._path if isinstance(target, File) else pystr(target)
        self._name = jstr(name)
        self._streams = set()
        self._file = open_file(name, "rb")
        self._zip = None
        try:
            if os.fstat(self._file.fileno()).st_size > MAX_ARCHIVE:
                zip_error("archive is larger than %d bytes" % MAX_ARCHIVE)
            self._zip = zipfile.ZipFile(self._file)
            if len(self._zip.infolist()) > MAX_ENTRIES:
                zip_error("archive has more than %d entries" % MAX_ENTRIES)
        except (zipfile.BadZipFile, OSError, ValueError) as error:
            self._file.close()
            zip_error(error)
        except BaseException:
            if self._zip is not None:
                self._zip.close()
            self._file.close()
            raise

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init(self, target):
        ZipFile.__init__(self, target)

    def _check_open(self):
        if self._zip is None:
            runtime.throw_new("java.lang.IllegalStateException", "zip file closed")

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("size", "()I")
    def size(self):
        self._check_open()
        return len(self._zip.infolist())

    @jmethod("getEntry", "(Ljava/lang/String;)Ljava/util/zip/ZipEntry;")
    def getEntry(self, name):
        self._check_open()
        name = pystr(check_nonnull(name))
        try:
            info = self._zip.getinfo(name)
        except KeyError:
            try:
                info = self._zip.getinfo(name + "/")
            except KeyError:
                return None
        return ZipEntry(info.filename, info)

    @jmethod("entries", "()Ljava/util/Enumeration;")
    def entries(self):
        self._check_open()
        return PyIterator([ZipEntry(info.filename, info) for info in self._zip.infolist()])

    @jmethod("getInputStream", "(Ljava/util/zip/ZipEntry;)Ljava/io/InputStream;")
    def getInputStream(self, entry):
        self._check_open()
        check_nonnull(entry)
        try:
            info = self._zip.getinfo(pystr(entry.getName()))
        except KeyError:
            return None
        if info.file_size > MAX_ENTRY:
            zip_error("entry is larger than %d bytes" % MAX_ENTRY)
        try:
            stream = _EntryStream(self, self._zip.open(info))
        except (zipfile.BadZipFile, OSError, RuntimeError, NotImplementedError) as error:
            zip_error(error)
        self._streams.add(stream)
        return stream

    @jmethod("close", "()V")
    def close(self):
        if self._zip is not None:
            for stream in tuple(self._streams):
                stream.close()
            self._zip.close()
            self._zip = None
            self._file.close()
