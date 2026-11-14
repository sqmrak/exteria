"""java.net and javax.net.ssl: URLEncoder, URLDecoder, URI, URL, InetAddress, Socket, ServerSocket, HttpURLConnection

sockets are the python sockets of the process, so they follow the network of the app (the vpn of the app included).
tls is the python ssl module with the default context: the chain is checked against the bundle in SSL_CERT_FILE and the
host name is checked. a program may add checks (a TrustManager or a HostnameVerifier it supplies is not consulted, since
the default checks already ran) but it cannot turn the default checks off: a trust-all manager written for android
leaves the connection verified here. HttpURLConnection follows redirects as the android client does (up to 20, across
http and https), asks for gzip itself and hands the body over decoded, and answers any status of 400 or more with a
FileNotFoundException from getInputStream, as android does"""

import http.client
import re
import socket
import threading
import zlib

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jstring, string_hash
from .jio import File, FileInputStream, InputStream, OutputStream, _check_range, to_java_bytes, to_py_bytes
from .jlang import Object, jstr, pystr
from .jmap import LinkedHashMap
from .jutil import ArrayList, ImmutableList, check_nonnull

MAX_REDIRECTS = 20
MAX_REQUEST_BODY = 64 * 1024 * 1024
USER_AGENT = "Dalvik/2.1.0 (Linux; U; Android; exteria)"


def _define_exceptions(table):
    pending = [line.split() for line in table.strip().splitlines()]
    for name, parent in pending:
        py = type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__})
        host_class(name)(py)


_define_exceptions("""
java.net.BindException java.net.SocketException
java.net.NoRouteToHostException java.net.SocketException
java.net.PortUnreachableException java.net.SocketException
java.net.ProtocolException java.io.IOException
java.net.HttpRetryException java.io.IOException
java.net.UnknownServiceException java.io.IOException
javax.net.ssl.SSLException java.io.IOException
javax.net.ssl.SSLHandshakeException javax.net.ssl.SSLException
javax.net.ssl.SSLPeerUnverifiedException javax.net.ssl.SSLException
javax.net.ssl.SSLProtocolException javax.net.ssl.SSLException
javax.net.ssl.SSLKeyException javax.net.ssl.SSLException
""")


def _throw(name, message=None):
    runtime.throw_new(name, message)


def _io_failure(error, host=None):
    """the java exception for a python network error"""
    import ssl
    if isinstance(error, socket.timeout):
        _throw("java.net.SocketTimeoutException", "failed to connect to %s" % host if host else "Read timed out")
    if isinstance(error, socket.gaierror):
        _throw("java.net.UnknownHostException", 'Unable to resolve host "%s": No address associated with hostname' % host)
    if isinstance(error, ssl.SSLCertVerificationError):
        _throw("javax.net.ssl.SSLHandshakeException", error.verify_message or str(error))
    if isinstance(error, ssl.SSLError):
        _throw("javax.net.ssl.SSLException", str(error))
    if isinstance(error, ConnectionRefusedError):
        _throw("java.net.ConnectException", "Connection refused")
    if isinstance(error, (ConnectionResetError, BrokenPipeError)):
        _throw("java.net.SocketException", "Connection reset")
    _throw("java.net.SocketException", str(error))


