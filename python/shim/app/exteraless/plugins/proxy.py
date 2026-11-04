"""java_subclass on ios: a subclass of a class of the shims is a python subclass of it.

extera_utils.classes describes a class as a json spec and asks PluginServices for a generated class, an instance of it and
the call of the super implementation. the shims already are python classes, so the generated class is made with type():
every method the spec names calls the python peer through __extera_dispatch__, and invokeSuper runs the method of the shim
that the override replaced. interfaces become extra bases when the shims have them. fields and constructors that run before
the super constructor have no counterpart and the spec that asks for them is refused with a reason"""

import importlib
import json
import threading

from java import jclass
from java.lang import Class

_lock = threading.Lock()
_generated = {}
_specs = {}
_error = [None]


def _resolve(name):
    """a class by java name; a nested one may arrive with dots instead of the $"""
    try:
        return jclass(name)
    except Exception:
        pass
    parts = name.split(".")
    for cut in range(len(parts) - 1, 0, -1):
        try:
            entry = importlib.import_module(".".join(parts[:cut]))
            for part in parts[cut:]:
                entry = getattr(entry, part)
            return entry
        except (ImportError, AttributeError):
            continue
    raise LookupError("no class " + name)


def _method(spec):
    key = spec["key"]
    name = spec["name"]

    def call(self, *args):
        return self.__dict__["__extera_peer__"].__extera_dispatch__(key, self, *args)

    call.__name__ = name
    return name, call


def generate(owner, spec_json):
    _error[0] = None
    try:
        spec = json.loads(spec_json)
        if spec.get("fields"):
            raise NotImplementedError("jfield is not available on ios")
        bases = [_resolve(spec["superclass"])] + [_resolve(name) for name in spec.get("interfaces", [])]
        bases = tuple(base for base in bases if isinstance(base, type))
        members = dict(_method(entry) for entry in spec.get("methods", []))
        with _lock:
            key = "proxy:%d" % (len(_generated) + 1)
            created = type(spec["name"], bases, dict(members, __module__=__name__))
            _generated[key] = created
            _specs[key] = {entry["key"]: entry for entry in spec.get("methods", [])}
        return key
    except Exception as error:
        _error[0] = "%s: %s" % (type(error).__name__, error)
        return None


def error():
    return _error[0]


def proxy_class(key):
    return Class._of(_generated[key])


def new_instance(owner, key, _signature, args, peer):
    created = _generated[key]
    instance = created.__new__(created)
    instance.__dict__["__extera_peer__"] = peer
    created.__init__(instance, *args)
    return instance


def invoke_super(key, proxy, py_key, args):
    """the method of the shim that the override with this key replaced; None when the shim has no such method"""
    name = _specs[key][py_key]["name"]
    for base in _generated[key].__mro__[1:]:
        function = vars(base).get(name)
        if function is not None:
            return getattr(function, "__func__", function)(proxy, *args)
    return None
