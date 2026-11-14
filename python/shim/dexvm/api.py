"""java types of the vm and the registry of host classes

a host class is a python class that answers for a java class: java.lang.String, java.util.ArrayList, android.os.Handler.
a method of it is found by java name and descriptor first (@jmethod, the exact overload) and then by name alone, in
which case the vm converts boolean and char values at the call. a class registered lazily is imported on the first
lookup of its name, so listing a class costs nothing until a program uses it.

JType is also java.lang.Class: const-class and getClass() hand out the same object, so a class has one identity"""

import threading

_ESCAPES = {}


def escape(text):
    """a reversible spelling of a java name or descriptor as a python identifier part"""
    found = _ESCAPES.get(text)
    if found is None:
        found = _ESCAPES[text] = "".join(
            char if char.isascii() and char.isalnum() else "_%x_" % ord(char) for char in text)
    return found


_METHOD_NAMES = {}


def method_attr(name, descriptor):
    """the python attribute a dex class carries a virtual method under"""
    attr = "jm_" + escape(name) + "__" + escape(descriptor)
    _METHOD_NAMES[attr] = (name, descriptor)
    return attr


def method_of_attr(attr):
    return _METHOD_NAMES.get(attr)


def field_attr(declaring, name, static=False):
    return ("s_" if static else "f_") + escape(declaring) + "__" + escape(name)


def binary_name(descriptor):
    """java.lang.String for Ljava/lang/String;, [I for [I"""
    if descriptor[0] == "L":
        return descriptor[1:-1].replace("/", ".")
    return descriptor.replace("/", ".")


PRIMITIVE_NAMES = {"Z": "boolean", "B": "byte", "S": "short", "C": "char", "I": "int", "J": "long",
                   "F": "float", "D": "double", "V": "void"}


def jmethod(name, descriptor):
    """mark a python function as the java method name+descriptor of its class. several marks stack for a function that serves more than one overload"""
    def mark(function):
        function.__dict__.setdefault("_jsigs", []).append((name, descriptor))
        return function
    return mark


def jstatic(name, descriptor):
    """the same for a static method; the function is stored as a staticmethod"""
    def mark(function):
        function.__dict__.setdefault("_jsigs", []).append((name, descriptor))
        function.__dict__["_jstatic"] = True
        return function
    return mark


def caller_sensitive(function):
    """the vm passes the DexClass of the calling code as the keyword caller; Class.forName resolves in the loader of its caller"""
    function._jcaller = True
    return function


