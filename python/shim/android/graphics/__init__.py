"""android.graphics: a bitmap is a python rgba buffer, the canvas fills rectangles into it. text, paths and shaders are not here"""

import base64

from java.lang import Object


def _argb(color):
    return int(color) & 0xFFFFFFFF


class Color:
    BLACK = 0xFF000000
    WHITE = 0xFFFFFFFF
    TRANSPARENT = 0
    RED = 0xFFFF0000
    GREEN = 0xFF00FF00
    BLUE = 0xFF0000FF

    @staticmethod
    def argb(a, r, g, b):
        return ((int(a) & 255) << 24) | ((int(r) & 255) << 16) | ((int(g) & 255) << 8) | (int(b) & 255)

    @staticmethod
    def rgb(r, g, b):
        return Color.argb(255, r, g, b)

    @staticmethod
    def alpha(color):
        return (_argb(color) >> 24) & 255

    @staticmethod
    def red(color):
        return (_argb(color) >> 16) & 255

    @staticmethod
    def green(color):
        return (_argb(color) >> 8) & 255

    @staticmethod
    def blue(color):
        return _argb(color) & 255


class Typeface(Object):
    def __init__(self, bold=False):
        self.bold = bold

    DEFAULT = None
    DEFAULT_BOLD = None
    BOLD = 1

    @staticmethod
    def create(family, style=0):
        return Typeface(bool(style & 1))


Typeface.DEFAULT = Typeface(False)
Typeface.DEFAULT_BOLD = Typeface(True)


class Paint(Object):
    class Style:
        FILL = 0
        STROKE = 1
        FILL_AND_STROKE = 2

    class Cap:
        BUTT = "BUTT"
        ROUND = "ROUND"
        SQUARE = "SQUARE"

    class Join:
        MITER = "MITER"
        ROUND = "ROUND"
        BEVEL = "BEVEL"

    ANTI_ALIAS_FLAG = 1

    def __init__(self, flags=0):
        self._color = 0xFF000000
        self._style = Paint.Style.FILL
        self._stroke = 0.0

    def setColor(self, color):
        self._color = _argb(color)

    def getColor(self):
        return self._color

    def setAlpha(self, alpha):
        self._color = (self._color & 0x00FFFFFF) | ((int(alpha) & 255) << 24)

    def setStyle(self, style):
        self._style = style

    def setStrokeWidth(self, width):
        self._stroke = float(width)

    def setStrokeCap(self, cap):
        self._cap = cap

    def setStrokeJoin(self, join):
        self._join = join

    def setAntiAlias(self, value):
        pass

    def setFilterBitmap(self, value):
        pass


class Rect(Object):
    def __init__(self, left=0, top=0, right=0, bottom=0):
        self.left, self.top, self.right, self.bottom = left, top, right, bottom

    def width(self):
        return self.right - self.left

    def height(self):
        return self.bottom - self.top


class RectF(Object):
    def __init__(self, left=0.0, top=0.0, right=0.0, bottom=0.0):
        if isinstance(left, (Rect, RectF)):
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self.left, self.top, self.right, self.bottom = float(left), float(top), float(right), float(bottom)

    def width(self):
        return self.right - self.left

    def height(self):
        return self.bottom - self.top

    def centerX(self):
        return (self.left + self.right) / 2

    def centerY(self):
        return (self.top + self.bottom) / 2

    def set(self, left, top, right, bottom):
        self.left, self.top, self.right, self.bottom = float(left), float(top), float(right), float(bottom)


class PorterDuff(Object):
    class Mode:
        CLEAR = "CLEAR"
        SRC = "SRC"
        DST = "DST"
        SRC_OVER = "SRC_OVER"
        DST_OVER = "DST_OVER"
        SRC_IN = "SRC_IN"
        DST_IN = "DST_IN"
        SRC_OUT = "SRC_OUT"
        DST_OUT = "DST_OUT"
        SRC_ATOP = "SRC_ATOP"
        DST_ATOP = "DST_ATOP"
        XOR = "XOR"
        DARKEN = "DARKEN"
        LIGHTEN = "LIGHTEN"
        MULTIPLY = "MULTIPLY"
        SCREEN = "SCREEN"
        ADD = "ADD"
        OVERLAY = "OVERLAY"


class ColorFilter(Object):
    pass


class PorterDuffColorFilter(ColorFilter):
    def __init__(self, color, mode):
        self._color = _argb(color)
        self._mode = mode


