"""a software rasterizer for android.graphics.Canvas: polygons with coverage, strokes, shaders and Porter-Duff blending

pixels are straight (not premultiplied) rgba bytes, the layout of Bitmap._pixels. a shape is turned into polygons in device
space; coverage of a pixel is exact along x and four samples along y, so edges are antialiased without a mask buffer per
shape. only the rows and columns a shape touches are visited, and a run of fully covered opaque pixels is one slice
assignment. this is python: it is meant for icons, badges and small custom views, not for full screen animation"""

import math

SUBROWS = (0.125, 0.375, 0.625, 0.875)


def edges_of(contours):
    """[(x0, y0, x1, y1, direction)] of the closed polygons, edges that are horizontal dropped"""
    edges = []
    for points in contours:
        count = len(points)
        if count < 2:
            continue
        for index in range(count):
            x0, y0 = points[index]
            x1, y1 = points[(index + 1) % count]
            if y0 == y1:
                continue
            if y0 < y1:
                edges.append((x0, y0, x1, y1, 1))
            else:
                edges.append((x1, y1, x0, y0, -1))
    return edges


def coverage_rows(contours, even_odd, left, top, right, bottom):
    """yields (y, first_x, coverage list) for each pixel row of the polygons inside the clip box; coverage is 0..1 per pixel"""
    edges = edges_of(contours)
    if not edges:
        return
    ymin = max(top, int(math.floor(min(e[1] for e in edges))))
    ymax = min(bottom, int(math.ceil(max(e[3] for e in edges))))
    xmin = max(left, int(math.floor(min(min(e[0], e[2]) for e in edges))))
    xmax = min(right, int(math.ceil(max(max(e[0], e[2]) for e in edges))))
    if ymin >= ymax or xmin >= xmax:
        return
    width = xmax - xmin
    buckets = {}
    for edge in edges:
        first = max(ymin, int(math.floor(edge[1])))
        last = min(ymax - 1, int(math.ceil(edge[3])) - 1)
        for row in range(first, last + 1):
            buckets.setdefault(row, []).append(edge)
    for y in range(ymin, ymax):
        row_edges = buckets.get(y)
        if not row_edges:
            continue
        cover = [0.0] * width
        touched = False
        for sub in SUBROWS:
            sy = y + sub
            crossings = []
            for x0, y0, x1, y1, direction in row_edges:
                if y0 <= sy < y1:
                    crossings.append((x0 + (sy - y0) * (x1 - x0) / (y1 - y0), direction))
            if len(crossings) < 2:
                continue
            crossings.sort()
            winding = 0
            start = 0.0
            for x, direction in crossings:
                was_inside = (winding & 1) if even_odd else winding != 0
                winding += direction
                now_inside = (winding & 1) if even_odd else winding != 0
                if not was_inside and now_inside:
                    start = x
                elif was_inside and not now_inside:
                    _span(cover, start - xmin, x - xmin, width)
                    touched = True
        if touched:
            yield y, xmin, cover


def _span(cover, x0, x1, width):
    """add a quarter of coverage for the horizontal span [x0, x1) to the row"""
    if x1 <= 0 or x0 >= width or x1 <= x0:
        return
    x0 = max(x0, 0.0)
    x1 = min(x1, float(width))
    first = int(x0)
    last = int(x1)
    if first == last:
        cover[first] += 0.25 * (x1 - x0)
        return
    cover[first] += 0.25 * (first + 1 - x0)
    for index in range(first + 1, last):
        cover[index] += 0.25
    if last < width:
        cover[last] += 0.25 * (x1 - last)


# (source factor, destination factor) of each Porter-Duff mode as functions of source alpha sa and destination alpha da
_FACTORS = {
    "CLEAR": lambda sa, da: (0.0, 0.0),
    "SRC": lambda sa, da: (1.0, 0.0),
    "DST": lambda sa, da: (0.0, 1.0),
    "SRC_OVER": lambda sa, da: (1.0, 1.0 - sa),
    "DST_OVER": lambda sa, da: (1.0 - da, 1.0),
    "SRC_IN": lambda sa, da: (da, 0.0),
    "DST_IN": lambda sa, da: (0.0, sa),
    "SRC_OUT": lambda sa, da: (1.0 - da, 0.0),
    "DST_OUT": lambda sa, da: (0.0, 1.0 - sa),
    "SRC_ATOP": lambda sa, da: (da, 1.0 - sa),
    "DST_ATOP": lambda sa, da: (1.0 - da, sa),
    "XOR": lambda sa, da: (1.0 - da, 1.0 - sa),
    "ADD": lambda sa, da: (1.0, 1.0),
}