class JType:
    """a java type: java.lang.Class of it. subclasses are DexClass, HostClass, ArrayType and PrimitiveType"""

    descriptor = None
    pytype = None

    def getName(self):
        if self.descriptor is None:
            return "?"
        return PRIMITIVE_NAMES.get(self.descriptor) if len(self.descriptor) == 1 else binary_name(self.descriptor)

    def getSimpleName(self):
        name = self.getName()
        return name[name.rfind(".") + 1:].rsplit("$", 1)[-1]

    def getTypeName(self):
        return self.getName()

    def getCanonicalName(self):
        return self.getName().replace("$", ".")

    def toString(self):
        prefix = "interface " if self.isInterface() else ("" if self.isPrimitive() else "class ")
        return prefix + self.getName()

    def hashCode(self):
        return id(self) >> 4 & 0x7FFFFFFF

    def equals(self, other):
        return self is other

    def isInterface(self):
        return False

    def isArray(self):
        return False

    def isPrimitive(self):
        return False

    def isEnum(self):
        return False

    def isAnnotation(self):
        return False

    def getEnumConstants(self):
        return None

    def getComponentType(self):
        return None

    def getSuperclass(self):
        return None

    def getInterfaces(self):
        from .runtime import new_array
        return new_array("[Ljava/lang/Class;", 0)

    def getModifiers(self):
        return 1

    def isInstance(self, value):
        raise NotImplementedError

    def isAssignableFrom(self, other):
        raise NotImplementedError

    def getClassLoader(self):
        return None

    def desiredAssertionStatus(self):
        return 0

    def getPackageName(self):
        name = self.getName()
        return name[:name.rfind(".")] if "." in name else ""

    def getDeclaredMethods(self):
        from . import jreflect
        return jreflect.declared_methods(self)

    def getMethods(self):
        from . import jreflect
        return jreflect.public_methods(self)

    def getDeclaredMethod(self, name, *types):
        from . import jreflect
        return jreflect.find_method(self, name, types, declared=True)

    def getMethod(self, name, *types):
        from . import jreflect
        return jreflect.find_method(self, name, types, declared=False)

    def getDeclaredConstructors(self):
        from . import jreflect
        return jreflect.declared_constructors(self)

    def getConstructors(self):
        from . import jreflect
        return jreflect.declared_constructors(self, public_only=True)

    def getDeclaredConstructor(self, *types):
        from . import jreflect
        return jreflect.find_constructor(self, types, declared=True)

    def getConstructor(self, *types):
        from . import jreflect
        return jreflect.find_constructor(self, types, declared=False)

    def getDeclaredFields(self):
        from . import jreflect
        return jreflect.declared_fields(self)

    def getFields(self):
        from . import jreflect
        return jreflect.public_fields(self)

    def getDeclaredField(self, name):
        from . import jreflect
        return jreflect.find_field(self, name, declared=True)

    def getField(self, name):
        from . import jreflect
        return jreflect.find_field(self, name, declared=False)

    def newInstance(self):
        return self.getDeclaredConstructor().newInstance()

    def cast(self, value):
        from . import runtime
        return runtime.check_cast(value, self)

    def getAnnotation(self, annotation_class):
        from . import jreflect
        return jreflect.annotation_of(self, annotation_class)

    def getAnnotations(self):
        from . import jreflect
        return jreflect.annotations_of(self)

    getDeclaredAnnotations = getAnnotations

    def isAnnotationPresent(self, annotation_class):
        return 1 if self.getAnnotation(annotation_class) is not None else 0

    def getEnclosingClass(self):
        name = self.getName()
        if "$" not in name:
            return None
        loader = getattr(self, "loader", None)
        outer = name.rsplit("$", 1)[0]
        descriptor = "L" + outer.replace(".", "/") + ";"
        if loader is not None:
            return loader.load_or_none(descriptor)
        return lookup_host(outer)

    def getDeclaringClass(self):
        return self.getEnclosingClass()

    def isAnonymousClass(self):
        simple = self.getName().rsplit("$", 1)[-1]
        return "$" in self.getName() and simple.isdigit()

    def isMemberClass(self):
        return "$" in self.getName() and not self.isAnonymousClass()

    def isSynthetic(self):
        return 1 if self.getModifiers() & 0x1000 else 0

    def getGenericSuperclass(self):
        return self.getSuperclass()

    def getGenericInterfaces(self):
        return self.getInterfaces()


class PrimitiveType(JType):
    def __init__(self, descriptor):
        self.descriptor = descriptor

    def isPrimitive(self):
        return True

    def isInstance(self, value):
        return 0

    def isAssignableFrom(self, other):
        return 1 if other is self else 0

    def getModifiers(self):
        return 0x411


PRIMITIVES = {code: PrimitiveType(code) for code in PRIMITIVE_NAMES}


class ArrayType(JType):
    def __init__(self, descriptor, component):
        self.descriptor = descriptor
        self.component = component
        self.pytype = None

    def isArray(self):
        return True

    def getComponentType(self):
        return self.component

    def getSuperclass(self):
        return lookup_host("java.lang.Object")

    def getModifiers(self):
        return 0x411

    def isInstance(self, value):
        return 1 if value is not None and self.accepts(value) else 0

    def accepts(self, value):
        from .runtime import JArray
        if not isinstance(value, JArray):
            return False
        return self.isAssignableFrom(value.jtype)

    def isAssignableFrom(self, other):
        if other is self:
            return 1
        if not isinstance(other, ArrayType):
            return 0
        mine = self.component
        theirs = other.component
        if mine.isPrimitive() or theirs.isPrimitive():
            return 1 if mine is theirs else 0
        return mine.isAssignableFrom(theirs)


