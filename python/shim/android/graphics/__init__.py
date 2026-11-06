"""android.graphics: a bitmap is a python rgba buffer, the canvas fills rectangles into it. text, paths and shaders are not here"""

import base64
import json

import _exteria
from android import _ui
from java.lang import IllegalArgumentException, Object


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

    def setColorFilter(self, color_filter):
        if color_filter is not None and not isinstance(color_filter, ColorFilter):
            raise TypeError("not a color filter: %r" % (color_filter,))
        self._filter = color_filter
        return color_filter

    def getColorFilter(self):
        return getattr(self, "_filter", None)


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


class ColorMatrix(Object):
    """20 numbers, four rows of r, g, b, a and an offset, as the android class. a color is multiplied by the matrix"""

    def __init__(self, source=None):
        self._m = []
        self.reset()
        if source is not None:
            self.set(source)

    def reset(self):
        self._m = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]

    def set(self, source):
        values = source._m if isinstance(source, ColorMatrix) else list(source)
        if len(values) != 20:
            raise IllegalArgumentException("a color matrix has 20 values, not %d" % len(values))
        self._m = [float(value) for value in values]

    def getArray(self):
        return self._m

    def setScale(self, r_scale, g_scale, b_scale, a_scale):
        self._m = [0.0] * 20
        self._m[0], self._m[6], self._m[12], self._m[18] = float(r_scale), float(g_scale), float(b_scale), float(a_scale)


class ColorMatrixColorFilter(ColorFilter):
    def __init__(self, matrix):
        self._matrix = ColorMatrix(matrix)

    def _alpha_scale(self):
        """how much the filter keeps of the alpha of what it covers, when it only scales alpha (the way a plugin makes a card see-through),
        None for any other matrix"""
        m = self._matrix._m
        rest = [value for index, value in enumerate(m) if index not in (0, 6, 12, 18)]
        if any(rest) or m[0] != 1.0 or m[6] != 1.0 or m[12] != 1.0:
            return None
        return min(1.0, max(0.0, m[18]))


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

    class CompressFormat:
        JPEG = "JPEG"
        PNG = "PNG"
        WEBP = "WEBP"

    @staticmethod
    def createBitmap(*args):
        """createBitmap(width, height[, config]) is a blank picture; createBitmap(source, x, y, width, height) the part of a picture that BitmapFactory decoded"""
        if args and isinstance(args[0], Bitmap):
            if len(args) != 5:
                raise NotImplementedError("only createBitmap(source, x, y, width, height) cuts a picture")
            source, x, y, width, height = args
            if not isinstance(source, _NativeBitmap):
                raise NotImplementedError("a part can be cut from a picture decoded by BitmapFactory only")
            return source._cut(x, y, width, height)
        width, height = args[0], args[1]
        if width <= 0 or height <= 0:
            raise ValueError("width and height must be > 0")
        return Bitmap(width, height)

    def getWidth(self):
        return self._w

    def getHeight(self):
        return self._h

    def isRecycled(self):
        return False

    def isMutable(self):
        return True

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


_released = []
_NATIVE_BITMAP_SIDE = 2048


def _release_native():
    """the bitmaps python let go of since the last flush are let go of in the app too; a finalizer cannot ask the app itself"""
    if _released:
        handles = _released[:]
        del _released[:len(handles)]
        _exteria.service("bitmap.release", json.dumps({"handles": handles}))


_ui.on_flush(_release_native)


