"""java.lang.reflect: arrays, members of dex and host classes, dynamic proxies, runtime annotations

reflection sees a dex class as its dex file declares it. a host class is seen through its typed methods (@jmethod,
@jstatic) and the public attributes of its python class; a host method known by name only has no parameter types.
access flags are reported, never enforced: setAccessible is accepted and a private member can be invoked"""

import itertools
import threading

from . import api, runtime
from .api import host_class, jmethod, jstatic
from .jlang import Object, Integer, Long, Short, Byte, Character, Boolean, Float, Double, Throwable

PUBLIC, PRIVATE, PROTECTED, STATIC, FINAL, SYNCHRONIZED, VOLATILE, TRANSIENT = 1, 2, 4, 8, 16, 32, 64, 128
NATIVE, INTERFACE, ABSTRACT, STRICT = 256, 512, 1024, 2048
METHOD_MASK = 0xD3F
FIELD_MASK = 0xDF
CONSTRUCTOR_MASK = 0x7


def array_type_for(component):
    """the ArrayType whose component is the given JType"""
    descriptor = "[" + component.descriptor
    loader = getattr(component, "loader", None)
    if loader is not None and getattr(component, "loader_bound", False):
        return loader.array_type(descriptor)
    return runtime.array_type_of(descriptor, None)


def class_array(items):
    array = runtime.new_array("[Ljava/lang/Class;", 0)
    array.extend(items)
    return array


def object_array(items):
    array = runtime.new_array("[Ljava/lang/Object;", 0)
    array.extend(items)
    return array


def _loader_of(jtype):
    from . import classes
    return getattr(jtype, "loader", None) or classes.BOOT


def type_from(owner, descriptor):
    return _loader_of(owner).load(descriptor)


def _varargs(types):
    # jarray(Class)(...) of a plugin is a python list: chaquopy passes it as the Class[] of the varargs
    if len(types) == 1 and (types[0] is None or isinstance(types[0], (runtime.JArray, list, tuple))):
        return [_as_jtype(t) for t in (types[0] or ())]
    return [_as_jtype(t) for t in types]


def _as_jtype(value):
    """a parameter type given by python code may be the Class object of a shim class (python/shim/java/lang): the
    vm class of the same java name is the one the dex signatures name"""
    if value is None or isinstance(value, api.JType):
        return value
    code = getattr(value, "_code", None)
    if code is not None:
        return api.PRIMITIVES[code]
    if isinstance(value, type):
        # find_class answers the python class itself, which stands for the java class of its name
        found = api._by_pytype.get(value)
        if found is None:
            from java import _registry
            name = _registry.name_of(value) or value.__module__ + "." + value.__qualname__.replace(".", "$")
            found = api.lookup_host(name)
        return found if found is not None else api.host_for_pytype(value) or value
    target = getattr(value, "_py", None)
    if target is not None:
        found = api.host_for_pytype(target)
        if found is None:
            found = api.lookup_host(value.getName())
        if found is not None:
            return found
    return value


_BOXES = {"I": Integer, "J": Long, "S": Short, "B": Byte, "C": Character, "Z": Boolean, "F": Float, "D": Double}
_WIDENING = {
    "Z": "Z", "B": "B", "S": "BS", "C": "C", "I": "BSCI", "J": "BSCIJ", "F": "BSCIJF", "D": "BSCIJFD",
}
_CODE_OF_BOX = {Integer: "I", Long: "J", Short: "S", Byte: "B", Character: "C", Boolean: "Z", Float: "F",
                Double: "D"}


def box(value, descriptor):
    """a register value as the java object for its type"""
    code = descriptor[0]
    if code == "V":
        return None
    if code in _BOXES:
        return _BOXES[code].valueOf(value)
    return value


def _java_box(value):
    """python code that calls Method.invoke passes plain values: a bool, an int or a float is the box a parameter of that
    primitive kind takes"""
    cls = value.__class__
    if cls.__module__ == "java.lang":
        # the wrappers of python/shim/java/lang are subclasses of int, float and str that remember their java type
        name = cls.__name__
        if name == "Long":
            return Long.valueOf(int(value))
        if name == "Integer":
            return Integer.valueOf(int(value))
        if name == "Short":
            return Short(int(value))
        if name == "Byte":
            return Byte(int(value))
        if name == "Float":
            return Float(runtime.f32(float(value)))
        if name == "Double":
            return Double(float(value))
        if name == "String":
            return str(value)
    if value.__class__ is bool:
        return Boolean.TRUE if value else Boolean.FALSE
    if value.__class__ is int:
        return Integer.valueOf(value) if -0x80000000 <= value <= 0x7FFFFFFF else Long.valueOf(value)
    if value.__class__ is float:
        return Double(value)
    return value


def unbox(value, descriptor, owner):
    """a java object as the register value a parameter of that descriptor takes, with the widenings of Method.invoke"""
    code = descriptor[0]
    if value.__class__ is float and code == "F":
        return runtime.f32(value)
    value = _java_box(value)
    if code in _WIDENING:
        if value is None:
            runtime.throw_new("java.lang.IllegalArgumentException", "expected a value of type %s, got null" %
                              api.PRIMITIVE_NAMES[code])
        source = _CODE_OF_BOX.get(type(value))
        if source is None or source not in _WIDENING[code]:
            runtime.throw_new("java.lang.IllegalArgumentException", "argument type mismatch")
        number = value.value
        if code == "F":
            return runtime.f32(float(number))
        if code == "D":
            return float(number)
        return number
    if value is not None:
        jtype = type_from(owner, descriptor)
        if not jtype.isInstance(value):
            runtime.throw_new("java.lang.IllegalArgumentException", "argument type mismatch")
    return value