_UNRESERVED = frozenset(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_")


@host_class("java.net.URLEncoder", final=True)
class URLEncoder(Object):
    @jstatic("encode", "(Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("encode", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("encode", "(Ljava/lang/String;Ljava/nio/charset/Charset;)Ljava/lang/String;")
    def encode(text, charset="UTF-8"):
        name = _charset(charset)
        out = []
        for char in pystr(check_nonnull(text)):
            if char == " ":
                out.append("+")
            elif ord(char) < 128 and ord(char) in _UNRESERVED:
                out.append(char)
            else:
                out.append("".join("%%%02X" % b for b in char.encode(name)))
        return "".join(out)


@host_class("java.net.URLDecoder", final=True)
class URLDecoder(Object):
    @jstatic("decode", "(Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("decode", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("decode", "(Ljava/lang/String;Ljava/nio/charset/Charset;)Ljava/lang/String;")
    def decode(text, charset="UTF-8"):
        name = _charset(charset)
        text = check_nonnull(text)
        out = bytearray()
        pos = 0
        while pos < len(text):
            char = text[pos]
            if char == "+":
                out += b" "
                pos += 1
            elif char == "%":
                digits = text[pos + 1:pos + 3]
                if len(digits) < 2 or not all(c in "0123456789abcdefABCDEF" for c in digits):
                    _throw("java.lang.IllegalArgumentException",
                           "URLDecoder: Illegal hex characters in escape (%) pattern - " + (
                               "Error at index %d in: \"%s\"" % (0, digits)))
                out.append(int(digits, 16))
                pos += 3
            else:
                out += char.encode("utf-16-le", "surrogatepass").decode("utf-16-le", "replace").encode(name) \
                    if ord(char) > 127 else char.encode("ascii")
                pos += 1
        return jstr(out.decode(name, "replace"))


def _charset(charset):
    name = charset if isinstance(charset, str) else charset.name()
    try:
        import codecs
        return codecs.lookup(pystr(name)).name
    except LookupError:
        _throw("java.io.UnsupportedEncodingException", name)


_URI = re.compile(r"^(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?\Z", re.S)
_ILLEGAL = re.compile(r'[\x00-\x20"<>\\^`{|}\x7f]')


def _syntax_error(reason, text, index=-1):
    message = reason + (" at index %d" % index if index >= 0 else "") + ": " + text
    error = runtime.make_throwable(lookup_host("java.net.URISyntaxException").py, message)
    error._reason = reason
    error._input = text
    error._index = index
    raise error


def _decode_percent(text):
    """the text with its %XX escapes read as utf-8 bytes, as URI.getPath and the other decoded getters do"""
    if text is None or "%" not in text:
        return text
    out = []
    raw = bytearray()
    pos = 0
    while pos < len(text):
        char = text[pos]
        if char == "%" and re.match(r"[0-9a-fA-F]{2}\Z", text[pos + 1:pos + 3]):
            raw.append(int(text[pos + 1:pos + 3], 16))
            pos += 3
            continue
        if raw:
            out.append(raw.decode("utf-8", "replace"))
            raw.clear()
        out.append(char)
        pos += 1
    if raw:
        out.append(raw.decode("utf-8", "replace"))
    return jstr("".join(out))


def _remove_dots(path):
    """the path without . and .. segments; a .. that has nothing to remove stays, as in URI.normalize"""
    out = []
    segments = path.split("/")
    for index, segment in enumerate(segments):
        last = index == len(segments) - 1
        if segment == ".":
            if last:
                out.append("")
        elif segment == "..":
            if out and out[-1] not in ("", ".."):
                out.pop()
            else:
                out.append("..")
            if last:
                out.append("")
        else:
            out.append(segment)
    return "/".join(out)


@host_class("java.net.URI", interfaces=("java.lang.Comparable", "java.io.Serializable"))
class URI(Object):
    def __init__(self, text=None, *parts):
        if parts:
            text = _compose(text, *parts)
        self._text = check_nonnull(text)
        self._parse()

    def _parse(self):
        text = self._text
        match = _ILLEGAL.search(text)
        if match is not None:
            _syntax_error("Illegal character in " + _region(text, match.start()), text, match.start())
        found = _URI.match(text)
        scheme, authority, path, query, fragment = found.groups()
        if scheme is not None and not re.match(r"[A-Za-z][A-Za-z0-9+.-]*\Z", scheme):
            _syntax_error("Illegal character in scheme name", text, 0)
        if scheme is None and text.startswith(":"):
            _syntax_error("Expected scheme name", text, 0)
        self._scheme = scheme
        self._opaque = scheme is not None and authority is None and not path.startswith("/") and path != ""
        self._authority = authority
        self._path = path if not self._opaque else None
        self._ssp_raw = None
        if self._opaque:
            self._ssp_raw = path + ("?" + query if query is not None else "")
            query = None
        self._query = query
        self._fragment = fragment
        self._user = self._host = None
        self._port = -1
        if authority:
            userinfo, _, hostport = authority.rpartition("@")
            self._user = userinfo if _ else None
            host, port = hostport, ""
            if hostport.startswith("["):
                end = hostport.find("]")
                host = hostport[:end + 1]
                port = hostport[end + 2:] if hostport[end + 1:end + 2] == ":" else ""
            elif ":" in hostport:
                host, _, port = hostport.rpartition(":")
            if host and port.isdigit() or not port:
                self._host = host or None
                self._port = int(port) if port else -1
            else:
                self._host = None
        if scheme is not None and authority is None and not self._opaque and path == "":
            _syntax_error("Expected scheme-specific part", text, len(scheme) + 1)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, text):
        URI.__init__(self, text)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V")
    def _init3(self, scheme, ssp, fragment):
        URI.__init__(self, scheme, ssp, fragment)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;"
                       "Ljava/lang/String;)V")
    def _init7(self, scheme, user, host, port, path, query, fragment):
        URI.__init__(self, scheme, user, host, port, path, query, fragment)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V")
    def _init5(self, scheme, host, path, query, fragment):
        URI.__init__(self, scheme, host, path, query, fragment)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V")
    def _init4(self, scheme, host, path, fragment):
        URI.__init__(self, scheme, host, path, fragment)

    @jstatic("create", "(Ljava/lang/String;)Ljava/net/URI;")
    def create(text):
        try:
            return URI(text)
        except lookup_host("java.net.URISyntaxException").py as error:
            raise runtime.make_throwable(lookup_host("java.lang.IllegalArgumentException").py, error.getMessage()
                                         ) from None

    @jmethod("getScheme", "()Ljava/lang/String;")
    def getScheme(self):
        return self._scheme

    @jmethod("isAbsolute", "()Z")
    def isAbsolute(self):
        return 1 if self._scheme is not None else 0

    @jmethod("isOpaque", "()Z")
    def isOpaque(self):
        return 1 if self._opaque else 0

    @jmethod("getRawSchemeSpecificPart", "()Ljava/lang/String;")
    def getRawSchemeSpecificPart(self):
        if self._opaque:
            return self._ssp_raw
        rest = self._text.split("#", 1)[0]
        return rest[len(self._scheme) + 1:] if self._scheme is not None else rest

    @jmethod("getSchemeSpecificPart", "()Ljava/lang/String;")
    def getSchemeSpecificPart(self):
        return _decode_percent(self.getRawSchemeSpecificPart())

    @jmethod("getRawAuthority", "()Ljava/lang/String;")
    def getRawAuthority(self):
        return self._authority or None

    @jmethod("getAuthority", "()Ljava/lang/String;")
    def getAuthority(self):
        return _decode_percent(self._authority or None)

    @jmethod("getRawUserInfo", "()Ljava/lang/String;")
    def getRawUserInfo(self):
        return self._user

    @jmethod("getUserInfo", "()Ljava/lang/String;")
    def getUserInfo(self):
        return _decode_percent(self._user)

    @jmethod("getHost", "()Ljava/lang/String;")
    def getHost(self):
        return self._host

    @jmethod("getPort", "()I")
    def getPort(self):
        return self._port

    @jmethod("getRawPath", "()Ljava/lang/String;")
    def getRawPath(self):
        return self._path

    @jmethod("getPath", "()Ljava/lang/String;")
    def getPath(self):
        return _decode_percent(self._path)

    @jmethod("getRawQuery", "()Ljava/lang/String;")
    def getRawQuery(self):
        return self._query

    @jmethod("getQuery", "()Ljava/lang/String;")
    def getQuery(self):
        return _decode_percent(self._query)

    @jmethod("getRawFragment", "()Ljava/lang/String;")
    def getRawFragment(self):
        return self._fragment

    @jmethod("getFragment", "()Ljava/lang/String;")
    def getFragment(self):
        return _decode_percent(self._fragment)

    @jmethod("normalize", "()Ljava/net/URI;")
    def normalize(self):
        if self._opaque or not self._path:
            return self
        path = _remove_dots(self._path)
        if path == self._path:
            return self
        return URI(self._rebuild(path=path))

    def _rebuild(self, path=None, scheme=True, fragment=True):
        out = []
        if scheme and self._scheme is not None:
            out.append(self._scheme + ":")
        if self._authority is not None:
            out.append("//" + self._authority)
        out.append(self._path if path is None else path)
        if self._query is not None:
            out.append("?" + self._query)
        if fragment and self._fragment is not None:
            out.append("#" + self._fragment)
        return "".join(out)

    @jmethod("resolve", "(Ljava/net/URI;)Ljava/net/URI;")
    @jmethod("resolve", "(Ljava/lang/String;)Ljava/net/URI;")
    def resolve(self, other):
        if isinstance(other, str):
            other = URI.create(other)
        if other._scheme is not None or self._opaque:
            return other
        if not other._path and other._authority is None and other._query is None:
            if other._fragment is None:
                return self
            return URI(self._rebuild(fragment=False) + "#" + other._fragment)
        out = []
        if self._scheme is not None:
            out.append(self._scheme + ":")
        if other._authority is not None:
            out.append("//" + other._authority + _remove_dots(other._path))
        else:
            if self._authority is not None:
                out.append("//" + self._authority)
            if other._path.startswith("/"):
                path = other._path
            else:
                base = self._path[:self._path.rfind("/") + 1] if self._path else ""
                if not base and self._authority is not None:
                    base = "/"
                path = base + other._path
            out.append(_remove_dots(path))
        if other._query is not None:
            out.append("?" + other._query)
        if other._fragment is not None:
            out.append("#" + other._fragment)
        return URI("".join(out))

    @jmethod("relativize", "(Ljava/net/URI;)Ljava/net/URI;")
    def relativize(self, other):
        if self._opaque or other._opaque or self._scheme != other._scheme or self._authority != other._authority:
            return other
        base = self._path if self._path.endswith("/") else self._path + "/"
        if not other._path.startswith(base) and other._path != self._path:
            return other
        rest = other._path[len(self._path):].lstrip("/") if other._path != self._path else ""
        return URI(rest + ("?" + other._query if other._query is not None else "")
                   + ("#" + other._fragment if other._fragment is not None else ""))

    @jmethod("toURL", "()Ljava/net/URL;")
    def toURL(self):
        if self._scheme is None:
            _throw("java.lang.IllegalArgumentException", "URI is not absolute")
        return URL(self._text)

    @jmethod("toString", "()Ljava/lang/String;")
    @jmethod("toASCIIString", "()Ljava/lang/String;")
    def toString(self):
        return self._text

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        if not isinstance(other, URI):
            return 0
        if self._scheme and other._scheme and self._scheme.lower() != other._scheme.lower():
            return 0
        return 1 if _canonical(self) == _canonical(other) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return string_hash(_canonical(self))

    @jmethod("compareTo", "(Ljava/net/URI;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        a, b = _canonical(self), _canonical(check_nonnull(other))
        return (a > b) - (a < b)


def _canonical(uri):
    scheme = uri._scheme.lower() if uri._scheme else ""
    host = (uri._authority or "")
    return scheme + "|" + (uri._ssp_raw or "") + "|" + host.lower() + "|" + (uri._path or "") + "|" + (
        uri._query or "") + "|" + (uri._fragment or "")


def _region(text, index):
    """the name of the URI component the character at index belongs to, for the syntax error message"""
    hash_at = text.find("#")
    if 0 <= hash_at < index:
        return "fragment"
    question = text.find("?")
    if 0 <= question < index:
        return "query"
    if re.match(r"[^:/?#]+://", text):
        start = text.find("//") + 2
        end = min([i for i in (text.find("/", start), question, hash_at) if i != -1] or [len(text)])
        if start <= index < end:
            return "authority"
    return "path"


def _quote_part(text, extra=""):
    """a URI component for the multi-argument constructors: characters that may not appear are escaped as utf-8,
    non-ascii characters stay as they are, and a percent sign is always escaped"""
    out = []
    for char in text:
        if ord(char) > 127 or char.isalnum() or char in "-_.!~*'()" + extra:
            out.append(char)
        else:
            out.append("".join("%%%02X" % b for b in char.encode("utf-8")))
    return "".join(out)


def _compose(scheme, *parts):
    """the text a multi-part URI constructor stands for"""
    out = []
    if len(parts) == 2 and parts[0] is not None and not isinstance(parts[0], int):
        ssp, fragment = parts
        if scheme is not None:
            out.append(scheme + ":")
        out.append(_quote_part(ssp, ":/?[]@;&=+$,") if ssp else "")
    else:
        if len(parts) == 6:
            user, host, port, path, query, fragment = parts
            authority = (_quote_part(user, ":;&=+$,") + "@" if user else "") + (host or "") + (
                ":%d" % port if port is not None and port >= 0 else "")
        elif len(parts) == 4:
            host, path, query, fragment = parts
            authority = host
        else:
            host, path, fragment = parts
            query = None
            authority = host
        if scheme is not None:
            out.append(scheme + ":")
        if authority:
            out.append("//" + authority)
        out.append(_quote_part(path or "", "/@:&=+$,;"))
        if query is not None:
            out.append("?" + _quote_part(query, "/?:@&=+$,;[]"))
    if fragment is not None:
        out.append("#" + _quote_part(fragment, "/?:@&=+$,;[]"))
    return "".join(out)


@host_class("java.net.URISyntaxException")
class URISyntaxException(lookup_host("java.lang.Exception").py):
    _reason = None
    _input = None
    _index = -1

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;I)V")
    def _init(self, text, reason, index=-1):
        self._input = text
        self._reason = reason
        self._index = index
        self._message = reason + (" at index %d" % index if index >= 0 else "") + ": " + text
        self._cause = None

    @jmethod("getInput", "()Ljava/lang/String;")
    def getInput(self):
        return self._input

    @jmethod("getReason", "()Ljava/lang/String;")
    def getReason(self):
        return self._reason

    @jmethod("getIndex", "()I")
    def getIndex(self):
        return self._index


_DEFAULT_PORTS = {"http": 80, "https": 443, "ftp": 21, "file": -1, "jar": -1}


@host_class("java.net.URL", interfaces=("java.io.Serializable",))
class URL(Object):
    def __init__(self, first, spec=None, port=None, file=None):
        if isinstance(first, URL):
            context = first
            text = check_nonnull(spec)
            uri = None
            if re.match(r"[A-Za-z][A-Za-z0-9+.-]*:", text) is None:
                uri = context._uri().resolve(URI.create(text.replace(" ", "%20")))
                text = uri.toString()
        elif port is not None:
            host = spec
            text = "%s://%s%s%s" % (first, host, ":%d" % port if port >= 0 else "", file or "")
        else:
            text = check_nonnull(first)
        self._parse(text)

    def _parse(self, text):
        found = re.match(r"([A-Za-z][A-Za-z0-9+.-]*):", text)
        if found is None:
            _throw("java.net.MalformedURLException", "no protocol: " + text)
        scheme = found.group(1).lower()
        if scheme not in _DEFAULT_PORTS:
            _throw("java.net.MalformedURLException", "unknown protocol: " + scheme)
        self._text = text
        self._protocol = scheme
        rest = text[found.end():]
        ref = None
        if "#" in rest:
            rest, ref = rest.split("#", 1)
        self._ref = ref
        authority = ""
        if rest.startswith("//"):
            end = len(rest)
            for mark in "/?":
                at = rest.find(mark, 2)
                if at != -1:
                    end = min(end, at)
            authority = rest[2:end]
            rest = rest[end:]
        self._authority = authority
        userinfo, at, hostport = authority.rpartition("@")
        self._userinfo = userinfo if at else None
        host, port = hostport, ""
        if hostport.startswith("["):
            close = hostport.find("]")
            host = hostport[:close + 1]
            port = hostport[close + 2:]
        elif ":" in hostport:
            host, _, port = hostport.rpartition(":")
        if port and not port.isdigit():
            _throw("java.net.MalformedURLException", "Invalid port number :" + port)
        self._host = host
        self._port = int(port) if port else -1
        self._query = None
        if "?" in rest:
            rest, self._query = rest.split("?", 1)
        self._path = rest
        if scheme in ("http", "https") and not authority:
            _throw("java.net.MalformedURLException", "Expected authority at index %d: %s" % (found.end(), text))

    def _uri(self):
        return URI.create(self._text.split("#", 1)[0] + ("#" + self._ref if self._ref is not None else ""))

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, text):
        URL.__init__(self, text)

    @jmethod("<init>", "(Ljava/net/URL;Ljava/lang/String;)V")
    def _init_context(self, context, spec):
        if context is None:
            URL.__init__(self, spec)
        else:
            URL.__init__(self, context, spec)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;)V")
    def _init4(self, protocol, host, port, file):
        URL.__init__(self, protocol, host, port, file)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V")
    def _init3(self, protocol, host, file):
        URL.__init__(self, protocol, host, -1, file)

    @jmethod("getProtocol", "()Ljava/lang/String;")
    def getProtocol(self):
        return self._protocol

    @jmethod("getHost", "()Ljava/lang/String;")
    def getHost(self):
        return self._host

    @jmethod("getPort", "()I")
    def getPort(self):
        return self._port

    @jmethod("getDefaultPort", "()I")
    def getDefaultPort(self):
        return _DEFAULT_PORTS[self._protocol]

    @jmethod("getPath", "()Ljava/lang/String;")
    def getPath(self):
        return self._path

    @jmethod("getQuery", "()Ljava/lang/String;")
    def getQuery(self):
        return self._query

    @jmethod("getFile", "()Ljava/lang/String;")
    def getFile(self):
        return self._path + ("?" + self._query if self._query is not None else "")

    @jmethod("getRef", "()Ljava/lang/String;")
    def getRef(self):
        return self._ref

    @jmethod("getUserInfo", "()Ljava/lang/String;")
    def getUserInfo(self):
        return self._userinfo

    @jmethod("getAuthority", "()Ljava/lang/String;")
    def getAuthority(self):
        return self._authority or None

    @jmethod("toExternalForm", "()Ljava/lang/String;")
    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._text

    @jmethod("toURI", "()Ljava/net/URI;")
    def toURI(self):
        return URI(self._text)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, URL) and other._text.lower() == self._text.lower() else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return string_hash(self._text.lower())

    @jmethod("openConnection", "()Ljava/net/URLConnection;")
    @jmethod("openConnection", "(Ljava/net/Proxy;)Ljava/net/URLConnection;")
    def openConnection(self, proxy=None):
        if self._protocol == "https":
            return HttpsURLConnection(self)
        if self._protocol == "http":
            return HttpURLConnection(self)
        if self._protocol == "file":
            return _FileConnection(self)
        _throw("java.net.UnknownServiceException", "Unsupported protocol: " + self._protocol)

    @jmethod("openStream", "()Ljava/io/InputStream;")
    def openStream(self):
        return self.openConnection().getInputStream()


