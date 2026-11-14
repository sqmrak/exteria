"""java.util: the collection interfaces, the abstract bases a program extends, lists, queues and deques

the abstract classes are written over their primitive methods (iterator, size, get, entrySet), so a dex class that
extends AbstractList or AbstractMap gets the rest the way it does on a real runtime. mutations of an ArrayList or a
LinkedList bump modCount and an iterator that finds it changed throws ConcurrentModificationException"""

import functools

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import compare_natural, compare_with, jequals, jhash, jstring, _Lambda
from .jfunc import Comparator, Consumer, Function, Predicate, UnaryOperator
from .jlang import Iterable, Object, _cs


def unsupported():
    runtime.throw_new("java.lang.UnsupportedOperationException", None)


def ioobe(index, size):
    runtime.throw_new("java.lang.IndexOutOfBoundsException", "Index %d out of bounds for length %d" % (index, size))


def no_such_element(message=None):
    runtime.throw_new("java.util.NoSuchElementException", message)


def check_nonnull(value):
    if value is None:
        runtime.npe()
    return value


def to_array(items, array_type="[Ljava/lang/Object;"):
    array = runtime.new_array(array_type, 0)
    array.extend(items)
    return array


def iterate(collection):
    """a python iterator over any java Iterable, a JArray or a python sequence; the java iterator protocol is honoured"""
    if isinstance(collection, (list, tuple)):
        return iter(collection)
    return _java_iter(collection.iterator())


def _java_iter(iterator):
    has_next = iterator.hasNext
    take = iterator.next
    while has_next():
        yield take()


@host_class("java.util.Iterator", interface=True)
class Iterator:
    __slots__ = ()

    @jmethod("remove", "()V")
    def remove(self):
        unsupported()

    @jmethod("forEachRemaining", "(Ljava/util/function/Consumer;)V")
    def forEachRemaining(self, action):
        while self.hasNext():
            action.accept(self.next())


@host_class("java.util.ListIterator", interface=True, interfaces=("java.util.Iterator",))
class ListIterator(Iterator):
    __slots__ = ()


@host_class("java.util.Enumeration", interface=True)
class Enumeration:
    __slots__ = ()


@host_class("java.util.RandomAccess", interface=True)
class RandomAccess:
    __slots__ = ()


class PyIterator(Object):
    """a java Iterator over a python iterator, with an optional remover for the last element returned"""

    _iterator = None
    _peeked = False
    _next = None
    _last = None
    _remover = None

    def __init__(self, source, remover=None):
        self._iterator = iter(source)
        self._remover = remover
        self._peeked = False

    def hasNext(self):
        if not self._peeked:
            try:
                self._next = next(self._iterator)
            except StopIteration:
                return 0
            self._peeked = True
        return 1

    def next(self):
        if not self._peeked and not self.hasNext():
            no_such_element()
        self._peeked = False
        self._last = self._next
        return self._next

    def remove(self):
        if self._remover is None:
            unsupported()
        self._remover(self._last)

    def forEachRemaining(self, action):
        Iterator.forEachRemaining(self, action)

    def hasMoreElements(self):
        return self.hasNext()

    def nextElement(self):
        return self.next()


host_class("java.util.PyIterator", interfaces=("java.util.Iterator", "java.util.Enumeration"))(PyIterator)


@host_class("java.util.Collection", interface=True, interfaces=("java.lang.Iterable",))
class Collection(Iterable):
    __slots__ = ()

    @jmethod("stream", "()Ljava/util/stream/Stream;")
    @jmethod("parallelStream", "()Ljava/util/stream/Stream;")
    def stream(self):
        from .jstream import BaseStream
        return BaseStream.from_items(list(iterate(self)))

    @jmethod("removeIf", "(Ljava/util/function/Predicate;)Z")
    def removeIf(self, predicate):
        check_nonnull(predicate)
        removed = 0
        iterator = self.iterator()
        while iterator.hasNext():
            if predicate.test(iterator.next()):
                iterator.remove()
                removed = 1
        return removed

    @jmethod("forEach", "(Ljava/util/function/Consumer;)V")
    def forEach(self, action):
        check_nonnull(action)
        iterator = self.iterator()
        while iterator.hasNext():
            action.accept(iterator.next())


