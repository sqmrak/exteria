"""classes defined by dex files, the loader that holds them, and the linking of translated code to them

a DexClass is the JType of a class a dex file defines and carries the python class its instances have. virtual
methods are attributes of that python class under the name method_attr(name, descriptor); instance fields are
attributes with class-level defaults, so a new object needs no field initialisation; static fields are attributes of
the python class. host classes (java.lang.String, android.os.Handler ...) come from the registry in api.

a method is translated and compiled on its first call. the references of its code are bound on the first execution of
the instruction that names them (see bind), in the globals dictionary of the class"""

import functools
import sys
import threading
import types

from . import api, cache as method_cache, jlang, limits, native as native_path, runtime, translate
from .api import ArrayType, HostClass, JType, PRIMITIVES, escape, field_attr, method_attr
from .format import (ACC_ABSTRACT, ACC_ANNOTATION, ACC_CONSTRUCTOR, ACC_ENUM, ACC_FINAL, ACC_INTERFACE,
                     ACC_NATIVE, ACC_PRIVATE, ACC_STATIC, ACC_SYNCHRONIZED, DexFile, DexFormatError, NO_INDEX,
                     VALUE_BOOLEAN, VALUE_BYTE, VALUE_CHAR, VALUE_DOUBLE, VALUE_FLOAT, VALUE_INT, VALUE_LONG,
                     VALUE_NULL, VALUE_SHORT, VALUE_STRING)
from .runtime import throw_new

UNINITIALIZED, INITIALIZING, INITIALIZED, ERRONEOUS = 0, 1, 2, 3

_EMPTY = frozenset()


class Uninitialized:
    """new-instance of a java class whose values are immutable python objects: the object is built by the constructor call that follows"""
    __slots__ = ("host",)

    def __init__(self, host):
        self.host = host


def to_register(value, descriptor):
    """a python value as the representation the translated code keeps for a java type"""
    code = descriptor[0]
    if code == "Z":
        return 1 if value else 0
    if code == "C":
        return ord(value) if isinstance(value, str) else value
    if code in "BSIJ":
        if isinstance(value, float):
            raise TypeError("float given for %s" % descriptor)
        value = int(value)
        if code == "I":
            return runtime.wrap32(value)
        if code == "J":
            return runtime.wrap64(value)
        if code == "S":
            return (value + 32768 & 0xFFFF) - 32768
        return (value + 128 & 0xFF) - 128
    if code == "F":
        return runtime.f32(float(value))
    if code == "D":
        return float(value)
    return value


def from_register(value, descriptor):
    """a register value as the natural python value: bool for boolean, a one character str for char"""
    code = descriptor[0]
    if code == "Z":
        return bool(value)
    if code == "C":
        return chr(value)
    return value


def _needs_conversion(descriptors):
    return any(d[0] in "ZCFD" or d[0] in "BS" for d in descriptors)


def argument_converter(params):
    """a function turning a tuple of host-style arguments into register values, or None when none is needed"""
    if not any(d[0] in "ZCBSIJFD" for d in params):
        return None
    pairs = tuple(params)

    def convert(args):
        if len(args) != len(pairs):
            raise TypeError("expected %d arguments, got %d" % (len(pairs), len(args)))
        return tuple(to_register(a, d) for a, d in zip(args, pairs))
    return convert


def dynamic_adapter(function, params, return_type):
    """call a by-name host function with the natural values for boolean and char arguments and bring the result back to registers"""
    flags = tuple(d[0] if d[0] in "ZC" else None for d in params)
    ret = return_type[0]
    if not any(flags) and ret not in "ZCFBSIJ":
        return function
    first_arg = 0

    def call(*args):
        if any(flags):
            args = tuple(bool(a) if f == "Z" else (chr(a) if f == "C" else a) for a, f in zip(args, flags + (None,) * len(args)))
        result = function(*args)
        if ret == "V":
            return None
        return to_register(result, return_type) if ret in "ZCFBSIJD" else result
    return call


def dynamic_receiver_adapter(function, params, return_type):
    """the same for a function whose first argument is the receiver"""
    flags = tuple(d[0] if d[0] in "ZC" else None for d in params)
    ret = return_type[0]
    if not any(flags) and ret not in "ZCFBSIJ":
        return function

    def call(receiver, *args):
        if any(flags):
            args = tuple(bool(a) if f == "Z" else (chr(a) if f == "C" else a) for a, f in zip(args, flags))
        result = function(receiver, *args)
        if ret == "V":
            return None
        return to_register(result, return_type) if ret in "ZCFBSIJD" else result
    return call


def parse_descriptor(descriptor):
    """(parameter descriptors, return descriptor) of a method descriptor"""
    params = []
    pos = 1
    while descriptor[pos] != ")":
        start = pos
        while descriptor[pos] == "[":
            pos += 1
        if descriptor[pos] == "L":
            pos = descriptor.index(";", pos)
        pos += 1
        params.append(descriptor[start:pos])
    return tuple(params), descriptor[pos + 1:]


def _unwrap(value):
    return value.__func__ if isinstance(value, (staticmethod, classmethod)) else value


def host_static(host, name, descriptor):
    """the python callable of a static method of a host class, taking register values"""
    entry = host.typed().get((name, descriptor))
    if entry is not None and entry[1]:
        function = _unwrap(entry[0])
        if getattr(function, "_jcaller", False):
            return function, True
        return function, False
    for base in host.py.__mro__:
        if name in vars(base):
            value = vars(base)[name]
            function = _unwrap(value)
            params, ret = parse_descriptor(descriptor)
            return dynamic_adapter(function, params, ret), False
    return None, False


def host_virtual(host, name, descriptor):
    """fn(receiver, *args) for an instance method of a host class, register values in and out"""
    entry = host.typed().get((name, descriptor))
    if entry is not None and not entry[1]:
        return _unwrap(entry[0])
    params, ret = parse_descriptor(descriptor)
    for base in host.py.__mro__:
        if name in vars(base):
            return dynamic_receiver_adapter(_unwrap(vars(base)[name]), params, ret)
    obj = api.lookup_host("java.lang.Object")
    if host is not obj:
        return host_virtual(obj, name, descriptor)
    return None


def host_constructor(host, descriptor):
    """fn(receiver, *args) that runs a constructor of a host class and returns the object to use"""
    entry = host.typed().get(("<init>", descriptor))
    if entry is not None:
        function = _unwrap(entry[0])

        def construct(receiver, *args):
            function(receiver, *args)
            return receiver
        return construct
    params, ret = parse_descriptor(descriptor)
    if host.value_type:
        build = host.construct

        def build_value(receiver, *args):
            return build(*args)
        return build_value
    py = host.py
    init = py.__init__
    flags = tuple(d[0] if d[0] in "ZC" else None for d in params)

    def construct_dynamic(receiver, *args):
        if any(flags):
            args = tuple(bool(a) if f == "Z" else (chr(a) if f == "C" else a) for a, f in zip(args, flags))
        init(receiver, *args)
        return receiver
    return construct_dynamic


