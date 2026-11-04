"""java.util.concurrent: the map is a HashMap behind a lock, which is what plugins need of it"""
import threading

from java.util import HashMap


class ConcurrentHashMap(HashMap):
    def __init__(self, *args):
        HashMap.__init__(self, *args)
        self._lock = threading.RLock()

    def put(self, key, value):
        with self._lock:
            return HashMap.put(self, key, value)

    def remove(self, key):
        with self._lock:
            return HashMap.remove(self, key)
