"""the part of websocket-client that plugins call: create_connection(url, header=, timeout=, origin=, sslopt=), then
send, recv, recv_data, recv_frame and close, and the exceptions. rfc 6455 client over socket and ssl.

the handshake checks the status and the accept key; frames are read with hard limits: a server frame must not be masked
and must not set reserved bits, a control frame is at most 125 bytes and never fragmented, a message is at most 16 MiB"""

import base64
import hashlib
import os
import socket
import ssl
import struct
import urllib.parse

__all__ = ["create_connection", "WebSocket", "ABNF", "WebSocketException", "WebSocketBadStatusException",
           "WebSocketConnectionClosedException", "WebSocketTimeoutException"]

_GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
_MESSAGE_MAX = 16 * 1024 * 1024
_HEADER_MAX = 16 * 1024


class WebSocketException(Exception):
    pass


class WebSocketBadStatusException(WebSocketException):
    def __init__(self, message, status_code, status_message=None, resp_headers=None):
        super().__init__(message)
        self.status_code = status_code
        self.status_message = status_message
        self.resp_headers = resp_headers


class WebSocketConnectionClosedException(WebSocketException):
    pass


class WebSocketTimeoutException(WebSocketException):
    pass


class ABNF:
    OPCODE_CONT = 0x0
    OPCODE_TEXT = 0x1
    OPCODE_BINARY = 0x2
    OPCODE_CLOSE = 0x8
    OPCODE_PING = 0x9
    OPCODE_PONG = 0xA

    def __init__(self, fin, opcode, data):
        self.fin = fin
        self.opcode = opcode
        self.data = data


class WebSocket:
    def __init__(self, sock):
        self._sock = sock
        self._buffer = bytearray()
        self.connected = True
        self.status = None
        self.headers = {}

    def _read(self, count):
        while len(self._buffer) < count:
            try:
                chunk = self._sock.recv(65536)
            except (socket.timeout, TimeoutError) as error:
                raise WebSocketTimeoutException("timed out") from error
            except OSError as error:
                self.connected = False
                raise WebSocketConnectionClosedException(str(error)) from error
            if not chunk:
                self.connected = False
                raise WebSocketConnectionClosedException("the connection is closed")
            self._buffer += chunk
        data = bytes(self._buffer[:count])
        del self._buffer[:count]
        return data

    def _write(self, data):
        try:
            self._sock.sendall(data)
        except OSError as error:
            self.connected = False
            raise WebSocketConnectionClosedException(str(error)) from error

    def _send_frame(self, opcode, payload):
        if opcode >= 0x8 and len(payload) > 125:
            raise WebSocketException("a control frame holds at most 125 bytes")
        head = bytearray([0x80 | opcode])
        size = len(payload)
        if size < 126:
            head.append(0x80 | size)
        elif size < 65536:
            head += bytes([0x80 | 126]) + struct.pack(">H", size)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", size)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload)) if size < 4096 else _mask_large(payload, mask)
        self._write(bytes(head) + mask + masked)

    def send(self, payload, opcode=ABNF.OPCODE_TEXT):
        if isinstance(payload, str):
            payload = payload.encode("utf-8")
            opcode = ABNF.OPCODE_TEXT
        self._send_frame(opcode, bytes(payload))

    def send_binary(self, payload):
        self._send_frame(ABNF.OPCODE_BINARY, bytes(payload))

    def ping(self, payload=b""):
        self._send_frame(ABNF.OPCODE_PING, payload if isinstance(payload, bytes) else payload.encode("utf-8"))

    def recv_frame(self):
        first, second = self._read(2)
        if first & 0x70:
            raise WebSocketException("a reserved bit is set")
        if second & 0x80:
            raise WebSocketException("a server frame is masked")
        fin, opcode, size = bool(first & 0x80), first & 0x0F, second & 0x7F
        if opcode not in (0x0, 0x1, 0x2, 0x8, 0x9, 0xA):
            raise WebSocketException("unknown opcode %d" % opcode)
        if size == 126:
            size = struct.unpack(">H", self._read(2))[0]
        elif size == 127:
            size = struct.unpack(">Q", self._read(8))[0]
        if opcode >= 0x8 and (size > 125 or not fin):
            raise WebSocketException("a bad control frame")
        if size > _MESSAGE_MAX:
            raise WebSocketException("a frame of %d bytes is too large" % size)
        return ABNF(fin, opcode, self._read(size))

    def recv_data(self, control_frame=False):
        """(opcode, data) of the next message. ping is answered, pong is skipped, a close is answered and returned"""
        message = bytearray()
        kind = None
        while True:
            frame = self.recv_frame()
            if frame.opcode == ABNF.OPCODE_PING:
                self._send_frame(ABNF.OPCODE_PONG, frame.data)
                continue
            if frame.opcode == ABNF.OPCODE_PONG:
                continue
            if frame.opcode == ABNF.OPCODE_CLOSE:
                try:
                    self._send_frame(ABNF.OPCODE_CLOSE, frame.data[:2])
                except WebSocketException:
                    pass
                self.connected = False
                return ABNF.OPCODE_CLOSE, frame.data
            if frame.opcode == ABNF.OPCODE_CONT:
                if kind is None:
                    raise WebSocketException("a continuation with no message")
            else:
                if kind is not None:
                    raise WebSocketException("a new message inside a fragmented one")
                kind = frame.opcode
            message += frame.data
            if len(message) > _MESSAGE_MAX:
                raise WebSocketException("a message is larger than %d bytes" % _MESSAGE_MAX)
            if frame.fin:
                if kind == ABNF.OPCODE_TEXT:
                    return kind, bytes(message).decode("utf-8")
                return kind, bytes(message)

    def recv(self):
        opcode, data = self.recv_data()
        return "" if opcode == ABNF.OPCODE_CLOSE else data

    def settimeout(self, timeout):
        self._sock.settimeout(timeout)

    def close(self, status=1000, reason=b""):
        if self._sock is None:
            return
        try:
            if self.connected:
                self._send_frame(ABNF.OPCODE_CLOSE, struct.pack(">H", status) + (reason if isinstance(reason, bytes) else reason.encode("utf-8")))
        except WebSocketException:
            pass
        finally:
            self.connected = False
            self._sock.close()
            self._sock = None


