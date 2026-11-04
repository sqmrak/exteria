"""android.os"""

import time

from java.lang import Object


class Looper(Object):
    _main = None

    @staticmethod
    def getMainLooper():
        if Looper._main is None:
            Looper._main = Looper()
        return Looper._main

    @staticmethod
    def myLooper():
        # every python entry point of the host runs on the main thread of the app
        return Looper.getMainLooper()

    def getThread(self):
        import threading
        return threading.main_thread()


class Handler(Object):
    def __init__(self, *_args):
        pass

    @staticmethod
    def _entries():
        return _pending

    def post(self, runnable):
        return self.postDelayed(runnable, 0)

    def postAtFrontOfQueue(self, runnable):
        return self.postDelayed(runnable, 0)

    def postDelayed(self, runnable, delay=0):
        from app.exteraless.plugins import PluginServices
        entry = {"runnable": runnable, "live": True}
        _pending.append(entry)

        def fire():
            if not entry["live"]:
                return
            entry["live"] = False
            try:
                _pending.remove(entry)
            except ValueError:
                pass
            run = getattr(runnable, "run", None)
            (run if run is not None else runnable)()

        PluginServices.runOnUiThread(fire, max(0, int(delay)))
        return True

    def removeCallbacks(self, runnable):
        for entry in list(_pending):
            if entry["runnable"] == runnable:
                entry["live"] = False
                _pending.remove(entry)

    def removeCallbacksAndMessages(self, token=None):
        for entry in list(_pending):
            entry["live"] = False
        del _pending[:]


_pending = []


class Bundle(Object):
    """a map of typed values; the put and get methods share one dictionary"""

    def __init__(self):
        self._values = {}

    def _put(self, key, value):
        self._values[key] = value

    putInt = putBoolean = putString = putFloat = putLong = _put

    def get(self, key, default=None):
        return self._values.get(key, default)

    getInt = getBoolean = getString = getFloat = getLong = get

    def containsKey(self, key):
        return key in self._values


class Process:
    _started = int(time.monotonic() * 1000)

    @staticmethod
    def getStartElapsedRealtime():
        """the clock reading when the interpreter started: it runs from the first plugin, so uptime here is the time plugins have had"""
        return Process._started


class SystemClock:
    @staticmethod
    def uptimeMillis():
        return int(time.monotonic() * 1000)

    elapsedRealtime = uptimeMillis


class Build:
    class VERSION:
        SDK_INT = 33
        RELEASE = "13"

    MODEL = "iPhone"
    MANUFACTURER = "Apple"