@host_class("java.lang.reflect.Modifier", final=True)
class Modifier(Object):
    PUBLIC, PRIVATE, PROTECTED, STATIC, FINAL = 1, 2, 4, 8, 16
    SYNCHRONIZED, VOLATILE, TRANSIENT, NATIVE, INTERFACE, ABSTRACT, STRICT = 32, 64, 128, 256, 512, 1024, 2048

    @jstatic("isPublic", "(I)Z")
    def isPublic(m):
        return 1 if m & 1 else 0

    @jstatic("isVolatile", "(I)Z")
    def isVolatile(m):
        return 1 if m & 64 else 0

    @jstatic("isPrivate", "(I)Z")
    def isPrivate(m):
        return 1 if m & 2 else 0

    @jstatic("isProtected", "(I)Z")
    def isProtected(m):
        return 1 if m & 4 else 0

    @jstatic("isStatic", "(I)Z")
    def isStatic(m):
        return 1 if m & 8 else 0

    @jstatic("isFinal", "(I)Z")
    def isFinal(m):
        return 1 if m & 16 else 0

    @jstatic("isSynchronized", "(I)Z")
    def isSynchronized(m):
        return 1 if m & 32 else 0

    @jstatic("isAbstract", "(I)Z")
    def isAbstract(m):
        return 1 if m & 1024 else 0

    @jstatic("isInterface", "(I)Z")
    def isInterface(m):
        return 1 if m & 512 else 0

    @jstatic("isNative", "(I)Z")
    def isNative(m):
        return 1 if m & 256 else 0

    @jstatic("toString", "(I)Ljava/lang/String;")
    def toString(m):
        names = ((1, "public"), (4, "protected"), (2, "private"), (1024, "abstract"), (8, "static"), (16, "final"),
                 (128, "transient"), (64, "volatile"), (32, "synchronized"), (256, "native"), (2048, "strictfp"),
                 (512, "interface"))
        return " ".join(name for bit, name in names if m & bit)


@host_class("java.lang.reflect.AnnotatedElement", interface=True)
class AnnotatedElement:
    __slots__ = ()


@host_class("java.lang.reflect.Member", interface=True)
class Member:
    __slots__ = ()


@host_class("java.lang.reflect.AccessibleObject", interfaces=("java.lang.reflect.AnnotatedElement",))
class AccessibleObject(Object):
    _accessible = 0

    @jmethod("setAccessible", "(Z)V")
    def setAccessible(self, flag):
        self._accessible = flag

    @jmethod("isAccessible", "()Z")
    def isAccessible(self):
        return self._accessible

    @jmethod("trySetAccessible", "()Z")
    def trySetAccessible(self):
        self._accessible = 1
        return 1

    def _annotation_source(self):
        return ()

    def getAnnotation(self, annotation_class):
        return annotation_proxy_for(self._annotation_source(), annotation_class, self.getDeclaringClass())

    def getAnnotations(self):
        return annotation_array(self._annotation_source(), self.getDeclaringClass())

    getDeclaredAnnotations = getAnnotations

    def isAnnotationPresent(self, annotation_class):
        return 1 if self.getAnnotation(annotation_class) is not None else 0


@host_class("java.lang.reflect.Executable", interfaces=("java.lang.reflect.Member",))
class Executable(AccessibleObject):
    def __init__(self, declaring, name, params, modifiers, backend, varargs=False):
        self._declaring = declaring
        self._name = name
        self._params = tuple(params)
        self._modifiers = modifiers
        self._backend = backend
        self._varargs = varargs

    def getDeclaringClass(self):
        return self._declaring

    def getName(self):
        return self._name

    def getModifiers(self):
        return self._modifiers

    def getParameterTypes(self):
        return class_array(self._params)

    def getParameterCount(self):
        return len(self._params)

    def getGenericParameterTypes(self):
        return self.getParameterTypes()

    def getExceptionTypes(self):
        return class_array(())

    def isVarArgs(self):
        return 1 if self._varargs else 0

    def isSynthetic(self):
        return 1 if getattr(self._backend, "access", 0) & 0x1000 else 0

    def _annotation_source(self):
        return self._backend.annotations() if self._backend is not None else ()

    def getParameterAnnotations(self):
        return runtime.new_array("[[Ljava/lang/annotation/Annotation;", 0)

    def _convert(self, args):
        args = list(args or ())
        if len(args) != len(self._params):
            runtime.throw_new("java.lang.IllegalArgumentException", "wrong number of arguments; expected %d, got %d" % (
                len(self._params), len(args)))
        return [unbox(a, p.descriptor, self._declaring) for a, p in zip(args, self._params)]

    def _signature(self):
        return "%s(%s)" % (self._name, ",".join(p.getTypeName() for p in self._params))


def _vararg_array(args):
    """the Object[] of a reflective call: a program passes the array, python code passes the arguments themselves"""
    if len(args) == 1 and (args[0] is None or isinstance(args[0], (list, tuple))):
        return args[0]
    return list(args) if args else None


