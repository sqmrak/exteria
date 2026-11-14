"""java.util helpers: Collections, Arrays, Objects, Optional, Random, StringJoiner, UUID

Random is the 48 bit linear congruential generator of the jdk with its exact output scaling, so a seeded sequence is the
sequence a runtime produces"""

import functools
import hashlib
import math
import os
import threading
import time

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import Comparator, compare_natural, compare_with, jequals, jhash, jstring, _Lambda
from .jlang import Object, _StringImpl, _cs, float_to_string
from .jmap import ArrayList, HashMap, ImmutableList, ImmutableMap, LinkedHashMap, TreeMap
from .jmap import HashSet, LinkedHashSet, TreeSet
from .jutil import (AbstractList, ListItr, PyIterator, check_nonnull, iterate, ioobe, no_such_element, to_array,
                    unsupported, _sort)


def _numeric_code(array):
    return array.jtype.descriptor[1]


def element_text(array, value):
    code = _numeric_code(array)
    if code == "Z":
        return "true" if value else "false"
    if code == "C":
        return chr(value)
    if code == "F":
        return float_to_string(value, True)
    if code == "D":
        return float_to_string(value, False)
    if code in "BSIJ":
        return str(value)
    return jstring(value)


def element_hash(array, value):
    code = _numeric_code(array)
    if code == "Z":
        return 1231 if value else 1237
    if code in "BSCI":
        return value
    if code == "J":
        return runtime.wrap32(value ^ (value & 0xFFFFFFFFFFFFFFFF) >> 32)
    if code == "F":
        return 0x7FC00000 if value != value else runtime.float_bits(value)
    if code == "D":
        bits = 0x7FF8000000000000 if value != value else runtime.double_bits(value)
        return runtime.wrap32(bits ^ (bits & 0xFFFFFFFFFFFFFFFF) >> 32)
    return jhash(value)


def _check_range(length, start, end):
    if start > end:
        runtime.throw_new("java.lang.IllegalArgumentException", "fromIndex(%d) > toIndex(%d)" % (start, end))
    if start < 0:
        runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "Array index out of range: %d" % start)
    if end > length:
        runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "Array index out of range: %d" % end)