def host_all_supers(host):
    """descriptors of a host class, its python bases and the interfaces it names"""
    found = getattr(host, "_all_supers", None)
    if found is None:
        found = {host.descriptor}
        for name in host._interface_names:
            other = api.lookup_host(name)
            if other is not None:
                found |= host_all_supers(other)
        for base in host.py.__mro__[1:]:
            other = api._by_pytype.get(base)
            if other is not None and other is not host:
                found |= host_all_supers(other)
        host._all_supers = frozenset(found)
        found = host._all_supers
    return found


def _host_instance_ok(self, value):
    if self.name == "java.lang.Object":
        return True
    if isinstance(value, self.pytype):
        return True
    if self.interface:
        supers = getattr(value.__class__, "_jsupers", None)
        if supers is not None:
            return self.descriptor in supers
        host = api.host_for_pytype(value.__class__)
        if host is not None and self.descriptor in host_all_supers(host):
            return True
        # a python object that says it implements java interfaces (java.dynamic_proxy) is an instance of each of them
        return any(isinstance(i, type) and issubclass(i, self.pytype) for i in getattr(value, "_java_interfaces", ()))
    return False


HostClass.instance_ok = _host_instance_ok
HostClass.all_supers = host_all_supers


class DexMixin:
    """base of every python class made from a dex class: bridges the mangled attributes of virtual methods that a host superclass implements"""

    def __getattr__(self, attr):
        if attr.startswith("jm_"):
            key = api.method_of_attr(attr)
            if key is not None:
                fn = find_host_virtual(type(self), key[0], key[1])
                if fn is not None:
                    setattr(type(self), attr, fn)
                    return types.MethodType(fn, self)
                throw_new("java.lang.AbstractMethodError", "%s.%s%s" % (
                    runtime.class_of(self).getName(), key[0], key[1]))
        raise AttributeError("'%s' object has no attribute '%s'" % (type(self).__name__, attr))


def find_host_virtual(py, name, descriptor):
    """the implementation a dex class inherits from its nearest host base class or, for a default method, from a host interface it implements"""
    for base in py.__mro__:
        host = api._by_pytype.get(base)
        if host is not None:
            found = host_virtual(host, name, descriptor)
            if found is not None and not _is_object_fallback(host, found, name, descriptor):
                return found
            break
    jtype = getattr(py, "_jclass", None)
    if jtype is not None:
        for interface in _host_interfaces(jtype):
            entry = interface.typed().get((name, descriptor))
            if entry is not None and not entry[1]:
                return _unwrap(entry[0])
            for klass in interface.py.__mro__:
                if name in vars(klass) and callable(_unwrap(vars(klass)[name])):
                    params, ret = parse_descriptor(descriptor)
                    return dynamic_receiver_adapter(_unwrap(vars(klass)[name]), params, ret)
    return host_virtual(api.lookup_host("java.lang.Object"), name, descriptor)


def _is_object_fallback(host, function, name, descriptor):
    """host_virtual falls back to java.lang.Object for any host class; that answer must not hide a default method of an interface"""
    obj = api.lookup_host("java.lang.Object")
    if host is obj:
        return False
    return function is host_virtual(obj, name, descriptor) and not any(
        name in vars(klass) for klass in host.py.__mro__)


def _host_interfaces(jtype):
    found = []
    queue = list(jtype.all_interfaces()) if isinstance(jtype, DexClass) else []
    while queue:
        interface = queue.pop(0)
        if isinstance(interface, HostClass) and interface not in found:
            found.append(interface)
            queue.extend(api.lookup_host(n) for n in interface._interface_names if api.lookup_host(n) is not None)
    return found


class DexMethod:
    """a method a dex class declares. function() translates and compiles it on first use"""

    def __init__(self, owner, index, method_id, encoded):
        self.owner = owner
        self.index = index
        self.name = method_id.name
        self.proto = method_id.proto
        self.descriptor = method_id.proto.descriptor()
        self.access = encoded.access
        self.code_off = encoded.code_off
        self.static = bool(encoded.access & ACC_STATIC)
        self.params = method_id.proto.parameters
        self.attr = method_attr(self.name, self.descriptor)
        self._function = None
        self._lock = threading.RLock()

    def is_virtual(self):
        return not (self.access & (ACC_STATIC | ACC_PRIVATE)) and self.name != "<init>" and self.name != "<clinit>"

    def __repr__(self):
        return "<DexMethod %s.%s%s>" % (self.owner.descriptor, self.name, self.descriptor)

    def function(self):
        fn = self._function
        if fn is None:
            with self._lock:
                fn = self._function
                if fn is None:
                    fn = self._function = self._build()
        return fn

    def _build(self):
        owner = self.owner
        access = self.access
        if access & ACC_NATIVE:
            def native(*args):
                throw_new("java.lang.UnsatisfiedLinkError",
                          "%s.%s%s is native" % (api.binary_name(owner.descriptor), self.name, self.descriptor))
            return native
        code = owner.dexfile.code(self.code_off)
        if code is None:
            def abstract(*args):
                throw_new("java.lang.AbstractMethodError",
                          "abstract method \"%s.%s%s\"" % (api.binary_name(owner.descriptor), self.name,
                                                          self.descriptor))
            return abstract
        label = "%s.%s%s" % (api.binary_name(owner.descriptor), self.name, self.descriptor)
        fn = native_path.compile_method(owner.dexfile, code, self.proto, access, label)
        if fn is not None:
            return fn
        env = owner.env
        cache = method_cache.current()
        translation = None
        if cache is not None:
            key = method_cache.method_key(owner.dexfile.sha256, self.index)
            translation = self._stored(cache.get(key), env)
        if translation is None:
            asked = method_cache.RecordingEnv(env) if cache is not None else env
            try:
                translation = translate.translate(owner.dexfile, code, self.name, self.proto, access,
                                                  owner.descriptor, asked, label, uid=str(self.index))
            except translate.TranslateError as error:
                throw_new("java.lang.VerifyError", "%s: %s" % (label, error))
            if cache is not None:
                translation.code = compile(translation.source, "<dex %s>" % label, "exec")
                translation.deps = asked.log
                cache.put(key, (translation.code, translation.sites, translation.consts, translation.handlers,
                                translation.deps))
        fn = owner.install(translation, label, self.index)
        if access & ACC_SYNCHRONIZED:
            fn = _synchronized(fn, owner if self.static else None)
        return fn

    def _stored(self, payload, env):
        """the translation kept in the cache, or None when there is none or the classes around the method changed since"""
        if payload is None:
            return None
        try:
            code, sites, consts, handlers, deps = payload
            if not isinstance(code, types.CodeType) or not method_cache.still_true(deps, env):
                return None
        except (TypeError, ValueError, AttributeError):
            return None
        return translate.Translation(None, sites, consts, handlers, code, deps)

    def invoke(self, *args):
        """call from python with natural values (bool, one character str ...); the result is converted back. a call that
        arrives without a budget gets the default one, when limits.configure set it"""
        if limits._defaults is None:
            return self._invoke(*args)
        with limits.entry():
            return self._invoke(*args)

    def _invoke(self, *args):
        fn = self.function()
        params = self.params
        if not self.static:
            receiver, args = args[0], args[1:]
        if len(args) != len(params):
            raise TypeError("%s takes %d arguments, %d given" % (self.name, len(params), len(args)))
        converted = tuple(to_register(a, d) for a, d in zip(args, params))
        if self.static:
            self.owner.ensure_initialized()
            result = fn(*converted)
        else:
            result = fn(receiver, *converted)
        return from_register(result, self.proto.return_type) if self.proto.return_type != "V" else None