@host_class("java.util.List", interface=True, interfaces=("java.util.Collection",))
class List(Collection):
    __slots__ = ()

    @jstatic("of", "([Ljava/lang/Object;)Ljava/util/List;")
    def of_array(items):
        return ImmutableList([check_nonnull(item) for item in items])

    @jstatic("of", "()Ljava/util/List;")
    @jstatic("of", "(Ljava/lang/Object;)Ljava/util/List;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/List;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/List;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/List;")
    @jstatic("of", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/util/List;")
    def of(*items):
        return ImmutableList([check_nonnull(item) for item in items])

    @jstatic("copyOf", "(Ljava/util/Collection;)Ljava/util/List;")
    def copyOf(collection):
        return ImmutableList([check_nonnull(item) for item in iterate(collection)])

    @jmethod("sort", "(Ljava/util/Comparator;)V")
    def sort(self, comparator):
        items = list(iterate(self))
        _sort(items, comparator)
        for index, item in enumerate(items):
            self.set(index, item)

    @jmethod("replaceAll", "(Ljava/util/function/UnaryOperator;)V")
    def replaceAll(self, operator):
        for index in range(self.size()):
            self.set(index, operator.apply(self.get(index)))


@host_class("java.util.Set", interface=True, interfaces=("java.util.Collection",))
class Set(Collection):
    __slots__ = ()


@host_class("java.util.SortedSet", interface=True, interfaces=("java.util.Set",))
class SortedSet(Set):
    __slots__ = ()


@host_class("java.util.NavigableSet", interface=True, interfaces=("java.util.SortedSet",))
class NavigableSet(SortedSet):
    __slots__ = ()


@host_class("java.util.Queue", interface=True, interfaces=("java.util.Collection",))
class Queue(Collection):
    __slots__ = ()


@host_class("java.util.Deque", interface=True, interfaces=("java.util.Queue",))
class Deque(Queue):
    __slots__ = ()


def _sort(items, comparator):
    if comparator is None:
        items.sort(key=functools.cmp_to_key(compare_natural))
    else:
        items.sort(key=functools.cmp_to_key(comparator.compare))


@host_class("java.util.AbstractCollection", interfaces=("java.util.Collection",))
class AbstractCollection(Collection, Object):
    def __init__(self):
        pass

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 1 if self.size() == 0 else 0

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        for element in iterate(self):
            if jequals(item, element):
                return 1
        return 0

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        unsupported()

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove(self, item):
        iterator = self.iterator()
        while iterator.hasNext():
            if jequals(item, iterator.next()):
                iterator.remove()
                return 1
        return 0

    @jmethod("containsAll", "(Ljava/util/Collection;)Z")
    def containsAll(self, other):
        for item in iterate(other):
            if not self.contains(item):
                return 0
        return 1

    @jmethod("addAll", "(Ljava/util/Collection;)Z")
    def addAll(self, other):
        changed = 0
        for item in list(iterate(other)):
            if self.add(item):
                changed = 1
        return changed

    @jmethod("removeAll", "(Ljava/util/Collection;)Z")
    def removeAll(self, other):
        check_nonnull(other)
        changed = 0
        iterator = self.iterator()
        while iterator.hasNext():
            if other.contains(iterator.next()):
                iterator.remove()
                changed = 1
        return changed

    @jmethod("retainAll", "(Ljava/util/Collection;)Z")
    def retainAll(self, other):
        check_nonnull(other)
        changed = 0
        iterator = self.iterator()
        while iterator.hasNext():
            if not other.contains(iterator.next()):
                iterator.remove()
                changed = 1
        return changed

    @jmethod("clear", "()V")
    def clear(self):
        iterator = self.iterator()
        while iterator.hasNext():
            iterator.next()
            iterator.remove()

    @jmethod("toArray", "()[Ljava/lang/Object;")
    @jmethod("toArray", "([Ljava/lang/Object;)[Ljava/lang/Object;")
    def toArray(self, target=None):
        items = list(iterate(self))
        if target is None:
            return to_array(items)
        if len(target) >= len(items):
            target[:len(items)] = items
            if len(target) > len(items):
                target[len(items)] = None
            return target
        array = runtime.JArray(target.jtype, items)
        return array

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        parts = []
        for item in iterate(self):
            parts.append("(this Collection)" if item is self else jstring(item))
        return "[" + ", ".join(parts) + "]"


@host_class("java.util.AbstractList", interfaces=("java.util.List",))
class AbstractList(AbstractCollection, List):
    modCount = 0

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        self.add_at(self.size(), item)
        return 1

    @jmethod("add", "(ILjava/lang/Object;)V")
    def add_at(self, index, item):
        unsupported()

    @jmethod("set", "(ILjava/lang/Object;)Ljava/lang/Object;")
    def set(self, index, item):
        unsupported()

    @jmethod("remove", "(I)Ljava/lang/Object;")
    def remove_at(self, index):
        unsupported()

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove_object(self, item):
        index = self.indexOf(item)
        if index < 0:
            return 0
        self.remove_at(index)
        return 1

    def remove(self, value):
        return self.remove_at(value) if value.__class__ is int else self.remove_object(value)

    @jmethod("indexOf", "(Ljava/lang/Object;)I")
    def indexOf(self, item):
        for index in range(self.size()):
            if jequals(item, self.get(index)):
                return index
        return -1

    @jmethod("lastIndexOf", "(Ljava/lang/Object;)I")
    def lastIndexOf(self, item):
        for index in range(self.size() - 1, -1, -1):
            if jequals(item, self.get(index)):
                return index
        return -1

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        return 1 if self.indexOf(item) >= 0 else 0

    @jmethod("clear", "()V")
    def clear(self):
        for index in range(self.size() - 1, -1, -1):
            self.remove_at(index)

    @jmethod("addAll", "(Ljava/util/Collection;)Z")
    @jmethod("addAll", "(ILjava/util/Collection;)Z")
    def addAll(self, first, second=None):
        index, other = (self.size(), first) if second is None else (first, second)
        items = list(iterate(other))
        for offset, item in enumerate(items):
            self.add_at(index + offset, item)
        return 1 if items else 0

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return ListItr(self, 0)

    @jmethod("listIterator", "()Ljava/util/ListIterator;")
    @jmethod("listIterator", "(I)Ljava/util/ListIterator;")
    def listIterator(self, index=0):
        if index < 0 or index > self.size():
            ioobe(index, self.size())
        return ListItr(self, index)

    @jmethod("subList", "(II)Ljava/util/List;")
    def subList(self, start, end):
        if start < 0 or end > self.size() or start > end:
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "fromIndex: %d, toIndex: %d, size: %d" % (
                start, end, self.size()))
        return SubList(self, start, end)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        if other is self:
            return 1
        if not isinstance(other, List) and "Ljava/util/List;" not in getattr(type(other), "_jsupers", ()):
            return 0
        a, b = self.iterator(), other.iterator()
        while a.hasNext() and b.hasNext():
            if not jequals(a.next(), b.next()):
                return 0
        return 0 if a.hasNext() or b.hasNext() else 1

    @jmethod("hashCode", "()I")
    def hashCode(self):
        h = 1
        for item in iterate(self):
            h = (31 * h + jhash(item)) & 0xFFFFFFFF
        return h - 0x100000000 if h & 0x80000000 else h