@host_class("java.util.Arrays", final=True)
class Arrays(Object):
    @jstatic("stream", "([Ljava/lang/Object;)Ljava/util/stream/Stream;")
    @jstatic("stream", "([I)Ljava/util/stream/IntStream;")
    @jstatic("stream", "([J)Ljava/util/stream/LongStream;")
    @jstatic("stream", "([D)Ljava/util/stream/DoubleStream;")
    @jstatic("stream", "([Ljava/lang/Object;II)Ljava/util/stream/Stream;")
    @jstatic("stream", "([III)Ljava/util/stream/IntStream;")
    def stream(array, start=0, end=None):
        from .jstream import BaseStream
        kind = {"I": "int", "J": "long", "D": "double"}.get(array.jtype.descriptor[1], "obj")
        return BaseStream.from_items(array[start:end], kind)

    @jstatic("asList", "([Ljava/lang/Object;)Ljava/util/List;")
    def asList(array):
        return ArrayAsList(check_nonnull(array))

    @jstatic("toString", "([I)Ljava/lang/String;")
    @jstatic("toString", "([J)Ljava/lang/String;")
    @jstatic("toString", "([B)Ljava/lang/String;")
    @jstatic("toString", "([S)Ljava/lang/String;")
    @jstatic("toString", "([C)Ljava/lang/String;")
    @jstatic("toString", "([Z)Ljava/lang/String;")
    @jstatic("toString", "([F)Ljava/lang/String;")
    @jstatic("toString", "([D)Ljava/lang/String;")
    @jstatic("toString", "([Ljava/lang/Object;)Ljava/lang/String;")
    def toString(array):
        if array is None:
            return "null"
        return "[" + ", ".join(element_text(array, v) for v in array) + "]"

    @jstatic("deepToString", "([Ljava/lang/Object;)Ljava/lang/String;")
    def deepToString(array):
        if array is None:
            return "null"

        def render(value):
            if isinstance(value, runtime.JArray):
                if value.jtype.component.isPrimitive():
                    return Arrays.toString(value)
                return "[" + ", ".join(render(v) for v in value) + "]"
            return jstring(value)
        return render(array)

    @jstatic("copyOf", "([II)[I")
    @jstatic("copyOf", "([JI)[J")
    @jstatic("copyOf", "([BI)[B")
    @jstatic("copyOf", "([SI)[S")
    @jstatic("copyOf", "([CI)[C")
    @jstatic("copyOf", "([ZI)[Z")
    @jstatic("copyOf", "([FI)[F")
    @jstatic("copyOf", "([DI)[D")
    @jstatic("copyOf", "([Ljava/lang/Object;I)[Ljava/lang/Object;")
    def copyOf(array, length):
        if length < 0:
            runtime.throw_new("java.lang.NegativeArraySizeException", str(length))
        result = runtime.new_array(array.jtype, length)
        count = min(length, len(array))
        result[:count] = array[:count]
        return result

    @jstatic("copyOfRange", "([III)[I")
    @jstatic("copyOfRange", "([JII)[J")
    @jstatic("copyOfRange", "([BII)[B")
    @jstatic("copyOfRange", "([SII)[S")
    @jstatic("copyOfRange", "([CII)[C")
    @jstatic("copyOfRange", "([ZII)[Z")
    @jstatic("copyOfRange", "([FII)[F")
    @jstatic("copyOfRange", "([DII)[D")
    @jstatic("copyOfRange", "([Ljava/lang/Object;II)[Ljava/lang/Object;")
    def copyOfRange(array, start, end):
        if start > end:
            runtime.throw_new("java.lang.IllegalArgumentException", "%d > %d" % (start, end))
        if start < 0 or start > len(array):
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "length=%d; index=%d" % (len(array), start))
        result = runtime.new_array(array.jtype, end - start)
        chunk = array[start:min(end, len(array))]
        result[:len(chunk)] = chunk
        return result

    @jstatic("fill", "([II)V")
    @jstatic("fill", "([JJ)V")
    @jstatic("fill", "([BB)V")
    @jstatic("fill", "([SS)V")
    @jstatic("fill", "([CC)V")
    @jstatic("fill", "([ZZ)V")
    @jstatic("fill", "([FF)V")
    @jstatic("fill", "([DD)V")
    @jstatic("fill", "([Ljava/lang/Object;Ljava/lang/Object;)V")
    @jstatic("fill", "([IIII)V")
    @jstatic("fill", "([JIIJ)V")
    @jstatic("fill", "([BIIB)V")
    @jstatic("fill", "([CIIC)V")
    @jstatic("fill", "([Ljava/lang/Object;IILjava/lang/Object;)V")
    def fill(array, *args):
        if array is None:
            runtime.npe()
        if len(args) == 1:
            array[:] = [args[0]] * len(array)
        else:
            start, end, value = args
            _check_range(len(array), start, end)
            array[start:end] = [value] * (end - start)

    @jstatic("sort", "([I)V")
    @jstatic("sort", "([J)V")
    @jstatic("sort", "([B)V")
    @jstatic("sort", "([S)V")
    @jstatic("sort", "([C)V")
    @jstatic("sort", "([F)V")
    @jstatic("sort", "([D)V")
    @jstatic("sort", "([Ljava/lang/Object;)V")
    @jstatic("sort", "([III)V")
    @jstatic("sort", "([JII)V")
    @jstatic("sort", "([CII)V")
    @jstatic("sort", "([Ljava/lang/Object;II)V")
    @jstatic("sort", "([Ljava/lang/Object;Ljava/util/Comparator;)V")
    @jstatic("sort", "([Ljava/lang/Object;IILjava/util/Comparator;)V")
    def sort(array, *args):
        if array is None:
            runtime.npe()
        comparator = None
        start, end = 0, len(array)
        if len(args) == 1:
            comparator = args[0]
        elif len(args) >= 2:
            start, end = args[0], args[1]
            _check_range(len(array), start, end)
            if len(args) == 3:
                comparator = args[2]
        part = list(array[start:end])
        code = array.jtype.descriptor[1]
        if code in "FD":
            part.sort(key=functools.cmp_to_key(_float_order))
        elif code in "BSCIJ":
            part.sort()
        else:
            _sort(part, comparator)
        array[start:end] = part

    @jstatic("equals", "([I[I)Z")
    @jstatic("equals", "([J[J)Z")
    @jstatic("equals", "([B[B)Z")
    @jstatic("equals", "([C[C)Z")
    @jstatic("equals", "([Z[Z)Z")
    @jstatic("equals", "([D[D)Z")
    @jstatic("equals", "([F[F)Z")
    @jstatic("equals", "([Ljava/lang/Object;[Ljava/lang/Object;)Z")
    def equals(a, b):
        if a is b:
            return 1
        if a is None or b is None or len(a) != len(b):
            return 0
        if a.jtype.descriptor[1] in "FD":
            return 1 if all(element_hash(a, x) == element_hash(b, y) for x, y in zip(a, b)) else 0
        return 1 if all(jequals(x, y) if not a.jtype.component.isPrimitive() else x == y for x, y in zip(a, b)) else 0

    @jstatic("hashCode", "([I)I")
    @jstatic("hashCode", "([J)I")
    @jstatic("hashCode", "([B)I")
    @jstatic("hashCode", "([C)I")
    @jstatic("hashCode", "([Ljava/lang/Object;)I")
    def hashCode(array):
        if array is None:
            return 0
        h = 1
        for value in array:
            h = (31 * h + element_hash(array, value)) & 0xFFFFFFFF
        return h - 0x100000000 if h & 0x80000000 else h

    @jstatic("binarySearch", "([II)I")
    @jstatic("binarySearch", "([JJ)I")
    @jstatic("binarySearch", "([CC)I")
    @jstatic("binarySearch", "([Ljava/lang/Object;Ljava/lang/Object;)I")
    @jstatic("binarySearch", "([Ljava/lang/Object;Ljava/lang/Object;Ljava/util/Comparator;)I")
    def binarySearch(array, key, comparator=None):
        low, high = 0, len(array) - 1
        primitive = array.jtype.component.isPrimitive()
        while low <= high:
            middle = (low + high) >> 1
            value = array[middle]
            order = (value > key) - (value < key) if primitive else compare_with(comparator, value, key)
            if order < 0:
                low = middle + 1
            elif order > 0:
                high = middle - 1
            else:
                return middle
        return -(low + 1)

    @jstatic("setAll", "([ILjava/util/function/IntUnaryOperator;)V")
    def setAll(array, generator):
        for index in range(len(array)):
            array[index] = generator.applyAsInt(index)

    @jstatic("deepEquals", "([Ljava/lang/Object;[Ljava/lang/Object;)Z")
    def deepEquals(a, b):
        return 1 if Arrays.deepToString(a) == Arrays.deepToString(b) else 0


