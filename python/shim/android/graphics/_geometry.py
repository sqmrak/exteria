"""android.graphics geometry: Rect, RectF, Point, PointF, Matrix, Path and PathMeasure

these are the numbers only: a rectangle, a transform, a list of contour segments. nothing here draws; Canvas says so for the
operations it cannot do. float values are rounded to 32 bits on the way in, as the float fields of android are, so a value
that is printed or compared reads as it does on a device"""

import math
import struct

from java.lang import ArrayIndexOutOfBoundsException, IllegalArgumentException, Object, UnsupportedOperationException

_F32 = struct.Struct("<f")


def f32(value):
    try:
        return _F32.unpack(_F32.pack(value))[0]
    except OverflowError:
        return math.inf if value > 0 else -math.inf


def _text(value):
    """Float.toString of a float32 value"""
    from dexvm.jlang import float_to_string
    return float_to_string(value, True)


class Rect(Object):
    def __init__(self, left=0, top=0, right=0, bottom=0):
        if isinstance(left, Rect):
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self.left, self.top, self.right, self.bottom = int(left), int(top), int(right), int(bottom)

    def width(self):
        return self.right - self.left

    def height(self):
        return self.bottom - self.top

    def centerX(self):
        return (self.left + self.right) >> 1

    def centerY(self):
        return (self.top + self.bottom) >> 1

    def exactCenterX(self):
        return (self.left + self.right) * 0.5

    def exactCenterY(self):
        return (self.top + self.bottom) * 0.5

    def isEmpty(self):
        return self.left >= self.right or self.top >= self.bottom

    def set(self, left, top=None, right=None, bottom=None):
        if top is None:
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self.left, self.top, self.right, self.bottom = int(left), int(top), int(right), int(bottom)

    def setEmpty(self):
        self.left = self.top = self.right = self.bottom = 0

    def offset(self, dx, dy):
        self.left += dx
        self.right += dx
        self.top += dy
        self.bottom += dy

    def offsetTo(self, x, y):
        self.right += x - self.left
        self.bottom += y - self.top
        self.left, self.top = x, y

    def inset(self, dx, dy=None, dr=None, db=None):
        if dy is None:
            dx, dy, dr, db = dx.left, dx.top, dx.right, dx.bottom
        elif dr is None:
            dr, db = dx, dy
        self.left += dx
        self.top += dy
        self.right -= dr
        self.bottom -= db

    def contains(self, first, top=None, right=None, bottom=None):
        if isinstance(first, Rect):
            left, top, right, bottom = first.left, first.top, first.right, first.bottom
            return (self.left < self.right and self.top < self.bottom and self.left <= left and self.top <= top
                    and self.right >= right and self.bottom >= bottom)
        if right is None:
            return self.left <= first < self.right and self.top <= top < self.bottom
        return (self.left < self.right and self.top < self.bottom and self.left <= first and self.top <= top
                and self.right >= right and self.bottom >= bottom)

    def intersect(self, first, top=None, right=None, bottom=None):
        if isinstance(first, Rect):
            first, top, right, bottom = first.left, first.top, first.right, first.bottom
        if self.left < right and first < self.right and self.top < bottom and top < self.bottom:
            self.left = max(self.left, first)
            self.top = max(self.top, top)
            self.right = min(self.right, right)
            self.bottom = min(self.bottom, bottom)
            return True
        return False

    def setIntersect(self, a, b):
        if a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom:
            self.left, self.top = max(a.left, b.left), max(a.top, b.top)
            self.right, self.bottom = min(a.right, b.right), min(a.bottom, b.bottom)
            return True
        return False

    def intersects(self, first, second=None, third=None, fourth=None):
        if second is None:
            return Rect._overlap(self.left, self.top, self.right, self.bottom, first.left, first.top, first.right,
                                 first.bottom)
        return Rect._overlap(self.left, self.top, self.right, self.bottom, first, second, third, fourth)

    @staticmethod
    def _overlap(al, at, ar, ab, bl, bt, br, bb):
        return al < br and bl < ar and at < bb and bt < ab

    def union(self, first, top=None, right=None, bottom=None):
        if top is None:
            self._grow(first.left, first.top, first.right, first.bottom)
        elif right is None:
            self.left, self.right = min(self.left, first), max(self.right, first)
            self.top, self.bottom = min(self.top, top), max(self.bottom, top)
        else:
            self._grow(first, top, right, bottom)

    def _grow(self, left, top, right, bottom):
        if left < right and top < bottom:
            if self.left < self.right and self.top < self.bottom:
                self.left, self.top = min(self.left, left), min(self.top, top)
                self.right, self.bottom = max(self.right, right), max(self.bottom, bottom)
            else:
                self.left, self.top, self.right, self.bottom = left, top, right, bottom

    def sort(self):
        if self.left > self.right:
            self.left, self.right = self.right, self.left
        if self.top > self.bottom:
            self.top, self.bottom = self.bottom, self.top

    def equals(self, other):
        return isinstance(other, Rect) and (self.left, self.top, self.right, self.bottom) == (
            other.left, other.top, other.right, other.bottom)

    __eq__ = equals

    def __hash__(self):
        return hash((self.left, self.top, self.right, self.bottom))

    def hashCode(self):
        return ((self.left * 31 + self.top) * 31 + self.right) * 31 + self.bottom & 0x7FFFFFFF

    def toString(self):
        return "Rect(%d, %d - %d, %d)" % (self.left, self.top, self.right, self.bottom)


