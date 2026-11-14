"""java.nio.file walking, channels, selectors and the rest of java.net (datagrams, cookies, IDN) of the dex runtime"""

import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import dexvm  # noqa: E402,F401
from dexvm import api, runtime  # noqa: E402
from dexvm.jio import to_java_bytes  # noqa: E402


def J(name):
    return api.lookup_host(name).py


class NioFile(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = self.tmp.name
        os.makedirs(os.path.join(base, "a", "b"))
        for rel in ("x.txt", os.path.join("a", "y.txt"), os.path.join("a", "b", "z.log")):
            with open(os.path.join(base, rel), "w") as handle:
                handle.write("one\ntwo\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_walk_file_tree_visits_in_order_and_skips(self):
        seen = []
        Visitor = J("java.nio.file.SimpleFileVisitor")
        FVR = J("java.nio.file.FileVisitResult")

        class V(Visitor):
            def __init__(self):
                Visitor.__init__(self)

            def preVisitDirectory(self, d, a):
                seen.append("d:" + os.path.basename(d._p))
                return FVR.SKIP_SUBTREE if os.path.basename(d._p) == "b" else FVR.CONTINUE

            def visitFile(self, f, a):
                seen.append("f:" + os.path.basename(f._p))
                return FVR.CONTINUE
        J("java.nio.file.Files").walkFileTree(J("java.nio.file.Paths").get(self.tmp.name, None), V())
        self.assertEqual(seen[1:], ["d:a", "d:b", "f:y.txt", "f:x.txt"])

    def test_glob_matcher_and_directory_stream(self):
        fs = J("java.nio.file.FileSystems").getDefault()
        matcher = fs.getPathMatcher("glob:*.{txt,log}")
        P = J("java.nio.file.Path")
        self.assertEqual(matcher.matches(P("x.txt")), 1)
        self.assertEqual(matcher.matches(P("x.png")), 0)
        stream = J("java.nio.file.Files").newDirectoryStream(P(self.tmp.name), "*.txt")
        names = [os.path.basename(p._p) for p in iter_java(stream)]
        self.assertEqual(names, ["x.txt"])

    def test_posix_permissions_roundtrip(self):
        perms = J("java.nio.file.attribute.PosixFilePermissions")
        self.assertEqual(perms.toString(perms.fromString("rwxr-x---")), "rwxr-x---")
        with self.assertRaises(J("java.lang.IllegalArgumentException")):
            perms.fromString("rwx")


def iter_java(iterable):
    it = iterable.iterator()
    while it.hasNext():
        yield it.next()


class Channels(unittest.TestCase):
    def test_file_channel_positional_io(self):
        path = J("java.nio.file.Path")(os.path.join(tempfile.mkdtemp(), "c.bin"))
        FC, BB = J("java.nio.channels.FileChannel"), J("java.nio.ByteBuffer")
        SO = J("java.nio.file.StandardOpenOption")
        channel = FC.open(path, SO.CREATE, SO.WRITE, SO.READ)
        channel.write(BB.wrap(to_java_bytes(b"hello world")))
        channel.write(BB.wrap(to_java_bytes(b"J")), 6)
        self.assertEqual(channel.size(), 11)
        buffer = BB.allocate(5)
        channel.read(buffer, 6)
        self.assertEqual(bytes(b & 0xFF for b in buffer.array()), b"Jorld")
        channel.close()
        with self.assertRaises(J("java.nio.channels.ClosedChannelException")):
            channel.size()

    def test_selector_reports_acceptable_and_readable(self):
        Server, Client, Selector, Key = (J("java.nio.channels." + n) for n in ("ServerSocketChannel", "SocketChannel", "Selector", "SelectionKey"))
        server = Server.open()
        server.bind(J("java.net.InetSocketAddress")("127.0.0.1", 0))
        port = server.getLocalAddress().getPort()
        server.configureBlocking(0)
        selector = Selector.open()
        server.register(selector, Key.OP_ACCEPT)
        client = Client.open(J("java.net.InetSocketAddress")("127.0.0.1", port))
        self.assertEqual(selector.select(2000), 1)
        key = next(iter_java(selector.selectedKeys()))
        self.assertEqual(key.isAcceptable(), 1)
        conn = server.accept()
        client.write(J("java.nio.ByteBuffer").wrap(to_java_bytes(b"ping")))
        buf = J("java.nio.ByteBuffer").allocate(8)
        conn.configureBlocking(1)
        self.assertEqual(conn.read(buf), 4)
        self.assertEqual(bytes(b & 0xFF for b in buf.array()[:4]), b"ping")
        for item in (client, conn, server):
            item.close()
        selector.close()


class Net(unittest.TestCase):
    def test_datagram_loopback(self):
        DS, DP, Addr = J("java.net.DatagramSocket"), J("java.net.DatagramPacket"), J("java.net.InetAddress")
        receiver, sender = DS(0), DS()
        receiver.setSoTimeout(2000)
        data = to_java_bytes(b"udp!")
        sender.send(DP(data, 4, Addr.getByName("127.0.0.1"), receiver.getLocalPort()))
        buffer = to_java_bytes(b"\0" * 16)
        packet = DP(buffer, 16)
        receiver.receive(packet)
        self.assertEqual(bytes(b & 0xFF for b in buffer[:packet.getLength()]), b"udp!")
        sender.close()
        receiver.close()

    def test_cookie_manager_stores_and_returns(self):
        CM, URI, HM, AL = (J(n) for n in ("java.net.CookieManager", "java.net.URI", "java.util.HashMap", "java.util.ArrayList"))
        manager = CM()
        headers = HM()
        values = AL()
        values.add("sid=abc; Path=/; Secure")
        headers.put("Set-Cookie", values)
        manager.put(URI("https://example.com/app/x"), headers)
        got = manager.get(URI("https://example.com/app/y"), HM())
        self.assertEqual(got.get("Cookie").get(0), "sid=abc")
        self.assertEqual(manager.get(URI("http://example.com/"), HM()).size(), 0)

    def test_http_cookie_parse_and_domain(self):
        HC = J("java.net.HttpCookie")
        cookie = HC.parse("Set-Cookie: a=b; Max-Age=0; Domain=.Example.com").get(0)
        self.assertEqual((cookie.getName(), cookie.getValue(), cookie.hasExpired()), ("a", "b", 1))
        self.assertEqual(HC.domainMatches(".example.com", "www.example.com"), 1)
        self.assertEqual(HC.domainMatches(".example.com", "evil.com"), 0)

    def test_idn(self):
        IDN = J("java.net.IDN")
        self.assertEqual(IDN.toASCII("bücher.example"), "xn--bcher-kva.example")
        self.assertEqual(IDN.toUnicode("xn--bcher-kva.example"), "bücher.example")


if __name__ == "__main__":
    unittest.main()
