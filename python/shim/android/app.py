"""android.app: the activity a plugin finds as LaunchActivity.instance. one object, kept for the life of the process"""

from android.content import Context
from android.view import DecorView


class Window:
    def __init__(self, activity):
        self._activity = activity

    def getDecorView(self):
        return self._activity._decor


class Activity(Context):
    def __init__(self):
        self._decor = DecorView(self)
        self._window = Window(self)
        self._context = self

    def getWindow(self):
        return self._window

    def isFinishing(self):
        return False

    def isDestroyed(self):
        return False

    def getApplicationContext(self):
        return self

    def getSystemService(self, name):
        if name == Context.SENSOR_SERVICE:
            from android.hardware import SensorManager
            return SensorManager.instance()
        raise LookupError("system service %r is not available" % (name,))

    def openMessage(self, *_args):
        raise NotImplementedError("opening a message in the app is not available to plugins on ios")

    def getResources(self):
        raise NotImplementedError("resources are not available on ios")


_activity = []


def activity():
    if not _activity:
        _activity.append(Activity())
    return _activity[0]
