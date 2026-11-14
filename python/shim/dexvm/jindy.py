"""invoke-custom and the rest of java.lang.invoke a program needs to link a call site

a call site names a bootstrap method. LambdaMetafactory and StringConcatFactory are linked here without running any
java code; any other bootstrap is a method of the dex file (or a host method) that is called with a Lookup, the name
and the method type and answers a CallSite, as on a device. a site is linked once, on its first execution

a lambda is an instance of a class made for the call site (LambdaClass): it implements the interface the site names,
holds the captured values and forwards the one abstract method to the implementation handle, converting each value
between the types the interface erases to and the types the implementation takes (boxing, unboxing, widening, casts)"""

import itertools
import threading

from . import api, classes, runtime
from .api import caller_sensitive, host_class, jmethod, jstatic
from .classes import DexClass, DexMixin, INITIALIZED, from_register, parse_descriptor, to_register
from .format import (ACC_FINAL, ACC_SYNTHETIC, VALUE_BOOLEAN, VALUE_BYTE, VALUE_CHAR, VALUE_DOUBLE, VALUE_FLOAT,
                     VALUE_INT, VALUE_LONG, VALUE_METHOD_HANDLE, VALUE_METHOD_TYPE, VALUE_NULL, VALUE_SHORT,
                     VALUE_STRING, VALUE_TYPE)
from .jinvoke import MethodHandle, MethodType, adapt_primitive, invoke_handle
from .jlang import Object, float_to_string
from .jreflect import _CODE_OF_BOX, _WIDENING, box
from .runtime import throw_new

FLAG_SERIALIZABLE, FLAG_MARKERS, FLAG_BRIDGES = 1, 2, 4

_BOX_CODE = {"Ljava/lang/Integer;": "I", "Ljava/lang/Long;": "J", "Ljava/lang/Short;": "S", "Ljava/lang/Byte;": "B",
             "Ljava/lang/Character;": "C", "Ljava/lang/Boolean;": "Z", "Ljava/lang/Float;": "F",
             "Ljava/lang/Double;": "D"}
_OBJECT = "Ljava/lang/Object;"
_PRIMITIVE_VALUES = {VALUE_BOOLEAN: "Z", VALUE_BYTE: "B", VALUE_CHAR: "C", VALUE_SHORT: "S", VALUE_INT: "I",
                     VALUE_LONG: "J", VALUE_FLOAT: "F", VALUE_DOUBLE: "D"}


def converter(loader, source, target):
    """fn(value) that turns a register value of the source type into one of the target type the way a method handle
    adaptation does, or None when the value passes unchanged"""
    if source == target:
        return None
    if len(source) == 1 and len(target) == 1:
        if source == "V" or target == "V":
            throw_new("java.lang.invoke.LambdaConversionException", "cannot convert %s to %s" % (source, target))
        if target not in _widen_to(source):
            throw_new("java.lang.invoke.LambdaConversionException", "cannot convert %s to %s" % (source, target))
        return lambda value: adapt_primitive(value, source, target)
    if len(source) == 1:
        if source == "V":
            throw_new("java.lang.invoke.LambdaConversionException", "cannot convert void to %s" % target)
        code = _BOX_CODE.get(target, source)
        if source not in _WIDENING[code]:
            throw_new("java.lang.invoke.LambdaConversionException", "cannot convert %s to %s" % (source, target))
        return lambda value: box(adapt_primitive(value, source, code), code)
    if len(target) == 1:
        if target == "V":
            return None

        def unbox(value):
            if value is None:
                runtime.npe()
            code = _CODE_OF_BOX.get(type(value))
            if code is None or code not in _WIDENING[target]:
                throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                    runtime.type_name_of(value), api.PRIMITIVE_NAMES[target]))
            return adapt_primitive(value.value, code, target)
        return unbox
    if target == _OBJECT:
        return None
    jtype = loader.load(target)
    return lambda value: runtime.check_cast(value, jtype)


