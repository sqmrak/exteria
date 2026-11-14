"""android.view.animation: the interpolators map to curves of the app"""


class Interpolator:
    """a program implements getInterpolation(input) and returns the eased fraction"""


class _Interpolator:
    curve = "decel"

    def __init__(self, *_args):
        pass

    def getInterpolation(self, fraction):
        from android.animation import _CURVES
        return _CURVES[self.curve](fraction)


class LinearInterpolator(_Interpolator):
    curve = "linear"


class AccelerateInterpolator(_Interpolator):
    curve = "accel"


class DecelerateInterpolator(_Interpolator):
    curve = "decel"


class AccelerateDecelerateInterpolator(_Interpolator):
    curve = "ease"


class OvershootInterpolator(_Interpolator):
    curve = "overshoot"


class Animation:
    """the animations of the old view framework, played through the property animator of the app: a translation moves the layer, and
    when the animation ends the layer goes back unless setFillAfter(True). INFINITE repeats until cancel() or until the view leaves the
    window"""

    ABSOLUTE = 0
    RELATIVE_TO_SELF = 1
    RELATIVE_TO_PARENT = 2
    INFINITE = -1
    RESTART = 1
    REVERSE = 2

    class AnimationListener:
        """a program implements onAnimationStart(animation), onAnimationEnd(animation) and onAnimationRepeat(animation)"""

    def __init__(self, *_args):
        self._duration = 0
        self._offset = 0
        self._interpolator = None
        self._fill_after = False
        self._repeat_count = 0
        self._repeat_mode = Animation.RESTART
        self._listener = None
        self._cancelled = True
        self._token = 0

    def setDuration(self, ms):
        self._duration = max(0, int(ms))

    def getDuration(self):
        return self._duration

    def setStartOffset(self, ms):
        self._offset = max(0, int(ms))

    def getStartOffset(self):
        return self._offset

    def setInterpolator(self, interpolator):
        self._interpolator = interpolator

    def getInterpolator(self):
        return self._interpolator

    def setFillAfter(self, value):
        self._fill_after = bool(value)

    def getFillAfter(self):
        return self._fill_after

    def setFillBefore(self, value):
        # the layer is placed at the first frame when the animation starts, as a program that sets it expects
        return None

    def setRepeatCount(self, count):
        self._repeat_count = int(count)

    def getRepeatCount(self):
        return self._repeat_count

    def setRepeatMode(self, mode):
        self._repeat_mode = int(mode)

    def getRepeatMode(self):
        return self._repeat_mode

    def setAnimationListener(self, listener):
        self._listener = listener

    def hasStarted(self):
        return not self._cancelled

    def cancel(self):
        self._cancelled = True

    def reset(self):
        self._cancelled = True

    def _tell(self, name):
        method = getattr(self._listener, name, None) if self._listener is not None else None
        if method is not None:
            method(self)

    def _later(self, delay, step):
        from android.os import Handler
        Handler().postDelayed(_Step(step), max(0, int(delay)))

    def _alive(self, view, token):
        return not self._cancelled and token == self._token and view._attached

    def _span(self):
        """the time from the start to the last frame, an infinite animation has none"""
        if self._repeat_count < 0:
            return None
        return self._offset + self._duration * (self._repeat_count + 1)

    def _play(self, view, delay, interpolator=None):
        raise NotImplementedError("%s has no frames to play" % type(self).__name__)

    def start(self, view):
        self._cancelled = False
        self._token += 1
        self._play(view, 0)


class _Step:
    def __init__(self, step):
        self._step = step

    def run(self):
        self._step()