@host_class("java.lang.reflect.Method", final=True)
class Method(Executable):
    def __init__(self, declaring, name, params, return_type, modifiers, backend, varargs=False):
        Executable.__init__(self, declaring, name, params, modifiers, backend, varargs)
        self._return = return_type

    def getReturnType(self):
        return self._return

    def getGenericReturnType(self):
        return self._return

    def isBridge(self):
        return 1 if getattr(self._backend, "access", 0) & 0x40 else 0

    def isDefault(self):
        return 1 if self._declaring.isInterface() and not self._modifiers & (ABSTRACT | STATIC) else 0

    @jmethod("invoke", "(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;")
    def invoke(self, receiver, *args):
        args = _vararg_array(args)
        static = bool(self._modifiers & STATIC)
        if not static:
            if receiver is None:
                runtime.npe("null receiver for " + self._signature())
            if not self._declaring.isInstance(receiver):
                runtime.throw_new("java.lang.IllegalArgumentException", "object is not an instance of declaring class")
        registers = self._convert(args)
        try:
            result = self._backend.call(None if static else receiver, registers)
        except Exception as error:
            failure = runtime.to_throwable(error)
            wrapper = runtime.make_throwable(api.lookup_host("java.lang.reflect.InvocationTargetException").py, None)
            wrapper._cause = failure
            raise wrapper
        return box(result, self._return.descriptor)

    def equals(self, other):
        return 1 if isinstance(other, Method) and other._declaring is self._declaring and other._name == self._name \
            and other._params == self._params and other._return is self._return else 0

    def hashCode(self):
        return Integer.hashCode_int(hash(self._declaring.getName())) ^ hash(self._name) & 0x7FFFFFFF

    def toString(self):
        prefix = Modifier.toString(self._modifiers & METHOD_MASK)
        return "%s%s %s.%s" % (prefix + " " if prefix else "", self._return.getTypeName(),
                               self._declaring.getName(), self._signature())


@host_class("java.lang.reflect.Constructor", final=True)
class Constructor(Executable):
    def getName(self):
        return self._declaring.getName()

    @jmethod("newInstance", "([Ljava/lang/Object;)Ljava/lang/Object;")
    def newInstance(self, *args):
        args = _vararg_array(args)
        declaring = self._declaring
        if declaring.getModifiers() & ABSTRACT or declaring.isInterface():
            runtime.throw_new("java.lang.InstantiationException", declaring.getName())
        registers = self._convert(args)
        try:
            return self._backend.construct(registers)
        except Exception as error:
            failure = runtime.to_throwable(error)
            if isinstance(failure, api.lookup_host("java.lang.Error").py) and not isinstance(
                    failure, api.lookup_host("java.lang.ExceptionInInitializerError").py):
                raise failure
            wrapper = runtime.make_throwable(api.lookup_host("java.lang.reflect.InvocationTargetException").py, None)
            wrapper._cause = failure
            raise wrapper

    def toString(self):
        prefix = Modifier.toString(self._modifiers & CONSTRUCTOR_MASK)
        return "%s%s(%s)" % (prefix + " " if prefix else "", self._declaring.getName(),
                             ",".join(p.getTypeName() for p in self._params))


