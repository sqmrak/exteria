"""android.graphics.Canvas over the software rasterizer, and the shaders and the transfer mode it uses

what is drawn: rectangles, round rectangles, ovals, circles, arcs, lines, points, paths (fill and stroke with caps, joins and
a miter limit), bitmaps made by python, colors, gradients and bitmap shaders, with a matrix, rectangle and path clips,
layers and the Porter-Duff modes. what is not: text (drawText needs glyphs, and the app has no service that draws them into a
bitmap, so it raises), pictures and vertices, and bitmaps decoded by the app (their pixels stay in the app)"""

import math

from android.graphics import _raster
from android.graphics._geometry import Matrix, Path, Rect, RectF, f32
from java.lang import IllegalArgumentException, IllegalStateException, Object, UnsupportedOperationException


def _color_parts(color):
    color = int(color) & 0xFFFFFFFF
    return (color >> 16) & 255, (color >> 8) & 255, color & 255, (color >> 24) / 255.0


class Shader(Object):
    class TileMode:
        CLAMP = "CLAMP"
        REPEAT = "REPEAT"
        MIRROR = "MIRROR"

    def __init__(self):
        self._local = Matrix()

    def setLocalMatrix(self, matrix):
        self._local = Matrix(matrix) if matrix is not None else Matrix()

    def getLocalMatrix(self, matrix):
        matrix.set(self._local)
        return True

    def _tile(self, t, mode):
        if mode == "REPEAT":
            return t - math.floor(t)
        if mode == "MIRROR":
            t = t % 2.0
            return 2.0 - t if t > 1.0 else t
        return min(1.0, max(0.0, t))

    def _device_to_local(self, canvas_matrix):
        total = Matrix(canvas_matrix)
        total.preConcat(self._local)
        inverse = Matrix()
        if not total.invert(inverse):
            return None
        return inverse


def _stops(colors, positions):
    colors = [int(c) & 0xFFFFFFFF for c in colors]
    if positions is None:
        count = len(colors)
        positions = [i / (count - 1) for i in range(count)] if count > 1 else [0.0]
    else:
        positions = [float(p) for p in positions]
    if len(positions) != len(colors) or len(colors) < 2:
        raise IllegalArgumentException("a gradient needs two or more colors and one position for each")
    return colors, positions


def _ramp(colors, positions, t):
    if t <= positions[0]:
        return _color_parts(colors[0])
    for index in range(1, len(positions)):
        if t <= positions[index]:
            span = positions[index] - positions[index - 1]
            f = 0.0 if span <= 0 else (t - positions[index - 1]) / span
            a = _color_parts(colors[index - 1])
            b = _color_parts(colors[index])
            return tuple(a[i] + (b[i] - a[i]) * f for i in range(4))
    return _color_parts(colors[-1])


class LinearGradient(Shader):
    def __init__(self, x0, y0, x1, y1, first, second, third=None, fourth=None):
        super().__init__()
        self._p = (float(x0), float(y0), float(x1), float(y1))
        if isinstance(first, (list, tuple)):
            self._colors, self._pos = _stops(first, second)
            self._tile_mode = third
        else:
            self._colors, self._pos = _stops([first, second], None)
            self._tile_mode = third
        self._tile_mode = self._tile_mode or Shader.TileMode.CLAMP

    def _sampler(self, canvas_matrix):
        inverse = self._device_to_local(canvas_matrix)
        if inverse is None:
            return None
        x0, y0, x1, y1 = self._p
        dx, dy = x1 - x0, y1 - y0
        denominator = dx * dx + dy * dy

        def sample(x, y):
            lx, ly = inverse._map(x, y)
            t = ((lx - x0) * dx + (ly - y0) * dy) / denominator if denominator else 0.0
            return _ramp(self._colors, self._pos, self._tile(t, self._tile_mode))
        return sample


