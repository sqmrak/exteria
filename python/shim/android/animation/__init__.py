"""android.animation: value animators driven by a timer of the app, one frame about every 16 ms on the main thread.
an ObjectAnimator calls the setter of the property on its target each frame, so it works on any view of the shim"""

import time

from java.lang import Object

_clock = time.monotonic
FRAME_MS = 16

_CURVES = {
    "linear": lambda t: t,
    "accel": lambda t: t * t,
    "decel": lambda t: 1.0 - (1.0 - t) * (1.0 - t),
    "ease": lambda t: t * t * (3.0 - 2.0 * t),
    "overshoot": lambda t: ((t - 1.0) ** 3) * 3.0 + ((t - 1.0) ** 2) * 2.0 + 1.0,
}


class TimeInterpolator:
    """a program implements getInterpolation(input)"""


def _notify(listeners, name, *args):
    for listener in list(listeners):
        method = getattr(listener, name, None)
        if method is not None:
            method(*args)


class Animator(Object):
    class AnimatorListener:
        """a plugin class implements onAnimationStart, onAnimationEnd, onAnimationCancel and onAnimationRepeat"""

    def __init__(self):
        self._duration = 300
        self._delay = 0
        self._curve = _CURVES["ease"]
        self._listeners = []
        self._running = False
        self._generation = 0

    def setDuration(self, ms):
        if ms < 0:
            raise ValueError("duration must be >= 0")
        self._duration = int(ms)
        return self

    def getDuration(self):
        return self._duration

    def setStartDelay(self, ms):
        self._delay = int(ms)

    def getStartDelay(self):
        return self._delay

    def setInterpolator(self, interpolator):
        self._curve = _CURVES.get(getattr(interpolator, "curve", "ease"), _CURVES["ease"])

    def addListener(self, listener):
        self._listeners.append(listener)

    def removeListener(self, listener):
        if listener in self._listeners:
            self._listeners.remove(listener)

    def isRunning(self):
        return self._running

    def isStarted(self):
        return self._running


class AnimatorListenerAdapter(Animator.AnimatorListener):
    def onAnimationStart(self, animation, *_reverse):
        pass

    def onAnimationEnd(self, animation, *_reverse):
        pass

    def onAnimationCancel(self, animation):
        pass

    def onAnimationRepeat(self, animation):
        pass


class ValueAnimator(Animator):
    INFINITE = -1
    RESTART = 1
    REVERSE = 2

    class AnimatorUpdateListener:
        """a plugin class implements onAnimationUpdate(animator)"""

    def __init__(self):
        super().__init__()
        self._values = (0.0, 1.0)
        self._integer = False
        self._update_listeners = []
        self._repeat_count = 0
        self._repeat_mode = ValueAnimator.RESTART
        self._fraction = 0.0
        self._value = 0.0
        self._started_at = 0.0
        self._cycle = 0

    @staticmethod
    def ofFloat(*values):
        animator = ValueAnimator()
        animator._set_values(values, False)
        return animator

    @staticmethod
    def ofInt(*values):
        animator = ValueAnimator()
        animator._set_values(values, True)
        return animator

    def _set_values(self, values, integer):
        if len(values) == 1:
            values = (0, values[0])
        if not values:
            raise ValueError("an animator needs at least one value")
        self._values = tuple(values)
        self._integer = integer
        self._value = self._values[0]

    def addUpdateListener(self, listener):
        self._update_listeners.append(listener)

    def removeUpdateListener(self, listener):
        if listener in self._update_listeners:
            self._update_listeners.remove(listener)

    def setRepeatCount(self, count):
        self._repeat_count = int(count)

    def setRepeatMode(self, mode):
        self._repeat_mode = int(mode)

    def getAnimatedValue(self):
        return self._value

    def getAnimatedFraction(self):
        return self._fraction

    def _value_at(self, fraction):
        segments = len(self._values) - 1
        if segments == 0:
            return self._values[0]
        position = min(fraction * segments, segments)
        index = min(int(position), segments - 1)
        local = position - index
        low, high = self._values[index], self._values[index + 1]
        value = low + (high - low) * local
        return int(round(value)) if self._integer else float(value)

    def _apply(self, fraction):
        self._fraction = fraction
        self._value = self._value_at(self._curve(fraction))
        self._on_value(self._value)
        _notify(self._update_listeners, "onAnimationUpdate", self)

    def _on_value(self, value):
        pass

    def start(self):
        if self._running:
            return
        self._running = True
        self._generation += 1
        self._cycle = 0
        generation = self._generation
        _notify(self._listeners, "onAnimationStart", self)
        self._schedule(generation, self._delay, first=True)

    def _schedule(self, generation, delay, first=False):
        from android.os import Handler
        Handler().postDelayed(lambda: self._frame(generation, first), delay)

    def _frame(self, generation, first):
        if generation != self._generation or not self._running:
            return
        now = _clock()
        if first:
            self._started_at = now
        elapsed_ms = (now - self._started_at) * 1000.0
        fraction = 1.0 if self._duration == 0 else min(elapsed_ms / self._duration, 1.0)
        shown = 1.0 - fraction if self._cycle % 2 == 1 and self._repeat_mode == ValueAnimator.REVERSE else fraction
        self._apply(shown)
        if fraction < 1.0:
            self._schedule(generation, FRAME_MS)
            return
        if self._repeat_count == ValueAnimator.INFINITE or self._cycle < self._repeat_count:
            self._cycle += 1
            self._started_at = now
            _notify(self._listeners, "onAnimationRepeat", self)
            self._schedule(generation, FRAME_MS)
            return
        self._finish()

    def _finish(self):
        self._running = False
        _notify(self._listeners, "onAnimationEnd", self)

    def cancel(self):
        if not self._running:
            return
        self._running = False
        self._generation += 1
        _notify(self._listeners, "onAnimationCancel", self)
        _notify(self._listeners, "onAnimationEnd", self)

    def end(self):
        """jumps to the last value and finishes"""
        if not self._running:
            return
        self._generation += 1
        last = 0.0 if self._cycle % 2 == 1 and self._repeat_mode == ValueAnimator.REVERSE else 1.0
        self._apply(last)
        self._finish()


