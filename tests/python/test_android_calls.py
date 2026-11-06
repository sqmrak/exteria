"""android and java classes that plugins import or look up by name: the ones with a python body and the ones that must
import but refuse where they are used"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path[:0] = [os.path.dirname(os.path.abspath(__file__)), os.path.join(ROOT, "python", "shim"),
                os.path.join(ROOT, "third_party", "exteraless")]

import fakeapp  # noqa: E402,F401

import java  # noqa: E402
from java.io import ByteArrayOutputStream  # noqa: E402
from java.net import URL, MalformedURLException  # noqa: E402
from java.nio import BufferOverflowException, BufferUnderflowException, ByteBuffer  # noqa: E402
from android.graphics import Paint, PorterDuff, PorterDuffColorFilter, RectF  # noqa: E402


class Graphics(unittest.TestCase):
    def test_porter_duff_filter(self):
        flt = PorterDuffColorFilter(0x35000000, PorterDuff.Mode.SRC_IN)
        self.assertEqual(flt._color, 0x35000000)
        self.assertEqual(flt._mode, "SRC_IN")
        self.assertIs(java.jclass("android.graphics.PorterDuff$Mode"), PorterDuff.Mode)

    def test_rectf_and_cap(self):
        rect = RectF(1, 2, 5, 10)
        self.assertEqual((rect.width(), rect.height(), rect.centerX(), rect.centerY()), (4.0, 8.0, 3.0, 6.0))
        self.assertIs(java.jclass("android.graphics.Paint$Cap"), Paint.Cap)


class Bytes(unittest.TestCase):
    def test_url_parts(self):
        url = URL("https://example.com:8443/a/b?x=1")
        self.assertEqual((url.getProtocol(), url.getHost(), url.getPort(), url.getPath(), url.getQuery()),
                         ("https", "example.com", 8443, "/a/b", "x=1"))
        self.assertEqual(URL("http://example.com/").getPort(), -1)

    def test_url_rejects_without_host_and_non_http_open(self):
        with self.assertRaises(MalformedURLException):
            URL("example.com/a")
        with self.assertRaises(MalformedURLException):
            URL("file:///etc/passwd").openStream()

    def test_byte_buffer_wrap_and_bounds(self):
        buffer = ByteBuffer.wrap([1, 2, 255])
        self.assertEqual(buffer.remaining(), 3)
        self.assertEqual([buffer.get(), buffer.get(), buffer.get()], [1, 2, -1])
        with self.assertRaises(BufferUnderflowException):
            buffer.get()
        out = ByteBuffer.allocate(2).put([7, 8])
        with self.assertRaises(BufferOverflowException):
            out.put(9)
        self.assertEqual(list(out.flip().array()), [7, 8])

    def test_byte_array_output_stream(self):
        out = ByteArrayOutputStream()
        out.write(65)
        out.write([66, 255])
        self.assertEqual(out.toByteArray(), [65, 66, -1])
        self.assertEqual(out.size(), 3)


class Interfaces(unittest.TestCase):
    def test_resources_provider_is_a_proxy_base(self):
        provider = java.jclass("org.telegram.ui.ActionBar.Theme$ResourcesProvider")
        java.dynamic_proxy(provider)

    def test_unknown_class_still_missing(self):
        with self.assertRaises(java.ClassNotFoundException):
            java.jclass("android.graphics.Shader")


class Timed(unittest.TestCase):
    """animators run on the timer of the app; the test drives the timers and a clock it sets"""

    def setUp(self):
        import android.animation as animation
        self.animation = animation
        self.now = [100.0]
        self._clock = animation._clock
        animation._clock = lambda: self.now[0]
        fakeapp.fake.timers.clear()

    def tearDown(self):
        self.animation._clock = self._clock

    def run_timers(self, step):
        import exteria_host
        for _ in range(200):
            if not fakeapp.fake.timers:
                return
            token, _delay = fakeapp.fake.timers.pop(0)
            self.now[0] += step
            exteria_host.run_token(token)

    def test_value_animator_reaches_the_end_and_reports(self):
        values, events = [], []
        animator = self.animation.ValueAnimator.ofFloat(0.0, 10.0)
        animator.setDuration(100)
        animator.setInterpolator(type("L", (), {"curve": "linear"})())
        animator.addUpdateListener(type("U", (), {"onAnimationUpdate": lambda self, a: values.append(a.getAnimatedValue())})())
        animator.addListener(type("E", (self.animation.AnimatorListenerAdapter,), {
            "onAnimationStart": lambda self, a, *r: events.append("start"),
            "onAnimationEnd": lambda self, a, *r: events.append("end")})())
        animator.start()
        self.assertTrue(animator.isRunning())
        self.run_timers(0.05)
        self.assertEqual(events, ["start", "end"])
        self.assertEqual(values[-1], 10.0)
        self.assertTrue(all(a <= b for a, b in zip(values, values[1:])))
        self.assertFalse(animator.isRunning())

    def test_int_values_and_cancel(self):
        events = []
        animator = self.animation.ValueAnimator.ofInt(0, 100).setDuration(1000)
        animator.addListener(type("E", (self.animation.AnimatorListenerAdapter,), {
            "onAnimationCancel": lambda self, a: events.append("cancel")})())
        animator.start()
        animator.cancel()
        self.assertEqual(events, ["cancel"])
        self.assertIsInstance(animator.getAnimatedValue(), int)
        self.run_timers(0.5)
        self.assertEqual(events, ["cancel"])

    def test_object_animator_drives_a_view_setter(self):
        from android.app import activity
        from android.view import View
        view = View(activity())
        animator = self.animation.ObjectAnimator.ofFloat(view, "alpha", 1.0, 0.0).setDuration(50)
        animator.start()
        self.run_timers(0.05)
        self.assertEqual(view.getAlpha(), 0.0)
        with self.assertRaises(AttributeError):
            self.animation.ObjectAnimator.ofFloat(view, "noSuchProperty", 0.0, 1.0)

    def test_animator_set_runs_in_order(self):
        order = []
        first = self.animation.ValueAnimator.ofFloat(0.0, 1.0).setDuration(10)
        second = self.animation.ValueAnimator.ofFloat(0.0, 1.0).setDuration(10)
        first.addListener(type("E", (self.animation.AnimatorListenerAdapter,), {"onAnimationEnd": lambda self, a, *r: order.append("first")})())
        second.addListener(type("S", (self.animation.AnimatorListenerAdapter,), {"onAnimationStart": lambda self, a, *r: order.append("second")})())
        group = self.animation.AnimatorSet()
        group.playSequentially(first, second)
        done = []
        group.addListener(type("E", (self.animation.AnimatorListenerAdapter,), {"onAnimationEnd": lambda self, a, *r: done.append(1)})())
        group.start()
        self.run_timers(0.02)
        self.assertEqual(order, ["first", "second"])
        self.assertEqual(done, [1])


class Views(unittest.TestCase):
    def setUp(self):
        from android import _ui
        from android.app import activity
        self._ui = _ui
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fakeapp.fake.ops.clear()

    def layout(self):
        self._ui.flush()

    def test_popup_window_shows_and_dismisses(self):
        from android.view import Gravity
        from android.widget import PopupWindow, TextView
        closed = []
        content = TextView(self.decor.getContext())
        popup = PopupWindow(content, 100, 40, True)
        popup.setOnDismissListener(type("D", (), {"onDismiss": lambda self: closed.append(1)})())
        popup.showAtLocation(self.decor, Gravity.TOP | Gravity.LEFT, 30, 50)
        self.assertTrue(popup.isShowing())
        self.assertEqual(self.decor.getChildCount(), 1)
        self.layout()
        self.assertEqual((content.getLeft(), content.getTop(), content.getWidth(), content.getHeight()), (30, 50, 100, 40))
        popup.dismiss()
        popup.dismiss()
        self.assertEqual((self.decor.getChildCount(), closed, popup.isShowing()), (0, [1], False))

    def test_seek_bar_follows_touch(self):
        from android.view import MotionEvent
        from android.widget import FrameLayout, SeekBar
        from android.view import dispatch_touch
        bar = SeekBar(self.decor.getContext())
        seen = []
        bar.setOnSeekBarChangeListener(type("L", (), {
            "onProgressChanged": lambda self, b, p, user: seen.append((p, user))})())
        self.decor.addView(bar, FrameLayout.LayoutParams(200, 20))
        self.layout()
        bar.setProgress(25)
        self.layout()
        self.assertEqual(bar._fill.getWidth(), 50)
        self.assertEqual(seen, [(25, False)])
        bar.setMax(10)
        self.assertEqual(bar.getProgress(), 10)

    def test_bitmap_drawable_tint_and_background(self):
        from android.graphics import Bitmap, PorterDuff
        from android.graphics.drawable import BitmapDrawable
        from android.view import View
        bitmap = Bitmap.createBitmap(2, 1)
        bitmap.setPixel(0, 0, 0xFFFFFFFF)
        drawable = BitmapDrawable(bitmap).mutate()
        drawable.setColorFilter(0xFF0000FF, PorterDuff.Mode.SRC_IN)
        self.assertEqual(drawable._rendered().getPixel(0, 0), 0xFF0000FF)
        self.assertEqual(drawable._rendered().getPixel(1, 0) >> 24, 0)
        with self.assertRaises(ValueError):
            BitmapDrawable(None)
        view = View(self.decor.getContext())
        view.setBackground(drawable)
        self.decor.addView(view)
        self.layout()
        self.assertTrue([op for op in fakeapp.fake.ops if op[0] == "img" and op[1] == view._id])

    def test_layout_helper(self):
        from android.view import Gravity
        from org.telegram.ui.Components import LayoutHelper
        frame = LayoutHelper.createFrame(48, 48, Gravity.LEFT | Gravity.CENTER_VERTICAL, 16, 0, 0, 0)
        self.assertEqual((frame.width, frame.height, frame.leftMargin, frame.gravity), (48, 48, 16, 19))
        linear = LayoutHelper.createLinear(-1, -2, 1.0, 17, 5, 6, 7, 8)
        self.assertEqual((linear.width, linear.height, linear.weight, linear.gravity, linear.topMargin), (-1, -2, 1.0, 17, 6))
        self.assertEqual(LayoutHelper.createLinear(-1, -2, 0, 2, 0, 0).topMargin, 2)

    def test_line_progress_and_cells(self):
        from android.widget import FrameLayout
        from org.telegram.ui.Cells import CheckBoxCell, RadioColorCell, TextCheckCell2
        from org.telegram.ui.Components import LineProgressView
        bar = LineProgressView(self.decor.getContext())
        self.decor.addView(bar, FrameLayout.LayoutParams(100, 4))
        bar.setProgress(0.5, True)
        self.layout()
        self.assertEqual(bar._fill.getWidth(), 50)
        bar.setProgress(7)
        self.assertEqual(bar.getProgress(), 1.0)
        cell = CheckBoxCell(self.decor.getContext(), 1)
        cell.setText("one", "", True, False)
        self.assertTrue(cell.isChecked())
        cell.setChecked(False, True)
        self.assertFalse(cell.isChecked())
        radio = RadioColorCell(self.decor.getContext())
        radio.setTextAndValue("r", True)
        self.assertTrue(radio.isChecked())
        row = TextCheckCell2(self.decor.getContext())
        row.setCollapsed(True)
        self.assertTrue(row.isCollapsed())

    def test_item_options_menu_runs_the_row(self):
        from android.view import View
        from org.telegram.ui.Components import ItemOptions
        anchor = View(self.decor.getContext())
        self.decor.addView(anchor)
        ran = []
        menu = ItemOptions.makeOptions(None, anchor).add(0, "go", False, lambda: ran.append("go")).add(0, "del", True, lambda: ran.append("del"))
        menu.show()
        self.layout()
        scrim = self.decor.getChildAt(1)
        rows = scrim.getChildAt(0)
        self.assertEqual(rows.getChildCount(), 2)
        rows.getChildAt(1).performClick()
        self.assertEqual((ran, self.decor.getChildCount()), (["del"], 1))
        with self.assertRaises(ValueError):
            ItemOptions(anchor).show()

    def test_bottom_sheet_shows_and_dismisses(self):
        from android.widget import TextView
        from org.telegram.ui.ActionBar import BottomSheet
        gone = []
        sheet = BottomSheet(self.decor.getContext(), False)
        sheet.setCustomView(TextView(self.decor.getContext()))
        sheet.setOnDismissListener(type("R", (), {"run": lambda self: gone.append(1)})())
        sheet.show()
        self.assertEqual(self.decor.getChildCount(), 1)
        sheet._scrim.performClick()
        self.assertEqual((self.decor.getChildCount(), gone), (0, [1]))
        locked = BottomSheet(self.decor.getContext())
        locked.setCustomView(TextView(self.decor.getContext()))
        locked.setCancelable(False)
        locked.show()
        locked._scrim.performClick()
        self.assertTrue(locked.isShowing())
        locked.dismiss()
        with self.assertRaises(ValueError):
            BottomSheet(self.decor.getContext()).show()

    def test_tl_records(self):
        from org.telegram.tgnet import TLRPC
        error = TLRPC.TL_error(code=400, text="BAD")
        self.assertEqual((error.code, error.text), (400, "BAD"))
        self.assertTrue(issubclass(TLRPC.TL_updates, TLRPC.Updates))


class Pickers(unittest.TestCase):
    def setUp(self):
        fakeapp.fake.picks.clear()

    def answer(self, chosen):
        import exteria_host
        exteria_host.pick_result(fakeapp.fake.picks[-1]["token"], chosen)

    def test_group_create_picker_returns_signed_ids_and_closes(self):
        from android.os import Bundle
        from org.telegram.ui import BaseFragment, GroupCreateActivity
        got, gone = [], []
        picker = GroupCreateActivity(Bundle())
        picker.setDelegate(type("D", (GroupCreateActivity.GroupCreateActivityDelegate,), {
            "didSelectUsers": lambda self, a, count, ids: got.append((count, list(ids.toArray())))})())
        picker.onFragmentDestroy = lambda: gone.append(1)
        BaseFragment().presentFragment(picker)
        self.assertEqual(fakeapp.fake.picks[-1]["types"], 15)
        self.answer([{"id": 7, "kind": 1}, {"id": 9, "kind": 3}, {"id": 11, "kind": 4}])
        self.assertEqual(got, [(3, [7, -9, -11])])
        self.assertEqual(gone, [1])
        self.answer([{"id": 7, "kind": 1}])
        self.assertEqual(len(got), 1)

    def test_going_back_from_the_picker_ends_it_without_a_choice(self):
        import exteria_host
        from android.os import Bundle
        from org.telegram.ui import BaseFragment, DialogsActivity, GroupCreateActivity
        for make in (GroupCreateActivity, DialogsActivity):
            got, gone = [], []
            picker = make(Bundle())
            picker.setDelegate(type("D", (object,), {
                "didSelectUsers": lambda self, *args: got.append(args),
                "didSelectDialogs": lambda self, *args: got.append(args)})())
            picker.onFragmentDestroy = lambda gone=gone: gone.append(1)
            BaseFragment().presentFragment(picker)
            token = fakeapp.fake.picks[-1]["token"]
            exteria_host.pick_cancelled(token)
            self.assertEqual((got, gone), ([], [1]), make.__name__)
            exteria_host.pick_cancelled(token)
            exteria_host.pick_result(token, [{"id": 7, "kind": 1}])
            self.assertEqual((got, gone), ([], [1]), "an answer after the end is dropped")

    def test_a_hook_on_the_adapter_narrows_the_kinds(self):
        from org.telegram.tgnet import TLRPC
        from org.telegram.ui import GroupCreateActivity
        original = GroupCreateActivity.GroupCreateAdapter.__init__

        def only_chats(self, activity=None):
            original(self, activity)
            self.contacts = type(self.contacts)(c for c in self.contacts if isinstance(c, TLRPC.Chat))

        GroupCreateActivity.GroupCreateAdapter.__init__ = only_chats
        try:
            picker = GroupCreateActivity()
            picker.setDelegate(object())
            picker._present()
        finally:
            GroupCreateActivity.GroupCreateAdapter.__init__ = original
        self.assertEqual(fakeapp.fake.picks[-1]["types"], 12)

    def test_preselection_and_missing_delegate_are_refused(self):
        from org.telegram.ui import GroupCreateActivity
        with self.assertRaises(NotImplementedError):
            GroupCreateActivity().select([1], False, False)
        with self.assertRaises(ValueError):
            GroupCreateActivity()._present()

    def test_dialogs_picker_follows_the_allow_keys(self):
        from android.os import Bundle
        from org.telegram.ui import DialogsActivity
        args = Bundle()
        for key in ("allowUsers", "allowBots", "allowGroups", "allowMegagroups", "allowLegacyGroups"):
            args.putBoolean(key, False)
        args.putBoolean("allowChannels", True)
        got = []
        picker = DialogsActivity(args)
        picker.setDelegate(type("D", (DialogsActivity.DialogsActivityDelegate,), {
            "didSelectDialogs": lambda self, fragment, dids, *rest: got.append((dids.get(0).dialogId, dids.get(0).topicId))})())
        picker._present()
        self.assertEqual((fakeapp.fake.picks[-1]["types"], fakeapp.fake.picks[-1]["limit"]), (8, 1))
        self.answer([{"id": 5, "kind": 4}])
        self.assertEqual(got, [(-5, 0)])

    def test_file_loader_names_and_sizes(self):
        from org.telegram.messenger import FileLoader, ImageLocation
        from org.telegram.tgnet import TLRPC
        document = TLRPC.Document(id=5, dc_id=2, file_name="a.b.PDF", mime_type="application/pdf")
        self.assertEqual(FileLoader.getAttachFileName(document), "2_5.PDF")
        self.assertEqual(FileLoader.getAttachFileName(TLRPC.Document(id=5, dc_id=2, mime_type="image/png")), "2_5.png")
        self.assertEqual(FileLoader.getAttachFileName(TLRPC.Document(id=5, dc_id=2)), "2_5")
        small, big = TLRPC.PhotoSize(type="m", w=90, h=60), TLRPC.PhotoSize(type="x", w=800, h=600)
        photo = TLRPC.Photo(id=8, sizes=[small, big])
        self.assertIs(FileLoader.getClosestPhotoSizeWithSize(photo.sizes, 9999), big)
        self.assertIs(FileLoader.getClosestPhotoSizeWithSize(photo.sizes, 100), small)
        self.assertIsNone(FileLoader.getClosestPhotoSizeWithSize([], 100))
        self.assertEqual(FileLoader.getAttachFileName(photo), "8_x.jpg")
        self.assertIs(ImageLocation.getForPhoto(big, photo).photoSize, big)
        with self.assertRaises(TypeError):
            FileLoader.getAttachFileName("x")
        with self.assertRaises(ValueError):
            FileLoader.getAttachFileName(TLRPC.Photo(id=1))

    def test_clip_to_outline_reaches_the_view(self):
        from android.app import activity
        from android.view import View
        from org.telegram.messenger.utils import ViewOutlineProviderImpl
        from org.telegram.ui.Components import BackupImageView
        decor = activity().getWindow().getDecorView()
        decor.removeAllViews()
        view = View(decor.getContext())
        decor.addView(view)
        view.outlineProvider = ViewOutlineProviderImpl.boundsWithRoundRect(12.0)
        self.assertEqual(view._clip_radius(), 0.0)
        view.clipToOutline = True
        self.assertEqual(view._clip_radius(), 12.0)
        image = BackupImageView(decor.getContext())
        image.setRoundRadius(8)
        self.assertEqual(image._clip_radius(), 8.0)
        with self.assertRaises(ValueError):
            ViewOutlineProviderImpl(-1)


if __name__ == "__main__":
    unittest.main()