class HostClass(JType):
    """a java class implemented in python. py is the python class, value_type marks classes whose instances are plain python values (String is str) and whose methods then take that value as self"""

    def __init__(self, name, py, interface=False, final=False, abstract=False, value_type=False, superclass=None,
                 interfaces=()):
        self.name = name
        self.descriptor = "L" + name.replace(".", "/") + ";"
        self.py = py
        self.pytype = py
        self.interface = interface
        self.final = final
        self.abstract = abstract
        self.value_type = value_type
        self._superclass_name = superclass
        self._interface_names = tuple(interfaces)
        self._typed = None
        self.module = None
        self._lock = threading.Lock()

    def getName(self):
        return self.name

    def isInterface(self):
        return self.interface

    def getSuperclass(self):
        if self.interface or self.name == "java.lang.Object":
            return None
        if self._superclass_name:
            return lookup_host(self._superclass_name)
        for base in self.py.__mro__[1:]:
            found = _by_pytype.get(base)
            if found is not None:
                return found
        return lookup_host("java.lang.Object")

    def getInterfaces(self):
        from .runtime import new_array, JArray
        found = [lookup_host(name) for name in self._interface_names]
        array = new_array("[Ljava/lang/Class;", len(found))
        array[:] = found
        return array

    def getModifiers(self):
        flags = 1
        if self.interface:
            flags |= 0x600
        if self.final:
            flags |= 0x10
        if self.abstract:
            flags |= 0x400
        return flags

    def instance_ok(self, value):
        return self.py is not None and isinstance(value, self.py)

    def isInstance(self, value):
        return 1 if value is not None and self.instance_ok(value) else 0

    def isAssignableFrom(self, other):
        if other is self:
            return 1
        if isinstance(other, ArrayType):
            return 1 if self.name in ("java.lang.Object", "java.lang.Cloneable", "java.io.Serializable") else 0
        if isinstance(other, HostClass):
            return 1 if other.py is not None and issubclass(other.py, self.py) else 0
        if isinstance(other, JType) and other.pytype is not None and self.py is not None:
            if self.interface:
                return 1 if self.descriptor in getattr(other, "supers", ()) else 0
            return 1 if issubclass(other.pytype, self.py) else 0
        return 0

    def typed(self):
        """{(name, descriptor): (function, is_static)} of the class and its python bases. a method that a more derived class defines under the same name without a mark replaces the marked methods of that name from less derived classes, so an override written as plain python is the one called"""
        if self._typed is None:
            with self._lock:
                if self._typed is None:
                    table = {}
                    depth_of = {}
                    by_name = {}
                    for depth, base in enumerate(reversed(self.py.__mro__)):
                        for key, value in vars(base).items():
                            function = value.__func__ if isinstance(value, (staticmethod, classmethod)) else value
                            sigs = getattr(function, "_jsigs", None)
                            if sigs:
                                for sig in sigs:
                                    table[sig] = (value, bool(function.__dict__.get("_jstatic")))
                                    depth_of[sig] = depth
                                    by_name.setdefault(sig[0], set()).add(sig)
                            elif key in by_name and callable(function):
                                for sig in by_name[key]:
                                    if depth_of[sig] < depth and not table[sig][1]:
                                        table[sig] = (value, False)
                                        depth_of[sig] = depth
                    self._typed = table
        return self._typed


_by_pytype = {}
_classes = {}
_lazy = {}
_lock = threading.Lock()


def host_class(name, **options):
    """decorator: register a python class as the java class name"""
    def register(py):
        entry = HostClass(name, py, **options)
        entry.module = py.__module__
        with _lock:
            if name in _classes:
                raise ValueError("class registered twice: " + name)
            _classes[name] = entry
        _by_pytype.setdefault(py, entry)
        py._jhost = entry
        return py
    return register


def register_value_type(name, py, impl, **options):
    """a java class whose values are plain python objects of type py; impl is the python class holding the methods"""
    entry = HostClass(name, impl, value_type=True, **options)
    entry.module = impl.__module__
    entry.pytype = py
    with _lock:
        if name in _classes:
            raise ValueError("class registered twice: " + name)
        _classes[name] = entry
    _by_pytype[py] = entry
    impl._jhost = entry
    return entry


