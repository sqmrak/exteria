"""what a call into the vm may spend: time, loop steps and array elements

translated code calls tick() at the entry of every method that makes a call and before every backward jump, so a loop
or a runaway recursion reaches a check. a budget is set for the thread that calls into the vm; threads the program
starts share the budget of the thread that started them; one of them that runs out ends alone, and the call that owns
the budget raises its BudgetExceeded when it returns. tick() costs one global read while no budget is active

an exhausted budget raises BudgetExceeded, a BaseException: a catch (Throwable) of the program cannot swallow it, and
it ends the whole call into the vm with the state the program had at that point. this bounds a program that loops; it
is not a sandbox: a call blocked in c or in a lock never reaches a tick, and the process still has the rights of the app

the elements limit counts the elements of the arrays a program allocates while the budget runs; MAX_ARRAY_LENGTH caps a
single array whether a budget runs or not, as an OutOfMemoryError the program can catch"""

import contextlib
import threading
import time

MAX_ARRAY_LENGTH = 1 << 26


class BudgetExceeded(BaseException):
    """a call into the vm used up its time, its steps or its array elements"""


class Budget:
    __slots__ = ("deadline", "steps", "elements", "limits", "failure")

    def __init__(self, seconds=None, steps=None, elements=None):
        self.failure = None
        self.limits = (seconds, steps, elements)
        self.deadline = None if seconds is None else time.monotonic() + seconds
        self.steps = steps
        self.elements = elements

    def narrowed(self, seconds, steps, elements):
        """a budget that is never wider than this one, for a call nested in a call that already has a budget"""
        inner = Budget(seconds, steps, elements)
        if self.deadline is not None and (inner.deadline is None or self.deadline < inner.deadline):
            inner.deadline = self.deadline
        return inner


_local = threading.local()
_lock = threading.Lock()
_active = 0
_defaults = None


def _enter(budget):
    global _active
    with _lock:
        _active += 1
    previous = getattr(_local, "budget", None)
    _local.budget = budget
    return previous


def _leave(previous):
    global _active
    _local.budget = previous
    with _lock:
        _active -= 1


def tick():
    if _active:
        _check()


def native_tick(jumps):
    """called by the native machine between two runs of a loop with the number of jumps back it took"""
    if _active:
        _check(jumps)


def _check(weight=1):
    budget = getattr(_local, "budget", None)
    if budget is None:
        return
    if budget.steps is not None:
        budget.steps -= weight
        if budget.steps < 0:
            raise BudgetExceeded("step limit of %d reached" % budget.limits[1])
    if budget.deadline is not None and time.monotonic() > budget.deadline:
        raise BudgetExceeded("time limit of %g s reached" % budget.limits[0])


def charge_elements(count):
    """called by an array allocation"""
    if _active:
        budget = getattr(_local, "budget", None)
        if budget is not None and budget.elements is not None:
            budget.elements -= count
            if budget.elements < 0:
                raise BudgetExceeded("array element limit of %d reached" % budget.limits[2])


@contextlib.contextmanager
def budget(seconds=None, steps=None, elements=None):
    """run a call into the vm under a budget; inside a call that has one the inner can only be narrower"""
    outer = getattr(_local, "budget", None)
    mine = Budget(seconds, steps, elements) if outer is None else outer.narrowed(seconds, steps, elements)
    previous = _enter(mine)
    try:
        yield mine
    finally:
        _leave(previous)
    # a thread of the program that ran out of budget ended alone: the call that owns the budget reports it
    if mine.failure is not None:
        raise mine.failure


def configure(seconds=None, steps=None, elements=None):
    """the budget every call from python into the vm gets when its caller has not set one; no arguments removes it"""
    global _defaults
    _defaults = None if seconds is None and steps is None and elements is None else (seconds, steps, elements)


def defaults():
    return _defaults


def entry():
    """the context of a call from python into the vm: the default budget when the thread has none running"""
    if _defaults is None or getattr(_local, "budget", None) is not None:
        return contextlib.nullcontext()
    return budget(*_defaults)


def current():
    """the budget of this thread, for a thread the program starts"""
    return getattr(_local, "budget", None)


@contextlib.contextmanager
def adopt(shared):
    """run on this thread under the budget of the thread that started it"""
    if shared is None:
        yield
        return
    previous = _enter(shared)
    try:
        yield
    finally:
        _leave(previous)
