"""java.util.concurrent over python threads: atomics, locks, executors, futures, blocking queues, ThreadLocal

an exception thrown by a task is kept in its Future and rethrown by get() inside an ExecutionException, as in the jdk.
a worker thread is a daemon: the interpreter may exit while a pool is idle"""

import queue as pyqueue
import threading
import time

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import jequals, jstring
from .jlang import Enum, Integer, Long, Object, Runnable, Thread, System
from .jutil import AbstractQueue, ArrayDeque, PyIterator, check_nonnull, iterate, no_such_element
from .jmap import ArrayList


@host_class("java.util.concurrent.TimeUnit", final=True, interfaces=("java.lang.Comparable",))
class TimeUnit(Enum):
    _NANOS = {"NANOSECONDS": 1, "MICROSECONDS": 1000, "MILLISECONDS": 1000000, "SECONDS": 1000000000,
              "MINUTES": 60 * 1000000000, "HOURS": 3600 * 1000000000, "DAYS": 86400 * 1000000000}

    def _nanos(self):
        return TimeUnit._NANOS[self._name]

    @jmethod("toNanos", "(J)J")
    def toNanos(self, duration):
        return runtime.wrap64(duration * self._nanos())

    @jmethod("toMicros", "(J)J")
    def toMicros(self, duration):
        return _convert(duration, self._nanos(), 1000)

    @jmethod("toMillis", "(J)J")
    def toMillis(self, duration):
        return _convert(duration, self._nanos(), 1000000)

    @jmethod("toSeconds", "(J)J")
    def toSeconds(self, duration):
        return _convert(duration, self._nanos(), 1000000000)

    @jmethod("toMinutes", "(J)J")
    def toMinutes(self, duration):
        return _convert(duration, self._nanos(), 60 * 1000000000)

    @jmethod("toHours", "(J)J")
    def toHours(self, duration):
        return _convert(duration, self._nanos(), 3600 * 1000000000)

    @jmethod("toDays", "(J)J")
    def toDays(self, duration):
        return _convert(duration, self._nanos(), 86400 * 1000000000)

    @jmethod("convert", "(JLjava/util/concurrent/TimeUnit;)J")
    def convert(self, duration, source):
        return _convert(duration, source._nanos(), self._nanos())

    @jmethod("sleep", "(J)V")
    def sleep(self, duration):
        if duration > 0:
            time.sleep(duration * self._nanos() / 1e9)

    @jstatic("values", "()[Ljava/util/concurrent/TimeUnit;")
    def values():
        array = runtime.new_array("[Ljava/util/concurrent/TimeUnit;", 0)
        array.extend(_UNITS)
        return array

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/util/concurrent/TimeUnit;")
    def valueOf(name):
        for unit in _UNITS:
            if unit._name == name:
                return unit
        runtime.throw_new("java.lang.IllegalArgumentException", "No enum constant java.util.concurrent.TimeUnit." + name)


def _convert(duration, from_nanos, to_nanos):
    total = duration * from_nanos
    value = abs(total) // to_nanos
    value = -value if total < 0 else value
    return max(min(value, runtime.LONG_MAX), runtime.LONG_MIN)


_UNITS = []
for _index, _name in enumerate(TimeUnit._NANOS):
    _unit = TimeUnit.__new__(TimeUnit)
    _unit._name = _name
    _unit._ordinal = _index
    setattr(TimeUnit, _name, _unit)
    _UNITS.append(_unit)


def seconds_of(timeout, unit):
    return None if timeout is None else unit.toNanos(timeout) / 1e9


