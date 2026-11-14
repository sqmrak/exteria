"""the classes plugins of the public catalogs reach for that the shim lacked: LayerDrawable, PaintDrawable, Picture and PictureDrawable, the
translate and set animations with View.startAnimation, Html.fromHtml, and the link movement method with the character lookup it needs"""

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
from android.graphics import Bitmap, Canvas, Color, Paint, Picture  # noqa: E402
from android.graphics.drawable import ColorDrawable, LayerDrawable, PaintDrawable, PictureDrawable  # noqa: E402
from android.text import ClickableSpan, Html, SpannableString, Spanned, StyleSpan, URLSpan  # noqa: E402
from android.text.method import ArrowKeyMovementMethod, LinkMovementMethod  # noqa: E402
from android.view import MotionEvent, View, dispatch_touch  # noqa: E402
from android.view.animation import Animation, AnimationSet, LinearInterpolator, TranslateAnimation  # noqa: E402
from android.widget import FrameLayout, TextView  # noqa: E402
from java import jclass  # noqa: E402

RED, BLUE, CLEAR = 0xFFFF0000, 0xFF0000FF, 0


def paint_of(color):
    paint = Paint()
    paint.setColor(color)
    return paint


class Drawables(unittest.TestCase):
    def test_layers_paint_in_order_inside_their_insets(self):
        layers = LayerDrawable([ColorDrawable(RED), ColorDrawable(BLUE)])
        layers.setLayerInset(1, 2, 2, 2, 2)
        layers.setBounds(0, 0, 10, 10)
        bitmap = Bitmap(10, 10)
        layers.draw(Canvas(bitmap))
        self.assertEqual(bitmap.getPixel(0, 0), RED)
        self.assertEqual(bitmap.getPixel(5, 5), BLUE)
        self.assertEqual(bitmap.getPixel(9, 9), RED)
        self.assertEqual(bitmap.getPixel(1, 5), RED)
        self.assertEqual(bitmap.getPixel(2, 5), BLUE)

    def test_layers_are_found_by_index_and_by_id(self):
        first, second = ColorDrawable(RED), ColorDrawable(BLUE)
        layers = LayerDrawable([first, second])
        layers.setId(1, 77)
        self.assertEqual(layers.getNumberOfLayers(), 2)
        self.assertIs(layers.getDrawable(0), first)
        self.assertIs(layers.findDrawableByLayerId(77), second)
        self.assertIsNone(layers.findDrawableByLayerId(5))
        self.assertEqual((layers.findIndexByLayerId(77), layers.findIndexByLayerId(5)), (1, -1))
        self.assertEqual(layers.addLayer(ColorDrawable(0)), 2)
        with self.assertRaises(ValueError):
            LayerDrawable([None])

    def test_a_layer_that_changes_repaints_the_background_of_the_view(self):
        decor = activity().getWindow().getDecorView()
        decor.removeAllViews()
        _ui.flush()
        view = View(decor.getContext())
        under = ColorDrawable(RED)
        view.setBackground(LayerDrawable([under]))
        decor.addView(view, FrameLayout.LayoutParams(8, 6))
        _ui.flush()
        pictures = [op for op in fake.ops if op[0] == "img" and op[1] == view._id]
        self.assertEqual(pictures[-1][2:4], [8, 6])
        count = len(pictures)
        under.setColor(BLUE)
        _ui.flush()
        pictures = [op for op in fake.ops if op[0] == "img" and op[1] == view._id]
        self.assertEqual(len(pictures), count + 1)

    def test_paint_drawable_is_a_colored_rectangle_with_a_size_of_its_own(self):
        cursor = PaintDrawable(BLUE)
        cursor.setIntrinsicWidth(3)
        cursor.setIntrinsicHeight(20)
        cursor.setBounds(0, 0, 3, 4)
        bitmap = Bitmap(3, 4)
        cursor.draw(Canvas(bitmap))
        self.assertEqual((cursor.getIntrinsicWidth(), cursor.getIntrinsicHeight()), (3, 20))
        self.assertEqual(bitmap.getPixel(1, 2), BLUE)
        self.assertEqual(PaintDrawable().getIntrinsicWidth(), -1)

    def test_picture_replays_what_was_recorded(self):
        picture = Picture()
        canvas = picture.beginRecording(4, 4)
        canvas.drawRect(0, 0, 2, 4, paint_of(RED))
        picture.endRecording()
        target = Bitmap(8, 4)
        canvas = Canvas(target)
        canvas.translate(4, 0)
        picture.draw(canvas)
        self.assertEqual((picture.getWidth(), picture.getHeight()), (4, 4))
        self.assertEqual((target.getPixel(4, 1), target.getPixel(6, 1), target.getPixel(0, 1)), (RED, CLEAR, CLEAR))

    def test_picture_refuses_what_it_cannot_record(self):
        from java.lang import IllegalArgumentException, IllegalStateException
        picture = Picture()
        with self.assertRaises(IllegalStateException):
            picture.endRecording()
        picture.beginRecording(2, 2)
        with self.assertRaises(IllegalStateException):
            picture.beginRecording(2, 2)
        with self.assertRaises(IllegalStateException):
            picture.draw(Canvas(Bitmap(2, 2)))
        picture.endRecording()
        with self.assertRaises(IllegalArgumentException):
            Picture().beginRecording(100000, 100000)
        with self.assertRaises(IllegalArgumentException):
            Picture().beginRecording(-1, 4)

    def test_picture_drawable_scales_into_its_bounds(self):
        picture = Picture()
        picture.beginRecording(2, 2).drawRect(0, 0, 2, 2, paint_of(RED))
        picture.endRecording()
        drawable = PictureDrawable(picture)
        drawable.setBounds(0, 0, 6, 6)
        target = Bitmap(6, 6)
        drawable.draw(Canvas(target))
        self.assertEqual((target.getPixel(0, 0), target.getPixel(5, 5)), (RED, RED))
        self.assertEqual((drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight()), (2, 2))
        self.assertEqual(PictureDrawable(None).getIntrinsicWidth(), -1)


