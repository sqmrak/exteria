"""android.view.animation: the interpolators map to curves of the app"""


class _Interpolator:
    curve = "decel"

    def __init__(self, *_args):
        pass


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
