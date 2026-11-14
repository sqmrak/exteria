"""android.media: MediaPlayer for a local file, played by the app (AVAudioPlayer). one sound plays at a time, as the app holds one"""

from android import _ui
from java.lang import Object


class AudioManager(Object):
    STREAM_MUSIC = 3
    STREAM_VOICE_CALL = 0


class MediaMetadataRetriever(Object):
    """reads a frame of a video file. the app publishes pictures as stories only, and has no other use for a frame of a video, so a video is refused here
    by name and a plugin that shows a cover catches it as it catches an unreadable file"""

    def setDataSource(self, path):
        raise NotImplementedError("a frame of a video cannot be read here: %r is not a picture" % (path,))

    def getFrameAtTime(self, *_args):
        raise NotImplementedError("a frame of a video cannot be read here")

    def release(self):
        pass


class MediaPlayer(Object):
    def __init__(self):
        self._path = None
        self._duration = 0
        self._released = False

    def setAudioStreamType(self, _stream):
        pass

    def setDataSource(self, path):
        if not isinstance(path, str):
            raise NotImplementedError("only a file path can be a data source here")
        self._path = path

    def prepare(self):
        if self._path is None:
            raise RuntimeError("no data source")
        self._duration = int(_ui.ask("audio.open", path=self._path).get("duration_ms", 0))

    def getDuration(self):
        return self._duration

    def start(self):
        _ui.ask("audio.start")

    def stop(self):
        _ui.ask("audio.stop")

    def release(self):
        if not self._released:
            self._released = True
            _ui.ask("audio.release")


_EXIF_TAGS = {
    "ImageDescription": ("0", 0x010E, 2), "Make": ("0", 0x010F, 2), "Model": ("0", 0x0110, 2), "Orientation": ("0", 0x0112, 3),
    "XResolution": ("0", 0x011A, 5), "YResolution": ("0", 0x011B, 5), "XPosition": ("0", 0x011E, 5), "YPosition": ("0", 0x011F, 5),
    "ResolutionUnit": ("0", 0x0128, 3), "Software": ("0", 0x0131, 2), "DateTime": ("0", 0x0132, 2), "Artist": ("0", 0x013B, 2),
    "Copyright": ("0", 0x8298, 2),
    "ExposureTime": ("exif", 0x829A, 5), "FNumber": ("exif", 0x829D, 5), "ISOSpeedRatings": ("exif", 0x8827, 3),
    "ExifVersion": ("exif", 0x9000, 7), "DateTimeOriginal": ("exif", 0x9003, 2), "DateTimeDigitized": ("exif", 0x9004, 2),
    "Flash": ("exif", 0x9209, 3), "FocalLength": ("exif", 0x920A, 5), "UserComment": ("exif", 0x9286, 7),
    "PixelXDimension": ("exif", 0xA002, 4), "PixelYDimension": ("exif", 0xA003, 4), "WhiteBalance": ("exif", 0xA403, 3),
    "GPSVersionID": ("gps", 0x00, 1), "GPSLatitudeRef": ("gps", 0x01, 2), "GPSLatitude": ("gps", 0x02, 5),
    "GPSLongitudeRef": ("gps", 0x03, 2), "GPSLongitude": ("gps", 0x04, 5), "GPSAltitudeRef": ("gps", 0x05, 1),
    "GPSAltitude": ("gps", 0x06, 5), "GPSTimeStamp": ("gps", 0x07, 5), "GPSSatellites": ("gps", 0x08, 2),
    "GPSSpeedRef": ("gps", 0x0C, 2), "GPSSpeed": ("gps", 0x0D, 5), "GPSTrackRef": ("gps", 0x0E, 2), "GPSTrack": ("gps", 0x0F, 5),
    "GPSImgDirectionRef": ("gps", 0x10, 2), "GPSImgDirection": ("gps", 0x11, 5), "GPSMapDatum": ("gps", 0x12, 2),
    "GPSProcessingMethod": ("gps", 0x1B, 7), "GPSDateStamp": ("gps", 0x1D, 2),
}
_EXIF_BY_ID = {(ifd, tag): name for name, (ifd, tag, _kind) in _EXIF_TAGS.items()}
_EXIF_SIZES = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8}
_EXIF_POINTERS = {0x8769: "exif", 0x8825: "gps"}
_EXIF_MAX_FILE = 64 * 1024 * 1024
_EXIF_MAX_ENTRIES = 512
# the tags android answers with the decimal of the fraction instead of its text
_EXIF_AS_DECIMAL = ("ExposureTime", "FNumber")


def _exif_error(message):
    from java import jclass
    return jclass("java.io.IOException")(message)