def _float_order(a, b):
    from .jlang import _compare_double
    return _compare_double(a, b)


class ArrayAsList(AbstractList):
    """Arrays.asList: a fixed size list that writes through to the array"""

    def __init__(self, array):
        self._arr = array
        self.modCount = 0

    def size(self):
        return len(self._arr)

    def get(self, index):
        if not 0 <= index < len(self._arr):
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "length=%d; index=%d" % (len(self._arr), index))
        return self._arr[index]

    def set(self, index, item):
        old = self.get(index)
        self._arr[index] = item
        return old

    def toArray(self, target=None):
        return to_array(self._arr) if target is None else AbstractList.toArray(self, target)

    def sort(self, comparator):
        items = list(self._arr)
        _sort(items, comparator)
        self._arr[:] = items


host_class("java.util.Arrays$ArrayList", interfaces=("java.util.List", "java.util.RandomAccess"))(ArrayAsList)


class UnmodifiableList(AbstractList):
    def __init__(self, source):
        self._s = source
        self.modCount = 0

    def size(self):
        return self._s.size()

    def get(self, index):
        return self._s.get(index)

    def iterator(self):
        return PyIterator(list(iterate(self._s)))


host_class("java.util.Collections$UnmodifiableRandomAccessList", interfaces=("java.util.List",))(UnmodifiableList)


