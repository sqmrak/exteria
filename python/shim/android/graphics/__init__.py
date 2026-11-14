"""android.graphics: a bitmap is a python rgba buffer, the canvas fills rectangles into it. text, paths and shaders are not here"""

import base64
import json

import _exteria
from android import _ui
from android.graphics._geometry import Matrix, Path, PathMeasure, Point, PointF, Rect, RectF  # noqa: F401
from android.graphics._canvas import (BitmapShader, Canvas, LinearGradient, PorterDuffXfermode, RadialGradient,  # noqa: F401
                                      Shader, SweepGradient)
from java.lang import IllegalArgumentException, IllegalStateException, Object


def _argb(color):
    return int(color) & 0xFFFFFFFF


class PixelFormat:
    UNKNOWN = 0
    TRANSLUCENT = -3
    TRANSPARENT = -2
    OPAQUE = -1
    RGBA_8888 = 1
    RGBX_8888 = 2
    RGB_888 = 3
    RGB_565 = 4


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

    _anti_alias = False
    _underline = False
    _strike = False
    _fake_bold = False
    _shadow = None
    _miter = 4.0
    _text_scale_x = 1.0
    _text_skew_x = 0.0

    def setAntiAlias(self, value):
        # the rasterizer always antialiases; the flag is kept so a program reads back what it set
        self._anti_alias = bool(value)

    def isAntiAlias(self):
        return self._anti_alias

    def setUnderlineText(self, value):
        self._underline = bool(value)

    def isUnderlineText(self):
        return self._underline

    def setStrikeThruText(self, value):
        self._strike = bool(value)

    def isStrikeThruText(self):
        return self._strike

    def setFakeBoldText(self, value):
        self._fake_bold = bool(value)

    def isFakeBoldText(self):
        return self._fake_bold

    def setStrokeMiter(self, value):
        self._miter = float(value)

    def getStrokeMiter(self):
        return self._miter

    def setTextScaleX(self, value):
        self._text_scale_x = float(value)

    def getTextScaleX(self):
        return self._text_scale_x

    def setTextSkewX(self, value):
        self._text_skew_x = float(value)

    def getTextSkewX(self):
        return self._text_skew_x

    def setShadowLayer(self, radius, dx, dy, color):
        """the shadow of drawn text is the text again at (dx, dy) in the color; the radius is kept but the shadow is not blurred"""
        self._shadow = (float(radius), float(dx), float(dy), int(color) & 0xFFFFFFFF)

    def clearShadowLayer(self):
        self._shadow = None

    def setSubpixelText(self, value):
        self._subpixel = bool(value)

    setDither = setLinearText = setHinting = setFontFeatureSettings = setSubpixelText

    _filter_bitmap = False

    def setFilterBitmap(self, value):
        self._filter_bitmap = bool(value)

    def setColorFilter(self, color_filter):
        if color_filter is not None and not isinstance(color_filter, ColorFilter):
            raise TypeError("not a color filter: %r" % (color_filter,))
        self._filter = color_filter
        return color_filter

    def getColorFilter(self):
        return getattr(self, "_filter", None)

    # text and shader state: kept as set and read back, the way a plugin that sizes its own text expects. measuring asks
    # the app for the real width of the string in the typeface of the paint
    _text_size = 12.0
    _typeface = None
    _align = "LEFT"
    _shader = None
    _xfermode = None
    _path_effect = None
    _letter_spacing = 0.0

    class Align:
        LEFT = "LEFT"
        CENTER = "CENTER"
        RIGHT = "RIGHT"

    def setTextSize(self, size):
        self._text_size = float(size)

    def getTextSize(self):
        return self._text_size

    def setTypeface(self, typeface):
        self._typeface = typeface
        return typeface

    def getTypeface(self):
        return self._typeface

    def setTextAlign(self, align):
        self._align = align

    def getTextAlign(self):
        return self._align

    def setShader(self, shader):
        self._shader = shader
        return shader

    def getShader(self):
        return self._shader

    def setXfermode(self, mode):
        self._xfermode = mode
        return mode

    def getXfermode(self):
        return self._xfermode

    def setPathEffect(self, effect):
        self._path_effect = effect
        return effect

    def setLetterSpacing(self, spacing):
        self._letter_spacing = float(spacing)

    def getLetterSpacing(self):
        return self._letter_spacing

    def getAlpha(self):
        return (self._color >> 24) & 255

    def getStyle(self):
        return self._style

    def getStrokeWidth(self):
        return self._stroke

    def getStrokeCap(self):
        return getattr(self, "_cap", Paint.Cap.BUTT)

    def getStrokeJoin(self):
        return getattr(self, "_join", Paint.Join.MITER)

    def set(self, other):
        self.__dict__.update(other.__dict__)

    def reset(self):
        self.__dict__.clear()
        Paint.__init__(self)

    def _bold(self):
        return self._fake_bold or bool(self._typeface is not None and getattr(self._typeface, "bold", False))

    def measureText(self, text, start=None, end=None):
        if start is not None:
            text = str(text)[start:end]
        text = str(text)
        if not text:
            return 0.0
        width = _ui.measure_text(text, self._text_size, self._bold(), 100000)[0]
        return float(width) + self._letter_spacing * len(text) * self._text_size

    def getFontMetrics(self, metrics=None):
        height = float(_ui.measure_text("A", self._text_size, self._bold(), 100000)[1])
        result = metrics if metrics is not None else Paint.FontMetrics()
        result.top = -height * 0.95
        result.ascent = -height * 0.8
        result.descent = height * 0.2
        result.bottom = height * 0.25
        result.leading = 0.0
        return result.descent - result.ascent if metrics is not None else result

    def ascent(self):
        return self.getFontMetrics().ascent

    def descent(self):
        return self.getFontMetrics().descent

    def getFontSpacing(self):
        metrics = self.getFontMetrics()
        return metrics.bottom - metrics.top

    def getTextBounds(self, text, start, end, bounds):
        text = str(text)[start:end]
        metrics = self.getFontMetrics()
        bounds.set(0, int(metrics.ascent), int(round(self.measureText(text))), int(metrics.descent))

    class FontMetrics(Object):
        def __init__(self):
            self.top = self.ascent = self.descent = self.bottom = self.leading = 0.0

    class FontMetricsInt(Object):
        def __init__(self):
            self.top = self.ascent = self.descent = self.bottom = self.leading = 0


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

    def compress(self, format, quality, stream):
        """a picture made in python is written as PNG to any OutputStream. JPEG and WEBP need an encoder python does not have; the
        app encodes only the pictures it decoded itself"""
        import struct
        import zlib
        if format != Bitmap.CompressFormat.PNG:
            raise NotImplementedError("a bitmap made in python is compressed as PNG; %s needs an encoder the app only has for "
                                      "the pictures it decoded" % (format,))

        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        rows = b"".join(b"\x00" + bytes(self._pixels[y * self._w * 4:(y + 1) * self._w * 4]) for y in range(self._h))
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self._w, self._h, 8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))
        from dexvm.jio import to_java_bytes
        data = to_java_bytes(png)
        stream.write(data, 0, len(data))
        return True

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