@host_class("java.lang.reflect.Field", final=True)
class Field(AccessibleObject):
    def __init__(self, declaring, name, type_, modifiers, backend):
        self._declaring = declaring
        self._name = name
        self._type = type_
        self._modifiers = modifiers
        self._backend = backend

    def getDeclaringClass(self):
        return self._declaring

    def getName(self):
        return self._name

    def getType(self):
        return self._type

    def getGenericType(self):
        return self._type

    def getModifiers(self):
        return self._modifiers

    def isEnumConstant(self):
        return 1 if self._modifiers & 0x4000 else 0

    def isSynthetic(self):
        return 1 if self._modifiers & 0x1000 else 0

    def _annotation_source(self):
        return self._backend.annotations() if self._backend is not None else ()

    def _check_receiver(self, receiver):
        if self._modifiers & STATIC:
            return None
        if receiver is None:
            runtime.npe("null receiver for field " + self._name)
        if not self._declaring.isInstance(receiver):
            runtime.throw_new("java.lang.IllegalArgumentException", "field %s.%s is not a field of the object's class" % (
                self._declaring.getName(), self._name))
        return receiver

    @jmethod("get", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def get(self, receiver):
        value = self._backend.get(self._check_receiver(receiver))
        return box(value, self._type.descriptor)

    @jmethod("set", "(Ljava/lang/Object;Ljava/lang/Object;)V")
    def set(self, receiver, value):
        self._backend.put(self._check_receiver(receiver), unbox(value, self._type.descriptor, self._declaring))

    def _primitive(self, receiver, code):
        if self._type.descriptor not in _WIDENING[code]:
            runtime.throw_new("java.lang.IllegalArgumentException", "field type mismatch")
        return self._backend.get(self._check_receiver(receiver))

    @jmethod("getInt", "(Ljava/lang/Object;)I")
    def getInt(self, receiver):
        return self._primitive(receiver, "I")

    @jmethod("getLong", "(Ljava/lang/Object;)J")
    def getLong(self, receiver):
        return self._primitive(receiver, "J")

    @jmethod("getBoolean", "(Ljava/lang/Object;)Z")
    def getBoolean(self, receiver):
        return self._primitive(receiver, "Z")

    @jmethod("getDouble", "(Ljava/lang/Object;)D")
    def getDouble(self, receiver):
        return float(self._primitive(receiver, "D"))

    @jmethod("getFloat", "(Ljava/lang/Object;)F")
    def getFloat(self, receiver):
        return float(self._primitive(receiver, "F"))

    @jmethod("setInt", "(Ljava/lang/Object;I)V")
    @jmethod("setLong", "(Ljava/lang/Object;J)V")
    @jmethod("setBoolean", "(Ljava/lang/Object;Z)V")
    @jmethod("setFloat", "(Ljava/lang/Object;F)V")
    @jmethod("setDouble", "(Ljava/lang/Object;D)V")
    def setPrimitive(self, receiver, value):
        code = self._type.descriptor
        if code in "FD":
            value = float(value)
        self._backend.put(self._check_receiver(receiver), value)

    def equals(self, other):
        return 1 if isinstance(other, Field) and other._declaring is self._declaring and other._name == self._name else 0

    def hashCode(self):
        return hash(self._declaring.getName()) ^ hash(self._name) & 0x7FFFFFFF

    def toString(self):
        prefix = Modifier.toString(self._modifiers & FIELD_MASK)
        return "%s%s %s.%s" % (prefix + " " if prefix else "", self._type.getTypeName(), self._declaring.getName(),
                               self._name)


class DexMethodBackend:
    def __init__(self, method):
        self.method = method
        self.access = method.access

    def annotations(self):
        owner = self.method.owner
        _, _, methods, _ = owner.annotations_directory()
        return methods.get(self.method.index, ())

    def call(self, receiver, registers):
        method = self.method
        if method.static:
            method.owner.ensure_initialized()
            return method.function()(*registers)
        if method.is_virtual():
            return getattr(receiver, method.attr)(*registers)
        return method.function()(receiver, *registers)


class HostMethodBackend:
    access = 0

    def __init__(self, host, name, descriptor, static):
        self.host = host
        self.name = name
        self.descriptor = descriptor
        self.static = static

    def annotations(self):
        return ()

    def call(self, receiver, registers):
        from . import classes
        if self.static:
            function, _ = classes.host_static(self.host, self.name, self.descriptor)
            return function(*registers)
        site = classes.VirtualSite(None, self.host.descriptor, self.name, self.descriptor)
        return site(receiver, *registers)


class DexConstructorBackend:
    def __init__(self, method):
        self.method = method
        self.access = method.access

    def annotations(self):
        owner = self.method.owner
        _, _, methods, _ = owner.annotations_directory()
        return methods.get(self.method.index, ())

    def construct(self, registers):
        owner = self.method.owner
        owner.ensure_initialized()
        obj = owner.pytype.__new__(owner.pytype)
        self.method.function()(obj, *registers)
        return obj


class HostConstructorBackend:
    access = 0

    def __init__(self, host, descriptor):
        self.host = host
        self.descriptor = descriptor

    def annotations(self):
        return ()

    def construct(self, registers):
        from . import classes
        host = self.host
        fresh = classes.Uninitialized(host) if host.value_type else host.py.__new__(host.py)
        return classes.host_constructor(host, self.descriptor)(fresh, *registers)


class DexFieldBackend:
    def __init__(self, owner, name, type_desc, attr, static):
        self.owner = owner
        self.name = name
        self.type_desc = type_desc
        self.attr = attr
        self.static = static

    def annotations(self):
        owner = self.owner
        _, fields, _, _ = owner.annotations_directory()
        for index in range(owner.dexfile.field_count()):
            ref = owner.dexfile.field(index)
            if ref.class_type == owner.descriptor and ref.name == self.name and ref.type == self.type_desc:
                return fields.get(index, ())
        return ()

    def get(self, receiver):
        if self.static:
            self.owner.ensure_initialized()
            return getattr(self.owner.pytype, self.attr)
        return getattr(receiver, self.attr)

    def put(self, receiver, value):
        if self.static:
            self.owner.ensure_initialized()
            setattr(self.owner.pytype, self.attr, value)
        else:
            setattr(receiver, self.attr, value)


class HostFieldBackend:
    def __init__(self, host, name, static):
        self.host = host
        self.name = name
        self.static = static

    def annotations(self):
        return ()

    def get(self, receiver):
        target = self.host.py if self.static else receiver
        return getattr(target, self.name)

    def put(self, receiver, value):
        target = self.host.py if self.static else receiver
        setattr(target, self.name, value)


def _dex_method(owner, method):
    params = [type_from(owner, d) for d in method.params]
    ret = type_from(owner, method.proto.return_type)
    flags = method.access & METHOD_MASK
    if owner.isInterface() and not method.access & (STATIC | ABSTRACT | PRIVATE):
        flags |= PUBLIC
    return Method(owner, method.name, params, ret, flags, DexMethodBackend(method),
                  varargs=bool(method.access & 0x80))


def _host_method(host, name, descriptor, static):
    from . import classes
    params_desc, ret_desc = classes.parse_descriptor(descriptor)
    params = [type_from(host, d) for d in params_desc]
    ret = type_from(host, ret_desc)
    flags = PUBLIC | (STATIC if static else 0)
    return Method(host, name, params, ret, flags, HostMethodBackend(host, name, descriptor, static))


def declared_methods(jtype):
    from . import classes
    found = []
    if isinstance(jtype, classes.DexClass):
        for (name, descriptor), method in list(jtype.direct.items()) + list(jtype.virtual.items()):
            if name not in ("<init>", "<clinit>"):
                found.append(_dex_method(jtype, method))
    elif isinstance(jtype, api.HostClass):
        for (name, descriptor), (value, static) in jtype.typed().items():
            if name != "<init>":
                found.append(_host_method(jtype, name, descriptor, static))
    array = runtime.new_array("[Ljava/lang/reflect/Method;", 0)
    array.extend(found)
    return array


def _chain(jtype):
    """the class, its superclasses and every interface, nearest first"""
    seen = []
    queue = [jtype]
    while queue:
        current = queue.pop(0)
        if current is None or current in seen:
            continue
        seen.append(current)
        queue.append(current.getSuperclass())
        queue.extend(current.getInterfaces())
    return seen


def public_methods(jtype):
    found = {}
    for klass in _chain(jtype):
        for method in declared_methods(klass):
            if method._modifiers & PUBLIC:
                found.setdefault((method._name, method._params), method)
    if jtype.isInterface() is False and not jtype.isPrimitive():
        for method in declared_methods(api.lookup_host("java.lang.Object")):
            found.setdefault((method._name, method._params), method)
    array = runtime.new_array("[Ljava/lang/reflect/Method;", 0)
    array.extend(found.values())
    return array


def find_method(jtype, name, types, declared):
    wanted = tuple(_varargs(types))
    classes_to_search = [jtype] if declared else _chain(jtype) + [api.lookup_host("java.lang.Object")]
    for klass in classes_to_search:
        for method in declared_methods(klass):
            if method._name == name and method._params == wanted and (declared or method._modifiers & PUBLIC):
                return method
    runtime.throw_new("java.lang.NoSuchMethodException", "%s.%s(%s)" % (
        jtype.getName(), name, ", ".join(t.getName() for t in wanted)))


def declared_constructors(jtype, public_only=False):
    from . import classes
    found = []
    if isinstance(jtype, classes.DexClass):
        for (name, descriptor), method in jtype.direct.items():
            if name == "<init>":
                params = [type_from(jtype, d) for d in method.params]
                flags = method.access & CONSTRUCTOR_MASK
                found.append(Constructor(jtype, "<init>", params, flags, DexConstructorBackend(method),
                                         varargs=bool(method.access & 0x80)))
    elif isinstance(jtype, api.HostClass) and not jtype.interface:
        seen = False
        for (name, descriptor), (value, static) in jtype.typed().items():
            if name == "<init>":
                seen = True
                params_desc, _ = classes.parse_descriptor(descriptor)
                found.append(Constructor(jtype, "<init>", [type_from(jtype, d) for d in params_desc], PUBLIC,
                                         HostConstructorBackend(jtype, descriptor)))
        if not seen and not jtype.abstract:
            found.append(Constructor(jtype, "<init>", [], PUBLIC, HostConstructorBackend(jtype, "()V")))
    if public_only:
        found = [c for c in found if c._modifiers & PUBLIC]
    array = runtime.new_array("[Ljava/lang/reflect/Constructor;", 0)
    array.extend(found)
    return array


def find_constructor(jtype, types, declared):
    wanted = tuple(_varargs(types))
    for constructor in declared_constructors(jtype, public_only=not declared):
        if constructor._params == wanted:
            return constructor
    runtime.throw_new("java.lang.NoSuchMethodException", "%s.<init>(%s)" % (
        jtype.getName(), ", ".join(t.getName() for t in wanted)))


def declared_fields(jtype):
    from . import classes
    found = []
    if isinstance(jtype, classes.DexClass):
        for name, type_desc, access, static, attr in jtype.field_defs:
            found.append(Field(jtype, name, type_from(jtype, type_desc), access & 0xDF | (access & 0x4000) | (access & 0x1000),
                               DexFieldBackend(jtype, name, type_desc, attr, static)))
    elif isinstance(jtype, api.HostClass):
        for name, value in vars(jtype.py).items():
            if name.startswith("_") or callable(value) or isinstance(value, (staticmethod, classmethod, property)):
                continue
            kind = ("Z" if isinstance(value, bool) else "D" if isinstance(value, float) else "I"
                    if isinstance(value, int) else "Ljava/lang/String;" if isinstance(value, str)
                    else "Ljava/lang/Object;")
            found.append(Field(jtype, name, type_from(jtype, kind), PUBLIC | STATIC | FINAL,
                               HostFieldBackend(jtype, name, True)))
    array = runtime.new_array("[Ljava/lang/reflect/Field;", 0)
    array.extend(found)
    return array


def public_fields(jtype):
    found = {}
    for klass in _chain(jtype):
        for field in declared_fields(klass):
            if field._modifiers & PUBLIC:
                found.setdefault(field._name, field)
    array = runtime.new_array("[Ljava/lang/reflect/Field;", 0)
    array.extend(found.values())
    return array


def find_field(jtype, name, declared):
    for klass in [jtype] if declared else _chain(jtype):
        for field in declared_fields(klass):
            if field._name == name and (declared or field._modifiers & PUBLIC):
                return field
    if isinstance(jtype, api.HostClass) and not name.startswith("_"):
        # a constant a shim computes when it is read (BuildVars.BUILD_VERSION_STRING is a property of the metaclass) is not in
        # the class dict, but it is a static field to a program that asks for it by name
        value = getattr(jtype.py, name, _NO_FIELD)
        if value is not _NO_FIELD and not callable(value):
            kind = ("Z" if isinstance(value, bool) else "D" if isinstance(value, float) else "I" if isinstance(value, int)
                    else "Ljava/lang/String;" if isinstance(value, str) else "Ljava/lang/Object;")
            return Field(jtype, name, type_from(jtype, kind), PUBLIC | STATIC | FINAL, HostFieldBackend(jtype, name, True))
    runtime.throw_new("java.lang.NoSuchFieldException", name)


_NO_FIELD = object()


def _runtime_annotations(source):
    from .format import VISIBILITY_RUNTIME
    return [a for a in source if a.visibility == VISIBILITY_RUNTIME]


def annotation_array(source, context):
    array = runtime.new_array("[Ljava/lang/annotation/Annotation;", 0)
    for annotation in _runtime_annotations(source):
        proxy = make_annotation(annotation, context)
        if proxy is not None:
            array.append(proxy)
    return array


def annotation_proxy_for(source, annotation_class, context):
    if annotation_class is None:
        runtime.npe()
    for annotation in _runtime_annotations(source):
        if annotation.type == annotation_class.descriptor:
            return make_annotation(annotation, context)
    return None


def annotation_of(jtype, annotation_class):
    return annotation_proxy_for(_class_annotations(jtype), annotation_class, jtype)


def annotations_of(jtype):
    return annotation_array(_class_annotations(jtype), jtype)


def _class_annotations(jtype):
    from . import classes
    if isinstance(jtype, classes.DexClass):
        return jtype.annotations_directory()[0]
    return ()


def _element_value(value, return_type, context):
    from . import classes
    from .format import (VALUE_ANNOTATION, VALUE_ARRAY, VALUE_BOOLEAN, VALUE_ENUM, VALUE_NULL, VALUE_STRING,
                         VALUE_TYPE, VALUE_FIELD, VALUE_METHOD)
    kind, payload = value
    dex = context.dexfile
    loader = context.loader
    if kind == VALUE_STRING:
        return dex.string(payload)
    if kind == VALUE_TYPE:
        return loader.load(dex.type(payload))
    if kind == VALUE_ENUM:
        ref = dex.field(payload)
        owner = loader.load(ref.class_type)
        owner.ensure_initialized()
        return getattr(owner.pytype, api.field_attr(ref.class_type, ref.name, True))
    if kind == VALUE_ARRAY:
        component = return_type.getComponentType()
        items = [_element_value(v, component, context) for v in payload]
        array = runtime.new_array(return_type, len(items))
        for index, item in enumerate(items):
            array[index] = item
        return array
    if kind == VALUE_ANNOTATION:
        return make_annotation(payload, context)
    if kind == VALUE_NULL:
        return None
    if kind == VALUE_BOOLEAN:
        return 1 if payload else 0
    return payload


def make_annotation(annotation, context):
    """a proxy object that implements the annotation interface with the values the dex file records and the defaults of the annotation class"""
    loader = context.loader
    jtype = loader.load_or_none(annotation.type)
    if jtype is None:
        return None
    values = {}
    for name, value in annotation.elements:
        values[name] = value
    return AnnotationProxy.create(jtype, values, context)


@host_class("java.lang.annotation.Annotation", interface=True)
class Annotation:
    __slots__ = ()


@host_class("java.lang.reflect.InvocationHandler", interface=True)
class InvocationHandler:
    __slots__ = ()


_proxy_counter = itertools.count()
_proxy_classes = {}
_proxy_lock = threading.Lock()


class ProxyType(api.JType):
    loader_bound = False

    def __init__(self, descriptor, interfaces, pytype):
        self.descriptor = descriptor
        self.interfaces = interfaces
        self.pytype = pytype
        self.supers = frozenset()

    def getSuperclass(self):
        return api.lookup_host("java.lang.reflect.Proxy")

    def getInterfaces(self):
        return class_array(self.interfaces)

    def getModifiers(self):
        return 0x11

    def isInstance(self, value):
        return 1 if value is not None and isinstance(value, self.pytype) else 0

    def isAssignableFrom(self, other):
        return 1 if other is self else 0

    def getClassLoader(self):
        return None


def _interface_method(interfaces, name, descriptor):
    for interface in interfaces:
        for klass in _chain(interface):
            for method in declared_methods(klass):
                if method._name == name and method._descriptor_of() == descriptor:
                    return method
    obj = api.lookup_host("java.lang.Object")
    for method in declared_methods(obj):
        if method._name == name and method._descriptor_of() == descriptor:
            return method
    return None


def _method_descriptor(self):
    return "(" + "".join(p.descriptor for p in self._params) + ")" + self._return.descriptor


Method._descriptor_of = _method_descriptor


_FINAL_OBJECT_METHODS = ("getClass", "notify", "notifyAll", "wait")


class ProxyMeta(type):
    """a class attribute lookup of a mangled method name answers with the function that calls the handler"""

    def __getattr__(cls, attr):
        key = api.method_of_attr(attr)
        if key is not None and "_jproxy" in cls.__dict__:
            if key[0] in _FINAL_OBJECT_METHODS:
                from . import classes
                return classes.host_virtual(api.lookup_host("java.lang.Object"), key[0], key[1])
            return cls._jproxy_function(key[0], key[1])
        raise AttributeError(attr)


class ProxyBase(Object):
    _handler = None

    # the three methods of Object a proxy forwards to its handler; Object itself defines them, so they need explicit overrides
    def toString(self):
        return type(self)._jproxy_function("toString", "()Ljava/lang/String;")(self)

    def hashCode(self):
        return type(self)._jproxy_function("hashCode", "()I")(self)

    def equals(self, other):
        return type(self)._jproxy_function("equals", "(Ljava/lang/Object;)Z")(self, other)

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        cls = type(self)
        if name in ("getClass", "notify", "notifyAll", "wait"):
            return getattr(super(), name)
        candidates = [m for m in _all_interface_methods(cls._jinterfaces) if m._name == name]
        if not candidates:
            raise AttributeError(name)
        method = candidates[0]
        function = cls._jproxy_function(name, method._descriptor_of())
        return lambda *args: function(self, *args)


def _all_interface_methods(interfaces):
    methods = []
    for interface in interfaces:
        for klass in _chain(interface):
            methods.extend(declared_methods(klass))
    methods.extend(declared_methods(api.lookup_host("java.lang.Object")))
    return methods


def _proxy_class(interfaces):
    key = tuple(i.descriptor for i in interfaces)
    with _proxy_lock:
        found = _proxy_classes.get(key)
        if found is not None:
            return found
        number = next(_proxy_counter)
        descriptor = "Lcom/sun/proxy/$Proxy%d;" % number
        supers = {descriptor, "Ljava/lang/reflect/Proxy;"}
        from . import classes
        for interface in interfaces:
            supers |= classes.host_all_supers(interface) if isinstance(interface, api.HostClass) else interface.supers

        def proxy_function(cls, name, method_descriptor):
            def call(self, *registers):
                method = _interface_method(cls._jinterfaces, name, method_descriptor)
                if method is None:
                    runtime.throw_new("java.lang.AbstractMethodError", name + method_descriptor)
                args = object_array([box(r, p.descriptor) for r, p in zip(registers, method._params)] if registers else [])
                handler = self._handler
                try:
                    result = handler.invoke(self, method, args if registers else None)
                except Exception as error:
                    failure = runtime.to_throwable(error)
                    allowed = isinstance(failure, (api.lookup_host("java.lang.RuntimeException").py,
                                                   api.lookup_host("java.lang.Error").py))
                    if not allowed:
                        wrapper = runtime.make_throwable(
                            api.lookup_host("java.lang.reflect.UndeclaredThrowableException").py, None)
                        wrapper._cause = failure
                        raise wrapper
                    raise failure
                return_type = method._return
                if return_type.descriptor == "V":
                    return None
                if return_type.isPrimitive():
                    if result is None:
                        runtime.npe("proxy handler returned null for " + return_type.getName())
                    return unbox(result, return_type.descriptor, return_type)
                if result is not None and not return_type.isInstance(result):
                    runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                        runtime.type_name_of(result), return_type.getName()))
                return result
            return call

        namespace = {"__module__": "dexvm.proxy", "_jproxy": True, "_jinterfaces": tuple(interfaces),
                     "_jsupers": frozenset(supers)}
        py = ProxyMeta("$Proxy%d" % number, (ProxyBase,), namespace)
        py._jproxy_function = classmethod(proxy_function)
        jtype = ProxyType(descriptor, tuple(interfaces), py)
        jtype.supers = frozenset(supers)
        py._jclass = jtype
        _proxy_classes[key] = py
        return py


