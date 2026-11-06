"""org.telegram.tgnet"""

import struct

from java.lang import Object


class TLObject(Object):
    """base of the records of the telegram schema"""


class SerializedData(Object):
    """the stream a record writes itself to: the bytes the android client would put on the wire, so what a plugin serializes can be read back and checked"""

    def __init__(self):
        self._bytes = bytearray()

    def writeInt32(self, value):
        self._bytes += struct.pack("<i", _int(value, 32))

    def writeInt64(self, value):
        self._bytes += struct.pack("<q", _int(value, 64))

    def writeByteArray(self, data):
        """a TL string or bytes: one length byte below 254, else 0xFE and three, padded to four bytes"""
        data = bytes(data)
        if len(data) < 254:
            self._bytes.append(len(data))
            used = 1 + len(data)
        elif len(data) < 1 << 24:
            self._bytes += bytes([254]) + len(data).to_bytes(3, "little")
            used = 4 + len(data)
        else:
            raise ValueError("a TL string is shorter than 16 MiB")
        self._bytes += data + b"\0" * (-used % 4)

    def writeString(self, value):
        self.writeByteArray(str(value).encode("utf-8"))

    def getBytes(self):
        return bytes(self._bytes)


def _int(value, bits):
    """a java int or long: a python int that wrapped the way two's complement does, as the android client sees it"""
    value = int(value) & ((1 << bits) - 1)
    return value - (1 << bits) if value >> (bits - 1) else value