def _synchronized(fn, lock_owner):
    if lock_owner is not None:
        def static_call(*args):
            runtime.monitor_enter(lock_owner)
            try:
                return fn(*args)
            finally:
                runtime.monitor_exit(lock_owner)
        return static_call

    def call(this, *args):
        runtime.monitor_enter(this)
        try:
            return fn(this, *args)
        finally:
            runtime.monitor_exit(this)
    return call


class Site:
    """a global of translated code that resolves its reference when it first runs and then replaces itself by the result"""
    __slots__ = ("owner", "globals", "name", "spec", "fn")

    def __init__(self, owner, globals_, name, spec):
        self.owner = owner
        self.globals = globals_
        self.name = name
        self.spec = spec
        self.fn = None

    def __call__(self, *args):
        fn = self.fn
        if fn is None:
            fn = self.resolve()
        return fn(*args)

    def resolve(self):
        fn, cacheable = bind(self.owner, self.spec)
        self.fn = fn
        if cacheable:
            self.globals[self.name] = fn
        return fn


class CatchTest:
    """the type test of a catch clause: an unresolvable exception type never matches"""
    __slots__ = ("owner", "descriptor", "jtype")

    def __init__(self, owner, descriptor):
        self.owner = owner
        self.descriptor = descriptor
        self.jtype = None

    def __call__(self, exc):
        jtype = self.jtype
        if jtype is None:
            jtype = self.jtype = self.owner.loader.load_or_none(self.descriptor)
            if jtype is None:
                return False
        return bool(jtype.isInstance(exc))


class DexClass(JType):
    loader_bound = True

    def __init__(self, loader, dexfile, class_def):
        self.loader = loader
        self.dexfile = dexfile
        self.class_def = class_def
        self.descriptor = dexfile.type(class_def.type_idx)
        self.access = class_def.access
        self.state = UNINITIALIZED
        self.init_lock = threading.RLock()
        self.init_thread = None
        self.init_error = None
        self.superclass = None
        self.interfaces = ()
        self.pytype = None
        self.supers = _EMPTY
        self.direct = {}
        self.virtual = {}
        self.instance_attrs = {}
        self.static_attrs = {}
        self.field_defs = []
        self.globals = None
        self.env = _ClassEnv(self)
        self._annotations = None


    def isInterface(self):
        return bool(self.access & ACC_INTERFACE)

    def isEnum(self):
        return bool(self.access & ACC_ENUM)

    def isAnnotation(self):
        return bool(self.access & ACC_ANNOTATION)

    def getSuperclass(self):
        return None if self.isInterface() else self.superclass

    def getInterfaces(self):
        array = runtime.new_array("[Ljava/lang/Class;", 0)
        array.extend(self.interfaces)
        return array

    def getEnumConstants(self):
        """a copy of the values() array of an enum, None for any other class"""
        if not self.isEnum() or self.superclass is None or self.superclass.getName() != "java.lang.Enum":
            return None
        self.ensure_initialized()
        values = self.direct.get(("values", "()[" + self.descriptor))
        if values is None:
            return None
        return values.function()()

    def getModifiers(self):
        """the access flags, with the ones of a nested class taken from its InnerClass annotation as the dex format keeps them there"""
        flags = self.access & 0xFFFF
        for annotation in self.annotations_directory()[0]:
            if annotation.type == "Ldalvik/annotation/InnerClass;":
                for name, value in annotation.elements:
                    if name == "accessFlags":
                        return value[1] & 0xFFFF
        return flags

    def getClassLoader(self):
        return self.loader.java_object()

    def annotations_directory(self):
        """(class annotations, {field idx: annotations}, {method idx: annotations}, {method idx: parameter annotations})"""
        if self._annotations is None:
            self._annotations = self.dexfile.annotations_directory(self.class_def)
        return self._annotations

    def isInstance(self, value):
        if value is None:
            return 0
        if self.isInterface():
            supers = getattr(value.__class__, "_jsupers", None)
            if supers is not None:
                return 1 if self.descriptor in supers else 0
            return 0
        return 1 if isinstance(value, self.pytype) else 0

    def isAssignableFrom(self, other):
        if other is self:
            return 1
        if isinstance(other, DexClass):
            return 1 if self.descriptor in other.supers else 0
        if isinstance(other, HostClass):
            return 1 if self.descriptor in host_all_supers(other) else 0
        return 0

    def __repr__(self):
        return "<DexClass %s>" % self.descriptor


    def ensure_initialized(self):
        if self.state == INITIALIZED:
            return
        self._initialize()

    def _initialize(self):
        with self.init_lock:
            if self.state == INITIALIZED:
                return
            if self.state == INITIALIZING:
                if self.init_thread == threading.get_ident():
                    return
            if self.state == ERRONEOUS:
                error = runtime.make_throwable(api.lookup_host("java.lang.NoClassDefFoundError").py,
                                               "Could not initialize class " + api.binary_name(self.descriptor))
                error._cause = self.init_error
                raise error
            self.state = INITIALIZING
            self.init_thread = threading.get_ident()
            try:
                superclass = self.superclass
                if isinstance(superclass, DexClass) and not self.isInterface():
                    superclass.ensure_initialized()
                clinit = self.direct.get(("<clinit>", "()V"))
                if clinit is not None:
                    clinit.function()()
            except BaseException as error:
                failure = runtime.to_throwable(error)
                self.init_error = failure
                self.state = ERRONEOUS
                self.init_thread = None
                if isinstance(failure, api.lookup_host("java.lang.Error").py):
                    raise failure
                wrapped = runtime.make_throwable(api.lookup_host("java.lang.ExceptionInInitializerError").py, None)
                wrapped._cause = failure
                raise wrapped
            self.init_thread = None
            self.state = INITIALIZED


    def install(self, translation, label, index):
        """compile a translation into the globals of the class and return its function"""
        glob = self.globals
        uid = str(index)
        for name, (kind, value) in translation.consts.items():
            glob[name] = sys.intern(value) if kind == "string" else value
        for name, spec in translation.sites.items():
            glob[name] = Site(self, glob, name, spec)
        if translation.handlers:
            glob["_H" + uid] = {block: tuple((None if desc is None else CatchTest(self, desc), target)
                                             for desc, target in entries)
                                for block, entries in translation.handlers.items()}
        compiled = translation.code
        if compiled is None:
            compiled = compile(translation.source, "<dex %s>" % label, "exec")
        namespace = {}
        exec(compiled, glob, namespace)
        fn = namespace["m"]
        fn.__qualname__ = label
        return fn

    def find_method(self, name, descriptor):
        """the DexMethod declared by this class, or None"""
        return self.direct.get((name, descriptor)) or self.virtual.get((name, descriptor))

    def lookup_method(self, name, descriptor):
        """method resolution: the class, its superclasses, then the superinterfaces. returns (DexMethod or None, host class or None)"""
        klass = self
        while isinstance(klass, DexClass):
            found = klass.find_method(name, descriptor)
            if found is not None:
                return found, None
            klass = klass.superclass
        if isinstance(klass, HostClass):
            if host_virtual(klass, name, descriptor) is not None:
                return None, klass
        for interface in self.all_interfaces():
            if isinstance(interface, DexClass):
                found = interface.find_method(name, descriptor)
                if found is not None:
                    return found, None
        return None, None

    def all_interfaces(self):
        """the direct and inherited interfaces, nearest first"""
        seen = []
        queue = []
        klass = self
        while isinstance(klass, DexClass):
            queue.extend(klass.interfaces)
            klass = klass.superclass
        while queue:
            interface = queue.pop(0)
            if interface in seen:
                continue
            seen.append(interface)
            if isinstance(interface, DexClass):
                queue.extend(interface.interfaces)
        return seen

    def find_field(self, name, type_desc, static):
        """(declaring DexClass, attribute) of a field by the java lookup: the class, its interfaces, then the superclass; or None"""
        table = self.static_attrs if static else self.instance_attrs
        attr = table.get((name, type_desc))
        if attr is not None:
            return self, attr
        for interface in self.interfaces:
            if isinstance(interface, DexClass):
                found = interface.find_field(name, type_desc, True)
                if found is not None and static:
                    return found
        if isinstance(self.superclass, DexClass):
            return self.superclass.find_field(name, type_desc, static)
        return None


    def method(self, name, descriptor=None):
        """the DexMethod of a name, optionally narrowed by descriptor; walks the superclasses"""
        klass = self
        found = []
        while isinstance(klass, DexClass):
            for (n, d), method in list(klass.direct.items()) + list(klass.virtual.items()):
                if n == name and (descriptor is None or d == descriptor):
                    found.append(method)
            if found:
                break
            klass = klass.superclass
        if not found:
            raise AttributeError("%s has no method %s" % (self.descriptor, name))
        if len(found) > 1:
            raise AttributeError("%s.%s is overloaded, give a descriptor: %s" % (
                self.descriptor, name, ", ".join(m.descriptor for m in found)))
        return found[0]

    def call_static(self, name, *args, descriptor=None):
        method = self.method(name, descriptor)
        if not method.static:
            raise TypeError("%s is not static" % name)
        return method.invoke(*args)

    def new_instance(self, *args, descriptor=None):
        if self.access & (ACC_ABSTRACT | ACC_INTERFACE):
            throw_new("java.lang.InstantiationError", api.binary_name(self.descriptor))
        self.ensure_initialized()
        candidates = [m for (n, d), m in self.direct.items() if n == "<init>" and (descriptor is None or d == descriptor)]
        if len(candidates) > 1:
            candidates = [m for m in candidates if len(m.params) == len(args)] or candidates
        if len(candidates) != 1:
            raise AttributeError("%s: %d constructors match" % (self.descriptor, len(candidates)))
        ctor = candidates[0]
        obj = self.pytype.__new__(self.pytype)
        ctor.invoke(obj, *args)
        return obj


