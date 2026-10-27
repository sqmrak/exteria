#!/usr/bin/env python3
"""writes the linen tiles the classic chat is laid on: seamless 128 point squares in a light and a dark weave

usage: make_linen.py resources/chat   (needs pillow and numpy)

The thread noise wraps around, so the tile repeats without a seam. The same weave is drawn at 256 pixels and halved for
the one-x file, so both densities show the same cloth.
"""
import os
import sys

import numpy as np
from PIL import Image

SIDE = 256
SEED = 20261009


def weave(base, spread):
    rng = np.random.RandomState(SEED)
    y, x = np.mgrid[0:SIDE, 0:SIDE]
    rows = rng.normal(0, 1, SIDE)
    cols = rng.normal(0, 1, SIDE)
    # threads run a few pixels long, so the noise is smoothed along its own direction only
    kernel = np.ones(5) / 5.0
    rows = np.convolve(np.concatenate([rows[-4:], rows, rows[:4]]), kernel, mode="same")[4:-4]
    cols = np.convolve(np.concatenate([cols[-4:], cols, cols[:4]]), kernel, mode="same")[4:-4]
    long_h = rng.normal(0, 1, (SIDE, SIDE // 8 + 1))
    long_v = rng.normal(0, 1, (SIDE // 8 + 1, SIDE))
    # irregular thread length: noise stretched along each direction
    h = np.kron(long_h, np.ones((1, 8)))[:, :SIDE]
    v = np.kron(long_v, np.ones((8, 1)))[:SIDE, :]
    cross = np.sin(x * np.pi / 2.0) * np.sin(y * np.pi / 2.0)
    value = 0.55 * rows[:, None] + 0.55 * cols[None, :] + 0.5 * h + 0.5 * v + 0.45 * cross + rng.normal(0, 0.35, (SIDE, SIDE))
    value = value / 2.1
    tile = np.zeros((SIDE, SIDE, 3))
    for channel in range(3):
        tile[..., channel] = base[channel] + value * spread
    return np.clip(tile, 0, 255).astype(np.uint8)


def write(directory, name, base, spread):
    image = Image.fromarray(weave(base, spread), "RGB")
    image.save(os.path.join(directory, name + "@2x.png"), optimize=True)
    image.resize((SIDE // 2, SIDE // 2), Image.LANCZOS).save(os.path.join(directory, name + ".png"), optimize=True)


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "resources/chat"
    os.makedirs(directory, exist_ok=True)
    write(directory, "chat_linen_light", (216, 208, 228), 15)
    write(directory, "chat_linen_dark", (44, 38, 56), 9)


if __name__ == "__main__":
    main()