class ListItr(Object):
    """the iterator of an AbstractList: fail-fast on modCount"""

    def __init__(self, owner, index):
        self._owner = owner
        self._cursor = index
        self._last = -1
        self._expected = owner.modCount

    def _check(self):
        if self._owner.modCount != self._expected:
            runtime.throw_new("java.util.ConcurrentModificationException", None)

    def hasNext(self):
        return 1 if self._cursor != self._owner.size() else 0

    def next(self):
        self._check()
        index = self._cursor
        if index >= self._owner.size():
            no_such_element()
        item = self._owner.get(index)
        self._last = index
        self._cursor = index + 1
        return item

    def hasPrevious(self):
        return 1 if self._cursor != 0 else 0

    def previous(self):
        self._check()
        index = self._cursor - 1
        if index < 0:
            no_such_element()
        self._cursor = self._last = index
        return self._owner.get(index)

    def nextIndex(self):
        return self._cursor

    def previousIndex(self):
        return self._cursor - 1

    def remove(self):
        if self._last < 0:
            runtime.throw_new("java.lang.IllegalStateException", None)
        self._check()
        self._owner.remove_at(self._last)
        if self._last < self._cursor:
            self._cursor -= 1
        self._last = -1
        self._expected = self._owner.modCount

    def set(self, item):
        if self._last < 0:
            runtime.throw_new("java.lang.IllegalStateException", None)
        self._check()
        self._owner.set(self._last, item)

    def add(self, item):
        self._check()
        self._owner.add_at(self._cursor, item)
        self._cursor += 1
        self._last = -1
        self._expected = self._owner.modCount

    def forEachRemaining(self, action):
        while self.hasNext():
            action.accept(self.next())


