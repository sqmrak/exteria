"""java.util.concurrent classes the other modules leave out (AbstractExecutorService, ExecutorCompletionService, DelayQueue,
Exchanger, Phaser, LinkedTransferQueue, the atomic field updaters), SimpleTimeZone, MonthDay and ValueRange. each class does
what the jdk class does; tests/fixtures/dex/src/Api3.java prints the same text on a jvm"""

import threading
import time

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jconc import FutureTask, LinkedBlockingQueue
from .jlang import Object
from .jtime import (TimeZone, _Zone, civil_from_days, days_from_civil, is_leap, month_length)
from .jutil import AbstractQueue, PyIterator, check_nonnull, iterate

_MAX_LONG = 0x7FFFFFFFFFFFFFFF


def _seconds(timeout, unit):
    return unit.toNanos(timeout) / 1e9


def _nanos():
    return lookup_host("java.util.concurrent.TimeUnit").py.NANOSECONDS


@host_class("java.util.concurrent.AbstractExecutorService", interfaces=("java.util.concurrent.ExecutorService",))
class AbstractExecutorService(Object):
    """the base a program extends: it gives execute, shutdown and the rest of the lifecycle, this class the submit family"""

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    def newTaskFor(self, task, result=None):
        return FutureTask(task, result)

    def submit(self, task, result=None):
        check_nonnull(task)
        future = self.newTaskFor(task, result)
        self.execute(future)
        return future

    def invokeAll(self, tasks, timeout=None, unit=None):
        from .jmap import ArrayList
        futures = ArrayList()
        for task in iterate(check_nonnull(tasks)):
            futures.add(self.newTaskFor(task))
        for future in iterate(futures):
            self.execute(future)
        deadline = None if timeout is None else time.monotonic() + _seconds(timeout, unit)
        for future in iterate(futures):
            try:
                if deadline is None:
                    future.get()
                else:
                    future.get(max(int((deadline - time.monotonic()) * 1e9), 0), _nanos())
            except Exception as error:
                failure = runtime.to_throwable(error)
                name = runtime.class_of(failure).getName()
                if name not in ("java.util.concurrent.ExecutionException", "java.util.concurrent.CancellationException"):
                    if name != "java.util.concurrent.TimeoutException":
                        raise
                    for rest in iterate(futures):
                        rest.cancel(1)
                    break
        return futures

    def invokeAny(self, tasks, timeout=None, unit=None):
        last = None
        count = 0
        for task in iterate(check_nonnull(tasks)):
            count += 1
            future = self.newTaskFor(task)
            self.execute(future)
            try:
                return future.get() if timeout is None else future.get(timeout, unit)
            except Exception as error:
                last = runtime.to_throwable(error)
        if count == 0:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        raise last


class _QueueingFuture(FutureTask):
    def __init__(self, task, result, queue):
        FutureTask.__init__(self, task, result)
        self._completed = queue

    def done(self):
        self._completed.add(self)


@host_class("java.util.concurrent.ExecutorCompletionService", interfaces=("java.util.concurrent.CompletionService",))
class ExecutorCompletionService(Object):
    def __init__(self, executor, queue=None):
        self._executor = check_nonnull(executor)
        self._queue = queue if queue is not None else LinkedBlockingQueue()

    @jmethod("<init>", "(Ljava/util/concurrent/Executor;)V")
    @jmethod("<init>", "(Ljava/util/concurrent/Executor;Ljava/util/concurrent/BlockingQueue;)V")
    def _init(self, executor, queue=None):
        ExecutorCompletionService.__init__(self, executor, queue)

    def submit(self, task, result=None):
        check_nonnull(task)
        future = _QueueingFuture(task, result, self._queue)
        self._executor.execute(future)
        return future

    def take(self):
        return self._queue.take()

    def poll(self, timeout=None, unit=None):
        return self._queue.poll() if timeout is None else self._queue.poll(timeout, unit)


