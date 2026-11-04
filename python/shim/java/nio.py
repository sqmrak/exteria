"""java.nio.ByteBuffer over a bytearray: wrap, allocate and the relative reads and writes with position and limit"""

from java.lang import Object


class BufferUnderflowException(Exception):
    pass


class BufferOverflowException(Exception):
    pass


class ByteBuffer(Object):
    def __init__(self, data, position=0, limit=None):
        self._data = data
        self._position = position
        self._limit = len(data) if limit is None else limit

    @staticmethod
    def wrap(array):
        return ByteBuffer(bytearray(array))

    @staticmethod
    def allocate(capacity):
        if capacity < 0:
            raise ValueError("capacity < 0: %d" % capacity)
        return ByteBuffer(bytearray(capacity))

    def array(self):
        return self._data

    def capacity(self):
        return len(self._data)

    def position(self, new=None):
        if new is None:
            return self._position
        if not 0 <= new <= self._limit:
            raise ValueError("bad position %d" % new)
        self._position = new
        return self

    def limit(self, new=None):
        if new is None:
            return self._limit
        if not 0 <= new <= len(self._data):
            raise ValueError("bad limit %d" % new)
        self._limit = new
        self._position = min(self._position, new)
        return self

    def remaining(self):
        return self._limit - self._position

    def hasRemaining(self):
        return self._position < self._limit

    def flip(self):
        self._limit = self._position
        self._position = 0
        return self

    def clear(self):
        self._position = 0
        self._limit = len(self._data)
        return self

    def get(self, destination=None):
        if destination is None:
            if self.remaining() < 1:
                raise BufferUnderflowException()
            value = self._data[self._position]
            self._position += 1
            return value - 256 if value > 127 else value
        count = len(destination)
        if self.remaining() < count:
            raise BufferUnderflowException()
        destination[:] = [b - 256 if b > 127 else b for b in self._data[self._position:self._position + count]]
        self._position += count
        return self

    def put(self, source):
        values = [source] if isinstance(source, int) else list(source)
        if self.remaining() < len(values):
            raise BufferOverflowException()
        for value in values:
            self._data[self._position] = value & 255
            self._position += 1
        return self
