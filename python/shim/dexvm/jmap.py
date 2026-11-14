"""java.util maps and sets

HashMap answers lookups from a python dict and reproduces the iteration order of the jdk table: the entries are
ordered by bucket index (the spread hash masked with the table length) and, inside a bucket, by insertion. the table
length follows the jdk growth rule (doubling when the size passes 0.75 of it, never shrinking), so a program that
prints a HashMap or a HashSet shows what it shows on a runtime. a bucket that the jdk would turn into a tree (eight
collisions in a table of 64 or more) keeps list order here. Hashtable shares this implementation and its order"""

import functools

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import _BOX_TYPES, compare_natural, compare_with, jequals, jhash, jstring
from .jlang import Double, Float, Object
from .jutil import (AbstractCollection, ImmutableList, PyIterator, check_nonnull, iterate, no_such_element, ioobe,
                    to_array, unsupported, ArrayList)
from .jutil import Collection, Iterator, NavigableSet, Set, SortedSet


@host_class("java.util.Map", interface=True)
class Map:
    __slots__ = ()

    @jstatic("of", "()Ljava/util/Map;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/Map;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/Map;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/Map;")
    def of(*pairs):
        result = LinkedHashMap()
        for index in range(0, len(pairs), 2):
            check_nonnull(pairs[index])
            check_nonnull(pairs[index + 1])
            if result.containsKey(pairs[index]):
                runtime.throw_new("java.lang.IllegalArgumentException", "duplicate key: " + jstring(pairs[index]))
            result.put(pairs[index], pairs[index + 1])
        return ImmutableMap(result)

    @jstatic("entry", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/Map$Entry;")
    def entry(key, value):
        return SimpleEntry(check_nonnull(key), check_nonnull(value))

    @jstatic("copyOf", "(Ljava/util/Map;)Ljava/util/Map;")
    def copyOf(other):
        return ImmutableMap(LinkedHashMap(other))


@host_class("java.util.Map$Entry", interface=True)
class MapEntry:
    __slots__ = ()


@host_class("java.util.SortedMap", interface=True, interfaces=("java.util.Map",))
class SortedMap(Map):
    __slots__ = ()


@host_class("java.util.NavigableMap", interface=True, interfaces=("java.util.SortedMap",))
class NavigableMap(SortedMap):
    __slots__ = ()


@host_class("java.util.AbstractMap$SimpleEntry", interfaces=("java.util.Map$Entry",))
class SimpleEntry(Object):
    __slots__ = ("key", "value")

    def __init__(self, key=None, value=None):
        self.key = key
        self.value = value

    @jmethod("<init>", "(Ljava/lang/Object;Ljava/lang/Object;)V")
    def _init(self, key, value):
        self.key = key
        self.value = value

    @jmethod("<init>", "(Ljava/util/Map$Entry;)V")
    def _init_entry(self, entry):
        self.key = entry.getKey()
        self.value = entry.getValue()

    @jmethod("getKey", "()Ljava/lang/Object;")
    def getKey(self):
        return self.key

    @jmethod("getValue", "()Ljava/lang/Object;")
    def getValue(self):
        return self.value

    @jmethod("setValue", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def setValue(self, value):
        old = self.value
        self.value = value
        return old

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, (SimpleEntry, Entry)) and jequals(self.key, other.getKey()) \
            and jequals(self.value, other.getValue()) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return jhash(self.key) ^ jhash(self.value)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return jstring(self.key) + "=" + jstring(self.value)


host_class("java.util.AbstractMap$SimpleImmutableEntry", interfaces=("java.util.Map$Entry",))(
    type("SimpleImmutableEntry", (SimpleEntry,), {"__slots__": (), "setValue": lambda self, value: unsupported()}))


class Entry(SimpleEntry):
    """an entry of a hash or tree map; setValue writes through to the map"""
    __slots__ = ("hash", "seq")

    def __init__(self, key, value, hash_=0, seq=0):
        SimpleEntry.__init__(self, key, value)
        self.hash = hash_
        self.seq = seq


host_class("java.util.HashMap$Node", interfaces=("java.util.Map$Entry",))(Entry)

_overrides = {}


def _key_of(key):
    """the python dict key that stands for a java key: strings and boxes map to their value, an object whose class overrides equals or hashCode is wrapped"""
    cls = key.__class__
    if cls is str or key is None:
        return key
    if cls in _BOX_TYPES:
        value = key.value
        if cls is Float or cls is Double:
            return (cls, runtime.double_bits(value) if value == value else 0x7FF8000000000000)
        return (cls, value)
    custom = _overrides.get(cls)
    if custom is None:
        custom = _overrides[cls] = (getattr(cls, "equals", None) is not Object.equals
                                    or getattr(cls, "hashCode", None) is not Object.hashCode)
    return _JavaKey(key) if custom else key


class _JavaKey:
    __slots__ = ("key", "hash")

    def __init__(self, key):
        self.key = key
        self.hash = key.hashCode()

    def __hash__(self):
        return self.hash

    def __eq__(self, other):
        return other.__class__ is _JavaKey and jequals(self.key, other.key)


def _spread(h):
    h &= 0xFFFFFFFF
    return h ^ (h >> 16)


def _table_size_for(capacity):
    if capacity <= 1:
        return 1
    return 1 << (capacity - 1).bit_length()


@host_class("java.util.AbstractMap", interfaces=("java.util.Map",))
class AbstractMap(Map, Object):
    """the generic algorithms over entrySet()"""

    def __init__(self):
        pass

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("size", "()I")
    def size(self):
        return self.entrySet().size()

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 1 if self.size() == 0 else 0

    def _entries_list(self):
        return list(iterate(self.entrySet()))

    @jmethod("containsKey", "(Ljava/lang/Object;)Z")
    def containsKey(self, key):
        return 1 if any(jequals(key, e.getKey()) for e in self._entries_list()) else 0

    @jmethod("containsValue", "(Ljava/lang/Object;)Z")
    def containsValue(self, value):
        return 1 if any(jequals(value, e.getValue()) for e in self._entries_list()) else 0

    @jmethod("get", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def get(self, key):
        for entry in self._entries_list():
            if jequals(key, entry.getKey()):
                return entry.getValue()
        return None

    @jmethod("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def put(self, key, value):
        unsupported()

    @jmethod("remove", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def remove(self, key):
        iterator = self.entrySet().iterator()
        while iterator.hasNext():
            entry = iterator.next()
            if jequals(key, entry.getKey()):
                value = entry.getValue()
                iterator.remove()
                return value
        return None

    @jmethod("putAll", "(Ljava/util/Map;)V")
    def putAll(self, other):
        for entry in list(iterate(other.entrySet())):
            self.put(entry.getKey(), entry.getValue())

    @jmethod("clear", "()V")
    def clear(self):
        self.entrySet().clear()

    @jmethod("keySet", "()Ljava/util/Set;")
    def keySet(self):
        return _KeyView(self)

    @jmethod("values", "()Ljava/util/Collection;")
    def values(self):
        return _ValuesView(self)

    @jmethod("getOrDefault", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def getOrDefault(self, key, default):
        if self.containsKey(key):
            return self.get(key)
        return default

    @jmethod("putIfAbsent", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def putIfAbsent(self, key, value):
        current = self.get(key)
        if current is None:
            self.put(key, value)
        return current

    @jmethod("computeIfAbsent", "(Ljava/lang/Object;Ljava/util/function/Function;)Ljava/lang/Object;")
    def computeIfAbsent(self, key, function):
        current = self.get(key)
        if current is None:
            value = function.apply(key)
            if value is not None:
                self.put(key, value)
            return value
        return current

    @jmethod("computeIfPresent", "(Ljava/lang/Object;Ljava/util/function/BiFunction;)Ljava/lang/Object;")
    def computeIfPresent(self, key, function):
        current = self.get(key)
        if current is None:
            return None
        value = function.apply(key, current)
        if value is None:
            self.remove(key)
        else:
            self.put(key, value)
        return value

    @jmethod("compute", "(Ljava/lang/Object;Ljava/util/function/BiFunction;)Ljava/lang/Object;")
    def compute(self, key, function):
        current = self.get(key)
        value = function.apply(key, current)
        if value is None:
            if current is not None or self.containsKey(key):
                self.remove(key)
            return None
        self.put(key, value)
        return value

    @jmethod("merge", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/util/function/BiFunction;)Ljava/lang/Object;")
    def merge(self, key, value, function):
        check_nonnull(value)
        current = self.get(key)
        result = value if current is None else function.apply(current, value)
        if result is None:
            self.remove(key)
        else:
            self.put(key, result)
        return result

    @jmethod("forEach", "(Ljava/util/function/BiConsumer;)V")
    def forEach(self, action):
        check_nonnull(action)
        for entry in self._entries_list():
            action.accept(entry.getKey(), entry.getValue())

    @jmethod("replaceAll", "(Ljava/util/function/BiFunction;)V")
    def replaceAll(self, function):
        for entry in self._entries_list():
            entry.setValue(function.apply(entry.getKey(), entry.getValue()))

    @jmethod("replace", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def replace(self, key, value):
        if self.containsKey(key):
            return self.put(key, value)
        return None

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        if other is self:
            return 1
        if not hasattr(other, "entrySet") or other.size() != self.size():
            return 0
        for entry in self._entries_list():
            key = entry.getKey()
            if not other.containsKey(key) or not jequals(entry.getValue(), other.get(key)):
                return 0
        return 1

    @jmethod("hashCode", "()I")
    def hashCode(self):
        total = 0
        for entry in self._entries_list():
            total += jhash(entry.getKey()) ^ jhash(entry.getValue())
        return runtime.wrap32(total)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        parts = []
        for entry in self._entries_list():
            key, value = entry.getKey(), entry.getValue()
            parts.append("%s=%s" % ("(this Map)" if key is self else jstring(key),
                                    "(this Map)" if value is self else jstring(value)))
        return "{" + ", ".join(parts) + "}"


class _View(AbstractCollection):
    """a live view of a map: a key set, the values, the entries"""

    def __init__(self, owner):
        self._owner = owner
        self.modCount = 0

    def size(self):
        return self._owner.size()

    def clear(self):
        self._owner.clear()

    def iterator(self):
        owner = self._owner
        return PyIterator(self._items(), self._remover)


class _KeyView(_View):
    def _items(self):
        return [e.getKey() for e in self._owner._entries_list()]

    def _remover(self, key):
        self._owner.remove(key)

    def contains(self, key):
        return self._owner.containsKey(key)

    def remove(self, key):
        had = self._owner.containsKey(key)
        self._owner.remove(key)
        return 1 if had else 0

    def equals(self, other):
        return AbstractSet.equals(self, other)

    def hashCode(self):
        return AbstractSet.hashCode(self)


class _ValuesView(_View):
    def _items(self):
        return [e.getValue() for e in self._owner._entries_list()]

    def _remover(self, value):
        iterator = self._owner.entrySet().iterator()
        while iterator.hasNext():
            if iterator.next().getValue() is value:
                iterator.remove()
                return

    def contains(self, value):
        return self._owner.containsValue(value)


class _EntryView(_View):
    def _items(self):
        return self._owner._entries_list()

    def _remover(self, entry):
        self._owner.remove(entry.getKey())

    def contains(self, entry):
        key = entry.getKey()
        return 1 if self._owner.containsKey(key) and jequals(self._owner.get(key), entry.getValue()) else 0

    def remove(self, entry):
        if self.contains(entry):
            self._owner.remove(entry.getKey())
            return 1
        return 0

    def equals(self, other):
        return AbstractSet.equals(self, other)

    def hashCode(self):
        return AbstractSet.hashCode(self)


for _view in (_KeyView, _ValuesView, _EntryView):
    host_class("java.util.HashMap$" + _view.__name__.strip("_"),
               interfaces=("java.util.Set",) if _view is not _ValuesView else ("java.util.Collection",))(_view)


@host_class("java.util.AbstractSet", interfaces=("java.util.Set",))
class AbstractSet(AbstractCollection, Set):
    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        if other is self:
            return 1
        if not hasattr(other, "containsAll") or other.size() != self.size():
            return 0
        return 1 if self.containsAll(other) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(sum(jhash(item) for item in iterate(self)))

    @jmethod("removeAll", "(Ljava/util/Collection;)Z")
    def removeAll(self, other):
        check_nonnull(other)
        changed = 0
        for item in list(iterate(self)):
            if other.contains(item):
                self.remove(item)
                changed = 1
        return changed


@host_class("java.util.HashMap", interfaces=("java.util.Map", "java.lang.Cloneable", "java.io.Serializable"))
class HashMap(AbstractMap):
    _ordered_cache = None
    _linked = False
    _access_order = False

    def __init__(self, first=None, second=None):
        self._d = {}
        self._seq = 0
        self._cap = 0
        self._load = 0.75
        self._initial = 0
        self.modCount = 0
        self._ordered_cache = None
        if isinstance(first, int) and not isinstance(first, bool):
            if first < 0:
                runtime.throw_new("java.lang.IllegalArgumentException", "Illegal initial capacity: %d" % first)
            self._initial = _table_size_for(first)
            if second is not None:
                self._load = second
        elif first is not None:
            size = first.size()
            if size > 0:
                self._initial = _table_size_for(int(size / self._load + 1.0))
            for entry in iterate(first.entrySet()):
                self._put(entry.getKey(), entry.getValue())

    @jmethod("<init>", "()V")
    def _init(self):
        HashMap.__init__(self)

    @jmethod("<init>", "(I)V")
    def _init_capacity(self, capacity):
        HashMap.__init__(self, capacity)

    @jmethod("<init>", "(IF)V")
    def _init_load(self, capacity, load):
        HashMap.__init__(self, capacity, load)

    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init_map(self, other):
        HashMap.__init__(self, check_nonnull(other))

    def _grow_for(self, size):
        if self._cap == 0:
            self._cap = self._initial or 16
        while size > int(self._cap * self._load):
            self._cap *= 2

    def _put(self, key, value, only_if_absent=False, head=False):
        nk = _key_of(key)
        entry = self._d.get(nk)
        if entry is not None:
            old = entry.value
            if not only_if_absent or old is None:
                entry.value = value
            if self._access_order:
                self._touch(nk, entry)
            return old
        self.modCount += 1
        # put appends to the bucket; merge, compute and computeIfAbsent link the new node in front of it
        self._seq += 1
        self._d[nk] = Entry(key, value, _spread(jhash(key)), -self._seq if head else self._seq)
        self._ordered_cache = None
        self._grow_for(len(self._d))
        return None

    def _touch(self, nk, entry):
        pass

    def _ordered(self):
        cache = self._ordered_cache
        if cache is None:
            mask = (self._cap or 16) - 1
            cache = self._ordered_cache = sorted(self._d.values(), key=lambda e: (e.hash & mask, e.seq))
        return cache

    def _entries_list(self):
        return list(self._ordered())

    @jmethod("size", "()I")
    def size(self):
        return len(self._d)

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 0 if self._d else 1

    @jmethod("get", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def get(self, key):
        entry = self._d.get(_key_of(key))
        if entry is None:
            return None
        if self._access_order:
            self._touch(_key_of(key), entry)
        return entry.value

    @jmethod("containsKey", "(Ljava/lang/Object;)Z")
    def containsKey(self, key):
        return 1 if _key_of(key) in self._d else 0

    @jmethod("containsValue", "(Ljava/lang/Object;)Z")
    def containsValue(self, value):
        return 1 if any(jequals(value, e.value) for e in self._d.values()) else 0

    @jmethod("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def put(self, key, value):
        return self._put(key, value)

    @jmethod("putIfAbsent", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def putIfAbsent(self, key, value):
        return self._put(key, value, True)

    @jmethod("getOrDefault", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def getOrDefault(self, key, default):
        entry = self._d.get(_key_of(key))
        return default if entry is None else entry.value

    @jmethod("remove", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def remove(self, key, *rest):
        if rest:
            return self.remove_pair(key, rest[0])
        nk = _key_of(key)
        entry = self._d.get(nk)
        if entry is None:
            return None
        del self._d[nk]
        self.modCount += 1
        self._ordered_cache = None
        return entry.value

    @jmethod("remove", "(Ljava/lang/Object;Ljava/lang/Object;)Z")
    def remove_pair(self, key, value):
        nk = _key_of(key)
        entry = self._d.get(nk)
        if entry is None or not jequals(entry.value, value):
            return 0
        del self._d[nk]
        self.modCount += 1
        self._ordered_cache = None
        return 1

    @jmethod("clear", "()V")
    def clear(self):
        self.modCount += 1
        self._d.clear()
        self._ordered_cache = None

    @jmethod("putAll", "(Ljava/util/Map;)V")
    def putAll(self, other):
        size = check_nonnull(other).size()
        if size > 0:
            if self._cap == 0:
                self._initial = max(self._initial, _table_size_for(int(size / self._load + 1.0)))
            elif size > int(self._cap * self._load):
                self._cap *= 2
        for entry in list(iterate(other.entrySet())):
            self._put(entry.getKey(), entry.getValue())

    @jmethod("entrySet", "()Ljava/util/Set;")
    def entrySet(self):
        return _EntryView(self)

    @jmethod("keySet", "()Ljava/util/Set;")
    def keySet(self):
        return _KeyView(self)

    @jmethod("values", "()Ljava/util/Collection;")
    def values(self):
        return _ValuesView(self)

    @jmethod("computeIfAbsent", "(Ljava/lang/Object;Ljava/util/function/Function;)Ljava/lang/Object;")
    def computeIfAbsent(self, key, function):
        entry = self._d.get(_key_of(key))
        if entry is not None and entry.value is not None:
            return entry.value
        expected = self.modCount
        value = function.apply(key)
        if self.modCount != expected:
            runtime.throw_new("java.util.ConcurrentModificationException", None)
        if value is not None:
            self._put(key, value, head=True)
        return value

    @jmethod("merge", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/util/function/BiFunction;)Ljava/lang/Object;")
    def merge(self, key, value, function):
        check_nonnull(value)
        check_nonnull(function)
        entry = self._d.get(_key_of(key))
        if entry is None:
            self._put(key, value, head=True)
            return value
        result = value if entry.value is None else function.apply(entry.value, value)
        if result is None:
            self.remove(key)
        else:
            entry.value = result
            if self._access_order:
                self._touch(_key_of(key), entry)
        return result

    @jmethod("compute", "(Ljava/lang/Object;Ljava/util/function/BiFunction;)Ljava/lang/Object;")
    def compute(self, key, function):
        check_nonnull(function)
        entry = self._d.get(_key_of(key))
        result = function.apply(key, None if entry is None else entry.value)
        if entry is not None:
            if result is None:
                self.remove(key)
            else:
                entry.value = result
        elif result is not None:
            self._put(key, result, head=True)
        return result

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        copy = type(self).__new__(type(self))
        HashMap.__init__(copy)
        copy._cap = self._cap
        copy._initial = self._initial
        copy._load = self._load
        for entry in self._ordered():
            copy._put(entry.key, entry.value)
        return copy

    @jmethod("forEach", "(Ljava/util/function/BiConsumer;)V")
    def forEach(self, action):
        check_nonnull(action)
        expected = self.modCount
        for entry in self._entries_list():
            action.accept(entry.key, entry.value)
        if self.modCount != expected:
            runtime.throw_new("java.util.ConcurrentModificationException", None)


@host_class("java.util.LinkedHashMap")
class LinkedHashMap(HashMap):
    """entries in insertion order, or in access order when the constructor asks for it"""

    def __init__(self, first=None, second=None, access_order=False):
        self._access_order = bool(access_order)
        HashMap.__init__(self, first, second)

    @jmethod("<init>", "()V")
    def _init0(self):
        LinkedHashMap.__init__(self)

    @jmethod("<init>", "(I)V")
    def _init1(self, capacity):
        LinkedHashMap.__init__(self, capacity)

    @jmethod("<init>", "(IF)V")
    def _init2(self, capacity, load):
        LinkedHashMap.__init__(self, capacity, load)

    @jmethod("<init>", "(IFZ)V")
    def _init3(self, capacity, load, access_order):
        LinkedHashMap.__init__(self, capacity, load, access_order)

    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init_map(self, other):
        LinkedHashMap.__init__(self, check_nonnull(other))

    def _ordered(self):
        return list(self._d.values())

    def _touch(self, nk, entry):
        del self._d[nk]
        self._d[nk] = entry

    def _put(self, key, value, only_if_absent=False, head=False):
        before = len(self._d)
        old = HashMap._put(self, key, value, only_if_absent)
        if len(self._d) > before:
            eldest = next(iter(self._d.values()))
            if self.removeEldestEntry(eldest):
                self.remove(eldest.key)
        return old

    @jmethod("removeEldestEntry", "(Ljava/util/Map$Entry;)Z")
    def removeEldestEntry(self, eldest):
        return 0

    @jmethod("eldest", "()Ljava/util/Map$Entry;")
    def eldest(self):
        return next(iter(self._d.values()), None)


host_class("java.util.Hashtable", interfaces=("java.util.Map",))(type("Hashtable", (HashMap,), {}))
host_class("java.util.concurrent.ConcurrentHashMap", interfaces=("java.util.Map",))(type("ConcurrentHashMap", (HashMap,), {}))
host_class("java.util.WeakHashMap", interfaces=("java.util.Map",))(type("WeakHashMap", (HashMap,), {}))
host_class("java.util.IdentityHashMap", interfaces=("java.util.Map",))(type("IdentityHashMap", (HashMap,), {}))


class ImmutableMap(LinkedHashMap):
    """Map.of and the unmodifiable views"""

    def __init__(self, source):
        LinkedHashMap.__init__(self)
        for entry in iterate(source.entrySet()):
            LinkedHashMap._put(self, entry.getKey(), entry.getValue())

    put = remove = clear = putAll = putIfAbsent = computeIfAbsent = merge = compute = replaceAll = (
        lambda self, *args: unsupported())


host_class("java.util.ImmutableCollections$MapN", interfaces=("java.util.Map",))(ImmutableMap)


@host_class("java.util.TreeMap", interfaces=("java.util.NavigableMap", "java.lang.Cloneable"))
class TreeMap(AbstractMap, NavigableMap):
    """sorted by the comparator or the natural order; keys equal by compare are one key"""

    def __init__(self, source=None):
        self._keys = []
        self._entries = []
        self._cmp = None
        self.modCount = 0
        if source is None:
            return
        if hasattr(source, "compare") and not hasattr(source, "entrySet"):
            self._cmp = source
        else:
            if isinstance(source, TreeMap):
                self._cmp = source._cmp
            for entry in iterate(source.entrySet()):
                self.put(entry.getKey(), entry.getValue())

    @jmethod("<init>", "()V")
    def _init(self):
        TreeMap.__init__(self)

    @jmethod("<init>", "(Ljava/util/Comparator;)V")
    def _init_cmp(self, comparator):
        TreeMap.__init__(self, comparator)

    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init_map(self, other):
        TreeMap.__init__(self, check_nonnull(other))

    def _compare(self, a, b):
        return compare_with(self._cmp, a, b)

    def _search(self, key):
        """(index, found): the position of the key or where it would go"""
        entries = self._entries
        low, high = 0, len(entries)
        while low < high:
            middle = (low + high) >> 1
            order = self._compare(entries[middle].key, key)
            if order < 0:
                low = middle + 1
            elif order > 0:
                high = middle
            else:
                return middle, True
        return low, False

    def _entries_list(self):
        return list(self._entries)

    def size(self):
        return len(self._entries)

    def get(self, key):
        if key is None and self._cmp is None:
            runtime.npe()
        if not self._entries:
            return None
        index, found = self._search(key)
        return self._entries[index].value if found else None

    def containsKey(self, key):
        if key is None and self._cmp is None:
            runtime.npe()
        return 1 if self._entries and self._search(key)[1] else 0

    def put(self, key, value):
        if not self._entries:
            self._compare(key, key)
        index, found = self._search(key)
        if found:
            old = self._entries[index].value
            self._entries[index].value = value
            return old
        self.modCount += 1
        self._entries.insert(index, Entry(key, value))
        return None

    def remove(self, key):
        if not self._entries:
            return None
        index, found = self._search(key)
        if not found:
            return None
        self.modCount += 1
        return self._entries.pop(index).value

    def clear(self):
        self.modCount += 1
        self._entries.clear()

    def entrySet(self):
        return _EntryView(self)

    def containsValue(self, value):
        return 1 if any(jequals(value, e.value) for e in self._entries) else 0

    def comparator(self):
        return self._cmp

    def _entry_at(self, index):
        return self._entries[index] if 0 <= index < len(self._entries) else None

    def _snapshot(self, entry):
        return None if entry is None else SimpleEntry(entry.key, entry.value)

    @jmethod("firstKey", "()Ljava/lang/Object;")
    def firstKey(self):
        if not self._entries:
            no_such_element()
        return self._entries[0].key

    @jmethod("lastKey", "()Ljava/lang/Object;")
    def lastKey(self):
        if not self._entries:
            no_such_element()
        return self._entries[-1].key

    @jmethod("firstEntry", "()Ljava/util/Map$Entry;")
    def firstEntry(self):
        return self._snapshot(self._entry_at(0))

    @jmethod("lastEntry", "()Ljava/util/Map$Entry;")
    def lastEntry(self):
        return self._snapshot(self._entry_at(len(self._entries) - 1))

    @jmethod("pollFirstEntry", "()Ljava/util/Map$Entry;")
    def pollFirstEntry(self):
        if not self._entries:
            return None
        self.modCount += 1
        entry = self._entries.pop(0)
        return SimpleEntry(entry.key, entry.value)

    @jmethod("pollLastEntry", "()Ljava/util/Map$Entry;")
    def pollLastEntry(self):
        if not self._entries:
            return None
        self.modCount += 1
        entry = self._entries.pop()
        return SimpleEntry(entry.key, entry.value)

    def _floor(self, key):
        index, found = self._search(key)
        return index if found else index - 1

    def _ceiling(self, key):
        return self._search(key)[0]

    def _lower(self, key):
        return self._search(key)[0] - 1

    def _higher(self, key):
        index, found = self._search(key)
        return index + 1 if found else index

    @jmethod("floorKey", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def floorKey(self, key):
        entry = self._entry_at(self._floor(key))
        return None if entry is None else entry.key

    @jmethod("ceilingKey", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def ceilingKey(self, key):
        entry = self._entry_at(self._ceiling(key))
        return None if entry is None else entry.key

    @jmethod("lowerKey", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def lowerKey(self, key):
        entry = self._entry_at(self._lower(key))
        return None if entry is None else entry.key

    @jmethod("higherKey", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def higherKey(self, key):
        entry = self._entry_at(self._higher(key))
        return None if entry is None else entry.key

    @jmethod("floorEntry", "(Ljava/lang/Object;)Ljava/util/Map$Entry;")
    def floorEntry(self, key):
        return self._snapshot(self._entry_at(self._floor(key)))

    @jmethod("ceilingEntry", "(Ljava/lang/Object;)Ljava/util/Map$Entry;")
    def ceilingEntry(self, key):
        return self._snapshot(self._entry_at(self._ceiling(key)))

    @jmethod("lowerEntry", "(Ljava/lang/Object;)Ljava/util/Map$Entry;")
    def lowerEntry(self, key):
        return self._snapshot(self._entry_at(self._lower(key)))

    @jmethod("higherEntry", "(Ljava/lang/Object;)Ljava/util/Map$Entry;")
    def higherEntry(self, key):
        return self._snapshot(self._entry_at(self._higher(key)))

    def _slice(self, low, high):
        copy = TreeMap(self._cmp)
        copy._entries = [Entry(e.key, e.value) for e in self._entries[max(low, 0):max(high, 0)]]
        return copy

    @jmethod("headMap", "(Ljava/lang/Object;)Ljava/util/SortedMap;")
    @jmethod("headMap", "(Ljava/lang/Object;Z)Ljava/util/NavigableMap;")
    def headMap(self, key, inclusive=False):
        return self._slice(0, self._higher(key) if inclusive else self._ceiling(key))

    @jmethod("tailMap", "(Ljava/lang/Object;)Ljava/util/SortedMap;")
    @jmethod("tailMap", "(Ljava/lang/Object;Z)Ljava/util/NavigableMap;")
    def tailMap(self, key, inclusive=True):
        return self._slice(self._ceiling(key) if inclusive else self._higher(key), len(self._entries))

    @jmethod("subMap", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/SortedMap;")
    @jmethod("subMap", "(Ljava/lang/Object;ZLjava/lang/Object;Z)Ljava/util/NavigableMap;")
    def subMap(self, *args):
        if len(args) == 2:
            low_key, high_key, low_inc, high_inc = args[0], args[1], True, False
        else:
            low_key, low_inc, high_key, high_inc = args
        low = self._ceiling(low_key) if low_inc else self._higher(low_key)
        high = self._higher(high_key) if high_inc else self._ceiling(high_key)
        return self._slice(low, high)

    @jmethod("descendingMap", "()Ljava/util/NavigableMap;")
    def descendingMap(self):
        copy = TreeMap(Comparator_reverse(self._cmp))
        copy._entries = [Entry(e.key, e.value) for e in reversed(self._entries)]
        return copy

    @jmethod("navigableKeySet", "()Ljava/util/NavigableSet;")
    def navigableKeySet(self):
        return TreeSet(self.keySet(), self._cmp)

    @jmethod("descendingKeySet", "()Ljava/util/NavigableSet;")
    def descendingKeySet(self):
        return self.descendingMap().navigableKeySet()

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return TreeMap(self)


def Comparator_reverse(comparator):
    from .jfunc import Comparator
    return Comparator.reverseOrder() if comparator is None else Comparator.reversed(comparator)


@host_class("java.util.HashSet", interfaces=("java.util.Set", "java.lang.Cloneable", "java.io.Serializable"))
class HashSet(AbstractSet):
    _map_class = HashMap
    _PRESENT = object()

    def __init__(self, first=None, load=None):
        if first is None or isinstance(first, int):
            self._m = self._map_class(first, load) if first is not None else self._map_class()
        else:
            self._m = self._map_class(max(int(first.size() / 0.75) + 1, 16))
            for item in iterate(first):
                self._m._put(item, HashSet._PRESENT)
        self.modCount = 0

    @jmethod("<init>", "()V")
    def _init(self):
        HashSet.__init__(self)

    @jmethod("<init>", "(I)V")
    def _init_capacity(self, capacity):
        HashSet.__init__(self, capacity)

    @jmethod("<init>", "(IF)V")
    def _init_load(self, capacity, load):
        HashSet.__init__(self, capacity, load)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        HashSet.__init__(self, check_nonnull(source))

    def size(self):
        return len(self._m._d)

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        return 1 if self._m._put(item, HashSet._PRESENT) is None else 0

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        return self._m.containsKey(item)

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove(self, item):
        return 1 if self._m.remove(item) is not None else 0

    @jmethod("clear", "()V")
    def clear(self):
        self._m.clear()

    def iterator(self):
        return PyIterator([e.key for e in self._m._ordered()], self.remove)

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        copy = type(self).__new__(type(self))
        copy._m = self._m.clone()
        copy.modCount = 0
        return copy


@host_class("java.util.LinkedHashSet")
class LinkedHashSet(HashSet):
    _map_class = LinkedHashMap


host_class("java.util.concurrent.CopyOnWriteArraySet", interfaces=("java.util.Set",))(
    type("CopyOnWriteArraySet", (LinkedHashSet,), {}))


@host_class("java.util.TreeSet", interfaces=("java.util.NavigableSet", "java.lang.Cloneable"))
class TreeSet(AbstractSet, NavigableSet):
    def __init__(self, source=None, comparator=None):
        self._m = TreeMap(comparator)
        self.modCount = 0
        if source is None:
            return
        if hasattr(source, "compare") and not hasattr(source, "iterator"):
            self._m = TreeMap(source)
        else:
            if isinstance(source, TreeSet) and comparator is None:
                self._m = TreeMap(source._m._cmp)
            for item in iterate(source):
                self._m.put(item, HashSet._PRESENT)

    @jmethod("<init>", "()V")
    def _init(self):
        TreeSet.__init__(self)

    @jmethod("<init>", "(Ljava/util/Comparator;)V")
    def _init_cmp(self, comparator):
        TreeSet.__init__(self, comparator)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        TreeSet.__init__(self, check_nonnull(source))

    def size(self):
        return len(self._m._entries)

    def add(self, item):
        return 1 if self._m.put(item, HashSet._PRESENT) is None else 0

    def contains(self, item):
        return self._m.containsKey(item)

    def remove(self, item):
        return 1 if self._m.remove(item) is not None else 0

    def clear(self):
        self._m.clear()

    def iterator(self):
        return PyIterator([e.key for e in self._m._entries], self.remove)

    @jmethod("first", "()Ljava/lang/Object;")
    def first(self):
        return self._m.firstKey()

    @jmethod("last", "()Ljava/lang/Object;")
    def last(self):
        return self._m.lastKey()

    @jmethod("pollFirst", "()Ljava/lang/Object;")
    def pollFirst(self):
        entry = self._m.pollFirstEntry()
        return None if entry is None else entry.key

    @jmethod("pollLast", "()Ljava/lang/Object;")
    def pollLast(self):
        entry = self._m.pollLastEntry()
        return None if entry is None else entry.key

    @jmethod("floor", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def floor(self, item):
        return self._m.floorKey(item)

    @jmethod("ceiling", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def ceiling(self, item):
        return self._m.ceilingKey(item)

    @jmethod("lower", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def lower(self, item):
        return self._m.lowerKey(item)

    @jmethod("higher", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def higher(self, item):
        return self._m.higherKey(item)

    @jmethod("comparator", "()Ljava/util/Comparator;")
    def comparator(self):
        return self._m._cmp

    def _wrap(self, tree_map):
        result = TreeSet(tree_map._cmp)
        result._m = tree_map
        return result

    @jmethod("headSet", "(Ljava/lang/Object;)Ljava/util/SortedSet;")
    @jmethod("headSet", "(Ljava/lang/Object;Z)Ljava/util/NavigableSet;")
    def headSet(self, item, inclusive=False):
        return self._wrap(self._m.headMap(item, inclusive))

    @jmethod("tailSet", "(Ljava/lang/Object;)Ljava/util/SortedSet;")
    @jmethod("tailSet", "(Ljava/lang/Object;Z)Ljava/util/NavigableSet;")
    def tailSet(self, item, inclusive=True):
        return self._wrap(self._m.tailMap(item, inclusive))

    @jmethod("subSet", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/SortedSet;")
    @jmethod("subSet", "(Ljava/lang/Object;ZLjava/lang/Object;Z)Ljava/util/NavigableSet;")
    def subSet(self, *args):
        return self._wrap(self._m.subMap(*args))

    @jmethod("descendingSet", "()Ljava/util/NavigableSet;")
    def descendingSet(self):
        return self._wrap(self._m.descendingMap())

    @jmethod("descendingIterator", "()Ljava/util/Iterator;")
    def descendingIterator(self):
        return PyIterator([e.key for e in reversed(self._m._entries)], self.remove)

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return TreeSet(self)