@host_class("java.net.Proxy")
class Proxy(Object):
    NO_PROXY = None

    def __init__(self, kind=None, address=None):
        self._kind = kind
        self._address = address

    @jmethod("<init>", "(Ljava/net/Proxy$Type;Ljava/net/SocketAddress;)V")
    def _init(self, kind, address):
        Proxy.__init__(self, kind, address)

    @jmethod("address", "()Ljava/net/SocketAddress;")
    def address(self):
        return self._address

    @jmethod("type", "()Ljava/net/Proxy$Type;")
    def type(self):
        return self._kind


@host_class("java.net.Proxy$Type", final=True)
class ProxyType(Object):
    def __init__(self, name):
        self._name = name

    @jmethod("name", "()Ljava/lang/String;")
    @jmethod("toString", "()Ljava/lang/String;")
    def name(self):
        return self._name


ProxyType.DIRECT = ProxyType("DIRECT")
ProxyType.HTTP = ProxyType("HTTP")
ProxyType.SOCKS = ProxyType("SOCKS")
Proxy.NO_PROXY = Proxy(ProxyType.DIRECT, None)


@host_class("java.net.SocketAddress", interfaces=("java.io.Serializable",))
class SocketAddress(Object):
    pass


@host_class("java.net.InetAddress", interfaces=("java.io.Serializable",))
class InetAddress(Object):
    def __init__(self, host=None, address=None):
        self._host = host
        self._addr = address

    @staticmethod
    def _make(host, address):
        cls = Inet6Address if ":" in address else Inet4Address
        return cls(host, address)

    @jstatic("getByName", "(Ljava/lang/String;)Ljava/net/InetAddress;")
    def getByName(host):
        return InetAddress.getAllByName(host)[0]

    @jstatic("getAllByName", "(Ljava/lang/String;)[Ljava/net/InetAddress;")
    def getAllByName(host):
        if not host:
            found = [InetAddress._make(None, "127.0.0.1")]
        else:
            literal = host.strip("[]")
            try:
                socket.inet_pton(socket.AF_INET6 if ":" in literal else socket.AF_INET, literal)
                found = [InetAddress._make(None, literal)]
            except (OSError, ValueError):
                try:
                    infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
                except OSError:
                    _throw("java.net.UnknownHostException", 'Unable to resolve host "%s": No address associated '
                           'with hostname' % host)
                seen = []
                found = []
                for info in infos:
                    address = info[4][0]
                    if address not in seen:
                        seen.append(address)
                        found.append(InetAddress._make(host, address))
        array = runtime.new_array("[Ljava/net/InetAddress;", 0)
        array.extend(found)
        return array

    @jstatic("getByAddress", "([B)Ljava/net/InetAddress;")
    @jstatic("getByAddress", "(Ljava/lang/String;[B)Ljava/net/InetAddress;")
    def getByAddress(first, second=None):
        host, raw = (None, first) if second is None else (first, second)
        data = to_py_bytes(raw)
        if len(data) == 4:
            return InetAddress._make(host, socket.inet_ntop(socket.AF_INET, data))
        if len(data) == 16:
            return InetAddress._make(host, socket.inet_ntop(socket.AF_INET6, data))
        _throw("java.net.UnknownHostException", "addr is of illegal length")

    @jstatic("getLocalHost", "()Ljava/net/InetAddress;")
    def getLocalHost():
        name = socket.gethostname()
        try:
            return InetAddress.getByName(name)
        except lookup_host("java.net.UnknownHostException").py:
            return InetAddress._make(name, "127.0.0.1")

    @jstatic("getLoopbackAddress", "()Ljava/net/InetAddress;")
    def getLoopbackAddress():
        return InetAddress._make("localhost", "127.0.0.1")

    @jmethod("getHostAddress", "()Ljava/lang/String;")
    def getHostAddress(self):
        return self._addr

    @jmethod("getHostName", "()Ljava/lang/String;")
    @jmethod("getCanonicalHostName", "()Ljava/lang/String;")
    def getHostName(self):
        if self._host is None:
            try:
                self._host = socket.gethostbyaddr(self._addr)[0]
            except OSError:
                self._host = self._addr
        return self._host

    @jmethod("getAddress", "()[B")
    def getAddress(self):
        family = socket.AF_INET6 if ":" in self._addr else socket.AF_INET
        return to_java_bytes(socket.inet_pton(family, self._addr))

    @jmethod("isLoopbackAddress", "()Z")
    def isLoopbackAddress(self):
        return 1 if self._addr.startswith("127.") or self._addr == "::1" else 0

    @jmethod("isAnyLocalAddress", "()Z")
    def isAnyLocalAddress(self):
        return 1 if self._addr in ("0.0.0.0", "::") else 0

    @jmethod("isSiteLocalAddress", "()Z")
    def isSiteLocalAddress(self):
        import ipaddress
        address = ipaddress.ip_address(self._addr)
        return 1 if address.is_private and not address.is_loopback and not address.is_link_local else 0

    @jmethod("isLinkLocalAddress", "()Z")
    def isLinkLocalAddress(self):
        import ipaddress
        return 1 if ipaddress.ip_address(self._addr).is_link_local else 0

    @jmethod("isMulticastAddress", "()Z")
    def isMulticastAddress(self):
        import ipaddress
        return 1 if ipaddress.ip_address(self._addr).is_multicast else 0

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, InetAddress) and other._addr == self._addr else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return string_hash(self._addr)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return (self._host or "") + "/" + self._addr