def _widen_to(source):
    return {"B": "BSIJFD", "S": "SIJFD", "C": "CIJFD", "I": "IJFD", "J": "JFD", "F": "FD", "D": "D", "Z": "Z"}.get(
        source, "")


def _static_value(owner, item):
    """a bootstrap argument as the object a bootstrap method receives, with its primitive code for the ones that are primitive"""
    kind, payload = item
    dexfile = owner.dexfile
    if kind == VALUE_NULL:
        return None, None
    if kind in _PRIMITIVE_VALUES:
        return payload, _PRIMITIVE_VALUES[kind]
    if kind == VALUE_STRING:
        return dexfile.string(payload), None
    if kind == VALUE_TYPE:
        return owner.loader.load(dexfile.type(payload)), None
    if kind == VALUE_METHOD_TYPE:
        return classes._bind_method_type_const(owner, payload)[0](), None
    if kind == VALUE_METHOD_HANDLE:
        return classes._bind_handle_const(owner, payload)[0](), None
    throw_new("java.lang.BootstrapMethodError", "bootstrap argument of kind 0x%02x is not supported" % kind)


def _as_object(value, code):
    return box(value, code) if code is not None else value


_serial = itertools.count(1)


class LambdaClass(DexClass):
    """the class of the lambdas of one call site"""

    def __init__(self, owner, interfaces):
        self.loader = owner.loader
        self.dexfile = owner.dexfile
        self.class_def = None
        self.descriptor = "%s$$Lambda$%d;" % (owner.descriptor[:-1], next(_serial))
        self.access = ACC_FINAL | ACC_SYNTHETIC
        self.state = INITIALIZED
        self.init_lock = threading.RLock()
        self.init_thread = None
        self.init_error = None
        self.superclass = api.lookup_host("java.lang.Object")
        self.interfaces = tuple(interfaces)
        self.direct = {}
        self.virtual = {}
        self.instance_attrs = {}
        self.static_attrs = {}
        self.field_defs = []
        self.env = owner.env
        self._annotations = None
        supers = {self.descriptor} | classes.host_all_supers(self.superclass)
        for interface in self.interfaces:
            supers |= interface.supers if isinstance(interface, DexClass) else classes.host_all_supers(interface)
        self.supers = frozenset(supers)
        namespace = {"__module__": "dexvm.generated", "_jsupers": self.supers, "_cap": ()}
        self.pytype = type(api.escape(self.descriptor), (Object, DexMixin), namespace)
        self.pytype._jclass = self
        self.globals = {}

    def annotations_directory(self):
        return [], {}, {}, {}

    def getModifiers(self):
        return self.access

    def isAnonymousClass(self):
        return False

    def getEnclosingClass(self):
        return None


