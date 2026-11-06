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