host_class("java.util.ListItr", interfaces=("java.util.ListIterator",))(ListItr)


class SubList(AbstractList):
    """a view of a range of a list; structural changes go through to the parent"""

    def __init__(self, parent, start, end):
        self._parent = parent
        self._offset = start
        self._size = end - start
        self.modCount = parent.modCount

    def _check_index(self, index, upper):
        if index < 0 or index >= upper:
            ioobe(index, upper)

    def size(self):
        return self._size

    def get(self, index):
        self._check_index(index, self._size)
        return self._parent.get(self._offset + index)

    def set(self, index, item):
        self._check_index(index, self._size)
        return self._parent.set(self._offset + index, item)

    def add_at(self, index, item):
        if index < 0 or index > self._size:
            ioobe(index, self._size)
        self._parent.add_at(self._offset + index, item)
        self._size += 1
        self.modCount = self._parent.modCount

    def remove_at(self, index):
        self._check_index(index, self._size)
        item = self._parent.remove_at(self._offset + index)
        self._size -= 1
        self.modCount = self._parent.modCount
        return item


host_class("java.util.SubList")(SubList)


@host_class("java.util.ArrayList", interfaces=("java.util.List", "java.util.RandomAccess", "java.lang.Cloneable",
                                               "java.io.Serializable"))
class ArrayList(AbstractList):
    def __init__(self, source=None):
        self._a = []
        self.modCount = 0
        if source is not None:
            if isinstance(source, int):
                if source < 0:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Illegal Capacity: %d" % source)
            else:
                self._a.extend(iterate(source))

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=0):
        ArrayList.__init__(self, capacity)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        ArrayList.__init__(self, check_nonnull(source))

    @jmethod("size", "()I")
    def size(self):
        return len(self._a)

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 0 if self._a else 1

    @jmethod("get", "(I)Ljava/lang/Object;")
    def get(self, index):
        a = self._a
        if not 0 <= index < len(a):
            ioobe(index, len(a))
        return a[index]

    @jmethod("set", "(ILjava/lang/Object;)Ljava/lang/Object;")
    def set(self, index, item):
        a = self._a
        if not 0 <= index < len(a):
            ioobe(index, len(a))
        old = a[index]
        a[index] = item
        return old

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        self.modCount += 1
        self._a.append(item)
        return 1

    @jmethod("add", "(ILjava/lang/Object;)V")
    def add_at(self, index, item):
        if index < 0 or index > len(self._a):
            ioobe(index, len(self._a))
        self.modCount += 1
        self._a.insert(index, item)

    @jmethod("remove", "(I)Ljava/lang/Object;")
    def remove_at(self, index):
        a = self._a
        if not 0 <= index < len(a):
            ioobe(index, len(a))
        self.modCount += 1
        return a.pop(index)

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove_object(self, item):
        a = self._a
        for index in range(len(a)):
            if jequals(item, a[index]):
                self.modCount += 1
                del a[index]
                return 1
        return 0

    @jmethod("clear", "()V")
    def clear(self):
        self.modCount += 1
        self._a.clear()

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        return 1 if self.indexOf(item) >= 0 else 0

    @jmethod("indexOf", "(Ljava/lang/Object;)I")
    def indexOf(self, item):
        a = self._a
        for index in range(len(a)):
            if jequals(item, a[index]):
                return index
        return -1

    @jmethod("addAll", "(Ljava/util/Collection;)Z")
    @jmethod("addAll", "(ILjava/util/Collection;)Z")
    def addAll(self, first, second=None):
        index, other = (len(self._a), first) if second is None else (first, second)
        if index < 0 or index > len(self._a):
            ioobe(index, len(self._a))
        items = list(iterate(check_nonnull(other)))
        self.modCount += 1
        self._a[index:index] = items
        return 1 if items else 0

    @jmethod("removeIf", "(Ljava/util/function/Predicate;)Z")
    def removeIf(self, predicate):
        check_nonnull(predicate)
        kept = [item for item in self._a if not predicate.test(item)]
        changed = len(kept) != len(self._a)
        if changed:
            self.modCount += 1
            self._a[:] = kept
        return 1 if changed else 0

    @jmethod("removeAll", "(Ljava/util/Collection;)Z")
    def removeAll(self, other):
        check_nonnull(other)
        kept = [item for item in self._a if not other.contains(item)]
        changed = len(kept) != len(self._a)
        if changed:
            self.modCount += 1
            self._a[:] = kept
        return 1 if changed else 0

    @jmethod("retainAll", "(Ljava/util/Collection;)Z")
    def retainAll(self, other):
        check_nonnull(other)
        kept = [item for item in self._a if other.contains(item)]
        changed = len(kept) != len(self._a)
        if changed:
            self.modCount += 1
            self._a[:] = kept
        return 1 if changed else 0

    @jmethod("sort", "(Ljava/util/Comparator;)V")
    def sort(self, comparator):
        expected = self.modCount
        items = list(self._a)
        _sort(items, comparator)
        if self.modCount != expected:
            runtime.throw_new("java.util.ConcurrentModificationException", None)
        self._a[:] = items
        self.modCount += 1

    @jmethod("forEach", "(Ljava/util/function/Consumer;)V")
    def forEach(self, action):
        check_nonnull(action)
        expected = self.modCount
        for item in list(self._a):
            action.accept(item)
            if self.modCount != expected:
                runtime.throw_new("java.util.ConcurrentModificationException", None)

    @jmethod("replaceAll", "(Ljava/util/function/UnaryOperator;)V")
    def replaceAll(self, operator):
        self._a[:] = [operator.apply(item) for item in self._a]

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return ListItr(self, 0)

    @jmethod("toArray", "()[Ljava/lang/Object;")
    @jmethod("toArray", "([Ljava/lang/Object;)[Ljava/lang/Object;")
    def toArray(self, target=None):
        return AbstractCollection.toArray(self, target)

    @jmethod("ensureCapacity", "(I)V")
    @jmethod("trimToSize", "()V")
    def ensureCapacity(self, capacity=0):
        return None

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        copy = type(self).__new__(type(self))
        copy._a = list(self._a)
        copy.modCount = 0
        return copy

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "[" + ", ".join("(this Collection)" if item is self else jstring(item) for item in self._a) + "]"


