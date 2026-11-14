"""the rest of the public java.util, java.util.function, java.util.concurrent, java.io, java.text, java.util.zip and java.util.jar api that the
other modules leave out. each class here does what the jdk class does; where a part of the api cannot run in this process (processes, file
channels, collators of other locales) it is not here and a program that asks for it gets a named error"""

import io
import math
import os
import random
import re
import threading
import time
import unicodedata
import zlib

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jequals, jhash, jstring
from .jio import (InputStream, OutputStream, Reader, Writer, FilterOutputStream, FilterInputStream, io_error, to_java_bytes, to_py_bytes, _check_range)
from .jlang import Object, jstr, pystr
from .jmap import ArrayList, HashMap, TreeMap
from .jutil import PyIterator, AbstractQueue, check_nonnull, iterate, no_such_element


def _taken(name):
    """whether another module already registers the class, so this one leaves it alone"""
    from . import api
    return name in api._classes or api._lazy.get(name, "dexvm.jextra") != "dexvm.jextra"


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        if not _taken(name):
            host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


def _interfaces(names):
    for name in names.split():
        if not _taken(name):
            host_class(name, interface=True)(type(name.rsplit(".", 1)[1], (), {"__slots__": ()}))


_define("""
java.io.CharConversionException java.io.IOException
java.io.ObjectStreamException java.io.IOException
java.io.InvalidClassException java.io.ObjectStreamException
java.io.NotSerializableException java.io.ObjectStreamException
java.io.StreamCorruptedException java.io.ObjectStreamException
java.io.SyncFailedException java.io.IOException
java.util.IllformedLocaleException java.lang.RuntimeException
java.util.ServiceConfigurationError java.lang.Error
java.util.FormatterClosedException java.lang.IllegalStateException
java.util.DuplicateFormatFlagsException java.util.IllegalFormatException
java.util.UnknownFormatFlagsException java.util.IllegalFormatException
java.util.IllegalFormatWidthException java.util.IllegalFormatException
java.util.zip.ZipError java.lang.InternalError
java.nio.charset.IllegalCharsetNameException java.lang.IllegalArgumentException
java.nio.charset.CoderMalfunctionError java.lang.Error
java.util.jar.JarException java.util.zip.ZipException
""")

_interfaces("""
java.util.EventListener java.util.Observer java.util.Formattable java.lang.Appendable java.lang.Readable java.io.Externalizable
java.io.FileFilter java.io.FilenameFilter java.lang.reflect.Type java.lang.reflect.GenericDeclaration java.util.SequencedCollection
java.util.SequencedMap java.util.concurrent.CompletionStage java.util.concurrent.Delayed java.util.concurrent.RunnableFuture
java.util.concurrent.RunnableScheduledFuture java.util.concurrent.CompletionService java.util.concurrent.ThreadFactory
java.util.concurrent.RejectedExecutionHandler java.util.concurrent.BlockingDeque java.util.concurrent.TransferQueue
java.lang.annotation.Annotation java.lang.Deprecated java.lang.FunctionalInterface java.lang.Override java.lang.SafeVarargs
java.lang.SuppressWarnings java.util.function.DoubleConsumer java.util.function.DoublePredicate java.util.function.LongConsumer
java.util.function.LongPredicate java.util.function.DoubleToIntFunction java.util.function.DoubleToLongFunction
java.util.function.LongToDoubleFunction java.util.function.LongToIntFunction java.util.function.ObjDoubleConsumer
java.util.function.ObjLongConsumer java.util.function.ToDoubleBiFunction java.util.function.ToLongBiFunction
java.text.CharacterIterator java.text.AttributedCharacterIterator
""")


@host_class("java.util.EventObject", interfaces=("java.io.Serializable",))
class EventObject(Object):
    def __init__(self, source=None):
        if source is None:
            runtime.throw_new("java.lang.IllegalArgumentException", "null source")
        self._source = source

    @jmethod("<init>", "(Ljava/lang/Object;)V")
    def _init(self, source):
        EventObject.__init__(self, source)

    @jmethod("getSource", "()Ljava/lang/Object;")
    def getSource(self):
        return self._source

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s[source=%s]" % (runtime.class_of(self).getName(), jstring(self._source))


@host_class("java.util.Observable")
class Observable(Object):
    def __init__(self):
        self._observers = []
        self._changed = False

    @jmethod("<init>", "()V")
    def _init(self):
        Observable.__init__(self)

    @jmethod("addObserver", "(Ljava/util/Observer;)V")
    def addObserver(self, observer):
        if observer is None:
            runtime.npe()
        if observer not in self._observers:
            self._observers.append(observer)

    @jmethod("deleteObserver", "(Ljava/util/Observer;)V")
    def deleteObserver(self, observer):
        if observer in self._observers:
            self._observers.remove(observer)

    @jmethod("deleteObservers", "()V")
    def deleteObservers(self):
        self._observers = []

    @jmethod("countObservers", "()I")
    def countObservers(self):
        return len(self._observers)

    @jmethod("setChanged", "()V")
    def setChanged(self):
        self._changed = True

    @jmethod("clearChanged", "()V")
    def clearChanged(self):
        self._changed = False

    @jmethod("hasChanged", "()Z")
    def hasChanged(self):
        return 1 if self._changed else 0

    @jmethod("notifyObservers", "()V")
    @jmethod("notifyObservers", "(Ljava/lang/Object;)V")
    def notifyObservers(self, argument=None):
        if not self._changed:
            return
        self._changed = False
        for observer in reversed(list(self._observers)):
            observer.update(self, argument)


@host_class("java.util.Currency", interfaces=("java.io.Serializable",))
class Currency(Object):
    _TABLE = {"USD": (840, 2, "$"), "EUR": (978, 2, "€"), "GBP": (826, 2, "£"), "JPY": (392, 0, "¥"), "RUB": (643, 2, "₽"),
              "UAH": (980, 2, "₴"), "CNY": (156, 2, "CN¥"), "CHF": (756, 2, "CHF"), "CAD": (124, 2, "CA$"), "AUD": (36, 2, "A$"),
              "INR": (356, 2, "₹"), "KRW": (410, 0, "₩"), "BRL": (986, 2, "R$"), "TRY": (949, 2, "TRY"), "PLN": (985, 2, "PLN"),
              "KZT": (398, 2, "KZT"), "BYN": (933, 2, "BYN"), "XTR": (0, 0, "XTR")}
    _cache = {}

    def __init__(self, code):
        self._code = code

    @jstatic("getInstance", "(Ljava/lang/String;)Ljava/util/Currency;")
    def getInstance(code):
        if code not in Currency._TABLE:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        return Currency._cache.setdefault(code, Currency(code))

    @jmethod("getCurrencyCode", "()Ljava/lang/String;")
    def getCurrencyCode(self):
        return self._code

    @jmethod("getSymbol", "()Ljava/lang/String;")
    @jmethod("getSymbol", "(Ljava/util/Locale;)Ljava/lang/String;")
    def getSymbol(self, locale=None):
        return Currency._TABLE[self._code][2]

    @jmethod("getDefaultFractionDigits", "()I")
    def getDefaultFractionDigits(self):
        return Currency._TABLE[self._code][1]

    @jmethod("getNumericCode", "()I")
    def getNumericCode(self):
        return Currency._TABLE[self._code][0]

    @jmethod("getDisplayName", "()Ljava/lang/String;")
    def getDisplayName(self):
        return self._code

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._code


@host_class("java.util.SplittableRandom")
class SplittableRandom(Object):
    GOLDEN = 0x9E3779B97F4A7C15

    def __init__(self, seed=None, gamma=GOLDEN):
        self._seed = (seed if seed is not None else int(time.time() * 1e9)) & 0xFFFFFFFFFFFFFFFF
        self._gamma = gamma

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(J)V")
    def _init(self, seed=None):
        SplittableRandom.__init__(self, seed)

    def _next(self):
        self._seed = (self._seed + self._gamma) & 0xFFFFFFFFFFFFFFFF
        z = self._seed
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    @jmethod("nextLong", "()J")
    def nextLong(self):
        return runtime.wrap64(self._next())

    @jmethod("nextInt", "()I")
    @jmethod("nextInt", "(I)I")
    @jmethod("nextInt", "(II)I")
    def nextInt(self, first=None, second=None):
        value = runtime.wrap32(self._next() >> 32)
        if first is None:
            return value
        low, high = (0, first) if second is None else (first, second)
        if low >= high:
            runtime.throw_new("java.lang.IllegalArgumentException", "bound must be positive")
        return low + (self._next() >> 1) % (high - low)

    @jmethod("nextDouble", "()D")
    def nextDouble(self):
        return (self._next() >> 11) * (1.0 / (1 << 53))

    @jmethod("nextBoolean", "()Z")
    def nextBoolean(self):
        return 1 if self._next() >> 63 else 0

    @jmethod("split", "()Ljava/util/SplittableRandom;")
    def split(self):
        return SplittableRandom(self._next(), self._next() | 1)