class Point(Object):
    def __init__(self, x=0, y=0):
        self.x, self.y = x, y


class Bitmap(Object):
    class Config:
        ARGB_8888 = "ARGB_8888"
        RGB_565 = "RGB_565"
        ALPHA_8 = "ALPHA_8"

    def __init__(self, width, height):
        self._w, self._h = int(width), int(height)
        self._pixels = bytearray(self._w * self._h * 4)

    @staticmethod
    def createBitmap(width, height, config=None):
        if width <= 0 or height <= 0:
            raise ValueError("width and height must be > 0")
        return Bitmap(width, height)

    def getWidth(self):
        return self._w

    def getHeight(self):
        return self._h

    def isRecycled(self):
        return False

    def recycle(self):
        pass

    def eraseColor(self, color):
        self._fill(0, 0, self._w, self._h, _argb(color))

    def setPixel(self, x, y, color):
        self._fill(x, y, x + 1, y + 1, _argb(color))

    def getPixel(self, x, y):
        offset = (y * self._w + x) * 4
        r, g, b, a = self._pixels[offset:offset + 4]
        return (a << 24) | (r << 16) | (g << 8) | b

    def copy(self, config=None, mutable=True):
        other = Bitmap(self._w, self._h)
        other._pixels[:] = self._pixels
        return other

    def _fill(self, left, top, right, bottom, color):
        left, top = max(0, int(left)), max(0, int(top))
        right, bottom = min(self._w, int(right)), min(self._h, int(bottom))
        if right <= left or bottom <= top:
            return
        pixel = bytes(((color >> 16) & 255, (color >> 8) & 255, color & 255, (color >> 24) & 255))
        row = pixel * (right - left)
        for y in range(top, bottom):
            start = (y * self._w + left) * 4
            self._pixels[start:start + len(row)] = row

    def _base64(self):
        return base64.b64encode(bytes(self._pixels)).decode("ascii")


class Canvas(Object):
    def __init__(self, bitmap=None):
        self._bitmap = bitmap

    def drawRect(self, *args):
        if isinstance(args[0], Rect):
            rect, paint = args[0], args[1]
            left, top, right, bottom = rect.left, rect.top, rect.right, rect.bottom
        else:
            left, top, right, bottom, paint = args
        self._bitmap._fill(round(left), round(top), round(right), round(bottom), paint._color)

    def drawColor(self, color):
        self._bitmap.eraseColor(color)

    def drawPoint(self, x, y, paint):
        self._bitmap._fill(round(x), round(y), round(x) + 1, round(y) + 1, paint._color)


def _blend_channel(mode, src, dst):
    if mode == "MULTIPLY":
        return src * dst // 255
    if mode == "DARKEN":
        return min(src, dst)
    if mode == "LIGHTEN":
        return max(src, dst)
    if mode == "SCREEN":
        return src + dst - src * dst // 255
    raise ValueError("unsupported PorterDuff mode for a bitmap: " + mode)


def tint_pixels(pixels, color, mode):
    """the rgba bytes of a bitmap with a source color applied by the PorterDuff mode of a color filter. alpha of the result
    follows the mode: SRC_IN keeps the bitmap alpha scaled by the color alpha, SRC_ATOP keeps the bitmap alpha"""
    color = _argb(color)
    sa, sr, sg, sb = color >> 24, (color >> 16) & 255, (color >> 8) & 255, color & 255
    out = bytearray(len(pixels))
    for i in range(0, len(pixels), 4):
        dr, dg, db, da = pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
        if mode == "SRC_IN":
            r, g, b, a = sr, sg, sb, da * sa // 255
        elif mode == "SRC":
            r, g, b, a = sr, sg, sb, sa
        elif mode == "SRC_OVER":
            a = sa + da * (255 - sa) // 255
            r, g, b = ((sc * sa + dc * (255 - sa)) // 255 for sc, dc in ((sr, dr), (sg, dg), (sb, db)))
        elif mode == "SRC_ATOP":
            r, g, b = ((sc * sa + dc * (255 - sa)) // 255 for sc, dc in ((sr, dr), (sg, dg), (sb, db)))
            a = da
        else:
            mixed = [_blend_channel(mode, sc, dc) for sc, dc in ((sr, dr), (sg, dg), (sb, db))]
            r, g, b, a = [(m * sa + dc * (255 - sa)) // 255 for m, dc in zip(mixed, (dr, dg, db))] + [da]
        out[i:i + 4] = bytes((r, g, b, a))
    return out
