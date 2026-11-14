"""java.nio.file (walking, directory streams, attributes, matchers), java.nio.channels (file channels, socket channels, selectors, pipes) and the rest of
java.net (datagrams, cookies, IDN, authenticators, network interfaces)

a channel is a wrapper around a python file or socket; a selector is the selectors module of python. a SocketChannel in blocking mode behaves as a
Socket does, and in non-blocking mode read and write answer what the socket accepts at once"""

import fnmatch
import os
import re
import selectors
import socket
import stat
import struct
import threading
import time

from . import policy, runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jcore import _attach
from .jfiles import Files, Path
from .jio import FileInputStream, FileOutputStream, File, InputStream, OutputStream, to_java_bytes, to_py_bytes, io_error
from .jlang import Object, jstr, pystr
from .jmap import ArrayList, HashMap
from .jnet import InetAddress, InetSocketAddress, SocketAddress, _io_failure, _target
from .jnio import ByteBuffer
from .jutil import PyIterator, check_nonnull, iterate


def _taken(name):
    from . import api
    return name in api._classes or api._lazy.get(name, "dexvm.jnet2") != "dexvm.jnet2"


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        if not _taken(name):
            host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


def _interfaces(table):
    for line in table.strip().splitlines():
        name, *parents = line.split()
        if not _taken(name):
            host_class(name, interface=True, interfaces=tuple(parents))(type(name.rsplit(".", 1)[1], (), {"__slots__": ()}))


_define("""
java.nio.file.AtomicMoveNotSupportedException java.nio.file.FileSystemException
java.nio.file.FileSystemLoopException java.nio.file.FileSystemException
java.nio.file.NotLinkException java.nio.file.FileSystemException
java.nio.file.FileSystemNotFoundException java.lang.RuntimeException
java.nio.channels.ClosedChannelException java.io.IOException
java.nio.channels.AsynchronousCloseException java.nio.channels.ClosedChannelException
java.nio.channels.ClosedByInterruptException java.nio.channels.AsynchronousCloseException
java.nio.channels.NotYetConnectedException java.lang.IllegalStateException
java.nio.channels.NotYetBoundException java.lang.IllegalStateException
java.nio.channels.AlreadyBoundException java.lang.IllegalStateException
java.nio.channels.AlreadyConnectedException java.lang.IllegalStateException
java.nio.channels.ConnectionPendingException java.lang.IllegalStateException
java.nio.channels.NoConnectionPendingException java.lang.IllegalStateException
java.nio.channels.CancelledKeyException java.lang.IllegalStateException
java.nio.channels.ClosedSelectorException java.lang.IllegalStateException
java.nio.channels.IllegalBlockingModeException java.lang.IllegalStateException
java.nio.channels.IllegalSelectorException java.lang.IllegalArgumentException
java.nio.channels.NonReadableChannelException java.lang.IllegalStateException
java.nio.channels.NonWritableChannelException java.lang.IllegalStateException
java.nio.channels.OverlappingFileLockException java.lang.IllegalStateException
java.nio.channels.UnresolvedAddressException java.lang.IllegalArgumentException
java.nio.channels.UnsupportedAddressTypeException java.lang.IllegalArgumentException
""")

_interfaces("""
java.nio.file.CopyOption
java.nio.file.OpenOption
java.nio.file.Watchable
java.nio.file.PathMatcher
java.nio.file.FileVisitor
java.nio.file.DirectoryStream java.lang.Iterable java.io.Closeable
java.nio.channels.Channel java.io.Closeable
java.nio.channels.InterruptibleChannel java.nio.channels.Channel
java.nio.channels.ReadableByteChannel java.nio.channels.Channel
java.nio.channels.WritableByteChannel java.nio.channels.Channel
java.nio.channels.ByteChannel java.nio.channels.ReadableByteChannel java.nio.channels.WritableByteChannel
java.nio.channels.SeekableByteChannel java.nio.channels.ByteChannel
java.nio.channels.ScatteringByteChannel java.nio.channels.ReadableByteChannel
java.nio.channels.GatheringByteChannel java.nio.channels.WritableByteChannel
java.nio.channels.NetworkChannel java.nio.channels.Channel
java.net.SocketOption
java.net.ProtocolFamily
java.net.URLStreamHandlerFactory
java.net.ContentHandlerFactory
java.net.FileNameMap
""")


class _EnumLike(Object):
    def __init__(self, name, ordinal):
        self._name, self._ordinal = name, ordinal

    def name(self):
        return self._name

    def ordinal(self):
        return self._ordinal

    def toString(self):
        return self._name

    @classmethod
    def values(cls):
        array = runtime.new_array("[L%s;" % cls._jname.replace(".", "/"), 0)
        array.extend(cls._all)
        return array

    @classmethod
    def valueOf(cls, name):
        for item in cls._all:
            if item._name == name:
                return item
        runtime.throw_new("java.lang.IllegalArgumentException", "No enum constant %s.%s" % (cls._jname, name))


def _enum(jname, names, interfaces=()):
    cls = type(jname.rsplit(".", 1)[1], (_EnumLike,), {"_jname": jname, "_all": []})
    for index, name in enumerate(names):
        item = cls(name, index)
        setattr(cls, name, item)
        cls._all.append(item)
    return host_class(jname, interfaces=("java.lang.Comparable",) + tuple(interfaces))(cls)


LinkOption = _enum("java.nio.file.LinkOption", ["NOFOLLOW_LINKS"], ("java.nio.file.OpenOption", "java.nio.file.CopyOption"))
FileVisitResult = _enum("java.nio.file.FileVisitResult", ["CONTINUE", "TERMINATE", "SKIP_SUBTREE", "SKIP_SIBLINGS"])
FileVisitOption = _enum("java.nio.file.FileVisitOption", ["FOLLOW_LINKS"])
PosixFilePermission = _enum("java.nio.file.attribute.PosixFilePermission", [
    "OWNER_READ", "OWNER_WRITE", "OWNER_EXECUTE", "GROUP_READ", "GROUP_WRITE", "GROUP_EXECUTE", "OTHERS_READ", "OTHERS_WRITE", "OTHERS_EXECUTE"])
StandardProtocolFamily = _enum("java.net.StandardProtocolFamily", ["INET", "INET6"], ("java.net.ProtocolFamily",))
CookiePolicy = _enum("java.net.CookiePolicy", ["ACCEPT_ALL", "ACCEPT_NONE", "ACCEPT_ORIGINAL_SERVER"])


@host_class("java.nio.file.SimpleFileVisitor", interfaces=("java.nio.file.FileVisitor",))
class SimpleFileVisitor(Object):
    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("preVisitDirectory", "(Ljava/lang/Object;Ljava/nio/file/attribute/BasicFileAttributes;)Ljava/nio/file/FileVisitResult;")
    def preVisitDirectory(self, directory, attributes):
        return FileVisitResult.CONTINUE

    @jmethod("visitFile", "(Ljava/lang/Object;Ljava/nio/file/attribute/BasicFileAttributes;)Ljava/nio/file/FileVisitResult;")
    def visitFile(self, file, attributes):
        return FileVisitResult.CONTINUE

    @jmethod("visitFileFailed", "(Ljava/lang/Object;Ljava/io/IOException;)Ljava/nio/file/FileVisitResult;")
    def visitFileFailed(self, file, error):
        raise error

    @jmethod("postVisitDirectory", "(Ljava/lang/Object;Ljava/io/IOException;)Ljava/nio/file/FileVisitResult;")
    def postVisitDirectory(self, directory, error):
        if error is not None:
            raise error
        return FileVisitResult.CONTINUE


@host_class("java.nio.file.attribute.FileTime", interfaces=("java.lang.Comparable",))
class FileTime(Object):
    def __init__(self, millis):
        self._ms = millis

    @jstatic("fromMillis", "(J)Ljava/nio/file/attribute/FileTime;")
    def fromMillis(millis):
        return FileTime(millis)

    @jstatic("from", "(Ljava/time/Instant;)Ljava/nio/file/attribute/FileTime;")
    def from_(instant):
        return FileTime(instant.toEpochMilli())

    @jmethod("toMillis", "()J")
    def toMillis(self):
        return self._ms

    @jmethod("toInstant", "()Ljava/time/Instant;")
    def toInstant(self):
        return lookup_host("java.time.Instant").py.ofEpochMilli(self._ms)

    @jmethod("compareTo", "(Ljava/nio/file/attribute/FileTime;)I")
    def compareTo(self, other):
        return (self._ms > other._ms) - (self._ms < other._ms)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, FileTime) and other._ms == self._ms else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(self._ms ^ (self._ms >> 32))

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self.toInstant().toString()


setattr(FileTime, "from", FileTime.from_)


@host_class("java.nio.file.attribute.BasicFileAttributes", interface=True)
class _BasicAttributesMarker:
    __slots__ = ()