class Animations(unittest.TestCase):
    """the timers of the fake app run in the order of their due time, with a clock of milliseconds that the listeners can read"""

    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fake.timers.clear()
        fake.ops.clear()
        self.clock = 0
        self.view = View(self.decor.getContext())
        self.decor.addView(self.view, FrameLayout.LayoutParams(40, 20))
        _ui.flush()

    def run_timers(self, until=100000):
        pending = [(self.clock + delay, n, token) for n, (token, delay) in enumerate(fake.timers)]
        fake.timers.clear()
        serial = len(pending)
        while pending:
            pending.sort()
            due, _n, token = pending.pop(0)
            if due > until:
                pending.insert(0, (due, _n, token))
                break
            self.clock = due
            exteria_host.run_token(token)
            _ui.flush()
            for token, delay in fake.timers:
                serial += 1
                pending.append((self.clock + delay, serial, token))
            fake.timers.clear()
        return pending

    def recorder(self, log):
        outer = self

        class Events(Animation.AnimationListener):
            def onAnimationStart(self, animation):
                log.append(("start", outer.clock))

            def onAnimationEnd(self, animation):
                log.append(("end", outer.clock))

            def onAnimationRepeat(self, animation):
                log.append(("repeat", outer.clock))

        return Events()

    def moves(self):
        return [op for op in fake.ops if op[0] == "anim" and op[1] == self.view._id]

    def test_translate_moves_the_layer_and_puts_it_back(self):
        log = []
        move = TranslateAnimation(0, 30, 0, 10)
        move.setDuration(200)
        move.setInterpolator(LinearInterpolator())
        move.setAnimationListener(self.recorder(log))
        self.view.startAnimation(move)
        self.assertIs(self.view.getAnimation(), move)
        self.run_timers()
        self.assertEqual(log, [("start", 0), ("end", 200)])
        sent = self.moves()
        self.assertEqual(len(sent), 1)
        self.assertEqual((sent[0][2]["tx"], sent[0][2]["ty"], sent[0][3], sent[0][5]), (30.0, 10.0, 200, "linear"))
        self.assertEqual((self.view.getTranslationX(), self.view.getTranslationY()), (0, 0))

    def test_fill_after_keeps_the_last_frame(self):
        move = TranslateAnimation(0, 30, 0, 0)
        move.setDuration(50)
        move.setFillAfter(True)
        self.view.startAnimation(move)
        self.run_timers()
        self.assertEqual(self.view.getTranslationX(), 30)

    def test_the_relative_form_uses_the_size_of_the_view_or_of_its_parent(self):
        move = TranslateAnimation(Animation.RELATIVE_TO_SELF, 0, Animation.RELATIVE_TO_SELF, 1.0,
                                  Animation.RELATIVE_TO_PARENT, 0, Animation.ABSOLUTE, 5)
        move.setDuration(10)
        self.view.startAnimation(move)
        self.run_timers()
        sent = self.moves()[0][2]
        self.assertEqual((sent["tx"], sent["ty"]), (40.0, 5.0))
        with self.assertRaises(TypeError):
            TranslateAnimation(1, 2, 3)

    def test_a_set_plays_children_after_their_own_offsets(self):
        log = []
        shake = AnimationSet(True)
        left = TranslateAnimation(0, -10, 0, 0)
        right = TranslateAnimation(-10, 10, 0, 0)
        right.setStartOffset(100)
        shake.addAnimation(left)
        shake.addAnimation(right)
        shake.setDuration(100)
        shake.setAnimationListener(self.recorder(log))
        self.view.startAnimation(shake)
        self.run_timers()
        self.assertEqual(log, [("start", 0), ("end", 200)])
        self.assertEqual([op[2]["tx"] for op in self.moves()], [-10.0, 10.0])
        self.assertEqual(shake.getDuration(), 200)
        self.assertEqual(self.view.getTranslationX(), 0)

    def test_a_shared_interpolator_goes_to_children_that_have_none(self):
        shake = AnimationSet(True)
        shake.setInterpolator(LinearInterpolator())
        own = TranslateAnimation(0, 5, 0, 0)
        shake.addAnimation(TranslateAnimation(0, 5, 0, 0))
        shake.addAnimation(own)
        shake.setDuration(10)
        self.view.startAnimation(shake)
        self.run_timers()
        self.assertEqual([op[5] for op in self.moves()], ["linear", "linear"])
        alone = AnimationSet(False)
        alone.setInterpolator(LinearInterpolator())
        alone.addAnimation(TranslateAnimation(0, 5, 0, 0))
        alone.setDuration(10)
        fake.ops.clear()
        self.view.startAnimation(alone)
        self.run_timers()
        self.assertNotIn("linear", [op[5] for op in self.moves()])

    def test_reverse_repeat_goes_there_and_back(self):
        log = []
        move = TranslateAnimation(0, 20, 0, 0)
        move.setDuration(100)
        move.setRepeatCount(1)
        move.setRepeatMode(Animation.REVERSE)
        move.setAnimationListener(self.recorder(log))
        self.view.startAnimation(move)
        self.run_timers()
        self.assertEqual([op[2]["tx"] for op in self.moves()], [20.0, 0.0])
        self.assertEqual(log, [("start", 0), ("repeat", 100), ("end", 200)])

    def test_clear_animation_stops_an_infinite_one(self):
        move = TranslateAnimation(0, 20, 0, 0)
        move.setDuration(100)
        move.setRepeatCount(Animation.INFINITE)
        self.view.startAnimation(move)
        left = self.run_timers(until=450)
        self.assertEqual(len(self.moves()), 5)
        self.assertTrue(left)
        self.view.clearAnimation()
        self.assertIsNone(self.view.getAnimation())
        self.run_timers()
        self.assertEqual(len(self.moves()), 5)

    def test_leaving_the_window_stops_an_animation(self):
        log = []
        move = TranslateAnimation(0, 20, 0, 0)
        move.setDuration(100)
        move.setAnimationListener(self.recorder(log))
        self.view.startAnimation(move)
        self.decor.removeAllViews()
        _ui.flush()
        self.run_timers()
        self.assertEqual(log, [])

    def test_a_new_animation_replaces_the_running_one(self):
        first, second = TranslateAnimation(0, 10, 0, 0), TranslateAnimation(0, 20, 0, 0)
        first.setDuration(second_duration := 100)
        second.setDuration(second_duration)
        self.view.startAnimation(first)
        self.view.startAnimation(second)
        self.run_timers()
        self.assertEqual([op[2]["tx"] for op in self.moves()], [20.0])

    def test_the_base_class_has_nothing_to_play(self):
        with self.assertRaises(NotImplementedError):
            self.view.startAnimation(Animation())


