"""java.util.stream: Stream, IntStream, LongStream, DoubleStream, Collectors, Collector and the primitive Optionals

a stream pulls its elements through the pipeline one at a time when the terminal operation runs, so the side effects of
map, filter and peek happen in the order a sequential java stream gives them, limit and the matching operations stop
early, and Stream.iterate and Stream.generate without a bound are streams like any other. a stream is used once, as in
java. a collector receives the whole list of elements at the end; stateful collectors do not see them one by one"""

import collections.abc as _abc
import itertools as _itertools

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import compare_natural, compare_with, jequals, jhash
from .jlang import Boolean, Double, Integer, Long, Object
from .jmap import ArrayList, HashMap, HashSet
from .jutil import check_nonnull, iterate, to_array

_KINDS = {"obj": "Stream", "int": "IntStream", "long": "LongStream", "double": "DoubleStream"}


def _wrap(kind, value):
    return {"int": Integer.valueOf, "long": Long.valueOf, "double": Double}.get(kind, lambda x: x)(value)


def _unbox(kind, value):
    return value.value if kind != "obj" and hasattr(value, "value") else value


class _Optional(Object):
    _KIND = "int"

    def __init__(self, value=None, present=False):
        self._v, self._present = value, present

    def isPresent(self):
        return 1 if self._present else 0

    def isEmpty(self):
        return 0 if self._present else 1

    def _get(self):
        if not self._present:
            runtime.throw_new("java.util.NoSuchElementException", "No value present")
        return self._v

    def orElse(self, other):
        return self._v if self._present else other

    def orElseGet(self, supplier):
        return self._v if self._present else getattr(supplier, "getAsInt", getattr(supplier, "getAsLong", getattr(
            supplier, "getAsDouble", None)))()

    def orElseThrow(self, supplier=None):
        if self._present:
            return self._v
        if supplier is None:
            runtime.throw_new("java.util.NoSuchElementException", "No value present")
        raise supplier.get()

    def ifPresent(self, consumer):
        if self._present:
            consumer.accept(self._v)

    def toString(self):
        return "%s[%s]" % (type(self).__name__, self._v) if self._present else type(self).__name__ + ".empty"


def _optional(name, getter, desc, kind):
    cls = type(name, (_Optional,), {"_KIND": kind})
    setattr(cls, getter, _Optional._get)
    setattr(cls, "empty", staticmethod(lambda: cls()))
    setattr(cls, "of", staticmethod(lambda value: cls(value, True)))
    return host_class("java.util." + name, final=True)(cls)


OptionalInt = _optional("OptionalInt", "getAsInt", "I", "int")
OptionalLong = _optional("OptionalLong", "getAsLong", "J", "long")
OptionalDouble = _optional("OptionalDouble", "getAsDouble", "D", "double")
_OPTIONALS = {"int": OptionalInt, "long": OptionalLong, "double": OptionalDouble}