@host_class("java.util.concurrent.DelayQueue", interfaces=("java.util.concurrent.BlockingQueue",))
class DelayQueue(AbstractQueue):
    """elements come out in order of their delay, and only once the delay has run out"""

    def __init__(self, source=None):
        self._a = []
        self._cond = threading.Condition()
        self.modCount = 0
        if source is not None:
            for item in iterate(source):
                self.add(item)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init(self, source=None):
        DelayQueue.__init__(self, source)

    def size(self):
        return len(self._a)

    def iterator(self):
        return PyIterator(list(self._a))

    def _head(self):
        best = None
        for item in self._a:
            if best is None or item.compareTo(best) < 0:
                best = item
        return best

    def _delay(self, item):
        return item.getDelay(_nanos())

    def offer(self, item, timeout=None, unit=None):
        check_nonnull(item)
        with self._cond:
            self._a.append(item)
            self._cond.notify_all()
        return 1

    def put(self, item):
        self.offer(item)

    def peek(self):
        with self._cond:
            return self._head()

    def poll(self, timeout=None, unit=None):
        end = None if timeout is None else time.monotonic() + _seconds(timeout, unit)
        with self._cond:
            while True:
                head = self._head()
                if head is not None and self._delay(head) <= 0:
                    self._a.remove(head)
                    self._cond.notify_all()
                    return head
                if end is None:
                    return None
                left = end - time.monotonic()
                if left <= 0:
                    return None
                wait = left if head is None else min(left, self._delay(head) / 1e9)
                self._cond.wait(max(wait, 0.0005))

    def take(self):
        with self._cond:
            while True:
                head = self._head()
                if head is None:
                    self._cond.wait()
                    continue
                delay = self._delay(head)
                if delay <= 0:
                    self._a.remove(head)
                    self._cond.notify_all()
                    return head
                self._cond.wait(delay / 1e9)

    def remainingCapacity(self):
        return 0x7FFFFFFF

    def clear(self):
        with self._cond:
            self._a.clear()

    def remove(self, item=None):
        if item is None:
            return AbstractQueue.remove(self)
        with self._cond:
            for found in self._a:
                if found is item or found.equals(item):
                    self._a.remove(found)
                    return 1
        return 0

    def drainTo(self, target, limit=0x7FFFFFFF):
        count = 0
        while count < limit:
            item = self.poll()
            if item is None:
                break
            target.add(item)
            count += 1
        return count


@host_class("java.util.concurrent.LinkedTransferQueue", interfaces=("java.util.concurrent.TransferQueue",))
class LinkedTransferQueue(LinkedBlockingQueue):
    """a queue whose producers can wait until a consumer has taken their element"""

    def __init__(self, source=None):
        LinkedBlockingQueue.__init__(self, source)
        self._waiting = 0

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_transfer(self, source=None):
        LinkedTransferQueue.__init__(self, source)

    def take(self):
        with self._cond:
            self._waiting += 1
            try:
                return LinkedBlockingQueue.take(self)
            finally:
                self._waiting -= 1

    def poll(self, timeout=None, unit=None):
        with self._cond:
            if timeout:
                self._waiting += 1
            try:
                return LinkedBlockingQueue.poll(self, timeout, unit)
            finally:
                if timeout:
                    self._waiting -= 1

    def transfer(self, item):
        check_nonnull(item)
        with self._cond:
            self._a.append(item)
            self._cond.notify_all()
            while any(entry is item for entry in self._a):
                self._cond.wait()

    def tryTransfer(self, item, timeout=None, unit=None):
        check_nonnull(item)
        with self._cond:
            if timeout is None:
                if self._waiting <= len(self._a):
                    return 0
                self._a.append(item)
                self._cond.notify_all()
                return 1
            self._a.append(item)
            self._cond.notify_all()
            self._cond.wait_for(lambda: not any(entry is item for entry in self._a), _seconds(timeout, unit))
            if any(entry is item for entry in self._a):
                self._a[:] = [entry for entry in self._a if entry is not item]
                return 0
            return 1

    def hasWaitingConsumer(self):
        return 1 if self._waiting > len(self._a) else 0

    def getWaitingConsumerCount(self):
        return max(self._waiting - len(self._a), 0)


@host_class("java.util.concurrent.Exchanger")
class Exchanger(Object):
    class _Cell:
        def __init__(self, value):
            self.value = value
            self.response = None
            self.done = False

    def __init__(self):
        self._cond = threading.Condition()
        self._offer = None

    @jmethod("<init>", "()V")
    def _init(self):
        Exchanger.__init__(self)

    def exchange(self, value, timeout=None, unit=None):
        with self._cond:
            if self._offer is not None:
                cell, self._offer = self._offer, None
                cell.response = value
                cell.done = True
                self._cond.notify_all()
                return cell.value
            mine = Exchanger._Cell(value)
            self._offer = mine
            if not self._cond.wait_for(lambda: mine.done, None if timeout is None else _seconds(timeout, unit)):
                if self._offer is mine:
                    self._offer = None
                runtime.throw_new("java.util.concurrent.TimeoutException", None)
            return mine.response


