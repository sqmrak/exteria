#!/usr/bin/env python3
"""cut the doodle pattern of the chat wallpaper out of the light wallpaper picture, as an alpha mask, to resources/chat/chat_pattern.png

usage: tools/make_wallpaper_pattern.py   (needs pillow and numpy: python3 -m venv v && v/bin/pip install pillow numpy)
The light wallpaper (resources/chat/chat_bg_light.jpg) is purple line art on a near white ground. The coverage of a pixel is how far it is from the ground,
so the lines keep their weight and the ground becomes empty; the app fills the mask with the ink color of the wallpaper it draws, over any ground color.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCE = os.path.join(ROOT, "resources", "chat", "chat_bg_light.jpg")
TARGET = os.path.join(ROOT, "resources", "chat", "chat_pattern.png")
# the ground of the picture is at most this far from white, and the darkest line this far from it
GROUND = 0.965
SPAN = 0.50


def main():
    picture = np.asarray(Image.open(SOURCE).convert("L"), dtype=np.float64) / 255.0
    coverage = np.clip((GROUND - picture) / SPAN, 0.0, 1.0)
    alpha = (coverage * 255.0 + 0.5).astype(np.uint8)
    mask = Image.merge("LA", (Image.new("L", alpha.shape[::-1], 0), Image.fromarray(alpha, "L")))
    mask.save(TARGET, optimize=True)
    print(TARGET, mask.size, os.path.getsize(TARGET), "bytes")


if __name__ == "__main__":
    main()
