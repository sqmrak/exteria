"""java.net.URL: parsing and a plain read of the body over urllib, which verifies the certificate chain and hostname"""
import urllib.parse
import urllib.request

from java.lang import Object


class MalformedURLException(Exception):
    pass


class URL(Object):
    def __init__(self, spec):
        parts = urllib.parse.urlsplit(str(spec))
        if not parts.scheme or not parts.netloc:
            raise MalformedURLException("no protocol or host: %s" % spec)
        self._spec = str(spec)
        self._parts = parts

    def getProtocol(self):
        return self._parts.scheme

    def getHost(self):
        return self._parts.hostname or ""

    def getPort(self):
        return self._parts.port if self._parts.port is not None else -1

    def getPath(self):
        return self._parts.path

    def getQuery(self):
        return self._parts.query or None

    def toExternalForm(self):
        return self._spec

    def openStream(self):
        """the response, a file-like object of bytes. only http and https are opened, urllib would also take file:"""
        if self._parts.scheme not in ("http", "https"):
            raise MalformedURLException("unsupported protocol: " + self._parts.scheme)
        return urllib.request.urlopen(self._spec)

    toString = toExternalForm
    __str__ = toExternalForm