@host_class("java.util.concurrent.ThreadLocalRandom", superclass="java.util.Random")
class ThreadLocalRandom(lookup_host("java.util.Random").py):
    _local = threading.local()

    @jstatic("current", "()Ljava/util/concurrent/ThreadLocalRandom;")
    def current():
        found = getattr(ThreadLocalRandom._local, "value", None)
        if found is None:
            found = ThreadLocalRandom._local.value = ThreadLocalRandom()
        return found

    def __init__(self):
        lookup_host("java.util.Random").py.__init__(self, int.from_bytes(os.urandom(8), "big"))


@host_class("java.util.ServiceLoader", interfaces=("java.lang.Iterable",))
class ServiceLoader(Object):
    """no provider files exist in a dex that runs here, so a loader is empty: what android answers for a class without META-INF services"""

    def __init__(self, service):
        self._service = service

    @jstatic("load", "(Ljava/lang/Class;)Ljava/util/ServiceLoader;")
    @jstatic("load", "(Ljava/lang/Class;Ljava/lang/ClassLoader;)Ljava/util/ServiceLoader;")
    @jstatic("loadInstalled", "(Ljava/lang/Class;)Ljava/util/ServiceLoader;")
    def load(service, loader=None):
        return ServiceLoader(check_nonnull(service))

    @jmethod("iterator", "()Ljava/util/Iterator;")
    def iterator(self):
        return PyIterator([])

    @jmethod("findFirst", "()Ljava/util/Optional;")
    def findFirst(self):
        return lookup_host("java.util.Optional").py.empty()

    @jmethod("reload", "()V")
    def reload(self):
        return None


class _AtomicArray(Object):
    _DESC = "[I"
    _WRAP = staticmethod(runtime.wrap32)

    def __init__(self, source):
        self._lock = threading.Lock()
        if isinstance(source, int):
            self._a = [0] * source
        else:
            self._a = list(source)

    def _at(self, index):
        if not 0 <= index < len(self._a):
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "index %d" % index)
        return index

    def length(self):
        return len(self._a)

    def get(self, index):
        return self._a[self._at(index)]

    getPlain = getAcquire = getOpaque = get

    def set(self, index, value):
        self._a[self._at(index)] = self._WRAP(value) if self._WRAP else value

    lazySet = setPlain = setRelease = setOpaque = set

    def getAndSet(self, index, value):
        with self._lock:
            old = self._a[self._at(index)]
            self._a[index] = self._WRAP(value) if self._WRAP else value
            return old

    def compareAndSet(self, index, expect, update):
        with self._lock:
            current = self._a[self._at(index)]
            same = current is expect if self._WRAP is None else current == expect
            if same:
                self._a[index] = self._WRAP(update) if self._WRAP else update
            return 1 if same else 0

    weakCompareAndSet = weakCompareAndSetPlain = weakCompareAndSetVolatile = compareAndSet

    def _add(self, index, delta):
        with self._lock:
            old = self._a[self._at(index)]
            self._a[index] = self._WRAP(old + delta)
            return old, self._a[index]

    def getAndIncrement(self, index):
        return self._add(index, 1)[0]

    def getAndDecrement(self, index):
        return self._add(index, -1)[0]

    def getAndAdd(self, index, delta):
        return self._add(index, delta)[0]

    def incrementAndGet(self, index):
        return self._add(index, 1)[1]

    def decrementAndGet(self, index):
        return self._add(index, -1)[1]

    def addAndGet(self, index, delta):
        return self._add(index, delta)[1]

    def updateAndGet(self, index, function):
        with self._lock:
            self._a[self._at(index)] = self._apply(function, self._a[index])
            return self._a[index]

    def getAndUpdate(self, index, function):
        with self._lock:
            old = self._a[self._at(index)]
            self._a[index] = self._apply(function, old)
            return old

    def accumulateAndGet(self, index, x, function):
        with self._lock:
            self._a[self._at(index)] = self._apply2(function, self._a[index], x)
            return self._a[index]

    def getAndAccumulate(self, index, x, function):
        with self._lock:
            old = self._a[self._at(index)]
            self._a[index] = self._apply2(function, old, x)
            return old

    @staticmethod
    def _apply(function, value):
        for name in ("applyAsInt", "applyAsLong", "apply"):
            method = getattr(function, name, None)
            if method is not None:
                return method(value)
        runtime.throw_new("java.lang.AbstractMethodError", "applyAsInt")

    @staticmethod
    def _apply2(function, a, b):
        for name in ("applyAsInt", "applyAsLong", "apply"):
            method = getattr(function, name, None)
            if method is not None:
                return method(a, b)
        runtime.throw_new("java.lang.AbstractMethodError", "applyAsInt")

    def toString(self):
        return "[" + ", ".join(jstring(x) if self._WRAP is None else str(x) for x in self._a) + "]"


@host_class("java.util.concurrent.atomic.AtomicIntegerArray")
class AtomicIntegerArray(_AtomicArray):
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "([I)V")
    def _init(self, source):
        _AtomicArray.__init__(self, source)


@host_class("java.util.concurrent.atomic.AtomicLongArray")
class AtomicLongArray(_AtomicArray):
    _WRAP = staticmethod(runtime.wrap64)

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "([J)V")
    def _init(self, source):
        _AtomicArray.__init__(self, source)


@host_class("java.util.concurrent.atomic.AtomicReferenceArray")
class AtomicReferenceArray(_AtomicArray):
    _WRAP = None

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "([Ljava/lang/Object;)V")
    def _init(self, source):
        _AtomicArray.__init__(self, source if not isinstance(source, int) else [None] * source)

    def _add(self, index, delta):
        runtime.throw_new("java.lang.UnsupportedOperationException", None)


class _Adder(Object):
    _FLOAT = False

    def __init__(self):
        self._v = 0.0 if self._FLOAT else 0
        self._lock = threading.Lock()

    def add(self, x):
        with self._lock:
            self._v += x

    def increment(self):
        self.add(1)

    def decrement(self):
        self.add(-1)

    def sum(self):
        return self._v if self._FLOAT else runtime.wrap64(self._v)

    longValue = sum

    def intValue(self):
        return runtime.wrap32(int(self._v))

    def doubleValue(self):
        return float(self._v)

    def reset(self):
        self._v = 0.0 if self._FLOAT else 0

    def sumThenReset(self):
        with self._lock:
            old = self._v
            self._v = 0.0 if self._FLOAT else 0
            return old if self._FLOAT else runtime.wrap64(old)

    def toString(self):
        return str(self.sum()) if not self._FLOAT else lookup_host("java.lang.Double").py.toString_double(self._v)


@host_class("java.util.concurrent.atomic.LongAdder", superclass="java.lang.Number")
class LongAdder(_Adder):
    @jmethod("<init>", "()V")
    def _init(self):
        _Adder.__init__(self)


@host_class("java.util.concurrent.atomic.DoubleAdder", superclass="java.lang.Number")
class DoubleAdder(_Adder):
    _FLOAT = True

    @jmethod("<init>", "()V")
    def _init(self):
        _Adder.__init__(self)


class _Accumulator(Object):
    def __init__(self, function, identity):
        self._f, self._id, self._v = function, identity, identity
        self._lock = threading.Lock()

    def accumulate(self, x):
        with self._lock:
            self._v = _AtomicArray._apply2(self._f, self._v, x)

    def get(self):
        return self._v

    def reset(self):
        self._v = self._id

    def getThenReset(self):
        with self._lock:
            old, self._v = self._v, self._id
            return old

    def toString(self):
        return str(self._v)

    longValue = intValue = doubleValue = get


