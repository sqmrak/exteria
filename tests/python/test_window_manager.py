"""WindowManager: windows that are views of the overlay of the app, placed by gravity and offsets, and the overlay permission that is always on"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.graphics import PixelFormat  # noqa: E402
from android.view import Gravity, View, WindowManager  # noqa: E402
from android.widget import FrameLayout  # noqa: E402
from java import jclass  # noqa: E402
from java.lang import IllegalArgumentException, IllegalStateException, NullPointerException  # noqa: E402

LP = WindowManager.LayoutParams


class Windows(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        self.wm = activity().getSystemService("window")
        self.view = View(self.decor.getContext())

    def show(self, params):
        self.wm.addView(self.view, params)
        _ui.flush()
        return (self.view.getLeft(), self.view.getTop(), self.view.getWidth(), self.view.getHeight())

    def test_the_service_is_the_window_manager(self):
        self.assertIsInstance(self.wm, WindowManager)
        self.assertIs(activity().getSystemService(jclass("android.content.Context").WINDOW_SERVICE), self.wm)

    def test_top_left_offsets_come_from_the_corner(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, LP.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT)
        params.gravity = Gravity.TOP | Gravity.LEFT
        params.x, params.y = 12, 140
        self.assertEqual(self.show(params), (12, 140, 40, 30))

    def test_right_and_bottom_offsets_come_from_the_far_edges(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        params.gravity = Gravity.BOTTOM | Gravity.RIGHT
        params.x, params.y = 10, 20
        left, top, width, height = self.show(params)
        self.assertEqual((left + width, top + height), (self.decor.getWidth() - 10, self.decor.getHeight() - 20))

    def test_no_gravity_centers_the_window_and_the_offsets_move_it_from_there(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        left, top, width, height = self.show(params)
        self.assertEqual((left, top), ((self.decor.getWidth() - 40) // 2, (self.decor.getHeight() - 30) // 2))
        params.x, params.y = 15, -5
        self.wm.updateViewLayout(self.view, params)
        _ui.flush()
        self.assertEqual((self.view.getLeft(), self.view.getTop()), (left + 15, top - 5))

    def test_the_start_gravity_is_the_left_edge(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        params.gravity = Gravity.TOP | Gravity.START
        params.x = 7
        self.assertEqual(self.show(params)[:2], (7, 0))

    def test_update_moves_and_resizes_the_window(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        params.gravity = Gravity.TOP | Gravity.LEFT
        self.show(params)
        params.x, params.y, params.width, params.height = 50, 60, 70, 80
        self.wm.updateViewLayout(self.view, params)
        _ui.flush()
        self.assertEqual((self.view.getLeft(), self.view.getTop(), self.view.getWidth(), self.view.getHeight()), (50, 60, 70, 80))

    def test_remove_takes_the_window_off(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        self.show(params)
        self.wm.removeView(self.view)
        self.assertIsNone(self.view.getParent())
        self.assertEqual(self.decor.getChildCount(), 0)

    def test_the_alpha_of_the_params_is_applied(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        params.alpha = 0.5
        self.wm.addView(self.view, params)
        self.assertEqual(self.view.getAlpha(), 0.5)

    def test_the_mistakes_of_android_are_the_exceptions_of_android(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        self.wm.addView(self.view, params)
        with self.assertRaises(IllegalStateException):
            self.wm.addView(self.view, params)
        stranger = View(self.decor.getContext())
        with self.assertRaises(IllegalArgumentException):
            self.wm.updateViewLayout(stranger, params)
        with self.assertRaises(IllegalArgumentException):
            self.wm.removeView(stranger)
        with self.assertRaises(IllegalArgumentException):
            self.wm.addView(stranger, FrameLayout.LayoutParams(1, 1))
        with self.assertRaises(NullPointerException):
            self.wm.addView(None, params)
        self.wm.removeView(self.view)
        with self.assertRaises(IllegalArgumentException):
            self.wm.removeView(self.view)

    def test_a_window_taken_off_by_the_plugin_tree_cannot_be_updated(self):
        params = LP(40, 30, LP.TYPE_APPLICATION_OVERLAY, 0, PixelFormat.TRANSLUCENT)
        self.wm.addView(self.view, params)
        self.decor.removeAllViews()
        with self.assertRaises(IllegalArgumentException):
            self.wm.updateViewLayout(self.view, params)

    def test_every_constructor_form_fills_the_fields(self):
        self.assertEqual((LP().width, LP().height), (-1, -1))
        self.assertEqual(LP(2038).type, 2038)
        self.assertEqual((LP(2038, 8).flags, LP(2038, 8, -3).format), (8, -3))
        seven = LP(10, 20, 3, 4, 2038, 8, -3)
        self.assertEqual((seven.width, seven.height, seven.x, seven.y, seven.type, seven.flags, seven.format), (10, 20, 3, 4, 2038, 8, -3))
        with self.assertRaises(TypeError):
            LP(1, 2, 3, 4)

    def test_the_overlay_permission_is_always_there(self):
        settings = jclass("android.provider.Settings")
        self.assertTrue(settings.canDrawOverlays(self.decor.getContext()))
        self.assertEqual(settings.ACTION_MANAGE_OVERLAY_PERMISSION, "android.settings.action.MANAGE_OVERLAY_PERMISSION")
        self.assertIs(jclass("android.view.WindowManager"), WindowManager)


if __name__ == "__main__":
    unittest.main()