@host_class("java.util.Collections", final=True)
class Collections(Object):
    EMPTY_LIST = ImmutableList([])

    @jstatic("emptyList", "()Ljava/util/List;")
    def emptyList():
        return ImmutableList([])

    @jstatic("emptyMap", "()Ljava/util/Map;")
    def emptyMap():
        return ImmutableMap(LinkedHashMap())

    @jstatic("newSetFromMap", "(Ljava/util/Map;)Ljava/util/Set;")
    def newSetFromMap(backing):
        from .jcoll import MapBackedSet
        if not check_nonnull(backing).isEmpty():
            runtime.throw_new("java.lang.IllegalArgumentException", "Map is non-empty")
        return MapBackedSet(backing)

    @jstatic("emptySet", "()Ljava/util/Set;")
    def emptySet():
        return UnmodifiableSet(LinkedHashSet())

    @jstatic("singletonList", "(Ljava/lang/Object;)Ljava/util/List;")
    def singletonList(item):
        return ImmutableList([item])

    @jstatic("singleton", "(Ljava/lang/Object;)Ljava/util/Set;")
    def singleton(item):
        result = LinkedHashSet()
        result.add(item)
        return UnmodifiableSet(result)

    @jstatic("singletonMap", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/Map;")
    def singletonMap(key, value):
        result = LinkedHashMap()
        result.put(key, value)
        return ImmutableMap(result)

    @jstatic("unmodifiableList", "(Ljava/util/List;)Ljava/util/List;")
    def unmodifiableList(source):
        return UnmodifiableList(check_nonnull(source))

    @jstatic("unmodifiableSet", "(Ljava/util/Set;)Ljava/util/Set;")
    def unmodifiableSet(source):
        return UnmodifiableSet(check_nonnull(source))

    @jstatic("unmodifiableMap", "(Ljava/util/Map;)Ljava/util/Map;")
    def unmodifiableMap(source):
        return ImmutableMap(check_nonnull(source))

    @jstatic("unmodifiableCollection", "(Ljava/util/Collection;)Ljava/util/Collection;")
    def unmodifiableCollection(source):
        return UnmodifiableList(ArrayList(check_nonnull(source)))

    @jstatic("synchronizedList", "(Ljava/util/List;)Ljava/util/List;")
    @jstatic("synchronizedMap", "(Ljava/util/Map;)Ljava/util/Map;")
    @jstatic("synchronizedSet", "(Ljava/util/Set;)Ljava/util/Set;")
    @jstatic("synchronizedCollection", "(Ljava/util/Collection;)Ljava/util/Collection;")
    def synchronized(source):
        return source

    @jstatic("sort", "(Ljava/util/List;)V")
    @jstatic("sort", "(Ljava/util/List;Ljava/util/Comparator;)V")
    def sort(items, comparator=None):
        items.sort(comparator)

    @jstatic("reverse", "(Ljava/util/List;)V")
    def reverse(items):
        values = list(iterate(items))
        values.reverse()
        for index, value in enumerate(values):
            items.set(index, value)

    @jstatic("shuffle", "(Ljava/util/List;)V")
    @jstatic("shuffle", "(Ljava/util/List;Ljava/util/Random;)V")
    def shuffle(items, rnd=None):
        rnd = rnd or Random()
        values = list(iterate(items))
        for i in range(len(values), 1, -1):
            j = rnd.nextInt(i)
            values[i - 1], values[j] = values[j], values[i - 1]
        for index, value in enumerate(values):
            items.set(index, value)

    @jstatic("swap", "(Ljava/util/List;II)V")
    def swap(items, i, j):
        items.set(i, items.set(j, items.get(i)))

    @jstatic("max", "(Ljava/util/Collection;)Ljava/lang/Object;")
    @jstatic("max", "(Ljava/util/Collection;Ljava/util/Comparator;)Ljava/lang/Object;")
    def max(collection, comparator=None):
        values = list(iterate(collection))
        if not values:
            no_such_element()
        best = values[0]
        for value in values[1:]:
            if compare_with(comparator, value, best) > 0:
                best = value
        return best

    @jstatic("min", "(Ljava/util/Collection;)Ljava/lang/Object;")
    @jstatic("min", "(Ljava/util/Collection;Ljava/util/Comparator;)Ljava/lang/Object;")
    def min(collection, comparator=None):
        values = list(iterate(collection))
        if not values:
            no_such_element()
        best = values[0]
        for value in values[1:]:
            if compare_with(comparator, value, best) < 0:
                best = value
        return best

    @jstatic("frequency", "(Ljava/util/Collection;Ljava/lang/Object;)I")
    def frequency(collection, item):
        return sum(1 for value in iterate(collection) if jequals(item, value))

    @jstatic("addAll", "(Ljava/util/Collection;[Ljava/lang/Object;)Z")
    def addAll(collection, items):
        changed = 0
        for item in items:
            if collection.add(item):
                changed = 1
        return changed

    @jstatic("nCopies", "(ILjava/lang/Object;)Ljava/util/List;")
    def nCopies(count, item):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "List length = %d" % count)
        return ImmutableList([item] * count)

    @jstatic("reverseOrder", "()Ljava/util/Comparator;")
    @jstatic("reverseOrder", "(Ljava/util/Comparator;)Ljava/util/Comparator;")
    def reverseOrder(comparator=None):
        if comparator is None:
            return Comparator.reverseOrder()
        return comparator.reversed()

    @jstatic("binarySearch", "(Ljava/util/List;Ljava/lang/Object;)I")
    @jstatic("binarySearch", "(Ljava/util/List;Ljava/lang/Object;Ljava/util/Comparator;)I")
    def binarySearch(items, key, comparator=None):
        low, high = 0, items.size() - 1
        while low <= high:
            middle = (low + high) >> 1
            order = compare_with(comparator, items.get(middle), key)
            if order < 0:
                low = middle + 1
            elif order > 0:
                high = middle - 1
            else:
                return middle
        return -(low + 1)

    @jstatic("fill", "(Ljava/util/List;Ljava/lang/Object;)V")
    def fill(items, value):
        for index in range(items.size()):
            items.set(index, value)

    @jstatic("list", "(Ljava/util/Enumeration;)Ljava/util/ArrayList;")
    def list_(enumeration):
        result = ArrayList()
        while enumeration.hasMoreElements():
            result.add(enumeration.nextElement())
        return result

    @jstatic("disjoint", "(Ljava/util/Collection;Ljava/util/Collection;)Z")
    def disjoint(a, b):
        return 0 if any(b.contains(item) for item in iterate(a)) else 1


