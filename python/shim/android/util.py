"""android.util"""


class TypedValue:
    COMPLEX_UNIT_PX = 0
    COMPLEX_UNIT_DIP = 1
    COMPLEX_UNIT_SP = 2

    @staticmethod
    def applyDimension(unit, value, metrics=None):
        # one dp is one point on ios, one sp the same
        return float(value)


class DisplayMetrics:
    density = 1.0
    scaledDensity = 1.0