@host_class("java.util.concurrent.atomic.AtomicInteger", interfaces=("java.io.Serializable",))
class AtomicInteger(Object):
    def __init__(self, value=0):
        self._v = value
        self._lock = threading.Lock()

    @jmethod("<init>", "()V")
    def _init0(self):
        AtomicInteger.__init__(self)

    @jmethod("<init>", "(I)V")
    def _init1(self, value):
        AtomicInteger.__init__(self, value)

    _WRAP = staticmethod(runtime.wrap32)

    @jmethod("get", "()I")
    @jmethod("intValue", "()I")
    @jmethod("getPlain", "()I")
    @jmethod("getAcquire", "()I")
    def get(self):
        return self._v

    @jmethod("set", "(I)V")
    @jmethod("lazySet", "(I)V")
    @jmethod("setPlain", "(I)V")
    @jmethod("setRelease", "(I)V")
    def set(self, value):
        self._v = value

    @jmethod("getAndSet", "(I)I")
    def getAndSet(self, value):
        with self._lock:
            old, self._v = self._v, value
        return old

    @jmethod("incrementAndGet", "()I")
    def incrementAndGet(self):
        return self.addAndGet(1)

    @jmethod("decrementAndGet", "()I")
    def decrementAndGet(self):
        return self.addAndGet(-1)

    @jmethod("getAndIncrement", "()I")
    def getAndIncrement(self):
        return self.getAndAdd(1)

    @jmethod("getAndDecrement", "()I")
    def getAndDecrement(self):
        return self.getAndAdd(-1)

    @jmethod("addAndGet", "(I)I")
    def addAndGet(self, delta):
        with self._lock:
            self._v = self._WRAP(self._v + delta)
            return self._v

    @jmethod("getAndAdd", "(I)I")
    def getAndAdd(self, delta):
        with self._lock:
            old = self._v
            self._v = self._WRAP(old + delta)
            return old

    @jmethod("compareAndSet", "(II)Z")
    @jmethod("weakCompareAndSet", "(II)Z")
    def compareAndSet(self, expected, update):
        with self._lock:
            if self._v == expected:
                self._v = update
                return 1
            return 0

    @jmethod("updateAndGet", "(Ljava/util/function/IntUnaryOperator;)I")
    def updateAndGet(self, operator):
        with self._lock:
            self._v = operator.applyAsInt(self._v)
            return self._v

    @jmethod("getAndUpdate", "(Ljava/util/function/IntUnaryOperator;)I")
    def getAndUpdate(self, operator):
        with self._lock:
            old = self._v
            self._v = operator.applyAsInt(old)
            return old

    @jmethod("accumulateAndGet", "(ILjava/util/function/IntBinaryOperator;)I")
    def accumulateAndGet(self, other, operator):
        with self._lock:
            self._v = operator.applyAsInt(self._v, other)
            return self._v

    @jmethod("longValue", "()J")
    def longValue(self):
        return self._v

    @jmethod("doubleValue", "()D")
    def doubleValue(self):
        return float(self._v)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return str(self._v)


@host_class("java.util.concurrent.atomic.AtomicLong", interfaces=("java.io.Serializable",))
class AtomicLong(AtomicInteger):
    _WRAP = staticmethod(runtime.wrap64)

    @jmethod("<init>", "()V")
    def _init0(self):
        AtomicInteger.__init__(self)

    @jmethod("<init>", "(J)V")
    def _init1(self, value):
        AtomicInteger.__init__(self, value)

    @jmethod("get", "()J")
    @jmethod("longValue", "()J")
    def get(self):
        return self._v

    @jmethod("set", "(J)V")
    def set(self, value):
        self._v = value

    @jmethod("getAndSet", "(J)J")
    def getAndSet(self, value):
        return AtomicInteger.getAndSet(self, value)

    @jmethod("incrementAndGet", "()J")
    def incrementAndGet(self):
        return self.addAndGet(1)

    @jmethod("decrementAndGet", "()J")
    def decrementAndGet(self):
        return self.addAndGet(-1)

    @jmethod("getAndIncrement", "()J")
    def getAndIncrement(self):
        return self.getAndAdd(1)

    @jmethod("getAndDecrement", "()J")
    def getAndDecrement(self):
        return self.getAndAdd(-1)

    @jmethod("addAndGet", "(J)J")
    def addAndGet(self, delta):
        return AtomicInteger.addAndGet(self, delta)

    @jmethod("getAndAdd", "(J)J")
    def getAndAdd(self, delta):
        return AtomicInteger.getAndAdd(self, delta)

    @jmethod("compareAndSet", "(JJ)Z")
    def compareAndSet(self, expected, update):
        return AtomicInteger.compareAndSet(self, expected, update)

    @jmethod("intValue", "()I")
    def intValue(self):
        return runtime.wrap32(self._v)


@host_class("java.util.concurrent.atomic.AtomicBoolean", interfaces=("java.io.Serializable",))
class AtomicBoolean(Object):
    def __init__(self, value=False):
        self._v = 1 if value else 0
        self._lock = threading.Lock()

    @jmethod("<init>", "()V")
    def _init0(self):
        AtomicBoolean.__init__(self)

    @jmethod("<init>", "(Z)V")
    def _init1(self, value):
        AtomicBoolean.__init__(self, value)

    @jmethod("get", "()Z")
    def get(self):
        return self._v

    @jmethod("set", "(Z)V")
    @jmethod("lazySet", "(Z)V")
    def set(self, value):
        self._v = 1 if value else 0

    @jmethod("getAndSet", "(Z)Z")
    def getAndSet(self, value):
        with self._lock:
            old, self._v = self._v, 1 if value else 0
        return old

    @jmethod("compareAndSet", "(ZZ)Z")
    def compareAndSet(self, expected, update):
        with self._lock:
            if self._v == (1 if expected else 0):
                self._v = 1 if update else 0
                return 1
            return 0

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "true" if self._v else "false"