@host_class("java.nio.file.attribute.PosixFileAttributes", interfaces=("java.nio.file.attribute.BasicFileAttributes",))
class FileAttributes(Object):
    def __init__(self, status):
        self._st = status

    @jmethod("size", "()J")
    def size(self):
        return self._st.st_size

    @jmethod("isDirectory", "()Z")
    def isDirectory(self):
        return 1 if stat.S_ISDIR(self._st.st_mode) else 0

    @jmethod("isRegularFile", "()Z")
    def isRegularFile(self):
        return 1 if stat.S_ISREG(self._st.st_mode) else 0

    @jmethod("isSymbolicLink", "()Z")
    def isSymbolicLink(self):
        return 1 if stat.S_ISLNK(self._st.st_mode) else 0

    @jmethod("isOther", "()Z")
    def isOther(self):
        return 0 if stat.S_ISDIR(self._st.st_mode) or stat.S_ISREG(self._st.st_mode) or stat.S_ISLNK(self._st.st_mode) else 1

    @jmethod("lastModifiedTime", "()Ljava/nio/file/attribute/FileTime;")
    def lastModifiedTime(self):
        return FileTime(int(self._st.st_mtime * 1000))

    @jmethod("lastAccessTime", "()Ljava/nio/file/attribute/FileTime;")
    def lastAccessTime(self):
        return FileTime(int(self._st.st_atime * 1000))

    @jmethod("creationTime", "()Ljava/nio/file/attribute/FileTime;")
    def creationTime(self):
        return FileTime(int(getattr(self._st, "st_birthtime", self._st.st_ctime) * 1000))

    @jmethod("fileKey", "()Ljava/lang/Object;")
    def fileKey(self):
        return "(dev=%x,ino=%d)" % (self._st.st_dev, self._st.st_ino)

    @jmethod("permissions", "()Ljava/util/Set;")
    def permissions(self):
        return _permissions_of(self._st.st_mode)


def _permissions_of(mode):
    from .jmap import HashSet
    result = HashSet()
    for index, item in enumerate(PosixFilePermission._all):
        if mode & (1 << (8 - index)):
            result.add(item)
    return result


@host_class("java.nio.file.attribute.PosixFilePermissions", final=True)
class PosixFilePermissions(Object):
    @jstatic("toString", "(Ljava/util/Set;)Ljava/lang/String;")
    def toString(permissions):
        held = {p._ordinal for p in iterate(permissions)}
        return "".join(("rwx"[i % 3] if i in held else "-") for i in range(9))

    @jstatic("fromString", "(Ljava/lang/String;)Ljava/util/Set;")
    def fromString(text):
        from .jmap import HashSet
        if len(text) != 9 or any(c not in "rwx-" for c in text):
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid mode")
        result = HashSet()
        for index, char in enumerate(text):
            if char != "-":
                result.add(PosixFilePermission._all[index])
        return result


class _Glob:
    @staticmethod
    def regex(pattern):
        out, i = [], 0
        while i < len(pattern):
            c = pattern[i]
            if c == "*":
                if pattern[i:i + 2] == "**":
                    out.append(".*")
                    i += 1
                else:
                    out.append("[^/]*")
            elif c == "?":
                out.append("[^/]")
            elif c == "[":
                end = pattern.find("]", i + 1)
                out.append(pattern[i:end + 1].replace("[!", "[^") if end != -1 else "\\[")
                i = end if end != -1 else i
            elif c == "{":
                end = pattern.find("}", i)
                out.append("(?:" + "|".join(_Glob.regex(p) for p in pattern[i + 1:end].split(",")) + ")")
                i = end
            elif c == "\\":
                i += 1
                out.append(re.escape(pattern[i:i + 1]))
            else:
                out.append(re.escape(c))
            i += 1
        return "".join(out)


class _Matcher(Object):
    def __init__(self, pattern):
        self._re = pattern

    def matches(self, path):
        return 1 if self._re.fullmatch(path._p) else 0


host_class("java.nio.file.PathMatcher_Impl", interfaces=("java.nio.file.PathMatcher",))(_Matcher)


