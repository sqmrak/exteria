"""java.lang.reflect over the python classes of the shims: Method, Constructor and Field of a class are its own functions
and attributes, and invoke() goes through the class, so a hook installed on a method is seen by every caller"""
import inspect

from java.lang import Class, NoSuchFieldException, Object


class AccessibleObject(Object):
    def setAccessible(self, _flag):
        # nothing in a python class is private to the shims
        pass


class Member(AccessibleObject):
    def getDeclaringClass(self):
        return self._declaring


class Method(Member):
    def __init__(self, declaring, name):
        self._declaring = declaring
        self._name = name

    def _raw(self):
        return vars(self._declaring._py)[self._name]

    def _function(self):
        raw = self._raw()
        return getattr(raw, "__func__", raw)

    def getName(self):
        return self._name

    def _parameters(self):
        function = self._function()
        parameters = list(inspect.signature(function).parameters.values())
        if not isinstance(self._raw(), staticmethod):
            parameters = parameters[1:]
        return parameters

    def getParameterCount(self):
        return len(self._parameters())

    def getParameterTypes(self):
        # a python parameter is typed only when the shim annotates it, any other is an Object
        return [Class._of(p.annotation if isinstance(p.annotation, type) else Object) for p in self._parameters()]

    def invoke(self, obj, *args):
        target = self._declaring._py if obj is None else obj
        return getattr(target, self._name)(*args)

    def toString(self):
        return self._declaring.getName() + "." + self._name

    __repr__ = toString


class Constructor(Member):
    def __init__(self, declaring):
        self._declaring = declaring

    def getName(self):
        return self._declaring.getName()

    def getParameterCount(self):
        init = vars(self._declaring._py).get("__init__")
        return len(inspect.signature(init).parameters) - 1 if init is not None else 0

    def newInstance(self, *args):
        return self._declaring._py(*args)


class Field(Member):
    def __init__(self, declaring, name):
        self._declaring = declaring
        self._name = name

    def getName(self):
        return self._name

    def get(self, obj):
        target = self._declaring._py if obj is None else obj
        try:
            return getattr(target, self._name)
        except AttributeError:
            raise NoSuchFieldException(self._declaring.getName() + "." + self._name) from None

    def set(self, obj, value):
        setattr(self._declaring._py if obj is None else obj, self._name, value)


def _methods_of(declaring):
    found = []
    for name, raw in vars(declaring._py).items():
        if name.startswith("__") and name.endswith("__"):
            continue
        if isinstance(raw, (staticmethod, classmethod)) or inspect.isfunction(raw):
            found.append(Method(declaring, name))
    return found