class ImmutableList(ArrayList):
    """List.of and the unmodifiable views"""

    def __init__(self, items):
        ArrayList.__init__(self)
        self._a = list(items)

    def add(self, item):
        unsupported()

    add_at = set = remove_at = remove_object = clear = addAll = removeIf = removeAll = retainAll = sort = replaceAll = (
        lambda self, *args: unsupported())

    def remove(self, value):
        unsupported()

    def iterator(self):
        return PyIterator(self._a)

    def listIterator(self, index=0):
        return ListItr(self, index)


host_class("java.util.ImmutableCollections$ListN", interfaces=("java.util.List",))(ImmutableList)


@host_class("java.util.Vector", interfaces=("java.util.List", "java.util.RandomAccess"))
class Vector(ArrayList):
    @jmethod("addElement", "(Ljava/lang/Object;)V")
    def addElement(self, item):
        self.add(item)

    @jmethod("elementAt", "(I)Ljava/lang/Object;")
    def elementAt(self, index):
        return self.get(index)

    @jmethod("firstElement", "()Ljava/lang/Object;")
    def firstElement(self):
        if not self._a:
            no_such_element()
        return self._a[0]

    @jmethod("lastElement", "()Ljava/lang/Object;")
    def lastElement(self):
        if not self._a:
            no_such_element()
        return self._a[-1]

    @jmethod("removeAllElements", "()V")
    def removeAllElements(self):
        self.clear()

    @jmethod("removeElementAt", "(I)V")
    def removeElementAt(self, index):
        self.remove_at(index)

    @jmethod("insertElementAt", "(Ljava/lang/Object;I)V")
    def insertElementAt(self, item, index):
        self.add_at(index, item)

    @jmethod("elements", "()Ljava/util/Enumeration;")
    def elements(self):
        return PyIterator(list(self._a))