@host_class("java.nio.file.FileSystem", interfaces=("java.io.Closeable",))
class FileSystem(Object):
    @jmethod("getPath", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/nio/file/Path;")
    def getPath(self, first, more=None):
        return lookup_host("java.nio.file.Paths").py.get(first, more)

    @jmethod("getSeparator", "()Ljava/lang/String;")
    def getSeparator(self):
        return "/"

    @jmethod("isOpen", "()Z")
    def isOpen(self):
        return 1

    @jmethod("isReadOnly", "()Z")
    def isReadOnly(self):
        return 0

    @jmethod("close", "()V")
    def close(self):
        runtime.throw_new("java.lang.UnsupportedOperationException", None)

    @jmethod("getPathMatcher", "(Ljava/lang/String;)Ljava/nio/file/PathMatcher;")
    def getPathMatcher(self, spec):
        syntax, _, pattern = spec.partition(":")
        if syntax == "glob":
            return _Matcher(re.compile(_Glob.regex(pattern)))
        if syntax == "regex":
            return _Matcher(re.compile(pattern))
        runtime.throw_new("java.lang.UnsupportedOperationException", "Syntax '%s' not recognized" % syntax)

    @jmethod("getRootDirectories", "()Ljava/lang/Iterable;")
    def getRootDirectories(self):
        result = ArrayList()
        result.add(Path("/"))
        return result


@host_class("java.nio.file.FileSystems", final=True)
class FileSystems(Object):
    _default = None

    @jstatic("getDefault", "()Ljava/nio/file/FileSystem;")
    def getDefault():
        if FileSystems._default is None:
            FileSystems._default = FileSystem()
        return FileSystems._default


@host_class("java.nio.file.DirectoryStream_Impl", interfaces=("java.nio.file.DirectoryStream",))
class _DirectoryStream(Object):
    def __init__(self, items):
        self._items = items

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return PyIterator(list(self._items))

    @jmethod("close", "()V")
    def close(self):
        return None


def _walk(start, visitor, max_depth, follow):
    def attributes(path):
        try:
            return FileAttributes(os.stat(path) if follow else os.lstat(path))
        except OSError as error:
            return error

    def visit(path, depth):
        info = attributes(path)
        node = Path(path)
        if isinstance(info, OSError):
            return visitor.visitFileFailed(node, runtime.make_throwable(lookup_host("java.io.IOException").py, str(info)))
        if info.isDirectory() and depth < max_depth:
            result = visitor.preVisitDirectory(node, info)
            if result is FileVisitResult.SKIP_SUBTREE or result is FileVisitResult.SKIP_SIBLINGS:
                return FileVisitResult.CONTINUE if result is FileVisitResult.SKIP_SUBTREE else result
            if result is FileVisitResult.TERMINATE:
                return result
            error = None
            try:
                names = sorted(os.listdir(path))
            except OSError as exc:
                names, error = [], runtime.make_throwable(lookup_host("java.io.IOException").py, str(exc))
            for name in names:
                outcome = visit(os.path.join(path, name), depth + 1)
                if outcome is FileVisitResult.TERMINATE:
                    return outcome
                if outcome is FileVisitResult.SKIP_SIBLINGS:
                    break
            return visitor.postVisitDirectory(node, error)
        return visitor.visitFile(node, info)
    visit(start, 0)


def _stream_of(items):
    from .jstream import BaseStream
    return BaseStream.from_items(items)


def _attr(owner, name, descriptors, function):
    _attach(owner, name, descriptors, function)


def _new_directory_stream(path, glob=None):
    try:
        names = sorted(os.listdir(path._p))
    except OSError as error:
        from .jfiles import _fs_error
        _fs_error(error, path._p)
    if isinstance(glob, str):
        matcher = re.compile(_Glob.regex(glob))
        names = [n for n in names if matcher.fullmatch(n)]
    elif glob is not None:
        names = [n for n in names if glob.accept(Path(os.path.join(path._p, n)))]
    return _DirectoryStream([Path(os.path.join(path._p, n)) for n in names])


def _read_attributes(path, kind=None, *_options):
    from .jfiles import _fs_error
    try:
        return FileAttributes(os.stat(path._p) if not any(o is LinkOption.NOFOLLOW_LINKS for o in _options) else os.lstat(path._p))
    except OSError as error:
        _fs_error(error, path._p)


def _walk_file_tree(start, first, second=None, third=None):
    if third is not None:
        options, depth, visitor = first, second, third
    else:
        options, depth, visitor = None, 0x7FFFFFFF, first
    follow = options is not None and any(o is FileVisitOption.FOLLOW_LINKS for o in iterate(options))
    _walk(start._p, visitor, depth if depth is not None else 0x7FFFFFFF, follow)
    return start


def _files_walk(start, *args):
    depth = args[0] if args and isinstance(args[0], int) else 0x7FFFFFFF
    found = []

    class Collect:
        def preVisitDirectory(self, d, a):
            found.append(d)
            return FileVisitResult.CONTINUE

        def visitFile(self, f, a):
            found.append(f)
            return FileVisitResult.CONTINUE

        def visitFileFailed(self, f, e):
            raise e

        def postVisitDirectory(self, d, e):
            return FileVisitResult.CONTINUE
    _walk(start._p, Collect(), depth, False)
    return _stream_of(found)


def _files_find(start, depth, predicate, *_options):
    matched = [p for p in _files_walk(start, depth)._items if predicate.test(p, _read_attributes(p))]
    return _stream_of(matched)


def _set_modified(path, time):
    os.utime(path._p, (time._ms / 1000.0, time._ms / 1000.0))
    return path


def _read_lines_stream(path, *_charset):
    text = Files.readString(path)
    parts = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if parts and parts[-1] == "":
        parts.pop()
    return _stream_of([jstr(p) for p in parts])


def _new_reader(path, *_charset):
    return lookup_host("java.io.BufferedReader").py(lookup_host("java.io.InputStreamReader").py(FileInputStream(File(path._p))))


def _new_writer(path, *args):
    options = [a for a in args if hasattr(a, "_name")]
    append = any(getattr(o, "_name", "") == "APPEND" for o in options)
    return lookup_host("java.io.BufferedWriter").py(lookup_host("java.io.OutputStreamWriter").py(FileOutputStream(File(path._p), append)))


_attr(Files, "newDirectoryStream", ["(Ljava/nio/file/Path;)Ljava/nio/file/DirectoryStream;", "(Ljava/nio/file/Path;Ljava/lang/String;)Ljava/nio/file/DirectoryStream;"], _new_directory_stream)
_attr(Files, "readAttributes", ["(Ljava/nio/file/Path;Ljava/lang/Class;[Ljava/nio/file/LinkOption;)Ljava/nio/file/attribute/BasicFileAttributes;"], _read_attributes)
_attr(Files, "walkFileTree", ["(Ljava/nio/file/Path;Ljava/nio/file/FileVisitor;)Ljava/nio/file/Path;",
                              "(Ljava/nio/file/Path;Ljava/util/Set;ILjava/nio/file/FileVisitor;)Ljava/nio/file/Path;"], _walk_file_tree)
_attr(Files, "walk", ["(Ljava/nio/file/Path;[Ljava/nio/file/FileVisitOption;)Ljava/util/stream/Stream;", "(Ljava/nio/file/Path;I[Ljava/nio/file/FileVisitOption;)Ljava/util/stream/Stream;"], _files_walk)
_attr(Files, "find", ["(Ljava/nio/file/Path;ILjava/util/function/BiPredicate;[Ljava/nio/file/FileVisitOption;)Ljava/util/stream/Stream;"], _files_find)
_attr(Files, "getLastModifiedTime", ["(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Ljava/nio/file/attribute/FileTime;"],
      lambda path, *options: FileTime(int(os.stat(path._p).st_mtime * 1000)))
_attr(Files, "setLastModifiedTime", ["(Ljava/nio/file/Path;Ljava/nio/file/attribute/FileTime;)Ljava/nio/file/Path;"], _set_modified)
_attr(Files, "lines", ["(Ljava/nio/file/Path;)Ljava/util/stream/Stream;", "(Ljava/nio/file/Path;Ljava/nio/charset/Charset;)Ljava/util/stream/Stream;"], _read_lines_stream)
_attr(Files, "newBufferedReader", ["(Ljava/nio/file/Path;)Ljava/io/BufferedReader;", "(Ljava/nio/file/Path;Ljava/nio/charset/Charset;)Ljava/io/BufferedReader;"], _new_reader)
_attr(Files, "newBufferedWriter", ["(Ljava/nio/file/Path;[Ljava/nio/file/OpenOption;)Ljava/io/BufferedWriter;",
                                   "(Ljava/nio/file/Path;Ljava/nio/charset/Charset;[Ljava/nio/file/OpenOption;)Ljava/io/BufferedWriter;"], _new_writer)
_attr(Files, "isSymbolicLink", ["(Ljava/nio/file/Path;)Z"], lambda path: 1 if os.path.islink(path._p) else 0)
_attr(Files, "isHidden", ["(Ljava/nio/file/Path;)Z"], lambda path: 1 if os.path.basename(path._p).startswith(".") else 0)
_attr(Files, "isExecutable", ["(Ljava/nio/file/Path;)Z"], lambda path: 1 if os.access(path._p, os.X_OK) else 0)
_attr(Files, "isSameFile", ["(Ljava/nio/file/Path;Ljava/nio/file/Path;)Z"], lambda a, b: 1 if os.path.samefile(a._p, b._p) else 0)
_attr(Files, "readSymbolicLink", ["(Ljava/nio/file/Path;)Ljava/nio/file/Path;"], lambda path: Path(os.readlink(path._p)))
_attr(Files, "createSymbolicLink", ["(Ljava/nio/file/Path;Ljava/nio/file/Path;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;"],
      lambda link, target, *attributes: (os.symlink(target._p, link._p), link)[1])
_attr(Files, "getPosixFilePermissions", ["(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Ljava/util/Set;"], lambda path, *options: _permissions_of(os.stat(path._p).st_mode))
_attr(Files, "setPosixFilePermissions", ["(Ljava/nio/file/Path;Ljava/util/Set;)Ljava/nio/file/Path;"],
      lambda path, permissions: (os.chmod(path._p, sum(1 << (8 - p._ordinal) for p in iterate(permissions))), path)[1])
_attr(Files, "probeContentType", ["(Ljava/nio/file/Path;)Ljava/lang/String;"], lambda path: __import__("mimetypes").guess_type(path._p)[0])
_attr(Files, "createTempDirectory", ["(Ljava/lang/String;[Ljava/nio/file/attribute/FileAttribute;)Ljava/nio/file/Path;"],
      lambda prefix, *attributes: Path(__import__("tempfile").mkdtemp(prefix=prefix or "")))


class _Channel(Object):
    _open = True

    @jmethod("isOpen", "()Z")
    def isOpen(self):
        return 1 if self._open else 0

    def _need_open(self):
        if not self._open:
            runtime.throw_new("java.nio.channels.ClosedChannelException", None)

    @jmethod("close", "()V")
    def close(self):
        if self._open:
            self._open = False
            self._implClose()

    def _implClose(self):
        return None


def _drain(buffer, count=None):
    """the bytes in a ByteBuffer from its position, which moves"""
    count = buffer.remaining() if count is None else count
    data = buffer._raw(buffer._pos, count)
    buffer._pos += count
    return data


@host_class("java.nio.channels.FileChannel", interfaces=("java.nio.channels.SeekableByteChannel", "java.nio.channels.GatheringByteChannel",
                                                          "java.nio.channels.ScatteringByteChannel"))
class FileChannel(_Channel):
    class MapMode(Object):
        pass

    def __init__(self, handle, readable, writable, append=False):
        self._f, self._readable, self._writable, self._append = handle, readable, writable, append

    @jstatic("open", "(Ljava/nio/file/Path;[Ljava/nio/file/OpenOption;)Ljava/nio/channels/FileChannel;")
    def open(path, *options):
        names = {o._name for o in iterate(options[0]) if hasattr(o, "_name")} if options and not hasattr(options[0], "_name") else {
            o._name for o in options if hasattr(o, "_name")}
        write = bool(names & {"WRITE", "APPEND"})
        read = "READ" in names or not write
        mode = "r+b" if write else "rb"
        if write and ("CREATE" in names or "CREATE_NEW" in names) and not os.path.exists(path._p):
            open(path._p, "xb" if "CREATE_NEW" in names else "ab").close()
        elif "CREATE_NEW" in names and os.path.exists(path._p):
            runtime.throw_new("java.nio.file.FileAlreadyExistsException", path._p)
        policy.check_path(path._p, "write" if write else "read")
        try:
            handle = open(path._p, mode)
        except FileNotFoundError:
            runtime.throw_new("java.nio.file.NoSuchFileException", path._p)
        if "TRUNCATE_EXISTING" in names and write:
            handle.truncate(0)
        return FileChannel(handle, read, write, "APPEND" in names)

    def _implClose(self):
        self._f.close()

    @jmethod("read", "(Ljava/nio/ByteBuffer;)I")
    @jmethod("read", "(Ljava/nio/ByteBuffer;J)I")
    def read(self, buffer, position=None):
        self._need_open()
        if not self._readable:
            runtime.throw_new("java.nio.channels.NonReadableChannelException", None)
        if buffer.remaining() == 0:
            return 0
        if position is not None:
            here = self._f.tell()
            self._f.seek(position)
            data = self._f.read(buffer.remaining())
            self._f.seek(here)
        else:
            data = self._f.read(buffer.remaining())
        if not data:
            return -1
        buffer.put(to_java_bytes(data))
        return len(data)

    @jmethod("write", "(Ljava/nio/ByteBuffer;)I")
    @jmethod("write", "(Ljava/nio/ByteBuffer;J)I")
    def write(self, buffer, position=None):
        self._need_open()
        if not self._writable:
            runtime.throw_new("java.nio.channels.NonWritableChannelException", None)
        data = _drain(buffer)
        if position is not None:
            here = self._f.tell()
            self._f.seek(position)
            self._f.write(data)
            self._f.seek(here)
        else:
            if self._append:
                self._f.seek(0, 2)
            self._f.write(data)
        return len(data)

    @jmethod("position", "()J")
    @jmethod("position", "(J)Ljava/nio/channels/FileChannel;")
    def position(self, value=None):
        self._need_open()
        if value is None:
            return self._f.tell()
        if value < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        self._f.seek(value)
        return self

    @jmethod("size", "()J")
    def size(self):
        self._need_open()
        return os.fstat(self._f.fileno()).st_size

    @jmethod("truncate", "(J)Ljava/nio/channels/FileChannel;")
    def truncate(self, size):
        self._need_open()
        if not self._writable:
            runtime.throw_new("java.nio.channels.NonWritableChannelException", None)
        if size < self.size():
            self._f.truncate(size)
        if self._f.tell() > size:
            self._f.seek(size)
        return self

    @jmethod("force", "(Z)V")
    def force(self, metadata):
        self._f.flush()
        os.fsync(self._f.fileno())

    @jmethod("transferTo", "(JJLjava/nio/channels/WritableByteChannel;)J")
    def transferTo(self, position, count, target):
        here = self._f.tell()
        self._f.seek(position)
        data = self._f.read(count)
        self._f.seek(here)
        target.write(ByteBuffer.wrap(to_java_bytes(data)))
        return len(data)

    @jmethod("transferFrom", "(Ljava/nio/channels/ReadableByteChannel;JJ)J")
    def transferFrom(self, source, position, count):
        buffer = ByteBuffer.allocate(int(min(count, 1 << 20)))
        total = 0
        while total < count:
            buffer.clear()
            buffer.limit(int(min(buffer.capacity(), count - total)))
            got = source.read(buffer)
            if got <= 0:
                break
            buffer.flip()
            self.write(buffer, position + total)
            total += got
        return total

    @jmethod("lock", "()Ljava/nio/channels/FileLock;")
    @jmethod("lock", "(JJZ)Ljava/nio/channels/FileLock;")
    def lock(self, position=0, size=0x7FFFFFFFFFFFFFFF, shared=False):
        import fcntl
        fcntl.flock(self._f.fileno(), fcntl.LOCK_SH if shared else fcntl.LOCK_EX)
        return FileLock(self, position, size, shared)

    @jmethod("tryLock", "()Ljava/nio/channels/FileLock;")
    @jmethod("tryLock", "(JJZ)Ljava/nio/channels/FileLock;")
    def tryLock(self, position=0, size=0x7FFFFFFFFFFFFFFF, shared=False):
        import fcntl
        try:
            fcntl.flock(self._f.fileno(), (fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB)
        except OSError:
            return None
        return FileLock(self, position, size, shared)

    @jmethod("map", "(Ljava/nio/channels/FileChannel$MapMode;JJ)Ljava/nio/MappedByteBuffer;")
    def map(self, mode, position, size):
        runtime.throw_new("java.lang.UnsupportedOperationException", "memory mapped files are not implemented, read the bytes into a ByteBuffer")


@host_class("java.nio.channels.FileLock", interfaces=("java.lang.AutoCloseable",))
class FileLock(Object):
    def __init__(self, channel, position, size, shared):
        self._ch, self._pos, self._size, self._shared, self._valid = channel, position, size, shared, True

    @jmethod("isValid", "()Z")
    def isValid(self):
        return 1 if self._valid and self._ch._open else 0

    @jmethod("isShared", "()Z")
    def isShared(self):
        return 1 if self._shared else 0

    @jmethod("position", "()J")
    def position(self):
        return self._pos

    @jmethod("size", "()J")
    def size(self):
        return self._size

    @jmethod("channel", "()Ljava/nio/channels/FileChannel;")
    def channel(self):
        return self._ch

    @jmethod("release", "()V")
    @jmethod("close", "()V")
    def release(self):
        if self._valid:
            import fcntl
            self._valid = False
            if self._ch._open:
                fcntl.flock(self._ch._f.fileno(), fcntl.LOCK_UN)


def _file_channel(self):
    return FileChannel(self._f, True, False)


FileInputStream.getChannel = _file_channel
FileOutputStream.getChannel = lambda self: FileChannel(self._f, False, True)
for _name in ("getChannel",):
    for _cls, _sig in ((FileInputStream, "()Ljava/nio/channels/FileChannel;"), (FileOutputStream, "()Ljava/nio/channels/FileChannel;")):
        _fn = getattr(_cls, _name)
        _fn._jsigs = [(_name, _sig)]
        _cls.__dict__  # noqa: B018
host_class  # keep import used


@host_class("java.nio.channels.Channels", final=True)
class Channels(Object):
    @jstatic("newChannel", "(Ljava/io/InputStream;)Ljava/nio/channels/ReadableByteChannel;")
    @jstatic("newChannel", "(Ljava/io/OutputStream;)Ljava/nio/channels/WritableByteChannel;")
    def newChannel(stream):
        return _StreamChannel(stream)

    @jstatic("newInputStream", "(Ljava/nio/channels/ReadableByteChannel;)Ljava/io/InputStream;")
    def newInputStream(channel):
        return _ChannelInput(channel)

    @jstatic("newOutputStream", "(Ljava/nio/channels/WritableByteChannel;)Ljava/io/OutputStream;")
    def newOutputStream(channel):
        return _ChannelOutput(channel)

    @jstatic("newReader", "(Ljava/nio/channels/ReadableByteChannel;Ljava/lang/String;)Ljava/io/Reader;")
    def newReader(channel, charset):
        return lookup_host("java.io.InputStreamReader").py(_ChannelInput(channel), charset)

    @jstatic("newWriter", "(Ljava/nio/channels/WritableByteChannel;Ljava/lang/String;)Ljava/io/Writer;")
    def newWriter(channel, charset):
        return lookup_host("java.io.OutputStreamWriter").py(_ChannelOutput(channel), charset)


@host_class("java.nio.channels.Channels$StreamChannel", interfaces=("java.nio.channels.ByteChannel",))
class _StreamChannel(_Channel):
    def __init__(self, stream):
        self._s = stream

    def read(self, buffer):
        self._need_open()
        chunk = runtime.new_array("[B", max(1, buffer.remaining()))
        count = self._s.read(chunk, 0, len(chunk))
        if count > 0:
            buffer.put(chunk, 0, count)
        return count

    def write(self, buffer):
        self._need_open()
        data = _drain(buffer)
        self._s.write(to_java_bytes(data), 0, len(data))
        return len(data)

    def _implClose(self):
        self._s.close()


class _ChannelInput(InputStream):
    def __init__(self, channel):
        self._c = channel

    def read_byte(self):
        buffer = ByteBuffer.allocate(1)
        return -1 if self._c.read(buffer) <= 0 else (buffer._raw(0, 1)[0])

    def read(self, array, offset=0, length=None):
        length = len(array) - offset if length is None else length
        if length == 0:
            return 0
        buffer = ByteBuffer.allocate(length)
        count = self._c.read(buffer)
        if count > 0:
            array[offset:offset + count] = list(buffer._arr[:count])
        return count

    def close(self):
        self._c.close()


class _ChannelOutput(OutputStream):
    def __init__(self, channel):
        self._c = channel

    def write_byte(self, value):
        self._c.write(ByteBuffer.wrap(to_java_bytes(bytes((value & 0xFF,)))))

    def write(self, array, offset=0, length=None):
        length = len(array) - offset if length is None else length
        self._c.write(ByteBuffer.wrap(array, offset, length))

    def close(self):
        self._c.close()


class _SelectableChannel(_Channel):
    _blocking = True

    @jmethod("configureBlocking", "(Z)Ljava/nio/channels/SelectableChannel;")
    def configureBlocking(self, blocking):
        self._need_open()
        self._blocking = bool(blocking)
        self._sock.setblocking(bool(blocking))
        return self

    @jmethod("isBlocking", "()Z")
    def isBlocking(self):
        return 1 if self._blocking else 0

    @jmethod("register", "(Ljava/nio/channels/Selector;I)Ljava/nio/channels/SelectionKey;")
    @jmethod("register", "(Ljava/nio/channels/Selector;ILjava/lang/Object;)Ljava/nio/channels/SelectionKey;")
    def register(self, selector, ops, attachment=None):
        self._need_open()
        return selector._register(self, ops, attachment)

    @jmethod("keyFor", "(Ljava/nio/channels/Selector;)Ljava/nio/channels/SelectionKey;")
    def keyFor(self, selector):
        return selector._keys.get(id(self))

    @jmethod("isRegistered", "()Z")
    def isRegistered(self):
        return 1 if getattr(self, "_registered", False) else 0

    @jmethod("validOps", "()I")
    def validOps(self):
        return 0x1D

    def _implClose(self):
        try:
            self._sock.close()
        finally:
            for selector in list(getattr(self, "_selectors", ())):
                selector._forget(self)


host_class("java.nio.channels.SelectableChannel", interfaces=("java.nio.channels.InterruptibleChannel",))(_SelectableChannel)


@host_class("java.nio.channels.SocketChannel", interfaces=("java.nio.channels.ByteChannel", "java.nio.channels.NetworkChannel",
                                                            "java.nio.channels.ScatteringByteChannel", "java.nio.channels.GatheringByteChannel"),
            superclass="java.nio.channels.SelectableChannel")
class SocketChannel(_SelectableChannel):
    def __init__(self, sock=None):
        self._sock = sock or socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._connected = sock is not None
        self._pending = False
        self._remote = None

    @jstatic("open", "()Ljava/nio/channels/SocketChannel;")
    @jstatic("open", "(Ljava/net/SocketAddress;)Ljava/nio/channels/SocketChannel;")
    def open(address=None):
        channel = SocketChannel()
        if address is not None:
            channel.connect(address)
        return channel

    @jmethod("connect", "(Ljava/net/SocketAddress;)Z")
    def connect(self, address):
        self._need_open()
        host, port = _target(address) if not address._unresolved else runtime.throw_new("java.nio.channels.UnresolvedAddressException", None)
        self._remote = address
        if self._blocking:
            try:
                self._sock.connect((host, port))
            except OSError as error:
                _io_failure(error, address._host)
            self._connected = True
            return 1
        error = self._sock.connect_ex((host, port))
        if error in (0,):
            self._connected = True
            return 1
        self._pending = True
        return 0

    @jmethod("finishConnect", "()Z")
    def finishConnect(self):
        if self._connected:
            return 1
        if not self._pending:
            runtime.throw_new("java.nio.channels.NoConnectionPendingException", None)
        code = self._sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
        if code == 0:
            import select
            _, writable, _ = select.select([], [self._sock], [], 0)
            if writable:
                self._connected, self._pending = True, False
                return 1
            return 0
        self._pending = False
        _io_failure(OSError(code, os.strerror(code)), getattr(self._remote, "_host", None))

    @jmethod("isConnected", "()Z")
    def isConnected(self):
        return 1 if self._connected else 0

    @jmethod("isConnectionPending", "()Z")
    def isConnectionPending(self):
        return 1 if self._pending else 0

    @jmethod("read", "(Ljava/nio/ByteBuffer;)I")
    def read(self, buffer):
        self._need_open()
        if not self._connected:
            runtime.throw_new("java.nio.channels.NotYetConnectedException", None)
        if buffer.remaining() == 0:
            return 0
        try:
            data = self._sock.recv(buffer.remaining())
        except (BlockingIOError, InterruptedError):
            return 0
        except OSError as error:
            _io_failure(error)
        if not data:
            return -1
        buffer.put(to_java_bytes(data))
        return len(data)

    @jmethod("write", "(Ljava/nio/ByteBuffer;)I")
    def write(self, buffer):
        self._need_open()
        if not self._connected:
            runtime.throw_new("java.nio.channels.NotYetConnectedException", None)
        data = buffer._raw(buffer._pos, buffer.remaining())
        try:
            sent = self._sock.send(data)
        except (BlockingIOError, InterruptedError):
            return 0
        except OSError as error:
            _io_failure(error)
        buffer._pos += sent
        return sent

    @jmethod("socket", "()Ljava/net/Socket;")
    def socket_(self):
        from .jnet import Socket
        wrapper = Socket()
        wrapper._attach(self._sock, self._remote or InetSocketAddress(InetAddress._make(None, "0.0.0.0"), 0))
        return wrapper

    @jmethod("shutdownInput", "()Ljava/nio/channels/SocketChannel;")
    def shutdownInput(self):
        self._sock.shutdown(socket.SHUT_RD)
        return self

    @jmethod("shutdownOutput", "()Ljava/nio/channels/SocketChannel;")
    def shutdownOutput(self):
        self._sock.shutdown(socket.SHUT_WR)
        return self

    @jmethod("getRemoteAddress", "()Ljava/net/SocketAddress;")
    def getRemoteAddress(self):
        return self._remote

    @jmethod("getLocalAddress", "()Ljava/net/SocketAddress;")
    def getLocalAddress(self):
        host, port = self._sock.getsockname()[:2]
        return InetSocketAddress(InetAddress._make(None, host), port)

    @jmethod("bind", "(Ljava/net/SocketAddress;)Ljava/nio/channels/SocketChannel;")
    def bind(self, address):
        host, port = _target(address)
        self._sock.bind((host, port))
        return self

    @jmethod("setOption", "(Ljava/net/SocketOption;Ljava/lang/Object;)Ljava/nio/channels/SocketChannel;")
    def setOption(self, option, value):
        _set_option(self._sock, option, value)
        return self


setattr(SocketChannel, "socket", SocketChannel.socket_)


def _set_option(sock, option, value):
    value = value.value if hasattr(value, "value") else value
    table = {"TCP_NODELAY": (socket.IPPROTO_TCP, socket.TCP_NODELAY), "SO_KEEPALIVE": (socket.SOL_SOCKET, socket.SO_KEEPALIVE),
             "SO_REUSEADDR": (socket.SOL_SOCKET, socket.SO_REUSEADDR), "SO_RCVBUF": (socket.SOL_SOCKET, socket.SO_RCVBUF),
             "SO_SNDBUF": (socket.SOL_SOCKET, socket.SO_SNDBUF), "SO_BROADCAST": (socket.SOL_SOCKET, socket.SO_BROADCAST)}
    found = table.get(option._name)
    if found is None:
        runtime.throw_new("java.lang.UnsupportedOperationException", "'%s' not supported" % option._name)
    sock.setsockopt(found[0], found[1], int(value))


@host_class("java.nio.channels.ServerSocketChannel", interfaces=("java.nio.channels.NetworkChannel",), superclass="java.nio.channels.SelectableChannel")
class ServerSocketChannel(_SelectableChannel):
    def __init__(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._bound = False

    @jstatic("open", "()Ljava/nio/channels/ServerSocketChannel;")
    def open():
        return ServerSocketChannel()

    @jmethod("bind", "(Ljava/net/SocketAddress;)Ljava/nio/channels/ServerSocketChannel;")
    @jmethod("bind", "(Ljava/net/SocketAddress;I)Ljava/nio/channels/ServerSocketChannel;")
    def bind(self, address, backlog=50):
        self._need_open()
        host = "0.0.0.0" if address is None else _target(address)[0]
        port = 0 if address is None else address._port
        try:
            self._sock.bind((host, port))
            self._sock.listen(backlog if backlog > 0 else 50)
        except OSError as error:
            runtime.throw_new("java.net.BindException", "bind failed: %s" % error)
        self._bound = True
        return self

    @jmethod("accept", "()Ljava/nio/channels/SocketChannel;")
    def accept(self):
        self._need_open()
        if not self._bound:
            runtime.throw_new("java.nio.channels.NotYetBoundException", None)
        try:
            conn, peer = self._sock.accept()
        except (BlockingIOError, InterruptedError):
            return None
        except OSError as error:
            _io_failure(error)
        channel = SocketChannel(conn)
        channel._remote = InetSocketAddress(InetAddress._make(None, peer[0]), peer[1])
        return channel

    @jmethod("getLocalAddress", "()Ljava/net/SocketAddress;")
    def getLocalAddress(self):
        host, port = self._sock.getsockname()[:2]
        return InetSocketAddress(InetAddress._make(None, host), port)

    @jmethod("socket", "()Ljava/net/ServerSocket;")
    def socket_(self):
        runtime.throw_new("java.lang.UnsupportedOperationException", "use the channel itself")

    @jmethod("setOption", "(Ljava/net/SocketOption;Ljava/lang/Object;)Ljava/nio/channels/ServerSocketChannel;")
    def setOption(self, option, value):
        _set_option(self._sock, option, value)
        return self


@host_class("java.nio.channels.DatagramChannel", interfaces=("java.nio.channels.ByteChannel", "java.nio.channels.NetworkChannel"),
            superclass="java.nio.channels.SelectableChannel")
class DatagramChannel(_SelectableChannel):
    def __init__(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._peer = None

    @jstatic("open", "()Ljava/nio/channels/DatagramChannel;")
    @jstatic("open", "(Ljava/net/ProtocolFamily;)Ljava/nio/channels/DatagramChannel;")
    def open(family=None):
        return DatagramChannel()

    @jmethod("bind", "(Ljava/net/SocketAddress;)Ljava/nio/channels/DatagramChannel;")
    def bind(self, address):
        host, port = ("0.0.0.0", 0) if address is None else _target(address)
        self._sock.bind((host, port))
        return self

    @jmethod("connect", "(Ljava/net/SocketAddress;)Ljava/nio/channels/DatagramChannel;")
    def connect(self, address):
        self._peer = _target(address)
        self._sock.connect(self._peer)
        return self

    @jmethod("send", "(Ljava/nio/ByteBuffer;Ljava/net/SocketAddress;)I")
    def send(self, buffer, address):
        data = _drain(buffer)
        return self._sock.sendto(data, _target(address))

    @jmethod("receive", "(Ljava/nio/ByteBuffer;)Ljava/net/SocketAddress;")
    def receive(self, buffer):
        try:
            data, peer = self._sock.recvfrom(max(1, buffer.remaining()))
        except (BlockingIOError, InterruptedError):
            return None
        buffer.put(to_java_bytes(data[:buffer.remaining()]))
        return InetSocketAddress(InetAddress._make(None, peer[0]), peer[1])

    @jmethod("read", "(Ljava/nio/ByteBuffer;)I")
    def read(self, buffer):
        try:
            data = self._sock.recv(max(1, buffer.remaining()))
        except (BlockingIOError, InterruptedError):
            return 0
        buffer.put(to_java_bytes(data[:buffer.remaining()]))
        return len(data)

    @jmethod("write", "(Ljava/nio/ByteBuffer;)I")
    def write(self, buffer):
        return self._sock.send(_drain(buffer))

    @jmethod("getLocalAddress", "()Ljava/net/SocketAddress;")
    def getLocalAddress(self):
        host, port = self._sock.getsockname()[:2]
        return InetSocketAddress(InetAddress._make(None, host), port)


@host_class("java.nio.channels.SelectionKey")
class SelectionKey(Object):
    OP_READ = 1
    OP_WRITE = 4
    OP_CONNECT = 8
    OP_ACCEPT = 16

    def __init__(self, channel, selector, ops, attachment):
        self._ch, self._sel, self._ops, self._att, self._ready, self._valid = channel, selector, ops, attachment, 0, True

    @jmethod("channel", "()Ljava/nio/channels/SelectableChannel;")
    def channel(self):
        return self._ch

    @jmethod("selector", "()Ljava/nio/channels/Selector;")
    def selector(self):
        return self._sel

    @jmethod("isValid", "()Z")
    def isValid(self):
        return 1 if self._valid else 0

    @jmethod("interestOps", "()I")
    @jmethod("interestOps", "(I)Ljava/nio/channels/SelectionKey;")
    def interestOps(self, ops=None):
        if not self._valid:
            runtime.throw_new("java.nio.channels.CancelledKeyException", None)
        if ops is None:
            return self._ops
        self._ops = ops
        self._sel._update(self)
        return self

    @jmethod("readyOps", "()I")
    def readyOps(self):
        return self._ready

    @jmethod("attach", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def attach(self, attachment):
        old, self._att = self._att, attachment
        return old

    @jmethod("attachment", "()Ljava/lang/Object;")
    def attachment(self):
        return self._att

    @jmethod("cancel", "()V")
    def cancel(self):
        if self._valid:
            self._valid = False
            self._sel._cancelled.append(self)

    @jmethod("isReadable", "()Z")
    def isReadable(self):
        return 1 if self._ready & 1 else 0

    @jmethod("isWritable", "()Z")
    def isWritable(self):
        return 1 if self._ready & 4 else 0

    @jmethod("isConnectable", "()Z")
    def isConnectable(self):
        return 1 if self._ready & 8 else 0

    @jmethod("isAcceptable", "()Z")
    def isAcceptable(self):
        return 1 if self._ready & 16 else 0


@host_class("java.nio.channels.Selector", interfaces=("java.io.Closeable",))
class Selector(Object):
    def __init__(self):
        self._sel = selectors.DefaultSelector()
        self._keys = {}
        self._selected = []
        self._cancelled = []
        self._open = True
        self._wake = socket.socketpair()
        self._wake[0].setblocking(False)
        self._wake[1].setblocking(False)
        self._sel.register(self._wake[0], selectors.EVENT_READ, None)

    @jstatic("open", "()Ljava/nio/channels/Selector;")
    def open():
        return Selector()

    @staticmethod
    def _events(ops):
        events = 0
        if ops & (1 | 16):
            events |= selectors.EVENT_READ
        if ops & (4 | 8):
            events |= selectors.EVENT_WRITE
        return events

    def _register(self, channel, ops, attachment):
        if not self._open:
            runtime.throw_new("java.nio.channels.ClosedSelectorException", None)
        if not channel._blocking is False:
            runtime.throw_new("java.nio.channels.IllegalBlockingModeException", None)
        if id(channel) in self._keys:
            key = self._keys[id(channel)]
            key._ops, key._att = ops, attachment
            self._update(key)
            return key
        key = SelectionKey(channel, self, ops, attachment)
        self._keys[id(channel)] = key
        channel._registered = True
        channel.__dict__.setdefault("_selectors", []).append(self)
        self._sel.register(channel._sock, self._events(ops) or selectors.EVENT_READ, key)
        return key

    def _update(self, key):
        try:
            self._sel.modify(key._ch._sock, self._events(key._ops) or selectors.EVENT_READ, key)
        except (KeyError, ValueError, OSError):
            pass

    def _forget(self, channel):
        key = self._keys.pop(id(channel), None)
        if key is not None:
            key._valid = False
            try:
                self._sel.unregister(channel._sock)
            except (KeyError, ValueError, OSError):
                pass

    @jmethod("select", "()I")
    @jmethod("select", "(J)I")
    def select(self, timeout=0):
        return self._do_select(None if timeout == 0 else timeout / 1000.0)

    @jmethod("selectNow", "()I")
    def selectNow(self):
        return self._do_select(0)

    def _do_select(self, timeout):
        if not self._open:
            runtime.throw_new("java.nio.channels.ClosedSelectorException", None)
        for key in self._cancelled:
            self._forget(key._ch)
        self._cancelled.clear()
        count = 0
        for registered, mask in self._sel.select(timeout):
            if registered.data is None:
                try:
                    self._wake[0].recv(4096)
                except OSError:
                    pass
                continue
            key = registered.data
            ready = 0
            if mask & selectors.EVENT_READ:
                ready |= key._ops & (1 | 16)
            if mask & selectors.EVENT_WRITE:
                ready |= key._ops & (4 | 8)
            if ready:
                key._ready = ready
                if key not in self._selected:
                    self._selected.append(key)
                    count += 1
        return count

    @jmethod("selectedKeys", "()Ljava/util/Set;")
    def selectedKeys(self):
        from .jmap import LinkedHashSet
        result = _SelectedKeys(self)
        for key in self._selected:
            LinkedHashSet.add(result, key)
        return result

    @jmethod("keys", "()Ljava/util/Set;")
    def keys(self):
        from .jmap import LinkedHashSet
        result = LinkedHashSet()
        for key in self._keys.values():
            result.add(key)
        return result

    @jmethod("wakeup", "()Ljava/nio/channels/Selector;")
    def wakeup(self):
        try:
            self._wake[1].send(b"x")
        except OSError:
            pass
        return self

    @jmethod("isOpen", "()Z")
    def isOpen(self):
        return 1 if self._open else 0

    @jmethod("close", "()V")
    def close(self):
        if self._open:
            self._open = False
            for key in list(self._keys.values()):
                key._valid = False
            self._keys.clear()
            self._sel.close()
            for end in self._wake:
                end.close()


class _SelectedKeys(lookup_host("java.util.LinkedHashSet").py):
    """the set the selector hands out: removing a key from it also removes it from the selector's selected list"""

    def __init__(self, selector):
        lookup_host("java.util.LinkedHashSet").py.__init__(self)
        self._selector = selector

    def remove(self, key):
        found = lookup_host("java.util.LinkedHashSet").py.remove(self, key)
        if key in self._selector._selected:
            self._selector._selected.remove(key)
        return found

    def clear(self):
        lookup_host("java.util.LinkedHashSet").py.clear(self)
        self._selector._selected.clear()

    def iterator(self):
        base = lookup_host("java.util.LinkedHashSet").py.iterator(self)
        selected = self._selector._selected
        inner_remove = base.remove

        def remove():
            current = base._last
            inner_remove()
            if current in selected:
                selected.remove(current)
        base.remove = remove
        return base


@host_class("java.nio.channels.Pipe")
class Pipe(Object):
    class SourceChannel(_SelectableChannel):
        pass

    def __init__(self):
        a, b = socket.socketpair()
        self._source = _PipeEnd(a, True)
        self._sink = _PipeEnd(b, False)

    @jstatic("open", "()Ljava/nio/channels/Pipe;")
    def open():
        return Pipe()

    @jmethod("source", "()Ljava/nio/channels/Pipe$SourceChannel;")
    def source(self):
        return self._source

    @jmethod("sink", "()Ljava/nio/channels/Pipe$SinkChannel;")
    def sink(self):
        return self._sink


class _PipeEnd(_SelectableChannel):
    def __init__(self, sock, source):
        self._sock, self._source = sock, source

    def read(self, buffer):
        data = self._sock.recv(max(1, buffer.remaining()))
        if not data:
            return -1
        buffer.put(to_java_bytes(data))
        return len(data)

    def write(self, buffer):
        data = _drain(buffer)
        self._sock.sendall(data)
        return len(data)


host_class("java.nio.channels.Pipe$SourceChannel", interfaces=("java.nio.channels.ReadableByteChannel",), superclass="java.nio.channels.SelectableChannel")(_PipeEnd)
host_class("java.nio.channels.Pipe$SinkChannel", interfaces=("java.nio.channels.WritableByteChannel",), superclass="java.nio.channels.SelectableChannel")(
    type("SinkChannel", (_PipeEnd,), {}))


@host_class("java.net.DatagramPacket")
class DatagramPacket(Object):
    def __init__(self, data, first, second=None, third=None, fourth=None):
        self._buf = data
        self._off = 0
        self._addr = None
        self._port = -1
        if isinstance(second, InetAddress) or (third is not None and isinstance(third, InetAddress)):
            if isinstance(second, InetAddress):
                self._len, self._addr, self._port = first, second, third
            else:
                self._off, self._len, self._addr, self._port = first, second, third, fourth
        elif isinstance(second, SocketAddress):
            self._len, self._addr, self._port = first, second._address, second._port
        elif second is not None and not isinstance(second, InetAddress):
            self._off, self._len = first, second
            if isinstance(third, SocketAddress):
                self._addr, self._port = third._address, third._port
        else:
            self._len = first

    @jmethod("<init>", "([BI)V")
    @jmethod("<init>", "([BII)V")
    @jmethod("<init>", "([BILjava/net/InetAddress;I)V")
    @jmethod("<init>", "([BIILjava/net/InetAddress;I)V")
    @jmethod("<init>", "([BILjava/net/SocketAddress;)V")
    @jmethod("<init>", "([BIILjava/net/SocketAddress;)V")
    def _init(self, data, first, second=None, third=None, fourth=None):
        DatagramPacket.__init__(self, data, first, second, third, fourth)

    @jmethod("getData", "()[B")
    def getData(self):
        return self._buf

    @jmethod("setData", "([B)V")
    @jmethod("setData", "([BII)V")
    def setData(self, data, offset=0, length=None):
        self._buf, self._off, self._len = data, offset, len(data) - offset if length is None else length

    @jmethod("getLength", "()I")
    def getLength(self):
        return self._len

    @jmethod("setLength", "(I)V")
    def setLength(self, length):
        self._len = length

    @jmethod("getOffset", "()I")
    def getOffset(self):
        return self._off

    @jmethod("getAddress", "()Ljava/net/InetAddress;")
    def getAddress(self):
        return self._addr

    @jmethod("setAddress", "(Ljava/net/InetAddress;)V")
    def setAddress(self, address):
        self._addr = address

    @jmethod("getPort", "()I")
    def getPort(self):
        return self._port

    @jmethod("setPort", "(I)V")
    def setPort(self, port):
        self._port = port

    @jmethod("getSocketAddress", "()Ljava/net/SocketAddress;")
    def getSocketAddress(self):
        return InetSocketAddress(self._addr, self._port)

    @jmethod("setSocketAddress", "(Ljava/net/SocketAddress;)V")
    def setSocketAddress(self, address):
        self._addr, self._port = address._address, address._port


@host_class("java.net.DatagramSocket", interfaces=("java.io.Closeable",))
class DatagramSocket(Object):
    def __init__(self, first=None, second=None):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._timeout = 0
        self._closed = False
        self._connected = None
        if isinstance(first, SocketAddress):
            self.bind(first)
        elif isinstance(first, int):
            self.bind(InetSocketAddress(second, first) if second is not None else InetSocketAddress(first))

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(ILjava/net/InetAddress;)V")
    @jmethod("<init>", "(Ljava/net/SocketAddress;)V")
    def _init(self, first=None, second=None):
        DatagramSocket.__init__(self, first, second)

    @jmethod("bind", "(Ljava/net/SocketAddress;)V")
    def bind(self, address):
        host, port = ("0.0.0.0", 0) if address is None else _target(address)
        try:
            self._sock.bind((host, port))
        except OSError as error:
            runtime.throw_new("java.net.BindException", "bind failed: %s" % error)

    @jmethod("connect", "(Ljava/net/InetAddress;I)V")
    @jmethod("connect", "(Ljava/net/SocketAddress;)V")
    def connect(self, first, port=None):
        peer = (first._addr, port) if isinstance(first, InetAddress) else _target(first)
        self._sock.connect(peer)
        self._connected = peer

    @jmethod("disconnect", "()V")
    def disconnect(self):
        self._connected = None

    @jmethod("send", "(Ljava/net/DatagramPacket;)V")
    def send(self, packet):
        if self._closed:
            runtime.throw_new("java.net.SocketException", "Socket is closed")
        data = bytes(b & 0xFF for b in packet._buf[packet._off:packet._off + packet._len])
        try:
            if self._connected:
                self._sock.send(data)
            else:
                self._sock.sendto(data, (packet._addr._addr, packet._port))
        except OSError as error:
            _io_failure(error)

    @jmethod("receive", "(Ljava/net/DatagramPacket;)V")
    def receive(self, packet):
        if self._closed:
            runtime.throw_new("java.net.SocketException", "Socket closed")
        self._sock.settimeout(self._timeout / 1000.0 if self._timeout else None)
        try:
            data, peer = self._sock.recvfrom(max(1, len(packet._buf) - packet._off))
        except socket.timeout:
            runtime.throw_new("java.net.SocketTimeoutException", "Receive timed out")
        except OSError as error:
            if self._closed:
                runtime.throw_new("java.net.SocketException", "Socket closed")
            _io_failure(error)
        data = data[:packet._len if packet._len else len(data)]
        packet._buf[packet._off:packet._off + len(data)] = [b - 256 if b > 127 else b for b in data]
        packet._len = len(data)
        packet._addr, packet._port = InetAddress._make(None, peer[0]), peer[1]

    @jmethod("setSoTimeout", "(I)V")
    def setSoTimeout(self, millis):
        self._timeout = millis

    @jmethod("getSoTimeout", "()I")
    def getSoTimeout(self):
        return self._timeout

    @jmethod("getLocalPort", "()I")
    def getLocalPort(self):
        return -1 if self._closed else self._sock.getsockname()[1]

    @jmethod("getLocalAddress", "()Ljava/net/InetAddress;")
    def getLocalAddress(self):
        return InetAddress._make(None, self._sock.getsockname()[0])

    @jmethod("setBroadcast", "(Z)V")
    def setBroadcast(self, flag):
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1 if flag else 0)

    @jmethod("setReuseAddress", "(Z)V")
    def setReuseAddress(self, flag):
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1 if flag else 0)

    @jmethod("setReceiveBufferSize", "(I)V")
    def setReceiveBufferSize(self, size):
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, size)

    @jmethod("setSendBufferSize", "(I)V")
    def setSendBufferSize(self, size):
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, size)

    @jmethod("isClosed", "()Z")
    def isClosed(self):
        return 1 if self._closed else 0

    @jmethod("isBound", "()Z")
    def isBound(self):
        return 1 if not self._closed else 0

    @jmethod("isConnected", "()Z")
    def isConnected(self):
        return 1 if self._connected else 0

    @jmethod("close", "()V")
    def close(self):
        if not self._closed:
            self._closed = True
            try:
                self._sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._sock.close()


@host_class("java.net.MulticastSocket", superclass="java.net.DatagramSocket")
class MulticastSocket(DatagramSocket):
    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(Ljava/net/SocketAddress;)V")
    def _init(self, first=None):
        DatagramSocket.__init__(self, first)

    @jmethod("joinGroup", "(Ljava/net/InetAddress;)V")
    def joinGroup(self, group):
        mreq = struct.pack("4s4s", socket.inet_aton(group._addr), socket.inet_aton("0.0.0.0"))
        self._sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    @jmethod("leaveGroup", "(Ljava/net/InetAddress;)V")
    def leaveGroup(self, group):
        mreq = struct.pack("4s4s", socket.inet_aton(group._addr), socket.inet_aton("0.0.0.0"))
        self._sock.setsockopt(socket.IPPROTO_IP, socket.IP_DROP_MEMBERSHIP, mreq)

    @jmethod("setTimeToLive", "(I)V")
    def setTimeToLive(self, ttl):
        self._sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, ttl)