@host_class("java.net.Inet4Address")
class Inet4Address(InetAddress):
    pass


@host_class("java.net.Inet6Address")
class Inet6Address(InetAddress):
    pass


@host_class("java.net.InetSocketAddress")
class InetSocketAddress(SocketAddress):
    def __init__(self, first=None, second=None):
        self._unresolved = False
        if isinstance(first, int) and second is None:
            first, second = None, first
        if not 0 <= second <= 65535:
            _throw("java.lang.IllegalArgumentException", "port out of range:%d" % second)
        self._port = second
        if first is None:
            self._address = InetAddress._make(None, "0.0.0.0")
            self._host = "0.0.0.0"
        elif isinstance(first, InetAddress):
            self._address = first
            self._host = first.getHostName() if first._host else first._addr
        else:
            self._host = first
            try:
                self._address = InetAddress.getByName(first)
            except lookup_host("java.net.UnknownHostException").py:
                self._address = None
                self._unresolved = True

    @jmethod("<init>", "(I)V")
    def _init_port(self, port):
        InetSocketAddress.__init__(self, None, port)

    @jmethod("<init>", "(Ljava/lang/String;I)V")
    @jmethod("<init>", "(Ljava/net/InetAddress;I)V")
    def _init(self, host, port):
        InetSocketAddress.__init__(self, host, port)

    @jstatic("createUnresolved", "(Ljava/lang/String;I)Ljava/net/InetSocketAddress;")
    def createUnresolved(host, port):
        address = InetSocketAddress.__new__(InetSocketAddress)
        address._host, address._port, address._address, address._unresolved = host, port, None, True
        return address

    @jmethod("getPort", "()I")
    def getPort(self):
        return self._port

    @jmethod("getAddress", "()Ljava/net/InetAddress;")
    def getAddress(self):
        return self._address

    @jmethod("getHostName", "()Ljava/lang/String;")
    @jmethod("getHostString", "()Ljava/lang/String;")
    def getHostName(self):
        return self._host

    @jmethod("isUnresolved", "()Z")
    def isUnresolved(self):
        return 1 if self._unresolved else 0

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        if self._unresolved:
            return "%s/<unresolved>:%d" % (self._host, self._port)
        return "%s:%d" % (self._address.toString(), self._port)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, InetSocketAddress) and other._port == self._port \
            and other._host == self._host else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(string_hash(self._host or "") + self._port)


def _target(address):
    if address is None:
        runtime.throw_new("java.lang.IllegalArgumentException", "remoteAddr == null")
    if address._unresolved:
        _throw("java.net.UnknownHostException", address._host)
    return address._address._addr, address._port


class _SocketInput(InputStream):
    def __init__(self, owner):
        self._owner = owner

    def read_byte(self):
        data = self._recv(1)
        return data[0] if data else -1

    def _recv(self, count):
        sock = self._owner._sock
        if sock is None or self._owner._closed:
            _throw("java.net.SocketException", "Socket closed")
        if self._owner._in_shut:
            return b""
        try:
            return sock.recv(count)
        except socket.timeout:
            _throw("java.net.SocketTimeoutException", "Read timed out")
        except OSError as error:
            if self._owner._closed:
                _throw("java.net.SocketException", "Socket closed")
            _io_failure(error)

    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        data = self._recv(min(length, 65536))
        if not data:
            return -1
        buffer[offset:offset + len(data)] = [b - 256 if b > 127 else b for b in data]
        return len(data)

    def available(self):
        import select
        sock = self._owner._sock
        if sock is None or self._owner._closed:
            return 0
        ready, _, _ = select.select([sock], [], [], 0)
        if not ready:
            return 0
        try:
            return len(sock.recv(65536, socket.MSG_PEEK))
        except (OSError, ValueError):
            return 0

    def close(self):
        self._owner.close()


class _SocketOutput(OutputStream):
    def __init__(self, owner):
        self._owner = owner

    def write_byte(self, value):
        self._send(bytes((value & 0xFF,)))

    def _send(self, data):
        sock = self._owner._sock
        if sock is None or self._owner._closed:
            _throw("java.net.SocketException", "Socket closed")
        if self._owner._out_shut:
            _throw("java.net.SocketException", "Socket output is shutdown")
        try:
            sock.sendall(data)
        except socket.timeout:
            _throw("java.net.SocketTimeoutException", "Write timed out")
        except OSError as error:
            _io_failure(error)

    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._send(to_py_bytes(buffer, offset, length))

    def close(self):
        self._owner.close()


@host_class("java.net.Socket", interfaces=("java.io.Closeable",))
class Socket(Object):
    def __init__(self, first=None, second=None, proxy=None):
        self._sock = None
        self._closed = False
        self._connected = False
        self._timeout = 0.0
        self._remote = None
        self._in_shut = False
        self._out_shut = False
        self._options = {}
        if first is not None:
            if isinstance(first, InetAddress):
                first = InetSocketAddress(first, second)
            else:
                first = InetSocketAddress(first, second)
            self.connect(first)

    @jmethod("<init>", "()V")
    def _init0(self):
        Socket.__init__(self)

    @jmethod("<init>", "(Ljava/lang/String;I)V")
    @jmethod("<init>", "(Ljava/net/InetAddress;I)V")
    def _init2(self, host, port):
        Socket.__init__(self, host, port)

    @jmethod("<init>", "(Ljava/net/Proxy;)V")
    def _init_proxy(self, proxy):
        Socket.__init__(self)

    @jmethod("connect", "(Ljava/net/SocketAddress;)V")
    @jmethod("connect", "(Ljava/net/SocketAddress;I)V")
    def connect(self, address, timeout=0):
        if self._closed:
            _throw("java.net.SocketException", "Socket is closed")
        if self._connected:
            _throw("java.net.SocketException", "Already connected")
        host, port = _target(address)
        try:
            sock = socket.create_connection((host, port), timeout / 1000.0 if timeout else None)
        except OSError as error:
            _io_failure_connect(error, address)
        self._attach(sock, address)

    def _attach(self, sock, address):
        self._sock = sock
        self._remote = address
        self._connected = True
        sock.settimeout(self._timeout or None)
        for option, value in self._options.items():
            self._apply(option, value)

    def _apply(self, option, value):
        level, name = option
        try:
            self._sock.setsockopt(level, name, value)
        except OSError:
            pass

    @jmethod("getInputStream", "()Ljava/io/InputStream;")
    def getInputStream(self):
        self._need_connected()
        return _SocketInput(self)

    @jmethod("getOutputStream", "()Ljava/io/OutputStream;")
    def getOutputStream(self):
        self._need_connected()
        return _SocketOutput(self)

    def _need_connected(self):
        if self._closed:
            _throw("java.net.SocketException", "Socket is closed")
        if not self._connected:
            _throw("java.net.SocketException", "Socket is not connected")

    @jmethod("close", "()V")
    def close(self):
        if self._closed:
            return
        self._closed = True
        sock, self._sock = self._sock, None
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()

    @jmethod("shutdownInput", "()V")
    def shutdownInput(self):
        self._need_connected()
        self._in_shut = True
        try:
            self._sock.shutdown(socket.SHUT_RD)
        except OSError:
            pass

    @jmethod("shutdownOutput", "()V")
    def shutdownOutput(self):
        self._need_connected()
        self._out_shut = True
        try:
            self._sock.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    @jmethod("isClosed", "()Z")
    def isClosed(self):
        return 1 if self._closed else 0

    @jmethod("isConnected", "()Z")
    def isConnected(self):
        return 1 if self._connected else 0

    @jmethod("isInputShutdown", "()Z")
    def isInputShutdown(self):
        return 1 if self._in_shut else 0

    @jmethod("isOutputShutdown", "()Z")
    def isOutputShutdown(self):
        return 1 if self._out_shut else 0

    @jmethod("isBound", "()Z")
    def isBound(self):
        return 1 if self._connected else 0

    @jmethod("setSoTimeout", "(I)V")
    def setSoTimeout(self, millis):
        if millis < 0:
            _throw("java.lang.IllegalArgumentException", "timeout < 0")
        self._timeout = millis / 1000.0
        if self._sock is not None:
            self._sock.settimeout(self._timeout or None)

    @jmethod("getSoTimeout", "()I")
    def getSoTimeout(self):
        return int(self._timeout * 1000)

    def _option(self, level, name, flag):
        self._options[(level, name)] = 1 if flag else 0
        if self._sock is not None:
            self._apply((level, name), 1 if flag else 0)

    @jmethod("setTcpNoDelay", "(Z)V")
    def setTcpNoDelay(self, flag):
        self._option(socket.IPPROTO_TCP, socket.TCP_NODELAY, flag)

    @jmethod("setKeepAlive", "(Z)V")
    def setKeepAlive(self, flag):
        self._option(socket.SOL_SOCKET, socket.SO_KEEPALIVE, flag)

    @jmethod("setReuseAddress", "(Z)V")
    def setReuseAddress(self, flag):
        self._option(socket.SOL_SOCKET, socket.SO_REUSEADDR, flag)

    @jmethod("getTcpNoDelay", "()Z")
    def getTcpNoDelay(self):
        return self._options.get((socket.IPPROTO_TCP, socket.TCP_NODELAY), 0)

    @jmethod("getKeepAlive", "()Z")
    def getKeepAlive(self):
        return self._options.get((socket.SOL_SOCKET, socket.SO_KEEPALIVE), 0)

    @jmethod("setSoLinger", "(ZI)V")
    @jmethod("setReceiveBufferSize", "(I)V")
    @jmethod("setSendBufferSize", "(I)V")
    @jmethod("setTrafficClass", "(I)V")
    def setIgnoredOption(self, *args):
        return None

    @jmethod("getInetAddress", "()Ljava/net/InetAddress;")
    def getInetAddress(self):
        return self._remote._address if self._remote is not None else None

    @jmethod("getPort", "()I")
    def getPort(self):
        return self._remote._port if self._remote is not None else 0

    @jmethod("getRemoteSocketAddress", "()Ljava/net/SocketAddress;")
    def getRemoteSocketAddress(self):
        return self._remote

    @jmethod("getLocalPort", "()I")
    def getLocalPort(self):
        if self._sock is None:
            return -1
        return self._sock.getsockname()[1]

    @jmethod("getLocalAddress", "()Ljava/net/InetAddress;")
    def getLocalAddress(self):
        if self._sock is None:
            return InetAddress._make(None, "0.0.0.0")
        return InetAddress._make(None, self._sock.getsockname()[0])

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        if not self._connected:
            return "Socket[unconnected]"
        return "Socket[address=%s,port=%d,localPort=%d]" % (
            self._remote._address.toString(), self._remote._port, self.getLocalPort())