@host_class("java.util.concurrent.Phaser")
class Phaser(Object):
    """a reusable barrier with a changing number of parties. onAdvance(phase, parties) decides whether it terminates"""

    _MIN = -0x80000000

    def __init__(self, parent=None, parties=0):
        if isinstance(parent, int):
            parent, parties = None, parent
        if parties < 0 or parties > 65535:
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal number of parties")
        # a tree of phasers shares one lock and the phase of its root; only the root runs onAdvance
        self._parent = parent
        self._cond = parent._cond if parent is not None else threading.Condition()
        self._root = parent._root if parent is not None else self
        self._children = []
        self._parties = 0
        self._arrived = 0
        if parent is None:
            self._ph = 0
            self._term = False
        self._link = False
        if parties:
            with self._cond:
                self._add_parties(parties)

    @property
    def _phase(self):
        return self._root._ph

    @property
    def _terminated(self):
        return self._root._term

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(Ljava/util/concurrent/Phaser;)V")
    @jmethod("<init>", "(Ljava/util/concurrent/Phaser;I)V")
    def _init(self, parent=None, parties=0):
        Phaser.__init__(self, parent, parties)

    def _visible(self):
        return self._phase + Phaser._MIN if self._terminated else self._phase

    def _add_parties(self, count):
        if self._parent is not None and not self._link:
            self._link = True
            self._parent._children.append(self)
            self._parent._add_parties(1)
        self._parties += count

    def _reset(self):
        self._arrived = 0
        for child in self._children:
            child._reset()

    def _complete(self):
        """every party of this phaser has arrived"""
        if self._parent is not None:
            if self._parties == 0:
                self._link = False
                self._parent._children.remove(self)
                self._parent._leave()
            else:
                self._parent._arrive()
            return
        phase, parties = self._ph, self._parties
        self._reset()
        if self.onAdvance(phase, parties):
            self._term = True
        else:
            self._ph = (self._ph + 1) & 0x7FFFFFFF
        self._cond.notify_all()

    def _arrive(self):
        self._arrived += 1
        if self._arrived == self._parties:
            self._complete()

    def _leave(self):
        self._parties -= 1
        if self._arrived == self._parties:
            self._complete()

    def onAdvance(self, phase, parties):
        return 1 if parties == 0 else 0

    def register(self):
        return self.bulkRegister(1)

    def bulkRegister(self, count):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        with self._cond:
            if self._terminated:
                return self._visible()
            self._add_parties(count)
            return self._phase

    def _unregistered(self):
        runtime.throw_new("java.lang.IllegalStateException", "Attempted arrival of unregistered party for " + self.toString())

    def arrive(self):
        with self._cond:
            if self._terminated:
                return self._visible()
            if self._arrived >= self._parties:
                self._unregistered()
            phase = self._phase
            self._arrive()
            return phase

    def arriveAndDeregister(self):
        with self._cond:
            if self._terminated:
                return self._visible()
            if self._parties == 0:
                self._unregistered()
            phase = self._phase
            self._leave()
            return phase

    def arriveAndAwaitAdvance(self):
        with self._cond:
            if self._terminated:
                return self._visible()
            phase = self._phase
            if self._arrived >= self._parties:
                self._unregistered()
            self._arrive()
            self._cond.wait_for(lambda: self._phase != phase or self._terminated)
            return self._visible()

    def awaitAdvance(self, phase):
        with self._cond:
            if phase < 0:
                return phase
            if self._phase != phase and not self._terminated:
                return self._visible()
            self._cond.wait_for(lambda: self._phase != phase or self._terminated)
            return self._visible()

    def awaitAdvanceInterruptibly(self, phase, timeout=None, unit=None):
        with self._cond:
            if phase < 0:
                return phase
            if not self._cond.wait_for(lambda: self._phase != phase or self._terminated,
                                       None if timeout is None else _seconds(timeout, unit)):
                runtime.throw_new("java.util.concurrent.TimeoutException", None)
            return self._visible()

    def forceTermination(self):
        with self._cond:
            self._root._term = True
            self._cond.notify_all()

    def getPhase(self):
        return self._visible()

    def getRegisteredParties(self):
        return self._parties

    def getArrivedParties(self):
        return self._arrived

    def getUnarrivedParties(self):
        return self._parties - self._arrived

    def isTerminated(self):
        return 1 if self._terminated else 0

    def getParent(self):
        return self._parent

    def getRoot(self):
        return self._root

    def toString(self):
        return "%s[phase = %d parties = %d arrived = %d]" % (
            runtime.class_of(self).getName(), self._visible(), self._parties, self._arrived)


