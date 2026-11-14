"""the classes the plugins of the public catalogs name and the shim lacked: the settings cells, RadialProgressView, ActionBarMenuSubItem,
ActivityThread and ExifInterface over a jpeg assembled here byte by byte"""

import os
import shutil
import struct
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
from android.app import activity  # noqa: E402
from android.graphics import Bitmap  # noqa: E402
from android.graphics.drawable import BitmapDrawable, ColorDrawable  # noqa: E402
from android.view import View  # noqa: E402
from android.widget import FrameLayout  # noqa: E402
from java import jclass  # noqa: E402


def tiff(entries, order=">"):
    """a one directory Exif block. entries: (tag, type, count, raw bytes); a raw value over four bytes goes after the table"""
    marker = b"MM\0*" if order == ">" else b"II*\0"
    table = struct.pack(order + "H", len(entries))
    tail = b""
    base = 8 + 2 + 12 * len(entries) + 4
    for tag, kind, count, raw in entries:
        if len(raw) <= 4:
            value = raw + b"\0" * (4 - len(raw))
        else:
            value = struct.pack(order + "I", base + len(tail))
            tail += raw + (b"\0" if len(raw) & 1 else b"")
        table += struct.pack(order + "HHI", tag, kind, count) + value
    return marker + struct.pack(order + "I", 8) + table + struct.pack(order + "I", 0) + tail


def jpeg(block=None, jfif=False):
    out = b"\xff\xd8"
    if jfif:
        out += b"\xff\xe0\x00\x10JFIF\0\x01\x01\0\0\x01\0\x01\0\0"
    if block is not None:
        out += b"\xff\xe1" + struct.pack(">H", len(block) + 8) + b"Exif\0\0" + block
    return out + b"\xff\xdb\x00\x04\x00\x00" + b"\xff\xda\x00\x02" + b"scan-bytes" + b"\xff\xd9"


def read(path):
    with open(path, "rb") as handle:
        return handle.read()


def ascii_entry(tag, text):
    raw = text.encode() + b"\0"
    return (tag, 2, len(raw), raw)


def short_entry(tag, value, order=">"):
    return (tag, 3, 1, struct.pack(order + "H", value))


