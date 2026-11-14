"""java.lang.invoke types shared by dex method type constants and method handles"""

from . import api, runtime
from .api import host_class, jmethod, jstatic
from .jlang import Object

_WIDEN = {"B": "BSIJFD", "S": "SIJFD", "C": "CIJFD", "I": "IJFD", "J": "JFD", "F": "FD", "D": "D", "Z": "Z"}


def adapt_primitive(value, source, target):
    if source == target:
        return value
    if source in _WIDEN and target in _WIDEN[source]:
        return runtime.f32(float(value)) if target == "F" else float(value) if target == "D" else value
    runtime.throw_new("java.lang.invoke.WrongMethodTypeException", "%s cannot convert to %s" % (source, target))


_WRAPPER_CODES = {"Ljava/lang/Integer;": "I", "Ljava/lang/Long;": "J", "Ljava/lang/Short;": "S", "Ljava/lang/Byte;": "B",
                  "Ljava/lang/Character;": "C", "Ljava/lang/Boolean;": "Z", "Ljava/lang/Float;": "F",
                  "Ljava/lang/Double;": "D"}
_WRAPPER_NAMES = {code: descriptor[1:-1].replace("/", ".") for descriptor, code in _WRAPPER_CODES.items()}


def can_adapt(source, target):
    """whether MethodHandle.asType (and invoke) can convert a value of type source to type target"""
    if source is target:
        return True
    a, b = source.descriptor, target.descriptor
    if a == b or b == "V":
        return True
    if a == "V":
        return True
    if len(a) == 1 and len(b) == 1:
        return a in _WIDEN and b in _WIDEN[a]
    if len(a) == 1:
        return bool(target.isAssignableFrom(api.lookup_host(_WRAPPER_NAMES[a])))
    if len(b) == 1:
        code = _WRAPPER_CODES.get(a)
        if code is not None:
            return b in _WIDEN[code]
        # a reference that is no wrapper converts when a wrapper could be stored in it, the check is at run time
        return bool(source.isAssignableFrom(api.lookup_host(_WRAPPER_NAMES[b])))
    return True


def adapt(value, source, target):
    """the conversion MethodHandle.asType makes from source to target: primitive widening, boxing, unboxing, casts, and a
    dropped or introduced void"""
    from .jreflect import _CODE_OF_BOX, box
    a, b = source.descriptor, target.descriptor
    if a == b:
        return value
    if b == "V":
        return None
    if a == "V":
        return None if len(b) > 1 else (0.0 if b in "FD" else 0)
    if len(a) == 1 and len(b) == 1:
        return adapt_primitive(value, a, b)
    if len(a) == 1:
        return box(value, a)
    if len(b) == 1:
        if value is None:
            runtime.npe()
        code = _CODE_OF_BOX.get(type(value))
        if code is None or code not in _WIDEN or b not in _WIDEN[code]:
            runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                runtime.type_name_of(value), api.PRIMITIVE_NAMES[b]))
        return adapt_primitive(value.value, code, b)
    if value is not None and not target.isInstance(value):
        runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (runtime.type_name_of(value), target.getName()))
    return value


def invoke_handle(handle, call_type, descriptor, exact, args):
    """MethodHandle.invoke (or invokeExact) of handle with the arguments of a call site of type call_type"""
    if handle is None:
        runtime.npe()
    if not handle._type.equals(call_type):
        actual = handle._type
        if exact or len(actual._parameters) != len(call_type._parameters):
            runtime.throw_new("java.lang.invoke.WrongMethodTypeException", descriptor)
        if not all(can_adapt(src, dst) for src, dst in zip(call_type._parameters, actual._parameters)):
            runtime.throw_new("java.lang.invoke.WrongMethodTypeException", descriptor)
        if call_type._return_type.descriptor != "V" and not can_adapt(actual._return_type, call_type._return_type):
            runtime.throw_new("java.lang.invoke.WrongMethodTypeException", descriptor)
        converted = [adapt(value, src, dst) for value, src, dst in zip(args, call_type._parameters, actual._parameters)]
        result = handle._target(*converted)
        return None if call_type._return_type.descriptor == "V" else adapt(result, actual._return_type, call_type._return_type)
    return handle._target(*args)