@host_class("java.util.concurrent.atomic.AtomicReference", interfaces=("java.io.Serializable",))
class AtomicReference(Object):
    def __init__(self, value=None):
        self._v = value
        self._lock = threading.Lock()

    @jmethod("<init>", "()V")
    def _init0(self):
        AtomicReference.__init__(self)

    @jmethod("<init>", "(Ljava/lang/Object;)V")
    def _init1(self, value):
        AtomicReference.__init__(self, value)

    @jmethod("get", "()Ljava/lang/Object;")
    def get(self):
        return self._v

    @jmethod("set", "(Ljava/lang/Object;)V")
    @jmethod("lazySet", "(Ljava/lang/Object;)V")
    def set(self, value):
        self._v = value

    @jmethod("getAndSet", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def getAndSet(self, value):
        with self._lock:
            old, self._v = self._v, value
        return old

    @jmethod("compareAndSet", "(Ljava/lang/Object;Ljava/lang/Object;)Z")
    def compareAndSet(self, expected, update):
        with self._lock:
            if self._v is expected:
                self._v = update
                return 1
            return 0

    @jmethod("updateAndGet", "(Ljava/util/function/UnaryOperator;)Ljava/lang/Object;")
    def updateAndGet(self, operator):
        with self._lock:
            self._v = operator.apply(self._v)
            return self._v

    @jmethod("getAndUpdate", "(Ljava/util/function/UnaryOperator;)Ljava/lang/Object;")
    def getAndUpdate(self, operator):
        with self._lock:
            old = self._v
            self._v = operator.apply(old)
            return old

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return jstring(self._v)


@host_class("java.util.concurrent.locks.Lock", interface=True)
class Lock:
    __slots__ = ()


@host_class("java.util.concurrent.locks.Condition", interface=True)
class Condition:
    __slots__ = ()


@host_class("java.util.concurrent.locks.ReentrantLock", interfaces=("java.util.concurrent.locks.Lock", "java.io.Serializable"))
class ReentrantLock(Object):
    def __init__(self, fair=False):
        self._lock = threading.RLock()
        self._owner = None
        self._count = 0

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Z)V")
    def _init(self, fair=False):
        ReentrantLock.__init__(self, fair)

    @jmethod("lock", "()V")
    @jmethod("lockInterruptibly", "()V")
    def lock(self):
        self._lock.acquire()
        self._owner = threading.get_ident()
        self._count += 1

    @jmethod("tryLock", "()Z")
    @jmethod("tryLock", "(JLjava/util/concurrent/TimeUnit;)Z")
    def tryLock(self, timeout=None, unit=None):
        got = self._lock.acquire(timeout=seconds_of(timeout, unit)) if timeout is not None else self._lock.acquire(False)
        if got:
            self._owner = threading.get_ident()
            self._count += 1
        return 1 if got else 0

    @jmethod("unlock", "()V")
    def unlock(self):
        if self._owner != threading.get_ident():
            runtime.throw_new("java.lang.IllegalMonitorStateException", None)
        self._count -= 1
        if self._count == 0:
            self._owner = None
        self._lock.release()

    @jmethod("isLocked", "()Z")
    def isLocked(self):
        return 1 if self._count else 0

    @jmethod("isHeldByCurrentThread", "()Z")
    def isHeldByCurrentThread(self):
        return 1 if self._owner == threading.get_ident() else 0

    @jmethod("getHoldCount", "()I")
    def getHoldCount(self):
        return self._count if self._owner == threading.get_ident() else 0

    @jmethod("newCondition", "()Ljava/util/concurrent/locks/Condition;")
    def newCondition(self):
        return LockCondition(self)


@host_class("java.util.concurrent.locks.ReentrantLock$ConditionObject", interfaces=("java.util.concurrent.locks.Condition",))
class LockCondition(Object):
    def __init__(self, owner):
        self._owner = owner
        self._cond = threading.Condition(owner._lock)

    def _check(self):
        if self._owner._owner != threading.get_ident():
            runtime.throw_new("java.lang.IllegalMonitorStateException", None)

    @jmethod("await", "()V")
    def await_(self):
        self._check()
        count, self._owner._count = self._owner._count, 0
        self._owner._owner = None
        try:
            self._cond.wait()
        finally:
            self._owner._owner = threading.get_ident()
            self._owner._count = count

    @jmethod("await", "(JLjava/util/concurrent/TimeUnit;)Z")
    def await_timeout(self, timeout, unit):
        self._check()
        count, self._owner._count = self._owner._count, 0
        self._owner._owner = None
        try:
            return 1 if self._cond.wait(seconds_of(timeout, unit)) else 0
        finally:
            self._owner._owner = threading.get_ident()
            self._owner._count = count

    @jmethod("signal", "()V")
    def signal(self):
        self._check()
        self._cond.notify()

    @jmethod("signalAll", "()V")
    def signalAll(self):
        self._check()
        self._cond.notify_all()