def _io_failure_connect(error, address):
    if isinstance(error, socket.timeout):
        _throw("java.net.SocketTimeoutException", "failed to connect to %s (port %d)" % (
            address._host, address._port))
    if isinstance(error, ConnectionRefusedError):
        _throw("java.net.ConnectException", "failed to connect to %s (port %d): Connection refused" % (
            address._host, address._port))
    if isinstance(error, socket.gaierror):
        _throw("java.net.UnknownHostException", address._host)
    _throw("java.net.ConnectException", "failed to connect to %s (port %d): %s" % (
        address._host, address._port, error))


@host_class("java.net.ServerSocket", interfaces=("java.io.Closeable",))
class ServerSocket(Object):
    def __init__(self, port=None, backlog=50, address=None):
        self._sock = None
        self._closed = False
        self._timeout = 0.0
        self._reuse = True
        if port is not None:
            self.bind(InetSocketAddress(address, port) if address is not None else InetSocketAddress(port), backlog)

    @jmethod("<init>", "()V")
    def _init0(self):
        ServerSocket.__init__(self)

    @jmethod("<init>", "(I)V")
    @jmethod("<init>", "(II)V")
    @jmethod("<init>", "(IILjava/net/InetAddress;)V")
    def _init(self, port, backlog=50, address=None):
        ServerSocket.__init__(self, port, backlog, address)

    @jmethod("bind", "(Ljava/net/SocketAddress;)V")
    @jmethod("bind", "(Ljava/net/SocketAddress;I)V")
    def bind(self, address, backlog=50):
        if self._closed:
            _throw("java.net.SocketException", "Socket is closed")
        if self._sock is not None:
            _throw("java.net.SocketException", "Already bound")
        host = address._address._addr if address is not None and not address._unresolved else "0.0.0.0"
        port = address._port if address is not None else 0
        family = socket.AF_INET6 if ":" in host else socket.AF_INET
        sock = socket.socket(family, socket.SOCK_STREAM)
        try:
            if self._reuse:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((host, port))
            sock.listen(backlog if backlog > 0 else 50)
        except OSError as error:
            sock.close()
            _throw("java.net.BindException", "bind failed: %s" % error)
        sock.settimeout(self._timeout or None)
        self._sock = sock

    @jmethod("accept", "()Ljava/net/Socket;")
    def accept(self):
        if self._closed:
            _throw("java.net.SocketException", "Socket is closed")
        if self._sock is None:
            _throw("java.net.SocketException", "Socket is not bound yet")
        try:
            conn, peer = self._sock.accept()
        except socket.timeout:
            _throw("java.net.SocketTimeoutException", "Accept timed out")
        except OSError as error:
            if self._closed:
                _throw("java.net.SocketException", "Socket closed")
            _io_failure(error)
        result = Socket()
        result._attach(conn, InetSocketAddress(InetAddress._make(None, peer[0]), peer[1]))
        return result

    @jmethod("close", "()V")
    def close(self):
        self._closed = True
        sock, self._sock = self._sock, None
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()

    @jmethod("isClosed", "()Z")
    def isClosed(self):
        return 1 if self._closed else 0

    @jmethod("isBound", "()Z")
    def isBound(self):
        return 1 if self._sock is not None else 0

    @jmethod("getLocalPort", "()I")
    def getLocalPort(self):
        return self._sock.getsockname()[1] if self._sock is not None else -1

    @jmethod("getInetAddress", "()Ljava/net/InetAddress;")
    def getInetAddress(self):
        return InetAddress._make(None, self._sock.getsockname()[0]) if self._sock is not None else None

    @jmethod("setSoTimeout", "(I)V")
    def setSoTimeout(self, millis):
        self._timeout = millis / 1000.0
        if self._sock is not None:
            self._sock.settimeout(self._timeout or None)

    @jmethod("getSoTimeout", "()I")
    def getSoTimeout(self):
        return int(self._timeout * 1000)

    @jmethod("setReuseAddress", "(Z)V")
    def setReuseAddress(self, flag):
        self._reuse = bool(flag)

    @jmethod("getReuseAddress", "()Z")
    def getReuseAddress(self):
        return 1 if self._reuse else 0


@host_class("javax.net.SocketFactory")
class SocketFactory(Object):
    @jstatic("getDefault", "()Ljavax/net/SocketFactory;")
    def getDefault():
        return _PlainSocketFactory()

    @jmethod("<init>", "()V")
    def _init(self):
        return None

    @jmethod("createSocket", "()Ljava/net/Socket;")
    @jmethod("createSocket", "(Ljava/lang/String;I)Ljava/net/Socket;")
    @jmethod("createSocket", "(Ljava/net/InetAddress;I)Ljava/net/Socket;")
    def createSocket(self, host=None, port=None):
        return Socket(host, port)


class _PlainSocketFactory(SocketFactory):
    pass


def _client_context():
    import ssl
    return ssl.create_default_context()


@host_class("javax.net.ssl.SSLSession")
class SSLSession(Object):
    def __init__(self, ssock):
        self._ssock = ssock

    @jmethod("getProtocol", "()Ljava/lang/String;")
    def getProtocol(self):
        return self._ssock.version()

    @jmethod("getCipherSuite", "()Ljava/lang/String;")
    def getCipherSuite(self):
        cipher = self._ssock.cipher()
        return cipher[0] if cipher else None

    @jmethod("getPeerHost", "()Ljava/lang/String;")
    def getPeerHost(self):
        return self._ssock.server_hostname

    @jmethod("isValid", "()Z")
    def isValid(self):
        return 1


@host_class("javax.net.ssl.SSLParameters")
class SSLParameters(Object):
    def __init__(self, suites=None, protocols=None):
        self._suites, self._protocols, self._algorithm = suites, protocols, "HTTPS"

    @jmethod("<init>", "()V")
    @jmethod("<init>", "([Ljava/lang/String;)V")
    @jmethod("<init>", "([Ljava/lang/String;[Ljava/lang/String;)V")
    def _init(self, suites=None, protocols=None):
        SSLParameters.__init__(self, suites, protocols)

    @jmethod("getProtocols", "()[Ljava/lang/String;")
    def getProtocols(self):
        return self._protocols

    @jmethod("setProtocols", "([Ljava/lang/String;)V")
    def setProtocols(self, protocols):
        self._protocols = protocols

    @jmethod("getCipherSuites", "()[Ljava/lang/String;")
    def getCipherSuites(self):
        return self._suites

    @jmethod("setCipherSuites", "([Ljava/lang/String;)V")
    def setCipherSuites(self, suites):
        self._suites = suites

    @jmethod("getEndpointIdentificationAlgorithm", "()Ljava/lang/String;")
    def getEndpointIdentificationAlgorithm(self):
        return self._algorithm

    @jmethod("setEndpointIdentificationAlgorithm", "(Ljava/lang/String;)V")
    def setEndpointIdentificationAlgorithm(self, algorithm):
        self._algorithm = algorithm