class RectF(Object):
    def __init__(self, left=0.0, top=0.0, right=0.0, bottom=0.0):
        if isinstance(left, (Rect, RectF)):
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self.left, self.top, self.right, self.bottom = f32(left), f32(top), f32(right), f32(bottom)

    def width(self):
        return f32(self.right - self.left)

    def height(self):
        return f32(self.bottom - self.top)

    def centerX(self):
        return f32((self.left + self.right) * 0.5)

    def centerY(self):
        return f32((self.top + self.bottom) * 0.5)

    def isEmpty(self):
        return self.left >= self.right or self.top >= self.bottom

    def set(self, left, top=None, right=None, bottom=None):
        if top is None:
            left, top, right, bottom = left.left, left.top, left.right, left.bottom
        self.left, self.top, self.right, self.bottom = f32(left), f32(top), f32(right), f32(bottom)

    def setEmpty(self):
        self.left = self.top = self.right = self.bottom = 0.0

    def offset(self, dx, dy):
        self.left, self.right = f32(self.left + dx), f32(self.right + dx)
        self.top, self.bottom = f32(self.top + dy), f32(self.bottom + dy)

    def offsetTo(self, x, y):
        width, height = self.width(), self.height()
        self.left, self.top = f32(x), f32(y)
        self.right, self.bottom = f32(x + width), f32(y + height)

    def inset(self, dx, dy):
        self.left, self.right = f32(self.left + dx), f32(self.right - dx)
        self.top, self.bottom = f32(self.top + dy), f32(self.bottom - dy)

    def contains(self, first, top=None, right=None, bottom=None):
        if isinstance(first, (Rect, RectF)):
            left, top, right, bottom = first.left, first.top, first.right, first.bottom
            return (self.left < self.right and self.top < self.bottom and self.left <= left and self.top <= top
                    and self.right >= right and self.bottom >= bottom)
        if right is None:
            return self.left <= first < self.right and self.top <= top < self.bottom
        return (self.left < self.right and self.top < self.bottom and self.left <= first and self.top <= top
                and self.right >= right and self.bottom >= bottom)

    def intersect(self, first, top=None, right=None, bottom=None):
        if isinstance(first, (Rect, RectF)):
            first, top, right, bottom = first.left, first.top, first.right, first.bottom
        if self.left < right and first < self.right and self.top < bottom and top < self.bottom:
            self.left, self.top = max(self.left, f32(first)), max(self.top, f32(top))
            self.right, self.bottom = min(self.right, f32(right)), min(self.bottom, f32(bottom))
            return True
        return False

    def setIntersect(self, a, b):
        if a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom:
            self.left, self.top = max(a.left, b.left), max(a.top, b.top)
            self.right, self.bottom = min(a.right, b.right), min(a.bottom, b.bottom)
            return True
        return False

    def intersects(self, first, second=None, third=None, fourth=None):
        if second is None:
            first, second, third, fourth = first.left, first.top, first.right, first.bottom
        return self.left < third and first < self.right and self.top < fourth and second < self.bottom

    def union(self, first, top=None, right=None, bottom=None):
        if top is None:
            first, top, right, bottom = first.left, first.top, first.right, first.bottom
        elif right is None:
            self.left, self.right = min(self.left, f32(first)), max(self.right, f32(first))
            self.top, self.bottom = min(self.top, f32(top)), max(self.bottom, f32(top))
            return
        if first < right and top < bottom:
            if self.left < self.right and self.top < self.bottom:
                self.left, self.top = min(self.left, f32(first)), min(self.top, f32(top))
                self.right, self.bottom = max(self.right, f32(right)), max(self.bottom, f32(bottom))
            else:
                self.set(first, top, right, bottom)

    def sort(self):
        if self.left > self.right:
            self.left, self.right = self.right, self.left
        if self.top > self.bottom:
            self.top, self.bottom = self.bottom, self.top

    def round(self, dst):
        dst.set(_round(self.left), _round(self.top), _round(self.right), _round(self.bottom))

    def roundOut(self, dst):
        dst.set(math.floor(self.left), math.floor(self.top), math.ceil(self.right), math.ceil(self.bottom))

    def equals(self, other):
        return isinstance(other, RectF) and (self.left, self.top, self.right, self.bottom) == (
            other.left, other.top, other.right, other.bottom)

    __eq__ = equals

    def __hash__(self):
        return hash((self.left, self.top, self.right, self.bottom))

    def hashCode(self):
        return hash((self.left, self.top, self.right, self.bottom)) & 0x7FFFFFFF

    def toString(self):
        return "RectF(%s, %s, %s, %s)" % (_text(self.left), _text(self.top), _text(self.right), _text(self.bottom))


def _round(value):
    return math.floor(value + 0.5)


