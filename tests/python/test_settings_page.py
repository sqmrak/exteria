"""the settings tab as a page plugins hook (SettingsActivity: createView, onResume, onPause), the picker of pictures that answers through
LaunchActivity.onActivityResult, the pictures the app decodes, shrinks and blurs, and the color filters that dim a picture and make the
cards see-through. the plugin here does what a wallpaper plugin does; the real one runs when EXTERIA_SETTINGS_WALLPAPER names its file"""

import gc
import json
import os
import shutil
import sys
import tempfile
import time
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

HEADER = '''
__id__ = "%(id)s"
__name__ = "%(id)s"
__description__ = "test"
__author__ = "test"
__version__ = "1.0"
__min_version__ = "11.9.0"
__icon__ = "msg_edit"
'''

WALLPAPER = HEADER + '''
from base_plugin import BasePlugin
from android_utils import run_on_ui_thread
from hook_utils import find_class, get_private_field
from java import jclass
from android.content import Intent
from android.net import Uri
from android.app import Activity
from android.graphics import Color, BitmapFactory, Bitmap, ColorMatrix, ColorMatrixColorFilter, PorterDuff, PorterDuffColorFilter
from android.widget import ImageView, FrameLayout
from org.telegram.messenger import Utilities

REQUEST = 0xC11B


class Wall(BasePlugin):
    def on_plugin_load(self):
        self.refs = []
        self.set_setting("events", "")
        for name, args in (("onResume", ()), ("onPause", ()), ("createView", (jclass("android.content.Context"),))):
            method = find_class("org.telegram.ui.SettingsActivity").getClass().getDeclaredMethod(name, *args)
            method.setAccessible(True)
            self.refs.append(self.hook_method(method, Seen(self, name)))
        launch = find_class("org.telegram.ui.LaunchActivity")
        int_type = jclass("java.lang.Integer").TYPE
        result = launch.getClass().getDeclaredMethod("onActivityResult", int_type, int_type, jclass("android.content.Intent"))
        self.refs.append(self.hook_method(result, Taken(self)))

    def noted(self, name):
        self.set_setting("events", (self.get_setting("events", "") or "") + name + ",")

    def pick(self):
        intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.setType("image/*")
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        from android.app import activity
        activity().startActivityForResult(intent, REQUEST)

    def apply(self, fragment):
        root = fragment.getFragmentView()
        address = self.get_setting("uri", "")
        if not address:
            return
        view = None
        for i in range(root.getChildCount()):
            if isinstance(root.getChildAt(i), ImageView):
                view = root.getChildAt(i)
        if view is None:
            view = ImageView(root.getContext())
            view.setTag("wall")
            root.addView(view, 0, FrameLayout.LayoutParams(-1, -1))
        from android.app import activity
        stream = activity().getContentResolver().openInputStream(Uri.parse(address))
        bitmap = BitmapFactory.decodeStream(stream)
        stream.close()
        if bitmap is None:
            return
        if bitmap.getWidth() > 1920 or bitmap.getHeight() > 1920:
            r = min(1920 / bitmap.getWidth(), 1920 / bitmap.getHeight())
            bitmap = Bitmap.createScaledBitmap(bitmap, int(bitmap.getWidth() * r), int(bitmap.getHeight() * r), True)
        if not bitmap.isMutable():
            bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, True)
        Utilities.stackBlurBitmap(bitmap, int(self.get_setting("blur", 0)))
        self.bitmap = bitmap
        view.setImageBitmap(bitmap)
        view.setScaleType(ImageView.ScaleType.CENTER_CROP)
        view.setColorFilter(PorterDuffColorFilter(Color.argb(int(self.get_setting("dim", 0)), 0, 0, 0), PorterDuff.Mode.SRC_ATOP))
        listing = get_private_field(fragment, "listView")
        scale = int(self.get_setting("card", 255))
        matrix = ColorMatrix()
        matrix.setScale(1.0, 1.0, 1.0, scale / 255.0)
        for field in listing.getClass().getDeclaredFields():
            if str(field.getName()) == "sectionBackgroundPaint":
                field.setAccessible(True)
                field.get(listing).setColorFilter(ColorMatrixColorFilter(matrix) if scale < 255 else None)


class Seen:
    def __init__(self, plugin, name):
        self.plugin, self.name = plugin, name

    def after_hooked_method(self, param):
        self.plugin.noted(self.name)
        self.plugin.apply(param.thisObject)


class Taken:
    def __init__(self, plugin):
        self.plugin = plugin

    def after_hooked_method(self, param):
        request, result, data = param.args
        self.plugin.set_setting("answer", [int(request), int(result), None if data is None else str(data.getData().toString())])
        if result == Activity.RESULT_OK:
            self.plugin.set_setting("uri", str(data.getData().toString()))
'''