@host_class("java.util.Stack")
class Stack(Vector):
    @jmethod("push", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def push(self, item):
        self.add(item)
        return item

    @jmethod("pop", "()Ljava/lang/Object;")
    def pop(self):
        if not self._a:
            runtime.throw_new("java.util.EmptyStackException", None)
        return self.remove_at(len(self._a) - 1)

    @jmethod("peek", "()Ljava/lang/Object;")
    def peek(self):
        if not self._a:
            runtime.throw_new("java.util.EmptyStackException", None)
        return self._a[-1]

    @jmethod("empty", "()Z")
    def empty(self):
        return 0 if self._a else 1

    @jmethod("search", "(Ljava/lang/Object;)I")
    def search(self, item):
        index = self.lastIndexOf(item)
        return len(self._a) - index if index >= 0 else -1


@host_class("java.util.AbstractQueue", interfaces=("java.util.Queue",))
class AbstractQueue(AbstractCollection, Queue):
    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        if self.offer(item):
            return 1
        runtime.throw_new("java.lang.IllegalStateException", "Queue full")

    @jmethod("remove", "()Ljava/lang/Object;")
    def remove_head(self):
        item = self.poll()
        if item is None:
            no_such_element()
        return item

    @jmethod("element", "()Ljava/lang/Object;")
    def element(self):
        item = self.peek()
        if item is None:
            no_such_element()
        return item


@host_class("java.util.LinkedList", interfaces=("java.util.List", "java.util.Deque", "java.lang.Cloneable"))
class LinkedList(AbstractList, Deque):
    """a list and a deque over a python list; the element order and the exceptions are the ones of the java class"""

    def __init__(self, source=None):
        self._a = list(iterate(source)) if source is not None else []
        self.modCount = 0

    @jmethod("<init>", "()V")
    def _init(self):
        LinkedList.__init__(self)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        LinkedList.__init__(self, check_nonnull(source))

    def size(self):
        return len(self._a)

    def get(self, index):
        if not 0 <= index < len(self._a):
            ioobe(index, len(self._a))
        return self._a[index]

    def set(self, index, item):
        if not 0 <= index < len(self._a):
            ioobe(index, len(self._a))
        old = self._a[index]
        self._a[index] = item
        return old

    @jmethod("add", "(Ljava/lang/Object;)Z")
    def add(self, item):
        self.modCount += 1
        self._a.append(item)
        return 1

    @jmethod("add", "(ILjava/lang/Object;)V")
    def add_at(self, index, item):
        if index < 0 or index > len(self._a):
            ioobe(index, len(self._a))
        self.modCount += 1
        self._a.insert(index, item)

    @jmethod("remove", "(I)Ljava/lang/Object;")
    def remove_at(self, index):
        if not 0 <= index < len(self._a):
            ioobe(index, len(self._a))
        self.modCount += 1
        return self._a.pop(index)

    @jmethod("remove", "()Ljava/lang/Object;")
    def remove_head(self):
        return self.removeFirst()

    def remove(self, *args):
        if not args:
            return self.removeFirst()
        return AbstractList.remove(self, args[0])

    def _empty_check(self):
        if not self._a:
            no_such_element()

    @jmethod("addFirst", "(Ljava/lang/Object;)V")
    @jmethod("push", "(Ljava/lang/Object;)V")
    def addFirst(self, item):
        self.modCount += 1
        self._a.insert(0, item)

    @jmethod("addLast", "(Ljava/lang/Object;)V")
    def addLast(self, item):
        self.modCount += 1
        self._a.append(item)

    @jmethod("offer", "(Ljava/lang/Object;)Z")
    @jmethod("offerLast", "(Ljava/lang/Object;)Z")
    def offer(self, item):
        return self.add(item)

    @jmethod("offerFirst", "(Ljava/lang/Object;)Z")
    def offerFirst(self, item):
        self.addFirst(item)
        return 1

    @jmethod("removeFirst", "()Ljava/lang/Object;")
    @jmethod("pop", "()Ljava/lang/Object;")
    def removeFirst(self):
        self._empty_check()
        self.modCount += 1
        return self._a.pop(0)

    @jmethod("removeLast", "()Ljava/lang/Object;")
    def removeLast(self):
        self._empty_check()
        self.modCount += 1
        return self._a.pop()

    @jmethod("poll", "()Ljava/lang/Object;")
    @jmethod("pollFirst", "()Ljava/lang/Object;")
    def poll(self):
        if not self._a:
            return None
        self.modCount += 1
        return self._a.pop(0)

    @jmethod("pollLast", "()Ljava/lang/Object;")
    def pollLast(self):
        if not self._a:
            return None
        self.modCount += 1
        return self._a.pop()

    @jmethod("getFirst", "()Ljava/lang/Object;")
    @jmethod("element", "()Ljava/lang/Object;")
    def getFirst(self):
        self._empty_check()
        return self._a[0]

    @jmethod("getLast", "()Ljava/lang/Object;")
    def getLast(self):
        self._empty_check()
        return self._a[-1]

    @jmethod("peek", "()Ljava/lang/Object;")
    @jmethod("peekFirst", "()Ljava/lang/Object;")
    def peek(self):
        return self._a[0] if self._a else None

    @jmethod("peekLast", "()Ljava/lang/Object;")
    def peekLast(self):
        return self._a[-1] if self._a else None

    @jmethod("descendingIterator", "()Ljava/util/Iterator;")
    def descendingIterator(self):
        return PyIterator(list(reversed(self._a)))

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return LinkedList(self)


@host_class("java.util.ArrayDeque", interfaces=("java.util.Deque", "java.lang.Cloneable"))
class ArrayDeque(AbstractCollection, Deque):
    """null elements are refused, the iterator walks from head to tail"""

    def __init__(self, source=None):
        self._a = []
        self.modCount = 0
        if source is not None and not isinstance(source, int):
            self._a.extend(iterate(source))

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=0):
        ArrayDeque.__init__(self, capacity)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        ArrayDeque.__init__(self, check_nonnull(source))

    def size(self):
        return len(self._a)

    def iterator(self):
        return PyIterator(list(self._a), self._remove_identity)

    def _remove_identity(self, item):
        for index, element in enumerate(self._a):
            if element is item:
                del self._a[index]
                return

    @jmethod("addFirst", "(Ljava/lang/Object;)V")
    @jmethod("push", "(Ljava/lang/Object;)V")
    def addFirst(self, item):
        self._a.insert(0, check_nonnull(item))

    @jmethod("addLast", "(Ljava/lang/Object;)V")
    def addLast(self, item):
        self._a.append(check_nonnull(item))

    @jmethod("add", "(Ljava/lang/Object;)Z")
    @jmethod("offer", "(Ljava/lang/Object;)Z")
    @jmethod("offerLast", "(Ljava/lang/Object;)Z")
    def add(self, item):
        self.addLast(item)
        return 1

    @jmethod("offerFirst", "(Ljava/lang/Object;)Z")
    def offerFirst(self, item):
        self.addFirst(item)
        return 1

    @jmethod("removeFirst", "()Ljava/lang/Object;")
    @jmethod("pop", "()Ljava/lang/Object;")
    @jmethod("remove", "()Ljava/lang/Object;")
    def removeFirst(self):
        if not self._a:
            no_such_element()
        return self._a.pop(0)

    @jmethod("removeLast", "()Ljava/lang/Object;")
    def removeLast(self):
        if not self._a:
            no_such_element()
        return self._a.pop()

    @jmethod("pollFirst", "()Ljava/lang/Object;")
    @jmethod("poll", "()Ljava/lang/Object;")
    def pollFirst(self):
        return self._a.pop(0) if self._a else None

    @jmethod("pollLast", "()Ljava/lang/Object;")
    def pollLast(self):
        return self._a.pop() if self._a else None

    @jmethod("getFirst", "()Ljava/lang/Object;")
    @jmethod("element", "()Ljava/lang/Object;")
    def getFirst(self):
        if not self._a:
            no_such_element()
        return self._a[0]

    @jmethod("getLast", "()Ljava/lang/Object;")
    def getLast(self):
        if not self._a:
            no_such_element()
        return self._a[-1]

    @jmethod("peekFirst", "()Ljava/lang/Object;")
    @jmethod("peek", "()Ljava/lang/Object;")
    def peekFirst(self):
        return self._a[0] if self._a else None

    @jmethod("peekLast", "()Ljava/lang/Object;")
    def peekLast(self):
        return self._a[-1] if self._a else None

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove_object(self, item):
        for index, element in enumerate(self._a):
            if jequals(item, element):
                del self._a[index]
                return 1
        return 0

    def remove(self, *args):
        return self.removeFirst() if not args else self.remove_object(args[0])

    @jmethod("clear", "()V")
    def clear(self):
        self._a.clear()

    @jmethod("descendingIterator", "()Ljava/util/Iterator;")
    def descendingIterator(self):
        return PyIterator(list(reversed(self._a)))

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return ArrayDeque(self)