class BaseStream(Object):
    """a stream over an iterable that is pulled one element at a time by the terminal operation, as a sequential java
    stream is: map, filter, peek and flatMap run element by element, limit and the matching operations stop pulling
    as soon as they have their answer, and an unbounded iterate or generate is a stream like any other. a list or tuple
    given to a stream is copied when the stream is made. kind is obj, int, long or double"""

    def __init__(self, items, kind="obj"):
        self._items = items
        self._kind = kind
        self._used = False
        self._close = []
        # element count when the source and every operation so far fix it (jdk SIZED flag), else None
        self._size = len(items) if isinstance(items, (list, tuple, range)) else None

    @staticmethod
    def from_items(items, kind="obj"):
        if not isinstance(items, (range, _abc.Iterator)):
            items = list(items)
        return _CLASSES[kind](items, kind)

    def _take(self):
        if self._used:
            runtime.throw_new("java.lang.IllegalStateException", "stream has already been operated upon or closed")
        self._used = True
        return self._items

    def _new(self, items, kind=None, sized=False):
        kind = kind or self._kind
        made = _CLASSES[kind](items, kind)
        made._size = self._size if sized else None
        return made

    def filter(self, predicate):
        source = self._take()
        return self._new(x for x in source if predicate.test(x))

    def _fn(self, function):
        for name in ("apply", "applyAsInt", "applyAsLong", "applyAsDouble"):
            method = getattr(function, name, None)
            if method is not None:
                return method
        runtime.throw_new("java.lang.AbstractMethodError", "apply")

    def map(self, function):
        call = self._fn(function)
        source = self._take()
        return self._new((call(x) for x in source), sized=True)

    def mapToObj(self, function):
        call = function.apply
        source = self._take()
        return self._new((call(x) for x in source), "obj", True)

    def mapToInt(self, function):
        call = function.applyAsInt
        source = self._take()
        return self._new((call(x) for x in source), "int", True)

    def mapToLong(self, function):
        call = function.applyAsLong
        source = self._take()
        return self._new((call(x) for x in source), "long", True)

    def mapToDouble(self, function):
        call = function.applyAsDouble
        source = self._take()
        return self._new((call(x) for x in source), "double", True)

    def asLongStream(self):
        source = self._take()
        return self._new((int(x) for x in source), "long", True)

    def asDoubleStream(self):
        source = self._take()
        return self._new((float(x) for x in source), "double", True)

    def boxed(self):
        source = self._take()
        kind = self._kind
        return self._new((_wrap(kind, x) for x in source), "obj", True)

    def _flat(self, function, kind):
        source = self._take()

        def run():
            for item in source:
                inner = function.apply(item)
                if inner is not None:
                    yield from inner._take()
        return self._new(run(), kind)

    def flatMap(self, function):
        return self._flat(function, None)

    def flatMapToInt(self, function):
        return self._flat(function, "int")

    def flatMapToLong(self, function):
        return self._flat(function, "long")

    def flatMapToDouble(self, function):
        return self._flat(function, "double")

    def mapMulti(self, mapper):
        source = self._take()

        class Sink(Object):
            def __init__(self, out):
                self._out = out

            def accept(self, value):
                self._out.append(value)

        def run():
            for item in source:
                out = []
                mapper.accept(item, Sink(out))
                yield from out
        return self._new(run(), "obj")

    def distinct(self):
        source = self._take()
        if self._kind != "obj":
            return self._new(dict.fromkeys(source))
        table = {}

        def run():
            for item in source:
                bucket = table.setdefault(jhash(item), [])
                if not any(jequals(item, other) for other in bucket):
                    bucket.append(item)
                    yield item
        return self._new(run())

    def sorted(self, comparator=None):
        import functools
        source = self._take()
        kind = self._kind

        def run():
            items = list(source)
            if kind != "obj":
                yield from sorted(items)
            else:
                yield from sorted(items, key=functools.cmp_to_key(lambda a, b: compare_with(comparator, a, b)))
        return self._new(run(), sized=True)

    def limit(self, count):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", str(count))
        source = self._take()
        made = self._new(_itertools.islice(source, count))
        if self._size is not None:
            made._size = min(self._size, count)
        return made

    def skip(self, count):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", str(count))
        source = self._take()
        made = self._new(_itertools.islice(source, count, None))
        if self._size is not None:
            made._size = max(0, self._size - count)
        return made

    def peek(self, consumer):
        source = self._take()

        def run():
            for item in source:
                consumer.accept(item)
                yield item
        return self._new(run(), sized=True)

    def takeWhile(self, predicate):
        source = self._take()

        def run():
            for item in source:
                if not predicate.test(item):
                    return
                yield item
        return self._new(run())

    def dropWhile(self, predicate):
        source = self._take()
        return self._new(_itertools.dropwhile(predicate.test, source))

    def forEach(self, consumer):
        for item in self._take():
            consumer.accept(item)

    forEachOrdered = forEach

    def count(self):
        source = self._take()
        if self._size is not None:
            return self._size
        total = 0
        for _ in source:
            total += 1
        return total

    def anyMatch(self, predicate):
        return 1 if any(predicate.test(x) for x in self._take()) else 0

    def allMatch(self, predicate):
        return 1 if all(predicate.test(x) for x in self._take()) else 0

    def noneMatch(self, predicate):
        return 0 if any(predicate.test(x) for x in self._take()) else 1

    def _opt(self, value, present=True):
        if self._kind == "obj":
            from .jmisc import Optional
            return Optional.of(value) if present else Optional.empty()
        cls = _OPTIONALS[self._kind]
        return cls(value, True) if present else cls()

    def findFirst(self):
        for item in self._take():
            return self._opt(item)
        return self._opt(None, False)

    findAny = findFirst

    def _extreme(self, comparator, sign):
        best = None
        found = False
        for item in self._take():
            if not found:
                best, found = item, True
            elif self._kind != "obj":
                if (item < best) == (sign < 0) and item != best:
                    best = item
            elif compare_with(comparator, item, best) * sign > 0:
                best = item
        return self._opt(best) if found else self._opt(None, False)

    def min(self, comparator=None):
        return self._extreme(comparator, -1)

    def max(self, comparator=None):
        return self._extreme(comparator, 1)

    def sum(self):
        total = sum(self._take())
        return runtime.wrap32(total) if self._kind == "int" else runtime.wrap64(total) if self._kind == "long" \
            else float(total)

    def average(self):
        total = 0
        count = 0
        for item in self._take():
            total += item
            count += 1
        return OptionalDouble(total / count, True) if count else OptionalDouble()

    def reduce(self, first, second=None, third=None):
        items = iter(self._take())
        if second is None:
            call = self._binary(first)
            for value in items:
                for item in items:
                    value = call(value, item)
                return self._opt(value)
            return self._opt(None, False)
        call = self._binary(second)
        value = first
        for item in items:
            value = call(value, item)
        return value

    def _binary(self, operator):
        for name in ("apply", "applyAsInt", "applyAsLong", "applyAsDouble"):
            method = getattr(operator, name, None)
            if method is not None:
                return method
        runtime.throw_new("java.lang.AbstractMethodError", "apply")

    def collect(self, collector, accumulator=None, combiner=None):
        if accumulator is not None:
            container = collector.get()
            for item in self._take():
                accumulator.accept(container, item)
            return container
        return collector._collect(list(self._take()))

    def toList(self):
        from .jutil import ImmutableList
        return ImmutableList(list(self._take()))

    def toArray(self, generator=None):
        items = list(self._take())
        if self._kind != "obj":
            array = runtime.new_array("[" + {"int": "I", "long": "J", "double": "D"}[self._kind], 0)
            array.extend(items)
            return array
        array = generator.apply(len(items)) if generator is not None else runtime.new_array("[Ljava/lang/Object;", 0)
        if generator is None:
            array.extend(items)
        else:
            array[:] = items
        return array

    def iterator(self):
        from .jutil import PyIterator
        kind = self._kind
        return PyIterator(_wrap(kind, x) for x in self._take())

    def getAsDouble(self):
        return None

    def parallel(self):
        return self

    sequential = unordered = parallel

    def onClose(self, action):
        self._close.append(action)
        return self

    def close(self):
        for action in self._close:
            action.run()
        self._close = []

    def isParallel(self):
        return 0

    def summaryStatistics(self):
        items = list(self._take())
        return {"int": IntSummaryStatistics, "long": LongSummaryStatistics, "double": DoubleSummaryStatistics}[
            self._kind](items)


