"""java.io.File over os.path, the part of it plugins call"""
import os

from java.lang import Object


class File(Object):
    def __init__(self, parent, child=None):
        if child is None:
            self._path = os.fspath(parent)
        else:
            base = parent.getPath() if isinstance(parent, File) else os.fspath(parent)
            self._path = os.path.join(base, child)

    def getPath(self):
        return self._path

    def getAbsolutePath(self):
        return os.path.abspath(self._path)

    def getName(self):
        return os.path.basename(self._path)

    def getParent(self):
        parent = os.path.dirname(self._path)
        return parent or None

    def exists(self):
        return os.path.exists(self._path)

    def isFile(self):
        return os.path.isfile(self._path)

    def isDirectory(self):
        return os.path.isdir(self._path)

    def length(self):
        return os.path.getsize(self._path) if os.path.isfile(self._path) else 0

    def lastModified(self):
        try:
            return int(os.path.getmtime(self._path) * 1000)
        except OSError:
            return 0

    def mkdirs(self):
        if os.path.isdir(self._path):
            return False
        try:
            os.makedirs(self._path)
        except OSError:
            return False
        return True

    def mkdir(self):
        try:
            os.mkdir(self._path)
        except OSError:
            return False
        return True

    def delete(self):
        try:
            if os.path.isdir(self._path):
                os.rmdir(self._path)
            else:
                os.remove(self._path)
        except OSError:
            return False
        return True

    def listFiles(self):
        """None when the path is not a readable directory, as java"""
        try:
            return [File(self._path, name) for name in sorted(os.listdir(self._path))]
        except OSError:
            return None

    def toString(self):
        return self._path

    __str__ = toString


class ByteArrayOutputStream(Object):
    def __init__(self, size=32):
        self._data = bytearray()

    def write(self, value, offset=0, length=None):
        if isinstance(value, int):
            self._data.append(value & 255)
        else:
            chunk = bytes(b & 255 for b in value)
            self._data += chunk[offset:] if length is None else chunk[offset:offset + length]

    def toByteArray(self):
        return [b - 256 if b > 127 else b for b in self._data]

    def size(self):
        return len(self._data)

    def reset(self):
        self._data.clear()

    def flush(self):
        pass

    def close(self):
        pass

    def toString(self):
        return self._data.decode("utf-8", "replace")


class FileOutputStream(Object):
    """a file a plugin writes a picture into with Bitmap.compress: the app writes it, so only that is possible here, and only inside the folder
    the plugin may write pictures to (the app checks the place). write() is not available"""

    def __init__(self, path):
        from file_utils import _require_files
        self._path = os.fspath(path.getPath() if isinstance(path, File) else path)
        _require_files(self._path, "write a file")
        self._written = False
        self._closed = False

    def write(self, *_args):
        raise NotImplementedError("a FileOutputStream takes a picture from Bitmap.compress only")

    def flush(self):
        if self._closed:
            raise ValueError("the stream is closed")

    def close(self):
        self._closed = True


def __getattr__(name):
    if name.startswith("__"):
        raise AttributeError(name)
    # a class the shim does not write itself but the dex runtime implements
    from java import host_class
    return host_class("java.io", name)