def link_lambda(owner, name, invoked, sam, impl, instantiated, markers=(), bridges=()):
    """the factory of a metafactory call site: fn(*captured) answers an instance of the interface the site names"""
    loader = owner.loader
    interface = loader.load(invoked._return_type.descriptor)
    if not interface.isInterface():
        throw_new("java.lang.invoke.LambdaConversionException", "%s is not an interface" % interface.getName())
    cls = LambdaClass(owner, (interface,) + tuple(markers))
    target = impl._target
    impl_params = [p.descriptor for p in impl._type._parameters]
    impl_return = impl._type._return_type.descriptor
    captured = [p.descriptor for p in invoked._parameters]
    if len(captured) > len(impl_params):
        throw_new("java.lang.invoke.LambdaConversionException", "more captured values than the implementation takes")
    capture_conversions = [converter(loader, src, dst) for src, dst in zip(captured, impl_params)]
    first = len(captured)

    def forwarder(descriptor):
        sam_params, sam_return = parse_descriptor(descriptor)
        if first + len(sam_params) != len(impl_params):
            throw_new("java.lang.invoke.LambdaConversionException",
                      "%s takes %d values, the implementation takes %d" % (name, first + len(sam_params), len(impl_params)))
        conversions = tuple(converter(loader, src, dst) for src, dst in zip(sam_params, impl_params[first:]))
        if sam_return == "V":
            result_conversion = None
        elif impl_return == "V":
            throw_new("java.lang.invoke.LambdaConversionException", "the implementation returns void")
        else:
            # an int result of an Integer->Long lambda is widened before it is boxed, as the instantiated type says
            boxed = instantiated._return_type.descriptor
            if len(impl_return) == 1 and len(sam_return) > 1 and boxed in _BOX_CODE:
                result_conversion = converter(loader, impl_return, boxed)
            else:
                result_conversion = converter(loader, impl_return, sam_return)
        pairs = tuple(enumerate(conversions))

        def call(self, *args):
            values = list(self._cap)
            for index, convert in pairs:
                value = args[index]
                values.append(value if convert is None else convert(value))
            result = target(*values)
            if sam_return == "V":
                return None
            return result if result_conversion is None else result_conversion(result)
        call.__qualname__ = "%s.%s" % (cls.descriptor, name)
        return call

    descriptors = [sam.toMethodDescriptorString()] + [b.toMethodDescriptorString() for b in bridges]
    for descriptor in dict.fromkeys(descriptors):
        setattr(cls.pytype, api.method_attr(name, descriptor), forwarder(descriptor))
    sam_params, sam_return = parse_descriptor(descriptors[0])
    if name.isidentifier() and not name.startswith("__"):
        def plain(self, *args):
            if len(args) != len(sam_params):
                raise TypeError("%s takes %d arguments, %d given" % (name, len(sam_params), len(args)))
            converted = tuple(to_register(a, d) for a, d in zip(args, sam_params))
            result = getattr(self, api.method_attr(name, descriptors[0]))(*converted)
            return None if sam_return == "V" else from_register(result, sam_return)
        plain.__name__ = name
        setattr(cls.pytype, name, plain)
    classes._install_defaults(cls)
    pytype = cls.pytype

    def make(*values):
        instance = pytype.__new__(pytype)
        instance._cap = tuple(v if c is None else c(v) for v, c in zip(values, capture_conversions))
        return instance
    if not captured:
        singleton = make()
        return lambda: singleton
    return make


def _stringifier(descriptor):
    code = descriptor[0]
    if code == "Z":
        return lambda value: "true" if value else "false"
    if code == "C":
        return chr
    if code in "BSIJ":
        return str
    if code == "F":
        return lambda value: float_to_string(value, True)
    if code == "D":
        return lambda value: float_to_string(value, False)
    return lambda value: "null" if value is None else (value if isinstance(value, str) else value.toString())


def link_concat(call_proto, recipe, constants):
    """fn(*values) -> str for makeConcatWithConstants (a recipe) and makeConcat (the values in a row)"""
    params = call_proto.parameters
    texts = [_stringifier(d) for d in params]
    steps = []
    argument = constant = 0
    literal = []
    for char in recipe:
        if char in "\x01\x02":
            if literal:
                steps.append((None, "".join(literal)))
                literal = []
            if char == "\x01":
                if argument >= len(params):
                    throw_new("java.lang.invoke.StringConcatException", "the recipe takes more values than the site gives")
                steps.append((argument, None))
                argument += 1
            else:
                if constant >= len(constants):
                    throw_new("java.lang.invoke.StringConcatException", "the recipe names more constants than it has")
                steps.append((None, constants[constant]))
                constant += 1
        else:
            literal.append(char)
    if literal:
        steps.append((None, "".join(literal)))
    if argument != len(params):
        throw_new("java.lang.invoke.StringConcatException", "the recipe leaves values of the site unused")

    def concat(*values):
        return "".join(text if index is None else texts[index](values[index]) for index, text in steps)
    return concat


