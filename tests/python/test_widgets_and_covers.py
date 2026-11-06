"""the widgets a plugin that shows progress and embeds a cover uses: ColorStateList, RippleDrawable, TextUtils and the line limit of a TextView, and a
cover picture cut square, shrunk and written as a jpeg with BitmapFactory, Bitmap and FileOutputStream. the real playlist_to_profile helper runs when
EXTERIA_PLAYLIST_PLUGIN names its file"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from android import _ui  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402

PLUGINS = None
_saved = {}


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-cover-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


class Widgets(unittest.TestCase):
    def setUp(self):
        fake.ops.clear()

    def test_a_ripple_is_the_background_of_its_content(self):
        from android.content.res import ColorStateList
        from android.graphics.drawable import GradientDrawable, RippleDrawable
        from android.widget import LinearLayout
        from android.app import activity
        shape = GradientDrawable()
        shape.setColor(0xFF112233)
        shape.setCornerRadius(12.0)
        ripple = RippleDrawable(ColorStateList.valueOf(0x30FFFFFF), shape, None)
        view = LinearLayout(activity())
        activity().getWindow().getDecorView().addView(view)
        try:
            view.setBackground(ripple)
            _ui.flush()
            sets = {}
            for op in fake.ops:
                if op[0] == "set" and op[1] == view._id:
                    sets.update(op[2])
            self.assertEqual(sets["bg"], shape._encode())
            self.assertEqual(ColorStateList.valueOf(0x80010203).getDefaultColor(), 0x80010203)
            with self.assertRaises(TypeError):
                RippleDrawable(0x30FFFFFF, shape, None)
        finally:
            activity().getWindow().getDecorView().removeView(view)
            _ui.flush()

    def test_a_text_view_takes_the_lines_it_is_given_and_keeps_the_ellipsize_it_was_told(self):
        from android.app import activity
        from android.text import TextUtils
        from android.widget import TextView
        import unittest.mock
        # five lines of text and one line of 18 points, as the app would measure them
        measure = unittest.mock.patch.object(_ui, "measure_text", lambda text, size, bold, width: (100, 18 if text == "A" else 90))
        measure.start()
        self.addCleanup(measure.stop)
        view = TextView(activity())
        view.setText("a long text " * 40)
        view.setTextSize(14.0)
        decor = activity().getWindow().getDecorView()
        decor.addView(view)
        try:
            tall = view.getHeight()
            view.setSingleLine(True)
            view.setEllipsize(TextUtils.TruncateAt.END)
            self.assertEqual(view.getEllipsize(), TextUtils.TruncateAt.END)
            line = 18
            self.assertEqual(tall, 90)
            self.assertEqual(view.getHeight(), line)
            self.assertLess(view.getHeight(), tall)
            view.setMaxLines(2)
            self.assertEqual(view.getHeight(), 2 * line)
            self.assertEqual(view.getMaxLines(), 2)
            _ui.flush()
            lines = [op[2]["lines"] for op in fake.ops if op[0] == "set" and op[1] == view._id and "lines" in op[2]]
            self.assertEqual(lines[-1], 2)
            view.setSingleLine(False)
            self.assertEqual(view.getHeight(), tall)
            self.assertTrue(TextUtils.isEmpty(None) and TextUtils.isEmpty("") and not TextUtils.isEmpty("a"))
        finally:
            decor.removeView(view)
            _ui.flush()


class Covers(unittest.TestCase):
    def setUp(self):
        fake.bitmaps.clear()
        fake.pictures.clear()
        fake.encoded.clear()
        fake.settings.clear()
        self.cache = tempfile.mkdtemp(prefix="exteria-cover-files-")
        self.source = os.path.join(self.cache, "cover.webp")
        self.target = os.path.join(self.cache, "cover.jpg")
        with open(self.source, "wb") as handle:
            handle.write(b"x" * 100)

    def tearDown(self):
        shutil.rmtree(self.cache, ignore_errors=True)

    def test_a_cover_is_cut_square_shrunk_and_written_as_a_jpeg(self):
        from android.graphics import Bitmap, BitmapFactory
        from java.io import FileOutputStream
        fake.pictures[self.source] = (1600, 900)
        bmp = BitmapFactory.decodeFile(self.source)
        self.assertEqual((bmp.getWidth(), bmp.getHeight()), (1600, 900))
        square = Bitmap.createBitmap(bmp, 350, 0, 900, 900)
        self.assertEqual((square.getWidth(), square.getHeight()), (900, 900))
        small = Bitmap.createScaledBitmap(square, 800, 800, True)
        out = FileOutputStream(self.target)
        try:
            self.assertTrue(small.compress(Bitmap.CompressFormat.JPEG, 90, out))
            out.flush()
        finally:
            out.close()
        self.assertEqual(fake.encoded, [{"handle": small._handle, "png": False, "quality": 90, "path": self.target}])
        self.assertGreater(os.path.getsize(self.target), 500)

    def test_what_cannot_be_done_with_a_picture_is_refused(self):
        from android.graphics import Bitmap, BitmapFactory
        from java.io import FileOutputStream
        fake.pictures[self.source] = (100, 100)
        bmp = BitmapFactory.decodeFile(self.source)
        with self.assertRaises(Exception):
            Bitmap.createBitmap(bmp, 50, 50, 80, 80)
        with self.assertRaises(NotImplementedError):
            Bitmap.createBitmap(Bitmap.createBitmap(4, 4), 0, 0, 2, 2)
        with self.assertRaises(NotImplementedError):
            Bitmap.createBitmap(bmp, 0, 0)
        out = FileOutputStream(self.target)
        with self.assertRaises(NotImplementedError):
            bmp.compress(Bitmap.CompressFormat.WEBP, 90, out)
        with self.assertRaises(NotImplementedError):
            bmp.compress(Bitmap.CompressFormat.JPEG, 90, object())
        with self.assertRaises(NotImplementedError):
            out.write(b"x")
        self.assertIsNone(BitmapFactory.decodeFile(os.path.join(self.cache, "nothing.jpg")))
        with self.assertRaises(NotImplementedError):
            BitmapFactory.decodeFile(self.source, object())


@unittest.skipUnless(os.environ.get("EXTERIA_PLAYLIST_PLUGIN"), "set EXTERIA_PLAYLIST_PLUGIN to the file of the plugin")
class RealPlugin(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(PLUGINS, "playlist_to_profile.plugin")
        shutil.copy(os.environ["EXTERIA_PLAYLIST_PLUGIN"], self.path)
        lib = os.environ.get("EXTERIA_PYTHON_LIB")
        if lib:
            sys.path.insert(0, lib)
        self.assertTrue(exteria_host.load(self.path, "playlist_to_profile")["ok"])
        self.cache = tempfile.mkdtemp(prefix="exteria-cover-files-")

    def tearDown(self):
        exteria_host.unload("playlist_to_profile")
        shutil.rmtree(self.cache, ignore_errors=True)

    def module(self):
        return next(m for m in list(sys.modules.values()) if type(m).__name__ == "module" and callable(getattr(m, "_normalize_cover", None)) and callable(getattr(m, "_rounded_bitmap", None)))

    def test_the_cover_helper_of_the_plugin_writes_the_square_jpeg_with_the_android_classes(self):
        source = os.path.join(self.cache, "c.webp")
        target = os.path.join(self.cache, "c.jpg")
        with open(source, "wb") as handle:
            handle.write(b"x" * 100)
        fake.pictures[source] = (1600, 900)
        fake.encoded.clear()
        self.assertTrue(self.module()._normalize_cover(source, target))
        self.assertEqual([(e["path"], e["png"]) for e in fake.encoded], [(target, False)])
        # the squares of 900 and of 800 are the ones that were let go of again
        import gc
        gc.collect()
        _ui.flush()
        self.assertEqual(len(fake.bitmaps), 0)

    def test_the_rounded_cover_of_the_panel_says_why_it_is_not_drawn_and_gives_none(self):
        source = os.path.join(self.cache, "c.webp")
        with open(source, "wb") as handle:
            handle.write(b"x" * 100)
        fake.pictures[source] = (200, 200)
        self.assertIsNone(self.module()._rounded_bitmap(source, 64, 10))
        reasons = [d["message"] for c, d in list(fake.calls) if c == "log" and "rounded bitmap" in d.get("message", "")]
        self.assertTrue(reasons)


if __name__ == "__main__":
    unittest.main()