class _ClassEnv(translate.Env):
    """what the translator may ask about the classes around the class it translates a method of"""

    def __init__(self, owner):
        self.owner = owner

    def _class(self, descriptor):
        # a class that cannot be defined is reported by the site of the instruction that names it, not here
        try:
            return self.owner.loader.load_or_none(descriptor)
        except runtime.api.lookup_host("java.lang.Throwable").py:
            return None

    def dex_class(self, descriptor):
        found = self._class(descriptor)
        return isinstance(found, DexClass) and not found.isInterface()

    def instance_field(self, class_desc, name, type_desc):
        found = self._class(class_desc)
        if not isinstance(found, DexClass):
            return None
        resolved = found.find_field(name, type_desc, False)
        return resolved[1] if resolved else None

    def own_static(self, class_desc, name, type_desc):
        if class_desc != self.owner.descriptor:
            return None
        return self.owner.static_attrs.get((name, type_desc))


_DEFAULT_OF = {"Z": 0, "B": 0, "S": 0, "C": 0, "I": 0, "J": 0, "F": 0.0, "D": 0.0}


def _constant(value, type_desc):
    kind, payload = value
    if kind == VALUE_NULL:
        return None
    if kind == VALUE_BOOLEAN:
        return 1 if payload else 0
    if kind in (VALUE_BYTE, VALUE_SHORT, VALUE_CHAR, VALUE_INT, VALUE_LONG):
        return payload
    if kind in (VALUE_FLOAT, VALUE_DOUBLE):
        return payload
    return payload