setattr(LockCondition, "await", LockCondition.await_)


@host_class("java.util.concurrent.locks.ReadWriteLock", interface=True)
class ReadWriteLock:
    __slots__ = ()


@host_class("java.util.concurrent.locks.ReentrantReadWriteLock", interfaces=("java.util.concurrent.locks.ReadWriteLock",))
class ReentrantReadWriteLock(Object):
    """one lock stands for both halves: readers exclude each other, which is correct if slower than the jdk"""

    def __init__(self, fair=False):
        self._rw = ReentrantLock()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Z)V")
    def _init(self, fair=False):
        ReentrantReadWriteLock.__init__(self)

    @jmethod("readLock", "()Ljava/util/concurrent/locks/Lock;")
    @jmethod("writeLock", "()Ljava/util/concurrent/locks/Lock;")
    def readLock(self):
        return self._rw


@host_class("java.util.concurrent.Semaphore")
class Semaphore(Object):
    def __init__(self, permits=0, fair=False):
        self._permits = permits
        self._cond = threading.Condition()

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(IZ)V")
    def _init(self, permits, fair=False):
        Semaphore.__init__(self, permits)

    @jmethod("acquire", "()V")
    @jmethod("acquire", "(I)V")
    def acquire(self, count=1):
        with self._cond:
            while self._permits < count:
                self._cond.wait()
            self._permits -= count

    @jmethod("tryAcquire", "()Z")
    @jmethod("tryAcquire", "(I)Z")
    @jmethod("tryAcquire", "(JLjava/util/concurrent/TimeUnit;)Z")
    def tryAcquire(self, first=1, unit=None):
        timeout = None
        count = 1
        if unit is not None:
            timeout = seconds_of(first, unit)
        else:
            count = first
        with self._cond:
            if self._permits < count and timeout:
                self._cond.wait_for(lambda: self._permits >= count, timeout)
            if self._permits >= count:
                self._permits -= count
                return 1
            return 0

    @jmethod("release", "()V")
    @jmethod("release", "(I)V")
    def release(self, count=1):
        with self._cond:
            self._permits += count
            self._cond.notify_all()

    @jmethod("availablePermits", "()I")
    def availablePermits(self):
        return self._permits


@host_class("java.util.concurrent.CountDownLatch")
class CountDownLatch(Object):
    def __init__(self, count):
        if count < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "count < 0")
        self._count = count
        self._cond = threading.Condition()

    @jmethod("<init>", "(I)V")
    def _init(self, count):
        CountDownLatch.__init__(self, count)

    @jmethod("countDown", "()V")
    def countDown(self):
        with self._cond:
            if self._count > 0:
                self._count -= 1
                if self._count == 0:
                    self._cond.notify_all()

    @jmethod("getCount", "()J")
    def getCount(self):
        return self._count

    @jmethod("await", "()V")
    @jmethod("await", "(JLjava/util/concurrent/TimeUnit;)Z")
    def await_(self, timeout=None, unit=None):
        with self._cond:
            ok = self._cond.wait_for(lambda: self._count == 0, seconds_of(timeout, unit))
        return None if timeout is None else (1 if ok else 0)


setattr(CountDownLatch, "await", CountDownLatch.await_)


@host_class("java.util.concurrent.Callable", interface=True)
class Callable:
    __slots__ = ()


@host_class("java.util.concurrent.Executor", interface=True)
class Executor:
    __slots__ = ()


@host_class("java.util.concurrent.Future", interface=True)
class Future:
    __slots__ = ()