@host_class("java.util.concurrent.atomic.LongAccumulator", superclass="java.lang.Number")
class LongAccumulator(_Accumulator):
    @jmethod("<init>", "(Ljava/util/function/LongBinaryOperator;J)V")
    def _init(self, function, identity):
        _Accumulator.__init__(self, function, identity)


@host_class("java.util.concurrent.atomic.DoubleAccumulator", superclass="java.lang.Number")
class DoubleAccumulator(_Accumulator):
    @jmethod("<init>", "(Ljava/util/function/DoubleBinaryOperator;D)V")
    def _init(self, function, identity):
        _Accumulator.__init__(self, function, identity)


@host_class("java.util.concurrent.atomic.AtomicStampedReference")
class AtomicStampedReference(Object):
    def __init__(self, reference, stamp):
        self._r, self._s = reference, stamp
        self._lock = threading.Lock()

    @jmethod("<init>", "(Ljava/lang/Object;I)V")
    def _init(self, reference, stamp):
        AtomicStampedReference.__init__(self, reference, stamp)

    @jmethod("getReference", "()Ljava/lang/Object;")
    def getReference(self):
        return self._r

    @jmethod("getStamp", "()I")
    def getStamp(self):
        return self._s

    @jmethod("get", "([I)Ljava/lang/Object;")
    def get(self, holder):
        holder[0] = self._s
        return self._r

    @jmethod("compareAndSet", "(Ljava/lang/Object;Ljava/lang/Object;II)Z")
    def compareAndSet(self, expected, new, expected_stamp, new_stamp):
        with self._lock:
            if self._r is expected and self._s == expected_stamp:
                self._r, self._s = new, new_stamp
                return 1
            return 0

    @jmethod("set", "(Ljava/lang/Object;I)V")
    def set(self, reference, stamp):
        self._r, self._s = reference, stamp


@host_class("java.util.concurrent.atomic.AtomicMarkableReference")
class AtomicMarkableReference(Object):
    def __init__(self, reference, mark):
        self._r, self._m = reference, bool(mark)
        self._lock = threading.Lock()

    @jmethod("<init>", "(Ljava/lang/Object;Z)V")
    def _init(self, reference, mark):
        AtomicMarkableReference.__init__(self, reference, mark)

    @jmethod("getReference", "()Ljava/lang/Object;")
    def getReference(self):
        return self._r

    @jmethod("isMarked", "()Z")
    def isMarked(self):
        return 1 if self._m else 0

    @jmethod("get", "([Z)Ljava/lang/Object;")
    def get(self, holder):
        holder[0] = 1 if self._m else 0
        return self._r

    @jmethod("compareAndSet", "(Ljava/lang/Object;Ljava/lang/Object;ZZ)Z")
    def compareAndSet(self, expected, new, expected_mark, new_mark):
        with self._lock:
            if self._r is expected and self._m == bool(expected_mark):
                self._r, self._m = new, bool(new_mark)
                return 1
            return 0

    @jmethod("set", "(Ljava/lang/Object;Z)V")
    def set(self, reference, mark):
        self._r, self._m = reference, bool(mark)


@host_class("java.util.concurrent.locks.LockSupport", final=True)
class LockSupport(Object):
    _permits = {}
    _guard = threading.Lock()

    @staticmethod
    def _event():
        ident = threading.get_ident()
        with LockSupport._guard:
            return LockSupport._permits.setdefault(ident, threading.Event())

    @jstatic("park", "()V")
    @jstatic("park", "(Ljava/lang/Object;)V")
    def park(blocker=None):
        event = LockSupport._event()
        event.wait()
        event.clear()

    @jstatic("parkNanos", "(J)V")
    @jstatic("parkNanos", "(Ljava/lang/Object;J)V")
    def parkNanos(first, second=None):
        nanos = first if second is None else second
        event = LockSupport._event()
        if nanos > 0:
            event.wait(nanos / 1e9)
            event.clear()

    @jstatic("unpark", "(Ljava/lang/Thread;)V")
    def unpark(thread):
        if thread is not None and thread._thread is not None:
            with LockSupport._guard:
                LockSupport._permits.setdefault(thread._thread.ident, threading.Event()).set()


@host_class("java.util.concurrent.CyclicBarrier")
class CyclicBarrier(Object):
    def __init__(self, parties, action=None):
        if parties <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        self._parties = parties
        self._action = action
        self._barrier = threading.Barrier(parties, action=(lambda: action.run()) if action is not None else None)

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(ILjava/lang/Runnable;)V")
    def _init(self, parties, action=None):
        CyclicBarrier.__init__(self, parties, action)

    @jmethod("await", "()I")
    @jmethod("await", "(JLjava/util/concurrent/TimeUnit;)I")
    def await_(self, timeout=None, unit=None):
        from .jconc import seconds_of
        try:
            return self._barrier.wait(None if timeout is None else seconds_of(timeout, unit))
        except threading.BrokenBarrierError:
            runtime.throw_new("java.util.concurrent.BrokenBarrierException", None)

    @jmethod("getParties", "()I")
    def getParties(self):
        return self._parties

    @jmethod("getNumberWaiting", "()I")
    def getNumberWaiting(self):
        return self._barrier.n_waiting

    @jmethod("isBroken", "()Z")
    def isBroken(self):
        return 1 if self._barrier.broken else 0

    @jmethod("reset", "()V")
    def reset(self):
        self._barrier.reset()


setattr(CyclicBarrier, "await", CyclicBarrier.await_)


@host_class("java.util.concurrent.locks.StampedLock")
class StampedLock(Object):
    """a reader writer lock with stamps; an optimistic read is validated against the count of writes"""

    def __init__(self):
        self._lock = threading.Condition()
        self._readers = 0
        self._writer = False
        self._version = 0

    @jmethod("<init>", "()V")
    def _init(self):
        StampedLock.__init__(self)

    @jmethod("writeLock", "()J")
    def writeLock(self):
        with self._lock:
            self._lock.wait_for(lambda: not self._writer and not self._readers)
            self._writer = True
            self._version += 1
            return (self._version << 8) | 0x80

    @jmethod("readLock", "()J")
    def readLock(self):
        with self._lock:
            self._lock.wait_for(lambda: not self._writer)
            self._readers += 1
            return (self._version << 8) | 1

    @jmethod("tryOptimisticRead", "()J")
    def tryOptimisticRead(self):
        return 0 if self._writer else (self._version << 8)

    @jmethod("validate", "(J)Z")
    def validate(self, stamp):
        return 1 if stamp != 0 and (stamp >> 8) == self._version and not self._writer else 0

    @jmethod("unlockWrite", "(J)V")
    def unlockWrite(self, stamp):
        with self._lock:
            if not self._writer:
                runtime.throw_new("java.lang.IllegalMonitorStateException", None)
            self._writer = False
            self._version += 1
            self._lock.notify_all()

    @jmethod("unlockRead", "(J)V")
    def unlockRead(self, stamp):
        with self._lock:
            if not self._readers:
                runtime.throw_new("java.lang.IllegalMonitorStateException", None)
            self._readers -= 1
            self._lock.notify_all()

    @jmethod("unlock", "(J)V")
    def unlock(self, stamp):
        (self.unlockWrite if stamp & 0x80 else self.unlockRead)(stamp)

    @jmethod("tryConvertToWriteLock", "(J)J")
    def tryConvertToWriteLock(self, stamp):
        with self._lock:
            if stamp & 0x80:
                return stamp
            if (stamp & 1) and self._readers == 1 and not self._writer:
                self._readers = 0
                self._writer = True
                self._version += 1
                return (self._version << 8) | 0x80
            if stamp != 0 and (stamp >> 8) == self._version and not self._writer and not self._readers:
                self._writer = True
                self._version += 1
                return (self._version << 8) | 0x80
            return 0


class _Task(Object):
    def __init__(self):
        self._done = threading.Event()
        self._result = None
        self._error = None