def define_class(loader, dexfile, class_def, resolve_super):
    """build the DexClass for a class definition. resolve_super loads the superclass and the interfaces through the loader"""
    cls = DexClass(loader, dexfile, class_def)
    descriptor = cls.descriptor
    super_desc = dexfile.superclass(class_def)
    interface_descs = dexfile.interfaces(class_def)
    is_interface = bool(class_def.access & ACC_INTERFACE)
    if super_desc is None and descriptor != "Ljava/lang/Object;":
        throw_new("java.lang.ClassFormatError", "class %s has no superclass" % api.binary_name(descriptor))
    superclass = resolve_super(super_desc) if super_desc is not None else None
    interfaces = tuple(resolve_super(d) for d in interface_descs)
    if superclass is not None:
        if superclass.isInterface():
            throw_new("java.lang.IncompatibleClassChangeError", "Superclass %s of %s is an interface" % (
                superclass.getName(), cls.getName()))
        if isinstance(superclass, HostClass) and (superclass.final or superclass.value_type):
            throw_new("java.lang.VerifyError", "Superclass %s of %s is final" % (superclass.getName(), cls.getName()))
        if isinstance(superclass, DexClass) and superclass.access & ACC_FINAL:
            throw_new("java.lang.IncompatibleClassChangeError", "Superclass %s of %s is final" % (
                superclass.getName(), cls.getName()))
    for interface in interfaces:
        if not interface.isInterface():
            throw_new("java.lang.IncompatibleClassChangeError", "Class %s implements non-interface class %s" % (
                cls.getName(), interface.getName()))
    cls.superclass = superclass
    cls.interfaces = interfaces
    supers = {descriptor}
    for parent in ((superclass,) if superclass is not None else ()) + interfaces:
        if isinstance(parent, DexClass):
            supers |= parent.supers
        else:
            supers |= host_all_supers(parent)
    cls.supers = frozenset(supers)
    if superclass is None or is_interface:
        base = jlang.Object
    elif isinstance(superclass, DexClass):
        base = superclass.pytype
    else:
        base = superclass.py
    namespace = {"__module__": "dexvm.generated", "_jsupers": cls.supers}
    bases = (base, DexMixin) if not issubclass(base, DexMixin) else (base,)
    class_data = dexfile.class_data(class_def)
    # fields
    for encoded in class_data.static_fields + class_data.instance_fields:
        ref = dexfile.field(encoded.field_idx)
        if ref.class_type != descriptor:
            raise DexFormatError("field %s declared by %s belongs to %s" % (ref.name, descriptor, ref.class_type))
        static = encoded in class_data.static_fields
        attr = field_attr(descriptor, ref.name, static)
        (cls.static_attrs if static else cls.instance_attrs)[(ref.name, ref.type)] = attr
        cls.field_defs.append((ref.name, ref.type, encoded.access, static, attr))
        namespace[attr] = _DEFAULT_OF.get(ref.type)
    statics = dexfile.static_values(class_def)
    for encoded, value in zip(class_data.static_fields, statics):
        ref = dexfile.field(encoded.field_idx)
        constant = _constant(value, ref.type)
        if value[0] == VALUE_STRING:
            constant = sys.intern(dexfile.string(value[1]))
        if ref.type == "F" and isinstance(constant, float):
            constant = runtime.f32(constant)
        namespace[field_attr(descriptor, ref.name, True)] = constant
    # methods
    for encoded in class_data.direct_methods + class_data.virtual_methods:
        method_id = dexfile.method(encoded.method_idx)
        if method_id.class_type != descriptor:
            raise DexFormatError("method %s declared by %s belongs to %s" % (
                method_id.name, descriptor, method_id.class_type))
        method = DexMethod(cls, encoded.method_idx, method_id, encoded)
        key = (method.name, method.descriptor)
        if method.is_virtual():
            cls.virtual[key] = method
        else:
            cls.direct[key] = method
        if (key in cls.virtual and cls.virtual[key] is not method) or (key in cls.direct and cls.direct[key] is not method):
            raise DexFormatError("method %s%s declared twice in %s" % (method.name, method.descriptor, descriptor))
    cls.pytype = type(api.escape(descriptor), bases, namespace)
    cls.pytype._jclass = cls
    cls.globals = _class_globals(cls)
    for method in cls.virtual.values():
        setattr(cls.pytype, method.attr, _trampoline(cls, method))
    _install_plain_names(cls)
    _install_defaults(cls)
    return cls


def _class_globals(cls):
    glob = dict(HELPERS)
    glob["_C"] = cls.pytype
    glob["__name__"] = "dexvm.generated." + escape(cls.descriptor)
    return glob


def _trampoline(cls, method):
    """the first call of a virtual method compiles it and replaces the class attribute by the compiled function"""
    def first_call(self, *args):
        fn = method.function()
        if getattr(cls.pytype, method.attr, None) is first_call or method.attr not in vars(cls.pytype):
            setattr(cls.pytype, method.attr, fn)
        return fn(self, *args)
    first_call.__qualname__ = "%s.%s" % (cls.descriptor, method.name)
    return first_call


def _install_plain_names(cls):
    """host python code calls a method of a dex object by its java name, with natural values: install a function per name that picks the overload and converts"""
    by_name = {}
    for (name, descriptor), method in cls.virtual.items():
        by_name.setdefault(name, []).append(method)
    for name, methods in by_name.items():
        if name.startswith("<") or not name.isidentifier() or name.startswith("__"):
            continue
        setattr(cls.pytype, name, _plain_dispatcher(cls, name, methods))


def _plain_dispatcher(cls, name, methods):
    ordered = tuple(methods)

    def call(self, *args):
        chosen = None
        if len(ordered) == 1:
            chosen = ordered[0]
        else:
            matching = [m for m in ordered if len(m.params) == len(args)]
            if len(matching) == 1:
                chosen = matching[0]
            else:
                for method in matching:
                    if all(_fits(arg, desc, cls.loader) for arg, desc in zip(args, method.params)):
                        chosen = method
                        break
        if chosen is None or len(chosen.params) != len(args):
            raise TypeError("no overload of %s takes %d such arguments" % (name, len(args)))
        converted = tuple(to_register(a, d) for a, d in zip(args, chosen.params))
        result = getattr(self, chosen.attr)(*converted)
        return from_register(result, chosen.proto.return_type) if chosen.proto.return_type != "V" else None
    call.__name__ = name
    return call


def _fits(value, descriptor, loader):
    code = descriptor[0]
    if code == "Z":
        return isinstance(value, (bool, int)) and value in (0, 1)
    if code == "C":
        return isinstance(value, str) and len(value) == 1
    if code in "BSIJ":
        return isinstance(value, int) and not isinstance(value, bool)
    if code in "FD":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if value is None:
        return True
    jtype = loader.load_or_none(descriptor)
    return jtype is not None and bool(jtype.isInstance(value))


def _install_defaults(cls):
    """interface default methods: a class that neither declares nor inherits an implementation gets the most specific default"""
    if cls.isInterface():
        return
    chosen = {}
    for interface in cls.all_interfaces():
        if not isinstance(interface, DexClass):
            continue
        for key, method in interface.virtual.items():
            if method.access & ACC_ABSTRACT:
                continue
            if getattr(cls.pytype, method.attr, None) is not None:
                inherited_from = chosen.get(method.attr)
                if inherited_from is None:
                    continue
                if inherited_from.descriptor not in interface.supers and interface.descriptor in inherited_from.owner.supers:
                    pass
                else:
                    continue
            chosen[method.attr] = method
    for attr, method in chosen.items():
        setattr(cls.pytype, attr, _trampoline_default(method))


def _trampoline_default(method):
    def default(self, *args):
        return method.function()(self, *args)
    default.__qualname__ = "%s.%s" % (method.owner.descriptor, method.name)
    return default


def _noclass(loader, descriptor):
    jtype = loader.load_or_none(descriptor)
    if jtype is None:
        throw_new("java.lang.NoClassDefFoundError", api.binary_name(descriptor))
    return jtype


def bind(owner, spec):
    """(callable, cacheable) for a site spec of translated code in a method of class owner"""
    kind = spec[0]
    handler = _BINDERS.get(kind)
    if handler is None:
        throw_new("java.lang.UnsupportedOperationException", "site kind %s" % kind)
    return handler(owner, *spec[1:])


def _bind_const_class(owner, descriptor):
    jtype = _noclass(owner.loader, descriptor)
    return (lambda: jtype), True


def _bind_check_cast(owner, descriptor):
    jtype = _noclass(owner.loader, descriptor)
    name = jtype.getName()
    if isinstance(jtype, DexClass) and not jtype.isInterface():
        py = jtype.pytype

        def check(value):
            if value is not None and not isinstance(value, py):
                throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                    runtime.type_name_of(value), name))
            return value
        return check, True

    def check_any(value):
        if value is not None and not jtype.isInstance(value):
            throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                runtime.type_name_of(value), name))
        return value
    return check_any, True