def _constant_text(owner, item):
    value, code = _static_value(owner, item)
    if code is not None:
        return _stringifier(code)(value)
    return "null" if value is None else (value if isinstance(value, str) else value.toString())


def bind_custom(owner, index):
    """(fn, True) for the invoke-custom instruction that names call site index of the dex file of owner"""
    dexfile = owner.dexfile
    values = dexfile.call_site(index)
    if len(values) < 3 or values[0][0] != VALUE_METHOD_HANDLE or values[1][0] != VALUE_STRING or \
            values[2][0] != VALUE_METHOD_TYPE:
        throw_new("java.lang.BootstrapMethodError", "call site %d does not start with a bootstrap method, a name and a type" % index)
    bootstrap = dexfile.method(dexfile.method_handle(values[0][1]).target_idx)
    name = dexfile.string(values[1][1])
    call_proto = dexfile.proto(values[2][1])
    extras = values[3:]
    if bootstrap.class_type == "Ljava/lang/invoke/LambdaMetafactory;":
        return _lambda_site(owner, bootstrap.name, name, call_proto, extras), True
    if bootstrap.class_type == "Ljava/lang/invoke/StringConcatFactory;":
        return _concat_site(owner, bootstrap.name, call_proto, extras), True
    return _generic_site(owner, values[0][1], name, values[2][1], call_proto, extras), True


def _lambda_site(owner, factory, name, call_proto, extras):
    method_type = lambda item: _static_value(owner, item)[0]
    if factory == "metafactory":
        if len(extras) != 3:
            throw_new("java.lang.BootstrapMethodError", "metafactory takes three static arguments")
        sam, impl, instantiated = (method_type(item) for item in extras)
        markers = bridges = ()
    elif factory == "altMetafactory":
        if len(extras) < 4:
            throw_new("java.lang.BootstrapMethodError", "altMetafactory takes a flags argument")
        sam, impl, instantiated = (method_type(item) for item in extras[:3])
        flags = extras[3][1]
        position = 4
        markers, bridges = [], []
        if flags & FLAG_MARKERS:
            count = extras[position][1]
            markers = [method_type(item) for item in extras[position + 1:position + 1 + count]]
            position += 1 + count
        if flags & FLAG_BRIDGES:
            count = extras[position][1]
            bridges = [method_type(item) for item in extras[position + 1:position + 1 + count]]
    else:
        throw_new("java.lang.BootstrapMethodError", "LambdaMetafactory.%s is not implemented" % factory)
    invoked = MethodType(owner.loader.load(call_proto.return_type),
                         [owner.loader.load(d) for d in call_proto.parameters])
    return link_lambda(owner, name, invoked, sam, impl, instantiated, markers, bridges)


def _concat_site(owner, factory, call_proto, extras):
    if factory == "makeConcatWithConstants":
        if not extras or extras[0][0] != VALUE_STRING:
            throw_new("java.lang.BootstrapMethodError", "makeConcatWithConstants takes a recipe")
        recipe = owner.dexfile.string(extras[0][1])
        constants = [_constant_text(owner, item) for item in extras[1:]]
    elif factory == "makeConcat":
        recipe, constants = "\x01" * len(call_proto.parameters), []
    else:
        throw_new("java.lang.BootstrapMethodError", "StringConcatFactory.%s is not implemented" % factory)
    return link_concat(call_proto, recipe, constants)