@host_class("java.util.concurrent.FutureTask", interfaces=("java.util.concurrent.Future", "java.lang.Runnable"))
class FutureTask(Object):
    def __init__(self, task=None, result=None):
        self._task = task
        self._result = result
        self._done = threading.Event()
        self._value = None
        self._error = None
        self._cancelled = False
        self._lock = threading.Lock()

    @jmethod("<init>", "(Ljava/util/concurrent/Callable;)V")
    def _init(self, task):
        FutureTask.__init__(self, task)

    @jmethod("<init>", "(Ljava/lang/Runnable;Ljava/lang/Object;)V")
    def _init_runnable(self, task, result):
        FutureTask.__init__(self, task, result)

    @jmethod("run", "()V")
    def run(self):
        with self._lock:
            if self._done.is_set():
                return
        try:
            task = self._task
            if hasattr(task, "call"):
                value = task.call()
            else:
                task.run()
                value = self._result
            self._finish(value, None)
        except Exception as error:
            self._finish(None, runtime.to_throwable(error))

    def _finish(self, value, error):
        with self._lock:
            if self._done.is_set():
                return
            self._value, self._error = value, error
            self._done.set()
        self.done()

    @jmethod("done", "()V")
    def done(self):
        return None

    @jmethod("get", "()Ljava/lang/Object;")
    @jmethod("get", "(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;")
    def get(self, timeout=None, unit=None):
        if not self._done.wait(seconds_of(timeout, unit)):
            runtime.throw_new("java.util.concurrent.TimeoutException", None)
        if self._cancelled:
            runtime.throw_new("java.util.concurrent.CancellationException", None)
        if self._error is not None:
            wrapper = runtime.make_throwable(
                runtime.api.lookup_host("java.util.concurrent.ExecutionException").py, self._error.toString())
            wrapper._cause = self._error
            raise wrapper
        return self._value

    @jmethod("isDone", "()Z")
    def isDone(self):
        return 1 if self._done.is_set() else 0

    @jmethod("isCancelled", "()Z")
    def isCancelled(self):
        return 1 if self._cancelled else 0

    @jmethod("cancel", "(Z)Z")
    def cancel(self, interrupt):
        with self._lock:
            if self._done.is_set():
                return 0
            self._cancelled = True
            self._done.set()
        return 1


@host_class("java.util.concurrent.ExecutorService", interface=True, interfaces=("java.util.concurrent.Executor",))
class ExecutorService(Executor):
    __slots__ = ()


@host_class("java.util.concurrent.ThreadPoolExecutor", interfaces=("java.util.concurrent.ExecutorService",))
class ThreadPoolExecutor(Object):
    """worker threads that take tasks from a queue; a pool grows to its limit when the tasks are waiting"""

    def __init__(self, size=1, name="pool"):
        self._size = size if size > 0 else 1000
        self._tasks = pyqueue.Queue()
        self._workers = []
        self._idle = 0
        self._lock = threading.Lock()
        self._shutdown = False
        self._active = 0
        self._name = name
        self._cond = threading.Condition(self._lock)

    @jmethod("allowCoreThreadTimeOut", "(Z)V")
    def allowCoreThreadTimeOut(self, flag):
        self._core_timeout = bool(flag)

    @jmethod("purge", "()V")
    def purge(self):
        return None

    @jmethod("remove", "(Ljava/lang/Runnable;)Z")
    def remove(self, task):
        with self._lock:
            kept = []
            found = False
            while True:
                try:
                    item = self._tasks.get_nowait()
                except pyqueue.Empty:
                    break
                if not found and (item is task or getattr(item, "_runnable", None) is task):
                    found = True
                else:
                    kept.append(item)
            for item in kept:
                self._tasks.put(item)
        return 1 if found else 0

    def _spawn(self):
        thread = threading.Thread(target=self._work, daemon=True, name="%s-thread-%d" % (self._name, len(self._workers) + 1))
        self._workers.append(thread)
        thread.start()

    def _work(self):
        while True:
            task = self._tasks.get()
            if task is None:
                return
            with self._lock:
                self._active += 1
            try:
                task.run()
            except Exception as error:
                failure = runtime.to_throwable(error)
                System.err.println('Exception in thread "%s" %s' % (threading.current_thread().name, failure.toString()))
            finally:
                with self._cond:
                    self._active -= 1
                    self._cond.notify_all()

    @jmethod("execute", "(Ljava/lang/Runnable;)V")
    def execute(self, task):
        check_nonnull(task)
        with self._lock:
            if self._shutdown:
                runtime.throw_new("java.util.concurrent.RejectedExecutionException", "executor has been shut down")
            if len(self._workers) < self._size and (self._tasks.qsize() >= 0):
                busy = self._active + self._tasks.qsize()
                if len(self._workers) < min(self._size, busy + 1):
                    self._spawn()
            self._tasks.put(task)

    @jmethod("submit", "(Ljava/lang/Runnable;)Ljava/util/concurrent/Future;")
    @jmethod("submit", "(Ljava/util/concurrent/Callable;)Ljava/util/concurrent/Future;")
    @jmethod("submit", "(Ljava/lang/Runnable;Ljava/lang/Object;)Ljava/util/concurrent/Future;")
    def submit(self, task, result=None):
        future = FutureTask(check_nonnull(task), result)
        self.execute(future)
        return future

    @jmethod("invokeAll", "(Ljava/util/Collection;)Ljava/util/List;")
    def invokeAll(self, tasks):
        futures = ArrayList()
        for task in iterate(tasks):
            futures.add(self.submit(task))
        for future in iterate(futures):
            future._done.wait()
        return futures

    @jmethod("shutdown", "()V")
    def shutdown(self):
        with self._lock:
            self._shutdown = True
            for _ in self._workers:
                self._tasks.put(None)

    @jmethod("shutdownNow", "()Ljava/util/List;")
    def shutdownNow(self):
        pending = ArrayList()
        with self._lock:
            self._shutdown = True
            while True:
                try:
                    task = self._tasks.get_nowait()
                except pyqueue.Empty:
                    break
                if task is not None:
                    pending.add(task)
            for _ in self._workers:
                self._tasks.put(None)
        return pending

    @jmethod("isShutdown", "()Z")
    def isShutdown(self):
        return 1 if self._shutdown else 0

    @jmethod("isTerminated", "()Z")
    def isTerminated(self):
        return 1 if self._shutdown and not any(w.is_alive() for w in self._workers) else 0

    @jmethod("awaitTermination", "(JLjava/util/concurrent/TimeUnit;)Z")
    def awaitTermination(self, timeout, unit):
        deadline = time.monotonic() + seconds_of(timeout, unit)
        for worker in list(self._workers):
            worker.join(max(deadline - time.monotonic(), 0))
        return self.isTerminated()

    @jmethod("close", "()V")
    def close(self):
        self.shutdown()
        self.awaitTermination(1 << 30, TimeUnit.SECONDS)