class Point(Object):
    def __init__(self, x=0, y=0):
        if isinstance(x, Point):
            x, y = x.x, x.y
        self.x, self.y = int(x), int(y)

    def set(self, x, y):
        self.x, self.y = int(x), int(y)

    def negate(self):
        self.x, self.y = -self.x, -self.y

    def offset(self, dx, dy):
        self.x += dx
        self.y += dy

    def equals(self, first, second=None):
        if second is None:
            return isinstance(first, Point) and (first.x, first.y) == (self.x, self.y)
        return (self.x, self.y) == (first, second)

    __eq__ = lambda self, other: isinstance(other, Point) and (other.x, other.y) == (self.x, self.y)

    def __hash__(self):
        return hash((self.x, self.y))

    def hashCode(self):
        return self.x * 31 + self.y

    def toString(self):
        return "Point(%d, %d)" % (self.x, self.y)


class PointF(Object):
    def __init__(self, x=0.0, y=0.0):
        if isinstance(x, (Point, PointF)):
            x, y = x.x, x.y
        self.x, self.y = f32(x), f32(y)

    def set(self, x, y=None):
        if y is None:
            x, y = x.x, x.y
        self.x, self.y = f32(x), f32(y)

    def negate(self):
        self.x, self.y = -self.x, -self.y

    def offset(self, dx, dy):
        self.x, self.y = f32(self.x + dx), f32(self.y + dy)

    def length(self, x=None, y=None):
        if x is None:
            x, y = self.x, self.y
        return f32(math.hypot(x, y))

    def equals(self, first, second=None):
        if second is None:
            return isinstance(first, PointF) and (first.x, first.y) == (self.x, self.y)
        return (self.x, self.y) == (f32(first), f32(second))

    __eq__ = lambda self, other: isinstance(other, PointF) and (other.x, other.y) == (self.x, self.y)

    def __hash__(self):
        return hash((self.x, self.y))

    def toString(self):
        return "PointF(%s, %s)" % (_text(self.x), _text(self.y))


MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, MPERSP_0, MPERSP_1, MPERSP_2 = range(9)