@host_class("javax.net.ssl.SSLSocket", interfaces=("java.io.Closeable",))
class SSLSocket(Socket):
    """a client tls session over a connected Socket; the python ssl socket replaces the plain one"""

    def __init__(self, plain=None, host=None, port=None):
        Socket.__init__(self)
        if plain is not None:
            self._wrap(plain, host, port)
        self._handshaken = False

    def _wrap(self, plain, host, port):
        import ssl
        plain._need_connected()
        name = host if host is not None else plain._remote._host
        try:
            ssock = _client_context().wrap_socket(plain._sock, server_hostname=name, do_handshake_on_connect=False)
        except (OSError, ValueError) as error:
            _io_failure(error, name)
        plain._sock = None
        plain._closed = True
        self._sock = ssock
        self._remote = plain._remote
        self._connected = True
        self._timeout = plain._timeout
        ssock.settimeout(self._timeout or None)

    @jmethod("startHandshake", "()V")
    def startHandshake(self):
        if self._handshaken:
            return
        try:
            self._sock.do_handshake()
        except (OSError, ValueError) as error:
            _io_failure(error, self._sock.server_hostname)
        self._handshaken = True

    @jmethod("getInputStream", "()Ljava/io/InputStream;")
    def getInputStream(self):
        self.startHandshake()
        return Socket.getInputStream(self)

    @jmethod("getOutputStream", "()Ljava/io/OutputStream;")
    def getOutputStream(self):
        self.startHandshake()
        return Socket.getOutputStream(self)

    @jmethod("getSession", "()Ljavax/net/ssl/SSLSession;")
    def getSession(self):
        self.startHandshake()
        return SSLSession(self._sock)

    @jmethod("getSSLParameters", "()Ljavax/net/ssl/SSLParameters;")
    def getSSLParameters(self):
        return SSLParameters()

    @jmethod("setSSLParameters", "(Ljavax/net/ssl/SSLParameters;)V")
    def setSSLParameters(self, parameters):
        """protocol and suite choices are kept by the python ssl context of the process; the host name check stays on"""
        self._parameters = parameters

    @jmethod("setUseClientMode", "(Z)V")
    @jmethod("setEnabledProtocols", "([Ljava/lang/String;)V")
    @jmethod("setEnabledCipherSuites", "([Ljava/lang/String;)V")
    @jmethod("setNeedClientAuth", "(Z)V")
    def setOption(self, *args):
        return None

    @jmethod("getSupportedProtocols", "()[Ljava/lang/String;")
    @jmethod("getEnabledProtocols", "()[Ljava/lang/String;")
    def getEnabledProtocols(self):
        array = runtime.new_array("[Ljava/lang/String;", 0)
        array.extend(["TLSv1.2", "TLSv1.3"])
        return array


@host_class("javax.net.ssl.SSLSocketFactory", superclass="javax.net.SocketFactory")
class SSLSocketFactory(SocketFactory):
    @jstatic("getDefault", "()Ljavax/net/SocketFactory;")
    def getDefault():
        return _DefaultSSLSocketFactory()

    @jmethod("createSocket", "(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;")
    def create_over(self, plain, host, port, auto_close):
        return SSLSocket(plain, host, port)

    @jmethod("createSocket", "(Ljava/lang/String;I)Ljava/net/Socket;")
    @jmethod("createSocket", "(Ljava/net/InetAddress;I)Ljava/net/Socket;")
    def createSocket(self, host=None, port=None):
        plain = Socket(host, port)
        return SSLSocket(plain, host if isinstance(host, str) else None, port)

    @jmethod("getDefaultCipherSuites", "()[Ljava/lang/String;")
    @jmethod("getSupportedCipherSuites", "()[Ljava/lang/String;")
    def getDefaultCipherSuites(self):
        return runtime.new_array("[Ljava/lang/String;", 0)


class _DefaultSSLSocketFactory(SSLSocketFactory):
    pass


@host_class("javax.net.ssl.TrustManager", interface=True)
class TrustManager:
    __slots__ = ()


@host_class("javax.net.ssl.X509TrustManager", interface=True, interfaces=("javax.net.ssl.TrustManager",))
class X509TrustManager(TrustManager):
    __slots__ = ()


@host_class("javax.net.ssl.KeyManager", interface=True)
class KeyManager:
    __slots__ = ()


@host_class("javax.net.ssl.HostnameVerifier", interface=True)
class HostnameVerifier:
    __slots__ = ()


class _SystemTrustManager(Object):
    """what TrustManagerFactory hands out: the check is done by the tls layer itself on every handshake"""

    def getAcceptedIssuers(self):
        return runtime.new_array("[Ljava/lang/Object;", 0)

    def checkServerTrusted(self, chain, auth_type):
        return None

    def checkClientTrusted(self, chain, auth_type):
        return None


host_class("javax.net.ssl.SystemTrustManager", interfaces=("javax.net.ssl.X509TrustManager",))(_SystemTrustManager)


@host_class("javax.net.ssl.TrustManagerFactory")
class TrustManagerFactory(Object):
    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/net/ssl/TrustManagerFactory;")
    def getInstance(algorithm):
        return TrustManagerFactory()

    @jstatic("getDefaultAlgorithm", "()Ljava/lang/String;")
    def getDefaultAlgorithm():
        return "PKIX"

    @jmethod("init", "(Ljava/security/KeyStore;)V")
    def init(self, store):
        return None

    @jmethod("getTrustManagers", "()[Ljavax/net/ssl/TrustManager;")
    def getTrustManagers(self):
        array = runtime.new_array("[Ljavax/net/ssl/TrustManager;", 0)
        array.append(_SystemTrustManager())
        return array


@host_class("javax.net.ssl.SSLContext")
class SSLContext(Object):
    def __init__(self, protocol="TLS"):
        self._protocol = protocol

    @jstatic("getInstance", "(Ljava/lang/String;)Ljavax/net/ssl/SSLContext;")
    def getInstance(protocol):
        return SSLContext(protocol)

    @jstatic("getDefault", "()Ljavax/net/ssl/SSLContext;")
    def getDefault():
        return SSLContext()

    @jmethod("init", "([Ljavax/net/ssl/KeyManager;[Ljavax/net/ssl/TrustManager;Ljava/security/SecureRandom;)V")
    def init(self, key_managers, trust_managers, random):
        return None

    @jmethod("getSocketFactory", "()Ljavax/net/ssl/SSLSocketFactory;")
    def getSocketFactory(self):
        return _DefaultSSLSocketFactory()

    @jmethod("getProtocol", "()Ljava/lang/String;")
    def getProtocol(self):
        return self._protocol