@host_class("java.util.PriorityQueue", interfaces=("java.util.Queue",))
class PriorityQueue(AbstractQueue):
    """the binary heap of the jdk with its sift algorithms, so the iteration order and toString match the array order a jvm shows"""

    def __init__(self, first=None, second=None):
        self._q = []
        self._cmp = None
        self.modCount = 0
        for arg in (first, second):
            if arg is None or isinstance(arg, int):
                continue
            if hasattr(arg, "compare"):
                self._cmp = arg
            else:
                if isinstance(arg, PriorityQueue):
                    self._cmp = arg._cmp
                for item in iterate(arg):
                    self.offer(item)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=11):
        PriorityQueue.__init__(self)

    @jmethod("<init>", "(Ljava/util/Comparator;)V")
    def _init_cmp(self, comparator):
        PriorityQueue.__init__(self, comparator)

    @jmethod("<init>", "(ILjava/util/Comparator;)V")
    def _init_cap_cmp(self, capacity, comparator):
        PriorityQueue.__init__(self, comparator)

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        PriorityQueue.__init__(self, source)

    def _compare(self, a, b):
        return compare_with(self._cmp, a, b)

    def size(self):
        return len(self._q)

    @jmethod("offer", "(Ljava/lang/Object;)Z")
    @jmethod("add", "(Ljava/lang/Object;)Z")
    def offer(self, item):
        check_nonnull(item)
        self.modCount += 1
        q = self._q
        q.append(item)
        k = len(q) - 1
        if k == 0:
            self._compare(item, item)
        while k > 0:
            parent = (k - 1) >> 1
            if self._compare(item, q[parent]) >= 0:
                break
            q[k] = q[parent]
            k = parent
        q[k] = item
        return 1

    def add(self, item):
        return self.offer(item)

    @jmethod("peek", "()Ljava/lang/Object;")
    def peek(self):
        return self._q[0] if self._q else None

    @jmethod("poll", "()Ljava/lang/Object;")
    def poll(self):
        q = self._q
        if not q:
            return None
        self.modCount += 1
        result = q[0]
        last = q.pop()
        if q:
            self._sift_down(0, last)
        return result

    def _sift_down(self, k, item):
        q = self._q
        n = len(q)
        half = n >> 1
        while k < half:
            child = 2 * k + 1
            c = q[child]
            right = child + 1
            if right < n and self._compare(c, q[right]) > 0:
                child = right
                c = q[child]
            if self._compare(item, c) <= 0:
                break
            q[k] = c
            k = child
        q[k] = item

    def _sift_up(self, k, item):
        q = self._q
        while k > 0:
            parent = (k - 1) >> 1
            if self._compare(item, q[parent]) >= 0:
                break
            q[k] = q[parent]
            k = parent
        q[k] = item

    def _remove_at(self, index):
        q = self._q
        self.modCount += 1
        last_index = len(q) - 1
        if last_index == index:
            q.pop()
            return
        moved = q.pop()
        self._sift_down(index, moved)
        if q[index] is moved:
            self._sift_up(index, moved)

    @jmethod("remove", "(Ljava/lang/Object;)Z")
    def remove_object(self, item):
        for index, element in enumerate(self._q):
            if jequals(item, element):
                self._remove_at(index)
                return 1
        return 0

    def remove(self, *args):
        return self.remove_head() if not args else self.remove_object(args[0])

    @jmethod("clear", "()V")
    def clear(self):
        self.modCount += 1
        self._q.clear()

    @jmethod("comparator", "()Ljava/util/Comparator;")
    def comparator(self):
        return self._cmp

    def iterator(self):
        return PyIterator(list(self._q), lambda item: self.remove_object(item))

    @jmethod("contains", "(Ljava/lang/Object;)Z")
    def contains(self, item):
        return 1 if any(jequals(item, element) for element in self._q) else 0