class UnmodifiableSet(HashSet):
    def __init__(self, source):
        HashSet.__init__(self)
        self._m = source._m if isinstance(source, HashSet) else HashSet(source)._m

    add = remove = clear = addAll = removeAll = retainAll = removeIf = lambda self, *args: unsupported()


host_class("java.util.Collections$UnmodifiableSet", interfaces=("java.util.Set",))(UnmodifiableSet)


@host_class("java.util.Objects", final=True)
class Objects(Object):
    @jstatic("equals", "(Ljava/lang/Object;Ljava/lang/Object;)Z")
    def equals(a, b):
        return 1 if jequals(a, b) else 0

    @jstatic("hashCode", "(Ljava/lang/Object;)I")
    def hashCode(value):
        return jhash(value)

    @jstatic("hash", "([Ljava/lang/Object;)I")
    def hash(values):
        if values is None:
            return 0
        h = 1
        for value in values:
            h = (31 * h + jhash(value)) & 0xFFFFFFFF
        return h - 0x100000000 if h & 0x80000000 else h

    @jstatic("toString", "(Ljava/lang/Object;)Ljava/lang/String;")
    @jstatic("toString", "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/String;")
    def toString(value, default=None):
        if value is None and default is not None:
            return default
        return jstring(value)

    @jstatic("requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;")
    @jstatic("requireNonNull", "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;")
    def requireNonNull(value, message=None):
        if value is None:
            runtime.npe(message)
        return value

    @jstatic("requireNonNullElse", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def requireNonNullElse(value, default):
        return value if value is not None else Objects.requireNonNull(default, "defaultObj")

    @jstatic("isNull", "(Ljava/lang/Object;)Z")
    def isNull(value):
        return 1 if value is None else 0

    @jstatic("nonNull", "(Ljava/lang/Object;)Z")
    def nonNull(value):
        return 0 if value is None else 1

    @jstatic("compare", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/util/Comparator;)I")
    def compare(a, b, comparator):
        return 0 if a is b else comparator.compare(a, b)

    @jstatic("checkIndex", "(II)I")
    def checkIndex(index, length):
        if index < 0 or index >= length:
            ioobe(index, length)
        return index


@host_class("java.util.Optional", final=True)
class Optional(Object):
    _EMPTY = None

    def __init__(self, value=None):
        self._v = value

    @jstatic("of", "(Ljava/lang/Object;)Ljava/util/Optional;")
    def of(value):
        return Optional(check_nonnull(value))

    @jstatic("ofNullable", "(Ljava/lang/Object;)Ljava/util/Optional;")
    def ofNullable(value):
        return Optional(value) if value is not None else Optional.empty()

    @jstatic("empty", "()Ljava/util/Optional;")
    def empty():
        if Optional._EMPTY is None:
            Optional._EMPTY = Optional(None)
        return Optional._EMPTY

    @jmethod("isPresent", "()Z")
    def isPresent(self):
        return 0 if self._v is None else 1

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 1 if self._v is None else 0

    @jmethod("get", "()Ljava/lang/Object;")
    def get(self):
        if self._v is None:
            no_such_element("No value present")
        return self._v

    @jmethod("orElse", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def orElse(self, other):
        return self._v if self._v is not None else other

    @jmethod("orElseGet", "(Ljava/util/function/Supplier;)Ljava/lang/Object;")
    def orElseGet(self, supplier):
        return self._v if self._v is not None else supplier.get()

    @jmethod("orElseThrow", "()Ljava/lang/Object;")
    @jmethod("orElseThrow", "(Ljava/util/function/Supplier;)Ljava/lang/Object;")
    def orElseThrow(self, supplier=None):
        if self._v is None:
            if supplier is None:
                no_such_element("No value present")
            raise supplier.get()
        return self._v

    @jmethod("ifPresent", "(Ljava/util/function/Consumer;)V")
    def ifPresent(self, action):
        if self._v is not None:
            action.accept(self._v)

    @jmethod("map", "(Ljava/util/function/Function;)Ljava/util/Optional;")
    def map(self, function):
        return Optional.empty() if self._v is None else Optional.ofNullable(function.apply(self._v))

    @jmethod("filter", "(Ljava/util/function/Predicate;)Ljava/util/Optional;")
    def filter(self, predicate):
        return self if self._v is None or predicate.test(self._v) else Optional.empty()

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Optional) and jequals(self._v, other._v) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return jhash(self._v)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "Optional.empty" if self._v is None else "Optional[%s]" % jstring(self._v)


_MULTIPLIER = 0x5DEECE66D
_MASK = (1 << 48) - 1
_seed_uniquifier = [8682522807148012]
_seed_lock = threading.Lock()


@host_class("java.util.Random", interfaces=("java.io.Serializable",))
class Random(Object):
    def __init__(self, seed=None):
        if seed is None:
            with _seed_lock:
                _seed_uniquifier[0] = (_seed_uniquifier[0] * 1181783497276652981) & 0xFFFFFFFFFFFFFFFF
                seed = _seed_uniquifier[0] ^ time.monotonic_ns()
        self._seed = (seed ^ _MULTIPLIER) & _MASK
        self._next_gaussian = None
        self._lock = threading.Lock()

    @jmethod("<init>", "()V")
    def _init(self):
        Random.__init__(self)

    @jmethod("<init>", "(J)V")
    def _init_seed(self, seed):
        Random.__init__(self, seed)

    @jmethod("setSeed", "(J)V")
    def setSeed(self, seed):
        self._seed = (seed ^ _MULTIPLIER) & _MASK
        self._next_gaussian = None

    def _next(self, bits):
        with self._lock:
            self._seed = (self._seed * _MULTIPLIER + 0xB) & _MASK
            seed = self._seed
        return runtime.wrap32(seed >> (48 - bits))

    @jmethod("nextInt", "()I")
    @jmethod("nextInt", "(I)I")
    @jmethod("nextInt", "(II)I")
    def nextInt(self, bound=None, upper=None):
        if bound is None:
            return self._next(32)
        if upper is not None:
            origin, limit = bound, upper
            if origin >= limit:
                runtime.throw_new("java.lang.IllegalArgumentException", "bound must be greater than origin")
            span = limit - origin
            if span > 0 and span <= 0x7FFFFFFF:
                return origin + self.nextInt(span)
            while True:
                value = self._next(32)
                if origin <= value < limit:
                    return value
        if bound <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "bound must be positive")
        r = self._next(31)
        m = bound - 1
        if bound & m == 0:
            return (bound * r) >> 31
        u = r
        while True:
            r = u % bound
            if runtime.wrap32(u - r + m) >= 0:
                return r
            u = self._next(31)

    @jmethod("nextLong", "()J")
    def nextLong(self):
        return runtime.wrap64((self._next(32) << 32) + self._next(32))

    @jmethod("nextBoolean", "()Z")
    def nextBoolean(self):
        return 1 if self._next(1) != 0 else 0

    @jmethod("nextDouble", "()D")
    def nextDouble(self):
        return ((self._next(26) << 27) + self._next(27)) * (1.0 / (1 << 53))

    @jmethod("nextFloat", "()F")
    def nextFloat(self):
        return self._next(24) / float(1 << 24)

    @jmethod("nextGaussian", "()D")
    def nextGaussian(self):
        if self._next_gaussian is not None:
            value, self._next_gaussian = self._next_gaussian, None
            return value
        while True:
            v1 = 2 * self.nextDouble() - 1
            v2 = 2 * self.nextDouble() - 1
            s = v1 * v1 + v2 * v2
            if 0 < s < 1:
                break
        multiplier = math.sqrt(-2 * math.log(s) / s)
        self._next_gaussian = v2 * multiplier
        return v1 * multiplier

    @jmethod("nextBytes", "([B)V")
    def nextBytes(self, array):
        index = 0
        while index < len(array):
            rnd = self._next(32)
            for _ in range(min(len(array) - index, 4)):
                array[index] = (rnd + 128 & 0xFF) - 128
                rnd >>= 8
                index += 1