class RadialGradient(Shader):
    def __init__(self, cx, cy, radius, first, second, third=None, fourth=None):
        super().__init__()
        if radius <= 0:
            raise IllegalArgumentException("radius must be > 0")
        self._c = (float(cx), float(cy), float(radius))
        if isinstance(first, (list, tuple)):
            self._colors, self._pos = _stops(first, second)
            self._tile_mode = third
        else:
            self._colors, self._pos = _stops([first, second], None)
            self._tile_mode = third
        self._tile_mode = self._tile_mode or Shader.TileMode.CLAMP

    def _sampler(self, canvas_matrix):
        inverse = self._device_to_local(canvas_matrix)
        if inverse is None:
            return None
        cx, cy, radius = self._c

        def sample(x, y):
            lx, ly = inverse._map(x, y)
            return _ramp(self._colors, self._pos, self._tile(math.hypot(lx - cx, ly - cy) / radius, self._tile_mode))
        return sample


class SweepGradient(Shader):
    def __init__(self, cx, cy, first, second=None):
        super().__init__()
        self._c = (float(cx), float(cy))
        if isinstance(first, (list, tuple)):
            self._colors, self._pos = _stops(first, second)
        else:
            self._colors, self._pos = _stops([first, second], None)

    def _sampler(self, canvas_matrix):
        inverse = self._device_to_local(canvas_matrix)
        if inverse is None:
            return None
        cx, cy = self._c

        def sample(x, y):
            lx, ly = inverse._map(x, y)
            angle = math.atan2(ly - cy, lx - cx) / (2 * math.pi)
            return _ramp(self._colors, self._pos, angle % 1.0)
        return sample


class BitmapShader(Shader):
    def __init__(self, bitmap, tile_x, tile_y):
        super().__init__()
        _need_pixels(bitmap)
        self._bitmap = bitmap
        self._tiles = (tile_x, tile_y)

    def _sampler(self, canvas_matrix):
        inverse = self._device_to_local(canvas_matrix)
        if inverse is None:
            return None
        bitmap = self._bitmap
        width, height = bitmap._w, bitmap._h
        pixels = bitmap._pixels
        mode_x, mode_y = self._tiles

        def sample(x, y):
            lx, ly = inverse._map(x, y)
            u = self._tile(lx / width, mode_x)
            v = self._tile(ly / height, mode_y)
            px = min(width - 1, int(u * width))
            py = min(height - 1, int(v * height))
            offset = (py * width + px) * 4
            return pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3] / 255.0
        return sample


class PorterDuffXfermode(Object):
    def __init__(self, mode):
        self._mode = mode


def _need_pixels(bitmap):
    if bitmap is None:
        raise IllegalArgumentException("bitmap == null")
    if not hasattr(bitmap, "_pixels"):
        raise UnsupportedOperationException(
            "this bitmap was decoded by the app and its pixels stay there; a canvas draws bitmaps made by python only")


class _Saved:
    __slots__ = ("matrix", "box", "mask", "layer")

    def __init__(self, matrix, box, mask, layer):
        self.matrix, self.box, self.mask, self.layer = matrix, box, mask, layer