class _Option(_EnumLike):
    pass


@host_class("java.net.StandardSocketOptions", final=True)
class StandardSocketOptions(Object):
    pass


for _name in ("TCP_NODELAY", "SO_KEEPALIVE", "SO_REUSEADDR", "SO_RCVBUF", "SO_SNDBUF", "SO_BROADCAST", "SO_LINGER", "IP_TOS"):
    setattr(StandardSocketOptions, _name, _Option(_name, 0))
host_class("java.net.StandardSocketOptions$Option", interfaces=("java.net.SocketOption",))(_Option)


@host_class("java.net.IDN", final=True)
class IDN(Object):
    ALLOW_UNASSIGNED = 1
    USE_STD3_ASCII_RULES = 2

    @jstatic("toASCII", "(Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("toASCII", "(Ljava/lang/String;I)Ljava/lang/String;")
    def toASCII(text, flags=0):
        try:
            return ".".join(label.encode("idna").decode("ascii") if label else "" for label in pystr(text).split("."))
        except UnicodeError as error:
            runtime.throw_new("java.lang.IllegalArgumentException", str(error))

    @jstatic("toUnicode", "(Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("toUnicode", "(Ljava/lang/String;I)Ljava/lang/String;")
    def toUnicode(text, flags=0):
        try:
            return jstr(".".join(label.encode("ascii").decode("idna") if label else "" for label in text.split(".")))
        except UnicodeError:
            return text


@host_class("java.net.PasswordAuthentication")
class PasswordAuthentication(Object):
    def __init__(self, user, password):
        self._user, self._password = user, list(password)

    @jmethod("<init>", "(Ljava/lang/String;[C)V")
    def _init(self, user, password):
        PasswordAuthentication.__init__(self, user, password)

    @jmethod("getUserName", "()Ljava/lang/String;")
    def getUserName(self):
        return self._user

    @jmethod("getPassword", "()[C")
    def getPassword(self):
        array = runtime.new_array("[C", 0)
        array.extend(self._password)
        return array


@host_class("java.net.Authenticator")
class Authenticator(Object):
    _default = None

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jstatic("setDefault", "(Ljava/net/Authenticator;)V")
    def setDefault(authenticator):
        Authenticator._default = authenticator

    @jstatic("requestPasswordAuthentication", "(Ljava/net/InetAddress;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/net/PasswordAuthentication;")
    def requestPasswordAuthentication(address, port, protocol, prompt, scheme):
        return None

    @jmethod("getPasswordAuthentication", "()Ljava/net/PasswordAuthentication;")
    def getPasswordAuthentication(self):
        return None

    def _ask(self, host, port, protocol, prompt, scheme):
        self._host, self._port, self._protocol, self._prompt, self._scheme = host, port, protocol, prompt, scheme
        return self.getPasswordAuthentication()

    @jmethod("getRequestingHost", "()Ljava/lang/String;")
    def getRequestingHost(self):
        return getattr(self, "_host", None)

    @jmethod("getRequestingPort", "()I")
    def getRequestingPort(self):
        return getattr(self, "_port", -1)

    @jmethod("getRequestingPrompt", "()Ljava/lang/String;")
    def getRequestingPrompt(self):
        return getattr(self, "_prompt", None)

    @jmethod("getRequestingScheme", "()Ljava/lang/String;")
    def getRequestingScheme(self):
        return getattr(self, "_scheme", None)


@host_class("java.net.ProxySelector")
class ProxySelector(Object):
    _default = None

    @jstatic("getDefault", "()Ljava/net/ProxySelector;")
    def getDefault():
        if ProxySelector._default is None:
            ProxySelector._default = ProxySelector()
        return ProxySelector._default

    @jstatic("setDefault", "(Ljava/net/ProxySelector;)V")
    def setDefault(selector):
        ProxySelector._default = selector

    @jmethod("select", "(Ljava/net/URI;)Ljava/util/List;")
    def select(self, uri):
        result = ArrayList()
        result.add(lookup_host("java.net.Proxy").py.NO_PROXY)
        return result

    @jmethod("connectFailed", "(Ljava/net/URI;Ljava/net/SocketAddress;Ljava/io/IOException;)V")
    def connectFailed(self, uri, address, error):
        return None


@host_class("java.net.HttpCookie", interfaces=("java.lang.Cloneable",))
class HttpCookie(Object):
    def __init__(self, name, value):
        if not name or not re.fullmatch(r"[^\s,;=\"]+", name) or name.startswith("$"):
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal cookie name")
        self._name, self._value = name, value
        self._domain = self._path = self._comment = None
        self._max_age = -1
        self._secure = self._http_only = False
        self._version = 1
        self._created = time.time()

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init(self, name, value):
        HttpCookie.__init__(self, name, value)

    @jstatic("parse", "(Ljava/lang/String;)Ljava/util/List;")
    def parse(header):
        result = ArrayList()
        text = header
        for prefix in ("Set-Cookie2:", "Set-Cookie:"):
            if text[:len(prefix)].lower() == prefix.lower():
                text = text[len(prefix):]
        parts = [p.strip() for p in text.split(";")]
        if not parts or "=" not in parts[0]:
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid cookie name-value pair")
        name, _, value = parts[0].partition("=")
        cookie = HttpCookie(name.strip(), value.strip().strip('"'))
        for attribute in parts[1:]:
            key, _, val = attribute.partition("=")
            key = key.lower()
            if key == "domain":
                cookie._domain = val.lower()
            elif key == "path":
                cookie._path = val
            elif key == "max-age":
                try:
                    cookie._max_age = int(val)
                except ValueError:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Illegal cookie max-age attribute")
            elif key == "expires" and cookie._max_age == -1:
                from email.utils import parsedate_to_datetime
                try:
                    cookie._max_age = max(0, int(parsedate_to_datetime(val).timestamp() - time.time()))
                except (TypeError, ValueError):
                    pass
            elif key == "secure":
                cookie._secure = True
            elif key == "httponly":
                cookie._http_only = True
            elif key == "comment":
                cookie._comment = val
        result.add(cookie)
        return result

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("getValue", "()Ljava/lang/String;")
    def getValue(self):
        return self._value

    @jmethod("setValue", "(Ljava/lang/String;)V")
    def setValue(self, value):
        self._value = value

    @jmethod("getDomain", "()Ljava/lang/String;")
    def getDomain(self):
        return self._domain

    @jmethod("setDomain", "(Ljava/lang/String;)V")
    def setDomain(self, domain):
        self._domain = domain.lower() if domain else domain

    @jmethod("getPath", "()Ljava/lang/String;")
    def getPath(self):
        return self._path

    @jmethod("setPath", "(Ljava/lang/String;)V")
    def setPath(self, path):
        self._path = path

    @jmethod("getMaxAge", "()J")
    def getMaxAge(self):
        return self._max_age

    @jmethod("setMaxAge", "(J)V")
    def setMaxAge(self, seconds):
        self._max_age = seconds

    @jmethod("getSecure", "()Z")
    def getSecure(self):
        return 1 if self._secure else 0

    @jmethod("setSecure", "(Z)V")
    def setSecure(self, flag):
        self._secure = bool(flag)

    @jmethod("isHttpOnly", "()Z")
    def isHttpOnly(self):
        return 1 if self._http_only else 0

    @jmethod("setHttpOnly", "(Z)V")
    def setHttpOnly(self, flag):
        self._http_only = bool(flag)

    @jmethod("getComment", "()Ljava/lang/String;")
    def getComment(self):
        return self._comment

    @jmethod("getVersion", "()I")
    def getVersion(self):
        return self._version

    @jmethod("hasExpired", "()Z")
    def hasExpired(self):
        if self._max_age == 0:
            return 1
        return 1 if self._max_age > 0 and time.time() - self._created > self._max_age else 0

    @jstatic("domainMatches", "(Ljava/lang/String;Ljava/lang/String;)Z")
    def domainMatches(domain, host):
        if domain is None or host is None:
            return 0
        d, h = domain.lower(), host.lower()
        if d == h:
            return 1
        return 1 if d.startswith(".") and (h.endswith(d) or h == d[1:]) else 0

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, HttpCookie) and (other._name.lower(), (other._domain or "").lower(), other._path) == (
            self._name.lower(), (self._domain or "").lower(), self._path) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return hash((self._name.lower(), (self._domain or "").lower(), self._path)) & 0x7FFFFFFF

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s=\"%s\"" % (self._name, self._value) if self._version > 0 else "%s=%s" % (self._name, self._value)


@host_class("java.net.CookieStore", interface=True)
class _CookieStoreMarker:
    __slots__ = ()


@host_class("java.net.InMemoryCookieStore", interfaces=("java.net.CookieStore",))
class InMemoryCookieStore(Object):
    def __init__(self):
        self._items = []
        self._lock = threading.RLock()

    def _live(self):
        self._items = [(c, u) for c, u in self._items if not c.hasExpired()]

    @jmethod("add", "(Ljava/net/URI;Ljava/net/HttpCookie;)V")
    def add(self, uri, cookie):
        with self._lock:
            self._items = [(c, u) for c, u in self._items if not c.equals(cookie)]
            if not (cookie._max_age == 0):
                self._items.append((cookie, uri))

    @jmethod("get", "(Ljava/net/URI;)Ljava/util/List;")
    def get(self, uri):
        result = ArrayList()
        host = uri.getHost() or ""
        path = uri.getPath() or "/"
        with self._lock:
            self._live()
            for cookie, owner in self._items:
                domain = cookie._domain or (owner.getHost() if owner is not None else None)
                matches = HttpCookie.domainMatches(domain, host) if cookie._domain else (domain or "").lower() == host.lower()
                if not matches:
                    continue
                if cookie._path and not path.startswith(cookie._path):
                    continue
                if cookie._secure and uri.getScheme() != "https":
                    continue
                result.add(cookie)
        return result

    @jmethod("getCookies", "()Ljava/util/List;")
    def getCookies(self):
        result = ArrayList()
        with self._lock:
            self._live()
            for cookie, _ in self._items:
                result.add(cookie)
        return result

    @jmethod("getURIs", "()Ljava/util/List;")
    def getURIs(self):
        result = ArrayList()
        for _, uri in self._items:
            if uri is not None:
                result.add(uri)
        return result

    @jmethod("remove", "(Ljava/net/URI;Ljava/net/HttpCookie;)Z")
    def remove(self, uri, cookie):
        with self._lock:
            before = len(self._items)
            self._items = [(c, u) for c, u in self._items if not c.equals(cookie)]
            return 1 if len(self._items) != before else 0

    @jmethod("removeAll", "()Z")
    def removeAll(self):
        with self._lock:
            had = bool(self._items)
            self._items = []
            return 1 if had else 0


@host_class("java.net.CookieHandler")
class CookieHandler(Object):
    _default = None

    @jstatic("getDefault", "()Ljava/net/CookieHandler;")
    def getDefault():
        return CookieHandler._default

    @jstatic("setDefault", "(Ljava/net/CookieHandler;)V")
    def setDefault(handler):
        CookieHandler._default = handler

    @jmethod("<init>", "()V")
    def _init(self):
        return None


@host_class("java.net.CookieManager", superclass="java.net.CookieHandler")
class CookieManager(CookieHandler):
    def __init__(self, store=None, policy=None):
        self._store = store or InMemoryCookieStore()
        self._policy = policy or CookiePolicy.ACCEPT_ORIGINAL_SERVER

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/net/CookieStore;Ljava/net/CookiePolicy;)V")
    def _init(self, store=None, policy=None):
        CookieManager.__init__(self, store, policy)

    @jmethod("setCookiePolicy", "(Ljava/net/CookiePolicy;)V")
    def setCookiePolicy(self, policy):
        self._policy = policy

    @jmethod("getCookieStore", "()Ljava/net/CookieStore;")
    def getCookieStore(self):
        return self._store

    @jmethod("get", "(Ljava/net/URI;Ljava/util/Map;)Ljava/util/Map;")
    def get(self, uri, headers):
        result = HashMap()
        cookies = list(iterate(self._store.get(uri)))
        if cookies:
            values = ArrayList()
            values.add("; ".join("%s=%s" % (c._name, c._value) for c in cookies))
            result.put("Cookie", values)
        return result

    @jmethod("put", "(Ljava/net/URI;Ljava/util/Map;)V")
    def put(self, uri, headers):
        if self._policy is CookiePolicy.ACCEPT_NONE:
            return
        for key in iterate(headers.keySet()):
            if key is None or key.lower() not in ("set-cookie", "set-cookie2"):
                continue
            for header in iterate(headers.get(key)):
                try:
                    for cookie in iterate(HttpCookie.parse(header)):
                        if cookie._domain is None:
                            cookie._domain = None
                        if self._policy is CookiePolicy.ACCEPT_ORIGINAL_SERVER and cookie._domain and \
                                not HttpCookie.domainMatches(cookie._domain, uri.getHost() or ""):
                            continue
                        if cookie._path is None:
                            path = uri.getPath() or "/"
                            cookie._path = path[:path.rfind("/") + 1] or "/"
                        self._store.add(uri, cookie)
                except lookup_host("java.lang.IllegalArgumentException").py:
                    continue