def blend(pixels, offset, sr, sg, sb, sa, cover, mode):
    """composite one source pixel (colors 0..255, alpha 0..1) into pixels[offset:offset+4] with coverage 0..1"""
    dr, dg, db, da255 = pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]
    da = da255 / 255.0
    if mode == "SRC_OVER":
        a = sa * cover
        if a <= 0.0:
            return
        if a >= 1.0 or da255 == 0:
            if da255 == 0 and a < 1.0:
                pixels[offset:offset + 4] = bytes((sr, sg, sb, int(a * 255 + 0.5)))
            else:
                pixels[offset:offset + 4] = bytes((sr, sg, sb, 255))
            return
        out_a = a + da * (1.0 - a)
        pixels[offset] = int((sr * a + dr * da * (1.0 - a)) / out_a + 0.5)
        pixels[offset + 1] = int((sg * a + dg * da * (1.0 - a)) / out_a + 0.5)
        pixels[offset + 2] = int((sb * a + db * da * (1.0 - a)) / out_a + 0.5)
        pixels[offset + 3] = int(out_a * 255 + 0.5)
        return
    factor = _FACTORS.get(mode)
    if factor is None:
        raise ValueError("unsupported PorterDuff mode for a canvas: " + str(mode))
    fs, fd = factor(sa, da)
    pa = sa * fs + da * fd
    if mode == "ADD":
        pa = min(pa, 1.0)
    if pa <= 0.0:
        out = (0, 0, 0, 0)
    else:
        pr = (sr * sa * fs + dr * da * fd) / pa
        pg = (sg * sa * fs + dg * da * fd) / pa
        pb = (sb * sa * fs + db * da * fd) / pa
        out = (min(255, pr), min(255, pg), min(255, pb), min(1.0, pa) * 255)
    # coverage mixes the result of the mode with what was there
    pixels[offset] = int(dr + (out[0] - dr) * cover + 0.5) if out[3] else dr
    pixels[offset + 1] = int(dg + (out[1] - dg) * cover + 0.5) if out[3] else dg
    pixels[offset + 2] = int(db + (out[2] - db) * cover + 0.5) if out[3] else db
    pixels[offset + 3] = int(da255 + (out[3] - da255) * cover + 0.5)


class Target:
    """the pixel buffer the canvas draws into, with the clip: a box and an optional per pixel mask"""

    def __init__(self, bitmap):
        self.bitmap = bitmap
        self.width = bitmap._w
        self.height = bitmap._h


def paint_polygons(target, contours, even_odd, clip_box, clip_mask, color, shader, mode):
    """fill the polygons. color is (r, g, b, alpha 0..1); shader, when given, answers (r, g, b, a) for a device point"""
    left, top, right, bottom = clip_box
    pixels = target.bitmap._pixels
    width = target.width
    opaque_fast = shader is None and mode == "SRC_OVER" and color[3] >= 1.0 and clip_mask is None
    solid = bytes((color[0], color[1], color[2], 255))
    for y, first, cover in coverage_rows(contours, even_odd, left, top, right, bottom):
        base = y * width
        index = 0
        count = len(cover)
        while index < count:
            c = cover[index]
            if c <= 0.003:
                index += 1
                continue
            if opaque_fast and c >= 0.997:
                run = index
                while run < count and cover[run] >= 0.997:
                    run += 1
                start = (base + first + index) * 4
                pixels[start:start + (run - index) * 4] = solid * (run - index)
                index = run
                continue
            x = first + index
            if c > 1.0:
                c = 1.0
            if clip_mask is not None:
                c *= clip_mask[base + x] / 255.0
                if c <= 0.003:
                    index += 1
                    continue
            if shader is not None:
                r, g, b, a = shader(x + 0.5, y + 0.5)
                blend(pixels, (base + x) * 4, int(r + 0.5), int(g + 0.5), int(b + 0.5), a * color[3], c, mode)
            else:
                blend(pixels, (base + x) * 4, color[0], color[1], color[2], color[3], c, mode)
            index += 1


def coverage_mask(width, height, contours, even_odd, box, invert=False):
    """a width*height mask (0..255) of the polygons, for a clip path"""
    mask = bytearray(width * height)
    if invert:
        mask[:] = b"\xff" * (width * height)
    for y, first, cover in coverage_rows(contours, even_odd, box[0], box[1], box[2], box[3]):
        base = y * width + first
        for index, c in enumerate(cover):
            if c > 0.003:
                value = int(min(c, 1.0) * 255 + 0.5)
                mask[base + index] = 255 - value if invert else value
    return mask