def _mask_large(payload, mask):
    key = (mask * (len(payload) // 4 + 1))[:len(payload)]
    return (int.from_bytes(payload, "big") ^ int.from_bytes(key, "big")).to_bytes(len(payload), "big")


def create_connection(url, timeout=None, header=None, origin=None, sslopt=None, subprotocols=None, **_ignored):
    if _ignored:
        raise TypeError("not supported by this websocket: %s" % ", ".join(sorted(_ignored)))
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("ws", "wss") or not parts.hostname:
        raise WebSocketException("not a websocket address: " + url)
    for item in header or []:
        if "\r" in item or "\n" in item:
            raise WebSocketException("a header holds a line break")
    secure = parts.scheme == "wss"
    port = parts.port or (443 if secure else 80)
    try:
        sock = socket.create_connection((parts.hostname, port), timeout=15.0 if timeout is None else timeout)
    except socket.timeout as error:
        raise WebSocketTimeoutException(str(error)) from error
    try:
        if secure:
            options = dict(sslopt or {})
            context = ssl.create_default_context(cafile=options.pop("ca_certs", None))
            if options:
                raise TypeError("not supported in sslopt: %s" % ", ".join(sorted(options)))
            sock = context.wrap_socket(sock, server_hostname=parts.hostname)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        path = (parts.path or "/") + ("?" + parts.query if parts.query else "")
        lines = ["GET %s HTTP/1.1" % path, "Host: %s" % (parts.netloc.rpartition("@")[2]), "Upgrade: websocket", "Connection: Upgrade",
                 "Sec-WebSocket-Key: %s" % key, "Sec-WebSocket-Version: 13"]
        if origin:
            lines.append("Origin: %s" % origin)
        if subprotocols:
            lines.append("Sec-WebSocket-Protocol: %s" % ", ".join(subprotocols))
        lines.extend(header or [])
        sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("utf-8"))
        ws = WebSocket(sock)
        head = bytearray()
        while not head.endswith(b"\r\n\r\n"):
            if len(head) > _HEADER_MAX:
                raise WebSocketException("the handshake answer is too long")
            try:
                byte = sock.recv(1)
            except (socket.timeout, TimeoutError) as error:
                raise WebSocketTimeoutException("timed out") from error
            if not byte:
                raise WebSocketConnectionClosedException("the connection closed during the handshake")
            head += byte
        status_line, *header_lines = head.decode("latin-1").split("\r\n")
        words = status_line.split(" ", 2)
        status = int(words[1]) if len(words) > 1 and words[1].isdigit() else 0
        headers = {}
        for line in header_lines:
            name, _, value = line.partition(":")
            if name:
                headers[name.strip().lower()] = value.strip()
        if status != 101:
            raise WebSocketBadStatusException("Handshake status %d" % status, status, words[2] if len(words) > 2 else None, headers)
        accept = base64.b64encode(hashlib.sha1(key.encode("ascii") + _GUID).digest()).decode("ascii")
        if headers.get("upgrade", "").lower() != "websocket" or headers.get("sec-websocket-accept") != accept:
            raise WebSocketException("the handshake answer is not a websocket accept")
        ws.status = status
        ws.headers = headers
        return ws
    except BaseException:
        sock.close()
        raise