class HtmlText(unittest.TestCase):
    def spans(self, text, kind=object):
        return sorted((text.getSpanStart(s), text.getSpanEnd(s), type(s).__name__) for s in text.getSpans(0, len(str(text)), kind))

    def test_inline_tags_become_spans(self):
        text = Html.fromHtml("a <b>bold</b> <i>it</i> <u>un</u> <s>st</s> <a href=\"https://x.y/z\">link</a>")
        self.assertEqual(str(text), "a bold it un st link")
        self.assertEqual(self.spans(text), [(2, 6, "StyleSpan"), (7, 9, "StyleSpan"), (10, 12, "UnderlineSpan"),
                                            (13, 15, "StrikethroughSpan"), (16, 20, "URLSpan")])
        url = text.getSpans(0, 20, URLSpan)[0]
        self.assertEqual(url.getURL(), "https://x.y/z")
        styles = {text.getSpanStart(s): s.getStyle() for s in text.getSpans(0, 20, StyleSpan)}
        self.assertEqual(styles, {2: 1, 7: 2})

    def test_blocks_break_lines_and_entities_decode(self):
        text = Html.fromHtml("<p>one &amp; two</p><p>three</p>line<br>next<ul><li>x</li><li>y</li></ul>", Html.FROM_HTML_MODE_LEGACY)
        self.assertEqual(str(text), "one & two\n\nthree\n\nline\nnext\n• x\n• y")

    def test_an_unknown_tag_keeps_its_text_and_an_unclosed_one_ends_with_the_text(self):
        text = Html.fromHtml("<blink>keep</blink> <b>open")
        self.assertEqual(str(text), "keep open")
        self.assertEqual(self.spans(text), [(5, 9, "StyleSpan")])

    def test_a_link_without_an_address_is_plain_text(self):
        text = Html.fromHtml("<a name=\"x\">anchor</a>")
        self.assertEqual((str(text), self.spans(text)), ("anchor", []))

    def test_empty_and_none_give_empty_text(self):
        self.assertEqual((str(Html.fromHtml("")), str(Html.fromHtml(None))), ("", ""))

    def test_deep_nesting_is_refused(self):
        with self.assertRaises(ValueError):
            Html.fromHtml("<b>" * (Html.MAX_DEPTH + 1))

    def test_the_result_cannot_be_edited(self):
        from java.lang import UnsupportedOperationException
        with self.assertRaises(UnsupportedOperationException):
            Html.fromHtml("x").append("y")