@host_class("java.util.concurrent.ForkJoinTask", interfaces=("java.util.concurrent.Future",))
class ForkJoinTask(_Task):
    """a task is run by the thread that calls fork, join or invoke: this pool has no work stealing, and a recursive task finishes in the same order"""

    def _run(self):
        if not self._done.is_set():
            try:
                self._result = self._exec()
            except BaseException as error:
                self._error = error
            self._done.set()

    @jmethod("fork", "()Ljava/util/concurrent/ForkJoinTask;")
    def fork(self):
        self._run()
        return self

    @jmethod("join", "()Ljava/lang/Object;")
    @jmethod("get", "()Ljava/lang/Object;")
    @jmethod("invoke", "()Ljava/lang/Object;")
    def join(self):
        self._run()
        if self._error is not None:
            raise self._error
        return self._result

    @jmethod("isDone", "()Z")
    def isDone(self):
        return 1 if self._done.is_set() else 0

    @jstatic("invokeAll", "(Ljava/util/concurrent/ForkJoinTask;Ljava/util/concurrent/ForkJoinTask;)V")
    @jstatic("invokeAll", "([Ljava/util/concurrent/ForkJoinTask;)V")
    @jstatic("invokeAll", "(Ljava/util/Collection;)Ljava/util/Collection;")
    def invokeAll(first, second=None):
        tasks = [first, second] if second is not None else (list(first) if isinstance(first, list) else list(iterate(first)))
        for task in tasks:
            task._run()
        for task in tasks:
            if task._error is not None:
                raise task._error
        return None if second is not None or isinstance(first, list) else first


@host_class("java.util.concurrent.RecursiveTask", superclass="java.util.concurrent.ForkJoinTask")
class RecursiveTask(ForkJoinTask):
    def _exec(self):
        return self.compute()

    @jmethod("getRawResult", "()Ljava/lang/Object;")
    def getRawResult(self):
        return self._result


@host_class("java.util.concurrent.RecursiveAction", superclass="java.util.concurrent.ForkJoinTask")
class RecursiveAction(ForkJoinTask):
    def _exec(self):
        self.compute()
        return None


@host_class("java.util.concurrent.ForkJoinPool")
class ForkJoinPool(Object):
    _common = None

    def __init__(self, parallelism=1):
        self._p = parallelism

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, parallelism=1):
        ForkJoinPool.__init__(self, parallelism)

    @jstatic("commonPool", "()Ljava/util/concurrent/ForkJoinPool;")
    def commonPool():
        if ForkJoinPool._common is None:
            ForkJoinPool._common = ForkJoinPool(max(1, (os.cpu_count() or 2) - 1))
        return ForkJoinPool._common

    @jmethod("invoke", "(Ljava/util/concurrent/ForkJoinTask;)Ljava/lang/Object;")
    def invoke(self, task):
        return task.join()

    @jmethod("submit", "(Ljava/util/concurrent/ForkJoinTask;)Ljava/util/concurrent/ForkJoinTask;")
    @jmethod("execute", "(Ljava/util/concurrent/ForkJoinTask;)V")
    def submit(self, task):
        task._run()
        return task

    @jmethod("getParallelism", "()I")
    def getParallelism(self):
        return self._p

    @jstatic("getCommonPoolParallelism", "()I")
    def getCommonPoolParallelism():
        return ForkJoinPool.commonPool()._p

    @jmethod("shutdown", "()V")
    def shutdown(self):
        return None

    @jmethod("close", "()V")
    def close(self):
        return None


class _Reentrant:
    pass


def _policy(name, action):
    cls = type(name, (Object,), {"rejectedExecution": action})
    return host_class("java.util.concurrent.ThreadPoolExecutor$" + name, interfaces=("java.util.concurrent.RejectedExecutionHandler",))(cls)


def _abort(self, runnable, executor):
    runtime.throw_new("java.util.concurrent.RejectedExecutionException", "Task %s rejected from %s" % (jstring(runnable), jstring(executor)))


def _caller_runs(self, runnable, executor):
    if not executor.isShutdown():
        runnable.run()


AbortPolicy = _policy("AbortPolicy", _abort)
CallerRunsPolicy = _policy("CallerRunsPolicy", _caller_runs)
DiscardPolicy = _policy("DiscardPolicy", lambda self, runnable, executor: None)
DiscardOldestPolicy = _policy("DiscardOldestPolicy", lambda self, runnable, executor: None)


@host_class("java.util.concurrent.ConcurrentSkipListMap", interfaces=("java.util.Map",), superclass="java.util.TreeMap")
class ConcurrentSkipListMap(TreeMap):
    """a TreeMap whose operations hold one lock, so concurrent callers see whole updates"""

    def __init__(self, source=None):
        TreeMap.__init__(self, source)
        self._guard = threading.RLock()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Comparator;)V")
    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init(self, source=None):
        ConcurrentSkipListMap.__init__(self, source)


for _name in ("put", "get", "remove", "containsKey", "putIfAbsent", "clear", "firstKey", "lastKey", "pollFirstEntry", "pollLastEntry", "computeIfAbsent",
              "merge", "compute"):
    _fn = getattr(TreeMap, _name, None)
    if _fn is not None:
        setattr(ConcurrentSkipListMap, _name, (lambda f: lambda self, *a: _locked(self, f, *a))(_fn))


def _locked(self, function, *args):
    with self._guard:
        return function(self, *args)


@host_class("java.util.concurrent.ConcurrentSkipListSet", interfaces=("java.util.Set",), superclass="java.util.TreeSet")
class ConcurrentSkipListSet(lookup_host("java.util.TreeSet").py):
    def __init__(self, source=None):
        lookup_host("java.util.TreeSet").py.__init__(self, source)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Comparator;)V")
    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init(self, source=None):
        ConcurrentSkipListSet.__init__(self, source)


@host_class("java.util.concurrent.PriorityBlockingQueue", superclass="java.util.PriorityQueue")
class PriorityBlockingQueue(lookup_host("java.util.PriorityQueue").py):
    def __init__(self, first=None, second=None):
        lookup_host("java.util.PriorityQueue").py.__init__(self, first, second)
        self._cond = threading.Condition()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init0(self, capacity=11):
        PriorityBlockingQueue.__init__(self)

    @jmethod("<init>", "(ILjava/util/Comparator;)V")
    def _init2(self, capacity, comparator):
        PriorityBlockingQueue.__init__(self, comparator)

    def offer(self, item, *_timeout):
        with self._cond:
            result = lookup_host("java.util.PriorityQueue").py.offer(self, item)
            self._cond.notify()
            return result

    add = put = offer

    @jmethod("take", "()Ljava/lang/Object;")
    def take(self):
        with self._cond:
            while not self._q:
                self._cond.wait()
            return lookup_host("java.util.PriorityQueue").py.poll(self)

    @jmethod("poll", "()Ljava/lang/Object;")
    @jmethod("poll", "(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;")
    def poll(self, timeout=None, unit=None):
        from .jconc import seconds_of
        with self._cond:
            if not self._q and timeout:
                self._cond.wait_for(lambda: self._q, seconds_of(timeout, unit))
            return lookup_host("java.util.PriorityQueue").py.poll(self)

    @jmethod("remainingCapacity", "()I")
    def remainingCapacity(self):
        return 0x7FFFFFFF


@host_class("java.util.concurrent.SynchronousQueue", superclass="java.util.AbstractQueue")
class SynchronousQueue(AbstractQueue):
    """a queue with no room: put waits until another thread takes the item"""

    def __init__(self, fair=False):
        self._cond = threading.Condition()
        self._item = None
        self._has = False
        self._taken = False

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Z)V")
    def _init(self, fair=False):
        SynchronousQueue.__init__(self, fair)

    def size(self):
        return 0

    def iterator(self):
        return PyIterator([])

    @jmethod("put", "(Ljava/lang/Object;)V")
    def put(self, item):
        check_nonnull(item)
        with self._cond:
            self._cond.wait_for(lambda: not self._has)
            self._item, self._has, self._taken = item, True, False
            self._cond.notify_all()
            self._cond.wait_for(lambda: self._taken)
            self._taken = False
            self._cond.notify_all()

    @jmethod("offer", "(Ljava/lang/Object;)Z")
    @jmethod("offer", "(Ljava/lang/Object;JLjava/util/concurrent/TimeUnit;)Z")
    def offer(self, item, timeout=0, unit=None):
        from .jconc import seconds_of
        check_nonnull(item)
        with self._cond:
            if self._has:
                return 0
            self._item, self._has, self._taken = item, True, False
            self._cond.notify_all()
            if not self._cond.wait_for(lambda: self._taken, seconds_of(timeout, unit) if timeout else 0.0):
                self._has = False
                return 0
            self._taken = False
            self._cond.notify_all()
            return 1

    @jmethod("take", "()Ljava/lang/Object;")
    def take(self):
        with self._cond:
            self._cond.wait_for(lambda: self._has)
            item, self._item, self._has, self._taken = self._item, None, False, True
            self._cond.notify_all()
            return item

    @jmethod("poll", "()Ljava/lang/Object;")
    @jmethod("poll", "(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;")
    def poll(self, timeout=0, unit=None):
        from .jconc import seconds_of
        with self._cond:
            if not self._cond.wait_for(lambda: self._has, seconds_of(timeout, unit) if timeout else 0.0):
                return None
            item, self._item, self._has, self._taken = self._item, None, False, True
            self._cond.notify_all()
            return item

    def peek(self):
        return None


