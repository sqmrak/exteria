"""the java bridge of chaquopy as far as exteraGram plugins touch it, over the classes the app registers.

there is no jvm on ios. jclass answers only for names in java._registry, which the app and the shims under
python/shim fill; any other name raises ClassNotFoundException, the exception a plugin already handles when a class
is missing on the android build it targets."""

from . import _registry


class JavaException(Exception):
    """base of the errors that stand for a java throwable"""


class ClassNotFoundException(JavaException):
    pass


def jclass(name):
    entry = _registry.lookup(name)
    if entry is None:
        entry = _from_module(name)
    if entry is None:
        raise ClassNotFoundException(name)
    return entry


_SHIMMED = ("android", "androidx", "org.telegram", "java.lang", "java.util", "java.io", "java.net", "java.nio")


def _from_module(name):
    """the shim for a java class is the python class of the same name in the module of the same package.
    a nested class (Outer$Inner) is an attribute of the outer one"""
    if not isinstance(name, str) or not name.startswith(_SHIMMED):
        return None
    import importlib
    outer, *inner = name.split("$")
    package, _, simple = outer.rpartition(".")
    try:
        entry = getattr(importlib.import_module(package), simple)
        for part in inner:
            entry = getattr(entry, part)
    except (ImportError, AttributeError):
        return None
    return entry


def dynamic_proxy(*interfaces):
    """base class of a python object that implements java interfaces. the app calls its methods by name"""
    return type("DynamicProxy", (), {"_java_interfaces": tuple(interfaces)})


def jarray(element):
    def make(values):
        return list(values)
    return make


def cast(_type, value):
    return value


def jboolean(value):
    return bool(value)


def jbyte(value):
    return int(value)


def jshort(value):
    return int(value)


def jint(value):
    return int(value)


def jlong(value):
    return int(value)


def jfloat(value):
    return float(value)


def jdouble(value):
    return float(value)


def jchar(value):
    return str(value)[:1]


jvoid = None
