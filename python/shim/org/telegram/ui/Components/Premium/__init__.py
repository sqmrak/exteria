"""org.telegram.ui.Components.Premium: the particles of the premium screens"""

import random

from android.view import View
from java.lang import Object


class StarParticlesView(View):
    """a field of particles drifting out of (or around) the center, as on the premium screens. it draws circles, or four pointed stars when
    drawable.isCircle is off, in the color of drawable.colorKey (white without one). a frame every FRAME_MS while the view is in a window, with
    at most MAX_PARTICLES of them to keep a slow phone smooth; useBlur and roundEffect have no effect on the raster and are kept for a
    plugin that reads them back"""

    FRAME_MS = 125
    MAX_PARTICLES = 48

    class Drawable(Object):
        """the settings of the particles, written by a plugin before init(): colorKey, isCircle, roundEffect, useRotate, useBlur, useScale,
        startFromCenter, centerOffsetY, speedScale and the three sizes in pixels"""

        def __init__(self, count):
            self.count = int(count)
            self.colorKey = None
            self.isCircle = False
            self.roundEffect = False
            self.useRotate = True
            self.useBlur = False
            self.useScale = False
            self.startFromCenter = False
            self.centerOffsetY = 0
            self.speedScale = 1.0
            self.size1 = 4
            self.size2 = 8
            self.size3 = 12
            self.type = 0
            self._color = 0xFFFFFFFF
            self._particles = []
            self._rng = random.Random(self.count)
            self._boost = 0.0

        def init(self):
            """the particles are made from the settings as they are now, and the color of the key is read once"""
            if self.colorKey is not None:
                from org.telegram.ui.ActionBar import Theme
                self._color = Theme.getColor(self.colorKey)
            self._particles = [self._spawn(True) for _ in range(min(self.count, StarParticlesView.MAX_PARTICLES))]

        def _spawn(self, scattered):
            rng = self._rng
            if self.startFromCenter:
                x, y = 0.5, 0.5 + float(self.centerOffsetY) / 100.0
            else:
                x, y = rng.random(), rng.random()
            angle = rng.random() * 6.283185307179586
            return {"x": x, "y": y, "angle": angle, "speed": 0.05 + rng.random() * 0.1, "size": rng.choice((self.size1, self.size2, self.size3)),
                    "age": rng.random() if scattered else 0.0, "turn": rng.random() * 360.0}

        def advance(self, seconds):
            import math
            speed = self.speedScale * (1.0 + self._boost)
            self._boost = max(0.0, self._boost - 2.0 * seconds)
            for index, p in enumerate(self._particles):
                p["age"] += seconds * 0.5
                p["x"] += math.cos(p["angle"]) * p["speed"] * speed * seconds
                p["y"] += math.sin(p["angle"]) * p["speed"] * speed * seconds
                p["turn"] = (p["turn"] + 90.0 * seconds) % 360.0 if self.useRotate else p["turn"]
                if p["age"] >= 1.0 or not (-0.1 <= p["x"] <= 1.1 and -0.1 <= p["y"] <= 1.1):
                    self._particles[index] = self._spawn(False)

    def __init__(self, context=None, count=40, *_more):
        super().__init__(context)
        self.drawable = StarParticlesView.Drawable(count)
        self.drawable.init()
        self._paused = False
        self._loop = 0
        self._gradient = False

    def setClipWithGradient(self):
        self._gradient = True
        self.invalidate()

    def setPaused(self, paused):
        self._paused = bool(paused)
        self._restart()

    def flingParticles(self, speed):
        """a burst: the particles move faster for a moment, the faster the larger speed is (a value of 360 is a strong one)"""
        self.drawable._boost = min(max(float(speed), 0.0) / 120.0, 4.0)

    def _content_size(self, max_w, max_h):
        return (max_w or 0, max_h or 0)

    def onDraw(self, canvas):
        from android.graphics import Paint, Path
        width, height = self.getWidth(), self.getHeight()
        if width <= 0 or height <= 0:
            return
        paint = Paint(Paint.ANTI_ALIAS_FLAG)
        base = self.drawable._color
        for p in self.drawable._particles:
            # a particle is dim when new and when old, brightest in between; with the gradient clip the edges of the view fade too
            life = 1.0 - abs(p["age"] * 2.0 - 1.0)
            edge = 1.0
            if self._gradient:
                edge = max(0.0, min(1.0, 4.0 * min(p["x"], 1.0 - p["x"], p["y"], 1.0 - p["y"])))
            paint.setColor(base)
            paint.setAlpha(int(((base >> 24) & 255) * max(0.0, life) * edge))
            size = p["size"] * (0.5 + 0.5 * life if self.drawable.useScale else 1.0)
            cx, cy = p["x"] * width, p["y"] * height
            if self.drawable.isCircle:
                canvas.drawCircle(cx, cy, size / 2.0, paint)
            else:
                star = Path()
                star.moveTo(cx, cy - size / 2.0)
                star.lineTo(cx + size / 6.0, cy - size / 6.0)
                star.lineTo(cx + size / 2.0, cy)
                star.lineTo(cx + size / 6.0, cy + size / 6.0)
                star.lineTo(cx, cy + size / 2.0)
                star.lineTo(cx - size / 6.0, cy + size / 6.0)
                star.lineTo(cx - size / 2.0, cy)
                star.lineTo(cx - size / 6.0, cy - size / 6.0)
                star.close()
                canvas.drawPath(star, paint)

    def _restart(self):
        self._loop += 1
        if self._attached and not self._paused:
            self._schedule(self._loop)

    def _schedule(self, loop):
        from android.os import Handler

        class Step:
            def run(step):
                if loop != self._loop or not self._attached or self._paused:
                    return
                self.drawable.advance(StarParticlesView.FRAME_MS / 1000.0)
                self.invalidate()
                self._schedule(loop)

        Handler().postDelayed(Step(), StarParticlesView.FRAME_MS)

    def onAttachedToWindow(self):
        self._restart()

    def onDetachedFromWindow(self):
        self._loop += 1