class LinkTaps(unittest.TestCase):
    """a model of the label that wraps at spaces, 6 points to a character and 13 to a line, stands in for the measure of the app"""

    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        self.measure = _ui.measure_text
        _ui.measure_text = self.model

    def tearDown(self):
        _ui.measure_text = self.measure

    @staticmethod
    def model(text, size, bold, width):
        lines, widest = 0, 0
        for paragraph in text.split("\n"):
            lines += 1
            used = 0
            for word in paragraph.split(" "):
                need = len(word) * 6
                gap = 6 if used else 0
                if used and used + gap + need > width:
                    lines += 1
                    used = 0
                    gap = 0
                used += gap + need
                widest = max(widest, used)
        return (min(widest, width), lines * 13) if text else (0, 13)

    def label(self, text, width=120):
        view = TextView(self.decor.getContext())
        view.setTextSize(10)
        view.setText(text)
        self.decor.addView(view, FrameLayout.LayoutParams(width, 100))
        _ui.flush()
        return view

    def tap(self, view, x, y):
        dispatch_touch(view._id, MotionEvent.ACTION_DOWN, float(x), float(y), 0.0)
        return dispatch_touch(view._id, MotionEvent.ACTION_UP, float(x), float(y), 0.1)

    def linked(self, text):
        clicks = []

        class Link(ClickableSpan):
            def onClick(self, widget):
                clicks.append(widget)

        spanned = SpannableString(text)
        start = text.index("link")
        spanned.setSpan(Link(), start, start + 4, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return spanned, clicks

    def test_the_offset_is_the_character_under_the_point(self):
        view = self.label("hello world")
        self.assertEqual([view.getOffsetForPosition(x, 5) for x in (0, 5, 6, 35, 65)], [0, 0, 1, 5, 10])
        self.assertEqual(view.getOffsetForPosition(67, 5), -1)
        self.assertEqual(view.getOffsetForPosition(10, 20), -1)

    def test_the_offset_follows_wrapped_lines_and_newlines(self):
        view = self.label("aaa bbb ccc ddd", width=48)
        self.assertEqual(view.getOffsetForPosition(0, 5), 0)
        self.assertEqual(view.getOffsetForPosition(0, 18), 8)
        self.assertEqual(view.getOffsetForPosition(41, 18), 14)
        self.assertEqual(view.getOffsetForPosition(0, 31), -1)
        broken = self.label("ab\ncd\n\nef")
        self.assertEqual([broken.getOffsetForPosition(0, y) for y in (5, 18, 31, 44)], [0, 3, 6, 7])
        self.assertEqual(broken.getOffsetForPosition(0, 57), -1)

    def test_a_tap_on_a_link_calls_it(self):
        spanned, clicks = self.linked("see the link here")
        view = self.label("")
        view.setMovementMethod(LinkMovementMethod.getInstance())
        view.setText(spanned)
        _ui.flush()
        self.assertTrue(view.getMovementMethod() is LinkMovementMethod.getInstance())
        self.assertTrue(self.tap(view, 8 * 6 + 2, 5))
        self.assertEqual(clicks, [view])

    def test_a_tap_beside_the_link_does_nothing(self):
        spanned, clicks = self.linked("see the link here")
        view = self.label("")
        view.setMovementMethod(LinkMovementMethod.getInstance())
        view.setText(spanned)
        _ui.flush()
        self.tap(view, 2, 5)
        self.tap(view, 12 * 6 + 1, 5)
        self.tap(view, 8 * 6 - 1, 5)
        self.assertEqual(clicks, [])

    def test_the_link_of_html_is_tappable_and_reports_its_address(self):
        text = Html.fromHtml("go <a href=\"https://x.y\">here</a> now")
        view = self.label("")
        view.setMovementMethod(LinkMovementMethod.getInstance())
        view.setText(text)
        _ui.flush()
        urls = text.getSpans(0, len(str(text)), URLSpan)
        self.assertEqual([u.getURL() for u in urls], ["https://x.y"])
        self.assertTrue(self.tap(view, 3 * 6 + 3, 5))
        self.assertEqual(fake.opened[-1], "https://x.y")

    def test_text_without_a_movement_method_takes_no_touch(self):
        spanned, clicks = self.linked("see the link here")
        view = self.label("")
        view.setText(spanned)
        _ui.flush()
        self.assertFalse(self.tap(view, 8 * 6 + 2, 5))
        self.assertEqual(clicks, [])

    def test_the_arrow_key_method_leaves_the_touch_to_the_field(self):
        method = ArrowKeyMovementMethod.getInstance()
        self.assertIs(method, ArrowKeyMovementMethod.getInstance())
        view = self.label("text")
        view.setMovementMethod(method)
        _ui.flush()
        self.assertFalse(self.tap(view, 3, 5))


class Names(unittest.TestCase):
    def test_the_classes_resolve_by_their_java_names(self):
        for name in ("android.graphics.drawable.LayerDrawable", "android.graphics.drawable.PaintDrawable", "android.graphics.drawable.PictureDrawable",
                     "android.graphics.Picture", "android.view.animation.AnimationSet", "android.view.animation.TranslateAnimation",
                     "android.text.Html", "android.text.method.LinkMovementMethod", "android.text.method.ArrowKeyMovementMethod",
                     "android.webkit.ValueCallback", "androidx.core.content.ContextCompat"):
            self.assertIsNotNone(jclass(name), name)

    def test_a_drawable_of_the_android_client_is_an_error_a_plugin_can_catch(self):
        compat = jclass("androidx.core.content.ContextCompat")
        with self.assertRaises(NotImplementedError):
            compat.getDrawable(None, 12345)


if __name__ == "__main__":
    unittest.main()