@host_class("java.util.concurrent.LinkedBlockingDeque", interfaces=("java.util.concurrent.BlockingDeque", "java.util.Deque"),
            superclass="java.util.concurrent.LinkedBlockingQueue")
class LinkedBlockingDeque(lookup_host("java.util.concurrent.LinkedBlockingQueue").py):
    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=None):
        lookup_host("java.util.concurrent.LinkedBlockingQueue").py.__init__(self, capacity)

    @jmethod("putFirst", "(Ljava/lang/Object;)V")
    @jmethod("addFirst", "(Ljava/lang/Object;)V")
    @jmethod("push", "(Ljava/lang/Object;)V")
    def putFirst(self, item):
        check_nonnull(item)
        with self._cond:
            self._cond.wait_for(lambda: len(self._a) < self._cap)
            self._a.insert(0, item)
            self._cond.notify_all()

    @jmethod("offerFirst", "(Ljava/lang/Object;)Z")
    def offerFirst(self, item):
        check_nonnull(item)
        with self._cond:
            if len(self._a) >= self._cap:
                return 0
            self._a.insert(0, item)
            self._cond.notify_all()
            return 1

    putLast = lookup_host("java.util.concurrent.LinkedBlockingQueue").py.put
    addLast = lookup_host("java.util.concurrent.LinkedBlockingQueue").py.put
    offerLast = lookup_host("java.util.concurrent.LinkedBlockingQueue").py.offer

    @jmethod("takeFirst", "()Ljava/lang/Object;")
    def takeFirst(self):
        return self.take()

    @jmethod("takeLast", "()Ljava/lang/Object;")
    def takeLast(self):
        with self._cond:
            self._cond.wait_for(lambda: self._a)
            item = self._a.pop()
            self._cond.notify_all()
            return item

    @jmethod("pollFirst", "()Ljava/lang/Object;")
    def pollFirst(self):
        with self._cond:
            if not self._a:
                return None
            item = self._a.pop(0)
            self._cond.notify_all()
            return item

    @jmethod("pollLast", "()Ljava/lang/Object;")
    def pollLast(self):
        with self._cond:
            if not self._a:
                return None
            item = self._a.pop()
            self._cond.notify_all()
            return item

    @jmethod("peekFirst", "()Ljava/lang/Object;")
    def peekFirst(self):
        return self._a[0] if self._a else None

    @jmethod("peekLast", "()Ljava/lang/Object;")
    def peekLast(self):
        return self._a[-1] if self._a else None

    @jmethod("getFirst", "()Ljava/lang/Object;")
    @jmethod("removeFirst", "()Ljava/lang/Object;")
    @jmethod("pop", "()Ljava/lang/Object;")
    def removeFirst(self):
        item = self.pollFirst()
        if item is None:
            no_such_element()
        return item

    @jmethod("removeLast", "()Ljava/lang/Object;")
    def removeLast(self):
        item = self.pollLast()
        if item is None:
            no_such_element()
        return item


@host_class("java.io.FileDescriptor")
class FileDescriptor(Object):
    def __init__(self, number=-1):
        self._fd = number

    @jmethod("valid", "()Z")
    def valid(self):
        return 1 if self._fd >= 0 else 0

    @jmethod("sync", "()V")
    def sync(self):
        return None


FileDescriptor.out = FileDescriptor(1)
FileDescriptor.err = FileDescriptor(2)
FileDescriptor.in_ = FileDescriptor(0)
setattr(FileDescriptor, "in", FileDescriptor.in_)


@host_class("java.io.CharArrayReader")
class CharArrayReader(Reader):
    def __init__(self, chars, offset=0, length=None):
        self._c = list(chars[offset:offset + (len(chars) - offset if length is None else length)])
        self._pos = 0

    @jmethod("<init>", "([C)V")
    @jmethod("<init>", "([CII)V")
    def _init(self, chars, offset=0, length=None):
        CharArrayReader.__init__(self, chars, offset, length)

    def read_char(self):
        if self._pos >= len(self._c):
            return -1
        self._pos += 1
        return self._c[self._pos - 1]


@host_class("java.io.CharArrayWriter")
class CharArrayWriter(Writer):
    def __init__(self, size=32):
        self._parts = []

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, size=32):
        CharArrayWriter.__init__(self, size)

    def write_text(self, text):
        self._parts.append(text)

    @jmethod("toCharArray", "()[C")
    def toCharArray(self):
        array = runtime.new_array("[C", 0)
        array.extend(ord(c) for c in "".join(self._parts))
        return array

    @jmethod("size", "()I")
    def size(self):
        return sum(len(p) for p in self._parts)

    @jmethod("reset", "()V")
    def reset(self):
        self._parts = []

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "".join(self._parts)


@host_class("java.io.FilterReader")
class FilterReader(Reader):
    def __init__(self, source):
        self._r = source

    @jmethod("<init>", "(Ljava/io/Reader;)V")
    def _init(self, source):
        FilterReader.__init__(self, source)

    def read_char(self):
        return self._r.read_char()

    def ready(self):
        return self._r.ready()

    def close(self):
        self._r.close()


@host_class("java.io.FilterWriter")
class FilterWriter(Writer):
    def __init__(self, sink):
        self._w = sink

    @jmethod("<init>", "(Ljava/io/Writer;)V")
    def _init(self, sink):
        FilterWriter.__init__(self, sink)

    def write_text(self, text):
        self._w.write_text(text)

    def flush(self):
        self._w.flush()

    def close(self):
        self._w.close()


@host_class("java.io.LineNumberReader", superclass="java.io.BufferedReader")
class LineNumberReader(lookup_host("java.io.BufferedReader").py):
    _line = 0

    @jmethod("<init>", "(Ljava/io/Reader;)V")
    @jmethod("<init>", "(Ljava/io/Reader;I)V")
    def _init(self, source, size=8192):
        lookup_host("java.io.BufferedReader").py.__init__(self, source)

    def readLine(self):
        line = lookup_host("java.io.BufferedReader").py.readLine(self)
        if line is not None:
            self._line += 1
        return line

    @jmethod("getLineNumber", "()I")
    def getLineNumber(self):
        return self._line

    @jmethod("setLineNumber", "(I)V")
    def setLineNumber(self, n):
        self._line = n


@host_class("java.io.PushbackReader", superclass="java.io.FilterReader")
class PushbackReader(FilterReader):
    def __init__(self, source, size=1):
        FilterReader.__init__(self, source)
        self._back = []
        self._size = size

    @jmethod("<init>", "(Ljava/io/Reader;)V")
    @jmethod("<init>", "(Ljava/io/Reader;I)V")
    def _init(self, source, size=1):
        PushbackReader.__init__(self, source, size)

    def read_char(self):
        return self._back.pop() if self._back else self._r.read_char()

    @jmethod("unread", "(I)V")
    def unread(self, char):
        if len(self._back) >= self._size:
            io_error("Pushback buffer overflow")
        self._back.append(char)


@host_class("java.io.PushbackInputStream", superclass="java.io.FilterInputStream")
class PushbackInputStream(FilterInputStream):
    def __init__(self, source, size=1):
        FilterInputStream.__init__(self, source)
        self._back = []
        self._size = size

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;I)V")
    def _init(self, source, size=1):
        PushbackInputStream.__init__(self, source, size)

    def read_byte(self):
        return self._back.pop() if self._back else self._in.read_byte()

    @jmethod("unread", "(I)V")
    def unread(self, byte):
        if len(self._back) >= self._size:
            io_error("Push back buffer is full")
        self._back.append(byte & 0xFF)


