"""android.content.res"""

from java.lang import Object


class ColorStateList(Object):
    """a color for every state of a view. the shims draw one state, so it is the one color it was made from"""

    def __init__(self, color):
        self._color = int(color) & 0xFFFFFFFF

    @staticmethod
    def valueOf(color):
        return ColorStateList(color)

    def getDefaultColor(self):
        return self._color


class Resources(Object):
    """the resources of the app: it ships none of the android ones, so a lookup by id or by name answers NotFoundException
    or 0 (the id of nothing), and the display metrics are the screen of the app in points"""

    class NotFoundException(Exception):
        pass

    _system = None

    @staticmethod
    def getSystem():
        if Resources._system is None:
            Resources._system = Resources()
        return Resources._system

    def getDisplayMetrics(self):
        from android import _ui
        from android.util import DisplayMetrics
        screen = _ui.screen()
        metrics = DisplayMetrics()
        metrics.widthPixels = int(screen["w"])
        metrics.heightPixels = int(screen["h"])
        metrics.density = 1.0
        metrics.scaledDensity = 1.0
        metrics.densityDpi = 160
        return metrics

    def getConfiguration(self):
        return Configuration()

    # the drawables of the client that the app has a symbol for: name -> (symbol of the app, id handed out)
    _DRAWABLES = {"files_music": ("music", 0x7F080001)}

    def getIdentifier(self, name, kind, package):
        entry = Resources._DRAWABLES.get(name) if kind == "drawable" else None
        return entry[1] if entry else 0

    def _missing(self, what, resource_id):
        raise Resources.NotFoundException("%s resource ID #0x%x is not in this app" % (what, resource_id))

    def getString(self, resource_id, *args):
        self._missing("String", resource_id)

    def getColor(self, resource_id, theme=None):
        self._missing("Color", resource_id)

    def getDrawable(self, resource_id, theme=None):
        for symbol, number in Resources._DRAWABLES.values():
            if number == resource_id:
                from android.graphics.drawable import SymbolDrawable
                return SymbolDrawable(symbol)
        self._missing("Drawable", resource_id)

    def getDimension(self, resource_id):
        self._missing("Dimension", resource_id)

    getDimensionPixelSize = getDimensionPixelOffset = getDimension

    def getInteger(self, resource_id):
        self._missing("Integer", resource_id)

    def getBoolean(self, resource_id):
        self._missing("Boolean", resource_id)


class Configuration(Object):
    ORIENTATION_UNDEFINED = 0
    ORIENTATION_PORTRAIT = 1
    ORIENTATION_LANDSCAPE = 2
    UI_MODE_NIGHT_MASK = 0x30
    UI_MODE_NIGHT_NO = 0x10
    UI_MODE_NIGHT_YES = 0x20

    def __init__(self):
        from android import _ui
        screen = _ui.screen()
        self.orientation = 2 if int(screen["w"]) > int(screen["h"]) else 1
        self.uiMode = Configuration.UI_MODE_NIGHT_NO
        self.fontScale = 1.0
        self.screenWidthDp = int(screen["w"])
        self.screenHeightDp = int(screen["h"])
        self.densityDpi = 160