@host_class("java.net.URLConnection")
class URLConnection(Object):
    _default_use_caches = True

    def __init__(self, url):
        self._url = url
        self._connected = False
        self._request = []
        self._do_input = True
        self._do_output = False
        self._use_caches = True
        self._connect_timeout = 0
        self._read_timeout = 0

    @jmethod("<init>", "(Ljava/net/URL;)V")
    def _init(self, url):
        URLConnection.__init__(self, url)

    @jmethod("getURL", "()Ljava/net/URL;")
    def getURL(self):
        return self._url

    @jmethod("setConnectTimeout", "(I)V")
    def setConnectTimeout(self, millis):
        if millis < 0:
            _throw("java.lang.IllegalArgumentException", "timeouts can't be negative")
        self._connect_timeout = millis

    @jmethod("getConnectTimeout", "()I")
    def getConnectTimeout(self):
        return self._connect_timeout

    @jmethod("setReadTimeout", "(I)V")
    def setReadTimeout(self, millis):
        if millis < 0:
            _throw("java.lang.IllegalArgumentException", "timeouts can't be negative")
        self._read_timeout = millis

    @jmethod("getReadTimeout", "()I")
    def getReadTimeout(self):
        return self._read_timeout

    @jmethod("setDoInput", "(Z)V")
    def setDoInput(self, flag):
        self._do_input = bool(flag)

    @jmethod("getDoInput", "()Z")
    def getDoInput(self):
        return 1 if self._do_input else 0

    @jmethod("setDoOutput", "(Z)V")
    def setDoOutput(self, flag):
        self._do_output = bool(flag)

    @jmethod("getDoOutput", "()Z")
    def getDoOutput(self):
        return 1 if self._do_output else 0

    @jmethod("setUseCaches", "(Z)V")
    def setUseCaches(self, flag):
        self._use_caches = bool(flag)

    @jmethod("getUseCaches", "()Z")
    def getUseCaches(self):
        return 1 if self._use_caches else 0

    @jmethod("setAllowUserInteraction", "(Z)V")
    @jmethod("setIfModifiedSince", "(J)V")
    def setIgnored(self, value):
        return None

    @jmethod("setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V")
    def setRequestProperty(self, key, value):
        self._guard_unconnected()
        if key is None:
            runtime.throw_new("java.lang.NullPointerException", "key == null")
        self._request = [(k, v) for k, v in self._request if k.lower() != key.lower()]
        if value is not None:
            self._request.append((key, value))

    @jmethod("addRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V")
    def addRequestProperty(self, key, value):
        self._guard_unconnected()
        if key is None:
            runtime.throw_new("java.lang.NullPointerException", "key == null")
        if value is not None:
            self._request.append((key, value))

    @jmethod("getRequestProperty", "(Ljava/lang/String;)Ljava/lang/String;")
    def getRequestProperty(self, key):
        found = None
        for k, v in self._request:
            if key is not None and k.lower() == key.lower():
                found = v
        return found

    @jmethod("getRequestProperties", "()Ljava/util/Map;")
    def getRequestProperties(self):
        self._guard_unconnected()
        return _header_map(self._request)

    def _guard_unconnected(self):
        if self._connected:
            _throw("java.lang.IllegalStateException", "Already connected")

    @jmethod("connect", "()V")
    def connect(self):
        raise NotImplementedError

    @jmethod("getInputStream", "()Ljava/io/InputStream;")
    def getInputStream(self):
        _throw("java.net.UnknownServiceException", "protocol doesn't support input")

    @jmethod("getOutputStream", "()Ljava/io/OutputStream;")
    def getOutputStream(self):
        _throw("java.net.UnknownServiceException", "protocol doesn't support output")

    @jmethod("getContentType", "()Ljava/lang/String;")
    def getContentType(self):
        return self.getHeaderField("content-type")

    @jmethod("getContentEncoding", "()Ljava/lang/String;")
    def getContentEncoding(self):
        return self.getHeaderField("content-encoding")

    @jmethod("getContentLength", "()I")
    def getContentLength(self):
        value = self.getContentLengthLong()
        return value if value <= 0x7FFFFFFF else -1

    @jmethod("getContentLengthLong", "()J")
    def getContentLengthLong(self):
        text = self.getHeaderField("content-length")
        try:
            return int(text) if text is not None else -1
        except ValueError:
            return -1

    @jmethod("getHeaderField", "(Ljava/lang/String;)Ljava/lang/String;")
    def getHeaderField(self, name):
        return None

    @jmethod("getHeaderFields", "()Ljava/util/Map;")
    def getHeaderFields(self):
        return _header_map([])

    @jmethod("getHeaderFieldInt", "(Ljava/lang/String;I)I")
    def getHeaderFieldInt(self, name, fallback):
        try:
            return int(self.getHeaderField(name))
        except (TypeError, ValueError):
            return fallback

    @jmethod("getHeaderFieldLong", "(Ljava/lang/String;J)J")
    def getHeaderFieldLong(self, name, fallback):
        try:
            return int(self.getHeaderField(name))
        except (TypeError, ValueError):
            return fallback

    @jmethod("getDate", "()J")
    def getDate(self):
        return _header_date(self.getHeaderField("date"))

    @jmethod("getLastModified", "()J")
    def getLastModified(self):
        return _header_date(self.getHeaderField("last-modified"))

    @jmethod("getExpiration", "()J")
    def getExpiration(self):
        return _header_date(self.getHeaderField("expires"))

    @jmethod("getContent", "()Ljava/lang/Object;")
    def getContent(self):
        return self.getInputStream()

    @jstatic("guessContentTypeFromName", "(Ljava/lang/String;)Ljava/lang/String;")
    def guessContentTypeFromName(name):
        import mimetypes
        return mimetypes.guess_type(pystr(name))[0]

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s:%s" % (runtime.class_of(self).getName(), self._url.toString())


def _header_date(text):
    if text is None:
        return 0
    from email.utils import parsedate_to_datetime
    try:
        return int(parsedate_to_datetime(text).timestamp() * 1000)
    except (TypeError, ValueError):
        return 0


def _header_map(pairs, status=None):
    result = LinkedHashMap()
    grouped = {}
    order = []
    if status is not None:
        order.append(None)
        grouped[None] = [status]
    for key, value in pairs:
        if key not in grouped:
            grouped[key] = []
            order.append(key)
        grouped[key].append(value)
    for key in order:
        items = ArrayList()
        for value in grouped[key]:
            items.add(jstr(value))
        result.put(None if key is None else jstr(key), ImmutableList(items._a))
    from .jmap import ImmutableMap
    return ImmutableMap(result)


class _FileConnection(URLConnection):
    def connect(self):
        self._connected = True

    def getInputStream(self):
        return FileInputStream(File(_file_path(self._url)))

    def getHeaderField(self, name):
        import os
        path = _file_path(self._url)
        if name is not None and name.lower() == "content-length" and os.path.isfile(path):
            return str(os.path.getsize(path))
        return None


def _file_path(url):
    return _decode_percent(url._path)