_updater_lock = threading.RLock()


class _FieldUpdater(Object):
    """get and set of one field of a class of a dex file, atomic with respect to the other updaters"""

    _DESC = None
    _WRAP = staticmethod(lambda value: value)

    def __init__(self, attr):
        self._attr = attr

    @staticmethod
    def _find(tclass, name, desc):
        found = tclass.find_field(name, desc, False) if hasattr(tclass, "find_field") else None
        if found is None:
            error = runtime.make_throwable(lookup_host("java.lang.RuntimeException").py, "java.lang.NoSuchFieldException: " + name)
            error._cause = runtime.make_throwable(lookup_host("java.lang.NoSuchFieldException").py, name)
            raise error
        return found[1]

    def get(self, obj):
        return getattr(obj, self._attr)

    def set(self, obj, value):
        setattr(obj, self._attr, value)

    lazySet = set

    def getAndSet(self, obj, value):
        with _updater_lock:
            old = getattr(obj, self._attr)
            setattr(obj, self._attr, value)
            return old

    def compareAndSet(self, obj, expect, update):
        with _updater_lock:
            if getattr(obj, self._attr) == expect if self._DESC != "L" else getattr(obj, self._attr) is expect:
                setattr(obj, self._attr, update)
                return 1
            return 0

    weakCompareAndSet = compareAndSet
    weakCompareAndSetPlain = compareAndSet

    def getAndUpdate(self, obj, function):
        with _updater_lock:
            old = getattr(obj, self._attr)
            setattr(obj, self._attr, self._apply(function, old))
            return old

    def updateAndGet(self, obj, function):
        with _updater_lock:
            new = self._apply(function, getattr(obj, self._attr))
            setattr(obj, self._attr, new)
            return new

    def getAndAccumulate(self, obj, x, function):
        with _updater_lock:
            old = getattr(obj, self._attr)
            setattr(obj, self._attr, self._apply2(function, old, x))
            return old

    def accumulateAndGet(self, obj, x, function):
        with _updater_lock:
            new = self._apply2(function, getattr(obj, self._attr), x)
            setattr(obj, self._attr, new)
            return new

    @staticmethod
    def _apply(function, value):
        for name in ("apply", "applyAsInt", "applyAsLong"):
            call = getattr(function, name, None)
            if call is not None:
                return call(value)
        runtime.throw_new("java.lang.AbstractMethodError", "apply")

    @staticmethod
    def _apply2(function, a, b):
        for name in ("apply", "applyAsInt", "applyAsLong"):
            call = getattr(function, name, None)
            if call is not None:
                return call(a, b)
        runtime.throw_new("java.lang.AbstractMethodError", "apply")


class _NumberUpdater(_FieldUpdater):
    def _add(self, obj, delta, return_new):
        with _updater_lock:
            old = getattr(obj, self._attr)
            new = self._WRAP(old + delta)
            setattr(obj, self._attr, new)
            return new if return_new else old

    def getAndIncrement(self, obj):
        return self._add(obj, 1, False)

    def getAndDecrement(self, obj):
        return self._add(obj, -1, False)

    def getAndAdd(self, obj, delta):
        return self._add(obj, delta, False)

    def incrementAndGet(self, obj):
        return self._add(obj, 1, True)

    def decrementAndGet(self, obj):
        return self._add(obj, -1, True)

    def addAndGet(self, obj, delta):
        return self._add(obj, delta, True)


def _updater_class(name, desc, base, wrap, descriptor_of):
    full = "java.util.concurrent.atomic." + name
    cls = type(name, (base,), {"_DESC": desc, "_WRAP": staticmethod(wrap)})

    if desc == "L":
        def new_updater(tclass, vclass, field):
            return cls(_FieldUpdater._find(tclass, field, vclass.descriptor))
        cls.newUpdater = staticmethod(new_updater)
    else:
        def new_updater(tclass, field):
            return cls(_FieldUpdater._find(tclass, field, desc))
        cls.newUpdater = staticmethod(new_updater)
    return host_class(full)(cls)


