"""org.telegram.messenger.utils"""

from java.lang import Object


class ViewOutlineProviderImpl(Object):
    """the outline of a view for clipToOutline: a rectangle with round corners. the app clips a view at one radius for all four
    corners, so only boundsWithRoundRect(radius) is here"""

    def __init__(self, radius):
        radius = float(radius)
        if radius < 0:
            raise ValueError("a corner radius cannot be negative")
        self.radius = radius

    @staticmethod
    def boundsWithRoundRect(radius):
        return ViewOutlineProviderImpl(radius)