class Canvas(Object):
    def __init__(self, bitmap=None):
        self._bitmap = None
        self._stack = []
        self._matrix = Matrix()
        self.setBitmap(bitmap)

    def setBitmap(self, bitmap):
        self._bitmap = bitmap
        self._target = _raster.Target(bitmap) if bitmap is not None else None
        self._matrix = Matrix()
        self._stack = []
        self._mask = None
        self._box = (0, 0, bitmap._w, bitmap._h) if bitmap is not None else (0, 0, 0, 0)

    def _need_target(self):
        if self._target is None:
            raise IllegalStateException("this canvas has no bitmap to draw into")
        return self._target

    def getWidth(self):
        return self._bitmap._w if self._bitmap is not None else 0

    def getHeight(self):
        return self._bitmap._h if self._bitmap is not None else 0

    # state

    def save(self):
        self._stack.append(_Saved(Matrix(self._matrix), self._box, self._mask, None))
        return len(self._stack)

    def getSaveCount(self):
        return len(self._stack) + 1

    def restore(self):
        if not self._stack:
            raise IllegalStateException("Underflow in restore - more restores than saves")
        saved = self._stack.pop()
        if saved.layer is not None:
            self._end_layer(saved)
        self._matrix, self._box, self._mask = saved.matrix, saved.box, saved.mask

    def restoreToCount(self, count):
        if count < 1:
            raise IllegalArgumentException("Underflow in restoreToCount - count < 1")
        while len(self._stack) >= count:
            self.restore()

    def saveLayer(self, first, second=None, third=None, fourth=None, fifth=None, sixth=None):
        """saveLayer(RectF|null, paint), saveLayer(l, t, r, b, paint): the drawing goes to a copy of the canvas that is
        composited with the alpha and mode of the paint on restore"""
        paint = second if isinstance(first, (RectF, type(None))) else fifth
        return self._begin_layer(paint)

    def saveLayerAlpha(self, first, second=None, third=None, fourth=None, fifth=None, sixth=None):
        alpha = second if isinstance(first, (RectF, type(None))) else fifth
        from android.graphics import Paint
        paint = Paint()
        paint.setAlpha(alpha)
        return self._begin_layer(paint)

    def _begin_layer(self, paint):
        from android.graphics import Bitmap
        target = self._need_target()
        layer = Bitmap(target.width, target.height)
        saved = _Saved(Matrix(self._matrix), self._box, self._mask, (self._target, self._bitmap, paint))
        self._stack.append(saved)
        self._bitmap = layer
        self._target = _raster.Target(layer)
        return len(self._stack)

    def _end_layer(self, saved):
        parent_target, parent_bitmap, paint = saved.layer
        layer = self._bitmap
        self._bitmap, self._target = parent_bitmap, parent_target
        alpha = 1.0 if paint is None else ((paint._color >> 24) & 255) / 255.0
        mode = "SRC_OVER"
        xfer = getattr(paint, "_xfermode", None) if paint is not None else None
        if xfer is not None:
            mode = xfer._mode
        pixels = layer._pixels
        out = parent_bitmap._pixels
        width = layer._w
        left, top, right, bottom = saved.box
        for y in range(top, bottom):
            for x in range(left, right):
                offset = (y * width + x) * 4
                a = pixels[offset + 3]
                if a:
                    mask = 1.0 if saved.mask is None else saved.mask[y * width + x] / 255.0
                    _raster.blend(out, offset, pixels[offset], pixels[offset + 1], pixels[offset + 2], a / 255.0 * alpha,
                                  mask, mode)

    def translate(self, dx, dy):
        self._matrix.preTranslate(dx, dy)

    def scale(self, sx, sy, px=0.0, py=0.0):
        self._matrix.preScale(sx, sy, px, py)

    def rotate(self, degrees, px=0.0, py=0.0):
        self._matrix.preRotate(degrees, px, py)

    def skew(self, kx, ky):
        self._matrix.preSkew(kx, ky)

    def concat(self, matrix):
        self._matrix.preConcat(matrix)

    def setMatrix(self, matrix):
        self._matrix = Matrix(matrix) if matrix is not None else Matrix()

    def getMatrix(self, matrix=None):
        if matrix is None:
            return Matrix(self._matrix)
        matrix.set(self._matrix)
        return matrix

    # clip

    def _clip_polygon(self, polygon, even_odd=False, invert=False):
        target = self._need_target()
        mask = _raster.coverage_mask(target.width, target.height, [polygon], even_odd, self._box, invert)
        if self._mask is not None:
            mask = bytearray(a * b // 255 for a, b in zip(mask, self._mask))
        self._mask = mask
        xs = [p[0] for p in polygon]
        ys = [p[1] for p in polygon]
        if not invert:
            left, top, right, bottom = self._box
            self._box = (max(left, int(math.floor(min(xs)))), max(top, int(math.floor(min(ys)))),
                         min(right, int(math.ceil(max(xs)))), min(bottom, int(math.ceil(max(ys)))))
        return self._box[2] > self._box[0] and self._box[3] > self._box[1]

    def clipRect(self, first, second=None, third=None, fourth=None, fifth=None):
        """clipRect(rect[, op]) and clipRect(left, top, right, bottom[, op])"""
        if isinstance(first, (Rect, RectF)):
            left, top, right, bottom, op = first.left, first.top, first.right, first.bottom, second
        else:
            left, top, right, bottom, op = first, second, third, fourth, fifth
        polygon = _raster.rect_polygon(left, top, right, bottom, self._matrix)
        if self._matrix.rectStaysRect() and op in (None, "INTERSECT"):
            xs = [p[0] for p in polygon]
            ys = [p[1] for p in polygon]
            box = (max(self._box[0], int(math.floor(min(xs) + 0.5))), max(self._box[1], int(math.floor(min(ys) + 0.5))),
                   min(self._box[2], int(math.floor(max(xs) + 0.5))), min(self._box[3], int(math.floor(max(ys) + 0.5))))
            self._box = box
            return box[2] > box[0] and box[3] > box[1]
        return self._clip_polygon(polygon, False, op == "DIFFERENCE")

    INTERSECT = "INTERSECT"
    DIFFERENCE = "DIFFERENCE"

    def clipPath(self, path, op=None):
        contours = _raster.flatten(path, self._matrix)
        target = self._need_target()
        invert = op == "DIFFERENCE"
        even_odd = path._fill in ("EVEN_ODD", "INVERSE_EVEN_ODD")
        polygons = [c[0] for c in contours]
        mask = _raster.coverage_mask(target.width, target.height, polygons, even_odd, self._box,
                                     invert != path.isInverseFillType())
        if self._mask is not None:
            mask = bytearray(a * b // 255 for a, b in zip(mask, self._mask))
        self._mask = mask
        if polygons and not invert and not path.isInverseFillType():
            xs = [p[0] for poly in polygons for p in poly]
            ys = [p[1] for poly in polygons for p in poly]
            left, top, right, bottom = self._box
            self._box = (max(left, int(math.floor(min(xs)))), max(top, int(math.floor(min(ys)))),
                         min(right, int(math.ceil(max(xs)))), min(bottom, int(math.ceil(max(ys)))))
        return self._box[2] > self._box[0] and self._box[3] > self._box[1]

    def getClipBounds(self, rect=None):
        inverse = Matrix()
        if not self._matrix.invert(inverse):
            box = (0, 0, 0, 0)
        else:
            quad = [inverse._map(x, y) for x, y in ((self._box[0], self._box[1]), (self._box[2], self._box[1]),
                                                   (self._box[2], self._box[3]), (self._box[0], self._box[3]))]
            xs = [q[0] for q in quad]
            ys = [q[1] for q in quad]
            box = (math.floor(min(xs)), math.floor(min(ys)), math.ceil(max(xs)), math.ceil(max(ys)))
        if rect is None:
            return Rect(*box)
        rect.set(*box)
        return box[2] > box[0] and box[3] > box[1]

    def quickReject(self, first, top=None, right=None, bottom=None, edge_type=None):
        if top is None or not isinstance(top, (int, float)):
            first, top, right, bottom = first.left, first.top, first.right, first.bottom
        polygon = _raster.rect_polygon(first, top, right, bottom, self._matrix)
        xs = [p[0] for p in polygon]
        ys = [p[1] for p in polygon]
        return max(xs) <= self._box[0] or min(xs) >= self._box[2] or max(ys) <= self._box[1] or min(ys) >= self._box[3]

    # drawing

    def _paint_state(self, paint):
        color = _color_parts(paint._color)
        mode = "SRC_OVER"
        xfer = getattr(paint, "_xfermode", None)
        if xfer is not None:
            mode = xfer._mode
        shader = None
        shader_object = getattr(paint, "_shader", None)
        if shader_object is not None:
            shader = shader_object._sampler(self._matrix)
            if shader is None:
                return None
        filt = paint.getColorFilter()
        if filt is not None and shader is None:
            color = _filtered(color, filt)
        return color, shader, mode

    def _fill(self, contours, even_odd, paint):
        state = self._paint_state(paint)
        if state is None:
            return
        color, shader, mode = state
        _raster.paint_polygons(self._need_target(), [c[0] for c in contours], even_odd, self._box, self._mask, color,
                               shader, mode)

    def _stroke(self, user_contours, paint):
        state = self._paint_state(paint)
        if state is None:
            return
        color, shader, mode = state
        width = paint._stroke
        scale = math.sqrt(abs(self._matrix.m[0] * self._matrix.m[4] - self._matrix.m[1] * self._matrix.m[3])) or 1.0
        if width <= 0:
            width = 1.0 / scale
        polygons = _raster.stroke_polygons(user_contours, width, getattr(paint, "_cap", "BUTT"),
                                           getattr(paint, "_join", "MITER"), 4.0)
        device = [[self._matrix._map(x, y) for x, y in polygon] for polygon in polygons]
        _raster.paint_polygons(self._need_target(), device, False, self._box, self._mask, color, shader, mode)

    def _draw_path(self, path, paint, fill_override=None):
        style = paint._style if fill_override is None else fill_override
        even_odd = path._fill in ("EVEN_ODD", "INVERSE_EVEN_ODD")
        if style in (0, 2):
            self._fill(_raster.flatten(path, self._matrix), even_odd, paint)
        if style in (1, 2):
            self._stroke(_raster.flatten(path, Matrix()), paint)

    def drawPath(self, path, paint):
        self._draw_path(path, paint)

    def drawRect(self, first, second=None, third=None, fourth=None, fifth=None):
        if isinstance(first, (Rect, RectF)):
            left, top, right, bottom, paint = first.left, first.top, first.right, first.bottom, second
        else:
            left, top, right, bottom, paint = first, second, third, fourth, fifth
        if (self._matrix.isIdentity() and paint._style == 0 and getattr(paint, "_shader", None) is None
                and self._mask is None and paint._color >> 24 == 255
                and getattr(paint, "_xfermode", None) is None and paint.getColorFilter() is None
                and all(float(v) == int(v) for v in (left, top, right, bottom))):
            box = self._box
            self._need_target().bitmap._fill(max(box[0], int(left)), max(box[1], int(top)), min(box[2], int(right)),
                                             min(box[3], int(bottom)), paint._color)
            return
        path = Path()
        path.addRect(left, top, right, bottom, Path.Direction.CW)
        self._draw_path(path, paint)

    def drawRoundRect(self, first, second, third, fourth=None, fifth=None, sixth=None, seventh=None):
        if isinstance(first, RectF):
            rect, rx, ry, paint = first, second, third, fourth
        else:
            rect, rx, ry, paint = RectF(first, second, third, fourth), fifth, sixth, seventh
        path = Path()
        path.addRoundRect(rect, rx, ry, Path.Direction.CW)
        self._draw_path(path, paint)

    def drawOval(self, first, second, third=None, fourth=None, fifth=None):
        if isinstance(first, RectF):
            rect, paint = first, second
        else:
            rect, paint = RectF(first, second, third, fourth), fifth
        path = Path()
        path.addOval(rect, Path.Direction.CW)
        self._draw_path(path, paint)

    def drawCircle(self, cx, cy, radius, paint):
        path = Path()
        path.addCircle(cx, cy, radius, Path.Direction.CW)
        self._draw_path(path, paint)

    def drawArc(self, first, second, third, fourth, fifth=None, sixth=None, seventh=None, eighth=None):
        """drawArc(rect, start, sweep, useCenter, paint) and drawArc(left, top, right, bottom, start, sweep, useCenter, paint)"""
        if isinstance(first, RectF):
            rect, start, sweep, center, paint = first, second, third, fourth, fifth
        else:
            rect, start, sweep, center, paint = RectF(first, second, third, fourth), fifth, sixth, seventh, eighth
        path = Path()
        if center:
            path.moveTo(rect.centerX(), rect.centerY())
        path.arcTo(rect, start, sweep, not center)
        if center:
            path.close()
        self._draw_path(path, paint)

    def drawLine(self, x0, y0, x1, y1, paint):
        self._stroke([([(float(x0), float(y0)), (float(x1), float(y1))], False)], paint)

    def drawLines(self, points, first, second=None, third=None):
        paint = third if third is not None else (second if second is not None and not isinstance(second, int) else first)
        offset, count = (first, second) if third is not None else (0, len(points))
        for index in range(offset, offset + count - 3, 4):
            self.drawLine(points[index], points[index + 1], points[index + 2], points[index + 3], paint)

    def drawPoint(self, x, y, paint):
        self._stroke([([(float(x), float(y))], False)], paint)

    def drawPoints(self, points, first, second=None, third=None):
        paint = third if third is not None else (second if second is not None and not isinstance(second, int) else first)
        offset, count = (first, second) if third is not None else (0, len(points))
        for index in range(offset, offset + count - 1, 2):
            self.drawPoint(points[index], points[index + 1], paint)

    def drawColor(self, color, mode=None):
        target = self._need_target()
        r, g, b, a = _color_parts(color)
        box = self._box
        polygon = [(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])]
        _raster.paint_polygons(target, [polygon], False, box, self._mask, (r, g, b, a), None, mode or "SRC_OVER")

    def drawARGB(self, a, r, g, b):
        self.drawColor((int(a) << 24) | (int(r) << 16) | (int(g) << 8) | int(b))

    def drawRGB(self, r, g, b):
        self.drawARGB(255, r, g, b)

    def drawPaint(self, paint):
        box = self._box
        inverse = Matrix()
        self._matrix.invert(inverse)
        polygon = [(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])]
        state = self._paint_state(paint)
        if state is not None:
            _raster.paint_polygons(self._need_target(), [polygon], False, box, self._mask, state[0], state[1], state[2])

    def drawBitmap(self, bitmap, first, second=None, third=None):
        """drawBitmap(bitmap, left, top, paint), drawBitmap(bitmap, srcRect, dstRect, paint) and drawBitmap(bitmap, matrix, paint)"""
        _need_pixels(bitmap)
        if isinstance(first, Matrix):
            placement, paint = Matrix(first), second
            src = (0, 0, bitmap._w, bitmap._h)
        elif isinstance(first, (Rect, RectF)) or first is None:
            src = (first.left, first.top, first.right, first.bottom) if first is not None else (0, 0, bitmap._w, bitmap._h)
            dst = second
            placement = Matrix()
            sx = (dst.right - dst.left) / (src[2] - src[0]) if src[2] != src[0] else 0
            sy = (dst.bottom - dst.top) / (src[3] - src[1]) if src[3] != src[1] else 0
            placement.setScale(sx, sy)
            placement.postTranslate(dst.left - src[0] * sx, dst.top - src[1] * sy)
            paint = third
        else:
            placement = Matrix()
            placement.setTranslate(first, second)
            paint = third
            src = (0, 0, bitmap._w, bitmap._h)
        total = Matrix(self._matrix)
        total.preConcat(placement)
        inverse = Matrix()
        if not total.invert(inverse):
            return
        width, height = bitmap._w, bitmap._h
        pixels = bitmap._pixels
        smooth = bool(getattr(paint, "_filter_bitmap", False)) if paint is not None else False
        alpha = (paint._color >> 24) / 255.0 if paint is not None else 1.0
        mode = getattr(getattr(paint, "_xfermode", None), "_mode", "SRC_OVER") if paint is not None else "SRC_OVER"
        sl, st, sr, sb = src

        def sample(x, y):
            u, v = inverse._map(x, y)
            if smooth:
                u -= 0.5
                v -= 0.5
                x0, y0 = math.floor(u), math.floor(v)
                fx, fy = u - x0, v - y0
                acc = [0.0, 0.0, 0.0, 0.0]
                for dx, dy, weight in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
                    px = min(max(x0 + dx, int(sl)), int(sr) - 1)
                    py = min(max(y0 + dy, int(st)), int(sb) - 1)
                    offset = (py * width + px) * 4
                    pa = pixels[offset + 3] / 255.0 * weight
                    acc[0] += pixels[offset] * pa
                    acc[1] += pixels[offset + 1] * pa
                    acc[2] += pixels[offset + 2] * pa
                    acc[3] += pa
                if acc[3] <= 0:
                    return 0, 0, 0, 0.0
                return acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], acc[3]
            px, py = int(math.floor(u)), int(math.floor(v))
            px = min(max(px, int(sl)), int(sr) - 1)
            py = min(max(py, int(st)), int(sb) - 1)
            offset = (py * width + px) * 4
            return pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3] / 255.0
        polygon = _raster.rect_polygon(src[0], src[1], src[2], src[3], total)
        _raster.paint_polygons(self._need_target(), [polygon], False, self._box, self._mask, (0, 0, 0, alpha), sample, mode)

    def drawText(self, text, first, second, third=None, fourth=None, fifth=None):
        """drawText(String, x, y, paint), drawText(CharSequence | String, start, end, x, y, paint) and drawText(char[], index, count, x, y, paint).
        the glyphs come from the app, which draws the line in its font into a coverage mask; the mask is tinted with the paint, so a color,
        a shader, an alpha, an underline, a strike, a transfer mode and a shadow (an offset copy, not blurred) all apply. a line is one
        line: a newline is drawn as the app draws it in a label, not as a break"""
        if third is None:
            raise IllegalArgumentException("drawText needs a paint")
        if fourth is None:
            line, x, y, paint = str(text), first, second, third
        else:
            if isinstance(text, (list, tuple)):
                line = "".join(chr(u) for u in text[first:first + second])
            else:
                line = str(text)[first:second]
            x, y, paint = third, fourth, fifth
        self._draw_line(line, float(x), float(y), paint)

    def _draw_line(self, line, x, y, paint):
        if not line or not paint._text_size > 0:
            return
        shadow = getattr(paint, "_shadow", None)
        if shadow is not None and (shadow[3] >> 24):
            self._draw_line_once(line, x + shadow[1], y + shadow[2], paint, shadow[3])
        self._draw_line_once(line, x, y, paint, None)

    def _draw_line_once(self, line, x, y, paint, color_override):
        scale = math.sqrt(abs(self._matrix.m[0] * self._matrix.m[4] - self._matrix.m[1] * self._matrix.m[3])) or 1.0
        pixel_size = min(512.0, max(1.0, paint._text_size * scale))
        mask = _text_mask(line, pixel_size, paint._bold())
        width, height, ascent, alpha = mask
        text_width = (width - 2) / scale
        align = getattr(paint, "_align", "LEFT")
        left = x - (text_width / 2 if align == "CENTER" else text_width if align == "RIGHT" else 0.0)
        placement = Matrix()
        placement.setScale(1.0 / scale, 1.0 / scale)
        placement.postTranslate(left - 1.0 / scale, y - ascent / scale)
        if paint._text_skew_x:
            placement.postSkew(paint._text_skew_x, 0.0, left, y)
        total = Matrix(self._matrix)
        total.preConcat(placement)
        inverse = Matrix()
        if not total.invert(inverse):
            return
        draw_paint = paint
        if color_override is not None:
            from android.graphics import Paint
            draw_paint = Paint()
            draw_paint.setColor(color_override)
            draw_paint.setXfermode(getattr(paint, "_xfermode", None))
        state = self._paint_state(draw_paint)
        if state is None:
            return
        color, base_shader, mode = state

        def sample(dx, dy):
            mx, my = inverse._map(dx, dy)
            mx -= 0.5
            my -= 0.5
            x0, y0 = math.floor(mx), math.floor(my)
            fx, fy = mx - x0, my - y0
            total_alpha = 0.0
            for ox, oy, weight in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
                px, py = x0 + ox, y0 + oy
                if 0 <= px < width and 0 <= py < height:
                    total_alpha += alpha[py * width + px] * weight
            a = total_alpha / 255.0
            if base_shader is not None:
                r, g, b, ba = base_shader(dx, dy)
                return r, g, b, ba * a
            return color[0], color[1], color[2], a
        polygon = _raster.rect_polygon(0, 0, width, height, total)
        _raster.paint_polygons(self._need_target(), [polygon], False, self._box, self._mask, (0, 0, 0, color[3]), sample, mode)
        if color_override is None:
            self._decorate(paint, left, y, text_width, scale)

    def _decorate(self, paint, left, baseline, width, scale):
        """the underline and the strike of a paint, as thin rectangles under and through the text"""
        thickness = max(1.0 / scale, paint._text_size / 14.0)
        if paint._underline:
            self.drawRect(left, baseline + paint._text_size * 0.12, left + width,
                          baseline + paint._text_size * 0.12 + thickness, _fill_of(paint))
        if paint._strike:
            self.drawRect(left, baseline - paint._text_size * 0.3, left + width, baseline - paint._text_size * 0.3 + thickness,
                          _fill_of(paint))

    def drawTextRun(self, *args):
        raise UnsupportedOperationException("Canvas.drawTextRun: complex text layout is not implemented, use drawText")

    drawTextOnPath = drawPosText = drawTextRun

    def drawPicture(self, *args):
        raise UnsupportedOperationException("Canvas.drawPicture: pictures are not recorded by this runtime")

    drawVertices = drawPicture