AtomicIntegerFieldUpdater = _updater_class("AtomicIntegerFieldUpdater", "I", _NumberUpdater, runtime.wrap32, None)
AtomicLongFieldUpdater = _updater_class("AtomicLongFieldUpdater", "J", _NumberUpdater, runtime.wrap64, None)
AtomicReferenceFieldUpdater = _updater_class("AtomicReferenceFieldUpdater", "L", _FieldUpdater, lambda v: v, None)


def _dow_of(day_number):
    """Calendar.SUNDAY (1) to SATURDAY (7)"""
    return (day_number + 4) % 7 + 1


class _RuleZone(_Zone):
    """a zone whose daylight saving time starts and ends by the rules of a SimpleTimeZone"""

    def __init__(self, zone_id, raw, rules=None, savings=3600000):
        _Zone.__init__(self, zone_id, "fixed", raw)
        self.rules = rules
        self.savings = savings if rules is not None else 0

    def uses_dst(self):
        return self.rules is not None

    def _day(self, year, month, day, dow):
        """the day number a rule names in a year (month 0 to 11)"""
        if dow == 0:
            if day < 0:
                return days_from_civil(year, month + 1, month_length(year, month)) + day + 1
            return days_from_civil(year, month + 1, day)
        if dow > 0:
            if day > 0:
                first = days_from_civil(year, month + 1, 1)
                return first + (dow - _dow_of(first)) % 7 + 7 * (day - 1)
            last = days_from_civil(year, month + 1, month_length(year, month))
            return last - (_dow_of(last) - dow) % 7 + 7 * (day + 1)
        dow = -dow
        if day > 0:
            start = days_from_civil(year, month + 1, day)
            return start + (dow - _dow_of(start)) % 7
        start = days_from_civil(year, month + 1, -day)
        return start - (_dow_of(start) - dow) % 7

    def _bounds(self, year):
        sm, sd, sdow, st, smode, em, ed, edow, et, emode = self.rules
        raw = self.fixed
        start = self._day(year, sm, sd, sdow) * 86400000 + st - (0 if smode == 2 else raw)
        end = self._day(year, em, ed, edow) * 86400000 + et - (0 if emode == 2 else (raw if emode == 1 else raw + self.savings))
        return start, end

    def in_dst(self, utc_ms):
        if self.rules is None:
            return False
        year = civil_from_days((utc_ms + self.fixed) // 86400000)[0]
        start, end = self._bounds(year)
        if start < end:
            return start <= utc_ms < end
        return utc_ms < end or utc_ms >= start

    def offset(self, utc_ms):
        return self.fixed + (self.savings if self.in_dst(utc_ms) else 0)

    def raw(self):
        return self.fixed

    def short_name(self, utc_ms):
        from .jtime import _gmt_text
        return _gmt_text(self.offset(utc_ms))


@host_class("java.util.SimpleTimeZone")
class SimpleTimeZone(TimeZone):
    UTC_TIME, WALL_TIME, STANDARD_TIME = 2, 0, 1

    def __init__(self, raw, zone_id, *rules):
        check_nonnull(zone_id)
        parsed = None
        savings = 3600000
        if rules:
            if len(rules) == 8:
                sm, sd, sdow, st, em, ed, edow, et = rules
                parsed = (sm, sd, sdow, st, 0, em, ed, edow, et, 0)
            elif len(rules) == 9:
                sm, sd, sdow, st, em, ed, edow, et, savings = rules
                parsed = (sm, sd, sdow, st, 0, em, ed, edow, et, 0)
            elif len(rules) == 10:
                sm, sd, sdow, st, smode, em, ed, edow, et, emode = rules[:10]
                parsed = (sm, sd, sdow, st, smode, em, ed, edow, et, emode)
            else:
                sm, sd, sdow, st, smode, em, ed, edow, et, emode, savings = rules
                parsed = (sm, sd, sdow, st, smode, em, ed, edow, et, emode)
            for month in (parsed[0], parsed[5]):
                if not 0 <= month <= 11:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Illegal start month %d" % month if month == parsed[0]
                                      else "Illegal end month %d" % month)
        TimeZone.__init__(self, _RuleZone(zone_id, raw, parsed, savings))

    @jmethod("<init>", "(ILjava/lang/String;)V")
    @jmethod("<init>", "(ILjava/lang/String;IIIIIIII)V")
    @jmethod("<init>", "(ILjava/lang/String;IIIIIIIII)V")
    @jmethod("<init>", "(ILjava/lang/String;IIIIIIIIIII)V")
    def _init(self, raw, zone_id, *rules):
        SimpleTimeZone.__init__(self, raw, zone_id, *rules)

    def setRawOffset(self, raw):
        self._zone.fixed = raw
        self._zone._raw = None

    def setID(self, zone_id):
        self._zone.id = zone_id

    def setDSTSavings(self, savings):
        if savings <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal daylight saving value: %d" % savings)
        self._zone.savings = savings

    def getDSTSavings(self):
        return self._zone.savings if self._zone.rules is not None else 0

    def setStartRule(self, month, day, *rest):
        self._set_rule(0, month, day, rest)

    def setEndRule(self, month, day, *rest):
        self._set_rule(5, month, day, rest)

    def _set_rule(self, at, month, day, rest):
        zone = self._zone
        rules = list(zone.rules) if zone.rules is not None else [0, 1, 0, 7200000, 0, 0, 1, 0, 7200000, 0]
        if len(rest) == 1:
            dow, time_ = 0, rest[0]
        elif len(rest) == 2:
            dow, time_ = rest
        else:
            # day of week on or after (after) or on or before the day of month
            dow, time_, after = rest
            dow = -dow
            day = abs(day) if after else -abs(day)
        rules[at], rules[at + 1], rules[at + 2], rules[at + 3] = month, day, dow, time_
        zone.rules = tuple(rules)
        if zone.savings == 0:
            zone.savings = 3600000

    def useDaylightTime(self):
        return 1 if self._zone.rules is not None else 0

    observesDaylightTime = useDaylightTime

    def inDaylightTime(self, date):
        return 1 if self._zone.in_dst(date._ms) else 0

    def getOffset(self, when, *rest):
        if rest:
            era, year, month, day, dow, millis = (when,) + rest
            wall_standard = days_from_civil(year, month + 1, day) * 86400000 + millis
            return self._zone.offset(wall_standard - self._zone.fixed)
        return self._zone.offset(when)

    def hasSameRules(self, other):
        return 1 if isinstance(other, SimpleTimeZone) and other._zone.fixed == self._zone.fixed and \
            other._zone.rules == self._zone.rules and other._zone.savings == self._zone.savings else 0

    def clone(self):
        zone = self._zone
        return SimpleTimeZone.__new__(SimpleTimeZone)._copy_of(zone)

    def _copy_of(self, zone):
        TimeZone.__init__(self, _RuleZone(zone.id, zone.fixed, zone.rules, zone.savings))
        return self

    def equals(self, other):
        return 1 if isinstance(other, SimpleTimeZone) and other._zone.id == self._zone.id and self.hasSameRules(other) else 0

    def hashCode(self):
        from .jfunc import string_hash
        return runtime.wrap32(string_hash(self._zone.id) ^ self._zone.fixed)

    def toString(self):
        zone = self._zone
        return "java.util.SimpleTimeZone[id=%s,offset=%d,dstSavings=%d,useDaylight=%s]" % (
            zone.id, zone.fixed, zone.savings if zone.rules is not None else 3600000, "true" if zone.rules is not None else "false")