PICTURE = "/var/pictures/pick1.jpg"
ADDRESS = "file://" + PICTURE


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-page-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


def write(plugin_id, source):
    path = os.path.join(PLUGINS, plugin_id + ".plugin")
    with open(path, "w") as handle:
        handle.write(source % {"id": plugin_id} if "%(id)s" in source else source)
    return path


def pump(until, seconds=3):
    end = time.time() + seconds
    while time.time() < end:
        # a plugin that polls puts its timer back each time, so only the timers that stand now are run
        due, fake.timers[:] = list(fake.timers), []
        for token, _delay in due:
            exteria_host.run_token(token)
        if until():
            return True
        time.sleep(0.01)
    return False


def reset():
    fake.calls.clear()
    fake.ops.clear()
    fake.settings.clear()
    fake.timers.clear()
    fake.image_picks.clear()
    fake.bitmaps.clear()
    fake.cards.clear()
    fake.pictures.clear()
    fake.picks_root = "/var/pictures"


def setting(plugin_id, key):
    raw = fake.settings.get((plugin_id, key))
    return None if raw is None else json.loads(raw)


def ops(kind):
    return [op for op in list(fake.ops) if op[0] == kind]


class Page(unittest.TestCase):
    def setUp(self):
        reset()
        from org.telegram.ui import SettingsActivity
        page = SettingsActivity.instance()
        # the page lives as long as the process, so what an earlier test put on it is taken off
        page.getFragmentView().removeAllViews()
        page.listView.sectionBackgroundPaint._sent = 1.0
        self.path = write("wall", WALLPAPER)
        self.assertTrue(exteria_host.load(self.path, "wall")["ok"])

    def tearDown(self):
        exteria_host.unload("wall")
        exteria_host.fragment_event("settings", "pause", 320, 480)

    def event(self, name, width=320, height=480):
        exteria_host.fragment_event("settings", name, width, height)

    def choose(self, size=(4000, 3000), **values):
        fake.pictures[PICTURE] = size
        for key, value in values.items():
            fake.settings[("wall", key)] = json.dumps(value)
        fake.settings[("wall", "uri")] = json.dumps(ADDRESS)

    def test_the_hooks_on_the_page_run_for_each_event_the_app_reports(self):
        self.event("create")
        self.event("resume")
        self.event("pause")
        self.assertEqual(setting("wall", "events"), "createView,onResume,onPause,")

    def test_the_page_is_shown_between_resume_and_pause_only(self):
        from org.telegram.ui import SettingsActivity
        root = SettingsActivity.instance().getFragmentView()
        self.assertFalse(root.isShown())
        self.event("resume")
        self.assertTrue(root.isShown())
        self.event("pause")
        self.assertFalse(root.isShown())

    def test_the_last_fragment_is_the_settings_page_when_the_app_says_so(self):
        from client_utils import get_last_fragment
        from org.telegram.ui import SettingsActivity
        fake.current = {"kind": "settings"}
        try:
            self.assertIs(get_last_fragment(), SettingsActivity.instance())
        finally:
            fake.current = {"kind": "chat", "dialog": 777, "user": {"id": 777, "first_name": "Ann"}}

    def test_the_picker_opens_and_the_answer_reaches_the_hook_with_the_address_of_the_picture(self):
        plugin = self.plugin()
        plugin.pick()
        _ui.flush()
        self.assertEqual(fake.image_picks, [{"request": 0xC11B}])
        exteria_host.activity_result(0xC11B, -1, ADDRESS)
        self.assertEqual(setting("wall", "answer"), [0xC11B, -1, ADDRESS])
        self.assertEqual(setting("wall", "uri"), ADDRESS)

    def test_a_cancelled_picker_answers_without_data(self):
        exteria_host.activity_result(0xC11B, 0, "")
        self.assertEqual(setting("wall", "answer"), [0xC11B, 0, None])
        self.assertIsNone(setting("wall", "uri"))

    def test_an_intent_that_has_no_screen_is_refused_by_name(self):
        from android.app import activity
        from android.content import Intent
        for intent in (Intent(Intent.ACTION_VIEW), Intent(Intent.ACTION_OPEN_DOCUMENT).setType("video/*"), Intent(Intent.ACTION_OPEN_DOCUMENT)):
            with self.assertRaises(NotImplementedError):
                activity().startActivityForResult(intent, 1)
        self.assertEqual(fake.image_picks, [])

    def test_the_picture_is_shrunk_blurred_dimmed_and_put_under_the_rows(self):
        self.choose((4000, 3000), blur=10, dim=76)
        self.event("create")
        self.event("resume")
        added = [op for op in ops("add") if op[1] == -1]
        self.assertEqual(len(added), 1)
        view = added[0][2]
        self.assertEqual(added[0][3], 0)
        # the plugin decodes again at each event, and the picture of the first one is let go once python drops it
        shown = [op for op in ops("nimg") if op[1] == view]
        self.assertEqual(len(shown), 2)
        gc.collect()
        _ui.flush()
        self.assertEqual(len(fake.bitmaps), 1)
        picture = fake.bitmaps[shown[-1][2]]
        # the app decoded it at 2048 on the long side, the plugin scaled it down to 1920
        self.assertEqual((picture["w"], picture["h"]), (1920, 1440))
        self.assertEqual(picture["blur"], 10)
        merged = {}
        for op in ops("set"):
            if op[1] == view:
                merged.update(op[2])
        self.assertEqual(merged["tint"], 76 << 24)
        self.assertEqual(merged["scale"], "crop")
        self.assertEqual((merged["w"], merged["h"]), (320, 480))

    def test_the_cards_follow_the_alpha_of_the_filter_and_come_back_when_it_goes(self):
        self.choose(card=128)
        self.event("create")
        self.event("resume")
        self.assertEqual(len(fake.cards), 1)
        self.assertAlmostEqual(fake.cards[0], 128 / 255.0)
        self.event("resume")
        self.assertEqual(len(fake.cards), 1, "the same alpha is not sent twice")
        self.plugin().set_setting("card", 255)
        self.event("resume")
        self.assertEqual(fake.cards[-1], 1.0)

    def test_a_new_layer_of_the_page_gets_the_views_again(self):
        self.choose()
        self.event("create")
        self.event("resume")
        before = len(ops("add"))
        news = len(ops("new"))
        self.event("create")
        self.assertGreater(len(ops("add")), before)
        self.assertGreater(len(ops("new")), news)

    def test_a_picture_that_is_not_one_gives_null_and_the_reason_is_logged(self):
        from android.app import activity
        from android.graphics import BitmapFactory
        stream = activity().getContentResolver().openInputStream(self.uri("file:///var/pictures/broken.jpg"))
        self.assertIsNone(BitmapFactory.decodeStream(stream))
        reasons = [data["message"] for call, data in list(fake.calls) if call == "log" and "not a picture" in data.get("message", "")]
        self.assertTrue(reasons)

    def test_a_closed_stream_gives_null(self):
        from android.app import activity
        from android.graphics import BitmapFactory
        fake.pictures[PICTURE] = (10, 10)
        stream = activity().getContentResolver().openInputStream(self.uri(ADDRESS))
        stream.close()
        self.assertIsNone(BitmapFactory.decodeStream(stream))

    def test_only_the_pictures_the_person_chose_open(self):
        from android.app import activity
        from android.content import Intent
        resolver = activity().getContentResolver()
        for bad in ("file:///etc/passwd", "file:///var/pictures/../etc/passwd", "file:///var/pictures/sub/a.jpg", "file:///var/pictures",
                    "file:///var/pictures//a.jpg", "file://host/var/pictures/a.jpg", "content://media/external/1", "http://x/var/pictures/a.jpg"):
            with self.assertRaises(Exception, msg=bad) as caught:
                resolver.openInputStream(self.uri(bad))
            self.assertEqual(type(caught.exception).__name__, "SecurityException", bad)
        with self.assertRaises(Exception):
            resolver.takePersistableUriPermission(self.uri("file:///etc/passwd"), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        # a file of the folder is fine, and so is the grant that only reads it
        resolver.takePersistableUriPermission(self.uri(ADDRESS), Intent.FLAG_GRANT_READ_URI_PERMISSION)
        self.assertIsNotNone(resolver.openInputStream(self.uri(ADDRESS)))
        from java.lang import IllegalArgumentException
        with self.assertRaises(IllegalArgumentException):
            resolver.takePersistableUriPermission(self.uri(ADDRESS), 0x1000)

    def test_a_picture_is_let_go_in_the_app_when_python_drops_it(self):
        from android.app import activity
        from android.graphics import BitmapFactory
        fake.pictures[PICTURE] = (100, 100)
        bitmap = BitmapFactory.decodeStream(activity().getContentResolver().openInputStream(self.uri(ADDRESS)))
        self.assertEqual(len(fake.bitmaps), 1)
        del bitmap
        gc.collect()
        _ui.flush()
        self.assertEqual(len(fake.bitmaps), 0)

    def test_a_recycled_picture_is_let_go_once_and_refuses_use(self):
        from android.app import activity
        from android.graphics import BitmapFactory
        fake.pictures[PICTURE] = (100, 100)
        bitmap = BitmapFactory.decodeStream(activity().getContentResolver().openInputStream(self.uri(ADDRESS)))
        bitmap.recycle()
        bitmap.recycle()
        self.assertTrue(bitmap.isRecycled())
        _ui.flush()
        self.assertEqual(len(fake.bitmaps), 0)
        with self.assertRaises(Exception):
            bitmap.copy()

    def test_what_the_shims_cannot_do_is_refused_and_not_pretended(self):
        from android.graphics import Bitmap, ColorMatrix, ColorMatrixColorFilter, PorterDuff, PorterDuffColorFilter
        from android.widget import ImageView
        from org.telegram.messenger import Utilities
        plain = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
        with self.assertRaises(NotImplementedError):
            Bitmap.createScaledBitmap(plain, 2, 2, True)
        with self.assertRaises(NotImplementedError):
            Utilities.stackBlurBitmap(plain, 3)
        fake.pictures[PICTURE] = (64, 64)
        from android.app import activity
        from android.graphics import BitmapFactory
        picture = BitmapFactory.decodeStream(activity().getContentResolver().openInputStream(self.uri(ADDRESS)))
        for radius in (-1, 255):
            with self.assertRaises(ValueError):
                Utilities.stackBlurBitmap(picture, radius)
        Utilities.stackBlurBitmap(picture, 0)
        Utilities.stackBlurBitmap(picture, 7)
        self.assertEqual(fake.bitmaps[picture._handle]["blur"], 7)
        with self.assertRaises(NotImplementedError):
            picture.getPixel(0, 0)
        with self.assertRaises(Exception):
            ColorMatrix([1.0] * 19)
        view = ImageView(None)
        with self.assertRaises(NotImplementedError):
            view.setColorFilter(PorterDuffColorFilter(0x80000000, PorterDuff.Mode.MULTIPLY))
        with self.assertRaises(NotImplementedError):
            view.setColorFilter(ColorMatrixColorFilter(ColorMatrix()))

    def test_a_card_filter_that_does_more_than_scale_alpha_is_refused(self):
        from android.graphics import ColorMatrix, ColorMatrixColorFilter
        from org.telegram.ui import SettingsActivity
        paint = SettingsActivity.instance().listView.sectionBackgroundPaint
        matrix = ColorMatrix()
        matrix.set([0.5, 0.5, 0.0, 0.0, 0.0] + [0.0, 1.0, 0.0, 0.0, 0.0] + [0.0, 0.0, 1.0, 0.0, 0.0] + [0.0, 0.0, 0.0, 0.5, 0.0])
        with self.assertRaises(NotImplementedError):
            paint.setColorFilter(ColorMatrixColorFilter(matrix))
        self.assertEqual(fake.cards, [])

    def test_the_color_matrix_scales_and_resets(self):
        from android.graphics import ColorMatrix
        matrix = ColorMatrix()
        matrix.setScale(0.5, 1.0, 2.0, 0.25)
        self.assertEqual([matrix.getArray()[i] for i in (0, 6, 12, 18)], [0.5, 1.0, 2.0, 0.25])
        self.assertEqual(sum(1 for value in matrix.getArray() if value), 4)
        matrix.reset()
        self.assertEqual([matrix.getArray()[i] for i in (0, 6, 12, 18)], [1.0] * 4)

    def test_an_address_is_taken_apart_as_android_does(self):
        from android.net import Uri
        uri = Uri.parse("file:///var/pictures/a%20b.jpg?x=1")
        self.assertEqual((uri.getScheme(), uri.getPath(), uri.getLastPathSegment(), uri.getQuery()), ("file", "/var/pictures/a b.jpg", "a b.jpg", "x=1"))
        self.assertEqual(uri.toString(), "file:///var/pictures/a%20b.jpg?x=1")
        with self.assertRaises(Exception):
            Uri.parse(None)

    def uri(self, text):
        from android.net import Uri
        return Uri.parse(text)

    def plugin(self):
        # the one the loader holds: an instance of an earlier test may still be alive in the garbage and found first by gc
        record = plugin_loader.plugins.get("wall")
        if record is None:
            raise AssertionError("the plugin is not loaded")
        return record.instance


@unittest.skipUnless(os.environ.get("EXTERIA_SETTINGS_WALLPAPER"), "set EXTERIA_SETTINGS_WALLPAPER to the file of the plugin")
class RealPlugin(unittest.TestCase):
    """the plugin as its author wrote it, through the settings page: pick, answer, build, dim, blur, cards"""

    def setUp(self):
        reset()
        self.path = os.path.join(PLUGINS, "settings_wallpaper.plugin")
        shutil.copy(os.environ["EXTERIA_SETTINGS_WALLPAPER"], self.path)
        self.assertTrue(exteria_host.load(self.path, "settings_wallpaper")["ok"])

    def tearDown(self):
        exteria_host.unload("settings_wallpaper")
        exteria_host.fragment_event("settings", "pause", 320, 480)

    def test_it_picks_builds_the_background_and_takes_it_away(self):
        fake.current = {"kind": "settings"}
        try:
            fake.pictures[PICTURE] = (3000, 2000)
            exteria_host.fragment_event("settings", "create", 320, 480)
            exteria_host.fragment_event("settings", "resume", 320, 480)
            pump(lambda: False, 0.1)
            self.assertEqual(ops("nimg"), [])
            fake.settings[("settings_wallpaper", "blur_radius")] = json.dumps(2)
            fake.settings[("settings_wallpaper", "dimming")] = json.dumps(5)
            fake.settings[("settings_wallpaper", "card_opacity")] = json.dumps(5)
            pick = [item for item in exteria_host.settings("settings_wallpaper") if item.get("type") == "text"]
            self.assertEqual(len(pick), 1)
            exteria_host.setting_click("settings_wallpaper", pick[0]["callback_id"])
            self.assertTrue(pump(lambda: fake.image_picks, 2), "the plugin did not open the picker")
            request = fake.image_picks[0]["request"]
            exteria_host.activity_result(request, -1, ADDRESS)
            self.assertTrue(pump(lambda: ops("nimg"), 3), "no picture was put on the page")
            self.assertTrue(pump(lambda: fake.cards, 3), "the cards were not made see-through")
            view = [op for op in ops("add") if op[1] == -1][0][2]
            tint = [op[2]["tint"] for op in ops("set") if op[1] == view and "tint" in op[2]]
            self.assertIn(int(255 * 0.5) << 24, tint)
            self.assertAlmostEqual(fake.cards[-1], 127 / 255.0, places=2)
            live = len(fake.bitmaps)
            self.assertGreaterEqual(live, 1)
            exteria_host.unload("settings_wallpaper")
            self.assertTrue(pump(lambda: fake.cards[-1] == 1.0, 3), "the cards were not put back")
            self.assertTrue(any(op[0] == "rm" and op[1] == view for op in fake.ops), "the picture was not taken off the page")
        finally:
            fake.current = {"kind": "chat", "dialog": 777, "user": {"id": 777, "first_name": "Ann"}}


if __name__ == "__main__":
    unittest.main()