# a connection asks the default cookie handler for the Cookie header and gives it the Set-Cookie headers of the answer
def _cookie_headers(url):
    handler = CookieHandler._default
    if handler is None:
        return []
    result = handler.get(lookup_host("java.net.URI").py(url.toString().split("#")[0]), HashMap())
    return [(k, v) for k in iterate(result.keySet()) for v in iterate(result.get(k))]


def _store_cookies(url, headers):
    handler = CookieHandler._default
    if handler is None:
        return
    table = HashMap()
    for key, value in headers:
        if key.lower() in ("set-cookie", "set-cookie2"):
            values = table.get(key)
            if values is None:
                values = ArrayList()
                table.put(key, values)
            values.add(value)
    if table.size():
        handler.put(lookup_host("java.net.URI").py(url.toString().split("#")[0]), table)


@host_class("java.net.NetworkInterface")
class NetworkInterface(Object):
    def __init__(self, name, index):
        self._name, self._index = name, index

    @jstatic("getNetworkInterfaces", "()Ljava/util/Enumeration;")
    def getNetworkInterfaces():
        try:
            return PyIterator([NetworkInterface(n, i) for i, n in socket.if_nameindex()])
        except (OSError, AttributeError):
            return PyIterator([])

    @jstatic("getByName", "(Ljava/lang/String;)Ljava/net/NetworkInterface;")
    def getByName(name):
        for i, n in socket.if_nameindex():
            if n == name:
                return NetworkInterface(n, i)
        return None

    @jstatic("getByIndex", "(I)Ljava/net/NetworkInterface;")
    def getByIndex(index):
        for i, n in socket.if_nameindex():
            if i == index:
                return NetworkInterface(n, i)
        return None

    @jmethod("getName", "()Ljava/lang/String;")
    @jmethod("getDisplayName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("getIndex", "()I")
    def getIndex(self):
        return self._index

    @jmethod("isLoopback", "()Z")
    def isLoopback(self):
        return 1 if self._name.startswith("lo") else 0

    @jmethod("isUp", "()Z")
    def isUp(self):
        return 1

    @jmethod("getInetAddresses", "()Ljava/util/Enumeration;")
    def getInetAddresses(self):
        return PyIterator([InetAddress._make(None, "127.0.0.1")] if self._name.startswith("lo") else [])

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "name:%s (%s)" % (self._name, self._name)


def _abstract(name, parents=()):
    if not _taken(name):
        host_class(name, interfaces=parents)(type(name.rsplit(".", 1)[1], (Object,), {"__module__": __name__}))


for _n in ("java.net.URLStreamHandler", "java.net.ContentHandler", "java.net.ResponseCache", "java.net.CacheRequest", "java.net.CacheResponse",
           "java.net.SecureCacheResponse", "java.net.NetPermission", "java.net.SocketPermission", "java.net.InterfaceAddress",
           "java.net.JarURLConnection"):
    _abstract(_n)