class Picture(Object):
    """a recording of drawing calls. the shim keeps the pixels of the drawing and not the calls, so a picture drawn at another size is
    scaled and not drawn again; beginRecording sizes the pixels, and one over MAX_PIXELS is an IllegalArgumentException"""

    MAX_PIXELS = 16 * 1024 * 1024

    def __init__(self, source=None):
        self._bitmap = source._bitmap if source is not None else None
        self._w = source._w if source is not None else 0
        self._h = source._h if source is not None else 0
        self._recording = False

    def beginRecording(self, width, height):
        width, height = int(width), int(height)
        if width < 0 or height < 0 or width * height > Picture.MAX_PIXELS:
            raise IllegalArgumentException("a picture of %d by %d is not recordable" % (width, height))
        if self._recording:
            raise IllegalStateException("the picture is already recording")
        self._w, self._h = width, height
        self._bitmap = Bitmap(max(width, 1), max(height, 1))
        self._recording = True
        return Canvas(self._bitmap)

    def endRecording(self):
        if not self._recording:
            raise IllegalStateException("the picture is not recording")
        self._recording = False

    def getWidth(self):
        return self._w

    def getHeight(self):
        return self._h

    def draw(self, canvas):
        if self._recording:
            raise IllegalStateException("the picture is still recording")
        if self._bitmap is not None and self._w and self._h:
            canvas.drawBitmap(self._bitmap, 0, 0, None)


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
    def decodeByteArray(data, offset, length, options=None):
        """the picture in the bytes, decoded by the app: the bytes go to a file in the cache folder of the plugin and are decoded like a file"""
        import os
        import tempfile
        from android.content import Context
        from android.view import View  # noqa: F401  keeps the shim packages imported in one order
        raw = bytes(b & 0xFF for b in data[offset:offset + length])
        folder = Context().getCacheDir().getPath()
        handle, path = tempfile.mkstemp(dir=folder, prefix="decode-")
        try:
            with os.fdopen(handle, "wb") as out:
                out.write(raw)
            return BitmapFactory.decodeFile(path, options)
        finally:
            os.unlink(path)

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