def _time_error(message):
    runtime.throw_new("java.time.DateTimeException", message)


_MONTH_NAMES = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER",
                "DECEMBER"]


@host_class("java.time.temporal.ValueRange", final=True, interfaces=("java.io.Serializable",))
class ValueRange(Object):
    def __init__(self, min_smallest, min_largest, max_smallest, max_largest):
        self._ms, self._ml, self._xs, self._xl = min_smallest, min_largest, max_smallest, max_largest

    @staticmethod
    def _make(*bounds):
        if len(bounds) == 2:
            bounds = (bounds[0], bounds[0], bounds[1], bounds[1])
        elif len(bounds) == 3:
            bounds = (bounds[0], bounds[0], bounds[1], bounds[2])
        a, b, c, d = bounds
        if a > b:
            runtime.throw_new("java.lang.IllegalArgumentException", "Smallest minimum value must be less than largest minimum value")
        if c > d:
            runtime.throw_new("java.lang.IllegalArgumentException", "Smallest maximum value must be less than largest maximum value")
        if b > d:
            runtime.throw_new("java.lang.IllegalArgumentException", "Minimum value must be less than maximum value")
        return ValueRange(a, b, c, d)

    of = staticmethod(lambda *bounds: ValueRange._make(*bounds))

    def isFixed(self):
        return 1 if self._ms == self._ml and self._xs == self._xl else 0

    def getMinimum(self):
        return self._ms

    def getLargestMinimum(self):
        return self._ml

    def getSmallestMaximum(self):
        return self._xs

    def getMaximum(self):
        return self._xl

    def isIntValue(self):
        return 1 if self._ms >= -0x80000000 and self._xl <= 0x7FFFFFFF else 0

    def isValidValue(self, value):
        return 1 if self._ms <= value <= self._xl else 0

    def isValidIntValue(self, value):
        return 1 if self.isIntValue() and self.isValidValue(value) else 0

    def checkValidValue(self, value, field):
        if not self._ms <= value <= self._xl:
            name = field.toString() if field is not None else "Value"
            _time_error("Invalid value for %s (valid values %s): %d" % (name, self.toString(), value))
        return value

    def checkValidIntValue(self, value, field):
        if not self.isValidIntValue(value):
            _time_error("Invalid int value for %s: %d" % (field.toString() if field is not None else "Value", value))
        return value

    def equals(self, other):
        return 1 if isinstance(other, ValueRange) and (self._ms, self._ml, self._xs, self._xl) == (
            other._ms, other._ml, other._xs, other._xl) else 0

    def hashCode(self):
        h = self._ms + (self._ml << 16) + (self._ml >> 48) + (self._xs << 32) + (self._xs >> 32) + (self._xl << 48) + (self._xl >> 16)
        return runtime.wrap32((h ^ (h >> 32)) & 0xFFFFFFFF)

    def toString(self):
        text = str(self._ms) + ("/" + str(self._ml) if self._ms != self._ml else "") + " - " + str(self._xs) + (
            "/" + str(self._xl) if self._xs != self._xl else "")
        return text