class _BodyBuffer(OutputStream):
    """the request body of a connection, kept until the request is sent"""

    def __init__(self, connection, limit):
        self._connection = connection
        self._data = bytearray()
        self._limit = limit

    def write_byte(self, value):
        self._add(bytes((value & 0xFF,)))

    def write(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        self._add(to_py_bytes(buffer, offset, length))

    def _add(self, data):
        if self._connection._sent:
            _throw("java.io.IOException", "stream closed")
        if len(self._data) + len(data) > self._limit:
            _throw("java.io.IOException", "request body is larger than %d bytes" % self._limit)
        self._data += data


class _ResponseStream(InputStream):
    """the body of a response: bytes come from the socket as they are read, a gzip body is inflated on the way"""

    def __init__(self, response, connection, gzipped):
        self._response = response
        self._connection = connection
        self._inflater = zlib.decompressobj(16 + zlib.MAX_WBITS) if gzipped else None
        self._pending = b""
        self._done = False

    def _fill(self):
        while not self._pending and not self._done:
            try:
                chunk = self._response.read(16384)
            except socket.timeout:
                _throw("java.net.SocketTimeoutException", "Read timed out")
            except (OSError, ValueError) as error:
                if self._connection._closed:
                    _throw("java.io.IOException", "stream closed")
                _io_failure(error)
            except http.client.HTTPException as error:
                _throw("java.io.IOException", str(error))
            if not chunk:
                self._done = True
                if self._inflater is not None:
                    try:
                        self._pending = self._inflater.flush()
                    except zlib.error as error:
                        _throw("java.io.IOException", "gzip: %s" % error)
                break
            if self._inflater is not None:
                try:
                    chunk = self._inflater.decompress(chunk)
                except zlib.error as error:
                    _throw("java.io.IOException", "gzip: %s" % error)
            self._pending = chunk

    def read_byte(self):
        self._fill()
        if not self._pending:
            return -1
        value = self._pending[0]
        self._pending = self._pending[1:]
        return value

    def read(self, buffer, offset=0, length=None):
        if length is None:
            length = len(buffer)
        _check_range(buffer, offset, length)
        if length == 0:
            return 0
        self._fill()
        if not self._pending:
            return -1
        data, self._pending = self._pending[:length], self._pending[length:]
        buffer[offset:offset + len(data)] = [b - 256 if b > 127 else b for b in data]
        return len(data)

    def available(self):
        return len(self._pending)

    def close(self):
        self._connection._release()


@host_class("java.net.HttpURLConnection")
class HttpURLConnection(URLConnection):
    HTTP_OK = 200
    HTTP_CREATED = 201
    HTTP_ACCEPTED = 202
    HTTP_NO_CONTENT = 204
    HTTP_MOVED_PERM = 301
    HTTP_MOVED_TEMP = 302
    HTTP_SEE_OTHER = 303
    HTTP_NOT_MODIFIED = 304
    HTTP_BAD_REQUEST = 400
    HTTP_UNAUTHORIZED = 401
    HTTP_FORBIDDEN = 403
    HTTP_NOT_FOUND = 404
    HTTP_BAD_METHOD = 405
    HTTP_CLIENT_TIMEOUT = 408
    HTTP_CONFLICT = 409
    HTTP_GONE = 410
    HTTP_ENTITY_TOO_LARGE = 413
    HTTP_INTERNAL_ERROR = 500
    HTTP_NOT_IMPLEMENTED = 501
    HTTP_BAD_GATEWAY = 502
    HTTP_UNAVAILABLE = 503
    HTTP_GATEWAY_TIMEOUT = 504

    def __init__(self, url):
        URLConnection.__init__(self, url)
        self._method = "GET"
        self._follow = True
        self._body = None
        self._sent = False
        self._response = None
        self._conn = None
        self._status = None
        self._message = None
        self._headers = []
        self._final_url = url
        self._closed = False
        self._chunked = None
        self._fixed = None
        self._lock = threading.Lock()
        self._stream = None

    @jmethod("<init>", "(Ljava/net/URL;)V")
    def _init_url(self, url):
        HttpURLConnection.__init__(self, url)

    @jmethod("setRequestMethod", "(Ljava/lang/String;)V")
    def setRequestMethod(self, method):
        self._guard_unconnected()
        if method not in ("GET", "POST", "HEAD", "OPTIONS", "PUT", "DELETE", "TRACE", "PATCH"):
            _throw("java.net.ProtocolException", "Expected one of [OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, "
                   "PATCH] but was " + jstring(method))
        self._method = method

    @jmethod("getRequestMethod", "()Ljava/lang/String;")
    def getRequestMethod(self):
        return self._method

    @jmethod("setInstanceFollowRedirects", "(Z)V")
    def setInstanceFollowRedirects(self, flag):
        self._follow = bool(flag)

    @jmethod("getInstanceFollowRedirects", "()Z")
    def getInstanceFollowRedirects(self):
        return 1 if self._follow else 0

    @jmethod("setChunkedStreamingMode", "(I)V")
    def setChunkedStreamingMode(self, size):
        self._chunked = size

    @jmethod("setFixedLengthStreamingMode", "(I)V")
    @jmethod("setFixedLengthStreamingMode", "(J)V")
    def setFixedLengthStreamingMode(self, length):
        self._fixed = length

    @jmethod("getOutputStream", "()Ljava/io/OutputStream;")
    def getOutputStream(self):
        if not self._do_output:
            _throw("java.net.ProtocolException", "method does not support a request body: " + self._method)
        if self._sent:
            _throw("java.net.ProtocolException", "cannot write request body after response has been read")
        if self._body is None:
            self._body = _BodyBuffer(self, MAX_REQUEST_BODY)
            if self._method == "GET":
                self._method = "POST"
        return self._body

    @jmethod("connect", "()V")
    def connect(self):
        self._connected = True

    def _ssl_context(self):
        return _client_context()

    def _open(self, url, method, body, headers):
        host = url._host.strip("[]") if url._host.startswith("[") else url._host
        port = url._port if url._port >= 0 else _DEFAULT_PORTS[url._protocol]
        connect_timeout = self._connect_timeout / 1000.0 if self._connect_timeout else None
        if url._protocol == "https":
            conn = http.client.HTTPSConnection(host, port, timeout=connect_timeout, context=self._ssl_context())
        else:
            conn = http.client.HTTPConnection(host, port, timeout=connect_timeout)
        try:
            conn.connect()
            conn.sock.settimeout(self._read_timeout / 1000.0 if self._read_timeout else None)
            target = url._path or "/"
            if url._query is not None:
                target += "?" + url._query
            conn.putrequest(method, target, skip_host=True, skip_accept_encoding=True)
            names = {key.lower() for key, _ in headers}
            if "host" not in names:
                default = _DEFAULT_PORTS[url._protocol]
                conn.putheader("Host", url._host + (":%d" % url._port if url._port >= 0 and url._port != default
                                                    else ""))
            for key, value in headers:
                conn.putheader(key, value)
            if body is not None or method in ("POST", "PUT", "PATCH"):
                data = bytes(body._data) if body is not None else b""
                if "content-length" not in names:
                    conn.putheader("Content-Length", str(len(data)))
                conn.endheaders(data)
            else:
                conn.endheaders()
            response = conn.getresponse()
        except OSError as error:
            conn.close()
            _io_failure(error, host)
        except http.client.HTTPException as error:
            conn.close()
            _throw("java.io.IOException", str(error))
        return conn, response

    def _execute(self):
        with self._lock:
            if self._response is not None:
                return
            self._connected = True
            self._sent = True
            headers = list(self._request)
            names = {key.lower() for key, _ in headers}
            if "user-agent" not in names:
                headers.append(("User-Agent", USER_AGENT))
            if "accept" not in names:
                headers.append(("Accept", "*/*"))
            gzip_offered = "accept-encoding" not in names
            if gzip_offered:
                headers.append(("Accept-Encoding", "gzip"))
            if "connection" not in names:
                headers.append(("Connection", "close"))
            url, method, body = self._url, self._method, self._body
            for _ in range(MAX_REDIRECTS + 1):
                conn, response = self._open(url, method, body, headers)
                location = response.getheader("Location")
                if self._follow and response.status in (301, 302, 303, 307, 308) and location:
                    response.read()
                    conn.close()
                    try:
                        url = URL(url, location)
                    except lookup_host("java.net.MalformedURLException").py:
                        _throw("java.net.ProtocolException", "Bad redirect location: " + location)
                    if response.status in (301, 302, 303) and method != "HEAD":
                        method, body = "GET", None
                        headers = [(k, v) for k, v in headers if k.lower() not in ("content-length", "content-type")]
                    # a credential header must not follow the request to another host
                    if url._host.lower() != self._url._host.lower():
                        headers = [(k, v) for k, v in headers if k.lower() not in ("authorization", "cookie")]
                    continue
                break
            else:
                _throw("java.net.ProtocolException", "Too many follow-up requests: %d" % (MAX_REDIRECTS + 1))
            self._conn, self._response = conn, response
            self._final_url = url
            self._status = response.status
            self._message = response.reason
            raw = response.getheaders()
            encoding = (response.getheader("Content-Encoding") or "").lower()
            self._gzipped = gzip_offered and encoding == "gzip" and method != "HEAD"
            self._headers = [(k, v) for k, v in raw
                             if not (self._gzipped and k.lower() in ("content-encoding", "content-length"))]
            self._status_line = "HTTP/%s %d %s" % ("1.1" if response.version == 11 else "1.0", response.status,
                                                   response.reason)

    def _release(self):
        self._closed = True
        conn = self._conn
        if conn is not None:
            conn.close()

    @jmethod("getResponseCode", "()I")
    def getResponseCode(self):
        self._execute()
        return self._status

    @jmethod("getResponseMessage", "()Ljava/lang/String;")
    def getResponseMessage(self):
        self._execute()
        return self._message

    @jmethod("getInputStream", "()Ljava/io/InputStream;")
    def getInputStream(self):
        if not self._do_input:
            _throw("java.net.ProtocolException", "This protocol does not support input")
        self._execute()
        if self._status >= 400:
            _throw("java.io.FileNotFoundException", self._final_url.toString())
        return self._body_stream()

    def _body_stream(self):
        if self._stream is None:
            self._stream = _ResponseStream(self._response, self, self._gzipped)
        return self._stream

    @jmethod("getErrorStream", "()Ljava/io/InputStream;")
    def getErrorStream(self):
        if self._response is None or self._status < 400:
            return None
        return self._body_stream()

    @jmethod("getHeaderField", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("getHeaderField", "(I)Ljava/lang/String;")
    def getHeaderField(self, name):
        self._execute()
        if isinstance(name, int):
            if name == 0:
                return self._status_line
            return self._headers[name - 1][1] if 0 < name <= len(self._headers) else None
        if name is None:
            return self._status_line
        found = None
        for key, value in self._headers:
            if key.lower() == name.lower():
                found = value
        return found

    @jmethod("getHeaderFieldKey", "(I)Ljava/lang/String;")
    def getHeaderFieldKey(self, index):
        self._execute()
        return self._headers[index - 1][0] if 0 < index <= len(self._headers) else None

    @jmethod("getHeaderFields", "()Ljava/util/Map;")
    def getHeaderFields(self):
        self._execute()
        return _header_map(self._headers, self._status_line)

    @jmethod("getURL", "()Ljava/net/URL;")
    def getURL(self):
        return self._final_url if self._response is not None else self._url

    @jmethod("disconnect", "()V")
    def disconnect(self):
        self._release()

    @jmethod("usingProxy", "()Z")
    def usingProxy(self):
        return 0


@host_class("javax.net.ssl.HttpsURLConnection")
class HttpsURLConnection(HttpURLConnection):
    _default_verifier = None
    _default_factory = None

    @jmethod("<init>", "(Ljava/net/URL;)V")
    def _init_url(self, url):
        HttpURLConnection.__init__(self, url)

    @jstatic("setDefaultHostnameVerifier", "(Ljavax/net/ssl/HostnameVerifier;)V")
    def setDefaultHostnameVerifier(verifier):
        HttpsURLConnection._default_verifier = verifier

    @jstatic("getDefaultHostnameVerifier", "()Ljavax/net/ssl/HostnameVerifier;")
    def getDefaultHostnameVerifier():
        return HttpsURLConnection._default_verifier

    @jstatic("setDefaultSSLSocketFactory", "(Ljavax/net/ssl/SSLSocketFactory;)V")
    def setDefaultSSLSocketFactory(factory):
        HttpsURLConnection._default_factory = factory

    @jstatic("getDefaultSSLSocketFactory", "()Ljavax/net/ssl/SSLSocketFactory;")
    def getDefaultSSLSocketFactory():
        return HttpsURLConnection._default_factory or _DefaultSSLSocketFactory()

    @jmethod("setHostnameVerifier", "(Ljavax/net/ssl/HostnameVerifier;)V")
    def setHostnameVerifier(self, verifier):
        self._verifier = verifier

    @jmethod("getHostnameVerifier", "()Ljavax/net/ssl/HostnameVerifier;")
    def getHostnameVerifier(self):
        return getattr(self, "_verifier", None) or HttpsURLConnection._default_verifier

    @jmethod("setSSLSocketFactory", "(Ljavax/net/ssl/SSLSocketFactory;)V")
    def setSSLSocketFactory(self, factory):
        self._factory = factory

    @jmethod("getSSLSocketFactory", "()Ljavax/net/ssl/SSLSocketFactory;")
    def getSSLSocketFactory(self):
        return getattr(self, "_factory", None) or HttpsURLConnection.getDefaultSSLSocketFactory()