@host_class("java.util.concurrent.ScheduledExecutorService", interface=True, interfaces=("java.util.concurrent.ExecutorService",))
class ScheduledExecutorService(ExecutorService):
    __slots__ = ()


@host_class("java.util.concurrent.ScheduledThreadPoolExecutor", interfaces=("java.util.concurrent.ScheduledExecutorService",))
class ScheduledThreadPoolExecutor(ThreadPoolExecutor):
    @jmethod("setRemoveOnCancelPolicy", "(Z)V")
    @jmethod("setContinueExistingPeriodicTasksAfterShutdownPolicy", "(Z)V")
    @jmethod("setExecuteExistingDelayedTasksAfterShutdownPolicy", "(Z)V")
    def setPolicy(self, flag):
        self._policy = bool(flag)

    @jmethod("schedule", "(Ljava/lang/Runnable;JLjava/util/concurrent/TimeUnit;)Ljava/util/concurrent/ScheduledFuture;")
    @jmethod("schedule", "(Ljava/util/concurrent/Callable;JLjava/util/concurrent/TimeUnit;)Ljava/util/concurrent/ScheduledFuture;")
    def schedule(self, task, delay, unit):
        future = FutureTask(task)
        timer = threading.Timer(seconds_of(delay, unit), lambda: self.execute(future) if not self._shutdown else None)
        timer.daemon = True
        timer.start()
        return future

    @jmethod("scheduleAtFixedRate", "(Ljava/lang/Runnable;JJLjava/util/concurrent/TimeUnit;)Ljava/util/concurrent/ScheduledFuture;")
    @jmethod("scheduleWithFixedDelay", "(Ljava/lang/Runnable;JJLjava/util/concurrent/TimeUnit;)Ljava/util/concurrent/ScheduledFuture;")
    def scheduleAtFixedRate(self, task, initial, period, unit):
        handle = FutureTask(task)
        interval = seconds_of(period, unit)

        def tick():
            if self._shutdown or handle._cancelled:
                return
            try:
                self.execute(task)
            except Exception:
                return
            timer = threading.Timer(interval, tick)
            timer.daemon = True
            timer.start()
        first = threading.Timer(seconds_of(initial, unit), tick)
        first.daemon = True
        first.start()
        return handle


host_class("java.util.concurrent.ScheduledFuture", interface=True, interfaces=("java.util.concurrent.Future",))(
    type("ScheduledFuture", (), {"__slots__": ()}))


@host_class("java.util.concurrent.Executors", final=True)
class Executors(Object):
    @jstatic("newFixedThreadPool", "(I)Ljava/util/concurrent/ExecutorService;")
    def newFixedThreadPool(size):
        if size <= 0:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        return ThreadPoolExecutor(size)

    @jstatic("newSingleThreadExecutor", "()Ljava/util/concurrent/ExecutorService;")
    def newSingleThreadExecutor():
        return ThreadPoolExecutor(1)

    @jstatic("newCachedThreadPool", "()Ljava/util/concurrent/ExecutorService;")
    def newCachedThreadPool():
        return ThreadPoolExecutor(0)

    @jstatic("newScheduledThreadPool", "(I)Ljava/util/concurrent/ScheduledExecutorService;")
    def newScheduledThreadPool(size):
        return ScheduledThreadPoolExecutor(max(size, 1))

    @jstatic("newSingleThreadScheduledExecutor", "()Ljava/util/concurrent/ScheduledExecutorService;")
    def newSingleThreadScheduledExecutor():
        return ScheduledThreadPoolExecutor(1)


