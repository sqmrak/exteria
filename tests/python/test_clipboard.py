"""the clipboard a plugin can write to and not read: ClipData, ClipboardManager, and the copy helper of the sdk that goes through them"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from android.app import activity  # noqa: E402
from android.content import ClipboardManager, ClipData, Context  # noqa: E402
from java import jclass  # noqa: E402
from java.lang import IllegalArgumentException, NullPointerException, SecurityException  # noqa: E402


class Clipboard(unittest.TestCase):
    def setUp(self):
        fake.clipboard.clear()
        self.manager = activity().getSystemService(Context.CLIPBOARD_SERVICE)

    def test_the_service_is_the_clipboard_manager(self):
        self.assertIsInstance(self.manager, ClipboardManager)
        self.assertIs(activity().getSystemService("clipboard"), self.manager)
        self.assertIs(jclass("android.content.ClipboardManager"), ClipboardManager)

    def test_a_clip_of_text_reaches_the_app(self):
        self.manager.setPrimaryClip(ClipData.newPlainText("link", "https://t.me/x"))
        self.manager.setText("second")
        self.assertEqual(fake.clipboard, ["https://t.me/x", "second"])

    def test_text_outside_the_basic_plane_and_empty_text_arrive_whole(self):
        for text in ("", "\U0001F600 é中"):
            self.manager.setPrimaryClip(ClipData.newPlainText("x", text))
        self.assertEqual(fake.clipboard, ["", "\U0001F600 é中"])

    def test_the_clip_keeps_its_label_and_items(self):
        clip = ClipData.newPlainText("label", "one")
        clip.addItem(ClipData.Item("two"))
        self.assertEqual((clip.getDescription(), clip.getItemCount()), ("label", 2))
        self.assertEqual((clip.getItemAt(0).getText(), clip.getItemAt(1).coerceToText()), ("one", "two"))
        self.manager.setPrimaryClip(clip)
        self.assertEqual(fake.clipboard, ["one"])

    def test_a_clip_without_text_or_without_items_is_refused(self):
        with self.assertRaises(IllegalArgumentException):
            self.manager.setPrimaryClip(ClipData("empty"))
        with self.assertRaises(IllegalArgumentException):
            self.manager.setPrimaryClip(ClipData("x", ["text/plain"], ClipData.Item(None)))
        with self.assertRaises(NullPointerException):
            self.manager.setPrimaryClip(None)
        with self.assertRaises(NullPointerException):
            ClipData.newPlainText("x", None)
        self.assertEqual(fake.clipboard, [])

    def test_a_text_the_app_refuses_is_an_illegal_argument(self):
        with self.assertRaises(IllegalArgumentException):
            self.manager.setPrimaryClip(ClipData.newPlainText("big", "x" * (1024 * 1024 + 1)))
        self.assertEqual(fake.clipboard, [])
        self.manager.setPrimaryClip(ClipData.newPlainText("max", "x" * (1024 * 1024)))
        self.assertEqual(len(fake.clipboard[0]), 1024 * 1024)

    def test_reading_the_clipboard_is_refused(self):
        self.manager.setText("secret of the user")
        for read in (self.manager.getPrimaryClip, self.manager.hasPrimaryClip, self.manager.getText):
            with self.assertRaises(SecurityException):
                read()

    def test_the_copy_helper_of_the_sdk_copies(self):
        import android_utils
        android_utils.copy_to_clipboard("from the helper")
        self.assertEqual(fake.clipboard, ["from the helper"])


if __name__ == "__main__":
    unittest.main()