def _generic_site(owner, handle_index, name, proto_index, call_proto, extras):
    """a bootstrap method of the program: called on the first execution with (Lookup, name, MethodType, static arguments...)"""
    bootstrap = classes._bind_handle_const(owner, handle_index)[0]()
    call_type = classes._bind_method_type_const(owner, proto_index)[0]()
    descriptor = call_proto.descriptor()
    arguments = [Lookup(owner), name, call_type]
    declared = [p.descriptor for p in bootstrap._type._parameters]
    rest = [_static_value(owner, item) for item in extras]
    if len(declared) < 3:
        throw_new("java.lang.BootstrapMethodError", "bootstrap method takes fewer than three arguments")
    varargs = len(declared) > 3 and declared[-1].startswith("[")
    fixed = len(declared) - 4 if varargs else len(declared) - 3
    if len(rest) < fixed or (not varargs and len(rest) != fixed):
        throw_new("java.lang.BootstrapMethodError",
                  "bootstrap method takes %d static arguments, the site gives %d" % (fixed, len(rest)))
    for (value, code), wanted in zip(rest[:fixed], declared[3:3 + fixed]):
        arguments.append(value if len(wanted) == 1 else _as_object(value, code))
    if varargs:
        tail = rest[fixed:]
        array = runtime.new_array(declared[-1], len(tail))
        for position, (value, code) in enumerate(tail):
            array[position] = _as_object(value, code)
        arguments.append(array)
    try:
        site = bootstrap._target(*arguments)
    except BaseException as error:
        failure = runtime.to_throwable(error)
        if isinstance(failure, api.lookup_host("java.lang.Error").py):
            raise failure
        wrapped = runtime.make_throwable(api.lookup_host("java.lang.BootstrapMethodError").py, "bootstrap method failed")
        wrapped._cause = failure
        raise wrapped
    if not isinstance(site, CallSite):
        throw_new("java.lang.BootstrapMethodError", "bootstrap method returned something that is not a CallSite")
    if not site.type().equals(call_type):
        throw_new("java.lang.invoke.WrongMethodTypeException", "call site type %s, expected %s" % (
            site.type().toMethodDescriptorString(), descriptor))

    def call(*args):
        return invoke_handle(site.getTarget(), call_type, descriptor, False, args)
    return call


@host_class("java.lang.invoke.CallSite", abstract=True)
class CallSite(Object):
    def __init__(self, target_or_type=None):
        if isinstance(target_or_type, MethodHandle):
            self._call_type = target_or_type._type
            self._handle = target_or_type
        else:
            self._call_type = target_or_type
            self._handle = None

    @jmethod("type", "()Ljava/lang/invoke/MethodType;")
    def type(self):
        return self._call_type

    @jmethod("getTarget", "()Ljava/lang/invoke/MethodHandle;")
    def getTarget(self):
        if self._handle is None:
            throw_new("java.lang.IllegalStateException", "uninitialized call site")
        return self._handle

    @jmethod("dynamicInvoker", "()Ljava/lang/invoke/MethodHandle;")
    def dynamicInvoker(self):
        site = self
        return MethodHandle(self._call_type, lambda *args: site.getTarget()._target(*args))

    def _set(self, handle):
        if handle is None:
            runtime.npe()
        if not handle._type.equals(self._call_type):
            throw_new("java.lang.invoke.WrongMethodTypeException", "target type %s, call site type %s" % (
                handle._type.toMethodDescriptorString(), self._call_type.toMethodDescriptorString()))
        self._handle = handle


@host_class("java.lang.invoke.ConstantCallSite")
class ConstantCallSite(CallSite):
    @jmethod("<init>", "(Ljava/lang/invoke/MethodHandle;)V")
    def _init(self, handle):
        if handle is None:
            runtime.npe()
        CallSite.__init__(self, handle)

    @jmethod("setTarget", "(Ljava/lang/invoke/MethodHandle;)V")
    def setTarget(self, handle):
        throw_new("java.lang.UnsupportedOperationException", "ConstantCallSite")


@host_class("java.lang.invoke.MutableCallSite")
class MutableCallSite(CallSite):
    @jmethod("<init>", "(Ljava/lang/invoke/MethodType;)V")
    def _init_type(self, call_type):
        if call_type is None:
            runtime.npe()
        CallSite.__init__(self, call_type)

    @jmethod("<init>", "(Ljava/lang/invoke/MethodHandle;)V")
    def _init_handle(self, handle):
        if handle is None:
            runtime.npe()
        CallSite.__init__(self, handle)

    @jmethod("setTarget", "(Ljava/lang/invoke/MethodHandle;)V")
    def setTarget(self, handle):
        self._set(handle)