@host_class("java.util.concurrent.CompletableFuture", interfaces=("java.util.concurrent.Future",))
class CompletableFuture(FutureTask):
    def __init__(self):
        FutureTask.__init__(self)
        self._callbacks = []

    @jmethod("<init>", "()V")
    def _init(self):
        CompletableFuture.__init__(self)

    @staticmethod
    def _async(function):
        future = CompletableFuture()

        def work():
            try:
                future.complete(function())
            except Exception as error:
                future.completeExceptionally(runtime.to_throwable(error))
        threading.Thread(target=work, daemon=True).start()
        return future

    @jstatic("supplyAsync", "(Ljava/util/function/Supplier;)Ljava/util/concurrent/CompletableFuture;")
    @jstatic("supplyAsync", "(Ljava/util/function/Supplier;Ljava/util/concurrent/Executor;)Ljava/util/concurrent/CompletableFuture;")
    def supplyAsync(supplier, executor=None):
        return CompletableFuture._async(lambda: supplier.get())

    @jstatic("runAsync", "(Ljava/lang/Runnable;)Ljava/util/concurrent/CompletableFuture;")
    @jstatic("runAsync", "(Ljava/lang/Runnable;Ljava/util/concurrent/Executor;)Ljava/util/concurrent/CompletableFuture;")
    def runAsync(task, executor=None):
        return CompletableFuture._async(lambda: task.run())

    @jstatic("completedFuture", "(Ljava/lang/Object;)Ljava/util/concurrent/CompletableFuture;")
    def completedFuture(value):
        future = CompletableFuture()
        future.complete(value)
        return future

    @jmethod("complete", "(Ljava/lang/Object;)Z")
    def complete(self, value):
        with self._lock:
            if self._done.is_set():
                return 0
            self._value = value
            self._done.set()
            callbacks, self._callbacks = self._callbacks, []
        for callback in callbacks:
            callback()
        return 1

    @jmethod("completeExceptionally", "(Ljava/lang/Throwable;)Z")
    def completeExceptionally(self, error):
        with self._lock:
            if self._done.is_set():
                return 0
            self._error = error
            self._done.set()
            callbacks, self._callbacks = self._callbacks, []
        for callback in callbacks:
            callback()
        return 1

    def _then(self, on_value):
        result = CompletableFuture()

        def fire():
            if self._error is not None:
                wrapper = runtime.make_throwable(
                    runtime.api.lookup_host("java.util.concurrent.CompletionException").py, self._error.toString())
                wrapper._cause = self._error
                result.completeExceptionally(wrapper)
                return
            try:
                result.complete(on_value(self._value))
            except Exception as error:
                result.completeExceptionally(runtime.to_throwable(error))
        with self._lock:
            if not self._done.is_set():
                self._callbacks.append(fire)
                return result
        fire()
        return result

    @jmethod("thenApply", "(Ljava/util/function/Function;)Ljava/util/concurrent/CompletableFuture;")
    @jmethod("thenApplyAsync", "(Ljava/util/function/Function;)Ljava/util/concurrent/CompletableFuture;")
    def thenApply(self, function):
        return self._then(lambda value: function.apply(value))

    @jmethod("thenAccept", "(Ljava/util/function/Consumer;)Ljava/util/concurrent/CompletableFuture;")
    def thenAccept(self, consumer):
        return self._then(lambda value: consumer.accept(value))

    @jmethod("thenRun", "(Ljava/lang/Runnable;)Ljava/util/concurrent/CompletableFuture;")
    def thenRun(self, task):
        return self._then(lambda value: task.run())

    @jmethod("thenCompose", "(Ljava/util/function/Function;)Ljava/util/concurrent/CompletableFuture;")
    def thenCompose(self, function):
        return self._then(lambda value: function.apply(value).join())

    @jmethod("exceptionally", "(Ljava/util/function/Function;)Ljava/util/concurrent/CompletableFuture;")
    def exceptionally(self, function):
        result = CompletableFuture()

        def fire():
            if self._error is None:
                result.complete(self._value)
            else:
                try:
                    result.complete(function.apply(self._error))
                except Exception as error:
                    result.completeExceptionally(runtime.to_throwable(error))
        with self._lock:
            if not self._done.is_set():
                self._callbacks.append(fire)
                return result
        fire()
        return result

    @jmethod("join", "()Ljava/lang/Object;")
    def join(self):
        self._done.wait()
        if self._error is not None:
            wrapper = runtime.make_throwable(
                runtime.api.lookup_host("java.util.concurrent.CompletionException").py, self._error.toString())
            wrapper._cause = self._error
            raise wrapper
        return self._value

    @jmethod("getNow", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def getNow(self, default):
        return self.join() if self._done.is_set() else default


@host_class("java.util.concurrent.BlockingQueue", interface=True, interfaces=("java.util.Queue",))
class BlockingQueue:
    __slots__ = ()


@host_class("java.util.concurrent.LinkedBlockingQueue", interfaces=("java.util.concurrent.BlockingQueue",))
class LinkedBlockingQueue(AbstractQueue):
    def __init__(self, capacity=None):
        self._a = []
        self._cap = capacity if isinstance(capacity, int) else (1 << 31) - 1
        self._cond = threading.Condition()
        self.modCount = 0
        if capacity is not None and not isinstance(capacity, int):
            self._a.extend(iterate(capacity))

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=None):
        LinkedBlockingQueue.__init__(self, capacity)

    def size(self):
        return len(self._a)

    def iterator(self):
        return PyIterator(list(self._a))

    @jmethod("put", "(Ljava/lang/Object;)V")
    def put(self, item):
        check_nonnull(item)
        with self._cond:
            while len(self._a) >= self._cap:
                self._cond.wait()
            self._a.append(item)
            self._cond.notify_all()

    @jmethod("offer", "(Ljava/lang/Object;)Z")
    @jmethod("offer", "(Ljava/lang/Object;JLjava/util/concurrent/TimeUnit;)Z")
    def offer(self, item, timeout=None, unit=None):
        check_nonnull(item)
        with self._cond:
            if len(self._a) >= self._cap and timeout:
                self._cond.wait_for(lambda: len(self._a) < self._cap, seconds_of(timeout, unit))
            if len(self._a) >= self._cap:
                return 0
            self._a.append(item)
            self._cond.notify_all()
            return 1

    @jmethod("take", "()Ljava/lang/Object;")
    def take(self):
        with self._cond:
            while not self._a:
                self._cond.wait()
            item = self._a.pop(0)
            self._cond.notify_all()
            return item

    @jmethod("poll", "()Ljava/lang/Object;")
    @jmethod("poll", "(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;")
    def poll(self, timeout=None, unit=None):
        with self._cond:
            if not self._a and timeout:
                self._cond.wait_for(lambda: bool(self._a), seconds_of(timeout, unit))
            if not self._a:
                return None
            item = self._a.pop(0)
            self._cond.notify_all()
            return item

    @jmethod("peek", "()Ljava/lang/Object;")
    def peek(self):
        return self._a[0] if self._a else None

    @jmethod("remainingCapacity", "()I")
    def remainingCapacity(self):
        return self._cap - len(self._a)

    @jmethod("clear", "()V")
    def clear(self):
        with self._cond:
            self._a.clear()
            self._cond.notify_all()

    @jmethod("drainTo", "(Ljava/util/Collection;)I")
    def drainTo(self, target):
        with self._cond:
            items, self._a = self._a, []
            self._cond.notify_all()
        for item in items:
            target.add(item)
        return len(items)


