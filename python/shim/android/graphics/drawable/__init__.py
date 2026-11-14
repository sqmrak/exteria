"""android.graphics.drawable: shapes and flat colors, the two backgrounds the app can draw"""

from java.lang import Object


def _argb(color):
    return int(color) & 0xFFFFFFFF


class Drawable(Object):
    """what a drawable knows of itself: bounds, alpha, tint and a draw that paints into a canvas. a view the drawable is the
    background of shows it through the app (_encode); draw() is for a program that paints it itself, and a subclass of a
    program overrides draw()"""

    class Callback:
        """a program implements invalidateDrawable(who), scheduleDrawable(who, what, when) and unscheduleDrawable(who, what)"""

    class ConstantState(Object):
        def __init__(self, drawable):
            self._drawable = drawable

        def newDrawable(self, *args):
            import copy
            return copy.copy(self._drawable)

    def __init__(self):
        self._owners = []
        self._bounds = (0, 0, 0, 0)
        self._alpha = 255
        self._tint = None
        self._tint_mode = "SRC_IN"
        self._color_filter = None
        self._callback = None
        self._visible = True

    def _changed(self):
        for view in list(self._owners):
            view._bg_changed()
        callback = getattr(self, "_callback", None)
        if callback is not None:
            callback.invalidateDrawable(self)

    def setBounds(self, left, top=None, right=None, bottom=None):
        if top is None:
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self._bounds = (int(left), int(top), int(right), int(bottom))

    def getBounds(self):
        from android.graphics import Rect
        return Rect(*self._bounds)

    def copyBounds(self, rect=None):
        from android.graphics import Rect
        if rect is None:
            return Rect(*self._bounds)
        rect.set(*self._bounds)

    def setAlpha(self, alpha):
        self._alpha = max(0, min(255, int(alpha)))
        self._changed()

    def getAlpha(self):
        return self._alpha

    def setTint(self, color):
        self._tint = int(color) & 0xFFFFFFFF
        self._changed()

    def setTintMode(self, mode):
        self._tint_mode = mode

    def setColorFilter(self, first, mode=None):
        from android.graphics import ColorFilter, PorterDuffColorFilter
        self._color_filter = PorterDuffColorFilter(first, mode) if mode is not None else first
        if self._color_filter is not None and not isinstance(self._color_filter, ColorFilter):
            raise TypeError("not a color filter: %r" % (self._color_filter,))
        self._changed()

    def getColorFilter(self):
        return self._color_filter

    def clearColorFilter(self):
        self._color_filter = None
        self._changed()

    def setCallback(self, callback):
        self._callback = callback

    def getCallback(self):
        return self._callback

    def invalidateSelf(self):
        self._changed()

    def setVisible(self, visible, restart=False):
        changed = self._visible != bool(visible)
        self._visible = bool(visible)
        return changed

    def isVisible(self):
        return self._visible

    def getIntrinsicWidth(self):
        return -1

    def getIntrinsicHeight(self):
        return -1

    def getMinimumWidth(self):
        return max(self.getIntrinsicWidth(), 0)

    def getMinimumHeight(self):
        return max(self.getIntrinsicHeight(), 0)

    def getOpacity(self):
        return -3

    def getConstantState(self):
        return Drawable.ConstantState(self)

    def _paint_for(self, color):
        """a Paint of the color with the alpha, tint and color filter of the drawable applied"""
        from android.graphics import Paint
        paint = Paint()
        paint.setColor(color)
        paint.setAlpha(((color >> 24) & 255) * self._alpha // 255)
        if self._color_filter is not None:
            paint.setColorFilter(self._color_filter)
        elif self._tint is not None:
            from android.graphics import PorterDuffColorFilter
            paint.setColorFilter(PorterDuffColorFilter(self._tint, self._tint_mode))
        return paint

    def draw(self, canvas):
        raise NotImplementedError("a drawable draws itself in its own class")

    def mutate(self):
        """a drawable of the shim belongs to the one view that sets it, so it is its own copy already"""
        return self


class SymbolDrawable(Drawable):
    """an icon the app draws itself, named by the symbol it has for it (Resources.getDrawable). only a native control that takes a symbol,
    such as a tab of the bar, can show it; a canvas has no way to draw it"""

    def __init__(self, symbol):
        super().__init__()
        self._symbol = symbol


class ColorDrawable(Drawable):
    def __init__(self, color=0):
        super().__init__()
        self._color = _argb(color)

    def setColor(self, color):
        self._color = _argb(color)
        self._changed()

    def _encode(self):
        return {"type": "color", "color": self._color}

    def getColor(self):
        return self._color

    def getOpacity(self):
        alpha = self._color >> 24
        return -1 if alpha == 255 else (-2 if alpha == 0 else -3)

    def draw(self, canvas):
        if (self._color >> 24) and self._visible:
            left, top, right, bottom = self._bounds
            canvas.drawRect(left, top, right, bottom, self._paint_for(self._color))


class GradientDrawable(Drawable):
    RECTANGLE = 0
    OVAL = 1

    def __init__(self, orientation=None, colors=None, *_args):
        super().__init__()
        if orientation is not None:
            self._orientation = orientation
        if colors is not None:
            self._colors = [_argb(c) for c in colors]
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

    _radii = None
    _colors = None
    _size = (-1, -1)
    _orientation = "TOP_BOTTOM"

    class Orientation:
        TOP_BOTTOM = "TOP_BOTTOM"
        TR_BL = "TR_BL"
        RIGHT_LEFT = "RIGHT_LEFT"
        BR_TL = "BR_TL"
        BOTTOM_TOP = "BOTTOM_TOP"
        BL_TR = "BL_TR"
        LEFT_RIGHT = "LEFT_RIGHT"
        TL_BR = "TL_BR"

    LINEAR_GRADIENT = 0
    RADIAL_GRADIENT = 1
    SWEEP_GRADIENT = 2
    LINE = 2
    RING = 3

    def setColors(self, colors):
        self._colors = [_argb(c) for c in colors] if colors is not None else None
        self._changed()

    def setOrientation(self, orientation):
        self._orientation = orientation
        self._changed()

    def setCornerRadii(self, radii):
        self._radii = [float(r) for r in radii[:8]] if radii is not None else None
        self._changed()

    def getCornerRadius(self):
        return self._radius

    def setSize(self, width, height):
        self._size = (int(width), int(height))

    def getIntrinsicWidth(self):
        return self._size[0]

    def getIntrinsicHeight(self):
        return self._size[1]

    def setGradientType(self, kind):
        self._gradient_type = kind

    def _encode(self):
        return {"type": "shape", "oval": self._shape == GradientDrawable.OVAL, "color": self._color,
                "radius": self._radius, "stroke": self._stroke[0], "stroke_color": self._stroke[1]}

    def draw(self, canvas):
        from android.graphics import LinearGradient, Path, Paint, RectF, Shader
        if not self._visible:
            return
        left, top, right, bottom = self._bounds
        rect = RectF(left, top, right, bottom)
        path = Path()
        if self._shape == GradientDrawable.OVAL:
            path.addOval(rect, Path.Direction.CW)
        elif self._radii is not None:
            path.addRoundRect(rect, self._radii, Path.Direction.CW)
        elif self._radius > 0:
            path.addRoundRect(rect, self._radius, self._radius, Path.Direction.CW)
        else:
            path.addRect(rect, Path.Direction.CW)
        fill = self._paint_for(self._color)
        if self._colors:
            vectors = {"TOP_BOTTOM": (0, 0, 0, 1), "BOTTOM_TOP": (0, 1, 0, 0), "LEFT_RIGHT": (0, 0, 1, 0),
                       "RIGHT_LEFT": (1, 0, 0, 0), "TL_BR": (0, 0, 1, 1), "BR_TL": (1, 1, 0, 0), "TR_BL": (1, 0, 0, 1),
                       "BL_TR": (0, 1, 1, 0)}[self._orientation]
            x0, y0 = left + vectors[0] * (right - left), top + vectors[1] * (bottom - top)
            x1, y1 = left + vectors[2] * (right - left), top + vectors[3] * (bottom - top)
            fill.setShader(LinearGradient(x0, y0, x1, y1, self._colors if len(self._colors) > 1 else self._colors * 2,
                                          None, Shader.TileMode.CLAMP))
            fill.setAlpha(self._alpha)
        if self._colors or (self._color >> 24):
            canvas.drawPath(path, fill)
        if self._stroke[0] > 0:
            line = self._paint_for(self._stroke[1])
            line.setStyle(Paint.Style.STROKE)
            line.setStrokeWidth(self._stroke[0])
            canvas.drawPath(path, line)


class PaintDrawable(GradientDrawable):
    """a rectangle of one color, with the corner radius a plugin sets; the drawable of a cursor or a thin bar"""

    def __init__(self, color=0):
        super().__init__()
        self.setColor(color)
        self._width = -1
        self._height = -1

    def setIntrinsicWidth(self, width):
        self._width = int(width)

    def setIntrinsicHeight(self, height):
        self._height = int(height)

    def getIntrinsicWidth(self):
        return self._width

    def getIntrinsicHeight(self):
        return self._height


class LayerDrawable(Drawable):
    """drawables painted one over the next, each inside its own inset. as the background of a view the layers are painted into a bitmap
    the size of the view and the app shows the pixels; a layer that changes repaints it"""

    _sized = True

    def __init__(self, layers):
        super().__init__()
        self._layers = []
        self._ids = []
        self._insets = []
        for layer in list(layers):
            self._add(layer)

    def _add(self, layer, layer_id=-1):
        if layer is None or not hasattr(layer, "draw"):
            raise ValueError("a layer is a Drawable")
        self._layers.append(layer)
        self._ids.append(int(layer_id))
        self._insets.append((0, 0, 0, 0))
        layer._callback = self

    def invalidateDrawable(self, who):
        self._changed()

    def getNumberOfLayers(self):
        return len(self._layers)

    def getDrawable(self, index):
        return self._layers[index]

    def setDrawable(self, index, drawable):
        self._layers[index] = drawable
        drawable._callback = self
        self._changed()

    def setId(self, index, layer_id):
        self._ids[index] = int(layer_id)

    def getId(self, index):
        return self._ids[index]

    def findDrawableByLayerId(self, layer_id):
        layer_id = int(layer_id)
        for found, drawable in zip(self._ids, self._layers):
            if found == layer_id:
                return drawable
        return None

    def findIndexByLayerId(self, layer_id):
        layer_id = int(layer_id)
        return self._ids.index(layer_id) if layer_id in self._ids else -1

    def addLayer(self, drawable):
        self._add(drawable)
        self._changed()
        return len(self._layers) - 1

    def setLayerInset(self, index, left, top, right, bottom):
        self._insets[index] = (int(left), int(top), int(right), int(bottom))
        self._changed()

    def getIntrinsicWidth(self):
        widths = [d.getIntrinsicWidth() + i[0] + i[2] for d, i in zip(self._layers, self._insets) if d.getIntrinsicWidth() >= 0]
        return max(widths) if widths else -1

    def getIntrinsicHeight(self):
        heights = [d.getIntrinsicHeight() + i[1] + i[3] for d, i in zip(self._layers, self._insets) if d.getIntrinsicHeight() >= 0]
        return max(heights) if heights else -1

    def draw(self, canvas):
        if not self._visible:
            return
        left, top, right, bottom = self._bounds
        for layer, inset in zip(self._layers, self._insets):
            layer.setBounds(left + inset[0], top + inset[1], right - inset[2], bottom - inset[3])
            layer.draw(canvas)

    def _encode(self):
        return {"type": "color", "color": 0}

    def _rendered(self):
        """the layers as pixels, as large as the first view that shows them (a view that is not laid out yet shows a one pixel bitmap)"""
        from android.graphics import Bitmap, Canvas
        width = height = 1
        for view in self._owners:
            if view._frame[2] > 0 and view._frame[3] > 0:
                width, height = view._frame[2], view._frame[3]
                break
        bitmap = Bitmap(width, height)
        self._bounds = (0, 0, width, height)
        self.draw(Canvas(bitmap))
        return bitmap


class PictureDrawable(Drawable):
    """a Picture as a drawable, scaled into its bounds"""

    def __init__(self, picture):
        super().__init__()
        self._picture = picture

    def getPicture(self):
        return self._picture

    def setPicture(self, picture):
        self._picture = picture
        self._changed()

    def getIntrinsicWidth(self):
        return self._picture.getWidth() if self._picture is not None else -1

    def getIntrinsicHeight(self):
        return self._picture.getHeight() if self._picture is not None else -1

    def draw(self, canvas):
        picture = self._picture
        if picture is None or not self._visible or not picture.getWidth() or not picture.getHeight():
            return
        left, top, right, bottom = self._bounds
        canvas.save()
        canvas.translate(left, top)
        canvas.scale((right - left) / picture.getWidth(), (bottom - top) / picture.getHeight())
        picture.draw(canvas)
        canvas.restore()


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

    def getIntrinsicWidth(self):
        return self._bitmap.getWidth()

    def getIntrinsicHeight(self):
        return self._bitmap.getHeight()

    def draw(self, canvas):
        from android.graphics import Paint, Rect
        left, top, right, bottom = self._bounds
        paint = Paint()
        paint.setFilterBitmap(True)
        paint.setAlpha(self._alpha)
        source = self._rendered()
        canvas.drawBitmap(source, None, Rect(left, top, right, bottom), paint)

    def _rendered(self):
        if self._filter is None:
            return self._bitmap
        from android.graphics import Bitmap, tint_pixels
        out = Bitmap(self._bitmap.getWidth(), self._bitmap.getHeight())
        out._pixels[:] = tint_pixels(self._bitmap._pixels, self._filter._color, self._filter._mode)
        return out


class RippleDrawable(Drawable):
    """a background that rises under a finger on android. here it is its content (the drawable the plugin gives, or nothing): the app draws
    no ripple, so a view with this background does not answer a touch with a wave"""

    def __init__(self, color, content, mask):
        super().__init__()
        from android.content.res import ColorStateList
        if not isinstance(color, ColorStateList):
            raise TypeError("the color of a ripple is a ColorStateList")
        self._content = content
        self._mask = mask
        # a view draws a bitmap background as pixels, which is so only when the content is one
        if hasattr(content, "_rendered"):
            self._rendered = content._rendered

    def _encode(self):
        return self._content._encode() if self._content is not None else None
