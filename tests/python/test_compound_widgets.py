"""CheckBox, CompoundButton, Button, HorizontalScrollView and NestedScrollView, the widgets plugins of the public catalogs build that the shim lacked"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.view import MotionEvent, dispatch_touch  # noqa: E402
from android.widget import (Button, CheckBox, CompoundButton, FrameLayout, HorizontalScrollView, LinearLayout, ScrollView,  # noqa: E402
                            TextView)
from java import jclass  # noqa: E402


class Listener:
    def __init__(self):
        self.seen = []

    def onCheckedChanged(self, button, checked):
        self.seen.append(("changed", checked))

    def onClick(self, view):
        self.seen.append(("click", view.isChecked()))


class CompoundWidgets(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()
        fakeapp.fake.ops.clear()

    def tap(self, view):
        dispatch_touch(view._id, MotionEvent.ACTION_DOWN, 5.0, 5.0, 0.0)
        dispatch_touch(view._id, MotionEvent.ACTION_UP, 5.0, 5.0, 0.1)

    def test_a_tap_flips_the_state_then_tells_both_listeners(self):
        box = CheckBox(self.decor.getContext())
        listener = Listener()
        box.setOnCheckedChangeListener(listener)
        box.setOnClickListener(listener)
        box.setText("Keep")
        self.decor.addView(box, FrameLayout.LayoutParams(200, 30))
        _ui.flush()
        self.assertFalse(box.isChecked())
        self.tap(box)
        self.assertTrue(box.isChecked())
        self.tap(box)
        self.assertEqual(listener.seen, [("changed", True), ("click", True), ("changed", False), ("click", False)])
        self.assertEqual(str(box.getText()), "Keep")

    def test_set_checked_notifies_only_on_a_change(self):
        box = CheckBox(self.decor.getContext())
        listener = Listener()
        box.setOnCheckedChangeListener(listener)
        box.setChecked(False)
        box.setChecked(True)
        box.setChecked(True)
        box.toggle()
        self.assertEqual(listener.seen, [("changed", True), ("changed", False)])

    def test_a_click_listener_alone_is_reported(self):
        box = CheckBox(self.decor.getContext())
        self.assertFalse(box.hasOnClickListeners())
        box.setOnClickListener(Listener())
        self.assertTrue(box.hasOnClickListeners())
        box.setOnClickListener(None)
        self.assertFalse(box.hasOnClickListeners())

    def test_layout_puts_the_square_before_the_label(self):
        box = CheckBox(self.decor.getContext())
        box.setText("Keep")
        self.decor.addView(box, LinearLayout.LayoutParams(300, 40))
        _ui.flush()
        square, label = box._box, box._label
        self.assertEqual((square.getWidth(), square.getHeight()), (CompoundButton.BOX, CompoundButton.BOX))
        self.assertEqual(label.getLeft(), CompoundButton.BOX + CompoundButton.GAP)
        self.assertGreater(label.getWidth(), 0)
        self.assertEqual(square.getTop(), (40 - CompoundButton.BOX) // 2)

    def test_the_square_is_redrawn_when_the_state_changes(self):
        box = CheckBox(self.decor.getContext())
        self.decor.addView(box, FrameLayout.LayoutParams(100, 30))
        _ui.flush()
        off = box._box.getBackground()
        box.setChecked(True)
        on = box._box.getBackground()
        self.assertIsNot(off, on)

    def test_button_is_a_clickable_centered_text_view(self):
        button = Button(self.decor.getContext())
        seen = []
        button.setOnClickListener(type("L", (), {"onClick": lambda self, v: seen.append(v)})())
        self.decor.addView(button, FrameLayout.LayoutParams(80, 30))
        _ui.flush()
        self.assertIsInstance(button, TextView)
        self.assertTrue(button.isClickable())
        self.tap(button)
        self.assertEqual(seen, [button])

    def test_horizontal_scroll_view_takes_the_width_of_its_child(self):
        scroll = HorizontalScrollView(self.decor.getContext())
        row = LinearLayout(self.decor.getContext())
        for _ in range(3):
            row.addView(FrameLayout(self.decor.getContext()), LinearLayout.LayoutParams(150, 20))
        scroll.addView(row, FrameLayout.LayoutParams(-2, -1))
        self.decor.addView(scroll, FrameLayout.LayoutParams(200, 60))
        _ui.flush()
        self.assertEqual((scroll.getWidth(), scroll.getHeight()), (200, 60))
        self.assertEqual((row.getWidth(), row.getHeight()), (450, 60))
        sets = [op[2] for op in fakeapp.fake.ops if op[0] == "set" and op[1] == scroll._id and "content" in op[2]]
        self.assertEqual(sets[-1]["content"], [450, 60])

    def test_the_classes_resolve_by_their_java_names(self):
        for name, shim in (("android.widget.CheckBox", CheckBox), ("android.widget.CompoundButton", CompoundButton),
                           ("android.widget.Button", Button), ("android.widget.HorizontalScrollView", HorizontalScrollView)):
            self.assertIs(jclass(name), shim)
        nested = jclass("androidx.core.widget.NestedScrollView")
        self.assertTrue(issubclass(nested, ScrollView))
        self.assertEqual(jclass("android.provider.OpenableColumns").DISPLAY_NAME, "_display_name")
        self.assertEqual(jclass("android.provider.OpenableColumns").SIZE, "_size")
        self.assertEqual(jclass("android.graphics.PixelFormat").TRANSLUCENT, -3)


if __name__ == "__main__":
    unittest.main()