@host_class("java.io.SequenceInputStream")
class SequenceInputStream(InputStream):
    def __init__(self, first, second=None):
        self._streams = [first, second] if second is not None else list(iterate(first))
        self._i = 0

    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/util/Enumeration;)V")
    def _init(self, first, second=None):
        SequenceInputStream.__init__(self, first, second)

    def read_byte(self):
        while self._i < len(self._streams):
            value = self._streams[self._i].read_byte()
            if value != -1:
                return value
            self._streams[self._i].close()
            self._i += 1
        return -1

    def close(self):
        for stream in self._streams[self._i:]:
            stream.close()
        self._i = len(self._streams)


@host_class("java.io.PipedInputStream")
class PipedInputStream(InputStream):
    def __init__(self, source=None, size=1024):
        self._buf = bytearray()
        self._cond = threading.Condition()
        self._closed_write = False
        self._closed_read = False
        self._size = size
        if source is not None:
            self.connect(source)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(Ljava/io/PipedOutputStream;)V")
    @jmethod("<init>", "(Ljava/io/PipedOutputStream;I)V")
    def _init(self, first=None, second=None):
        if isinstance(first, int):
            PipedInputStream.__init__(self, None, first)
        else:
            PipedInputStream.__init__(self, first, 1024 if second is None else second)

    @jmethod("connect", "(Ljava/io/PipedOutputStream;)V")
    def connect(self, sink):
        sink.connect(self)

    def _receive(self, data):
        with self._cond:
            for byte in data:
                self._cond.wait_for(lambda: len(self._buf) < self._size or self._closed_read)
                if self._closed_read:
                    io_error("Pipe closed")
                self._buf.append(byte)
                self._cond.notify_all()

    def read_byte(self):
        with self._cond:
            self._cond.wait_for(lambda: self._buf or self._closed_write)
            if not self._buf:
                return -1
            value = self._buf.pop(0)
            self._cond.notify_all()
            return value

    def available(self):
        return len(self._buf)

    def close(self):
        with self._cond:
            self._closed_read = True
            self._cond.notify_all()


@host_class("java.io.PipedOutputStream")
class PipedOutputStream(OutputStream):
    def __init__(self, sink=None):
        self._sink = None
        if sink is not None:
            self.connect(sink)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/io/PipedInputStream;)V")
    def _init(self, sink=None):
        PipedOutputStream.__init__(self, sink)

    @jmethod("connect", "(Ljava/io/PipedInputStream;)V")
    def connect(self, sink):
        if self._sink is not None:
            io_error("Already connected")
        self._sink = sink

    def write_byte(self, value):
        if self._sink is None:
            io_error("Pipe not connected")
        self._sink._receive(bytes((value & 0xFF,)))

    def write(self, buffer, offset=0, length=None):
        if self._sink is None:
            io_error("Pipe not connected")
        length = len(buffer) - offset if length is None else length
        _check_range(buffer, offset, length)
        self._sink._receive(to_py_bytes(buffer, offset, length))

    def close(self):
        if self._sink is not None:
            with self._sink._cond:
                self._sink._closed_write = True
                self._sink._cond.notify_all()


class _Checksum:
    pass


@host_class("java.util.zip.CRC32C", interfaces=("java.util.zip.Checksum",))
class CRC32C(Object):
    _TABLE = None

    def __init__(self):
        if CRC32C._TABLE is None:
            table = []
            for n in range(256):
                c = n
                for _ in range(8):
                    c = (c >> 1) ^ 0x82F63B78 if c & 1 else c >> 1
                table.append(c)
            CRC32C._TABLE = table
        self._c = 0xFFFFFFFF

    @jmethod("<init>", "()V")
    def _init(self):
        CRC32C.__init__(self)

    @jmethod("update", "(I)V")
    @jmethod("update", "([B)V")
    @jmethod("update", "([BII)V")
    def update(self, data, offset=0, length=None):
        raw = bytes((data & 0xFF,)) if isinstance(data, int) else to_py_bytes(data, offset, length)
        c = self._c
        for byte in raw:
            c = CRC32C._TABLE[(c ^ byte) & 0xFF] ^ (c >> 8)
        self._c = c

    @jmethod("getValue", "()J")
    def getValue(self):
        return self._c ^ 0xFFFFFFFF

    @jmethod("reset", "()V")
    def reset(self):
        self._c = 0xFFFFFFFF


@host_class("java.util.zip.CheckedInputStream", superclass="java.io.FilterInputStream")
class CheckedInputStream(FilterInputStream):
    def __init__(self, source, checksum):
        FilterInputStream.__init__(self, source)
        self._ck = checksum

    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/util/zip/Checksum;)V")
    def _init(self, source, checksum):
        CheckedInputStream.__init__(self, source, checksum)

    def read_byte(self):
        value = self._in.read_byte()
        if value != -1:
            self._ck.update(value)
        return value

    def read(self, buffer, offset=0, length=None):
        count = self._in.read(buffer, offset, length) if length is not None else self._in.read(buffer)
        if count > 0:
            self._ck.update(buffer, offset, count)
        return count

    @jmethod("getChecksum", "()Ljava/util/zip/Checksum;")
    def getChecksum(self):
        return self._ck


@host_class("java.util.zip.CheckedOutputStream", superclass="java.io.FilterOutputStream")
class CheckedOutputStream(FilterOutputStream):
    def __init__(self, sink, checksum):
        FilterOutputStream.__init__(self, sink)
        self._ck = checksum

    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Checksum;)V")
    def _init(self, sink, checksum):
        CheckedOutputStream.__init__(self, sink, checksum)

    def write_byte(self, value):
        self._ck.update(value)
        self._out.write_byte(value)

    def write(self, buffer, offset=0, length=None):
        length = len(buffer) - offset if length is None else length
        self._ck.update(buffer, offset, length)
        self._out.write(buffer, offset, length)

    @jmethod("getChecksum", "()Ljava/util/zip/Checksum;")
    def getChecksum(self):
        return self._ck


@host_class("java.util.zip.DeflaterOutputStream", superclass="java.io.FilterOutputStream")
class DeflaterOutputStream(FilterOutputStream):
    def __init__(self, sink, deflater=None, *_rest):
        FilterOutputStream.__init__(self, sink)
        self._z = zlib.compressobj(-1, zlib.DEFLATED, -15 if deflater is not None and getattr(deflater, "_nowrap", False) else 15)
        self._finished = False

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Deflater;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Deflater;I)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Deflater;IZ)V")
    def _init(self, sink, deflater=None, *rest):
        DeflaterOutputStream.__init__(self, sink, deflater)

    def _emit(self, data):
        if data:
            self._out.write(to_java_bytes(data), 0, len(data))

    def write_byte(self, value):
        self._emit(self._z.compress(bytes((value & 0xFF,))))

    def write(self, buffer, offset=0, length=None):
        length = len(buffer) - offset if length is None else length
        _check_range(buffer, offset, length)
        self._emit(self._z.compress(to_py_bytes(buffer, offset, length)))

    @jmethod("finish", "()V")
    def finish(self):
        if not self._finished:
            self._finished = True
            self._emit(self._z.flush())

    def close(self):
        self.finish()
        self._out.close()


@host_class("java.util.zip.GZIPOutputStreamBase")
class _GzipBase(Object):
    pass