class TranslateAnimation(Animation):
    """TranslateAnimation(fromX, toX, fromY, toY) in pixels, or the eight argument form with a type before each value"""

    def __init__(self, *args):
        super().__init__()
        if len(args) == 4:
            values = args
            kinds = (Animation.ABSOLUTE,) * 4
        elif len(args) == 8:
            kinds, values = (args[0], args[2], args[4], args[6]), (args[1], args[3], args[5], args[7])
        else:
            raise TypeError("TranslateAnimation takes 4 or 8 arguments, got %d" % len(args))
        self._kinds = tuple(int(k) for k in kinds)
        self._values = tuple(float(v) for v in values)

    def _resolve(self, view, index):
        kind, value = self._kinds[index], self._values[index]
        if kind == Animation.ABSOLUTE:
            return value
        horizontal = index < 2
        if kind == Animation.RELATIVE_TO_SELF:
            return value * (view.getWidth() if horizontal else view.getHeight())
        parent = view.getParent()
        size = (parent.getWidth() if horizontal else parent.getHeight()) if parent is not None else 0
        return value * size

    def _play(self, view, delay, interpolator=None):
        interpolator = self._interpolator or interpolator
        base = (view._tx, view._ty)
        from_x, to_x = self._resolve(view, 0), self._resolve(view, 1)
        from_y, to_y = self._resolve(view, 2), self._resolve(view, 3)
        token, duration = self._token, self._duration
        plays = self._repeat_count + 1 if self._repeat_count >= 0 else None

        def run(n):
            if not self._alive(view, token):
                return
            backwards = self._repeat_mode == Animation.REVERSE and n % 2 == 1
            start, end = ((to_x, to_y), (from_x, from_y)) if backwards else ((from_x, from_y), (to_x, to_y))
            if n == 0:
                self._tell("onAnimationStart")
            else:
                self._tell("onAnimationRepeat")
            view._tx, view._ty = base[0] + start[0], base[1] + start[1]
            view._push(tx=view._tx, ty=view._ty)
            mover = view.animate().translationX(base[0] + end[0]).translationY(base[1] + end[1]).setDuration(duration)
            if interpolator is not None:
                mover.setInterpolator(interpolator)
            mover.start()
            self._later(duration, lambda: finish(n))

        def finish(n):
            if not self._alive(view, token):
                return
            if plays is None or n + 1 < plays:
                run(n + 1)
                return
            if not self._fill_after:
                view._tx, view._ty = base
                view._push(tx=view._tx, ty=view._ty)
            self._cancelled = True
            self._tell("onAnimationEnd")

        self._later(delay + self._offset, lambda: run(0))


class AnimationSet(Animation):
    """children that play together, each after its own start offset. a set made with shareInterpolator True hands its interpolator to the
    children that have none"""

    def __init__(self, share_interpolator=True):
        super().__init__()
        self._share = bool(share_interpolator)
        self._children = []

    def addAnimation(self, animation):
        self._children.append(animation)

    def getAnimations(self):
        return list(self._children)

    def setDuration(self, ms):
        super().setDuration(ms)
        for child in self._children:
            child.setDuration(ms)

    def setFillAfter(self, value):
        super().setFillAfter(value)
        for child in self._children:
            child.setFillAfter(value)

    def getDuration(self):
        spans = [child._offset + child._duration * (max(child._repeat_count, 0) + 1) for child in self._children]
        return max(spans) if spans else 0

    def cancel(self):
        super().cancel()
        for child in self._children:
            child.cancel()

    def _play(self, view, delay, interpolator=None):
        token = self._token
        shared = self._interpolator if self._share else None
        ends = []
        for child in self._children:
            child._cancelled = False
            child._token += 1
            child._play(view, delay + self._offset, shared)
            ends.append(child._span())
        self._tell_later(view, token, delay + self._offset, ends)

    def _tell_later(self, view, token, delay, ends):
        """onAnimationStart when the set begins and onAnimationEnd after its longest child, when every child is finite"""
        self._later(delay, lambda: self._alive(view, token) and self._tell("onAnimationStart"))
        if all(end is not None for end in ends):
            def done():
                if self._alive(view, token):
                    self._cancelled = True
                    self._tell("onAnimationEnd")
            self._later(delay + max(ends, default=0), done)
