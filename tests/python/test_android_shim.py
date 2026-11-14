import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path[:0] = [os.path.dirname(os.path.abspath(__file__)), os.path.join(ROOT, "python", "shim"),
                os.path.join(ROOT, "third_party", "exteraless")]

import fakeapp  # noqa: E402

fake = fakeapp.fake

from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.graphics import Bitmap, Canvas, Paint  # noqa: E402
from android.graphics.drawable import GradientDrawable  # noqa: E402
from android.hardware import Sensor, SensorEventListener, SensorManager  # noqa: E402
from android.os import Bundle, Handler, Looper  # noqa: E402
from android.view import Gravity, MotionEvent, View, dispatch_touch  # noqa: E402
from android.widget import FrameLayout, ImageView, LinearLayout, TextView  # noqa: E402
import exteria_host  # noqa: E402
import java  # noqa: E402
from org.telegram.messenger import AndroidUtilities, NotificationCenter  # noqa: E402


def frame_of(view):
    return (view.getLeft(), view.getTop(), view.getWidth(), view.getHeight())


class AndroidShim(unittest.TestCase):
    def setUp(self):
        fake.ops.clear()
        fake.calls.clear()
        fake.timers.clear()
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fake.ops.clear()

    def sets(self, view_id):
        merged = {}
        for op in fake.ops:
            if op[0] == "set" and op[1] == view_id:
                merged.update(op[2])
        return merged

    def test_bundle_typed_defaults_and_copy(self):
        bundle = Bundle()
        self.assertEqual(bundle.getInt("missing"), 0)
        self.assertFalse(bundle.getBoolean("missing"))
        self.assertEqual(bundle.getFloat("missing"), 0.0)
        self.assertIsNone(bundle.getString("missing"))
        bundle.putBoolean("flag", True)
        self.assertEqual(bundle.getInt("flag", 7), 7)
        bundle.putInt("count", 4)
        self.assertFalse(bundle.getBoolean("count"))
        copy = Bundle(bundle)
        bundle.remove("count")
        self.assertEqual(copy.getInt("count"), 4)
        copy.clear()
        self.assertTrue(copy.isEmpty())

    def test_worker_has_no_main_looper(self):
        import threading
        found = []
        thread = threading.Thread(target=lambda: found.append(Looper.myLooper()))
        thread.start()
        thread.join()
        self.assertEqual(found, [None])
        self.assertIs(Looper.myLooper(), Looper.getMainLooper())

    def test_frame_layout_places_by_gravity_and_margins(self):
        ctx = activity()
        box = ImageView(ctx)
        box.setImageBitmap(Bitmap.createBitmap(40, 20, Bitmap.Config.ARGB_8888))
        params = FrameLayout.LayoutParams(40, 20, Gravity.CENTER)
        self.decor.addView(box, params)
        self.assertEqual(frame_of(box), ((320 - 40) // 2, (480 - 20) // 2, 40, 20))
        params.gravity = Gravity.BOTTOM | Gravity.RIGHT
        params.setMargins(0, 0, 5, 7)
        box.setLayoutParams(params)
        self.assertEqual(frame_of(box), (320 - 40 - 5, 480 - 20 - 7, 40, 20))

    def test_linear_layout_weights_and_wrap(self):
        ctx = activity()
        row = LinearLayout(ctx)
        row.setOrientation(LinearLayout.HORIZONTAL)
        a, b = View(ctx), View(ctx)
        row.addView(a, LinearLayout.LayoutParams(0, 30, 1.0))
        row.addView(b, LinearLayout.LayoutParams(0, 30, 3.0))
        self.decor.addView(row, FrameLayout.LayoutParams(200, -2))
        self.assertEqual(a.getWidth() + b.getWidth(), 200)
        self.assertEqual((a.getWidth(), b.getWidth()), (50, 150))
        self.assertEqual(row.getHeight(), 30)

    def test_text_view_wraps_at_max_width(self):
        label = TextView(activity())
        label.setTextSize(1, 10.0)
        label.setMaxWidth(AndroidUtilities.dp(60))
        label.setPadding(5, 3, 5, 3)
        label.setText("a" * 40)
        self.decor.addView(label, FrameLayout.LayoutParams(-2, -2))
        self.assertEqual(label.getWidth(), 60)
        self.assertGreater(label.getHeight(), 6)

    def test_changes_reach_the_backend_once_per_flush(self):
        view = View(activity())
        self.decor.addView(view, FrameLayout.LayoutParams(10, 10))
        view.setTranslationX(3)
        view.setTranslationX(4)
        view.setAlpha(0.5)
        _ui.flush()
        merged = self.sets(view._id)
        self.assertEqual((merged["tx"], merged["alpha"], merged["w"]), (4.0, 0.5, 10))
        self.assertEqual([op[0] for op in fake.ops if op[1:2] == [view._id]][:2], ["new", "set"])
        self.assertIn(["add", 0, view._id, 0], fake.ops)

    def test_animator_sets_the_target_and_sends_one_animation(self):
        view = View(activity())
        self.decor.addView(view, FrameLayout.LayoutParams(10, 10))
        ended = []
        view.animate().translationX(30).alpha(0.0).setDuration(120).withEndAction(lambda: ended.append(1)).start()
        self.assertEqual(view.getTranslationX(), 30.0)
        _ui.flush()
        anim = [op for op in fake.ops if op[0] == "anim"]
        self.assertEqual(len(anim), 1)
        self.assertEqual(anim[0][1:4], [view._id, {"tx": 30.0, "alpha": 0.0}, 120])
        token, delay = fake.timers[-1]
        self.assertEqual(delay, 120)
        exteria_host.run_token(token)
        self.assertEqual(ended, [1])

    def test_handler_runs_and_cancels(self):
        ran = []
        handler = Handler()
        keep, drop = (lambda: ran.append("keep")), (lambda: ran.append("drop"))
        handler.postDelayed(keep, 10)
        handler.postDelayed(drop, 10)
        handler.removeCallbacks(drop)
        for token, _ in list(fake.timers):
            exteria_host.run_token(token)
        self.assertEqual(ran, ["keep"])

    def test_touch_listener_and_click(self):
        view = View(activity())
        seen = []

        class Touch(View.OnTouchListener):
            def onTouch(self, v, event):
                seen.append(event.getActionMasked())
                return True

        view.setOnTouchListener(Touch())
        self.decor.addView(view, FrameLayout.LayoutParams(10, 10))
        _ui.flush()
        self.assertTrue(self.sets(view._id)["touch"])
        for action in (0, 2, 1):
            self.assertTrue(exteria_host.touch(view._id, action, 5, 5, 1.0))
        self.assertEqual(seen, [0, 2, 1])
        clicked = []
        other = View(activity())
        other.setOnClickListener(lambda v: clicked.append(v))
        self.decor.addView(other, FrameLayout.LayoutParams(10, 10))
        exteria_host.touch(other._id, MotionEvent.ACTION_DOWN, 5, 5, 1.0)
        exteria_host.touch(other._id, MotionEvent.ACTION_UP, 5, 5, 1.1)
        self.assertEqual(clicked, [other])
        moved = []
        third = View(activity())
        third.setOnClickListener(lambda v: moved.append(v))
        self.decor.addView(third, FrameLayout.LayoutParams(10, 10))
        exteria_host.touch(third._id, MotionEvent.ACTION_DOWN, 5, 5, 1.0)
        exteria_host.touch(third._id, MotionEvent.ACTION_MOVE, 80, 5, 1.05)
        exteria_host.touch(third._id, MotionEvent.ACTION_UP, 80, 5, 1.1)
        self.assertEqual(moved, [])

    def test_bitmap_canvas_and_image_op(self):
        bitmap = Bitmap.createBitmap(4, 2, Bitmap.Config.ARGB_8888)
        paint = Paint()
        paint.setColor(0xFFD97757)
        Canvas(bitmap).drawRect(1, 0, 3, 1, paint)
        self.assertEqual(bitmap.getPixel(1, 0), 0xFFD97757)
        self.assertEqual(bitmap.getPixel(0, 0), 0)
        self.assertEqual(bitmap.getPixel(3, 0), 0)
        image = ImageView(activity())
        self.decor.addView(image, FrameLayout.LayoutParams(8, 4))
        image.setImageBitmap(bitmap)
        _ui.flush()
        img = [op for op in fake.ops if op[0] == "img"][0]
        self.assertEqual(img[2:4], [4, 2])
        import base64
        self.assertEqual(len(base64.b64decode(img[4])), 4 * 2 * 4)

    def test_background_follows_the_drawable(self):
        view = View(activity())
        shape = GradientDrawable()
        shape.setShape(GradientDrawable.OVAL)
        shape.setColor(0xFF112233)
        view.setBackground(shape)
        self.decor.addView(view, FrameLayout.LayoutParams(10, 10))
        shape.setColor(0xFF445566)
        _ui.flush()
        self.assertEqual(self.sets(view._id)["bg"]["color"], 0xFF445566)
        self.assertTrue(self.sets(view._id)["bg"]["oval"])

    def test_sensor_events_reach_the_listener(self):
        got = []

        class Listener(java.dynamic_proxy(SensorEventListener)):
            def onSensorChanged(self, event):
                got.append(list(event.values))

        manager = activity().getSystemService("sensor")
        sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        self.assertTrue(manager.registerListener(Listener(), sensor, SensorManager.SENSOR_DELAY_UI))
        exteria_host.sensor(0.0, 9.8, 0.1, 1.0)
        self.assertEqual(got, [[0.0, 9.8, 0.1]])
        self.assertEqual([c[0] for c in fake.calls if c[0].startswith("sensor.")][-2:], ["sensor.available", "sensor.start"])

    def test_new_messages_reach_a_notification_delegate(self):
        got = []

        class Delegate(java.dynamic_proxy(NotificationCenter.NotificationCenterDelegate)):
            def didReceivedNotification(self, notification_id, account, args):
                got.append((notification_id, account, args[0], args[1][0].messageOwner.message, args[1][0].isOut()))

        delegate = Delegate()
        NotificationCenter.getInstance(0).addObserver(delegate, NotificationCenter.didReceiveNewMessages)
        exteria_host.new_messages(0, 777, [{"id": 5, "text": "hi", "out": False}])
        NotificationCenter.getInstance(0).removeObserver(delegate, NotificationCenter.didReceiveNewMessages)
        self.assertEqual(got, [(NotificationCenter.didReceiveNewMessages, 0, 777, "hi", False)])

    def test_unknown_classes_and_shims_resolve(self):
        self.assertIs(java.jclass("android.view.View$OnClickListener"), View.OnClickListener)
        helper = java.jclass("org.telegram.messenger.SendMessagesHelper")
        self.assertIs(java.jclass("org.telegram.messenger.SendMessagesHelper$SendMessageParams"), helper.SendMessageParams)
        with self.assertRaises(java.ClassNotFoundException):
            java.jclass("org.telegram.messenger.NoSuchThing")

    def test_current_chat_and_send(self):
        from org.telegram.ui import ChatActivity, LaunchActivity
        fragment = LaunchActivity.getLastFragment()
        self.assertIsInstance(fragment, ChatActivity)
        self.assertEqual(fragment.getDialogId(), 777)
        self.assertEqual(fragment.getCurrentUser().first_name, "Ann")
        from org.telegram.messenger import SendMessagesHelper
        params = SendMessagesHelper.SendMessageParams.of("hello", 777)
        SendMessagesHelper.getInstance(0).sendMessage(params)
        self.assertIn(("chat.send", {"peer": 777, "text": "hello", "reply": 0}), fake.calls)


if __name__ == "__main__":
    unittest.main()