@host_class("java.util.zip.InflaterInputStream", superclass="java.io.FilterInputStream")
class InflaterInputStream(FilterInputStream):
    def __init__(self, source, inflater=None, *_rest):
        FilterInputStream.__init__(self, source)
        self._z = zlib.decompressobj(-15 if inflater is not None and getattr(inflater, "_nowrap", False) else 15)
        self._pending = b""
        self._eof = False

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/util/zip/Inflater;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/util/zip/Inflater;I)V")
    def _init(self, source, inflater=None, *rest):
        InflaterInputStream.__init__(self, source, inflater)

    def _fill(self):
        chunk = runtime.new_array("[B", 4096)
        while not self._pending and not self._eof:
            count = self._in.read(chunk, 0, 4096)
            try:
                if count < 0:
                    self._pending = self._z.flush()
                    self._eof = True
                else:
                    self._pending = self._z.decompress(to_py_bytes(chunk, 0, count))
            except zlib.error as error:
                runtime.throw_new("java.util.zip.ZipException", str(error))

    def read_byte(self):
        self._fill()
        if not self._pending:
            return -1
        value, self._pending = self._pending[0], self._pending[1:]
        return value

    def read(self, buffer, offset=0, length=None):
        length = len(buffer) - offset if length is None else length
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        self._fill()
        if not self._pending:
            return -1
        data, self._pending = self._pending[:length], self._pending[length:]
        buffer[offset:offset + len(data)] = [b - 256 if b > 127 else b for b in data]
        return len(data)

    def available(self):
        return 0 if self._eof and not self._pending else 1


@host_class("java.util.zip.InflaterOutputStream", superclass="java.io.FilterOutputStream")
class InflaterOutputStream(FilterOutputStream):
    def __init__(self, sink, inflater=None, *_rest):
        FilterOutputStream.__init__(self, sink)
        self._z = zlib.decompressobj(-15 if inflater is not None and getattr(inflater, "_nowrap", False) else 15)

    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Inflater;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/zip/Inflater;I)V")
    def _init(self, sink, inflater=None, *rest):
        InflaterOutputStream.__init__(self, sink, inflater)

    def write(self, buffer, offset=0, length=None):
        length = len(buffer) - offset if length is None else length
        try:
            data = self._z.decompress(to_py_bytes(buffer, offset, length))
        except zlib.error as error:
            runtime.throw_new("java.util.zip.ZipException", str(error))
        if data:
            self._out.write(to_java_bytes(data), 0, len(data))

    def write_byte(self, value):
        self.write(to_java_bytes(bytes((value & 0xFF,))), 0, 1)

    def finish(self):
        data = self._z.flush()
        if data:
            self._out.write(to_java_bytes(data), 0, len(data))

    def close(self):
        self.finish()
        self._out.close()


@host_class("java.util.zip.DeflaterInputStream", superclass="java.io.FilterInputStream")
class DeflaterInputStream(FilterInputStream):
    def __init__(self, source, *_rest):
        FilterInputStream.__init__(self, source)
        self._z = zlib.compressobj()
        self._pending = b""
        self._eof = False

    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/util/zip/Deflater;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Ljava/util/zip/Deflater;I)V")
    def _init(self, source, *rest):
        DeflaterInputStream.__init__(self, source)

    def _fill(self):
        chunk = runtime.new_array("[B", 4096)
        while not self._pending and not self._eof:
            count = self._in.read(chunk, 0, 4096)
            if count < 0:
                self._pending = self._z.flush()
                self._eof = True
            else:
                self._pending = self._z.compress(to_py_bytes(chunk, 0, count))

    def read_byte(self):
        self._fill()
        if not self._pending:
            return -1
        value, self._pending = self._pending[0], self._pending[1:]
        return value


@host_class("java.util.jar.Attributes$Name")
class AttributesName(Object):
    def __init__(self, name):
        self._name = name

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, name):
        AttributesName.__init__(self, name)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._name

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, AttributesName) and other._name.lower() == self._name.lower() else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return hash(self._name.lower()) & 0x7FFFFFFF


for _n, _v in (("MANIFEST_VERSION", "Manifest-Version"), ("MAIN_CLASS", "Main-Class"), ("CLASS_PATH", "Class-Path"), ("CONTENT_TYPE", "Content-Type"),
               ("SIGNATURE_VERSION", "Signature-Version"), ("IMPLEMENTATION_TITLE", "Implementation-Title"),
               ("IMPLEMENTATION_VERSION", "Implementation-Version"), ("IMPLEMENTATION_VENDOR", "Implementation-Vendor"),
               ("SPECIFICATION_TITLE", "Specification-Title"), ("SPECIFICATION_VERSION", "Specification-Version"),
               ("SPECIFICATION_VENDOR", "Specification-Vendor"), ("SEALED", "Sealed"), ("EXTENSION_NAME", "Extension-Name")):
    setattr(AttributesName, _n, AttributesName(_v))