class Matrix(Object):
    """a 3x3 transform in the order of android: scale x, skew x, translate x, skew y, scale y, translate y, perspective"""

    MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, MPERSP_0, MPERSP_1, MPERSP_2 = range(9)

    class ScaleToFit:
        FILL = "FILL"
        START = "START"
        CENTER = "CENTER"
        END = "END"

    def __init__(self, other=None):
        self.m = list(other.m) if isinstance(other, Matrix) else [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]

    def reset(self):
        self.m = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]

    def set(self, other):
        self.m = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0] if other is None else list(other.m)

    def isIdentity(self):
        return self.m == [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]

    def isAffine(self):
        return self.m[6] == 0 and self.m[7] == 0 and self.m[8] == 1

    def rectStaysRect(self):
        m = self.m
        return self.isAffine() and ((m[1] == 0 and m[3] == 0) or (m[0] == 0 and m[4] == 0))

    def getValues(self, values):
        if len(values) < 9:
            raise ArrayIndexOutOfBoundsException("values.length < 9")
        for index in range(9):
            values[index] = self.m[index]

    def setValues(self, values):
        if len(values) < 9:
            raise ArrayIndexOutOfBoundsException("values.length < 9")
        self.m = [f32(values[index]) for index in range(9)]

    @staticmethod
    def _mul(a, b):
        return [f32(sum(a[row * 3 + k] * b[k * 3 + col] for k in range(3))) for row in range(3) for col in range(3)]

    def setConcat(self, a, b):
        self.m = Matrix._mul(a.m, b.m)
        return True

    def _translate(self, dx, dy):
        return [1.0, 0.0, f32(dx), 0.0, 1.0, f32(dy), 0.0, 0.0, 1.0]

    def _scale(self, sx, sy, px=0.0, py=0.0):
        return [f32(sx), 0.0, f32(px - sx * px), 0.0, f32(sy), f32(py - sy * py), 0.0, 0.0, 1.0]

    def _rotate(self, degrees, px=0.0, py=0.0):
        radians = math.radians(degrees)
        sin, cos = math.sin(radians), math.cos(radians)
        # skia snaps a value this close to zero, so a quarter turn is exact
        sin = 0.0 if abs(sin) < 1 / 4096 else sin
        cos = 0.0 if abs(cos) < 1 / 4096 else cos
        return [f32(cos), f32(-sin), f32(px - cos * px + sin * py), f32(sin), f32(cos), f32(py - sin * px - cos * py),
                0.0, 0.0, 1.0]

    def _skew(self, kx, ky, px=0.0, py=0.0):
        return [1.0, f32(kx), f32(-kx * py), f32(ky), 1.0, f32(-ky * px), 0.0, 0.0, 1.0]

    def setTranslate(self, dx, dy):
        self.m = self._translate(dx, dy)

    def setScale(self, sx, sy, px=0.0, py=0.0):
        self.m = self._scale(sx, sy, px, py)

    def setRotate(self, degrees, px=0.0, py=0.0):
        self.m = self._rotate(degrees, px, py)

    def setSkew(self, kx, ky, px=0.0, py=0.0):
        self.m = self._skew(kx, ky, px, py)

    def preTranslate(self, dx, dy):
        self.m = Matrix._mul(self.m, self._translate(dx, dy))
        return True

    def preScale(self, sx, sy, px=0.0, py=0.0):
        self.m = Matrix._mul(self.m, self._scale(sx, sy, px, py))
        return True

    def preRotate(self, degrees, px=0.0, py=0.0):
        self.m = Matrix._mul(self.m, self._rotate(degrees, px, py))
        return True

    def preSkew(self, kx, ky, px=0.0, py=0.0):
        self.m = Matrix._mul(self.m, self._skew(kx, ky, px, py))
        return True

    def preConcat(self, other):
        self.m = Matrix._mul(self.m, other.m)
        return True

    def postTranslate(self, dx, dy):
        self.m = Matrix._mul(self._translate(dx, dy), self.m)
        return True

    def postScale(self, sx, sy, px=0.0, py=0.0):
        self.m = Matrix._mul(self._scale(sx, sy, px, py), self.m)
        return True

    def postRotate(self, degrees, px=0.0, py=0.0):
        self.m = Matrix._mul(self._rotate(degrees, px, py), self.m)
        return True

    def postSkew(self, kx, ky, px=0.0, py=0.0):
        self.m = Matrix._mul(self._skew(kx, ky, px, py), self.m)
        return True

    def postConcat(self, other):
        self.m = Matrix._mul(other.m, self.m)
        return True

    def invert(self, inverse):
        m = self.m
        det = (m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6])
               + m[2] * (m[3] * m[7] - m[4] * m[6]))
        if det == 0 or det != det:
            return False
        inv = [(m[4] * m[8] - m[5] * m[7]) / det, (m[2] * m[7] - m[1] * m[8]) / det, (m[1] * m[5] - m[2] * m[4]) / det,
               (m[5] * m[6] - m[3] * m[8]) / det, (m[0] * m[8] - m[2] * m[6]) / det, (m[2] * m[3] - m[0] * m[5]) / det,
               (m[3] * m[7] - m[4] * m[6]) / det, (m[1] * m[6] - m[0] * m[7]) / det, (m[0] * m[4] - m[1] * m[3]) / det]
        if inverse is not None:
            inverse.m = [f32(value) for value in inv]
        return True

    def _map(self, x, y):
        m = self.m
        w = m[6] * x + m[7] * y + m[8]
        px = m[0] * x + m[1] * y + m[2]
        py = m[3] * x + m[4] * y + m[5]
        if w != 1.0 and w != 0.0:
            px, py = px / w, py / w
        return f32(px), f32(py)

    def mapPoints(self, first, second=None, third=None, fourth=None, fifth=None):
        """mapPoints(float[] pts), mapPoints(dst, src) and mapPoints(dst, dstIndex, src, srcIndex, pointCount)"""
        if second is None:
            dst, dst_index, src, src_index, count = first, 0, first, 0, len(first) // 2
        elif third is None:
            dst, dst_index, src, src_index, count = first, 0, second, 0, len(second) // 2
        else:
            dst, dst_index, src, src_index, count = first, second, third, fourth, fifth
        points = [self._map(src[src_index + 2 * i], src[src_index + 2 * i + 1]) for i in range(count)]
        for i, (x, y) in enumerate(points):
            dst[dst_index + 2 * i] = x
            dst[dst_index + 2 * i + 1] = y

    def mapVectors(self, first, second=None):
        src = first if second is None else second
        dst = first
        m = self.m
        out = []
        for i in range(len(src) // 2):
            x, y = src[2 * i], src[2 * i + 1]
            out.append((f32(m[0] * x + m[1] * y), f32(m[3] * x + m[4] * y)))
        for i, (x, y) in enumerate(out):
            dst[2 * i], dst[2 * i + 1] = x, y

    def mapRadius(self, radius):
        m = self.m
        d1 = math.hypot(m[0], m[3])
        d2 = math.hypot(m[1], m[4])
        return f32(radius * math.sqrt(d1 * d2))

    def mapRect(self, first, second=None):
        dst, src = (first, first) if second is None else (first, second)
        corners = [self._map(x, y) for x, y in ((src.left, src.top), (src.right, src.top), (src.right, src.bottom),
                                               (src.left, src.bottom))]
        xs = [c[0] for c in corners]
        ys = [c[1] for c in corners]
        dst.set(min(xs), min(ys), max(xs), max(ys))
        return self.rectStaysRect()

    def setRectToRect(self, src, dst, fit):
        if src.isEmpty():
            self.reset()
            return False
        sx = dst.width() / src.width()
        sy = dst.height() / src.height()
        if fit != Matrix.ScaleToFit.FILL:
            sx = sy = min(sx, sy)
        tx = dst.left - src.left * sx
        ty = dst.top - src.top * sy
        spare_x = dst.width() - src.width() * sx
        spare_y = dst.height() - src.height() * sy
        if fit == Matrix.ScaleToFit.CENTER:
            tx += spare_x / 2
            ty += spare_y / 2
        elif fit == Matrix.ScaleToFit.END:
            tx += spare_x
            ty += spare_y
        self.m = [f32(sx), 0.0, f32(tx), 0.0, f32(sy), f32(ty), 0.0, 0.0, 1.0]
        return True

    def equals(self, other):
        return isinstance(other, Matrix) and other.m == self.m

    __eq__ = equals

    def __hash__(self):
        return hash(tuple(self.m))

    def hashCode(self):
        return hash(tuple(self.m)) & 0x7FFFFFFF

    def toShortString(self):
        m = self.m
        return "[%s, %s, %s][%s, %s, %s][%s, %s, %s]" % tuple(_text(v) for v in m)

    def toString(self):
        return "Matrix{" + self.toShortString() + "}"


KAPPA = 0.5522847498307936


class Path(Object):
    """a list of contours: ('M', x, y), ('L', x, y), ('Q', cx, cy, x, y), ('C', c1x, c1y, c2x, c2y, x, y) and ('Z',)"""

    class Direction:
        CW = "CW"
        CCW = "CCW"

    class FillType:
        WINDING = "WINDING"
        EVEN_ODD = "EVEN_ODD"
        INVERSE_WINDING = "INVERSE_WINDING"
        INVERSE_EVEN_ODD = "INVERSE_EVEN_ODD"

    class Op:
        DIFFERENCE = "DIFFERENCE"
        INTERSECT = "INTERSECT"
        UNION = "UNION"
        XOR = "XOR"
        REVERSE_DIFFERENCE = "REVERSE_DIFFERENCE"

    def __init__(self, other=None):
        self.segments = list(other.segments) if isinstance(other, Path) else []
        self._fill = other._fill if isinstance(other, Path) else Path.FillType.WINDING
        self._current = other._current if isinstance(other, Path) else None
        self._start = other._start if isinstance(other, Path) else None

    def reset(self):
        self.segments = []
        self._current = self._start = None
        self._fill = Path.FillType.WINDING

    rewind = reset

    def set(self, other):
        self.segments = list(other.segments)
        self._current, self._start, self._fill = other._current, other._start, other._fill

    def isEmpty(self):
        return not self.segments

    def getFillType(self):
        return self._fill

    def setFillType(self, fill):
        self._fill = fill

    def isInverseFillType(self):
        return self._fill.startswith("INVERSE")

    def toggleInverseFillType(self):
        self._fill = {"WINDING": "INVERSE_WINDING", "EVEN_ODD": "INVERSE_EVEN_ODD", "INVERSE_WINDING": "WINDING",
                      "INVERSE_EVEN_ODD": "EVEN_ODD"}[self._fill]

    def incReserve(self, extra):
        # a capacity hint on android; the list grows by itself here
        return None

    def moveTo(self, x, y):
        x, y = f32(x), f32(y)
        if self.segments and self.segments[-1][0] == "M":
            self.segments[-1] = ("M", x, y)
        else:
            self.segments.append(("M", x, y))
        self._current = self._start = (x, y)

    def _need_start(self):
        if self._current is None:
            self.moveTo(0.0, 0.0)

    def lineTo(self, x, y):
        self._need_start()
        self.segments.append(("L", f32(x), f32(y)))
        self._current = (f32(x), f32(y))

    def quadTo(self, cx, cy, x, y):
        self._need_start()
        self.segments.append(("Q", f32(cx), f32(cy), f32(x), f32(y)))
        self._current = (f32(x), f32(y))

    def cubicTo(self, x1, y1, x2, y2, x3, y3):
        self._need_start()
        self.segments.append(("C", f32(x1), f32(y1), f32(x2), f32(y2), f32(x3), f32(y3)))
        self._current = (f32(x3), f32(y3))

    def _relative(self):
        return self._current if self._current is not None else (0.0, 0.0)

    def rMoveTo(self, dx, dy):
        x, y = self._relative()
        self.moveTo(x + dx, y + dy)

    def rLineTo(self, dx, dy):
        x, y = self._relative()
        self.lineTo(x + dx, y + dy)

    def rQuadTo(self, dx1, dy1, dx2, dy2):
        x, y = self._relative()
        self.quadTo(x + dx1, y + dy1, x + dx2, y + dy2)

    def rCubicTo(self, dx1, dy1, dx2, dy2, dx3, dy3):
        x, y = self._relative()
        self.cubicTo(x + dx1, y + dy1, x + dx2, y + dy2, x + dx3, y + dy3)

    def close(self):
        if self.segments and self.segments[-1][0] != "Z":
            self.segments.append(("Z",))
            self._current = self._start

    def arcTo(self, first, second, third=None, fourth=None, fifth=None, sixth=None, seventh=None):
        """arcTo(RectF, start, sweep[, forceMoveTo]) and arcTo(left, top, right, bottom, start, sweep, forceMoveTo)"""
        if isinstance(first, RectF):
            oval, start, sweep = first, second, third
            force = bool(fourth) if fourth is not None else False
        else:
            oval = RectF(first, second, third, fourth)
            start, sweep, force = fifth, sixth, bool(seventh)
        self._arc(oval, start, sweep, force)

    def _arc(self, oval, start, sweep, force_move):
        """append the arc of the oval as cubic curves; it starts with a line from the current point unless forceMoveTo"""
        rx, ry = oval.width() / 2.0, oval.height() / 2.0
        cx, cy = oval.centerX(), oval.centerY()
        if rx == 0 and ry == 0:
            return
        sweep = max(-360.0, min(360.0, sweep))
        pieces = max(1, int(math.ceil(abs(sweep) / 90.0)))
        step = math.radians(sweep) / pieces
        begin = math.radians(start)
        first = (cx + rx * math.cos(begin), cy + ry * math.sin(begin))
        if force_move or self._current is None:
            self.moveTo(*first)
        elif max(abs(self._current[0] - first[0]), abs(self._current[1] - first[1])) > 1e-4:
            self.lineTo(*first)
        k = 4.0 / 3.0 * math.tan(step / 4.0)
        angle = begin
        for _ in range(pieces):
            end = angle + step
            c1 = (cx + rx * (math.cos(angle) - k * math.sin(angle)), cy + ry * (math.sin(angle) + k * math.cos(angle)))
            c2 = (cx + rx * (math.cos(end) + k * math.sin(end)), cy + ry * (math.sin(end) - k * math.cos(end)))
            self.cubicTo(c1[0], c1[1], c2[0], c2[1], cx + rx * math.cos(end), cy + ry * math.sin(end))
            angle = end

    def addArc(self, first, second, third, fourth=None, fifth=None, sixth=None):
        if isinstance(first, RectF):
            self._arc(first, second, third, True)
        else:
            self._arc(RectF(first, second, third, fourth), fifth, sixth, True)

    def addRect(self, first, second, third=None, fourth=None, fifth=None):
        if isinstance(first, RectF):
            left, top, right, bottom, direction = first.left, first.top, first.right, first.bottom, second
        else:
            left, top, right, bottom, direction = first, second, third, fourth, fifth
        self.moveTo(left, top)
        if direction == Path.Direction.CCW:
            self.lineTo(left, bottom)
            self.lineTo(right, bottom)
            self.lineTo(right, top)
        else:
            self.lineTo(right, top)
            self.lineTo(right, bottom)
            self.lineTo(left, bottom)
        self.close()

    def addOval(self, first, second, third=None, fourth=None, fifth=None):
        if isinstance(first, RectF):
            oval, direction = first, second
        else:
            oval, direction = RectF(first, second, third, fourth), fifth
        rx, ry = oval.width() / 2.0, oval.height() / 2.0
        self.moveTo(oval.centerX() + rx, oval.centerY())
        self._oval_curves(oval.centerX(), oval.centerY(), rx, ry, direction)

    def _oval_curves(self, cx, cy, rx, ry, direction):
        sign = -1.0 if direction == Path.Direction.CCW else 1.0
        # quarter turns from angle 0; every quarter is one cubic with the control length of a circle
        angle = 0.0
        for _ in range(4):
            end = angle + sign * math.pi / 2
            c1 = (cx + rx * (math.cos(angle) - sign * KAPPA * math.sin(angle)),
                  cy + ry * (math.sin(angle) + sign * KAPPA * math.cos(angle)))
            c2 = (cx + rx * (math.cos(end) + sign * KAPPA * math.sin(end)),
                  cy + ry * (math.sin(end) - sign * KAPPA * math.cos(end)))
            self.cubicTo(c1[0], c1[1], c2[0], c2[1], cx + rx * math.cos(end), cy + ry * math.sin(end))
            angle = end
        self.close()

    def addCircle(self, x, y, radius, direction):
        if radius <= 0:
            return
        self.moveTo(x + radius, y)
        self._oval_curves(x, y, radius, radius, direction)

    def addRoundRect(self, first, second, third, fourth=None, fifth=None, sixth=None, seventh=None):
        """addRoundRect(RectF, rx, ry, dir), addRoundRect(RectF, float[] radii, dir) and the left, top, right, bottom forms"""
        if isinstance(first, RectF):
            rect = first
            rest = (second, third, fourth)
        else:
            rect = RectF(first, second, third, fourth)
            rest = (fifth, sixth, seventh)
        if isinstance(rest[0], (int, float)):
            rx, ry, direction = rest
            radii = [rx, ry] * 4
        else:
            radii, direction = rest[0], rest[1]
            if len(radii) < 8:
                raise IllegalArgumentException("radii[] needs 8 values")
        left, top, right, bottom = rect.left, rect.top, rect.right, rect.bottom
        width, height = right - left, bottom - top
        clamped = [max(0.0, float(r)) for r in radii[:8]]
        scale = 1.0
        for a, b, extent in ((0, 2, width), (6, 4, width), (1, 7, height), (3, 5, height)):
            total = clamped[a] + clamped[b]
            if total > extent > 0:
                scale = min(scale, extent / total)
        radii = [r * scale for r in clamped]
        tl, tr, br, bl = (radii[0], radii[1]), (radii[2], radii[3]), (radii[4], radii[5]), (radii[6], radii[7])
        self.moveTo(left + tl[0], top)
        # clockwise: the straight side to the start of each corner, then the quarter arc around its centre
        corners = ((right - tr[0], top, right - tr[0], top + tr[1], tr, -90.0),
                   (right, bottom - br[1], right - br[0], bottom - br[1], br, 0.0),
                   (left + bl[0], bottom, left + bl[0], bottom - bl[1], bl, 90.0),
                   (left, top + tl[1], left + tl[0], top + tl[1], tl, 180.0))
        for line_x, line_y, center_x, center_y, radius, start in corners:
            if (line_x, line_y) != self._current:
                self.lineTo(line_x, line_y)
            if radius[0] > 0 and radius[1] > 0:
                self._arc(RectF(center_x - radius[0], center_y - radius[1], center_x + radius[0],
                                center_y + radius[1]), start, 90.0, False)
        self.close()
        if direction == Path.Direction.CCW:
            self._reverse_last_contour()

    def _reverse_last_contour(self):
        """RoundRect in counter clockwise order: the same shape walked backwards"""
        index = max(i for i, s in enumerate(self.segments) if s[0] == "M")
        contour = self.segments[index:]
        self.segments = self.segments[:index] + _reverse_contour(contour)

    def addPath(self, other, first=None, second=None):
        if isinstance(first, Matrix):
            transformed = Path(other)
            transformed.transform(first)
            self.segments.extend(transformed.segments)
        elif first is not None:
            moved = Path(other)
            moved.offset(first, second)
            self.segments.extend(moved.segments)
        else:
            self.segments.extend(other.segments)
        if other._current is not None:
            self._current, self._start = other._current, other._start

    def offset(self, dx, dy, dst=None):
        target = self if dst is None else dst
        matrix = Matrix()
        matrix.setTranslate(dx, dy)
        self.transform(matrix, target)

    def transform(self, matrix, dst=None):
        out = []
        for segment in self.segments:
            kind = segment[0]
            if kind == "Z":
                out.append(segment)
                continue
            points = [matrix._map(segment[i], segment[i + 1]) for i in range(1, len(segment), 2)]
            out.append((kind,) + tuple(value for point in points for value in point))
        target = self if dst is None else dst
        target.segments = out
        if dst is not None:
            target._fill = self._fill
        for source, name in ((self._current, "_current"), (self._start, "_start")):
            setattr(target, name, matrix._map(*source) if source is not None else None)

    def computeBounds(self, bounds, exact=True):
        xs, ys = [], []
        previous = None
        for segment in self.segments:
            kind = segment[0]
            if kind in ("M", "L"):
                xs.append(segment[1])
                ys.append(segment[2])
            elif kind == "Q":
                xs.extend((segment[3],))
                ys.extend((segment[4],))
                xs.extend(_quad_extrema(previous[0], segment[1], segment[3]) if exact else (segment[1],))
                ys.extend(_quad_extrema(previous[1], segment[2], segment[4]) if exact else (segment[2],))
            elif kind == "C":
                xs.append(segment[5])
                ys.append(segment[6])
                if exact:
                    xs.extend(_cubic_extrema(previous[0], segment[1], segment[3], segment[5]))
                    ys.extend(_cubic_extrema(previous[1], segment[2], segment[4], segment[6]))
                else:
                    xs.extend((segment[1], segment[3]))
                    ys.extend((segment[2], segment[4]))
            if kind != "Z":
                previous = (segment[-2], segment[-1])
        if not xs:
            bounds.set(0.0, 0.0, 0.0, 0.0)
        else:
            bounds.set(min(xs), min(ys), max(xs), max(ys))

    def isRect(self, rect):
        points = [s for s in self.segments if s[0] != "Z"]
        if len(points) not in (4, 5) or any(s[0] not in ("M", "L") for s in points):
            return False
        corners = [(s[1], s[2]) for s in points]
        if len(corners) == 5 and corners[4] != corners[0]:
            return False
        a, b, c, d = corners[:4]
        ok = (a[0] == b[0] and b[1] == c[1] and c[0] == d[0] and d[1] == a[1]) or (
            a[1] == b[1] and b[0] == c[0] and c[1] == d[1] and d[0] == a[0])
        if ok and rect is not None:
            rect.set(min(a[0], c[0]), min(a[1], c[1]), max(a[0], c[0]), max(a[1], c[1]))
        return ok

    def op(self, first, second=None, third=None):
        raise UnsupportedOperationException("Path.op needs a polygon clipper, which this runtime does not have")

    def isConvex(self):
        raise UnsupportedOperationException("Path.isConvex is not computed by this runtime")

    def toString(self):
        return "Path@%x" % (id(self) & 0xFFFFFF)


def _reverse_contour(contour):
    """a contour of M, L, Q, C and Z segments with its direction reversed"""
    closed = contour[-1][0] == "Z"
    body = contour[:-1] if closed else contour
    points = [(body[0][1], body[0][2])]
    pieces = []
    for segment in body[1:]:
        pieces.append((segment, points[-1]))
        points.append((segment[-2], segment[-1]))
    out = [("M",) + points[-1]]
    for segment, start in reversed(pieces):
        kind = segment[0]
        if kind == "L":
            out.append(("L",) + start)
        elif kind == "Q":
            out.append(("Q", segment[1], segment[2]) + start)
        else:
            out.append(("C", segment[3], segment[4], segment[1], segment[2]) + start)
    if closed:
        out.append(("Z",))
    return out


def _quad_extrema(p0, p1, p2):
    denominator = p0 - 2 * p1 + p2
    if denominator == 0:
        return ()
    t = (p0 - p1) / denominator
    if 0 < t < 1:
        return ((1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2,)
    return ()


def _cubic_extrema(p0, p1, p2, p3):
    a = -p0 + 3 * p1 - 3 * p2 + p3
    b = 2 * (p0 - 2 * p1 + p2)
    c = p1 - p0
    roots = []
    if abs(a) < 1e-12:
        if abs(b) > 1e-12:
            roots.append(-c / b)
    else:
        disc = b * b - 4 * a * c
        if disc >= 0:
            root = math.sqrt(disc)
            roots.extend(((-b + root) / (2 * a), (-b - root) / (2 * a)))
    values = []
    for t in roots:
        if 0 < t < 1:
            u = 1 - t
            values.append(u ** 3 * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t ** 3 * p3)
    return values


class PathMeasure(Object):
    """the length of a path and the points along it. curves are measured as polylines of 24 pieces, so the length of a curve is
    accurate to well under a pixel for the sizes a view has, and a segment taken out of a curve is a polyline"""

    _PIECES = 24
    POSITION_MATRIX_FLAG = 1
    TANGENT_MATRIX_FLAG = 2

    def __init__(self, path=None, force_closed=False):
        self._contours = []
        self._index = 0
        self._force = bool(force_closed)
        if path is not None:
            self.setPath(path, force_closed)

    def setPath(self, path, force_closed):
        self._force = bool(force_closed)
        self._contours = _flatten(path, self._PIECES)
        self._index = 0

    def _contour(self):
        return self._contours[self._index] if self._index < len(self._contours) else None

    def _closed_points(self, contour):
        points, closed = contour
        if (closed or self._force) and points and points[0] != points[-1]:
            return points + [points[0]]
        return points

    def isClosed(self):
        contour = self._contour()
        return bool(contour and (contour[1] or self._force))

    def getLength(self):
        contour = self._contour()
        if contour is None:
            return 0.0
        points = self._closed_points(contour)
        return f32(sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:])))

    def nextContour(self):
        self._index += 1
        return self._index < len(self._contours)

    def _locate(self, distance):
        contour = self._contour()
        if contour is None:
            return None
        points = self._closed_points(contour)
        if len(points) < 2:
            return None
        distance = max(0.0, distance)
        walked = 0.0
        for a, b in zip(points, points[1:]):
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            if walked + length >= distance and length > 0:
                t = (distance - walked) / length
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
            walked += length
        a, b = points[-2], points[-1]
        length = math.hypot(b[0] - a[0], b[1] - a[1]) or 1.0
        return b, ((b[0] - a[0]) / length, (b[1] - a[1]) / length)

    def getPosTan(self, distance, pos, tan):
        found = self._locate(distance)
        if found is None or distance < 0 or distance > self.getLength():
            return False
        if pos is not None:
            pos[0], pos[1] = f32(found[0][0]), f32(found[0][1])
        if tan is not None:
            tan[0], tan[1] = f32(found[1][0]), f32(found[1][1])
        return True

    def getMatrix(self, distance, matrix, flags):
        found = self._locate(distance)
        if found is None or distance < 0 or distance > self.getLength():
            return False
        (x, y), (tx, ty) = found
        matrix.reset()
        if flags & PathMeasure.TANGENT_MATRIX_FLAG:
            matrix.m[0], matrix.m[1], matrix.m[3], matrix.m[4] = f32(tx), f32(-ty), f32(ty), f32(tx)
        if flags & PathMeasure.POSITION_MATRIX_FLAG:
            matrix.m[2], matrix.m[5] = f32(x), f32(y)
        return True

    def getSegment(self, start, stop, dst, start_with_move_to):
        contour = self._contour()
        length = self.getLength()
        if contour is None or length <= 0:
            return False
        start, stop = max(0.0, start), min(length, stop)
        if start >= stop:
            return False
        points = self._closed_points(contour)
        out = []
        walked = 0.0
        for a, b in zip(points, points[1:]):
            seg = math.hypot(b[0] - a[0], b[1] - a[1])
            if seg == 0:
                continue
            lo, hi = max(start, walked), min(stop, walked + seg)
            if lo < hi:
                p = (a[0] + (b[0] - a[0]) * (lo - walked) / seg, a[1] + (b[1] - a[1]) * (lo - walked) / seg)
                q = (a[0] + (b[0] - a[0]) * (hi - walked) / seg, a[1] + (b[1] - a[1]) * (hi - walked) / seg)
                if not out:
                    out.append(p)
                out.append(q)
            walked += seg
        if not out:
            return False
        if start_with_move_to or dst.isEmpty():
            dst.moveTo(*out[0])
        else:
            dst.lineTo(*out[0])
        for point in out[1:]:
            dst.lineTo(*point)
        return True


