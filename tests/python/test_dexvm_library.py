"""the java and android classes the dex runtime adds on top of java.lang: org.json, dates, net, nio, collections, files, streams,
preferences, geometry and spans. expected values are what the android runtime answers for the same calls"""

import gzip
import http.server
import os
import sys
import tempfile
import threading
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path.insert(0, os.path.join(ROOT, "python", "shim"))

import dexvm  # noqa: E402,F401
from dexvm import api, runtime  # noqa: E402


def J(name):
    return api.lookup_host(name).py


def jbytes(*values):
    array = runtime.new_array("[B", 0)
    array.extend(values)
    return array


def java_name(error):
    return runtime.class_of(error).getName()


class Json(unittest.TestCase):
    def test_object_keeps_order_and_coerces(self):
        o = J("org.json.JSONObject")('{"a":1,"b":[1,2.5,"x",null,true,{"c":-0}],\'q\':0x10,r=012;s:12345678901,t:1e3,u:08}')
        self.assertEqual(o.toString(), '{"a":1,"b":[1,2.5,"x",null,true,{"c":0}],"q":16,"r":10,"s":12345678901,"t":1000,"u":8}')
        self.assertEqual((o.getInt("a"), o.optString("zz", "d"), o.getJSONArray("b").length()), (1, "d", 6))
        self.assertEqual(o.get("t").toString(), "1000.0")
        self.assertEqual(o.get("u").toString(), "8.0")

    def test_errors_carry_the_android_text(self):
        o = J("org.json.JSONObject")('{"a":1}')
        with self.assertRaises(J("org.json.JSONException")) as caught:
            o.getInt("nope")
        self.assertEqual(caught.exception.getMessage(), "No value for nope")
        with self.assertRaises(J("org.json.JSONException")) as caught:
            o.getJSONArray("a")
        self.assertEqual(caught.exception.getMessage(),
                         "Value 1 at a of type java.lang.Integer cannot be converted to JSONArray")
        with self.assertRaises(J("org.json.JSONException")) as caught:
            J("org.json.JSONObject")("{")
        self.assertEqual(caught.exception.getMessage(), "End of input at character 1 of {")

    def test_put_null_removes_and_doubles_print_integral(self):
        o = J("org.json.JSONObject")()
        o.put_int("k", 5)
        o.put("k", None)
        o.put_double("d", 2.0)
        o.put_double("e", 0.1)
        self.assertEqual(o.toString(), '{"d":2,"e":0.1}')
        with self.assertRaises(J("org.json.JSONException")):
            o.put_double("n", float("nan"))

    def test_indent_and_quote(self):
        o = J("org.json.JSONObject")('{"a":[1,{"b":2}]}')
        self.assertEqual(o.toString_indent(2), '{\n  "a": [\n    1,\n    {\n      "b": 2\n    }\n  ]\n}')
        self.assertEqual(J("org.json.JSONObject").quote('a"b/\n '), '"a\\"b\\/\\n\\u2028"')

    def test_array_with_empty_slots(self):
        a = J("org.json.JSONArray")("[1,,2,]")
        self.assertEqual((a.toString(), a.length()), ("[1,null,2,null]", 4))


