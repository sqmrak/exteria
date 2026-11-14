"""android.net: the address of a file the app handed to a plugin"""

from urllib.parse import quote, unquote, urlsplit

from java.lang import NullPointerException, Object


class Uri(Object):
    """a parsed address. the only schemes a plugin meets here are file (a picture the person chose, see android.content.ContentResolver)
    and the web ones it builds itself"""

    def __init__(self, text):
        self._text = str(text)
        self._parts = urlsplit(self._text)

    @staticmethod
    def parse(text):
        if text is None:
            raise NullPointerException("uriString")
        return Uri(text)

    @staticmethod
    def fromFile(file):
        return Uri("file://" + quote(file.getAbsolutePath(), safe="/"))

    def getScheme(self):
        return self._parts.scheme or None

    def getAuthority(self):
        return self._parts.netloc or None

    def getHost(self):
        return self._parts.hostname

    def getPath(self):
        return unquote(self._parts.path) if self._parts.path else None

    def getLastPathSegment(self):
        path = self.getPath()
        return path.rstrip("/").rsplit("/", 1)[-1] if path else None

    def getQuery(self):
        return self._parts.query or None

    def toString(self):
        return self._text

    def equals(self, other):
        return isinstance(other, Uri) and other._text == self._text

    def hashCode(self):
        return hash(self._text) & 0x7FFFFFFF

    __str__ = toString
    __repr__ = toString
