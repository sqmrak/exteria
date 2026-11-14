"""ActionBar, StarParticlesView, ReactionsLayoutInBubble.VisibleReaction, SizeNotifierFrameLayout, and the classes that only import:
GiftSheet, SelectAnimatedEmojiDialog and MediaDataController"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.graphics import Bitmap, Canvas  # noqa: E402
from android.graphics.drawable import ColorDrawable  # noqa: E402
from android.view import View  # noqa: E402
from android.widget import FrameLayout  # noqa: E402
from java import jclass  # noqa: E402
from java.lang import IllegalArgumentException  # noqa: E402
from org.telegram.messenger import MediaDataController  # noqa: E402
from org.telegram.ui import SelectAnimatedEmojiDialog  # noqa: E402
from org.telegram.ui.ActionBar import ActionBar  # noqa: E402
from org.telegram.ui.Components import SizeNotifierFrameLayout  # noqa: E402
from org.telegram.ui.Components.Premium import StarParticlesView  # noqa: E402
from org.telegram.ui.Components.Reactions import ReactionsLayoutInBubble  # noqa: E402
from org.telegram.ui.Gifts import GiftSheet  # noqa: E402

Visible = ReactionsLayoutInBubble.VisibleReaction


class Bars(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()

    def test_the_title_and_the_subtitle_are_set_and_read_back(self):
        bar = ActionBar(self.decor.getContext())
        self.decor.addView(bar, FrameLayout.LayoutParams(300, 56))
        bar.setTitle("Plugins")
        _ui.flush()
        self.assertEqual((bar.getTitle(), str(bar.getTitleTextView().getText())), ("Plugins", "Plugins"))
        self.assertEqual(bar.getSubtitleTextView().getVisibility(), View.GONE)
        bar.setSubtitle("3 on")
        self.assertEqual((bar.getSubtitleTextView().getVisibility(), str(bar.getSubtitleTextView().getText())), (View.VISIBLE, "3 on"))
        bar.setSubtitle(None)
        self.assertEqual(bar.getSubtitleTextView().getVisibility(), View.GONE)

    def test_the_menu_listener_base_is_empty_as_in_the_client_and_a_subclass_overrides_it(self):
        base = ActionBar.ActionBarMenuOnItemClick()
        self.assertIsNone(base.onItemClick(3))
        self.assertTrue(base.canOpenMenu())
        chosen = []

        class Mine(ActionBar.ActionBarMenuOnItemClick):
            def onItemClick(self, item_id):
                chosen.append(item_id)

        bar = ActionBar(self.decor.getContext())
        mine = Mine()
        bar.setActionBarMenuOnItemClick(mine)
        bar.getActionBarMenuOnItemClick().onItemClick(7)
        self.assertEqual(chosen, [7])

    def test_both_classes_resolve_by_their_java_names(self):
        self.assertIs(jclass("org.telegram.ui.ActionBar.ActionBar"), ActionBar)
        self.assertIs(jclass("org.telegram.ui.ActionBar.ActionBar$ActionBarMenuOnItemClick"), ActionBar.ActionBarMenuOnItemClick)


class Particles(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fake.timers.clear()
        fake.ops.clear()

    def run_next(self):
        token, _delay = fake.timers.pop(0)
        exteria_host.run_token(token)
        _ui.flush()

    def view(self, count=40):
        view = StarParticlesView(self.decor.getContext(), count)
        self.decor.addView(view, FrameLayout.LayoutParams(80, 60))
        _ui.flush()
        return view

    def test_the_number_of_particles_is_bounded(self):
        self.assertEqual(len(StarParticlesView(self.decor.getContext(), 160).drawable._particles), StarParticlesView.MAX_PARTICLES)
        self.assertEqual(len(StarParticlesView(self.decor.getContext(), 5).drawable._particles), 5)

    def test_the_settings_a_plugin_writes_reach_the_particles_on_init(self):
        view = StarParticlesView(self.decor.getContext(), 10)
        drawable = view.drawable
        drawable.startFromCenter = True
        drawable.size1 = drawable.size2 = drawable.size3 = 20
        drawable.colorKey = "featuredStickers_addButton"
        drawable.isCircle = True
        drawable.init()
        self.assertTrue(all(p["size"] == 20 and p["x"] == 0.5 and p["y"] == 0.5 for p in drawable._particles))
        # the key is read once, at init: the theme of the fake app answers 0xFF112233
        self.assertEqual(drawable._color, 0xFF112233)
        plain = StarParticlesView(self.decor.getContext(), 2)
        self.assertEqual(plain.drawable._color, 0xFFFFFFFF)

    def test_particles_move_age_and_are_replaced_when_they_leave(self):
        view = StarParticlesView(self.decor.getContext(), 6)
        drawable = view.drawable
        drawable.startFromCenter = True
        drawable.init()
        before = [(p["x"], p["y"]) for p in drawable._particles]
        drawable.advance(0.5)
        self.assertNotEqual(before, [(p["x"], p["y"]) for p in drawable._particles])
        for _ in range(40):
            drawable.advance(0.5)
        self.assertEqual(len(drawable._particles), 6)
        self.assertTrue(all(-0.1 <= p["x"] <= 1.1 and -0.1 <= p["y"] <= 1.1 and p["age"] < 1.0 for p in drawable._particles))

    def test_a_fling_speeds_them_up_and_fades(self):
        view = StarParticlesView(self.decor.getContext(), 1)
        drawable = view.drawable
        drawable.startFromCenter = True
        drawable.init()
        particle = dict(drawable._particles[0])
        drawable.advance(0.1)
        slow = abs(drawable._particles[0]["x"] - particle["x"]) + abs(drawable._particles[0]["y"] - particle["y"])
        drawable.init()
        view.flingParticles(360)
        particle = dict(drawable._particles[0])
        drawable.advance(0.1)
        fast = abs(drawable._particles[0]["x"] - particle["x"]) + abs(drawable._particles[0]["y"] - particle["y"])
        self.assertGreater(fast, slow * 2)
        for _ in range(20):
            drawable.advance(0.5)
        self.assertEqual(drawable._boost, 0.0)

    def test_it_animates_in_a_window_and_stops_when_it_leaves_or_is_paused(self):
        view = self.view()
        self.assertEqual(len(fake.timers), 1)
        self.run_next()
        self.assertEqual(len(fake.timers), 1)
        view.setPaused(True)
        self.run_next()
        self.assertEqual(fake.timers, [])
        view.setPaused(False)
        self.assertEqual(len(fake.timers), 1)
        self.decor.removeAllViews()
        _ui.flush()
        self.run_next()
        self.assertEqual(fake.timers, [])

    def test_it_draws_circles_and_stars_in_the_color_of_the_settings(self):
        view = self.view(30)
        view.drawable.startFromCenter = False
        view.drawable._color = 0xFF3366CC
        view.drawable.isCircle = True
        view.drawable.size1 = view.drawable.size2 = view.drawable.size3 = 10
        for p in view.drawable._particles:
            p["age"] = 0.5
        bitmap = Bitmap(80, 60)
        view.onDraw(Canvas(bitmap))
        painted = [bitmap.getPixel(x, y) for x in range(80) for y in range(60) if bitmap.getPixel(x, y) >> 24]
        self.assertGreater(len(painted), 20)
        self.assertTrue(all((c & 0xFFFFFF) == 0x3366CC for c in painted))
        stars = Bitmap(80, 60)
        view.drawable.isCircle = False
        view.onDraw(Canvas(stars))
        self.assertNotEqual(bytes(bitmap._pixels), bytes(stars._pixels))

    def test_the_gradient_clip_fades_the_edges(self):
        view = self.view(1)
        drawable = view.drawable
        drawable._particles = [{"x": 0.02, "y": 0.5, "angle": 0.0, "speed": 0.0, "size": 10, "age": 0.5, "turn": 0.0}]
        drawable._color = 0xFFFFFFFF
        drawable.isCircle = True
        plain, clipped = Bitmap(80, 60), Bitmap(80, 60)
        view.onDraw(Canvas(plain))
        view.setClipWithGradient()
        view.onDraw(Canvas(clipped))
        peak = lambda bmp: max(bmp.getPixel(x, y) >> 24 for x in range(80) for y in range(60))
        self.assertGreater(peak(plain), peak(clipped))

    def test_it_resolves_by_its_java_name(self):
        self.assertIs(jclass("org.telegram.ui.Components.Premium.StarParticlesView"), StarParticlesView)


class Reactions(unittest.TestCase):
    def test_an_emoji_and_a_custom_emoji_are_values_that_compare(self):
        heart = Visible.fromEmojicon("❤")
        self.assertEqual((heart.emojicon, heart.documentId), ("❤", 0))
        self.assertTrue(heart.equals(Visible.fromEmojicon("❤")))
        self.assertEqual(heart, Visible.fromEmojicon("❤"))
        self.assertNotEqual(heart, Visible.fromEmojicon("\U0001F44D"))
        custom = Visible.fromCustomEmoji(5368324170671202286)
        self.assertEqual((custom.emojicon, custom.documentId), (None, 5368324170671202286))
        self.assertEqual(custom, Visible.fromCustomEmoji(5368324170671202286))
        self.assertNotEqual(custom, heart)
        self.assertNotEqual(Visible.fromCustomEmoji(1), Visible.fromCustomEmoji(2))
        self.assertFalse(Visible.fromCustomEmoji(1).equals(Visible.fromCustomEmoji(2)))
        self.assertEqual(len({heart, Visible.fromEmojicon("❤"), custom}), 2)
        self.assertEqual(heart.hashCode(), Visible.fromEmojicon("❤").hashCode())

    def test_tl_records_are_read_by_what_they_carry(self):
        emoji = type("R", (), {"emoticon": "\U0001F525"})()
        custom = type("R", (), {"document_id": 77})()
        self.assertEqual(Visible.fromTL(emoji), Visible.fromEmojicon("\U0001F525"))
        self.assertEqual(Visible.fromTL(custom), Visible.fromCustomEmoji(77))
        with self.assertRaises(IllegalArgumentException):
            Visible.fromTL(object())
        with self.assertRaises(IllegalArgumentException):
            Visible.fromEmojicon(None)

    def test_it_prints_and_resolves(self):
        self.assertEqual(Visible.fromEmojicon("x").toString(), "VisibleReaction{x}")
        self.assertEqual(Visible.fromCustomEmoji(5).toString(), "VisibleReaction{custom:5}")
        self.assertIs(jclass("org.telegram.ui.Components.Reactions.ReactionsLayoutInBubble$VisibleReaction"), Visible)


class Layouts(unittest.TestCase):
    def test_the_keyboard_is_not_followed_and_the_background_is_the_background(self):
        decor = activity().getWindow().getDecorView()
        layout = SizeNotifierFrameLayout(decor.getContext())
        delegate = object()
        layout.setDelegate(delegate)
        image = ColorDrawable(0xFF112233)
        layout.setBackgroundImage(image, True)
        self.assertEqual((layout.getKeyboardHeight(), layout.measureKeyboardHeight()), (0, 0))
        self.assertIs(layout.getBackgroundImage(), image)
        self.assertIs(layout.getBackground(), image)
        self.assertIs(jclass("org.telegram.ui.Components.SizeNotifierFrameLayout"), SizeNotifierFrameLayout)


class ImportOnly(unittest.TestCase):
    def test_the_gift_sheet_and_the_emoji_picker_load_and_say_what_they_cannot_do(self):
        with self.assertRaises(NotImplementedError) as sheet:
            GiftSheet(None, 0, 1, None, None)
        self.assertIn("profile", str(sheet.exception))
        with self.assertRaises(NotImplementedError):
            SelectAnimatedEmojiDialog(None)
        self.assertFalse(hasattr(SelectAnimatedEmojiDialog, "TYPE_REACTIONS"))
        self.assertIs(jclass("org.telegram.ui.Gifts.GiftSheet"), GiftSheet)
        self.assertIs(jclass("org.telegram.ui.SelectAnimatedEmojiDialog"), SelectAnimatedEmojiDialog)

    def test_the_media_data_controller_answers_per_account_and_refuses_what_needs_its_data(self):
        self.assertIs(MediaDataController.getInstance(0), MediaDataController.getInstance(0))
        self.assertIsNot(MediaDataController.getInstance(0), MediaDataController.getInstance(1))
        controller = MediaDataController.getInstance(0)
        for call in (lambda: controller.getStickerSetByName("pack"), lambda: controller.getReactionsList(),
                     lambda: controller.loadStickersByEmojiOrName("pack", False, False)):
            with self.assertRaises(NotImplementedError) as refused:
                call()
            self.assertIn("MediaDataController.", str(refused.exception))
        with self.assertRaises(AttributeError):
            controller._private
        self.assertIs(jclass("org.telegram.messenger.MediaDataController"), MediaDataController)


if __name__ == "__main__":
    unittest.main()