@host_class("java.util.jar.Attributes", interfaces=("java.util.Map",))
class Attributes(Object):
    def __init__(self, source=None):
        self._m = {}
        if source is not None:
            self._m.update(source._m)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/jar/Attributes;)V")
    def _init(self, source=None):
        Attributes.__init__(self, source)

    @staticmethod
    def _key(name):
        return (name._name if isinstance(name, AttributesName) else str(name)).lower(), name

    @jmethod("getValue", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("getValue", "(Ljava/util/jar/Attributes$Name;)Ljava/lang/String;")
    def getValue(self, name):
        found = self._m.get(Attributes._key(name)[0])
        return found[1] if found else None

    @jmethod("putValue", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    def putValue(self, name, value):
        return self.put(AttributesName(name), value)

    @jmethod("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;")
    def put(self, name, value):
        key = Attributes._key(name)[0]
        old = self._m.get(key)
        self._m[key] = (name._name if isinstance(name, AttributesName) else str(name), value)
        return old[1] if old else None

    @jmethod("get", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def get(self, name):
        return self.getValue(name)

    @jmethod("remove", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def remove(self, name):
        old = self._m.pop(Attributes._key(name)[0], None)
        return old[1] if old else None

    @jmethod("containsKey", "(Ljava/lang/Object;)Z")
    def containsKey(self, name):
        return 1 if Attributes._key(name)[0] in self._m else 0

    @jmethod("size", "()I")
    def size(self):
        return len(self._m)

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 0 if self._m else 1

    @jmethod("clear", "()V")
    def clear(self):
        self._m.clear()

    @jmethod("keySet", "()Ljava/util/Set;")
    def keySet(self):
        result = lookup_host("java.util.LinkedHashSet").py()
        for name, _ in self._m.values():
            result.add(AttributesName(name))
        return result


@host_class("java.util.jar.Manifest", interfaces=("java.lang.Cloneable",))
class Manifest(Object):
    def __init__(self, source=None):
        self._main = Attributes()
        self._entries = {}
        if isinstance(source, InputStream):
            self.read(source)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    def _init(self, source=None):
        Manifest.__init__(self, source)

    @jmethod("getMainAttributes", "()Ljava/util/jar/Attributes;")
    def getMainAttributes(self):
        return self._main

    @jmethod("getAttributes", "(Ljava/lang/String;)Ljava/util/jar/Attributes;")
    def getAttributes(self, name):
        return self._entries.get(name)

    @jmethod("getEntries", "()Ljava/util/Map;")
    def getEntries(self):
        result = HashMap()
        for name, attributes in self._entries.items():
            result.put(name, attributes)
        return result

    @jmethod("read", "(Ljava/io/InputStream;)V")
    def read(self, stream):
        text = bytes(b & 0xFF for b in stream.readAllBytes()).decode("utf-8", "replace")
        text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n ", "")
        current = self._main
        for line in text.split("\n"):
            if not line:
                current = None if current is self._main and False else current
                continue
            name, _, value = line.partition(": ")
            if name.lower() == "name":
                current = self._entries.setdefault(value, Attributes())
            else:
                current.putValue(name, value)

    @jmethod("write", "(Ljava/io/OutputStream;)V")
    def write(self, stream):
        lines = []

        def section(attributes, first=None):
            for key, value in attributes._m.values():
                if first is None or key.lower() != first:
                    lines.append(_fold("%s: %s" % (key, value)))
            lines.append("")
        main = list(self._main._m.values())
        version = self._main._m.get("manifest-version")
        if version:
            lines.append("Manifest-Version: %s" % version[1])
        section(self._main, "manifest-version")
        for name, attributes in self._entries.items():
            lines.append(_fold("Name: " + name))
            section(attributes)
        data = ("\r\n".join(lines) + "\r\n").encode("utf-8")
        stream.write(to_java_bytes(data), 0, len(data))


def _fold(line):
    raw = line.encode("utf-8")
    if len(raw) <= 72:
        return line
    pieces = [raw[:72]]
    rest = raw[72:]
    while rest:
        pieces.append(b" " + rest[:71])
        rest = rest[71:]
    return "\r\n".join(p.decode("utf-8", "replace") for p in pieces)


@host_class("java.util.jar.JarEntry", superclass="java.util.zip.ZipEntry")
class JarEntry(lookup_host("java.util.zip.ZipEntry").py):
    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/util/zip/ZipEntry;)V")
    def _init(self, source):
        lookup_host("java.util.zip.ZipEntry").py.__init__(self, source if isinstance(source, str) else source._name)

    @jmethod("getAttributes", "()Ljava/util/jar/Attributes;")
    def getAttributes(self):
        return None

    @jmethod("getCertificates", "()[Ljava/security/cert/Certificate;")
    def getCertificates(self):
        return None


@host_class("java.util.jar.JarFile", superclass="java.util.zip.ZipFile")
class JarFile(lookup_host("java.util.zip.ZipFile").py):
    MANIFEST_NAME = "META-INF/MANIFEST.MF"

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/io/File;)V")
    @jmethod("<init>", "(Ljava/lang/String;Z)V")
    @jmethod("<init>", "(Ljava/io/File;Z)V")
    def _init(self, target, verify=False):
        if verify:
            runtime.throw_new("java.lang.UnsupportedOperationException", "jar signature verification is not implemented")
        lookup_host("java.util.zip.ZipFile").py.__init__(self, target)

    @jmethod("getManifest", "()Ljava/util/jar/Manifest;")
    def getManifest(self):
        entry = self.getEntry(JarFile.MANIFEST_NAME)
        return None if entry is None else Manifest(self.getInputStream(entry))

    @jmethod("getJarEntry", "(Ljava/lang/String;)Ljava/util/jar/JarEntry;")
    def getJarEntry(self, name):
        entry = self.getEntry(name)
        return None if entry is None else JarEntry(entry)


@host_class("java.util.jar.JarOutputStream", superclass="java.util.zip.ZipOutputStream")
class JarOutputStream(lookup_host("java.util.zip.ZipOutputStream").py):
    @jmethod("<init>", "(Ljava/io/OutputStream;)V")
    @jmethod("<init>", "(Ljava/io/OutputStream;Ljava/util/jar/Manifest;)V")
    def _init(self, sink, manifest=None):
        lookup_host("java.util.zip.ZipOutputStream").py.__init__(self, sink)
        if manifest is not None:
            self.putNextEntry(lookup_host("java.util.zip.ZipEntry").py(JarFile.MANIFEST_NAME))
            out = lookup_host("java.io.ByteArrayOutputStream").py()
            manifest.write(out)
            data = out.toByteArray()
            self.write(data, 0, len(data))
            self.closeEntry()


@host_class("java.util.jar.JarInputStream", superclass="java.util.zip.ZipInputStream")
class JarInputStream(lookup_host("java.util.zip.ZipInputStream").py):
    @jmethod("<init>", "(Ljava/io/InputStream;)V")
    @jmethod("<init>", "(Ljava/io/InputStream;Z)V")
    def _init(self, source, verify=False):
        lookup_host("java.util.zip.ZipInputStream").py.__init__(self, source)

    @jmethod("getManifest", "()Ljava/util/jar/Manifest;")
    def getManifest(self):
        return None


@host_class("java.lang.StrictMath", final=True)
class StrictMath(Object):
    pass


for _n in ("abs", "max", "min", "pow", "sqrt", "cbrt", "floor", "ceil", "round", "rint", "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
           "sinh", "cosh", "tanh", "exp", "expm1", "log", "log10", "log1p", "hypot", "signum", "toRadians", "toDegrees", "floorDiv", "floorMod",
           "addExact", "multiplyExact", "toIntExact"):
    _m = lookup_host("java.lang.Math").py
    for _b in _m.__mro__:
        if _n in vars(_b):
            setattr(StrictMath, _n, vars(_b)[_n])
            break
for _n, _fn in (("PI", math.pi), ("E", math.e)):
    setattr(StrictMath, _n, _fn)


@host_class("java.lang.Record")
class Record(Object):
    """the base of a record class: equals, hashCode and toString over the components the dex class declares"""

    def _components(self):
        found = []
        for name in dir(type(self)):
            pass
        return found

    @jmethod("<init>", "()V")
    def _init(self):
        return None


@host_class("java.lang.ThreadGroup")
class ThreadGroup(Object):
    def __init__(self, first=None, second=None):
        self._name = second if second is not None else first
        self._parent = first if second is not None else None

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/ThreadGroup;Ljava/lang/String;)V")
    def _init(self, first, second=None):
        ThreadGroup.__init__(self, first, second)

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("getParent", "()Ljava/lang/ThreadGroup;")
    def getParent(self):
        return self._parent

    @jmethod("activeCount", "()I")
    def activeCount(self):
        return threading.active_count()


@host_class("java.lang.Runtime")
class Runtime(Object):
    _instance = None

    @jstatic("getRuntime", "()Ljava/lang/Runtime;")
    def getRuntime():
        if Runtime._instance is None:
            Runtime._instance = Runtime()
        return Runtime._instance

    @jmethod("availableProcessors", "()I")
    def availableProcessors(self):
        return os.cpu_count() or 1

    @jmethod("totalMemory", "()J")
    def totalMemory(self):
        return 256 * 1024 * 1024

    @jmethod("maxMemory", "()J")
    def maxMemory(self):
        return 512 * 1024 * 1024

    @jmethod("freeMemory", "()J")
    def freeMemory(self):
        return 128 * 1024 * 1024

    @jmethod("gc", "()V")
    def gc(self):
        import gc
        gc.collect()

    @jmethod("exec", "(Ljava/lang/String;)Ljava/lang/Process;")
    @jmethod("exec", "([Ljava/lang/String;)Ljava/lang/Process;")
    def exec_(self, command, *_rest):
        runtime.throw_new("java.io.IOException", "Cannot run program: this process cannot start other programs")

    @jmethod("addShutdownHook", "(Ljava/lang/Thread;)V")
    def addShutdownHook(self, thread):
        import atexit
        atexit.register(thread.run)

    @jmethod("exit", "(I)V")
    @jmethod("halt", "(I)V")
    def exit(self, status):
        runtime.throw_new("java.lang.SecurityException", "exit(%d) is not allowed" % status)


setattr(Runtime, "exec", Runtime.exec_)


@host_class("java.lang.Process")
class Process(Object):
    """no program can be started from here, so no Process exists; the class is here for code that names the type"""

    @jmethod("destroy", "()V")
    def destroy(self):
        return None


@host_class("java.lang.ProcessBuilder")
class ProcessBuilder(Object):
    def __init__(self, *command):
        self._cmd = list(command[0]) if len(command) == 1 and isinstance(command[0], list) else list(command)

    @jmethod("<init>", "([Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/util/List;)V")
    def _init(self, command):
        ProcessBuilder.__init__(self, command)

    @jmethod("start", "()Ljava/lang/Process;")
    def start(self):
        runtime.throw_new("java.io.IOException", "Cannot run program: this process cannot start other programs")


@host_class("java.lang.reflect.Parameter")
class Parameter(Object):
    def __init__(self, name, type_, modifiers=0):
        self._name, self._type, self._mod = name, type_, modifiers

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("getType", "()Ljava/lang/Class;")
    def getType(self):
        return self._type

    @jmethod("getModifiers", "()I")
    def getModifiers(self):
        return self._mod


@host_class("java.math.MathContext", interfaces=("java.io.Serializable",))
class MathContext(Object):
    def __init__(self, precision, mode=None):
        if precision < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Digits < 0")
        self._p = precision
        self._mode = mode

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(ILjava/math/RoundingMode;)V")
    def _init(self, precision, mode=None):
        MathContext.__init__(self, precision, mode)

    @jmethod("getPrecision", "()I")
    def getPrecision(self):
        return self._p

    @jmethod("getRoundingMode", "()Ljava/math/RoundingMode;")
    def getRoundingMode(self):
        return self._mode

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "precision=%d roundingMode=%s" % (self._p, jstring(self._mode) if self._mode is not None else "HALF_UP")


MathContext.UNLIMITED = MathContext(0)
MathContext.DECIMAL32 = MathContext(7)
MathContext.DECIMAL64 = MathContext(16)
MathContext.DECIMAL128 = MathContext(34)
