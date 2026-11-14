"""java class loaders over the loaders of the vm: ClassLoader, BaseDexClassLoader, PathClassLoader, DexClassLoader,
DelegateLastClassLoader, InMemoryDexClassLoader and DexFile

a loader that is a dex class of its own (a program that extends ClassLoader and overrides findClass or loadClass) is
used as a parent through an adapter that asks it by name. defineClass would need java class file bytecode, which the
vm does not run, so it refuses. a dex file that cannot be read does not fail the construction, as on a device: the
error is kept and the class lookup that follows reports it, with the reasons attached"""

import os

from . import api, classes, runtime
from .api import host_class, jmethod, jstatic, caller_sensitive
from .classes import BOOT, VMLoader
from .container import load_container, MAX_TOTAL_SIZE
from .format import DexFormatError
from .jio import File
from .jnio import ByteBuffer
from .jlang import Object, pystr, jstr
from .jutil import iterate


class _AdapterLoader(VMLoader):
    """the vm view of a java ClassLoader object implemented by a program"""

    def __init__(self, java_loader):
        VMLoader.__init__(self, name="adapter", parent=None)
        self._java = java_loader
        self.classes = {}

    def java_object(self):
        return self._java

    def _load(self, descriptor):
        if descriptor[0] == "[" or len(descriptor) == 1:
            return VMLoader._load(self, descriptor)
        name = api.binary_name(descriptor)
        try:
            return self._java.loadClass(name)
        except api.lookup_host("java.lang.ClassNotFoundException").py:
            return None


@host_class("java.lang.ClassLoader")
class ClassLoader(Object):
    _vm = None
    _parent = None

    def __init__(self, parent=None):
        self._parent = parent

    @jmethod("<init>", "()V")
    def _init(self):
        self._parent = ClassLoader.getSystemClassLoader()

    @jmethod("<init>", "(Ljava/lang/ClassLoader;)V")
    def _init_parent(self, parent):
        self._parent = parent

    def _vm_loader(self):
        if self._vm is None:
            self._vm = _AdapterLoader(self)
        return self._vm

    @jmethod("loadClass", "(Ljava/lang/String;)Ljava/lang/Class;")
    @jmethod("loadClass", "(Ljava/lang/String;Z)Ljava/lang/Class;")
    def loadClass(self, name, resolve=False):
        found = self.findLoadedClass(name)
        if found is not None:
            return found
        try:
            if self._parent is not None:
                return self._parent.loadClass(name)
            host = api.lookup_host(name)
            if host is not None:
                return host
            raise runtime.make_throwable(api.lookup_host("java.lang.ClassNotFoundException").py, name)
        except api.lookup_host("java.lang.ClassNotFoundException").py:
            pass
        return self.findClass(name)

    @jmethod("findClass", "(Ljava/lang/String;)Ljava/lang/Class;")
    def findClass(self, name):
        runtime.throw_new("java.lang.ClassNotFoundException", name)

    @jmethod("findLoadedClass", "(Ljava/lang/String;)Ljava/lang/Class;")
    def findLoadedClass(self, name):
        return None

    @jmethod("defineClass", "(Ljava/lang/String;[BII)Ljava/lang/Class;")
    def defineClass(self, name, data, offset, length):
        runtime.throw_new("java.lang.UnsupportedClassVersionError",
                          "java class file bytecode is not run by this vm, only dex")

    @jmethod("getParent", "()Ljava/lang/ClassLoader;")
    def getParent(self):
        return self._parent

    @jmethod("getResource", "(Ljava/lang/String;)Ljava/net/URL;")
    def getResource(self, name):
        return None

    @jmethod("getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;")
    def getResourceAsStream(self, name):
        return None

    @jstatic("getSystemClassLoader", "()Ljava/lang/ClassLoader;")
    def getSystemClassLoader():
        return SYSTEM


def _vm_of(java_loader):
    """the VMLoader behind a java ClassLoader object; None is the boot loader"""
    if java_loader is None:
        return BOOT
    vm = getattr(java_loader, "_vm", None)
    if vm is not None:
        return vm
    return java_loader._vm_loader()


@host_class("java.lang.BootClassLoader")
class BootClassLoader(ClassLoader):
    pass