class _NativeBitmap(Bitmap):
    """a picture the app decoded and keeps: python holds its size and a handle, the pixels stay in the app, so a photo does not pass
    through python as a megabyte of text. it is mutable (the blur works on it) and has no pixel access"""

    def __init__(self, handle, width, height):
        Object.__init__(self)
        self._handle = int(handle)
        self._w, self._h = int(width), int(height)
        self._gone = False

    def __del__(self):
        if not self._gone:
            _released.append(self._handle)

    def _live(self):
        if self._gone:
            raise IllegalArgumentException("the bitmap was recycled")
        return self._handle

    def isRecycled(self):
        return self._gone

    def recycle(self):
        if not self._gone:
            self._gone = True
            _released.append(self._handle)

    def copy(self, config=None, mutable=True):
        reply = _ui.ask("bitmap.copy", handle=self._live())
        return _NativeBitmap(reply["handle"], reply["w"], reply["h"])

    def _scaled(self, width, height):
        reply = _ui.ask("bitmap.scale", handle=self._live(), w=int(width), h=int(height))
        return _NativeBitmap(reply["handle"], reply["w"], reply["h"])

    def _cut(self, x, y, width, height):
        reply = _ui.ask("bitmap.crop", handle=self._live(), x=int(x), y=int(y), w=int(width), h=int(height))
        return _NativeBitmap(reply["handle"], reply["w"], reply["h"])

    def compress(self, format, quality, stream):
        """writes the picture to a FileOutputStream, as a jpeg or a png. the app writes the file, so the stream has to be one over a file in the folder the
        plugin may write pictures to. True when it was written"""
        from java.io import FileOutputStream
        if not isinstance(stream, FileOutputStream):
            raise NotImplementedError("a picture is compressed into a FileOutputStream only")
        if format not in (Bitmap.CompressFormat.JPEG, Bitmap.CompressFormat.PNG):
            raise NotImplementedError("a picture is compressed as JPEG or PNG, not %s" % (format,))
        _ui.ask("bitmap.encode", handle=self._live(), png=format == Bitmap.CompressFormat.PNG, quality=max(1, min(100, int(quality))), path=stream._path)
        stream._written = True
        return True

    def _blur(self, radius):
        _ui.ask("bitmap.blur", handle=self._live(), radius=int(radius))

    def _unsupported(self, *_args):
        raise NotImplementedError("the pixels of a decoded picture stay in the app, they cannot be read or drawn on from python")

    getPixel = setPixel = eraseColor = _base64 = _unsupported


def _create_scaled(source, width, height, _filter=True):
    if width <= 0 or height <= 0:
        raise IllegalArgumentException("width and height must be > 0")
    if not isinstance(source, _NativeBitmap):
        raise NotImplementedError("scaling is available for pictures decoded by BitmapFactory")
    return source._scaled(width, height)


Bitmap.createScaledBitmap = staticmethod(_create_scaled)


class BitmapFactory(Object):
    """decodes the picture the person chose in the picker of the app (see android.content.ContentResolver). the app reads the file and
    shrinks it while it decodes, to 2048 points on the long side, so a photo of the camera does not fill the memory of an old phone"""

    @staticmethod
    def decodeFile(path, options=None):
        """a picture file of the plugin (its files folder): decoded in the app like a stream, None when it is not a picture"""
        from android_utils import log
        from file_utils import _require_files
        if options is not None:
            raise NotImplementedError("decode options are not available, the app picks the size itself")
        _require_files(path, "decode a picture")
        try:
            reply = _ui.ask("bitmap.decode", path=str(path), side=_NATIVE_BITMAP_SIDE)
        except (RuntimeError, ValueError, LookupError, PermissionError) as error:
            log("BitmapFactory.decodeFile: %s" % error)
            return None
        return _NativeBitmap(reply["handle"], reply["w"], reply["h"])

    @staticmethod
    def decodeStream(stream, outside_padding=None, options=None):
        from android.content import _PickedStream
        from android_utils import log
        if options is not None or outside_padding is not None:
            raise NotImplementedError("decode options are not available, the app picks the size itself")
        if not isinstance(stream, _PickedStream):
            raise NotImplementedError("only the stream of a picture the person chose can be decoded")
        if stream._closed:
            log("BitmapFactory.decodeStream: the stream is closed")
            return None
        try:
            reply = _ui.ask("bitmap.decode", path=stream._path, side=_NATIVE_BITMAP_SIDE)
        except (RuntimeError, ValueError, LookupError, PermissionError) as error:
            # android answers null for a file that is not a picture, and the plugin handles that; the reason goes to the log
            log("BitmapFactory.decodeStream: %s" % error)
            return None
        return _NativeBitmap(reply["handle"], reply["w"], reply["h"])
