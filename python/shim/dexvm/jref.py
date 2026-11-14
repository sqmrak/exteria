"""java.lang.ref: Reference, WeakReference, SoftReference, PhantomReference and ReferenceQueue

a weak or soft reference holds its referent through a python weak reference when the object can have one, so the
referent is collected as on a runtime and the reference then answers null. a value that python cannot reference weakly
(a str, a box, an array) is held strongly: it is immutable or small, and clearing it early would change what a program
sees. a phantom reference never hands out its referent"""

import collections
import threading
import weakref

from . import runtime
from .api import host_class, jmethod
from .jlang import Object


@host_class("java.lang.ref.ReferenceQueue")
class ReferenceQueue(Object):
    def __init__(self):
        self._items = collections.deque()
        self._cond = threading.Condition()

    @jmethod("<init>", "()V")
    def _init(self):
        ReferenceQueue.__init__(self)

    def _put(self, reference):
        with self._cond:
            if reference._queued:
                return False
            reference._queued = True
            self._items.append(reference)
            self._cond.notify()
            return True

    @jmethod("poll", "()Ljava/lang/ref/Reference;")
    def poll(self):
        with self._cond:
            return self._items.popleft() if self._items else None

    @jmethod("remove", "()Ljava/lang/ref/Reference;")
    @jmethod("remove", "(J)Ljava/lang/ref/Reference;")
    def remove(self, timeout=0):
        if timeout < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "Negative timeout value")
        with self._cond:
            if not self._items:
                self._cond.wait(timeout / 1000.0 if timeout else None)
            return self._items.popleft() if self._items else None


@host_class("java.lang.ref.Reference")
class Reference(Object):
    _strong = None
    _weak = None
    _queue = None
    _queued = False

    def __init__(self, referent=None, queue=None):
        self._queue = queue
        self._queued = False
        self._strong = None
        self._weak = None
        if referent is None:
            return
        if self._holds_strongly():
            self._strong = referent
            return
        try:
            self._weak = weakref.ref(referent, self._collected if queue is not None else None)
        except TypeError:
            self._strong = referent

    def _holds_strongly(self):
        return False

    def _collected(self, _ref):
        if self._queue is not None:
            self._queue._put(self)

    @jmethod("get", "()Ljava/lang/Object;")
    def get(self):
        if self._weak is not None:
            return self._weak()
        return self._strong

    @jmethod("clear", "()V")
    def clear(self):
        self._weak = None
        self._strong = None

    @jmethod("refersTo", "(Ljava/lang/Object;)Z")
    def refersTo(self, target):
        return 1 if self.get() is target else 0

    @jmethod("enqueue", "()Z")
    def enqueue(self):
        self.clear()
        return 1 if self._queue is not None and self._queue._put(self) else 0

    @jmethod("isEnqueued", "()Z")
    def isEnqueued(self):
        return 1 if self._queued else 0


@host_class("java.lang.ref.WeakReference")
class WeakReference(Reference):
    @jmethod("<init>", "(Ljava/lang/Object;)V")
    def _init(self, referent):
        Reference.__init__(self, referent)

    @jmethod("<init>", "(Ljava/lang/Object;Ljava/lang/ref/ReferenceQueue;)V")
    def _init_queue(self, referent, queue):
        Reference.__init__(self, referent, queue)


@host_class("java.lang.ref.SoftReference")
class SoftReference(Reference):
    @jmethod("<init>", "(Ljava/lang/Object;)V")
    def _init(self, referent):
        Reference.__init__(self, referent)

    @jmethod("<init>", "(Ljava/lang/Object;Ljava/lang/ref/ReferenceQueue;)V")
    def _init_queue(self, referent, queue):
        Reference.__init__(self, referent, queue)


@host_class("java.lang.ref.PhantomReference")
class PhantomReference(Reference):
    @jmethod("<init>", "(Ljava/lang/Object;Ljava/lang/ref/ReferenceQueue;)V")
    def _init(self, referent, queue):
        Reference.__init__(self, referent, queue)

    @jmethod("get", "()Ljava/lang/Object;")
    def get(self):
        return None