@host_class("dalvik.system.BaseDexClassLoader")
class BaseDexClassLoader(ClassLoader):
    """loads classes from the dex files of a path or of buffers. lookups delegate to the parent first, as ClassLoader does"""

    _delegate_last = False

    def __init__(self, dex_path=None, optimized=None, library_path=None, parent=None, buffers=None):
        self._parent = parent
        self._dex_path = dex_path
        self._library_path = library_path
        self._errors = []
        files = []
        for entry in (str(dex_path).split(os.pathsep) if dex_path else []):
            self._add_path(entry, files)
        for buffer in buffers or ():
            self._add_bytes(buffer.to_bytes(), "<buffer>", files)
        self._vm = VMLoader(files, parent=_vm_of(parent) if parent is not None else None,
                            delegate_last=self._delegate_last, name="dex loader")
        self._vm._java_object = self

    def _add_path(self, entry, files):
        if not entry:
            return
        from . import policy
        try:
            policy.check_path(pystr(entry), "read")
            with open(pystr(entry), "rb") as handle:
                data = handle.read(MAX_TOTAL_SIZE + 1)
            if len(data) > MAX_TOTAL_SIZE:
                self._errors.append(self._exception("java.io.IOException", "%s: file is too large" % entry))
                return
        except OSError as error:
            self._errors.append(self._exception("java.io.IOException", "%s: %s" % (entry, error.strerror or error)))
            return
        self._add_bytes(data, entry, files)

    def _add_bytes(self, data, name, files):
        try:
            files.extend(load_container(data, name))
        except DexFormatError as error:
            self._errors.append(self._exception("java.io.IOException", "%s: %s" % (name, error)))

    @staticmethod
    def _exception(name, message):
        return runtime.make_throwable(api.lookup_host(name).py, jstr(message))

    @jmethod("<init>", "(Ljava/lang/String;Ljava/io/File;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init4(self, dex_path, optimized, library_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, optimized, library_path, parent)

    @jmethod("<init>", "([Ljava/nio/ByteBuffer;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init_buffers(self, buffers, library_path, parent):
        BaseDexClassLoader.__init__(self, None, None, library_path, parent, list(buffers))

    @jmethod("loadClass", "(Ljava/lang/String;)Ljava/lang/Class;")
    @jmethod("loadClass", "(Ljava/lang/String;Z)Ljava/lang/Class;")
    def loadClass(self, name, resolve=False):
        found = self._vm.load_class(pystr(name))
        if found is None:
            raise self._not_found(name)
        return found

    def findClass(self, name):
        found = self._vm.load_class(pystr(name)) if self._vm.has_own("L" + pystr(name).replace(".", "/") + ";") else None
        if found is None:
            raise self._not_found(name)
        return found

    def _not_found(self, name):
        error = runtime.make_throwable(api.lookup_host("java.lang.ClassNotFoundException").py,
                                       "Didn't find class \"%s\" on path: DexPathList[[%s],nativeLibraryDirectories=[%s]]" % (
                                           name, self._dex_path or "", self._library_path or ""))
        error._suppressed = list(self._errors) or None
        return error

    @jmethod("findLibrary", "(Ljava/lang/String;)Ljava/lang/String;")
    def findLibrary(self, name):
        for directory in (self._library_path or "").split(os.pathsep):
            candidate = os.path.join(directory, "lib%s.so" % name)
            if directory and os.path.isfile(candidate):
                return jstr(candidate)
        return None

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s[DexPathList[[%s],nativeLibraryDirectories=[%s]]]" % (
            runtime.class_of(self).getName(), self._dex_path or "", self._library_path or "")

    def dex_errors(self):
        """python side: the problems met while reading the dex files, as java exceptions"""
        return list(self._errors)

    def vm_loader(self):
        return self._vm


@host_class("dalvik.system.PathClassLoader")
class PathClassLoader(BaseDexClassLoader):
    def __init__(self, dex_path=None, *rest):
        # (dexPath, parent) or (dexPath, librarySearchPath, parent)
        library_path, parent = (None, rest[0]) if len(rest) == 1 else (rest[0], rest[1]) if rest else (None, None)
        BaseDexClassLoader.__init__(self, dex_path, None, library_path, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init2(self, dex_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, None, None, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init3(self, dex_path, library_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, None, library_path, parent)


@host_class("dalvik.system.DexClassLoader")
class DexClassLoader(BaseDexClassLoader):
    def __init__(self, dex_path=None, optimized_directory=None, library_path=None, parent=None):
        BaseDexClassLoader.__init__(self, dex_path, optimized_directory, library_path, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init4(self, dex_path, optimized_directory, library_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, optimized_directory, library_path, parent)


@host_class("dalvik.system.DelegateLastClassLoader")
class DelegateLastClassLoader(BaseDexClassLoader):
    _delegate_last = True

    def __init__(self, dex_path=None, *rest):
        library_path, parent = (None, rest[0]) if len(rest) == 1 else (rest[0], rest[1]) if rest else (None, None)
        BaseDexClassLoader.__init__(self, dex_path, None, library_path, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init2(self, dex_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, None, None, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init3(self, dex_path, library_path, parent):
        BaseDexClassLoader.__init__(self, dex_path, None, library_path, parent)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V")
    def _init4(self, dex_path, library_path, parent, delegate_last):
        BaseDexClassLoader.__init__(self, dex_path, None, library_path, parent)


@host_class("dalvik.system.InMemoryDexClassLoader")
class InMemoryDexClassLoader(BaseDexClassLoader):
    def __init__(self, buffers=(), *rest):
        # (buffer or buffers, parent) or (buffers, librarySearchPath, parent)
        library_path, parent = (None, rest[0]) if len(rest) == 1 else (rest[0], rest[1]) if rest else (None, None)
        if not isinstance(buffers, (list, tuple, runtime.JArray)):
            buffers = [buffers]
        BaseDexClassLoader.__init__(self, None, None, library_path, parent, [check_buffer(b) for b in buffers])

    @jmethod("<init>", "(Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V")
    def _init1(self, buffer, parent):
        BaseDexClassLoader.__init__(self, None, None, None, parent, [check_buffer(buffer)])

    @jmethod("<init>", "([Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V")
    def _init_many(self, buffers, parent):
        BaseDexClassLoader.__init__(self, None, None, None, parent, [check_buffer(b) for b in buffers])

    @jmethod("<init>", "([Ljava/nio/ByteBuffer;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
    def _init_library(self, buffers, library_path, parent):
        BaseDexClassLoader.__init__(self, None, None, library_path, parent, [check_buffer(b) for b in buffers])


def check_buffer(buffer):
    if buffer is None:
        runtime.npe()
    return buffer


@host_class("dalvik.system.DexFile", interfaces=("java.io.Closeable",))
class DexFile(Object):
    """the classes of a dex file or archive: entries(), loadClass(name, loader)"""

    def __init__(self, path):
        name = path._path if isinstance(path, File) else pystr(path)
        from . import policy
        policy.check_path(name, "read")
        try:
            with open(name, "rb") as handle:
                data = handle.read(MAX_TOTAL_SIZE + 1)
            if len(data) > MAX_TOTAL_SIZE:
                runtime.throw_new("java.io.IOException", "%s: file is too large" % name)
        except OSError as error:
            runtime.throw_new("java.io.IOException", "%s: %s" % (name, error.strerror or error))
        try:
            self._files = load_container(data, name)
        except DexFormatError as error:
            runtime.throw_new("java.io.IOException", "%s: %s" % (name, error))
        self._name = name
        self._closed = False

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    def _init(self, path):
        DexFile.__init__(self, path)

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return jstr(self._name)

    @jmethod("entries", "()Ljava/util/Enumeration;")
    def entries(self):
        from .jutil import PyIterator
        names = [api.binary_name(d) for dex in self._files for d in dex.class_descriptors()]
        return PyIterator(names)

    @jmethod("loadClass", "(Ljava/lang/String;Ljava/lang/ClassLoader;)Ljava/lang/Class;")
    def loadClass(self, name, loader):
        descriptor = "L" + pystr(name).replace(".", "/") + ";"
        if not any(descriptor in dex.class_descriptors() for dex in self._files):
            return None
        own = VMLoader(self._files, parent=_vm_of(loader), name="dexfile")
        return own.load_class(pystr(name))

    @jmethod("close", "()V")
    def close(self):
        self._closed = True


class _SystemLoader(PathClassLoader):
    """the loader of the app: no dex files of its own, the host classes below it"""


SYSTEM = _SystemLoader()
