"""android.content.SharedPreferences: key-value files under the files folder of the app

one store per name, shared by every caller, as on android. a file holds a json object of typed entries
(["s", text], ["i", int], ["l", int], ["f", float], ["b", bool], ["set", [text, ...]]) so an int stays an int and a float a float. the file is written
whole through a temporary file and renamed over the old one, so a crash leaves either version intact. apply() and commit() both write
before they return; commit() answers whether the write worked and apply() reports a failure on stderr"""

import json
import os
import struct
import sys
import threading

from java.lang import IllegalArgumentException, Object

_stores = {}
_stores_lock = threading.Lock()


def _f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


class _Store:
    def __init__(self, path):
        self.path = path
        self.lock = threading.RLock()
        self.values = {}
        self.listeners = []
        self.load()

    def load(self):
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                raw = json.load(handle)
        except FileNotFoundError:
            return
        except (OSError, ValueError) as error:
            sys.stderr.write("W/SharedPreferences: %s is unreadable and starts empty: %s\n" % (self.path, error))
            return
        if not isinstance(raw, dict):
            sys.stderr.write("W/SharedPreferences: %s does not hold an object and starts empty\n" % self.path)
            return
        for key, entry in raw.items():
            if isinstance(entry, list) and len(entry) == 2 and entry[0] in ("s", "i", "l", "f", "b", "set"):
                kind, value = entry
                if kind == "set":
                    value = set(value) if isinstance(value, list) and all(isinstance(v, str) for v in value) else None
                if value is not None:
                    self.values[key] = (kind, value)

    def write(self):
        raw = {}
        for key, (kind, value) in self.values.items():
            raw[key] = [kind, sorted(value) if kind == "set" else value]
        directory = os.path.dirname(self.path)
        os.makedirs(directory, exist_ok=True)
        temporary = self.path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(raw, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, self.path)


def open_store(path):
    with _stores_lock:
        store = _stores.get(path)
        if store is None:
            store = _stores[path] = _Store(path)
        return store


class SharedPreferences(Object):
    class OnSharedPreferenceChangeListener:
        """a program implements onSharedPreferenceChanged(preferences, key)"""

    class Editor(Object):
        def __init__(self, owner):
            self._owner = owner
            self._ops = []
            self._clear = False

        def _put(self, key, kind, value):
            self._ops.append((key, kind, value))
            return self

        def putString(self, key, value):
            return self._put(key, "s", value) if value is not None else self.remove(key)

        def putInt(self, key, value):
            return self._put(key, "i", int(value))

        def putLong(self, key, value):
            return self._put(key, "l", int(value))

        def putFloat(self, key, value):
            return self._put(key, "f", _f32(float(value)))

        def putBoolean(self, key, value):
            return self._put(key, "b", bool(value))

        def putStringSet(self, key, values):
            if values is None:
                return self.remove(key)
            from dexvm.jutil import iterate
            items = set()
            for item in (values if isinstance(values, (set, frozenset, list, tuple)) else iterate(values)):
                if not isinstance(item, str):
                    raise IllegalArgumentException("a string set holds strings only")
                items.add(item)
            return self._put(key, "set", items)

        def remove(self, key):
            self._ops.append((key, None, None))
            return self

        def clear(self):
            self._clear = True
            return self

        def _apply(self):
            owner = self._owner
            store = owner._store
            changed = []
            with store.lock:
                if self._clear:
                    changed.extend(store.values)
                    store.values.clear()
                for key, kind, value in self._ops:
                    if kind is None:
                        if store.values.pop(key, None) is not None:
                            changed.append(key)
                    else:
                        store.values[key] = (kind, set(value) if kind == "set" else value)
                        changed.append(key)
                self._ops = []
                self._clear = False
                try:
                    store.write()
                    ok = True
                    failure = None
                except OSError as error:
                    ok = False
                    failure = error
                listeners = list(store.listeners)
            for key in dict.fromkeys(changed):
                for listener in listeners:
                    listener.onSharedPreferenceChanged(owner, key)
            return ok, failure

        def commit(self):
            return self._apply()[0]

        def apply(self):
            ok, failure = self._apply()
            if not ok:
                sys.stderr.write("E/SharedPreferences: could not write %s: %s\n" % (self._owner._store.path, failure))

    def __init__(self, store):
        self._store = store

    def _get(self, key, kind, fallback):
        with self._store.lock:
            entry = self._store.values.get(key)
        if entry is None:
            return fallback
        if entry[0] != kind:
            from java.lang import ClassCastException
            raise ClassCastException("%s cannot be cast to the type requested for %s" % (entry[0], key))
        return entry[1]

    def getString(self, key, fallback=None):
        return self._get(key, "s", fallback)

    def getInt(self, key, fallback=0):
        return self._get(key, "i", fallback)

    def getLong(self, key, fallback=0):
        return self._get(key, "l", fallback)

    def getFloat(self, key, fallback=0.0):
        return self._get(key, "f", fallback)

    def getBoolean(self, key, fallback=False):
        return self._get(key, "b", fallback)

    def getStringSet(self, key, fallback=None):
        found = self._get(key, "set", None)
        if found is None:
            return fallback
        from dexvm.jmap import HashSet
        result = HashSet()
        for item in sorted(found):
            result.add(item)
        return result

    def contains(self, key):
        with self._store.lock:
            return key in self._store.values

    def getAll(self):
        from dexvm.jlang import Boolean, Float, Integer, Long
        from dexvm.jmap import HashMap
        result = HashMap()
        with self._store.lock:
            for key, (kind, value) in self._store.values.items():
                if kind == "i":
                    value = Integer.valueOf(value)
                elif kind == "l":
                    value = Long.valueOf(value)
                elif kind == "f":
                    value = Float(value)
                elif kind == "b":
                    value = Boolean.TRUE if value else Boolean.FALSE
                elif kind == "set":
                    value = self.getStringSet(key)
                result.put(key, value)
        return result

    def edit(self):
        return SharedPreferences.Editor(self)

    def registerOnSharedPreferenceChangeListener(self, listener):
        with self._store.lock:
            if listener not in self._store.listeners:
                self._store.listeners.append(listener)

    def unregisterOnSharedPreferenceChangeListener(self, listener):
        with self._store.lock:
            if listener in self._store.listeners:
                self._store.listeners.remove(listener)


Editor = SharedPreferences.Editor
