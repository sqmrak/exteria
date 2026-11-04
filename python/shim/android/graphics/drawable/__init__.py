"""android.graphics.drawable: shapes and flat colors, the two backgrounds the app can draw"""

from java.lang import Object


def _argb(color):
    return int(color) & 0xFFFFFFFF


class Drawable(Object):
    def __init__(self):
        self._owners = []

    def _changed(self):
        for view in list(self._owners):
            view._bg_changed()

    def mutate(self):
        """a drawable of the shim belongs to the one view that sets it, so it is its own copy already"""
        return self


class ColorDrawable(Drawable):
    def __init__(self, color=0):
        super().__init__()
        self._color = _argb(color)

    def setColor(self, color):
        self._color = _argb(color)
        self._changed()

    def _encode(self):
        return {"type": "color", "color": self._color}


class GradientDrawable(Drawable):
    RECTANGLE = 0
    OVAL = 1

    def __init__(self, *_args):
        super().__init__()
        self._shape = GradientDrawable.RECTANGLE
        self._color = 0
        self._radius = 0.0
        self._stroke = (0, 0)

    def setShape(self, shape):
        self._shape = int(shape)
        self._changed()

    def setColor(self, color):
        self._color = _argb(color)
        self._changed()

    def setCornerRadius(self, radius):
        self._radius = float(radius)
        self._changed()

    def setStroke(self, width, color, *_dash):
        self._stroke = (int(width), _argb(color))
        self._changed()

    def _encode(self):
        return {"type": "shape", "oval": self._shape == GradientDrawable.OVAL, "color": self._color,
                "radius": self._radius, "stroke": self._stroke[0], "stroke_color": self._stroke[1]}


class BitmapDrawable(Drawable):
    """a bitmap as the background of a view; the app puts the pixels on the layer of the view. a color filter is applied to
    the pixels here: SRC_IN, SRC_ATOP, SRC_OVER, SRC, MULTIPLY, DARKEN, LIGHTEN and SCREEN"""

    def __init__(self, *args):
        super().__init__()
        bitmap = args[-1] if args else None
        if bitmap is None or not hasattr(bitmap, "_pixels"):
            raise ValueError("a BitmapDrawable needs a bitmap")
        self._bitmap = bitmap
        self._filter = None

    def getBitmap(self):
        return self._bitmap

    def setColorFilter(self, *args):
        """a ColorFilter, or a color and a PorterDuff.Mode; None clears it"""
        from android.graphics import ColorFilter, PorterDuffColorFilter
        if len(args) == 2:
            self._filter = PorterDuffColorFilter(args[0], args[1])
        elif args[0] is None or isinstance(args[0], ColorFilter):
            self._filter = args[0]
        else:
            raise TypeError("not a color filter: %r" % (args[0],))
        self._changed()

    def clearColorFilter(self):
        self._filter = None
        self._changed()

    def _encode(self):
        return {"type": "color", "color": 0}

    def _rendered(self):
        if self._filter is None:
            return self._bitmap
        from android.graphics import Bitmap, tint_pixels
        out = Bitmap(self._bitmap.getWidth(), self._bitmap.getHeight())
        out._pixels[:] = tint_pixels(self._bitmap._pixels, self._filter._color, self._filter._mode)
        return out