@host_class("java.lang.invoke.MethodHandle", abstract=True)
class MethodHandle(Object):
    def __init__(self, method_type, target):
        self._type = method_type
        self._target = target

    @jmethod("type", "()Ljava/lang/invoke/MethodType;")
    def type(self):
        return self._type

    @jmethod("bindTo", "(Ljava/lang/Object;)Ljava/lang/invoke/MethodHandle;")
    def bindTo(self, value):
        params = self._type._parameters
        if not params or len(params[0].descriptor) == 1:
            runtime.throw_new("java.lang.IllegalArgumentException", "no leading reference parameter to bind")
        if value is not None and not params[0].isInstance(value):
            runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to %s" % (
                runtime.type_name_of(value), params[0].getName()))
        target = self._target
        return MethodHandle(MethodType(self._type._return_type, params[1:]), lambda *args: target(value, *args))

    @jmethod("asType", "(Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodHandle;")
    def asType(self, new_type):
        if new_type.equals(self._type):
            return self
        if len(new_type._parameters) != len(self._type._parameters):
            runtime.throw_new("java.lang.invoke.WrongMethodTypeException", "cannot convert %s to %s" % (
                self._type.toMethodDescriptorString(), new_type.toMethodDescriptorString()))
        handle, descriptor = self, new_type.toMethodDescriptorString()
        return MethodHandle(new_type, lambda *args: invoke_handle(handle, new_type, descriptor, False, args))

    @jmethod("invokeWithArguments", "([Ljava/lang/Object;)Ljava/lang/Object;")
    def invokeWithArguments(self, values):
        """every value is a boxed object; the result is boxed again"""
        from .jreflect import box, unbox
        params = self._type._parameters
        if len(values) != len(params):
            runtime.throw_new("java.lang.invoke.WrongMethodTypeException", "expected %d arguments, got %d" % (
                len(params), len(values)))
        converted = [unbox(v, p.descriptor, None) if len(p.descriptor) == 1 else v for v, p in zip(values, params)]
        result = self._target(*converted)
        returned = self._type._return_type.descriptor
        return None if returned == "V" else box(result, returned)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "MethodHandle" + self._type.toMethodDescriptorString()