class _Summary(Object):
    """IntSummaryStatistics, LongSummaryStatistics and DoubleSummaryStatistics: a consumer that keeps count, sum, min and max"""

    _EMPTY_MIN = _EMPTY_MAX = 0
    _ZERO = 0
    _DESC = "I"

    def __init__(self, items=()):
        self._n = 0
        self._sum = self._ZERO
        self._min = self._EMPTY_MIN
        self._max = self._EMPTY_MAX
        for item in items:
            self.accept(item)

    def accept(self, value):
        self._n += 1
        self._sum += value
        if value < self._min:
            self._min = value
        if value > self._max:
            self._max = value

    def combine(self, other):
        self._n += other._n
        self._sum += other._sum
        self._min = min(self._min, other._min)
        self._max = max(self._max, other._max)

    def getCount(self):
        return self._n

    def getSum(self):
        return self._sum

    def getMin(self):
        return self._min

    def getMax(self):
        return self._max

    def getAverage(self):
        return self._sum / self._n if self._n else 0.0

    def toString(self):
        name = type(self).__name__
        if self._DESC == "D":
            return "%s{count=%d, sum=%f, min=%f, average=%f, max=%f}" % (
                name, self._n, self._sum, self._min, self.getAverage(), self._max)
        return "%s{count=%d, sum=%d, min=%d, average=%f, max=%d}" % (
            name, self._n, self._sum, self._min, self.getAverage(), self._max)