@host_class("java.lang.invoke.VolatileCallSite")
class VolatileCallSite(MutableCallSite):
    pass


def _handle(owner, kind, class_desc, name, descriptor, params, result):
    site = classes.Site(owner, {}, "target", (kind, class_desc, name, descriptor))
    try:
        site.resolve()
    except BaseException as error:
        failure = runtime.to_throwable(error)
        for error_name, exception_name in (("java.lang.NoSuchMethodError", "java.lang.NoSuchMethodException"),
                                           ("java.lang.NoSuchFieldError", "java.lang.NoSuchFieldException")):
            if isinstance(failure, api.lookup_host(error_name).py):
                throw_new(exception_name, failure.getMessage())
        raise failure
    return MethodHandle(MethodType(result, tuple(params)), site)


@host_class("java.lang.invoke.MethodHandles$Lookup", final=True)
class Lookup(Object):
    """the lookup of a class: it finds handles on members through the loader of that class"""

    def __init__(self, owner):
        self._owner = owner

    def _scope(self, refc):
        if isinstance(self._owner, DexClass):
            return self._owner
        if isinstance(refc, DexClass):
            return refc
        throw_new("java.lang.UnsupportedOperationException", "a lookup needs a class of a dex file to find members")

    @jmethod("lookupClass", "()Ljava/lang/Class;")
    def lookupClass(self):
        return self._owner

    @jmethod("lookupModes", "()I")
    def lookupModes(self):
        return 15

    @jmethod("in", "(Ljava/lang/Class;)Ljava/lang/invoke/MethodHandles$Lookup;")
    def in_(self, requested):
        return Lookup(requested)

    @jmethod("findClass", "(Ljava/lang/String;)Ljava/lang/Class;")
    def findClass(self, name):
        scope = self._scope(None)
        found = scope.loader.load_or_none("L" + name.replace(".", "/") + ";")
        if found is None:
            throw_new("java.lang.ClassNotFoundException", name)
        return found

    @jmethod("findStatic", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodHandle;")
    def findStatic(self, refc, name, method_type):
        return _handle(self._scope(refc), "invoke-static", refc.descriptor, name, method_type.toMethodDescriptorString(),
                       method_type._parameters, method_type._return_type)

    @jmethod("findVirtual", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodHandle;")
    def findVirtual(self, refc, name, method_type):
        kind = "invoke-interface" if refc.isInterface() else "invoke-virtual"
        return _handle(self._scope(refc), kind, refc.descriptor, name, method_type.toMethodDescriptorString(),
                       (refc,) + tuple(method_type._parameters), method_type._return_type)

    @jmethod("findSpecial", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def findSpecial(self, refc, name, method_type, caller):
        return _handle(self._scope(refc), "invoke-direct", refc.descriptor, name, method_type.toMethodDescriptorString(),
                       (caller,) + tuple(method_type._parameters), method_type._return_type)

    @jmethod("findConstructor", "(Ljava/lang/Class;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodHandle;")
    def findConstructor(self, refc, method_type):
        if method_type._return_type.descriptor != "V":
            throw_new("java.lang.NoSuchMethodException", "a constructor returns void")
        scope = self._scope(refc)
        descriptor = method_type.toMethodDescriptorString()
        create = classes.Site(scope, {}, "create", ("new-instance", refc.descriptor))
        init = classes.Site(scope, {}, "init", ("invoke-direct", refc.descriptor, "<init>", descriptor))
        try:
            init.resolve()
        except BaseException as error:
            failure = runtime.to_throwable(error)
            if isinstance(failure, api.lookup_host("java.lang.NoSuchMethodError").py):
                throw_new("java.lang.NoSuchMethodException", failure.getMessage())
            raise failure

        def construct(*args):
            instance = create()
            result = init(instance, *args)
            return instance if isinstance(refc, DexClass) else result
        return MethodHandle(MethodType(refc, tuple(method_type._parameters)), construct)

    def _field(self, refc, name, field_type, kind, params, result):
        return _handle(self._scope(refc), kind, refc.descriptor, name, field_type.descriptor, params, result)

    @jmethod("findGetter", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def findGetter(self, refc, name, field_type):
        return self._field(refc, name, field_type, "iget", (refc,), field_type)

    @jmethod("findSetter", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def findSetter(self, refc, name, field_type):
        return self._field(refc, name, field_type, "iput", (refc, field_type), api.PRIMITIVES["V"])

    @jmethod("findStaticGetter", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def findStaticGetter(self, refc, name, field_type):
        return self._field(refc, name, field_type, "sget", (), field_type)

    @jmethod("findStaticSetter", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def findStaticSetter(self, refc, name, field_type):
        return self._field(refc, name, field_type, "sput", (field_type,), api.PRIMITIVES["V"])

    @jmethod("bind", "(Ljava/lang/Object;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodHandle;")
    def bind(self, receiver, name, method_type):
        if receiver is None:
            runtime.npe()
        return self.findVirtual(runtime.class_of(receiver), name, method_type).bindTo(receiver)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._owner.getName() if self._owner is not None else "no lookup class"


@host_class("java.lang.invoke.MethodHandles", final=True)
class MethodHandles(Object):
    @jstatic("lookup", "()Ljava/lang/invoke/MethodHandles$Lookup;")
    @caller_sensitive
    def lookup(caller=None):
        return Lookup(caller)

    @jstatic("publicLookup", "()Ljava/lang/invoke/MethodHandles$Lookup;")
    def publicLookup():
        return Lookup(None)

    @jstatic("constant", "(Ljava/lang/Class;Ljava/lang/Object;)Ljava/lang/invoke/MethodHandle;")
    def constant(value_type, value):
        if value_type.descriptor == "V":
            throw_new("java.lang.IllegalArgumentException", "void type")
        register = value if len(value_type.descriptor) > 1 else converter(None, _OBJECT, value_type.descriptor)(value)
        return MethodHandle(MethodType(value_type, ()), lambda: register)

    @jstatic("identity", "(Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def identity(value_type):
        if value_type.descriptor == "V":
            throw_new("java.lang.IllegalArgumentException", "void type")
        return MethodHandle(MethodType(value_type, (value_type,)), lambda value: value)

    @jstatic("insertArguments", "(Ljava/lang/invoke/MethodHandle;I[Ljava/lang/Object;)Ljava/lang/invoke/MethodHandle;")
    def insertArguments(handle, position, values):
        params = list(handle._type._parameters)
        if position < 0 or position + len(values) > len(params):
            throw_new("java.lang.IllegalArgumentException", "cannot insert at %d" % position)
        loader = None
        inserted = [converter(loader, _OBJECT, params[position + i].descriptor)(v) if len(params[position + i].descriptor) == 1
                    else v for i, v in enumerate(values)]
        remaining = params[:position] + params[position + len(values):]
        target = handle._target

        def call(*args):
            return target(*args[:position], *inserted, *args[position:])
        return MethodHandle(MethodType(handle._type._return_type, tuple(remaining)), call)

    @jstatic("dropArguments", "(Ljava/lang/invoke/MethodHandle;I[Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def dropArguments(handle, position, types):
        params = list(handle._type._parameters)
        if position < 0 or position > len(params):
            throw_new("java.lang.IllegalArgumentException", "cannot drop at %d" % position)
        count = len(types)
        target = handle._target

        def call(*args):
            return target(*args[:position], *args[position + count:])
        return MethodHandle(MethodType(handle._type._return_type, tuple(params[:position] + list(types) + params[position:])),
                            call)

    @jstatic("filterReturnValue", "(Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodHandle;)Ljava/lang/invoke/MethodHandle;")
    def filterReturnValue(handle, filter_):
        returned = handle._type._return_type
        if returned.descriptor == "V":
            if filter_._type._parameters:
                throw_new("java.lang.invoke.WrongMethodTypeException", "filter takes a value, the target returns none")
        elif len(filter_._type._parameters) != 1 or filter_._type._parameters[0].descriptor != returned.descriptor:
            throw_new("java.lang.invoke.WrongMethodTypeException", "filter does not take the return type of the target")
        target, after = handle._target, filter_._target
        if returned.descriptor == "V":
            def call(*args):
                target(*args)
                return after()
        else:
            def call(*args):
                return after(target(*args))
        return MethodHandle(MethodType(filter_._type._return_type, handle._type._parameters), call)

    @jstatic("filterArguments", "(Ljava/lang/invoke/MethodHandle;I[Ljava/lang/invoke/MethodHandle;)Ljava/lang/invoke/MethodHandle;")
    def filterArguments(handle, position, filters):
        params = list(handle._type._parameters)
        if position < 0 or position + len(filters) > len(params):
            throw_new("java.lang.IllegalArgumentException", "cannot filter at %d" % position)
        for offset, filter_ in enumerate(filters):
            if filter_ is not None and filter_._type._return_type.descriptor != params[position + offset].descriptor:
                throw_new("java.lang.invoke.WrongMethodTypeException", "filter %d does not return the argument type" % offset)
            if filter_ is not None:
                params[position + offset] = filter_._type._parameters[0]
        target = handle._target
        steps = [None if f is None else f._target for f in filters]

        def call(*args):
            args = list(args)
            for offset, step in enumerate(steps):
                if step is not None:
                    args[position + offset] = step(args[position + offset])
            return target(*args)
        return MethodHandle(MethodType(handle._type._return_type, tuple(params)), call)

    @jstatic("guardWithTest", "(Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodHandle;)Ljava/lang/invoke/MethodHandle;")
    def guardWithTest(test, target, fallback):
        if not target._type.equals(fallback._type):
            throw_new("java.lang.invoke.WrongMethodTypeException", "target and fallback differ in type")
        if test._type._return_type.descriptor != "Z":
            throw_new("java.lang.invoke.WrongMethodTypeException", "the test must return boolean")
        count = len(test._type._parameters)
        yes, no, check = target._target, fallback._target, test._target
        return MethodHandle(target._type, lambda *args: yes(*args) if check(*args[:count]) else no(*args))

    @jstatic("permuteArguments", "(Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;[I)Ljava/lang/invoke/MethodHandle;")
    def permuteArguments(handle, new_type, reorder):
        order = list(reorder)
        if len(order) != len(handle._type._parameters) or any(i < 0 or i >= len(new_type._parameters) for i in order):
            throw_new("java.lang.IllegalArgumentException", "bad reorder array")
        target = handle._target
        return MethodHandle(new_type, lambda *args: target(*[args[i] for i in order]))

    @jstatic("catchException", "(Ljava/lang/invoke/MethodHandle;Ljava/lang/Class;Ljava/lang/invoke/MethodHandle;)Ljava/lang/invoke/MethodHandle;")
    def catchException(handle, exception_type, handler):
        target, recover = handle._target, handler._target
        count = len(handler._type._parameters) - 1

        def call(*args):
            try:
                return target(*args)
            except BaseException as error:
                failure = runtime.to_throwable(error)
                if not exception_type.isInstance(failure):
                    raise failure
                return recover(failure, *args[:count])
        return MethodHandle(handle._type, call)

    @jstatic("throwException", "(Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/invoke/MethodHandle;")
    def throwException(return_type, exception_type):
        def call(error):
            if error is None:
                runtime.npe()
            raise error
        return MethodHandle(MethodType(return_type, (exception_type,)), call)