host_class("java.util.concurrent.ArrayBlockingQueue", interfaces=("java.util.concurrent.BlockingQueue",))(
    type("ArrayBlockingQueue", (LinkedBlockingQueue,), {}))
host_class("java.util.concurrent.ConcurrentLinkedQueue", interfaces=("java.util.Queue",))(
    type("ConcurrentLinkedQueue", (ArrayDeque,), {}))
host_class("java.util.concurrent.ConcurrentLinkedDeque", interfaces=("java.util.Deque",))(
    type("ConcurrentLinkedDeque", (ArrayDeque,), {}))
host_class("java.util.concurrent.CopyOnWriteArrayList", interfaces=("java.util.List",))(
    type("CopyOnWriteArrayList", (ArrayList,), {}))


@host_class("java.lang.ThreadLocal")
class ThreadLocal(Object):
    def __init__(self):
        self._local = threading.local()

    @jmethod("<init>", "()V")
    def _init(self):
        ThreadLocal.__init__(self)

    @jmethod("initialValue", "()Ljava/lang/Object;")
    def initialValue(self):
        return None

    @jmethod("get", "()Ljava/lang/Object;")
    def get(self):
        if not hasattr(self._local, "value"):
            self._local.value = self.initialValue()
        return self._local.value

    @jmethod("set", "(Ljava/lang/Object;)V")
    def set(self, value):
        self._local.value = value

    @jmethod("remove", "()V")
    def remove(self):
        if hasattr(self._local, "value"):
            del self._local.value

    @jstatic("withInitial", "(Ljava/util/function/Supplier;)Ljava/lang/ThreadLocal;")
    def withInitial(supplier):
        local = ThreadLocal()
        local.initialValue = lambda: supplier.get()
        return local