def _summary(name, desc, low, high, zero, sum_desc):
    cls = type(name, (_Summary,), {"_EMPTY_MIN": low, "_EMPTY_MAX": high, "_ZERO": zero, "_DESC": desc})
    full = "java.util." + name
    jtype = "L" + full.replace(".", "/") + ";"
    cls.accept = jmethod("accept", "(%s)V" % desc)(_Summary.accept)
    cls.combine = jmethod("combine", "(%s)V" % jtype)(_Summary.combine)
    cls._init0 = jmethod("<init>", "()V")(lambda self: cls.__init__(self))
    cls.getCount = jmethod("getCount", "()J")(_Summary.getCount)
    cls.getSum = jmethod("getSum", "()%s" % sum_desc)(_Summary.getSum)
    cls.getMin = jmethod("getMin", "()%s" % desc)(_Summary.getMin)
    cls.getMax = jmethod("getMax", "()%s" % desc)(_Summary.getMax)
    cls.getAverage = jmethod("getAverage", "()D")(_Summary.getAverage)
    cls.toString = jmethod("toString", "()Ljava/lang/String;")(_Summary.toString)
    return host_class(full, interfaces=("java.util.function.%sConsumer" % {"I": "Int", "J": "Long", "D": "Double"}[desc],))(cls)


IntSummaryStatistics = _summary("IntSummaryStatistics", "I", 0x7FFFFFFF, -0x80000000, 0, "J")
LongSummaryStatistics = _summary("LongSummaryStatistics", "J", 0x7FFFFFFFFFFFFFFF, -0x8000000000000000, 0, "J")
DoubleSummaryStatistics = _summary("DoubleSummaryStatistics", "D", float("inf"), float("-inf"), 0.0, "D")


@host_class("java.util.stream.BaseStream", interfaces=("java.lang.AutoCloseable",))
class _BaseStreamHost(BaseStream):
    pass


def _stream_class(kind, name):
    cls = type(name, (BaseStream,), {})
    return host_class("java.util.stream." + name, interfaces=("java.util.stream.BaseStream",))(cls)


Stream = _stream_class("obj", "Stream")
IntStream = _stream_class("int", "IntStream")
LongStream = _stream_class("long", "LongStream")
DoubleStream = _stream_class("double", "DoubleStream")
_CLASSES = {"obj": Stream, "int": IntStream, "long": LongStream, "double": DoubleStream}


def _of(kind):
    def of(*values):
        if len(values) == 1 and values[0].__class__ is runtime.JArray:
            values = tuple(values[0])
        return BaseStream.from_items(values, kind)
    return staticmethod(of)


def _empty(kind):
    return staticmethod(lambda: BaseStream.from_items([], kind))


def _supplied(supplier):
    for name in ("get", "getAsInt", "getAsLong", "getAsDouble"):
        method = getattr(supplier, name, None)
        if method is not None:
            return method
    runtime.throw_new("java.lang.AbstractMethodError", "get")


def _iterate(kind):
    def iterate_(seed, has_next_or_step, step=None):
        if step is None:
            call = has_next_or_step

            def unbounded():
                value = seed
                while True:
                    yield value
                    value = _step(call, value)
            return BaseStream.from_items(unbounded(), kind)

        def bounded():
            value = seed
            while has_next_or_step.test(value):
                yield value
                value = _step(step, value)
        return BaseStream.from_items(bounded(), kind)
    return staticmethod(iterate_)


def _step(function, value):
    for name in ("apply", "applyAsInt", "applyAsLong", "applyAsDouble"):
        method = getattr(function, name, None)
        if method is not None:
            return method(value)
    runtime.throw_new("java.lang.AbstractMethodError", "apply")


def _generate(kind):
    def generate_(supplier):
        call = _supplied(supplier)

        def unbounded():
            while True:
                yield call()
        return BaseStream.from_items(unbounded(), kind)
    return staticmethod(generate_)


for _kind, _cls in _CLASSES.items():
    _cls.of = _of(_kind)
    _cls.empty = _empty(_kind)
    _cls.iterate = _iterate(_kind)
    _cls.generate = _generate(_kind)
    _cls.concat = staticmethod(lambda a, b, kind=_kind: BaseStream.from_items(_itertools.chain(a._take(), b._take()), kind))
    _cls.ofNullable = staticmethod(lambda value: BaseStream.from_items([] if value is None else [value], "obj"))


