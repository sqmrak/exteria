import base64
import hashlib
import os
import socket
import struct
import sys
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import certifi  # noqa: E402
import websocket  # noqa: E402

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def frame(opcode, payload, fin=True, masked=False, rsv=0):
    head = bytearray([(0x80 if fin else 0) | rsv | opcode])
    size = len(payload)
    flag = 0x80 if masked else 0
    if size < 126:
        head.append(flag | size)
    elif size < 65536:
        head += bytes([flag | 126]) + struct.pack(">H", size)
    else:
        head += bytes([flag | 127]) + struct.pack(">Q", size)
    return bytes(head) + (b"\0\0\0\0" if masked else b"") + payload


def read_client_frame(conn):
    def need(count):
        data = b""
        while len(data) < count:
            part = conn.recv(count - len(data))
            if not part:
                raise EOFError
            data += part
        return data
    first, second = need(2)
    size = second & 0x7F
    if size == 126:
        size = struct.unpack(">H", need(2))[0]
    elif size == 127:
        size = struct.unpack(">Q", need(8))[0]
    assert second & 0x80, "a client frame must be masked"
    mask = need(4)
    body = bytes(b ^ mask[i % 4] for i, b in enumerate(need(size)))
    return first & 0x0F, body


class Server:
    """accepts one connection, answers the handshake, then runs script(conn, headers)"""

    def __init__(self, script, accept_key=None, status=b"101 Switching Protocols"):
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.script, self.accept_key, self.status = script, accept_key, status
        self.seen = {}
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        conn, _ = self.listener.accept()
        with conn:
            raw = b""
            while not raw.endswith(b"\r\n\r\n"):
                raw += conn.recv(1)
            lines = raw.decode().split("\r\n")
            self.seen["request"] = lines[0]
            self.seen["headers"] = {l.split(":", 1)[0].lower(): l.split(":", 1)[1].strip() for l in lines[1:] if ":" in l}
            key = self.seen["headers"]["sec-websocket-key"].encode()
            accept = self.accept_key or base64.b64encode(hashlib.sha1(key + GUID).digest()).decode()
            conn.sendall(b"HTTP/1.1 " + self.status + b"\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept.encode() + b"\r\n\r\n")
            if self.status.startswith(b"101"):
                self.script(conn)

    def url(self, path="/x?a=1"):
        return "ws://127.0.0.1:%d%s" % (self.port, path)

    def close(self):
        self.listener.close()


class Client(unittest.TestCase):
    def test_handshake_headers_and_echo(self):
        def script(conn):
            opcode, body = read_client_frame(conn)
            conn.sendall(frame(opcode, body))
            conn.sendall(frame(websocket.ABNF.OPCODE_BINARY, b"\x00\x02ab" + b"z" * 70000))
            read_client_frame(conn)
        server = Server(script)
        ws = websocket.create_connection(server.url(), header=["X-Test: yes"], origin="chrome-extension://abc", timeout=5)
        ws.send("héllo")
        self.assertEqual(ws.recv_data(), (websocket.ABNF.OPCODE_TEXT, "héllo"))
        opcode, data = ws.recv_data()
        self.assertEqual((opcode, len(data)), (websocket.ABNF.OPCODE_BINARY, 70004))
        ws.close()
        server.thread.join(5)
        self.assertEqual(server.seen["request"], "GET /x?a=1 HTTP/1.1")
        self.assertEqual(server.seen["headers"]["x-test"], "yes")
        self.assertEqual(server.seen["headers"]["origin"], "chrome-extension://abc")
        self.assertEqual(server.seen["headers"]["sec-websocket-version"], "13")

    def test_sends_a_large_masked_frame(self):
        got = []

        def script(conn):
            got.append(read_client_frame(conn))
        server = Server(script)
        ws = websocket.create_connection(server.url(), timeout=5)
        payload = bytes(range(256)) * 40
        ws.send_binary(payload)
        server.thread.join(5)
        ws.close()
        self.assertEqual(got, [(websocket.ABNF.OPCODE_BINARY, payload)])

    def test_joins_fragments_answers_ping_and_reports_close(self):
        pongs = []

        def script(conn):
            conn.sendall(frame(websocket.ABNF.OPCODE_TEXT, b"ab", fin=False))
            conn.sendall(frame(websocket.ABNF.OPCODE_PING, b"p"))
            conn.sendall(frame(websocket.ABNF.OPCODE_CONT, b"cd"))
            pongs.append(read_client_frame(conn))
            conn.sendall(frame(websocket.ABNF.OPCODE_CLOSE, struct.pack(">H", 1000)))
        server = Server(script)
        ws = websocket.create_connection(server.url(), timeout=5)
        self.assertEqual(ws.recv_data(), (websocket.ABNF.OPCODE_TEXT, "abcd"))
        self.assertEqual(ws.recv_data()[0], websocket.ABNF.OPCODE_CLOSE)
        self.assertEqual(pongs, [(websocket.ABNF.OPCODE_PONG, b"p")])
        self.assertFalse(ws.connected)

    def test_refuses_malformed_server_frames(self):
        bad = {
            "masked": frame(websocket.ABNF.OPCODE_TEXT, b"x", masked=True),
            "reserved bit": frame(websocket.ABNF.OPCODE_TEXT, b"x", rsv=0x40),
            "fragmented control": frame(websocket.ABNF.OPCODE_PING, b"x", fin=False),
            "long control": frame(websocket.ABNF.OPCODE_PING, b"x" * 126),
            "unknown opcode": frame(0x3, b"x"),
            "orphan continuation": frame(websocket.ABNF.OPCODE_CONT, b"x"),
            "huge": bytes([0x82, 127]) + struct.pack(">Q", 1 << 40),
        }
        for name, data in bad.items():
            with self.subTest(name):
                server = Server(lambda conn, data=data: conn.sendall(data))
                ws = websocket.create_connection(server.url(), timeout=5)
                with self.assertRaises(websocket.WebSocketException):
                    ws.recv_data()
                ws.close()

    def test_truncated_frame_is_a_closed_connection(self):
        server = Server(lambda conn: conn.sendall(frame(websocket.ABNF.OPCODE_TEXT, b"abcdef")[:4]))
        ws = websocket.create_connection(server.url(), timeout=5)
        with self.assertRaises(websocket.WebSocketConnectionClosedException):
            ws.recv_data()

    def test_silence_is_a_timeout(self):
        event = threading.Event()
        server = Server(lambda conn: event.wait(5))
        ws = websocket.create_connection(server.url(), timeout=0.2)
        with self.assertRaises(websocket.WebSocketTimeoutException):
            ws.recv_data()
        event.set()

    def test_handshake_failures_carry_the_status(self):
        server = Server(None, status=b"403 Forbidden")
        with self.assertRaises(websocket.WebSocketBadStatusException) as raised:
            websocket.create_connection(server.url(), timeout=5)
        self.assertEqual(raised.exception.status_code, 403)
        self.assertIn("upgrade", raised.exception.resp_headers)

    def test_wrong_accept_key_is_refused(self):
        server = Server(lambda conn: None, accept_key="AAAA")
        with self.assertRaises(websocket.WebSocketException):
            websocket.create_connection(server.url(), timeout=5)

    def test_bad_arguments(self):
        with self.assertRaises(websocket.WebSocketException):
            websocket.create_connection("http://127.0.0.1/", timeout=1)
        with self.assertRaises(TypeError):
            websocket.create_connection("ws://127.0.0.1:1/", http_proxy_host="x")
        with self.assertRaises(websocket.WebSocketException):
            websocket.create_connection("ws://127.0.0.1:1/", header=["A: b\r\nC: d"])

    def test_certifi_points_at_the_bundle(self):
        # the bundle is staged next to the stdlib by build_python.sh, so the repository has none
        with self.assertRaises(FileNotFoundError):
            certifi.where()


if __name__ == "__main__":
    unittest.main()