def flatten(path, matrix):
    """[(points, closed)] of a path with its curves cut into lines, in the space the matrix maps to. the number of pieces
    of a curve follows its size on screen"""
    contours = []
    points = []
    closed = False
    start = None
    for segment in path.segments:
        kind = segment[0]
        if kind == "M":
            if points:
                contours.append((points, closed))
            point = matrix._map(segment[1], segment[2])
            points, closed, start = [point], False, point
        elif kind == "L":
            points.append(matrix._map(segment[1], segment[2]))
        elif kind == "Q":
            p0 = points[-1]
            p1 = matrix._map(segment[1], segment[2])
            p2 = matrix._map(segment[3], segment[4])
            steps = _steps(p0, p1, p2)
            for i in range(1, steps + 1):
                t = i / steps
                u = 1 - t
                points.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                               u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
        elif kind == "C":
            p0 = points[-1]
            p1 = matrix._map(segment[1], segment[2])
            p2 = matrix._map(segment[3], segment[4])
            p3 = matrix._map(segment[5], segment[6])
            steps = _steps(p0, p1, p2, p3)
            for i in range(1, steps + 1):
                t = i / steps
                u = 1 - t
                points.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                               u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
        elif kind == "Z":
            closed = True
            if start is not None:
                contours.append((points, True))
                points, closed = [start], False
    if len(points) > 1 or (points and closed):
        contours.append((points, closed))
    return [c for c in contours if len(c[0]) > 1]


def _steps(*points):
    length = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))
    return max(4, min(64, int(length / 3) + 1))


def stroke_polygons(contours, width, cap, join, miter_limit):
    """polygons whose union (non zero winding) is the stroke of the polylines, in the space of the points"""
    half = max(width, 0.0) / 2.0
    polygons = []
    for points, closed in contours:
        clean = [points[0]]
        for point in points[1:]:
            if math.hypot(point[0] - clean[-1][0], point[1] - clean[-1][1]) > 1e-9:
                clean.append(point)
        if closed and len(clean) > 1 and math.hypot(clean[0][0] - clean[-1][0], clean[0][1] - clean[-1][1]) < 1e-9:
            clean.pop()
        if len(clean) == 1:
            if cap == "ROUND":
                polygons.append(_circle(clean[0], half))
            elif cap == "SQUARE":
                x, y = clean[0]
                polygons.append([(x - half, y - half), (x + half, y - half), (x + half, y + half), (x - half, y + half)])
            continue
        count = len(clean)
        segments = count if closed else count - 1
        normals = []
        for i in range(segments):
            a, b = clean[i], clean[(i + 1) % count]
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            nx, ny = (b[1] - a[1]) / length * half, -(b[0] - a[0]) / length * half
            normals.append((nx, ny))
            ax, ay, bx, by = a[0], a[1], b[0], b[1]
            if not closed and cap == "SQUARE":
                dx, dy = (b[0] - a[0]) / length * half, (b[1] - a[1]) / length * half
                if i == 0:
                    ax, ay = ax - dx, ay - dy
                if i == segments - 1:
                    bx, by = bx + dx, by + dy
            polygons.append([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)])
        joints = range(count) if closed else range(1, count - 1)
        for i in joints:
            n1 = normals[(i - 1) % segments]
            n2 = normals[i % segments]
            vertex = clean[i]
            cross = n1[0] * n2[1] - n1[1] * n2[0]
            if abs(cross) < 1e-9 and n1[0] * n2[0] + n1[1] * n2[1] > 0:
                continue
            if join == "ROUND":
                polygons.append(_circle(vertex, half))
                continue
            side = -1.0 if cross > 0 else 1.0
            p1 = (vertex[0] + side * n1[0], vertex[1] + side * n1[1])
            p2 = (vertex[0] + side * n2[0], vertex[1] + side * n2[1])
            piece = [vertex, p1, p2]
            if join == "MITER":
                mx, my = n1[0] + n2[0], n1[1] + n2[1]
                dot = mx * mx + my * my
                if dot > 1e-12:
                    scale = 2.0 * half * half / dot
                    tip = (vertex[0] + side * mx * scale, vertex[1] + side * my * scale)
                    if math.hypot(tip[0] - vertex[0], tip[1] - vertex[1]) <= miter_limit * half:
                        piece = [vertex, p1, tip, p2]
            polygons.append(piece)
        if not closed and cap == "ROUND":
            polygons.append(_circle(clean[0], half))
            polygons.append(_circle(clean[-1], half))
    return [_positive(p) for p in polygons if len(p) >= 3]


def _circle(center, radius):
    steps = max(8, min(64, int(radius * 2) + 8))
    return [(center[0] + radius * math.cos(2 * math.pi * i / steps), center[1] + radius * math.sin(2 * math.pi * i / steps))
            for i in range(steps)]


def _positive(points):
    area = 0.0
    for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]):
        area += x0 * y1 - x1 * y0
    return points if area >= 0 else points[::-1]


def rect_polygon(left, top, right, bottom, matrix):
    return [matrix._map(left, top), matrix._map(right, top), matrix._map(right, bottom), matrix._map(left, bottom)]