def _range(kind, closed):
    return staticmethod(lambda low, high: BaseStream.from_items(range(low, high + (1 if closed else 0)), kind))


IntStream.range = _range("int", False)
IntStream.rangeClosed = _range("int", True)
LongStream.range = _range("long", False)
LongStream.rangeClosed = _range("long", True)


class Collector(Object):
    """a reduction: a python function over the list of elements"""

    def __init__(self, function):
        self._fn = function

    def _collect(self, items):
        return self._fn(items)

    @jstatic("of", "(Ljava/util/function/Supplier;Ljava/util/function/BiConsumer;Ljava/util/function/BinaryOperator;"
                   "[Ljava/util/stream/Collector$Characteristics;)Ljava/util/stream/Collector;")
    def of(supplier, accumulator, combiner, *characteristics):
        def run(items):
            container = supplier.get()
            for item in items:
                accumulator.accept(container, item)
            return container
        return Collector(run)


host_class("java.util.stream.Collector")(Collector)


def _collection(factory, items):
    result = factory()
    for item in items:
        result.add(item)
    return result


def _group(items, classifier, downstream, factory):
    groups = {}
    order = []
    table = factory()
    keys = []
    for item in items:
        key = classifier.apply(item)
        for index, known in enumerate(keys):
            if jequals(known, key):
                groups[index].append(item)
                break
        else:
            keys.append(key)
            groups[len(keys) - 1] = [item]
    for index, key in enumerate(keys):
        table.put(key, downstream._collect(groups[index]))
    return table