def host_lazy(name, module, attribute=None):
    """a class the vm imports from module on first use. the module registers the class under name itself"""
    with _lock:
        if name in _classes or name in _lazy:
            raise ValueError("class registered twice: " + name)
        _lazy[name] = module


# python modules of the app that answer for classes of these packages; java.* is never bridged, the vm implements it
BRIDGE_PREFIXES = ["android.", "androidx.", "org.telegram.", "de.robv.", "app.exteraless.", "com.exteragram."]
_missing = set()


def _with_constants(found):
    """the first time a class is named, the constants of the jdk that its module left out are put on it"""
    if found is not None and not found.__dict__.get("_constants_set"):
        found._constants_set = True
        from . import jconst
        jconst.apply(found)
    return found


def lookup_host(name):
    """the HostClass for a binary java name or None. a lazily listed class is imported here; a name in a bridged
    package is taken from the python module of the same name when the app has one"""
    found = _classes.get(name)
    if found is not None:
        return _with_constants(found)
    module = _lazy.get(name)
    if module is not None:
        import importlib
        importlib.import_module(module)
        found = _classes.get(name)
        if found is None:
            raise RuntimeError("module %s did not register %s" % (module, name))
        return _with_constants(found)
    if name.startswith(tuple(BRIDGE_PREFIXES)) and name not in _missing:
        found = _bridge(name)
        if found is None:
            _missing.add(name)
        return found
    return None


def _bridged_interface(target):
    """a python class of the app stands for a java interface when it says so (_jinterface) or is a bare marker: no base
    but object and no method, like View.OnClickListener. a dex class may list only an interface in implements, so a
    listener written as an empty python class would otherwise fail to link with IncompatibleClassChangeError"""
    marked = target.__dict__.get("_jinterface")
    if marked is not None:
        return bool(marked)
    if target.__bases__ != (object,):
        return False
    return not any(callable(value) or isinstance(value, (staticmethod, classmethod, property))
                   for key, value in vars(target).items() if not (key.startswith("__") and key.endswith("__")))


def _from_shim_names(name):
    """a class the shims register under a java name that is not the path of a python module: the registry of python/shim/java,
    and for the names of exteraGram the substitutions of the exteraless sdk (com.exteragram.messenger.plugins.PluginsController
    is app.exteraless.plugins.controller.PluginsController here)"""
    import importlib
    try:
        from java import _registry
    except ImportError:
        return None
    found = _registry.lookup(name)
    if found is not None:
        return found
    try:
        from extera_utils import class_aliases
    except ImportError:
        return None
    ours = class_aliases.resolve(name)
    if ours != name:
        found = _registry.lookup(ours)
        if found is not None:
            return found
        package, _, simple = ours.rpartition(".")
        try:
            return getattr(importlib.import_module(package), simple)
        except (ImportError, AttributeError):
            pass
    return class_aliases.substitute(name)


def _bridge(name):
    """a python class of the app (python/shim/android/os.py: Handler) as the host class android.os.Handler. its methods are found by name, with the conversions of a by-name host method"""
    import importlib
    outer, *inner = name.split("$")
    package, _, simple = outer.rpartition(".")
    try:
        target = getattr(importlib.import_module(package), simple)
        for part in inner:
            target = getattr(target, part)
    except (ImportError, AttributeError):
        target = _from_shim_names(name)
    if not isinstance(target, type):
        # the import hook of the sdk may answer with a wrapper that is not the class: the registry has the class itself
        target = _from_shim_names(name)
    if not isinstance(target, type):
        return None
    entry = HostClass(name, target, interface=_bridged_interface(target))
    with _lock:
        existing = _classes.get(name)
        if existing is not None:
            return existing
        _classes[name] = entry
    _by_pytype.setdefault(target, entry)
    return entry


def host_for_pytype(py):
    """the HostClass of the nearest registered python class in the mro of py"""
    found = _by_pytype.get(py)
    if found is not None:
        return found
    for base in py.__mro__:
        found = _by_pytype.get(base)
        if found is not None:
            return found
    return None


def host_names():
    return sorted(set(_classes) | set(_lazy))