@host_class("java.lang.reflect.Proxy")
class Proxy(Object):
    @jstatic("newProxyInstance", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;")
    def newProxyInstance(loader, interfaces, handler):
        if handler is None:
            runtime.npe()
        items = list(interfaces)
        for interface in items:
            if not interface.isInterface():
                runtime.throw_new("java.lang.IllegalArgumentException", interface.getName() + " is not an interface")
        py = _proxy_class(items)
        proxy = py.__new__(py)
        proxy._handler = handler
        return proxy

    @jstatic("isProxyClass", "(Ljava/lang/Class;)Z")
    def isProxyClass(jtype):
        return 1 if isinstance(jtype, ProxyType) else 0

    @jstatic("getInvocationHandler", "(Ljava/lang/Object;)Ljava/lang/reflect/InvocationHandler;")
    def getInvocationHandler(proxy):
        if not isinstance(proxy, ProxyBase):
            runtime.throw_new("java.lang.IllegalArgumentException", "not a proxy instance")
        return proxy._handler


class AnnotationProxy(ProxyBase):
    """the object a reflective annotation lookup returns: element methods answer from the recorded values"""

    @staticmethod
    def create(jtype, values, context):
        py = _annotation_class(jtype)
        obj = py.__new__(py)
        obj._values = values
        obj._context = context
        obj._type = jtype
        obj._cache = {}
        return obj


def _annotation_defaults(jtype):
    from . import classes
    from .format import VALUE_ANNOTATION
    if not isinstance(jtype, classes.DexClass):
        return {}
    for annotation in jtype.annotations_directory()[0]:
        if annotation.type == "Ldalvik/annotation/AnnotationDefault;":
            for name, value in annotation.elements:
                if name == "value" and value[0] == VALUE_ANNOTATION:
                    return dict(value[1].elements)
    return {}


def _annotation_class(jtype):
    key = ("annotation", jtype.descriptor, id(jtype))
    with _proxy_lock:
        found = _proxy_classes.get(key)
        if found is not None:
            return found
        methods = {m._name: m for m in declared_methods(jtype) if not m._params}

        def element(self, name):
            if name in self._cache:
                return self._cache[name]
            method = methods[name]
            raw = self._values.get(name)
            if raw is None:
                raw = _annotation_defaults(jtype).get(name)
            if raw is None:
                runtime.throw_new("java.lang.annotation.IncompleteAnnotationException", name)
            result = _element_value(raw, method._return, self._context)
            self._cache[name] = result
            return result

        def getattr_(self, name):
            if name == "annotationType":
                return lambda: jtype
            if name == "toString":
                return lambda: "@%s(%s)" % (jtype.getName(), ", ".join(
                    "%s=%s" % (k, _text(self._element(k))) for k in methods))
            if name == "hashCode":
                return lambda: id(self) >> 4 & 0x7FFFFFFF
            if name == "equals":
                return lambda other: 1 if other is self else 0
            if name in methods:
                return lambda: self._element(name)
            if name.startswith("_"):
                raise AttributeError(name)
            return ProxyBase.__getattr__(self, name)

        def jm(cls, name, descriptor):
            if name in methods and descriptor.startswith("()"):
                return lambda self: self._element(name)
            return lambda self, *args: getattr_(self, name)(*args)

        supers = {jtype.descriptor, "Ljava/lang/annotation/Annotation;"}
        namespace = {"__module__": "dexvm.proxy", "_jproxy": True, "_jinterfaces": (jtype,),
                     "_jsupers": frozenset(supers), "_element": element, "__getattr__": getattr_}
        py = ProxyMeta("$Proxy$" + jtype.getSimpleName(), (AnnotationProxy,), namespace)
        py._jproxy_function = classmethod(jm)
        py._jclass = ProxyType("Lcom/sun/proxy/$Proxy$%s;" % jtype.getSimpleName(), (jtype,), py)
        py._jclass.supers = frozenset(supers)
        _proxy_classes[key] = py
        return py


def _text(value):
    if isinstance(value, str):
        return '"%s"' % value
    if isinstance(value, runtime.JArray):
        return "[" + ", ".join(_text(v) for v in value) + "]"
    return value.toString() if hasattr(value, "toString") else str(value)


def _attach_exception_accessors():
    ite = api.lookup_host("java.lang.reflect.InvocationTargetException").py
    ite.getTargetException = lambda self: self._cause
    ute = api.lookup_host("java.lang.reflect.UndeclaredThrowableException").py
    ute.getUndeclaredThrowable = lambda self: self._cause


_attach_exception_accessors()


@host_class("java.lang.reflect.Array", final=True)
class Array(Object):
    @jstatic("newInstance", "(Ljava/lang/Class;I)Ljava/lang/Object;")
    def newInstance(component, length):
        if component is None:
            runtime.npe()
        if component.descriptor == "V":
            runtime.throw_new("java.lang.IllegalArgumentException", "void component")
        return runtime.new_array(array_type_for(component), length)

    @jstatic("newInstance", "(Ljava/lang/Class;[I)Ljava/lang/Object;")
    def newInstanceMulti(component, dims):
        if component is None or dims is None:
            runtime.npe()
        if len(dims) == 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Empty dimensions array")
        kind = component
        for _ in dims:
            kind = array_type_for(kind)
        return runtime.new_multi_array(kind, list(dims))

    @jstatic("getLength", "(Ljava/lang/Object;)I")
    def getLength(array):
        if array is None:
            runtime.npe()
        if not isinstance(array, runtime.JArray):
            runtime.throw_new("java.lang.IllegalArgumentException", "Argument is not an array")
        return len(array)

    @jstatic("get", "(Ljava/lang/Object;I)Ljava/lang/Object;")
    def get(array, index):
        Array._check(array, index)
        return box(array[index], array.jtype.descriptor[1:])

    @jstatic("set", "(Ljava/lang/Object;ILjava/lang/Object;)V")
    def set(array, index, value):
        Array._check(array, index)
        code = array.jtype.descriptor[1]
        if code in "ZBSCIJFD":
            array[index] = unbox(value, code, array.jtype)
        else:
            runtime.array_store_check(array, value)
            array[index] = value

    @staticmethod
    def _check(array, index):
        if array is None:
            runtime.npe()
        if not isinstance(array, runtime.JArray):
            runtime.throw_new("java.lang.IllegalArgumentException", "Argument is not an array")
        if not 0 <= index < len(array):
            runtime.aioobe(array, index)

    @jstatic("getInt", "(Ljava/lang/Object;I)I")
    @jstatic("getLong", "(Ljava/lang/Object;I)J")
    @jstatic("getDouble", "(Ljava/lang/Object;I)D")
    @jstatic("getFloat", "(Ljava/lang/Object;I)F")
    @jstatic("getByte", "(Ljava/lang/Object;I)B")
    @jstatic("getChar", "(Ljava/lang/Object;I)C")
    @jstatic("getShort", "(Ljava/lang/Object;I)S")
    @jstatic("getBoolean", "(Ljava/lang/Object;I)Z")
    def getPrimitive(array, index):
        Array._check(array, index)
        return array[index]

    @jstatic("setInt", "(Ljava/lang/Object;II)V")
    @jstatic("setLong", "(Ljava/lang/Object;IJ)V")
    @jstatic("setDouble", "(Ljava/lang/Object;ID)V")
    @jstatic("setFloat", "(Ljava/lang/Object;IF)V")
    @jstatic("setByte", "(Ljava/lang/Object;IB)V")
    @jstatic("setChar", "(Ljava/lang/Object;IC)V")
    @jstatic("setShort", "(Ljava/lang/Object;IS)V")
    @jstatic("setBoolean", "(Ljava/lang/Object;IZ)V")
    def setPrimitive(array, index, value):
        Array._check(array, index)
        array[index] = value