class RenderEffect(Object):
    """an effect a view applies to itself and what it holds (API 31). making one takes no part of the app; View.setRenderEffect asks the app for the
    kinds it can draw: a blur, alone or chained with another blur. the other kinds are values a plugin can build and hand around, and setRenderEffect
    names the kind it cannot show"""

    def __init__(self, kind, inner=None, **fields):
        self._kind = kind
        self._inner = inner
        self.__dict__.update(fields)

    @staticmethod
    def createBlurEffect(radius_x, radius_y, *rest):
        # (rx, ry, tileMode) or (rx, ry, inner, tileMode)
        if len(rest) not in (1, 2):
            raise IllegalArgumentException("createBlurEffect takes a tile mode and an optional inner effect")
        inner = rest[0] if len(rest) == 2 else None
        if float(radius_x) < 0 or float(radius_y) < 0:
            raise IllegalArgumentException("a blur radius is not negative")
        return RenderEffect("blur", inner, rx=float(radius_x), ry=float(radius_y), tile=rest[-1])

    @staticmethod
    def createOffsetEffect(dx, dy, inner=None):
        return RenderEffect("offset", inner, dx=float(dx), dy=float(dy))

    @staticmethod
    def createColorFilterEffect(color_filter, inner=None):
        return RenderEffect("color filter", inner, color_filter=color_filter)

    @staticmethod
    def createBlendModeEffect(destination, source, mode):
        return RenderEffect("blend mode", None, destination=destination, source=source, mode=mode)

    @staticmethod
    def createChainEffect(outer, inner):
        if outer is None or inner is None:
            raise IllegalArgumentException("a chain needs both effects")
        return RenderEffect("chain", None, outer=outer, first=inner)

    @staticmethod
    def createShaderEffect(shader):
        return RenderEffect("shader", None, shader=shader)

    @staticmethod
    def createBitmapEffect(bitmap, src, dst):
        return RenderEffect("bitmap", None, bitmap=bitmap)

    def _blur_radius(self):
        """the blur the app draws for this effect, in pixels; UnsupportedOperationException names the first kind it cannot draw"""
        from java.lang import UnsupportedOperationException
        radius = 0.0
        if self._inner is not None:
            radius += self._inner._blur_radius()
        if self._kind == "chain":
            return self.outer._blur_radius() + self.first._blur_radius()
        if self._kind != "blur":
            raise UnsupportedOperationException("RenderEffect of the kind '%s' is not drawn by the app, only a blur is" % self._kind)
        # a blur of different radii in x and y is drawn with the larger one: the stack blur of the app is round
        return radius + max(self.rx, self.ry)