def _exif_constant(name):
    """TAG_MAKE for Make, TAG_GPS_LATITUDE for GPSLatitude; the three date tags are one word in android: TAG_DATETIME"""
    import re
    if name.startswith("DateTime"):
        return "TAG_DATETIME" + re.sub(r"([A-Z])", r"_\1", name[8:]).upper()
    words = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name))
    return "TAG_" + words.upper()


def _exif_read_tiff(data):
    """{(ifd, tag): (type, [values])} of the Exif block of a jpeg. the values are ints, (numerator, denominator) pairs, str for text and
    bytes for the undefined type. the thumbnail directory and the interoperability one are left out"""
    import struct
    if len(data) < 8 or data[:2] not in (b"II", b"MM"):
        raise _exif_error("not an Exif block")
    order = "<" if data[:2] == b"II" else ">"
    if struct.unpack(order + "H", data[2:4])[0] != 42:
        raise _exif_error("bad TIFF marker")
    found, seen = {}, set()

    def directory(offset, name):
        if offset in seen or offset + 2 > len(data):
            raise _exif_error("bad Exif directory offset %d" % offset)
        seen.add(offset)
        count = struct.unpack(order + "H", data[offset:offset + 2])[0]
        if count > _EXIF_MAX_ENTRIES or offset + 2 + 12 * count > len(data):
            raise _exif_error("bad Exif directory of %d entries" % count)
        for index in range(count):
            at = offset + 2 + 12 * index
            tag, kind, number = struct.unpack(order + "HHI", data[at:at + 8])
            width = _EXIF_SIZES.get(kind)
            if width is None:
                continue
            size = width * number
            if size <= 4:
                start = at + 8
            else:
                start = struct.unpack(order + "I", data[at + 8:at + 12])[0]
            if start + size > len(data):
                raise _exif_error("Exif value of tag 0x%04X is outside the block" % tag)
            raw = data[start:start + size]
            if name == "0" and tag in _EXIF_POINTERS:
                if kind == 4 and number == 1:
                    directory(struct.unpack(order + "I", raw)[0], _EXIF_POINTERS[tag])
                continue
            found[(name, tag)] = (kind, _exif_values(order, kind, number, raw))

    directory(struct.unpack(order + "I", data[4:8])[0], "0")
    return found


def _exif_values(order, kind, number, raw):
    import struct
    if kind == 2:
        return [raw.split(b"\0", 1)[0].decode("utf-8", "replace")]
    if kind in (1, 7):
        return [bytes(raw)] if kind == 7 else list(raw)
    letter = {3: "H", 4: "I", 6: "b", 8: "h", 9: "i"}.get(kind)
    if letter is not None:
        return list(struct.unpack(order + letter * number, raw))
    letter = "I" if kind == 5 else "i"
    flat = struct.unpack(order + letter * (2 * number), raw)
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]


def _exif_build_tiff(directories):
    """the little endian Exif block of {ifd: {tag: (type, [values])}}, directories in the order 0, exif, gps. entries are sorted by tag, as
    the format needs, and a value of more than four bytes goes after its directory"""
    import struct
    pointers = {"exif": 0x8769, "gps": 0x8825}
    names = [n for n in ("0", "exif", "gps") if directories.get(n) or n == "0"]
    encoded = {}
    for name in names:
        rows = {tag: (kind, _exif_pack(kind, values)) for tag, (kind, values) in directories.get(name, {}).items()}
        if name == "0":
            for sub, tag in pointers.items():
                if sub in names:
                    rows[tag] = (4, (1, b"\0\0\0\0"))
        encoded[name] = rows
    offsets, cursor = {}, 8
    for name in names:
        offsets[name] = cursor
        cursor += 2 + 12 * len(encoded[name]) + 4
        for _tag, (_kind, (_count, raw)) in encoded[name].items():
            if len(raw) > 4:
                cursor += len(raw) + (len(raw) & 1)
    out = bytearray(b"II*\0" + struct.pack("<I", 8))
    for name in names:
        rows = encoded[name]
        table, tail = bytearray(struct.pack("<H", len(rows))), bytearray()
        data_at = offsets[name] + 2 + 12 * len(rows) + 4
        for tag in sorted(rows):
            kind, (count, raw) = rows[tag]
            if name == "0" and tag in (0x8769, 0x8825):
                raw = struct.pack("<I", offsets["exif" if tag == 0x8769 else "gps"])
            if len(raw) <= 4:
                value = raw + b"\0" * (4 - len(raw))
            else:
                value = struct.pack("<I", data_at + len(tail))
                tail += raw + (b"\0" if len(raw) & 1 else b"")
            table += struct.pack("<HHI", tag, kind, count) + value
        out += table + struct.pack("<I", 0) + tail
    return bytes(out)