class Time(unittest.TestCase):
    def setUp(self):
        self.utc = J("java.util.TimeZone").getTimeZone("UTC")

    def test_format_and_parse_round_trip(self):
        fmt = J("java.text.SimpleDateFormat")("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
        fmt.setTimeZone(J("java.util.TimeZone").getTimeZone("GMT+05:30"))
        date = J("java.util.Date")(1700000000123)
        self.assertEqual(fmt.format(date), "2023-11-15T03:43:20.123+0530")
        self.assertEqual(fmt.parse("2023-11-15T03:43:20.123+0530").getTime(), 1700000000123)

    def test_unparseable_date_reports_offset(self):
        fmt = J("java.text.SimpleDateFormat")("yyyy-MM-dd")
        with self.assertRaises(J("java.text.ParseException")) as caught:
            fmt.parse("garbage")
        self.assertEqual((caught.exception.getMessage(), caught.exception.getErrorOffset()),
                         ('Unparseable date: "garbage"', 0))

    def test_calendar_is_lenient_and_add_keeps_the_day_valid(self):
        C = J("java.util.Calendar")
        c = C.getInstance(self.utc)
        c.clear()
        c.set(2024, 0, 31, 10, 30)
        c.add(C.MONTH, 1)
        self.assertEqual((c.get(C.MONTH), c.get(C.DAY_OF_MONTH)), (1, 29))
        c.set(C.MONTH, C.FEBRUARY)
        c.set(C.DAY_OF_MONTH, 31)
        self.assertEqual((c.get(C.MONTH), c.get(C.DAY_OF_MONTH)), (2, 2))
        c.set(C.HOUR_OF_DAY, 25)
        self.assertEqual((c.get(C.DAY_OF_MONTH), c.get(C.HOUR_OF_DAY)), (3, 1))
        self.assertEqual(c.getActualMaximum(C.DAY_OF_MONTH), 31)

    def test_two_digit_year_window(self):
        fmt = J("java.text.SimpleDateFormat")("dd.MM.yy")
        fmt.setTimeZone(self.utc)
        self.assertEqual(fmt.parse("05.03.99").getTime(), 920592000000)


class Net(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.path == "/r":
                    self.send_response(302)
                    self.send_header("Location", "/ok?x=1")
                    self.end_headers()
                    return
                if self.path == "/404":
                    self.send_response(404)
                    self.end_headers()
                    self.wfile.write(b"nope")
                    return
                body = gzip.compress(b"hello " + self.headers.get("Accept-Encoding", "").encode())
                self.send_response(200)
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                data = self.rfile.read(int(self.headers["Content-Length"]))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"got:" + data)

        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def read_all(self, stream):
        return bytes(b & 255 for b in stream.readAllBytes())

    def open(self, path):
        return J("java.net.URL")("http://127.0.0.1:%d%s" % (self.port, path)).openConnection()

    def test_redirect_and_gzip_are_followed_and_hidden(self):
        c = self.open("/r")
        self.assertEqual(c.getResponseCode(), 200)
        self.assertEqual(self.read_all(c.getInputStream()), b"hello gzip")
        self.assertIsNone(c.getHeaderField("content-encoding"))
        self.assertTrue(c.getURL().toString().endswith("/ok?x=1"))

    def test_post_sends_the_body(self):
        c = self.open("/p")
        c.setDoOutput(1)
        c.setRequestMethod("POST")
        c.getOutputStream().write(jbytes(65, 66))
        self.assertEqual(self.read_all(c.getInputStream()), b"got:AB")

    def test_status_over_399_is_file_not_found_with_an_error_stream(self):
        c = self.open("/404")
        with self.assertRaises(J("java.io.FileNotFoundException")):
            c.getInputStream()
        self.assertEqual(self.read_all(c.getErrorStream()), b"nope")

    def test_socket_line_echo_does_not_wait_for_eof(self):
        server = J("java.net.ServerSocket")(0)

        def serve():
            conn = server.accept()
            reader = J("java.io.BufferedReader")(J("java.io.InputStreamReader")(conn.getInputStream()))
            writer = J("java.io.PrintWriter")(conn.getOutputStream(), 1)
            writer.println("echo " + reader.readLine())
            writer.flush()
            time.sleep(0.5)
            conn.close()

        threading.Thread(target=serve, daemon=True).start()
        client = J("java.net.Socket")("127.0.0.1", server.getLocalPort())
        writer = J("java.io.PrintWriter")(client.getOutputStream(), 1)
        writer.println("hi")
        writer.flush()
        start = time.time()
        reader = J("java.io.BufferedReader")(J("java.io.InputStreamReader")(client.getInputStream()))
        self.assertEqual(reader.readLine(), "echo hi")
        self.assertLess(time.time() - start, 0.4)
        client.close()
        server.close()

    def test_uri_components_and_resolution(self):
        URI = J("java.net.URI")
        u = URI("http://user@example.com:8080/a/b/../c%20d?q=1&r=%C3%A9#frag")
        self.assertEqual((u.getHost(), u.getPort(), u.getPath(), u.getRawPath(), u.getUserInfo()),
                         ("example.com", 8080, "/a/b/../c d", "/a/b/../c%20d", "user"))
        self.assertEqual(u.normalize().getRawPath(), "/a/c%20d")
        self.assertEqual(u.resolve("../x/y?z").toString(), "http://user@example.com:8080/x/y?z")
        with self.assertRaises(J("java.net.URISyntaxException")) as caught:
            URI("http://a b/")
        self.assertEqual(caught.exception.getIndex(), 8)

    def test_url_encoding(self):
        self.assertEqual(J("java.net.URLEncoder").encode("a b&é/~", "UTF-8"), "a+b%26%C3%A9%2F%7E")
        self.assertEqual(J("java.net.URLDecoder").decode("a+b%26%C3%A9", "UTF-8"), "a b&é")


class Nio(unittest.TestCase):
    def test_wrap_shares_the_array_and_orders_bytes(self):
        array = runtime.new_array("[B", 16)
        buf = J("java.nio.ByteBuffer").wrap(array)
        buf.putInt(0x01020304)
        buf.order(J("java.nio.ByteOrder").LITTLE_ENDIAN)
        buf.putInt(0x01020304)
        buf.putFloat(1.5)
        self.assertEqual(list(array[:12]), [1, 2, 3, 4, 4, 3, 2, 1, 0, 0, -64, 63])
        buf.clear()
        view = buf.asIntBuffer()
        view.put(1, 7)
        self.assertEqual(list(array[4:8]), [7, 0, 0, 0])

    def test_decoder_stops_at_overflow_and_reports_malformed(self):
        charset = J("java.nio.charset.Charset").forName("UTF-8")
        source = J("java.nio.ByteBuffer").wrap(jbytes(-48, -65, -48, -72, -47, -128))
        out = J("java.nio.CharBuffer").allocate(2)
        result = charset.newDecoder().decode(source, out, False)
        self.assertEqual((result.toString(), source.position(), out.position()), ("OVERFLOW", 4, 2))
        with self.assertRaises(J("java.nio.charset.MalformedInputException")):
            charset.newDecoder().decode(J("java.nio.ByteBuffer").wrap(jbytes(-1, 65)))


class Collections(unittest.TestCase):
    def test_properties_round_trip(self):
        p = J("java.util.Properties")()
        text = jbytes(*[ord(c) for c in "# c\na = 1\nb:two\\u0020words\nc=\\\n  cont\n"])
        p.load(J("java.io.ByteArrayInputStream")(text))
        self.assertEqual((p.getProperty("a"), p.getProperty("b"), p.getProperty("c"), p.getProperty("z", "d")),
                         ("1", "two words", "cont", "d"))

    def test_bitset_and_tokenizer(self):
        b = J("java.util.BitSet")()
        b.set(3)
        b.set(5, 8)
        b.set(6, False)
        self.assertEqual((b.toString(), b.cardinality(), b.nextSetBit(4), b.length()), ("{3, 5, 7}", 3, 5, 8))
        t = J("java.util.StringTokenizer")("a, b;c", ", ;")
        self.assertEqual((t.countTokens(), t.nextToken(), t.nextToken()), (3, "a", "b"))

    def test_timer_runs_once_and_cancels(self):
        done = []

        class Task(J("java.util.TimerTask")):
            def run(self):
                done.append(1)

        timer = J("java.util.Timer")(True)
        timer.schedule(Task(), 10)
        time.sleep(0.2)
        timer.cancel()
        self.assertEqual(done, [1])

    def test_set_from_map(self):
        s = J("java.util.Collections").newSetFromMap(J("java.util.HashMap")())
        self.assertTrue(s.add("x"))
        self.assertFalse(s.add("x"))
        self.assertEqual(s.size(), 1)


class Files(unittest.TestCase):
    def test_nio_files_and_random_access(self):
        with tempfile.TemporaryDirectory() as d:
            path = J("java.nio.file.Paths").get(d, ["x.txt"])
            J("java.nio.file.Files").writeString(path, "hi\nyo\n")
            self.assertEqual(J("java.nio.file.Files").readAllLines(path).toString(), "[hi, yo]")
            self.assertEqual(J("java.nio.file.Files").size(path), 6)
            with self.assertRaises(J("java.nio.file.NoSuchFileException")):
                J("java.nio.file.Files").readAllBytes(J("java.nio.file.Paths").get(d, ["missing"]))
            raf = J("java.io.RandomAccessFile")(os.path.join(d, "r.bin"), "rw")
            raf.writeInt(7)
            raf.seek(0)
            self.assertEqual((raf.readInt(), raf.length()), (7, 4))
            raf.close()

    def test_zip_streams_round_trip(self):
        sink = J("java.io.ByteArrayOutputStream")()
        zos = J("java.util.zip.ZipOutputStream")(sink)
        zos.putNextEntry(J("java.util.zip.ZipEntry")("a.txt"))
        zos.write(jbytes(104, 105))
        zos.closeEntry()
        zos.close()
        zis = J("java.util.zip.ZipInputStream")(J("java.io.ByteArrayInputStream")(sink.toByteArray()))
        entry = zis.getNextEntry()
        self.assertEqual((entry.getName(), bytes(b & 255 for b in zis.readAllBytes())), ("a.txt", b"hi"))
        self.assertIsNone(zis.getNextEntry())


class Streams(unittest.TestCase):
    def test_pipeline_and_collectors(self):
        items = J("java.util.ArrayList")()
        for x in ("b", "a", "b", "c"):
            items.add(x)
        C = J("java.util.stream.Collectors")
        self.assertEqual(items.stream().distinct().sorted().collect(C.joining(",")), "a,b,c")
        self.assertEqual(J("java.util.stream.IntStream").rangeClosed(1, 5).sum(), 15)


class AndroidSide(unittest.TestCase):
    def test_shared_preferences_keep_types_and_survive_a_reload(self):
        from android.content import prefs
        with tempfile.TemporaryDirectory() as d:
            store = prefs.open_store(os.path.join(d, "p.json"))
            p = prefs.SharedPreferences(store)
            seen = []

            class Listener:
                def onSharedPreferenceChanged(self, preferences, key):
                    seen.append(key)

            p.registerOnSharedPreferenceChangeListener(Listener())
            p.edit().putInt("i", 3).putFloat("f", 0.1).putBoolean("b", True).putString("s", "x").commit()
            self.assertEqual((p.getInt("i"), p.getBoolean("b"), p.getString("s")), (3, True, "x"))
            self.assertAlmostEqual(p.getFloat("f"), 0.1, places=6)
            self.assertEqual(sorted(seen), ["b", "f", "i", "s"])
            with self.assertRaises(Exception):
                p.getString("i")
            fresh = prefs.SharedPreferences(prefs._Store(os.path.join(d, "p.json")))
            self.assertEqual(fresh.getInt("i"), 3)

    def test_geometry(self):
        from android.graphics import Matrix, Path, PathMeasure, RectF
        p = Path()
        p.addCircle(50, 50, 25, Path.Direction.CW)
        b = RectF()
        p.computeBounds(b, True)
        self.assertEqual(b.toString(), "RectF(25.0, 25.0, 75.0, 75.0)")
        self.assertAlmostEqual(PathMeasure(p, False).getLength(), 157.08, places=1)
        m = Matrix()
        m.setRotate(90, 10, 10)
        m.postTranslate(5, 0)
        pts = [20.0, 10.0]
        m.mapPoints(pts)
        self.assertEqual(pts, [15.0, 20.0])

    def test_spans_follow_edits(self):
        from android.text import ForegroundColorSpan, SpannableStringBuilder, Spanned
        b = SpannableStringBuilder("hello world")
        span = ForegroundColorSpan(0xFF0000)
        b.setSpan(span, 6, 11, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        b.insert(0, ">> ")
        self.assertEqual((b.getSpanStart(span), b.getSpanEnd(span)), (9, 14))
        b.delete(9, 14)
        self.assertEqual(b.getSpans(0, len(b), ForegroundColorSpan), [])

    def test_a_shim_listener_is_a_vm_interface_and_a_python_proxy_is_an_instance(self):
        from java import dynamic_proxy, jclass
        callback = jclass("org.telegram.messenger.Utilities").Callback
        self.assertTrue(api.lookup_host("org.telegram.messenger.Utilities$Callback").isInterface())
        self.assertTrue(api.lookup_host("android.view.View$OnClickListener").isInterface())

        class Proxy(dynamic_proxy(callback)):
            pass

        self.assertEqual(api.lookup_host("org.telegram.messenger.Utilities$Callback").isInstance(Proxy()), 1)

    def test_jclass_falls_back_to_the_vm_for_java_names(self):
        from java import jclass
        self.assertIs(jclass("java.lang.ref.WeakReference"), J("java.lang.ref.WeakReference"))
        self.assertIs(jclass("org.json.JSONObject"), J("org.json.JSONObject"))


class WeakReferences(unittest.TestCase):
    def test_weak_reference_clears_with_its_referent(self):
        class Thing(J("java.lang.Object")):
            pass

        thing = Thing()
        ref = J("java.lang.ref.WeakReference")(thing)
        self.assertIs(ref.get(), thing)
        del thing
        import gc
        gc.collect()
        self.assertIsNone(ref.get())


if __name__ == "__main__":
    unittest.main()


class Drawing(unittest.TestCase):
    def dump(self, bitmap, row):
        return "".join(" .:-=+*#%@"[bitmap._pixels[(row * bitmap._w + x) * 4 + 3] * 10 // 256] for x in range(bitmap._w))

    def test_shapes_are_antialiased_and_clipped(self):
        from android.graphics import Bitmap, Canvas, Paint, RectF
        bitmap = Bitmap(40, 20)
        canvas = Canvas(bitmap)
        fill = Paint()
        fill.setColor(0xFF000000)
        canvas.drawCircle(10, 10, 8, fill)
        self.assertEqual(bitmap.getPixel(10, 10) >> 24 & 255, 255)
        self.assertEqual(bitmap.getPixel(0, 0) >> 24 & 255, 0)
        edge = bitmap.getPixel(2, 10) >> 24 & 255
        self.assertTrue(0 < edge < 255)
        line = Paint()
        line.setColor(0xFF000000)
        line.setStyle(Paint.Style.STROKE)
        line.setStrokeWidth(3)
        canvas.drawRoundRect(RectF(20, 2, 38, 18), 4, 4, line)
        self.assertEqual(bitmap.getPixel(29, 10) >> 24 & 255, 0)
        self.assertEqual(bitmap.getPixel(29, 2) >> 24 & 255, 255)
        canvas.save()
        canvas.clipRect(0, 0, 5, 5)
        canvas.drawColor(0xFFFF0000)
        canvas.restore()
        self.assertEqual(bitmap.getPixel(2, 2), 0xFFFF0000)
        self.assertEqual(bitmap.getPixel(6, 2) >> 16 & 255, 0)

    def test_gradient_xfermode_layer_and_bitmap(self):
        from android.graphics import Bitmap, Canvas, LinearGradient, Paint, PorterDuffXfermode, Rect, RectF, Shader
        bitmap = Bitmap(20, 10)
        canvas = Canvas(bitmap)
        paint = Paint()
        paint.setShader(LinearGradient(0, 0, 20, 0, 0xFF000000, 0x00000000, Shader.TileMode.CLAMP))
        canvas.drawRect(0, 0, 20, 10, paint)
        alphas = [bitmap._pixels[(5 * 20 + x) * 4 + 3] for x in range(0, 20, 4)]
        self.assertEqual(alphas, sorted(alphas, reverse=True))
        green = Bitmap(10, 10)
        gc = Canvas(green)
        solid = Paint()
        solid.setColor(0xFF00FF00)
        gc.drawRect(0, 0, 10, 10, solid)
        clear = Paint()
        clear.setXfermode(PorterDuffXfermode("CLEAR"))
        gc.drawCircle(5, 5, 3, clear)
        self.assertEqual((green.getPixel(5, 5) >> 24 & 255, green.getPixel(0, 0) >> 24 & 255), (0, 255))
        gc.saveLayerAlpha(None, 128)
        gc.drawColor(0xFF0000FF)
        gc.restore()
        self.assertEqual(green.getPixel(0, 0), 0xFF007F80)
        source = Bitmap(2, 2)
        sc = Canvas(source)
        red = Paint()
        red.setColor(0xFFFF0000)
        sc.drawRect(0, 0, 1, 2, red)
        blue = Paint()
        blue.setColor(0xFF0000FF)
        sc.drawRect(1, 0, 2, 2, blue)
        target = Bitmap(8, 4)
        Canvas(target).drawBitmap(source, Rect(0, 0, 2, 2), RectF(0, 0, 8, 4), None)
        self.assertEqual((target.getPixel(1, 1), target.getPixel(6, 1)), (0xFFFF0000, 0xFF0000FF))

    def test_text_is_tinted_from_the_mask_the_app_draws(self):
        """the fake of the app answers one block per character, so this checks the path (request, mask, tint, alignment,
        underline, shader, transfer mode), not the look of glyphs"""
        from android.graphics import Bitmap, Canvas, LinearGradient, Paint, Shader
        bitmap = Bitmap(80, 24)
        canvas = Canvas(bitmap)
        paint = Paint()
        paint.setColor(0xFF112233)
        paint.setTextSize(10)
        fakeapp.fake.calls.clear()
        canvas.drawText("abc", 5, 14, paint)
        requests = [d for n, d in fakeapp.fake.calls if n == "ui.text_image"]
        self.assertEqual((requests[0]["text"], requests[0]["size"], requests[0]["bold"]), ("abc", 10.0, False))
        self.assertEqual(bitmap.getPixel(8, 8), 0xFF112233)
        self.assertEqual(bitmap.getPixel(40, 8) >> 24 & 255, 0)
        right = Bitmap(80, 24)
        paint.setTextAlign(Paint.Align.RIGHT)
        Canvas(right).drawText("abc", 70, 14, paint)
        self.assertEqual((right.getPixel(68, 8) >> 24 & 255, right.getPixel(40, 8) >> 24 & 255), (255, 0))
        underlined = Bitmap(80, 24)
        paint.setTextAlign(Paint.Align.LEFT)
        paint.setUnderlineText(True)
        Canvas(underlined).drawText("abc", 5, 14, paint)
        self.assertEqual(underlined.getPixel(8, 15) >> 24 & 255, 255)
        shaded = Bitmap(80, 24)
        paint.setUnderlineText(False)
        paint.setShader(LinearGradient(0, 0, 80, 0, 0xFFFF0000, 0xFF0000FF, Shader.TileMode.CLAMP))
        Canvas(shaded).drawText("abcdefghij", 0, 14, paint)
        self.assertGreater(shaded.getPixel(2, 8) >> 16 & 255, shaded.getPixel(50, 8) >> 16 & 255)
        bold = Paint()
        bold.setTextSize(10)
        bold.setFakeBoldText(True)
        fakeapp.fake.calls.clear()
        Canvas(Bitmap(40, 20)).drawText("x", 0, 10, bold)
        self.assertTrue([d for n, d in fakeapp.fake.calls if n == "ui.text_image"][0]["bold"])

    def test_text_the_app_cannot_draw_is_an_error(self):
        from android.graphics import Bitmap, Canvas, Paint
        paint = Paint()
        paint.setTextSize(10)
        with self.assertRaises(Exception):
            Canvas(Bitmap(4, 4)).drawTextRun("x", 0, 0, paint)

    def test_png_compress_is_a_png(self):
        from android.graphics import Bitmap, Canvas
        bitmap = Bitmap(4, 4)
        Canvas(bitmap).drawColor(0xFFFF0000)
        out = J("java.io.ByteArrayOutputStream")()
        self.assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out))
        data = bytes(b & 255 for b in out.toByteArray())
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")

    def test_a_view_that_overrides_ondraw_is_painted_into_a_layer(self):
        from android import _ui
        from android.app import activity
        from android.graphics import Canvas, Paint
        from android.view import LayoutParams, View

        class Dot(View):
            def onDraw(self, canvas):
                paint = Paint()
                paint.setColor(0xFF00FF00)
                canvas.drawCircle(10, 10, 8, paint)

        fakeapp.fake.ops.clear()
        decor = activity().getWindow().getDecorView()
        dot = Dot(decor.getContext())
        decor.addView(dot, LayoutParams(20, 20))
        _ui.flush()
        images = [op for op in fakeapp.fake.ops if op[0] == "img" and op[1] == dot._id]
        self.assertEqual(len(images), 1)
        self.assertEqual(images[0][2:4], [20, 20])
        decor.removeView(dot)
        _ui.flush()

    def test_dialog_shows_over_the_window_and_dismisses(self):
        from android.app import AlertDialog, activity
        pressed = []
        dialog = AlertDialog.Builder(activity()).setTitle("t").setPositiveButton("ok", lambda d, w: pressed.append(w)).create()
        decor = activity().getWindow().getDecorView()
        before = decor.getChildCount()
        dialog.show()
        self.assertEqual((dialog.isShowing(), decor.getChildCount()), (True, before + 1))
        dialog.dismiss()
        self.assertEqual((dialog.isShowing(), decor.getChildCount()), (False, before))


class BrowserOpen(unittest.TestCase):
    def test_web_and_telegram_addresses_go_to_the_app(self):
        from android.net import Uri
        from org.telegram.messenger.browser import Browser
        fakeapp.fake.opened.clear()
        Browser.openUrl(None, "https://example.com/a")
        Browser.openUrl(None, Uri("tg://resolve?domain=x"), True, False)
        self.assertEqual(fakeapp.fake.opened, ["https://example.com/a", "tg://resolve?domain=x"])
        self.assertTrue(Browser.isInternalUrl("https://t.me/x"))
        self.assertFalse(Browser.isInternalUrl("https://example.com"))

    def test_other_schemes_are_refused(self):
        from java.lang import IllegalArgumentException
        from org.telegram.messenger.browser import Browser
        for bad in ("tel:123", "file:///etc/passwd", "javascript:1", "https:///nohost", ""):
            with self.assertRaises(IllegalArgumentException):
                Browser.openUrl(None, bad)

    def test_a_dex_class_name_resolves(self):
        self.assertIsNotNone(api.lookup_host("org.telegram.messenger.browser.Browser"))
        self.assertIsNotNone(api.lookup_host("org.telegram.messenger.browser.Browser$Progress"))


class CoreAdditions(unittest.TestCase):
    def static(self, cls, name, descriptor):
        from dexvm import classes
        function, _ = classes.host_static(api.lookup_host(cls), name, descriptor)
        self.assertIsNotNone(function, name)
        return function

    def test_surrogates_and_code_points(self):
        self.assertEqual(self.static("java.lang.Character", "isHighSurrogate", "(C)Z")(0xD83D), 1)
        self.assertEqual(self.static("java.lang.Character", "toCodePoint", "(CC)I")(0xD83D, 0xDE00), 0x1F600)
        self.assertEqual(self.static("java.lang.Character", "charCount", "(I)I")(0x1F600), 2)

    def test_unsigned_and_exact_arithmetic(self):
        self.assertEqual(self.static("java.lang.Long", "parseUnsignedLong", "(Ljava/lang/String;)J")("18446744073709551615"), -1)
        self.assertEqual(self.static("java.lang.Integer", "compareUnsigned", "(II)I")(-1, 1), 1)
        self.assertEqual(self.static("java.lang.Integer", "toUnsignedLong", "(I)J")(-1), 0xFFFFFFFF)
        with self.assertRaises(J("java.lang.ArithmeticException")):
            self.static("java.lang.Math", "subtractExact", "(II)I")(-0x80000000, 1)
        self.assertEqual(self.static("java.lang.Math", "cbrt", "(D)D")(-8.0), -2.0)

    def test_native_libraries_are_refused_by_name(self):
        with self.assertRaises(J("java.lang.UnsatisfiedLinkError")) as caught:
            self.static("java.lang.System", "load", "(Ljava/lang/String;)V")("/x/libx.so")
        self.assertIn("libx.so", caught.exception.getMessage())

    def test_reflection_takes_python_arguments_and_shim_classes(self):
        from java import jclass
        reflect = J("java.lang.reflect.Modifier")
        self.assertEqual(self.static("java.lang.reflect.Modifier", "isVolatile", "(I)Z")(64), 1)
        build_vars = api.lookup_host("org.telegram.messenger.BuildVars")
        from dexvm import jreflect
        field = jreflect.find_field(build_vars, "BUILD_VERSION_STRING", False)
        self.assertEqual(field.getName(), "BUILD_VERSION_STRING")
        self.assertIsNotNone(jclass)
        self.assertIsNotNone(reflect)