def _flatten(path, pieces):
    """[(points, closed)] for each contour of the path, with curves cut into straight pieces"""
    contours = []
    points = []
    closed = False
    for segment in path.segments:
        kind = segment[0]
        if kind == "M":
            if points:
                contours.append((points, closed))
            points, closed = [(segment[1], segment[2])], False
        elif kind == "L":
            points.append((segment[1], segment[2]))
        elif kind == "Q":
            x0, y0 = points[-1]
            for i in range(1, pieces + 1):
                t = i / pieces
                u = 1 - t
                points.append((u * u * x0 + 2 * u * t * segment[1] + t * t * segment[3],
                               u * u * y0 + 2 * u * t * segment[2] + t * t * segment[4]))
        elif kind == "C":
            x0, y0 = points[-1]
            for i in range(1, pieces + 1):
                t = i / pieces
                u = 1 - t
                points.append((u ** 3 * x0 + 3 * u * u * t * segment[1] + 3 * u * t * t * segment[3] + t ** 3 * segment[5],
                               u ** 3 * y0 + 3 * u * u * t * segment[2] + 3 * u * t * t * segment[4] + t ** 3 * segment[6]))
        elif kind == "Z":
            closed = True
    if points:
        contours.append((points, closed))
    return [c for c in contours if len(c[0]) > 1 or c[1]]
