"""android.content"""

from java.lang import Object


class Context(Object):
    SENSOR_SERVICE = "sensor"
    WINDOW_SERVICE = "window"
    VIBRATOR_SERVICE = "vibrator"
    INPUT_METHOD_SERVICE = "input_method"
    CLIPBOARD_SERVICE = "clipboard"
    MODE_PRIVATE = 0

    def getCacheDir(self):
        """the one folder of the app a plugin writes to: the app may clear it, and photos and sounds are taken from it only"""
        from app.exteraless.plugins import PythonBridge
        from java.io import File
        return File(PythonBridge.getCacheDir())

    getFilesDir = getCacheDir


class DialogInterface:
    class OnClickListener:
        pass

    class OnDismissListener:
        pass

    class OnCancelListener:
        pass

    class OnShowListener:
        pass


class ClipData:
    @staticmethod
    def newPlainText(label, text):
        return ClipData()