@host_class("java.time.MonthDay", final=True, interfaces=("java.lang.Comparable", "java.io.Serializable",
                                                           "java.time.temporal.TemporalAccessor"))
class MonthDay(Object):
    def __init__(self, month, day):
        self._m, self._d = month, day

    @staticmethod
    def of(month, day):
        number = month if isinstance(month, int) else month.getValue()
        if not 1 <= number <= 12:
            _time_error("Invalid value for MonthOfYear: %d" % number)
        if not 1 <= day <= 31:
            _time_error("Invalid value for DayOfMonth (valid values 1 - 28/31): %d" % day)
        if day > month_length(2000, number - 1):
            _time_error("Illegal value for DayOfMonth field, value %d is not valid for month %s" % (day, _MONTH_NAMES[number - 1]))
        return MonthDay(number, day)

    @staticmethod
    def parse(text):
        import re
        found = re.fullmatch(r"--(\d{2})-(\d{2})", text)
        if found is None:
            runtime.throw_new("java.time.format.DateTimeParseException", "Text '%s' could not be parsed at index 0" % text)
        try:
            return MonthDay.of(int(found.group(1)), int(found.group(2)))
        except Exception as error:
            failure = runtime.to_throwable(error)
            raise runtime.make_throwable(lookup_host("java.time.format.DateTimeParseException").py,
                                         "Text '%s' could not be parsed: %s" % (text, failure.getMessage()))

    def getMonthValue(self):
        return self._m

    def getMonth(self):
        return lookup_host("java.time.Month").py._all[self._m - 1]

    def getDayOfMonth(self):
        return self._d

    def isValidYear(self, year):
        return 0 if self._d == 29 and self._m == 2 and not is_leap(year) else 1

    def atYear(self, year):
        return lookup_host("java.time.LocalDate").py.of(year, self._m, min(self._d, month_length(year, self._m - 1)))

    def withMonth(self, month):
        return MonthDay(month, min(self._d, month_length(2000, month - 1)))

    def withDayOfMonth(self, day):
        return MonthDay.of(self._m, day)

    def isBefore(self, other):
        return 1 if self.compareTo(other) < 0 else 0

    def isAfter(self, other):
        return 1 if self.compareTo(other) > 0 else 0

    def compareTo(self, other):
        return (self._m - other._m) or (self._d - other._d)

    def equals(self, other):
        return 1 if isinstance(other, MonthDay) and (self._m, self._d) == (other._m, other._d) else 0

    def hashCode(self):
        return (self._m << 6) + self._d

    def toString(self):
        return "--%02d-%02d" % (self._m, self._d)