@host_class("java.lang.invoke.MethodType", final=True)
class MethodType(Object):
    def __init__(self, return_type, parameters):
        self._return_type = return_type
        self._parameters = tuple(parameters)

    @jstatic("methodType", "(Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def methodType(return_type):
        return MethodType._make(return_type, ())

    @jstatic("methodType", "(Ljava/lang/Class;[Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def methodTypeArray(return_type, parameters):
        if parameters is None:
            runtime.npe()
        return MethodType._make(return_type, parameters)

    @jstatic("methodType", "(Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def methodTypeOne(return_type, parameter):
        return MethodType._make(return_type, (parameter,))

    @jstatic("methodType", "(Ljava/lang/Class;Ljava/lang/Class;[Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def methodTypeFirstAndRest(return_type, first, rest):
        if rest is None:
            runtime.npe()
        return MethodType._make(return_type, (first,) + tuple(rest))

    @jstatic("methodType", "(Ljava/lang/Class;Ljava/util/List;)Ljava/lang/invoke/MethodType;")
    def methodTypeList(return_type, parameters):
        from .jutil import iterate
        if parameters is None:
            runtime.npe()
        return MethodType._make(return_type, tuple(iterate(parameters)))

    @jstatic("methodType", "(Ljava/lang/Class;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/MethodType;")
    def methodTypeOf(return_type, other):
        if other is None:
            runtime.npe()
        return MethodType._make(return_type, other._parameters)

    @jstatic("genericMethodType", "(I)Ljava/lang/invoke/MethodType;")
    def genericMethodType(count):
        return MethodType.genericMethodTypeArray(count, 0)

    @jstatic("genericMethodType", "(IZ)Ljava/lang/invoke/MethodType;")
    def genericMethodTypeArray(count, array):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "bad parameter count %d" % count)
        everything = api.lookup_host("java.lang.Object")
        parameters = [everything] * count
        if array:
            parameters.append(runtime.array_type_of("[Ljava/lang/Object;"))
        return MethodType._make(everything, parameters)

    @staticmethod
    def _make(return_type, parameters):
        if return_type is None or any(item is None for item in parameters):
            runtime.npe()
        if any(item.descriptor == "V" for item in parameters):
            runtime.throw_new("java.lang.IllegalArgumentException", "parameter type is void")
        if sum(2 if item.descriptor in ("J", "D") else 1 for item in parameters) > 255:
            runtime.throw_new("java.lang.IllegalArgumentException", "too many parameter slots")
        return MethodType(return_type, parameters)

    @jmethod("returnType", "()Ljava/lang/Class;")
    def returnType(self):
        return self._return_type

    @jmethod("parameterList", "()Ljava/util/List;")
    def parameterList(self):
        from .jutil import ArrayList
        found = ArrayList()
        found._a.extend(self._parameters)
        return found

    @jmethod("changeReturnType", "(Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def changeReturnType(self, return_type):
        return MethodType._make(return_type, self._parameters)

    @jmethod("changeParameterType", "(ILjava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def changeParameterType(self, index, parameter):
        self.parameterType(index)
        found = list(self._parameters)
        found[index] = parameter
        return MethodType._make(self._return_type, found)

    @jmethod("insertParameterTypes", "(I[Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def insertParameterTypes(self, index, parameters):
        if index < 0 or index > len(self._parameters):
            runtime.throw_new("java.lang.IndexOutOfBoundsException", str(index))
        found = list(self._parameters)
        found[index:index] = list(parameters)
        return MethodType._make(self._return_type, found)

    @jmethod("appendParameterTypes", "([Ljava/lang/Class;)Ljava/lang/invoke/MethodType;")
    def appendParameterTypes(self, parameters):
        return MethodType._make(self._return_type, self._parameters + tuple(parameters))

    @jmethod("dropParameterTypes", "(II)Ljava/lang/invoke/MethodType;")
    def dropParameterTypes(self, start, end):
        if start < 0 or start > end or end > len(self._parameters):
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "%d..%d" % (start, end))
        return MethodType._make(self._return_type, self._parameters[:start] + self._parameters[end:])

    @jmethod("hasPrimitives", "()Z")
    def hasPrimitives(self):
        return int(self._return_type.isPrimitive() or any(item.isPrimitive() for item in self._parameters))

    @jmethod("erase", "()Ljava/lang/invoke/MethodType;")
    def erase(self):
        everything = api.lookup_host("java.lang.Object")
        return MethodType(self._return_type if self._return_type.isPrimitive() else everything,
                          [item if item.isPrimitive() else everything for item in self._parameters])

    @jmethod("generic", "()Ljava/lang/invoke/MethodType;")
    def generic(self):
        everything = api.lookup_host("java.lang.Object")
        return MethodType(everything, [everything] * len(self._parameters))

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "(" + ",".join(item.getSimpleName() for item in self._parameters) + ")" + self._return_type.getSimpleName()

    @jmethod("parameterCount", "()I")
    def parameterCount(self):
        return len(self._parameters)

    @jmethod("parameterType", "(I)Ljava/lang/Class;")
    def parameterType(self, index):
        if index < 0 or index >= len(self._parameters):
            runtime.throw_new("java.lang.IndexOutOfBoundsException", str(index))
        return self._parameters[index]

    @jmethod("parameterArray", "()[Ljava/lang/Class;")
    def parameterArray(self):
        array = runtime.new_array("[Ljava/lang/Class;", len(self._parameters))
        array[:] = self._parameters
        return array

    @jmethod("toMethodDescriptorString", "()Ljava/lang/String;")
    def toMethodDescriptorString(self):
        return "(" + "".join(item.descriptor for item in self._parameters) + ")" + self._return_type.descriptor

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return int(isinstance(other, MethodType) and self._return_type is other._return_type and
                   self._parameters == other._parameters)

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(hash((self._return_type, self._parameters)))
