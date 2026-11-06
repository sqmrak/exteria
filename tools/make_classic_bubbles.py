#!/usr/bin/env python3
"""cuts the classic chat bubbles out of the skeuomorphic bubble pictures, as grey and alpha templates

usage: make_classic_bubbles.py DESIGN_ASSETS_DIR resources/chat   (needs pillow and numpy)

The source pictures are bubble_in.png (tail on the left) and bubble_out.png (tail on the right), at one and two times. Each is cropped to the
bubble, with 6 points left for the tail and nothing for the soft shadow, which the chat view would clip anyway. The plain variants, for a bubble
that has a neighbour under it, are the side of the picture that has no tail, mirrored onto the other. The pictures keep only the lightness, the
app colours them with the accent at run time, so the files carry no hue.
"""
import os
import sys

import numpy as np
from PIL import Image

TAIL_POINTS = 6
SOLID = 128


def solid_bounds(alpha):
    cols = np.where(alpha.max(axis=0) >= SOLID)[0]
    rows = np.where(alpha.max(axis=1) >= SOLID)[0]
    return cols.min(), cols.max() + 1, rows.min(), rows.max() + 1


def body_left(alpha, rows):
    # the tail runs out below the middle, so the body edge is read at the rows of the straight side
    mid = (rows[0] + rows[1]) // 2
    xs = np.where(alpha[mid] >= SOLID)[0]
    return xs.min(), xs.max() + 1


def cut(name, scale, source):
    image = np.array(Image.open(os.path.join(source, "%s%s.png" % (name, "@2x" if scale == 2 else ""))).convert("RGBA")).astype(np.float64)
    alpha = image[..., 3]
    left, right, top, bottom = solid_bounds(alpha)
    body_a, body_b = body_left(alpha, (top, bottom))
    tail = TAIL_POINTS * scale
    if name == "bubble_in":
        left = body_a - tail
    else:
        right = body_b + tail
    return image[top:bottom, left:right], tail, body_a - left, right - body_b


def template(pixels):
    grey = 0.299 * pixels[..., 0] + 0.587 * pixels[..., 1] + 0.114 * pixels[..., 2]
    out = np.zeros(pixels.shape[:2] + (2,), dtype=np.uint8)
    out[..., 0] = np.clip(np.round(grey), 0, 255)
    out[..., 1] = np.clip(np.round(pixels[..., 3]), 0, 255)
    return Image.fromarray(out, "LA")


def plain(pixels, name, tail):
    width = pixels.shape[1]
    if name == "bubble_in":
        half = pixels[:, width - (width - tail) // 2 - ((width - tail) % 2):]
        whole = np.concatenate([half[:, ::-1], half], axis=1)
    else:
        half = pixels[:, :(width - tail + 1) // 2]
        whole = np.concatenate([half, half[:, ::-1]], axis=1)
    return whole


def main():
    source = sys.argv[1]
    directory = sys.argv[2] if len(sys.argv) > 2 else "resources/chat"
    os.makedirs(directory, exist_ok=True)
    for name, short in (("bubble_in", "in"), ("bubble_out", "out")):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            pixels, tail, _, _ = cut(name, scale, source)
            template(pixels).save(os.path.join(directory, "classic_bubble_%s%s.png" % (short, suffix)), optimize=True)
            template(plain(pixels, name, tail)).save(os.path.join(directory, "classic_bubble_%s_plain%s.png" % (short, suffix)), optimize=True)


if __name__ == "__main__":
    main()
