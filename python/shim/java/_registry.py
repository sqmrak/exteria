"""java class names the shims answer for. a name is registered once; the entry is whatever jclass should return"""

_classes = {}


def register(name, entry):
    if name in _classes:
        raise ValueError("class registered twice: " + name)
    _classes[name] = entry


_lazy = {}


def register_lazy(name, module, attribute):
    """a class the shims import on first use; importing it at registration would pull the plugin loader in while it starts"""
    if name in _classes or name in _lazy:
        raise ValueError("class registered twice: " + name)
    _lazy[name] = (module, attribute)


def lookup(name):
    entry = _classes.get(name)
    if entry is None and name in _lazy:
        import importlib
        module, attribute = _lazy[name]
        entry = _classes[name] = getattr(importlib.import_module(module), attribute)
    return entry


def names():
    return sorted(set(_classes) | set(_lazy))


def name_of(target):
    """the java name a class was registered under, or None"""
    for name, entry in _classes.items():
        if entry is target:
            return name
    for name, (module, attribute) in _lazy.items():
        if module == target.__module__ and attribute == target.__qualname__:
            return name
    return None