def _bind_instance_of(owner, descriptor):
    jtype = _noclass(owner.loader, descriptor)
    if isinstance(jtype, DexClass) and not jtype.isInterface():
        py = jtype.pytype
        return (lambda value: 1 if isinstance(value, py) else 0), True
    return (lambda value: 1 if value is not None and jtype.isInstance(value) else 0), True


def _bind_new_instance(owner, descriptor):
    jtype = _noclass(owner.loader, descriptor)
    if isinstance(jtype, DexClass):
        if jtype.access & (ACC_ABSTRACT | ACC_INTERFACE):
            throw_new("java.lang.InstantiationError", api.binary_name(descriptor))
        jtype.ensure_initialized()
        py = jtype.pytype
        if jtype.state == INITIALIZED:
            return (lambda: py.__new__(py)), True

        def create():
            jtype.ensure_initialized()
            return py.__new__(py)
        return create, False
    if isinstance(jtype, HostClass):
        if jtype.interface or jtype.abstract:
            throw_new("java.lang.InstantiationError", api.binary_name(descriptor))
        if jtype.value_type:
            return (lambda: Uninitialized(jtype)), True
        py = jtype.py
        return (lambda: py.__new__(py)), True
    throw_new("java.lang.InstantiationError", api.binary_name(descriptor))


def _bind_new_array(owner, descriptor):
    array_type = owner.loader.array_type(descriptor)
    return (lambda size: runtime.new_array(array_type, size)), True


def _bind_filled(owner, descriptor):
    array_type = owner.loader.array_type(descriptor)
    component = array_type.component
    code = descriptor[1]

    def make(*values):
        if code == "F":
            values = tuple(runtime.as_float(v) for v in values)
        elif code in "ZBSCIJ" or code == "D":
            pass
        else:
            for value in values:
                if value is not None and not component.isInstance(value):
                    throw_new("java.lang.ArrayStoreException", runtime.type_name_of(value))
        return runtime.JArray(array_type, values)
    return make, True


def _declaring_for_field(owner, class_desc, name, type_desc, static):
    jtype = _noclass(owner.loader, class_desc)
    if isinstance(jtype, DexClass):
        found = jtype.find_field(name, type_desc, static)
        if found is None:
            throw_new("java.lang.NoSuchFieldError", "No %s field %s:%s in class %s" % (
                "static" if static else "instance", name, type_desc, api.binary_name(class_desc)))
        return found
    return jtype, None


def _bind_sget(owner, class_desc, name, type_desc):
    declaring, attr = _declaring_for_field(owner, class_desc, name, type_desc, True)
    if attr is not None:
        declaring.ensure_initialized()
        py = declaring.pytype
        getter = functools.partial(getattr, py, attr)
        if declaring.state == INITIALIZED:
            return getter, True

        def read():
            declaring.ensure_initialized()
            return getter()
        return read, False
    py = declaring.py

    def host_read():
        if not hasattr(py, name):
            throw_new("java.lang.NoSuchFieldError", "%s.%s" % (api.binary_name(class_desc), name))
        return to_register(getattr(py, name), type_desc)
    return host_read, True


def _bind_sput(owner, class_desc, name, type_desc):
    declaring, attr = _declaring_for_field(owner, class_desc, name, type_desc, True)
    if attr is not None:
        declaring.ensure_initialized()
        py = declaring.pytype
        if declaring.state == INITIALIZED:
            return (lambda value: setattr(py, attr, value)), True

        def write(value):
            declaring.ensure_initialized()
            setattr(py, attr, value)
        return write, False
    py = declaring.py

    def host_write(value):
        setattr(py, name, from_register(value, type_desc))
    return host_write, True


def _bind_iget(owner, class_desc, name, type_desc):
    declaring, attr = _declaring_for_field(owner, class_desc, name, type_desc, False)
    if attr is not None:
        return (lambda receiver: getattr(receiver, attr)), True
    return (lambda receiver: to_register(getattr(receiver, name), type_desc)), True


def _bind_iput(owner, class_desc, name, type_desc):
    declaring, attr = _declaring_for_field(owner, class_desc, name, type_desc, False)
    if attr is not None:
        return (lambda receiver, value: setattr(receiver, attr, value)), True
    return (lambda receiver, value: setattr(receiver, name, from_register(value, type_desc))), True


def _bind_static(owner, class_desc, name, descriptor):
    jtype = _noclass(owner.loader, class_desc)
    if isinstance(jtype, DexClass):
        klass = jtype
        method = None
        while isinstance(klass, DexClass):
            method = klass.direct.get((name, descriptor))
            if method is not None:
                break
            klass = klass.superclass
        if method is None or not method.static:
            throw_new("java.lang.NoSuchMethodError", "No static method %s%s in class %s" % (
                name, descriptor, api.binary_name(class_desc)))
        declaring = method.owner
        declaring.ensure_initialized()
        fn = method.function()
        if declaring.state == INITIALIZED:
            return fn, True

        def call(*args):
            declaring.ensure_initialized()
            return fn(*args)
        return call, False
    function, caller_sensitive = host_static(jtype, name, descriptor)
    if function is None:
        throw_new("java.lang.NoSuchMethodError", "No static method %s%s in class %s" % (
            name, descriptor, api.binary_name(class_desc)))
    if caller_sensitive:
        return functools.partial(function, caller=owner), True
    return function, True


def _bind_direct(owner, class_desc, name, descriptor):
    jtype = _noclass(owner.loader, class_desc)
    if isinstance(jtype, DexClass):
        method = jtype.direct.get((name, descriptor))
        if method is None:
            method = jtype.virtual.get((name, descriptor))
        if method is None:
            throw_new("java.lang.NoSuchMethodError", "No direct method %s%s in class %s" % (
                name, descriptor, api.binary_name(class_desc)))
        return method.function(), True
    if name == "<init>":
        return host_constructor(jtype, descriptor), True
    function = host_virtual(jtype, name, descriptor)
    if function is None:
        throw_new("java.lang.NoSuchMethodError", "No method %s%s in class %s" % (
            name, descriptor, api.binary_name(class_desc)))
    return function, True


def _bind_super(owner, class_desc, name, descriptor):
    jtype = _noclass(owner.loader, class_desc)
    if isinstance(jtype, DexClass):
        method, host = jtype.lookup_method(name, descriptor)
        if method is not None:
            if method.access & ACC_ABSTRACT:
                throw_new("java.lang.AbstractMethodError", "%s.%s%s" % (api.binary_name(class_desc), name, descriptor))
            return method.function(), True
        if host is not None:
            return host_virtual(host, name, descriptor), True
        throw_new("java.lang.NoSuchMethodError", "No super method %s%s in class %s" % (
            name, descriptor, api.binary_name(class_desc)))
    function = host_virtual(jtype, name, descriptor)
    if function is None:
        throw_new("java.lang.NoSuchMethodError", "No super method %s%s in class %s" % (
            name, descriptor, api.binary_name(class_desc)))
    return function, True