@host_class("java.util.stream.Collectors", final=True)
class Collectors(Object):
    @jstatic("toList", "()Ljava/util/stream/Collector;")
    def toList():
        return Collector(lambda items: _collection(ArrayList, items))

    @jstatic("toUnmodifiableList", "()Ljava/util/stream/Collector;")
    def toUnmodifiableList():
        from .jutil import ImmutableList
        return Collector(lambda items: ImmutableList(items))

    @jstatic("toSet", "()Ljava/util/stream/Collector;")
    @jstatic("toUnmodifiableSet", "()Ljava/util/stream/Collector;")
    def toSet():
        return Collector(lambda items: _collection(HashSet, items))

    @jstatic("toCollection", "(Ljava/util/function/Supplier;)Ljava/util/stream/Collector;")
    def toCollection(supplier):
        return Collector(lambda items: _collection(supplier.get, items))

    @jstatic("joining", "()Ljava/util/stream/Collector;")
    @jstatic("joining", "(Ljava/lang/CharSequence;)Ljava/util/stream/Collector;")
    @jstatic("joining", "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/util/stream/Collector;")
    def joining(delimiter="", prefix="", suffix=""):
        from .jlang import _cs
        d, p, s = _cs(delimiter), _cs(prefix), _cs(suffix)
        return Collector(lambda items: p + d.join(_cs(x) for x in items) + s)

    @jstatic("counting", "()Ljava/util/stream/Collector;")
    def counting():
        return Collector(lambda items: Long.valueOf(len(items)))

    @jstatic("summingInt", "(Ljava/util/function/ToIntFunction;)Ljava/util/stream/Collector;")
    def summingInt(function):
        return Collector(lambda items: Integer.valueOf(runtime.wrap32(sum(function.applyAsInt(x) for x in items))))

    @jstatic("summingLong", "(Ljava/util/function/ToLongFunction;)Ljava/util/stream/Collector;")
    def summingLong(function):
        return Collector(lambda items: Long.valueOf(runtime.wrap64(sum(function.applyAsLong(x) for x in items))))

    @jstatic("summingDouble", "(Ljava/util/function/ToDoubleFunction;)Ljava/util/stream/Collector;")
    def summingDouble(function):
        return Collector(lambda items: Double(float(sum(function.applyAsDouble(x) for x in items))))

    @jstatic("averagingInt", "(Ljava/util/function/ToIntFunction;)Ljava/util/stream/Collector;")
    @jstatic("averagingLong", "(Ljava/util/function/ToLongFunction;)Ljava/util/stream/Collector;")
    @jstatic("averagingDouble", "(Ljava/util/function/ToDoubleFunction;)Ljava/util/stream/Collector;")
    def averaging(function):
        call = getattr(function, "applyAsInt", None) or getattr(function, "applyAsLong", None) or \
            function.applyAsDouble
        return Collector(lambda items: Double(sum(call(x) for x in items) / len(items) if items else 0.0))

    @jstatic("mapping", "(Ljava/util/function/Function;Ljava/util/stream/Collector;)Ljava/util/stream/Collector;")
    def mapping(function, downstream):
        return Collector(lambda items: downstream._collect([function.apply(x) for x in items]))

    @jstatic("filtering", "(Ljava/util/function/Predicate;Ljava/util/stream/Collector;)Ljava/util/stream/Collector;")
    def filtering(predicate, downstream):
        return Collector(lambda items: downstream._collect([x for x in items if predicate.test(x)]))

    @jstatic("minBy", "(Ljava/util/Comparator;)Ljava/util/stream/Collector;")
    def minBy(comparator):
        return Collector(lambda items: BaseStream.from_items(items).min(comparator))

    @jstatic("maxBy", "(Ljava/util/Comparator;)Ljava/util/stream/Collector;")
    def maxBy(comparator):
        return Collector(lambda items: BaseStream.from_items(items).max(comparator))

    @jstatic("reducing", "(Ljava/lang/Object;Ljava/util/function/BinaryOperator;)Ljava/util/stream/Collector;")
    def reducing(identity, operator):
        return Collector(lambda items: BaseStream.from_items(items).reduce(identity, operator))

    @jstatic("collectingAndThen", "(Ljava/util/stream/Collector;Ljava/util/function/Function;)Ljava/util/stream/Collector;")
    def collectingAndThen(downstream, finisher):
        return Collector(lambda items: finisher.apply(downstream._collect(items)))

    @jstatic("groupingBy", "(Ljava/util/function/Function;)Ljava/util/stream/Collector;")
    @jstatic("groupingBy", "(Ljava/util/function/Function;Ljava/util/stream/Collector;)Ljava/util/stream/Collector;")
    @jstatic("groupingBy", "(Ljava/util/function/Function;Ljava/util/function/Supplier;Ljava/util/stream/Collector;)"
                           "Ljava/util/stream/Collector;")
    def groupingBy(classifier, second=None, third=None):
        if third is not None:
            factory, downstream = second.get, third
        else:
            factory, downstream = HashMap, second if second is not None else Collectors.toList()
        return Collector(lambda items: _group(items, classifier, downstream, factory))

    @jstatic("partitioningBy", "(Ljava/util/function/Predicate;)Ljava/util/stream/Collector;")
    @jstatic("partitioningBy", "(Ljava/util/function/Predicate;Ljava/util/stream/Collector;)Ljava/util/stream/Collector;")
    def partitioningBy(predicate, downstream=None):
        downstream = downstream or Collectors.toList()

        def run(items):
            from .jmap import LinkedHashMap
            table = LinkedHashMap()
            table.put(Boolean.FALSE, downstream._collect([x for x in items if not predicate.test(x)]))
            table.put(Boolean.TRUE, downstream._collect([x for x in items if predicate.test(x)]))
            return table
        return Collector(run)

    @jstatic("toMap", "(Ljava/util/function/Function;Ljava/util/function/Function;)Ljava/util/stream/Collector;")
    @jstatic("toMap", "(Ljava/util/function/Function;Ljava/util/function/Function;Ljava/util/function/BinaryOperator;)"
                      "Ljava/util/stream/Collector;")
    @jstatic("toMap", "(Ljava/util/function/Function;Ljava/util/function/Function;Ljava/util/function/BinaryOperator;"
                      "Ljava/util/function/Supplier;)Ljava/util/stream/Collector;")
    def toMap(key_fn, value_fn, merge=None, supplier=None):
        def run(items):
            table = supplier.get() if supplier is not None else HashMap()
            for item in items:
                key, value = key_fn.apply(item), check_nonnull(value_fn.apply(item))
                if table.containsKey(key):
                    if merge is None:
                        runtime.throw_new("java.lang.IllegalStateException", "Duplicate key %s (attempted merging "
                                          "values %s and %s)" % (key, table.get(key), value))
                    value = merge.apply(table.get(key), value)
                table.put(key, value)
            return table
        return Collector(run)