def _fill_of(paint):
    """a fill paint with the color, alpha, shader and transfer mode of the paint"""
    from android.graphics import Paint
    result = Paint()
    result.set(paint)
    result.setStyle(0)
    return result


_TEXT_CACHE = {}
_TEXT_CACHE_LIMIT = 128


def _text_mask(line, size, bold):
    """(width, height, baseline row, coverage bytes) of the line as the app draws it; the last answers are kept, 128 of them"""
    import base64
    from android import _ui
    key = (line, round(size, 2), bool(bold))
    found = _TEXT_CACHE.get(key)
    if found is not None:
        return found
    try:
        reply = _ui.ask("ui.text_image", text=line, size=float(size), bold=bool(bold))
    except (RuntimeError, ValueError) as error:
        raise UnsupportedOperationException("Canvas.drawText: the app could not draw the text: %s" % error) from error
    mask = (int(reply["w"]), int(reply["h"]), float(reply["ascent"]), base64.b64decode(reply["alpha"]))
    if len(mask[3]) != mask[0] * mask[1]:
        raise UnsupportedOperationException("Canvas.drawText: the app answered a picture of the wrong size")
    if len(_TEXT_CACHE) >= _TEXT_CACHE_LIMIT:
        _TEXT_CACHE.pop(next(iter(_TEXT_CACHE)))
    _TEXT_CACHE[key] = mask
    return mask


def _filtered(color, color_filter):
    """a PorterDuffColorFilter applied to one solid color: the filter color composited by its mode"""
    mode = getattr(color_filter, "_mode", None)
    source = getattr(color_filter, "_color", None)
    if mode is None or source is None:
        return color
    sr, sg, sb, sa = _color_parts(source)
    if mode in ("SRC_IN", "SRC"):
        return (sr, sg, sb, sa * (color[3] if mode == "SRC_IN" else 1.0))
    if mode == "SRC_ATOP":
        return (sr * sa + color[0] * (1 - sa), sg * sa + color[1] * (1 - sa), sb * sa + color[2] * (1 - sa), color[3])
    if mode == "SRC_OVER":
        a = sa + color[3] * (1 - sa)
        if a <= 0:
            return (0, 0, 0, 0)
        return ((sr * sa + color[0] * color[3] * (1 - sa)) / a, (sg * sa + color[1] * color[3] * (1 - sa)) / a,
                (sb * sa + color[2] * color[3] * (1 - sa)) / a, a)
    if mode == "MULTIPLY":
        return (sr * color[0] / 255, sg * color[1] / 255, sb * color[2] / 255, color[3])
    return color