class VirtualSite:
    """invoke-virtual and invoke-interface when the receiver is not known to be a dex object: the target is looked up by the class of the receiver, once per class"""

    __slots__ = ("owner", "class_desc", "name", "descriptor", "cache", "attr")

    def __init__(self, owner, class_desc, name, descriptor):
        self.owner = owner
        self.class_desc = class_desc
        self.name = name
        self.descriptor = descriptor
        self.cache = {}
        self.attr = method_attr(name, descriptor)

    def __call__(self, receiver, *args):
        fn = self.cache.get(receiver.__class__)
        if fn is None:
            fn = self.lookup(receiver)
        return fn(receiver, *args)

    def lookup(self, receiver):
        if receiver is None:
            runtime.npe("Attempt to invoke virtual method '%s.%s%s' on a null object reference" % (
                api.binary_name(self.class_desc), self.name, self.descriptor))
        t = receiver.__class__
        fn = None
        if getattr(t, "_jclass", None) is not None:
            fn = getattr(t, self.attr, None)
            if fn is None:
                fn = find_host_virtual(t, self.name, self.descriptor)
            if fn is None:
                throw_new("java.lang.AbstractMethodError", "%s.%s%s" % (
                    runtime.class_of(receiver).getName(), self.name, self.descriptor))
        elif t is runtime.JArray:
            fn = getattr(runtime.JArray, self.name, None)
            if fn is None:
                fn = host_virtual(api.lookup_host("java.lang.Object"), self.name, self.descriptor)
        else:
            host = api.host_for_pytype(t)
            if host is not None:
                fn = host_virtual(host, self.name, self.descriptor)
            if fn is None:
                fn = _python_method(t, self.name, self.descriptor)
        if fn is None:
            throw_new("java.lang.NoSuchMethodError", "%s.%s%s" % (
                api.binary_name(self.class_desc), self.name, self.descriptor))
        self.cache[t] = fn
        return fn


def _python_method(py, name, descriptor):
    """a python object the registry knows nothing about: its method of that name"""
    function = getattr(py, name, None)
    if function is None or not callable(function):
        return None
    params, ret = parse_descriptor(descriptor)
    return dynamic_receiver_adapter(function, params, ret)


def _bind_virtual(owner, class_desc, name, descriptor):
    return VirtualSite(owner, class_desc, name, descriptor), True


def _bind_polymorphic(owner, class_desc, name, descriptor):
    from .jinvoke import MethodHandle, MethodType, invoke_handle
    if class_desc != "Ljava/lang/invoke/MethodHandle;" or name not in ("invoke", "invokeExact"):
        throw_new("java.lang.NoSuchMethodError", "%s.%s%s" % (api.binary_name(class_desc), name, descriptor))
    params, result = parse_descriptor(descriptor)
    call_type = MethodType(owner.loader.load(result), [owner.loader.load(param) for param in params])

    exact = name == "invokeExact"

    def call(handle, *args):
        if handle is not None and not isinstance(handle, MethodHandle):
            throw_new("java.lang.ClassCastException", "receiver is not a MethodHandle")
        return invoke_handle(handle, call_type, descriptor, exact, args)
    return call, True


def _bind_custom(owner, index):
    from . import jindy
    return jindy.bind_custom(owner, index)


def _bind_handle_const(owner, index):
    from .format import (METHOD_HANDLE_STATIC_PUT, METHOD_HANDLE_STATIC_GET, METHOD_HANDLE_INSTANCE_PUT,
                         METHOD_HANDLE_INSTANCE_GET, METHOD_HANDLE_INVOKE_STATIC, METHOD_HANDLE_INVOKE_INSTANCE,
                         METHOD_HANDLE_INVOKE_CONSTRUCTOR, METHOD_HANDLE_INVOKE_DIRECT, METHOD_HANDLE_INVOKE_INTERFACE)
    from .jinvoke import MethodHandle, MethodType
    item = owner.dexfile.method_handle(index)
    if item.kind in (METHOD_HANDLE_STATIC_PUT, METHOD_HANDLE_STATIC_GET,
                     METHOD_HANDLE_INSTANCE_PUT, METHOD_HANDLE_INSTANCE_GET):
        ref = owner.dexfile.field(item.target_idx)
        field_type = owner.loader.load(ref.type)
        receiver = owner.loader.load(ref.class_type)
        void = owner.loader.load("V")
        specs = {
            METHOD_HANDLE_STATIC_PUT: ("sput", (field_type,), void),
            METHOD_HANDLE_STATIC_GET: ("sget", (), field_type),
            METHOD_HANDLE_INSTANCE_PUT: ("iput", (receiver, field_type), void),
            METHOD_HANDLE_INSTANCE_GET: ("iget", (receiver,), field_type),
        }
        kind, params, result = specs[item.kind]
        target = Site(owner, {}, "target", (kind, ref.class_type, ref.name, ref.type))
        if item.kind in (METHOD_HANDLE_INSTANCE_PUT, METHOD_HANDLE_INSTANCE_GET):
            inner = target

            def target(receiver, *args):
                if receiver is None:
                    runtime.npe()
                return inner(receiver, *args)
        handle = MethodHandle(MethodType(result, params), target)
        return (lambda: handle), True
    if item.kind not in (METHOD_HANDLE_INVOKE_STATIC, METHOD_HANDLE_INVOKE_INSTANCE, METHOD_HANDLE_INVOKE_CONSTRUCTOR,
                          METHOD_HANDLE_INVOKE_DIRECT, METHOD_HANDLE_INVOKE_INTERFACE):
        throw_new("java.lang.UnsupportedOperationException", "method handle kind %d is not implemented" % item.kind)
    ref = owner.dexfile.method(item.target_idx)
    proto = ref.proto
    params = [owner.loader.load(p) for p in proto.parameters]
    if item.kind == METHOD_HANDLE_INVOKE_CONSTRUCTOR:
        if ref.name != "<init>" or proto.return_type != "V":
            throw_new("java.lang.VerifyError", "constructor handle has an invalid target")
        result_type = owner.loader.load(ref.class_type)
        create = Site(owner, {}, "create", ("new-instance", ref.class_type))
        init = Site(owner, {}, "init", ("invoke-direct", ref.class_type, ref.name, proto.descriptor()))

        def construct(*args):
            instance = create()
            result = init(instance, *args)
            return instance if isinstance(result_type, DexClass) else result
        handle = MethodHandle(MethodType(result_type, params), construct)
        return (lambda: handle), True
    if item.kind != METHOD_HANDLE_INVOKE_STATIC:
        params.insert(0, owner.loader.load(ref.class_type))
    method_type = MethodType(owner.loader.load(proto.return_type), params)
    kinds = {METHOD_HANDLE_INVOKE_STATIC: "invoke-static", METHOD_HANDLE_INVOKE_INSTANCE: "invoke-virtual",
             METHOD_HANDLE_INVOKE_DIRECT: "invoke-direct", METHOD_HANDLE_INVOKE_INTERFACE: "invoke-interface"}
    target = Site(owner, {}, "target", (kinds[item.kind], ref.class_type, ref.name, proto.descriptor()))
    handle = MethodHandle(method_type, target)
    return (lambda: handle), True