@host_class("java.util.StringJoiner", final=True)
class StringJoiner(Object):
    def __init__(self, delimiter="", prefix="", suffix=""):
        self._d = _cs(delimiter)
        self._p = _cs(prefix)
        self._s = _cs(suffix)
        self._parts = []
        self._empty = None

    @jmethod("<init>", "(Ljava/lang/CharSequence;)V")
    def _init(self, delimiter):
        StringJoiner.__init__(self, delimiter)

    @jmethod("<init>", "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;Ljava/lang/CharSequence;)V")
    def _init3(self, delimiter, prefix, suffix):
        StringJoiner.__init__(self, delimiter, prefix, suffix)

    @jmethod("add", "(Ljava/lang/CharSequence;)Ljava/util/StringJoiner;")
    def add(self, item):
        self._parts.append(jstring(item))
        return self

    @jmethod("setEmptyValue", "(Ljava/lang/CharSequence;)Ljava/util/StringJoiner;")
    def setEmptyValue(self, value):
        self._empty = _cs(value)
        return self

    @jmethod("length", "()I")
    def length(self):
        return len(self.toString())

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        if not self._parts and self._empty is not None:
            return self._empty
        return self._p + self._d.join(self._parts) + self._s


@host_class("java.util.UUID", interfaces=("java.lang.Comparable", "java.io.Serializable"))
class UUID(Object):
    def __init__(self, high=0, low=0):
        self._hi = runtime.wrap64(high)
        self._lo = runtime.wrap64(low)

    @jmethod("<init>", "(JJ)V")
    def _init(self, high, low):
        UUID.__init__(self, high, low)

    @jstatic("randomUUID", "()Ljava/util/UUID;")
    def randomUUID():
        raw = bytearray(os.urandom(16))
        raw[6] = raw[6] & 0x0F | 0x40
        raw[8] = raw[8] & 0x3F | 0x80
        return UUID(int.from_bytes(raw[:8], "big"), int.from_bytes(raw[8:], "big"))

    @jstatic("nameUUIDFromBytes", "([B)Ljava/util/UUID;")
    def nameUUIDFromBytes(data):
        raw = bytearray(hashlib.md5(bytes(b & 0xFF for b in data)).digest())
        raw[6] = raw[6] & 0x0F | 0x30
        raw[8] = raw[8] & 0x3F | 0x80
        return UUID(int.from_bytes(raw[:8], "big"), int.from_bytes(raw[8:], "big"))

    @jstatic("fromString", "(Ljava/lang/String;)Ljava/util/UUID;")
    def fromString(text):
        parts = text.split("-")
        if len(parts) != 5:
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid UUID string: " + text)
        try:
            value = int("".join(p.rjust(len(p), "0") for p in parts), 16)
            high = int(parts[0], 16) << 32 | int(parts[1], 16) << 16 | int(parts[2], 16)
            low = int(parts[3], 16) << 48 | int(parts[4], 16)
        except ValueError:
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid UUID string: " + text)
        return UUID(high, low)

    @jmethod("getMostSignificantBits", "()J")
    def getMostSignificantBits(self):
        return self._hi

    @jmethod("getLeastSignificantBits", "()J")
    def getLeastSignificantBits(self):
        return self._lo

    @jmethod("version", "()I")
    def version(self):
        return (self._hi >> 12) & 0xF

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        hi, lo = self._hi & 0xFFFFFFFFFFFFFFFF, self._lo & 0xFFFFFFFFFFFFFFFF
        return "%08x-%04x-%04x-%04x-%012x" % (hi >> 32, hi >> 16 & 0xFFFF, hi & 0xFFFF, lo >> 48, lo & 0xFFFFFFFFFFFF)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, UUID) and other._hi == self._hi and other._lo == self._lo else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        value = (self._hi ^ self._lo) & 0xFFFFFFFFFFFFFFFF
        return runtime.wrap32((value >> 32) ^ value)

    @jmethod("compareTo", "(Ljava/util/UUID;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        a = (self._hi, self._lo)
        b = (other._hi, other._lo)
        return (a > b) - (a < b)