class ObjectAnimator(ValueAnimator):
    def __init__(self, target=None, prop=None):
        super().__init__()
        self._target = target
        self._property = prop

    @staticmethod
    def _make(target, prop, values, integer):
        animator = ObjectAnimator(target, prop)
        animator._setter_name()
        animator._set_values(values, integer)
        return animator

    @staticmethod
    def ofFloat(target, prop, *values):
        return ObjectAnimator._make(target, prop, values, False)

    @staticmethod
    def ofInt(target, prop, *values):
        return ObjectAnimator._make(target, prop, values, True)

    def _setter_name(self):
        name = str(self._property)
        setter = "set" + name[:1].upper() + name[1:]
        if not callable(getattr(self._target, setter, None)):
            raise AttributeError("%s has no %s for the property %s" % (type(self._target).__name__, setter, name))
        return setter

    def getTarget(self):
        return self._target

    def _on_value(self, value):
        getattr(self._target, self._setter_name())(value)


class AnimatorSet(Animator):
    class Builder:
        def __init__(self, owner, animator):
            self._owner = owner
            self._animator = animator

        def with_(self, other):
            self._owner._order.append((other, self._animator, "with"))
            return self

        def before(self, other):
            self._owner._order.append((other, self._animator, "after"))
            return self

        def after(self, other):
            self._owner._order.append((self._animator, other, "after"))
            return self

    def __init__(self):
        super().__init__()
        self._steps = []
        self._order = []
        self._pending = 0
        self._active = []
        self._queue = []

    def playTogether(self, *animators):
        self._steps.append(list(animators[0] if len(animators) == 1 and not isinstance(animators[0], Animator) else animators))

    def playSequentially(self, *animators):
        for animator in (animators[0] if len(animators) == 1 and not isinstance(animators[0], Animator) else animators):
            self._steps.append([animator])

    def play(self, animator):
        self._order.append((animator, None, "play"))
        return AnimatorSet.Builder(self, animator)

    def _plan(self):
        """the steps of a Builder chain: an animator waits for the ones it must follow"""
        if not self._order:
            return list(self._steps)
        steps = list(self._steps)
        known = []
        for first, second, kind in self._order:
            for animator in (first, second):
                if animator is not None and animator not in known:
                    known.append(animator)
        depth = {id(a): 0 for a in known}
        for _ in known:
            for first, second, kind in self._order:
                if kind == "after":
                    depth[id(second)] = max(depth[id(second)], depth[id(first)] + 1)
                elif kind == "with" and second is not None:
                    depth[id(first)] = depth[id(second)] = max(depth[id(first)], depth[id(second)])
        for level in sorted(set(depth.values())):
            steps.append([a for a in known if depth[id(a)] == level])
        return steps

    def start(self):
        if self._running:
            return
        self._running = True
        self._generation += 1
        self._queue = self._plan()
        _notify(self._listeners, "onAnimationStart", self)
        self._next(self._generation)

    def _next(self, generation):
        if generation != self._generation or not self._running:
            return
        if not self._queue:
            self._running = False
            _notify(self._listeners, "onAnimationEnd", self)
            return
        step = self._queue.pop(0)
        self._pending = len(step)
        self._active = list(step)
        if not step:
            self._next(generation)
            return
        for animator in step:
            if self._duration_override is not None:
                animator.setDuration(self._duration_override)
            animator.addListener(_StepEnd(self, generation, animator))
            animator.start()

    _duration_override = None

    def setDuration(self, ms):
        self._duration_override = int(ms)
        return self

    def _step_ended(self, generation):
        if generation != self._generation:
            return
        self._pending -= 1
        if self._pending == 0:
            self._next(generation)

    def cancel(self):
        if not self._running:
            return
        self._running = False
        self._generation += 1
        for animator in self._active:
            animator.cancel()
        _notify(self._listeners, "onAnimationCancel", self)
        _notify(self._listeners, "onAnimationEnd", self)


class _StepEnd(AnimatorListenerAdapter):
    def __init__(self, owner, generation, animator):
        self._owner = owner
        self._generation = generation
        self._animator = animator

    def onAnimationEnd(self, animation, *_reverse):
        animation.removeListener(self)
        self._owner._step_ended(self._generation)


setattr(AnimatorSet.Builder, "with", AnimatorSet.Builder.with_)