def _bind_method_type_const(owner, index):
    from .jinvoke import MethodType
    proto = owner.dexfile.proto(index)
    result = owner.loader.load(proto.return_type)
    parameters = [owner.loader.load(descriptor) for descriptor in proto.parameters]
    method_type = MethodType(result, parameters)
    return (lambda: method_type), True


_BINDERS = {
    "const-class": _bind_const_class,
    "check-cast": _bind_check_cast,
    "instance-of": _bind_instance_of,
    "new-instance": _bind_new_instance,
    "new-array": _bind_new_array,
    "filled-new-array": _bind_filled,
    "sget": _bind_sget,
    "sput": _bind_sput,
    "iget": _bind_iget,
    "iput": _bind_iput,
    "invoke-static": _bind_static,
    "invoke-direct": _bind_direct,
    "invoke-super": _bind_super,
    "invoke-virtual": _bind_virtual,
    "invoke-interface": _bind_virtual,
    "invoke-polymorphic": _bind_polymorphic,
    "invoke-custom": _bind_custom,
    "const-method-handle": _bind_handle_const,
    "const-method-type": _bind_method_type_const,
}


def _throw(value):
    if value is None:
        runtime.npe("throw with null exception")
    raise value


def _aput_object(array, index, value):
    if array is None:
        runtime.npe()
    if not 0 <= index < len(array):
        runtime.aioobe(array, index)
    if value is not None:
        component = array.jtype.component
        if not (component.getName() == "java.lang.Object" or component.isInstance(value)):
            throw_new("java.lang.ArrayStoreException", runtime.type_name_of(value))
    array[index] = value


def _aput_bits(array, index, value):
    """aput of a register that may hold raw constant bits: the array type decides how to read them"""
    if array is None:
        runtime.npe()
    if not 0 <= index < len(array):
        runtime.aioobe(array, index)
    code = array.jtype.descriptor[1]
    if code == "F":
        value = runtime.as_float(value)
    elif code == "D":
        value = runtime.as_double(value)
    array[index] = value


HELPERS = {
    "_tick": limits.tick,
    "_menter": runtime.monitor_enter,
    "_mexit": runtime.monitor_exit,
    "_idiv": runtime.idiv,
    "_irem": runtime.irem,
    "_ldiv": runtime.ldiv,
    "_lrem": runtime.lrem,
    "_f32": runtime.f32,
    "_fdiv": runtime.fdiv,
    "_ddiv": runtime.ddiv,
    "_frem": runtime.frem,
    "_drem": runtime.drem,
    "_d2i": runtime.d2i,
    "_d2l": runtime.d2l,
    "_cmpl": runtime.cmpl,
    "_cmpg": runtime.cmpg,
    "_bf": runtime.bits_to_float,
    "_bd": runtime.bits_to_double,
    "_aioobe": runtime.aioobe,
    "_aput_object": _aput_object,
    "_aput_bits": _aput_bits,
    "_fill": lambda array, width, raw: runtime.array_fill(array, width, raw),
    "_throw": _throw,
    "_jexc": runtime.to_throwable,
}


class VMLoader:
    """a class loader of the vm: dex files it defines classes from, a parent it asks first (or last), and the host classes below everything"""

    def __init__(self, dex_files=(), parent=None, delegate_last=False, name=None):
        self.parent = parent
        self.delegate_last = delegate_last
        self.name = name or "loader"
        self.dex_files = []
        self.classes = {}
        self.missing = set()
        self.defining = []
        self.array_types = {}
        self.lock = threading.RLock()
        self._index = {}
        self._java_object = None
        for dex in dex_files:
            self.add_dex(dex)

    def add_dex(self, dex):
        with self.lock:
            self.dex_files.append(dex)
            for class_def in dex.class_defs():
                self._index.setdefault(dex.type(class_def.type_idx), (dex, class_def))
            self.missing.clear()

    def java_object(self):
        return self._java_object

    def has_own(self, descriptor):
        return descriptor in self._index

    def load_or_none(self, descriptor):
        found = self.classes.get(descriptor)
        if found is not None:
            return found
        if descriptor in self.missing:
            return None
        found = self._load(descriptor)
        if found is None:
            self.missing.add(descriptor)
        return found

    def load(self, descriptor):
        found = self.load_or_none(descriptor)
        if found is None:
            throw_new("java.lang.NoClassDefFoundError", api.binary_name(descriptor))
        return found

    def _load(self, descriptor):
        first = descriptor[0]
        if first == "[":
            return self.array_type(descriptor)
        if len(descriptor) == 1:
            return PRIMITIVES.get(descriptor)
        order = ("host", "own", "parent") if self.delegate_last else ("parent", "host", "own")
        for step in order:
            if step == "parent":
                found = self.parent.load_or_none(descriptor) if self.parent is not None else None
            elif step == "host":
                found = api.lookup_host(api.binary_name(descriptor))
            else:
                found = self._define_own(descriptor)
            if found is not None:
                return found
        return None

    def _define_own(self, descriptor):
        entry = self._index.get(descriptor)
        if entry is None:
            return None
        with self.lock:
            found = self.classes.get(descriptor)
            if found is not None:
                return found
            if descriptor in self.defining:
                throw_new("java.lang.ClassCircularityError", api.binary_name(descriptor))
            self.defining.append(descriptor)
            try:
                dex, class_def = entry
                cls = define_class(self, dex, class_def, self.load)
                self.classes[descriptor] = cls
                return cls
            finally:
                self.defining.pop()

    def array_type(self, descriptor):
        found = self.array_types.get(descriptor)
        if found is not None:
            return found
        element = descriptor[1:]
        if len(element) == 1:
            component = PRIMITIVES.get(element)
            if component is None:
                throw_new("java.lang.NoClassDefFoundError", descriptor)
        elif element[0] == "[":
            component = self.array_type(element)
        else:
            component = self.load(element)
        if isinstance(component, DexClass) or getattr(component, "loader_bound", False):
            found = ArrayType(descriptor, component)
        else:
            found = runtime.array_type_of(descriptor, None)
        self.array_types[descriptor] = found
        return found

    def load_class(self, name):
        """a class by its java name (com.example.Foo) or None"""
        return self.load_or_none("L" + name.replace(".", "/") + ";")

    def load_all(self):
        """define every class of this loader's own dex files; used to find link errors"""
        return [self.load(d) for d in list(self._index)]


class BootLoader(VMLoader):
    """the loader of the host classes only"""

    def __init__(self):
        VMLoader.__init__(self, name="boot")


BOOT = BootLoader()


def class_for_name(name, caller=None, loader=None, initialize=True):
    """Class.forName: initialises a dex class; the loader is the given one or the one of the calling class"""
    if loader is None:
        loader = caller.loader if caller is not None else BOOT
    descriptor = "L" + name.replace(".", "/") + ";" if not name.startswith("[") else name.replace(".", "/")
    jtype = loader.load_or_none(descriptor)
    if jtype is None:
        throw_new("java.lang.ClassNotFoundException", name)
    if isinstance(jtype, DexClass) and initialize:
        jtype.ensure_initialized()
    return jtype
