"""the part of the requests library that exteraGram plugins call, over urllib: get, post, put, delete, head, Session,
Response (status_code, headers, content, text, json, iter_content, raise_for_status) and the exceptions.

https trust is the bundle of python/cacert.pem through SSL_CERT_FILE. redirects are followed up to 10 times by urllib,
the body read by .content or .text is capped at 32 MiB, and a call with no timeout gets 30 s so a hook cannot hang on a socket"""

import json as _json
import urllib.error
import urllib.parse
import urllib.request

__all__ = ["get", "post", "put", "delete", "head", "request", "Session", "Response", "RequestException", "HTTPError", "ConnectionError",
           "Timeout", "TooManyRedirects"]

_DEFAULT_TIMEOUT = 30.0
_BODY_MAX = 32 * 1024 * 1024
_CHUNK = 8192


class RequestException(OSError):
    pass


class HTTPError(RequestException):
    def __init__(self, *args, response=None):
        super().__init__(*args)
        self.response = response


class ConnectionError(RequestException):
    pass


class Timeout(RequestException):
    pass


class TooManyRedirects(RequestException):
    pass


class _Headers(dict):
    """case insensitive lookup, original case kept for iteration"""

    def __init__(self, items=()):
        super().__init__()
        self._lower = {}
        for key, value in items:
            self[key] = value

    def __setitem__(self, key, value):
        old = self._lower.get(key.lower())
        if old is not None and old != key:
            super().__delitem__(old)
        self._lower[key.lower()] = key
        super().__setitem__(key, value)

    def __getitem__(self, key):
        return super().__getitem__(self._lower[key.lower()]) if key.lower() in self._lower else super().__getitem__(key)

    def get(self, key, default=None):
        return self[key] if key.lower() in self._lower else default

    def __contains__(self, key):
        return key.lower() in self._lower


class Response:
    def __init__(self, url, status, reason, headers, stream, body=None):
        self.url = url
        self.status_code = status
        self.reason = reason
        self.headers = headers
        self.encoding = None
        self._stream = stream
        self._body = body

    @property
    def ok(self):
        return self.status_code < 400

    def iter_content(self, chunk_size=1, decode_unicode=False):
        if self._body is not None:
            data = self._body
            for start in range(0, len(data), chunk_size or len(data) or 1):
                yield data[start:start + (chunk_size or len(data))]
            return
        size = chunk_size or _CHUNK
        try:
            while True:
                chunk = self._stream.read(size)
                if not chunk:
                    return
                yield chunk
        except OSError as error:
            raise ConnectionError(str(error)) from error
        finally:
            self.close()

    @property
    def content(self):
        if self._body is None:
            body = bytearray()
            for chunk in self.iter_content(_CHUNK):
                body += chunk
                if len(body) > _BODY_MAX:
                    self.close()
                    raise RequestException("the body is larger than %d bytes" % _BODY_MAX)
            self._body = bytes(body)
        return self._body

    @property
    def text(self):
        return self.content.decode(self.encoding or _charset(self.headers.get("Content-Type", "")) or "utf-8", "replace")

    def json(self, **options):
        return _json.loads(self.text, **options)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise HTTPError("%d %s for url: %s" % (self.status_code, self.reason, self.url), response=self)

    def close(self):
        if self._stream is not None:
            self._stream.close()
            self._stream = None


def _charset(content_type):
    for part in content_type.split(";")[1:]:
        key, _, value = part.strip().partition("=")
        if key.lower() == "charset":
            return value.strip("\"'")
    return None


class Session:
    def __init__(self):
        self.headers = {"User-Agent": "python-requests/exteria"}

    def request(self, method, url, params=None, data=None, json=None, headers=None, timeout=None, stream=False, allow_redirects=True, **_ignored):
        if _ignored:
            raise TypeError("not supported by this requests: %s" % ", ".join(sorted(_ignored)))
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, doseq=True)
        body = None
        merged = dict(self.headers)
        if json is not None:
            body = _json.dumps(json).encode("utf-8")
            merged["Content-Type"] = "application/json"
        elif isinstance(data, (dict, list, tuple)):
            body = urllib.parse.urlencode(data, doseq=True).encode("utf-8")
            merged["Content-Type"] = "application/x-www-form-urlencoded"
        elif data is not None:
            body = data.encode("utf-8") if isinstance(data, str) else bytes(data)
        merged.update(headers or {})
        opener = urllib.request.build_opener(*([] if allow_redirects else [_NoRedirect()]))
        call = urllib.request.Request(url, data=body, headers=merged, method=method.upper())
        try:
            raw = opener.open(call, timeout=_DEFAULT_TIMEOUT if timeout is None else timeout)
        except urllib.error.HTTPError as error:
            raw = error
        except urllib.error.URLError as error:
            reason = error.reason
            raise (Timeout if isinstance(reason, TimeoutError) else ConnectionError)(str(reason)) from error
        except TimeoutError as error:
            raise Timeout(str(error)) from error
        except OSError as error:
            raise ConnectionError(str(error)) from error
        response = Response(raw.geturl(), raw.status if hasattr(raw, "status") else raw.code, raw.reason, _Headers(raw.headers.items()), raw)
        if not stream:
            response.content
        return response

    def get(self, url, **options):
        return self.request("GET", url, **options)

    def post(self, url, **options):
        return self.request("POST", url, **options)

    def put(self, url, **options):
        return self.request("PUT", url, **options)

    def delete(self, url, **options):
        return self.request("DELETE", url, **options)

    def head(self, url, **options):
        return self.request("HEAD", url, **options)

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def request(method, url, **options):
    return Session().request(method, url, **options)


def get(url, **options):
    return Session().get(url, **options)


def post(url, **options):
    return Session().post(url, **options)


def put(url, **options):
    return Session().put(url, **options)


def delete(url, **options):
    return Session().delete(url, **options)


def head(url, **options):
    return Session().head(url, **options)
