"""java.lang as far as plugins reach it"""
import builtins
import threading


class _GetClass:
    """getClass answers for an instance and for the class itself, as the proxy of a java class does"""

    def __get__(self, obj, owner):
        target = owner if obj is None else type(obj)
        return lambda: Class._of(target)


class Object:
    getClass = _GetClass()

    def equals(self, other):
        return self is other

    def hashCode(self):
        return id(self) & 0x7FFFFFFF

    def toString(self):
        return repr(self)


class Class(Object):
    """java.lang.Class over a python class of the shims. members are the functions the class body defines, so a
    plugin that looks a method up by name finds what the shim implements and nothing else"""

    _cache = {}

    def __init__(self, target):
        self._py = target

    @staticmethod
    def _of(target):
        found = Class._cache.get(target)
        if found is None:
            found = Class._cache[target] = Class(target)
        return found

    def getName(self):
        from java import _registry
        registered = _registry.name_of(self._py)
        if registered is not None:
            return registered
        return self._py.__module__ + "." + self._py.__qualname__.replace(".", "$")

    def getSimpleName(self):
        return self._py.__name__

    def getSuperclass(self):
        base = self._py.__bases__[0] if self._py.__bases__ else None
        return None if base is None or base is builtins.object else Class._of(base)

    def isInstance(self, obj):
        return isinstance(obj, self._py)

    def getDeclaredMethods(self):
        from java.lang import reflect
        return reflect._methods_of(self)

    def getMethods(self):
        found = {}
        for klass in self._py.__mro__:
            if klass is builtins.object:
                continue
            for method in Class._of(klass).getDeclaredMethods():
                found.setdefault(method.getName(), method)
        return list(found.values())

    def getDeclaredMethod(self, name, *_types):
        for method in self.getDeclaredMethods():
            if method.getName() == name:
                return method
        raise NoSuchMethodException(self.getName() + "." + name)

    def getMethod(self, name, *types):
        for klass in self._py.__mro__:
            if klass is not builtins.object:
                try:
                    return Class._of(klass).getDeclaredMethod(name, *types)
                except NoSuchMethodException:
                    continue
        raise NoSuchMethodException(self.getName() + "." + name)

    def getConstructors(self):
        from java.lang import reflect
        return [reflect.Constructor(self)]

    getDeclaredConstructors = getConstructors

    def getDeclaredFields(self):
        from java.lang import reflect
        return [reflect.Field(self, name) for name in getattr(self._py, "__annotations__", {})]

    def getDeclaredField(self, name):
        from java.lang import reflect
        if name in vars(self._py) or name in getattr(self._py, "__annotations__", {}):
            return reflect.Field(self, name)
        raise NoSuchFieldException(self.getName() + "." + name)

    def getField(self, name):
        for klass in self._py.__mro__:
            if klass is not builtins.object:
                try:
                    return Class._of(klass).getDeclaredField(name)
                except NoSuchFieldException:
                    continue
        raise NoSuchFieldException(self.getName() + "." + name)

    def toString(self):
        return "class " + self.getName()

    __repr__ = toString


class Throwable(builtins.Exception):
    def getMessage(self):
        return str(self.args[0]) if self.args else None

    def toString(self):
        return type(self).__name__ + (": " + self.getMessage() if self.args else "")


class _JavaException(Throwable):
    pass


_JavaException.__name__ = _JavaException.__qualname__ = "Exception"


class RuntimeException(_JavaException):
    pass


class ReflectiveOperationException(_JavaException):
    pass


class NoSuchMethodException(ReflectiveOperationException):
    pass


class NoSuchFieldException(ReflectiveOperationException):
    pass


def __getattr__(name):
    # a module level name Exception would shadow the builtin for every function of this module
    if name == "Exception":
        return _JavaException
    raise AttributeError(name)


class Runnable:
    """a python object with run(); a plain callable is accepted wherever the shims take a Runnable"""

    def run(self):
        raise NotImplementedError


class Thread:
    @staticmethod
    def currentThread():
        return threading.current_thread()

    @staticmethod
    def sleep(ms):
        import time
        time.sleep(ms / 1000.0)


class Math:
    @staticmethod
    def abs(x):
        return abs(x)


class System:
    @staticmethod
    def currentTimeMillis():
        import time
        return int(time.time() * 1000)

    @staticmethod
    def nanoTime():
        import time
        return int(time.monotonic() * 1e9)


class String(str):
    """java.lang.String(bytes, charset) and String(text); plugins use it to turn bytes into text"""

    def __new__(cls, value="", charset=None):
        if isinstance(value, (bytes, bytearray)):
            return str.__new__(cls, bytes(value).decode(str(charset or "utf-8")))
        return str.__new__(cls, value)


class Long(int):
    MAX_VALUE = 2 ** 63 - 1
    MIN_VALUE = -2 ** 63

    @staticmethod
    def valueOf(value):
        return Long(value)

    @staticmethod
    def parseLong(text):
        return Long(int(text))


class Integer(int):
    MAX_VALUE = 2 ** 31 - 1
    MIN_VALUE = -2 ** 31

    @staticmethod
    def valueOf(value):
        return Integer(value)

    @staticmethod
    def parseInt(text):
        return Integer(int(text))


class Boolean:
    TRUE = True
    FALSE = False

    @staticmethod
    def valueOf(value):
        return value if isinstance(value, bool) else str(value).lower() == "true"

    @staticmethod
    def parseBoolean(text):
        return str(text).lower() == "true"


class Float(float):
    @staticmethod
    def valueOf(value):
        return Float(value)

    @staticmethod
    def parseFloat(text):
        return Float(text)