def _exif_pack(kind, values):
    import struct
    if kind == 2:
        raw = values[0].encode("utf-8") + b"\0"
        return (len(raw), raw)
    if kind == 7:
        return (len(values[0]), values[0])
    if kind == 1:
        return (len(values), bytes(values))
    letter = {3: "H", 4: "I"}.get(kind)
    if letter is not None:
        return (len(values), struct.pack("<" + letter * len(values), *values))
    flat = [part for pair in values for part in pair]
    return (len(values), struct.pack("<" + "I" * len(flat), *flat))


class ExifInterface(Object):
    """the Exif of a jpeg: the tags of _EXIF_TAGS are read, changed and written back. a tag outside that list stays in the file as it was.
    the thumbnail is dropped when the file is saved. other picture formats open with no attributes and cannot be saved. the decimal that
    getAttribute answers for ExposureTime and FNumber is written as python writes a float, which is not always the text java prints"""

    ORIENTATION_UNDEFINED = 0
    ORIENTATION_NORMAL = 1
    ORIENTATION_FLIP_HORIZONTAL = 2
    ORIENTATION_ROTATE_180 = 3
    ORIENTATION_FLIP_VERTICAL = 4
    ORIENTATION_TRANSPOSE = 5
    ORIENTATION_ROTATE_90 = 6
    ORIENTATION_TRANSVERSE = 7
    ORIENTATION_ROTATE_270 = 8

    def __init__(self, source):
        super().__init__()
        if hasattr(source, "getAbsolutePath"):
            source = source.getAbsolutePath()
        if not isinstance(source, str):
            raise TypeError("ExifInterface opens a path or a File, not %s" % type(source).__name__)
        self._path = source
        self._tags = {}
        self._jpeg = False
        self._load()

    def _read_file(self):
        import os
        try:
            if os.path.getsize(self._path) > _EXIF_MAX_FILE:
                raise _exif_error("%s is larger than %d bytes" % (self._path, _EXIF_MAX_FILE))
            with open(self._path, "rb") as handle:
                return handle.read()
        except FileNotFoundError as error:
            from java import jclass
            raise jclass("java.io.FileNotFoundException")(str(error)) from error
        except OSError as error:
            raise _exif_error(str(error)) from error

    @staticmethod
    def _segments(data):
        """(marker, start, end) of each jpeg segment before the scan; end is the offset after the segment"""
        position = 2
        while position + 4 <= len(data) and data[position] == 0xFF:
            marker = data[position + 1]
            if marker == 0xFF:
                position += 1
                continue
            if marker in (0xDA, 0xD9):
                return
            length = (data[position + 2] << 8) | data[position + 3]
            if length < 2 or position + 2 + length > len(data):
                raise _exif_error("a jpeg segment runs past the end of the file")
            yield marker, position, position + 2 + length
            position += 2 + length

    def _load(self):
        data = self._read_file()
        if data[:2] != b"\xff\xd8":
            return
        self._jpeg = True
        for marker, start, end in self._segments(data):
            if marker == 0xE1 and data[start + 4:start + 10] == b"Exif\0\0":
                for key, entry in _exif_read_tiff(data[start + 10:end]).items():
                    self._tags[key] = entry
                return

    def _known(self, tag):
        found = _EXIF_TAGS.get(tag)
        if found is None:
            from java.lang import IllegalArgumentException
            raise IllegalArgumentException("%s is not an Exif tag of this runtime" % (tag,))
        return found

    def hasAttribute(self, tag):
        ifd, number, _kind = self._known(tag)
        return (ifd, number) in self._tags

    def getAttribute(self, tag):
        ifd, number, _kind = self._known(tag)
        entry = self._tags.get((ifd, number))
        if entry is None:
            return None
        kind, values = entry
        if tag in _EXIF_AS_DECIMAL:
            return repr(self._double(kind, values))
        if tag == "GPSTimeStamp" and kind == 5 and len(values) == 3:
            return "%02d:%02d:%02d" % tuple(int(n / d) if d else 0 for n, d in values)
        if tag == "UserComment" and kind == 7:
            raw = values[0]
            charset, body = raw[:8], raw[8:]
            if charset.startswith(b"UNICODE"):
                return body.decode("utf-16-le" if not body.startswith(b"\xfe\xff") else "utf-16-be", "replace").rstrip("\0")
            return body.decode("utf-8", "replace").rstrip("\0")
        if kind == 7:
            return values[0].decode("latin-1")
        if kind == 5 or kind == 10:
            return ",".join("%d/%d" % pair for pair in values)
        return ",".join(str(v) for v in values)

    @staticmethod
    def _double(kind, values):
        first = values[0]
        if isinstance(first, tuple):
            return first[0] / first[1] if first[1] else 0.0
        return float(first)

    def getAttributeInt(self, tag, default):
        ifd, number, _kind = self._known(tag)
        entry = self._tags.get((ifd, number))
        if entry is None or entry[0] in (2, 7):
            return default
        first = entry[1][0]
        if isinstance(first, tuple):
            return int(first[0] / first[1]) if first[1] else default
        return int(first)

    def getAttributeDouble(self, tag, default):
        ifd, number, _kind = self._known(tag)
        entry = self._tags.get((ifd, number))
        if entry is None:
            return default
        if entry[0] == 2:
            try:
                return float(entry[1][0])
            except ValueError:
                return default
        if entry[0] == 7:
            return default
        return self._double(entry[0], entry[1])

    def setAttribute(self, tag, value):
        """None removes the tag. a value that does not fit the type of the tag is an IllegalArgumentException (android ignores it)"""
        ifd, number, kind = self._known(tag)
        if value is None:
            self._tags.pop((ifd, number), None)
            return
        self._tags[(ifd, number)] = (kind, self._parse(tag, kind, str(value)))

    @staticmethod
    def _parse(tag, kind, text):
        from fractions import Fraction
        from java.lang import IllegalArgumentException
        try:
            if kind == 2:
                return [text]
            if kind == 7:
                return [b"ASCII\0\0\0" + text.encode("utf-8")] if tag == "UserComment" else [text.encode("latin-1")]
            parts = text.split(",")
            if kind in (3, 4, 1):
                numbers = [int(p) for p in parts]
                limit = {1: 255, 3: 65535, 4: 4294967295}[kind]
                if any(n < 0 or n > limit for n in numbers):
                    raise ValueError("out of range")
                return numbers
            pairs = []
            for part in parts:
                if "/" in part:
                    num, den = part.split("/")
                    pairs.append((int(num), int(den)))
                else:
                    ratio = Fraction(part).limit_denominator(1 << 24)
                    pairs.append((ratio.numerator, ratio.denominator))
            if any(n < 0 or n > 4294967295 or d < 0 or d > 4294967295 for n, d in pairs):
                raise ValueError("out of range")
            return pairs
        except (ValueError, ArithmeticError, UnicodeEncodeError) as error:
            raise IllegalArgumentException("%r is not a value of the Exif tag %s: %s" % (text, tag, error)) from error

    def getLatLong(self):
        """[latitude, longitude] in degrees, or None when the file has no complete position"""
        def degrees(tag, ref, negative):
            entry, sign = self._tags.get(("gps", _EXIF_TAGS[tag][1])), self._tags.get(("gps", _EXIF_TAGS[ref][1]))
            if entry is None or sign is None or entry[0] != 5 or len(entry[1]) != 3 or any(d == 0 for _n, d in entry[1]):
                return None
            (dn, dd), (mn, md), (sn, sd) = entry[1]
            value = dn / dd + mn / md / 60.0 + sn / sd / 3600.0
            return -value if sign[1][0] == negative else value
        lat, lon = degrees("GPSLatitude", "GPSLatitudeRef", "S"), degrees("GPSLongitude", "GPSLongitudeRef", "W")
        return [lat, lon] if lat is not None and lon is not None else None

    def getRotationDegrees(self):
        return {6: 90, 3: 180, 8: 270, 5: 90, 7: 270}.get(self.getAttributeInt("Orientation", 1), 0)

    def hasThumbnail(self):
        return False

    def saveAttributes(self):
        import os
        import tempfile
        if not self._jpeg:
            raise _exif_error("only jpeg files can be saved")
        data = self._read_file()
        if data[:2] != b"\xff\xd8":
            raise _exif_error("the file is no longer a jpeg")
        directories = {}
        for (ifd, tag), entry in self._tags.items():
            directories.setdefault(ifd, {})[tag] = entry
        block = b"Exif\0\0" + _exif_build_tiff(directories) if self._tags else b""
        if block and len(block) + 2 > 65535:
            raise _exif_error("the Exif block of %d bytes does not fit one jpeg segment" % len(block))
        head, tail, insert = 2, 2, None
        existing = None
        for marker, start, end in self._segments(data):
            if marker == 0xE1 and data[start + 4:start + 10] == b"Exif\0\0":
                existing = (start, end)
                break
            if marker == 0xE0 and insert is None:
                insert = end
        if existing is not None:
            head, tail = existing
        else:
            head = tail = insert if insert is not None else 2
        segment = b"\xff\xe1" + (len(block) + 2).to_bytes(2, "big") + block if block else b""
        result = data[:head] + segment + data[tail:]
        folder = os.path.dirname(os.path.abspath(self._path))
        descriptor, staging = tempfile.mkstemp(dir=folder, prefix=".exif-")
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(result)
            os.chmod(staging, os.stat(self._path).st_mode & 0o7777)
            os.replace(staging, self._path)
        except OSError as error:
            try:
                os.unlink(staging)
            except OSError:
                pass
            raise _exif_error(str(error)) from error


for _name in _EXIF_TAGS:
    setattr(ExifInterface, _exif_constant(_name), _name)