class Cells(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()

    def show(self, view, width=300, height=48):
        self.decor.addView(view, FrameLayout.LayoutParams(width, height))
        _ui.flush()
        return view

    def test_a_header_shows_its_text_and_an_optional_second_line(self):
        cell = jclass("org.telegram.ui.Cells.HeaderCell")(self.decor.getContext())
        cell.setText("Options")
        self.show(cell)
        self.assertEqual(str(cell.getTextView().getText()), "Options")
        self.assertEqual(cell._sub.getVisibility(), View.GONE)
        cell.setText2("more")
        self.assertEqual((cell._sub.getVisibility(), str(cell._sub.getText())), (View.VISIBLE, "more"))
        cell.setText2(None)
        self.assertEqual(cell._sub.getVisibility(), View.GONE)

    def test_a_settings_cell_has_a_text_a_value_and_colors(self):
        cell = jclass("org.telegram.ui.Cells.TextSettingsCell")(self.decor.getContext())
        cell.setTextAndValue("Speed", "2x", True)
        cell.setTextColor(0xFFFF0000)
        self.show(cell)
        self.assertEqual((str(cell.getTextView().getText()), str(cell.getValueTextView().getText())), ("Speed", "2x"))
        self.assertEqual(cell.getValueTextView().getVisibility(), View.VISIBLE)
        self.assertEqual(cell.getTextView()._color, 0xFFFF0000)
        self.assertLess(cell.getTextView().getLeft() + cell.getTextView().getWidth(), cell.getValueTextView().getLeft() + 1)
        cell.setText("Plain", False)
        self.assertEqual(cell.getValueTextView().getVisibility(), View.GONE)

    def test_a_settings_cell_dims_only_when_it_can_be_disabled(self):
        cell = jclass("org.telegram.ui.Cells.TextSettingsCell")(self.decor.getContext())
        cell.setEnabled(False)
        self.assertEqual(cell.getAlpha(), 1.0)
        cell.setCanDisable(True)
        cell.setEnabled(False)
        self.assertEqual(cell.getAlpha(), 0.5)
        cell.setEnabled(True)
        self.assertEqual(cell.getAlpha(), 1.0)

    def test_a_check_cell_keeps_the_state_the_plugin_gives_it(self):
        cell = jclass("org.telegram.ui.Cells.TextCheckCell")(self.decor.getContext())
        cell.setTextAndCheck("Loud", True, False)
        self.show(cell)
        self.assertTrue(cell.isChecked())
        self.assertEqual(str(cell._label.getText()), "Loud")
        cell.setTextAndValueAndCheck("Loud", "very", False, True, False)
        self.assertEqual((cell.isChecked(), str(cell._value.getText()), cell._value.getVisibility()), (False, "very", View.VISIBLE))
        cell.setEnabled(False)
        self.assertEqual(cell._column.getAlpha(), 0.5)

    def test_a_menu_item_takes_a_picture_or_a_drawable_and_refuses_a_resource_number(self):
        item = jclass("org.telegram.ui.ActionBar.ActionBarMenuSubItem")(self.decor.getContext(), False, True)
        self.show(item)
        self.assertEqual(item._icon.getVisibility(), View.GONE)
        item.setTextAndIcon("Edit", BitmapDrawable(None, Bitmap(4, 4)))
        self.assertEqual((str(item.getTextView().getText()), item._icon.getVisibility()), ("Edit", View.VISIBLE))
        item.setIcon(ColorDrawable(0xFF00FF00))
        self.assertEqual(item._icon.getVisibility(), View.VISIBLE)
        item.setColors(0xFF112233, 0xFF445566)
        self.assertEqual(item.getTextView()._color, 0xFF112233)
        item.setIcon(None)
        self.assertEqual(item._icon.getVisibility(), View.GONE)
        with self.assertRaises(NotImplementedError):
            item.setTextAndIcon("Edit", 2131230000)


class Spinner(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fake.timers.clear()
        fake.ops.clear()
        self.spinner = jclass("org.telegram.ui.Components.RadialProgressView")(self.decor.getContext())

    def frames(self):
        return [op for op in fake.ops if op[0] == "img" and op[1] == self.spinner._id]

    def run_next(self):
        token, _delay = fake.timers.pop(0)
        exteria_host.run_token(token)
        _ui.flush()

    def test_it_has_the_size_it_is_given(self):
        self.spinner.setSize(36)
        self.decor.addView(self.spinner, FrameLayout.LayoutParams(-2, -2))
        _ui.flush()
        self.assertEqual((self.spinner.getWidth(), self.spinner.getHeight()), (36, 36))

    def test_it_spins_while_it_is_in_a_window_and_stops_when_it_leaves(self):
        self.decor.addView(self.spinner, FrameLayout.LayoutParams(40, 40))
        _ui.flush()
        first = len(self.frames())
        self.assertGreater(first, 0)
        self.assertEqual(len(fake.timers), 1)
        self.run_next()
        self.assertEqual(len(self.frames()), first + 1)
        self.assertEqual(len(fake.timers), 1)
        self.decor.removeAllViews()
        _ui.flush()
        self.run_next()
        self.assertEqual(fake.timers, [])

    def test_two_restarts_leave_one_loop(self):
        self.decor.addView(self.spinner, FrameLayout.LayoutParams(40, 40))
        _ui.flush()
        self.spinner.setNoProgress(True)
        self.spinner.setNoProgress(True)
        fake.timers.sort()
        for _ in range(len(fake.timers)):
            self.run_next()
        self.assertLessEqual(len(fake.timers), 1)

    def test_a_determinate_ring_does_not_spin(self):
        self.decor.addView(self.spinner, FrameLayout.LayoutParams(40, 40))
        _ui.flush()
        self.spinner.setNoProgress(False)
        self.spinner.setProgress(0.25)
        self.assertEqual(self.spinner.getProgress(), 0.25)
        fake.timers.clear()
        fake.ops.clear()
        self.spinner.setProgress(5)
        _ui.flush()
        self.assertEqual(self.spinner.getProgress(), 1.0)
        self.assertEqual(fake.timers, [])


class Application(unittest.TestCase):
    def test_the_current_application_is_the_context_with_a_files_folder(self):
        context = jclass("android.app.ActivityThread").currentApplication()
        self.assertTrue(os.path.isdir(str(context.getFilesDir())) or str(context.getFilesDir()).startswith("/"))
        self.assertEqual(context.getPackageName(), activity().getPackageName())


class Exif(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="exteria-exif-")
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.Exif = jclass("android.media.ExifInterface")

    def write(self, name, data):
        path = os.path.join(self.folder, name)
        with open(path, "wb") as handle:
            handle.write(data)
        return path

    def sample(self, order=">"):
        entries = [ascii_entry(0x010F, "Acme"), ascii_entry(0x0110, "Phone 1"), short_entry(0x0112, 6, order)]
        return self.write("a.jpg", jpeg(tiff(entries, order), jfif=True))

    def test_text_and_number_tags_are_read_in_both_byte_orders(self):
        for order in (">", "<"):
            exif = self.Exif(self.sample(order))
            self.assertEqual((exif.getAttribute(self.Exif.TAG_MAKE), exif.getAttribute(self.Exif.TAG_MODEL)), ("Acme", "Phone 1"))
            self.assertEqual(exif.getAttribute("Orientation"), "6")
            self.assertEqual(exif.getAttributeInt("Orientation", 1), 6)
            self.assertEqual(exif.getRotationDegrees(), 90)
            self.assertIsNone(exif.getAttribute("Software"))
            self.assertEqual(exif.getAttributeInt("Software", 7), 7)
            self.assertTrue(exif.hasAttribute("Make"))
            self.assertFalse(exif.hasAttribute("Software"))

    def test_a_file_without_exif_or_not_a_jpeg_has_no_attributes(self):
        plain = self.Exif(self.write("p.jpg", jpeg()))
        self.assertIsNone(plain.getAttribute("Make"))
        png = self.Exif(self.write("p.png", b"\x89PNG\r\n\x1a\n" + b"\0" * 32))
        self.assertIsNone(png.getAttribute("Make"))
        with self.assertRaises(jclass("java.io.IOException")):
            png.saveAttributes()

    def test_a_missing_file_is_a_file_not_found(self):
        with self.assertRaises(jclass("java.io.FileNotFoundException")):
            self.Exif(os.path.join(self.folder, "none.jpg"))

    def test_rationals_gps_and_the_user_comment(self):
        order = ">"
        rationals = struct.pack(order + "IIIIII", 40, 1, 26, 1, 4620, 100)
        # a gps directory after the first: IFD0 holds only the pointer, the pointer says where the second directory starts
        gps = [(0x0001, 2, 2, b"N\0"), (0x0002, 5, 3, rationals), (0x0003, 2, 2, b"W\0"), (0x0004, 5, 3, struct.pack(order + "IIIIII", 74, 1, 0, 1, 0, 1))]
        first = struct.pack(order + "H", 1) + struct.pack(order + "HHI", 0x8825, 4, 1) + struct.pack(order + "I", 8 + 2 + 12 + 4) + struct.pack(order + "I", 0)
        second_at = 8 + len(first)
        table = struct.pack(order + "H", len(gps))
        tail = b""
        base = second_at + 2 + 12 * len(gps) + 4
        for tag, kind, count, raw in gps:
            if len(raw) <= 4:
                value = raw + b"\0" * (4 - len(raw))
            else:
                value = struct.pack(order + "I", base + len(tail))
                tail += raw
            table += struct.pack(order + "HHI", tag, kind, count) + value
        block = b"MM\0*" + struct.pack(order + "I", 8) + first + table + struct.pack(order + "I", 0) + tail
        exif = self.Exif(self.write("g.jpg", jpeg(block)))
        self.assertEqual(exif.getAttribute(self.Exif.TAG_GPS_LATITUDE), "40/1,26/1,4620/100")
        lat, lon = exif.getLatLong()
        self.assertAlmostEqual(lat, 40 + 26 / 60.0 + 46.2 / 3600.0, places=9)
        self.assertAlmostEqual(lon, -74.0, places=9)
        self.assertEqual(exif.getAttributeDouble("GPSLongitude", 0.0), 74.0)

    def test_the_exposure_time_is_answered_as_a_decimal(self):
        # these two belong to the Exif directory: the writer of the shim puts them there and the reader finds them in the saved file
        exif = self.Exif(self.sample())
        exif.setAttribute("ExposureTime", "1/4")
        exif.setAttribute("FNumber", "2.8")
        exif.saveAttributes()
        again = self.Exif(exif._path)
        self.assertEqual(again.getAttribute("ExposureTime"), "0.25")
        self.assertEqual(again.getAttribute("FNumber"), "2.8")

    def test_a_changed_tag_survives_a_save_and_the_rest_of_the_file_is_untouched(self):
        path = self.sample()
        original = read(path)
        exif = self.Exif(path)
        exif.setAttribute("Make", "Other")
        exif.setAttribute("DateTimeOriginal", "2024:05:06 07:08:09")
        exif.setAttribute("UserComment", "note")
        exif.setAttribute("ISOSpeedRatings", "400")
        exif.saveAttributes()
        data = read(path)
        again = self.Exif(path)
        self.assertEqual(again.getAttribute("Make"), "Other")
        self.assertEqual(again.getAttribute("Model"), "Phone 1")
        self.assertEqual(again.getAttribute("DateTimeOriginal"), "2024:05:06 07:08:09")
        self.assertEqual(again.getAttribute("UserComment"), "note")
        self.assertEqual(again.getAttributeInt("ISOSpeedRatings", 0), 400)
        self.assertTrue(data.startswith(b"\xff\xd8\xff\xe0\x00\x10JFIF"))
        self.assertTrue(data.endswith(b"\xff\xdb\x00\x04\x00\x00\xff\xda\x00\x02scan-bytes\xff\xd9"))
        self.assertEqual(original[:20], data[:20])

    def test_removing_every_tag_removes_the_exif_segment(self):
        path = self.sample()
        exif = self.Exif(path)
        for tag in ("Make", "Model", "Orientation"):
            exif.setAttribute(tag, None)
        exif.saveAttributes()
        data = read(path)
        self.assertNotIn(b"Exif\0\0", data)
        self.assertEqual(data, jpeg(None, jfif=True))
        self.assertIsNone(self.Exif(path).getAttribute("Make"))

    def test_the_exif_segment_is_added_after_the_jfif_one(self):
        path = self.write("n.jpg", jpeg(None, jfif=True))
        exif = self.Exif(path)
        exif.setAttribute("Software", "tool 1")
        exif.saveAttributes()
        data = read(path)
        self.assertEqual(data[:4], b"\xff\xd8\xff\xe0")
        self.assertEqual(data[20:22], b"\xff\xe1")
        self.assertEqual(self.Exif(path).getAttribute("Software"), "tool 1")
        bare = self.write("b.jpg", jpeg())
        exif = self.Exif(bare)
        exif.setAttribute("Software", "tool 2")
        exif.saveAttributes()
        self.assertEqual(read(bare)[2:4], b"\xff\xe1")

    def test_a_tag_the_runtime_does_not_know_is_an_error_a_value_of_the_wrong_kind_too(self):
        from java.lang import IllegalArgumentException
        exif = self.Exif(self.sample())
        with self.assertRaises(IllegalArgumentException):
            exif.setAttribute("FocalPlaneXResolution", "1")
        with self.assertRaises(IllegalArgumentException):
            exif.getAttribute("Nonsense")
        with self.assertRaises(IllegalArgumentException):
            exif.setAttribute("Orientation", "up")
        with self.assertRaises(IllegalArgumentException):
            exif.setAttribute("Orientation", "70000")
        with self.assertRaises(IllegalArgumentException):
            exif.setAttribute("ExposureTime", "1/x")
        self.assertEqual(exif.getAttribute("Orientation"), "6")

    def test_a_damaged_block_is_an_io_error_and_not_a_wrong_answer(self):
        good = tiff([ascii_entry(0x010F, "Acme")])
        for block in (b"XX\0*" + good[4:], good[:20], good[:4] + struct.pack(">I", 9999) + good[8:],
                      b"MM\0*" + struct.pack(">I", 8) + struct.pack(">H", 600) + b"\0" * 12):
            with self.assertRaises(jclass("java.io.IOException"), msg=block[:12]):
                self.Exif(self.write("bad.jpg", jpeg(block)))

    def test_a_segment_longer_than_the_file_is_an_io_error(self):
        broken = b"\xff\xd8\xff\xe1\xff\xf0Exif\0\0short"
        with self.assertRaises(jclass("java.io.IOException")):
            self.Exif(self.write("cut.jpg", broken))

    def test_the_file_mode_survives_a_save(self):
        path = self.sample()
        os.chmod(path, 0o640)
        exif = self.Exif(path)
        exif.setAttribute("Make", "Z")
        exif.saveAttributes()
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o640)
        self.assertEqual([n for n in os.listdir(self.folder) if n.startswith(".exif-")], [])

    def test_the_constants_use_the_android_names(self):
        for constant, value in (("TAG_MAKE", "Make"), ("TAG_GPS_LATITUDE_REF", "GPSLatitudeRef"), ("TAG_GPS_PROCESSING_METHOD", "GPSProcessingMethod"),
                                ("TAG_USER_COMMENT", "UserComment"), ("TAG_IMAGE_DESCRIPTION", "ImageDescription"), ("TAG_DATETIME", "DateTime"), ("TAG_DATETIME_ORIGINAL", "DateTimeOriginal"),
                                ("TAG_DATETIME_DIGITIZED", "DateTimeDigitized")):
            self.assertEqual(getattr(self.Exif, constant, None), value, constant)
        self.assertEqual(self.Exif.ORIENTATION_ROTATE_90, 6)


if __name__ == "__main__":
    unittest.main()
