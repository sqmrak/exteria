"""the classes that kept plugins of the public catalogs from loading: CheckBox2, the proxies of java.chaquopy, NsdServiceInfo and NsdManager, and the
two that only import (RLottieImageView, ShareAlert)"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

from android import _ui  # noqa: E402
from android.app import activity  # noqa: E402
from android.graphics import Bitmap, Canvas  # noqa: E402
from android.widget import FrameLayout  # noqa: E402
from java import jclass  # noqa: E402
from java.lang import NullPointerException  # noqa: E402
from org.telegram.ui.Components import CheckBox2, RLottieImageView, ShareAlert  # noqa: E402


class Boxes(unittest.TestCase):
    def setUp(self):
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        _ui.flush()

    def box(self, size=21):
        box = CheckBox2(self.decor.getContext(), size, None)
        self.decor.addView(box, FrameLayout.LayoutParams(-2, -2))
        _ui.flush()
        return box

    def paint(self, box):
        bitmap = Bitmap(box.getWidth(), box.getHeight())
        box.onDraw(Canvas(bitmap))
        return bitmap

    def test_it_has_the_size_it_is_given_and_the_state_it_is_set_to(self):
        box = self.box(24)
        self.assertEqual((box.getWidth(), box.getHeight()), (24, 24))
        self.assertFalse(box.isChecked())
        box.setChecked(True, False)
        self.assertTrue(box.isChecked())
        box.setNum(3)
        self.assertEqual(box.getNum(), 3)

    def test_an_unchecked_box_is_empty_unless_it_draws_its_ring(self):
        box = self.box()
        box.setColor(0xFF112233, 0xFF445566, 0xFFFFFFFF)
        empty = self.paint(box)
        self.assertEqual(sum(1 for b in empty._pixels if b), 0)
        box.setDrawUnchecked(True)
        ring = self.paint(box)
        self.assertEqual(ring.getPixel(10, 1) & 0xFFFFFF, 0x112233)
        self.assertEqual(ring.getPixel(10, 10), 0)

    def test_a_checked_box_is_a_disc_with_a_tick(self):
        box = self.box(40)
        box.setColor(0xFF112233, 0xFF445566, 0xFFFFFFFF)
        box.setChecked(True)
        drawn = self.paint(box)
        self.assertEqual(drawn.getPixel(6, 20), 0xFF445566)
        light = sum(1 for x in range(40) for y in range(40) if drawn.getPixel(x, y) == 0xFFFFFFFF)
        self.assertGreater(light, 5)
        self.assertEqual(drawn.getPixel(0, 0), 0)

    def test_the_colors_may_be_theme_keys(self):
        box = self.box()
        box.setColor("dialogRoundCheckBox", "checkboxDisabled", "dialogRoundCheckBoxCheck")
        box.setChecked(True)
        self.assertEqual(self.paint(box).getPixel(2, 10), 0xFF112233)

    def test_it_resolves_by_its_java_name(self):
        self.assertIs(jclass("org.telegram.ui.Components.CheckBox2"), CheckBox2)


class Proxies(unittest.TestCase):
    def test_the_dynamic_proxy_is_importable_from_chaquopy_too(self):
        import java
        from java.chaquopy import dynamic_proxy
        self.assertIs(dynamic_proxy, java.dynamic_proxy)
        from java.chaquopy import static_proxy
        self.assertIs(static_proxy, java.static_proxy)

    def test_a_static_proxy_is_refused_where_the_class_is_made(self):
        from java import static_proxy
        with self.assertRaises(NotImplementedError):
            class Mine(static_proxy()):
                pass

    def test_an_unknown_name_of_chaquopy_is_an_attribute_error(self):
        import java.chaquopy
        with self.assertRaises(AttributeError):
            java.chaquopy.nothing


class Discovery(unittest.TestCase):
    def test_the_service_record_keeps_what_it_is_given(self):
        from android.net.nsd import NsdServiceInfo
        info = NsdServiceInfo()
        info.setServiceName("phone")
        info.setServiceType("_adb-tls-connect._tcp")
        info.setPort(37123)
        info.setHost("192.168.0.5")
        info.setAttribute("v", 2)
        info.setAttribute("empty")
        self.assertEqual((info.getServiceName(), info.getServiceType(), info.getPort(), info.getHost()),
                         ("phone", "_adb-tls-connect._tcp", 37123, "192.168.0.5"))
        self.assertEqual(info.getAttributes(), {"v": "2", "empty": None})
        self.assertIn("phone", info.toString())
        with self.assertRaises(NullPointerException):
            info.setAttribute(None, "x")

    def test_the_manager_is_the_service_and_says_what_it_lacks(self):
        from android.net.nsd import NsdManager
        manager = activity().getSystemService("servicediscovery")
        self.assertIs(manager, NsdManager._get())
        self.assertIs(activity().getSystemService(jclass("android.content.Context").NSD_SERVICE), manager)
        for call in (lambda: manager.discoverServices("_x._tcp", NsdManager.PROTOCOL_DNS_SD, object()), lambda: manager.resolveService(None, None),
                     lambda: manager.registerService(None, 1, None), lambda: manager.stopServiceDiscovery(None)):
            with self.assertRaises(NotImplementedError):
                call()

    def test_the_uri_module_still_works_from_the_package(self):
        from android.net import Uri
        self.assertEqual(Uri.parse("https://t.me/x").getHost(), "t.me")
        self.assertIs(jclass("android.net.nsd.NsdManager"), __import__("android.net.nsd", fromlist=["NsdManager"]).NsdManager)


class ImportOnly(unittest.TestCase):
    def test_a_lottie_view_and_a_share_sheet_load_and_refuse_to_be_made(self):
        with self.assertRaises(NotImplementedError):
            RLottieImageView(None)
        with self.assertRaises(NotImplementedError):
            ShareAlert(None, None, None, "/tmp/x", None, None, False, None, None, False, False, False, None, None)
        self.assertIs(jclass("org.telegram.ui.Components.RLottieImageView"), RLottieImageView)

    def test_the_delegate_of_the_share_sheet_can_be_extended(self):
        shared = []

        class Delegate(jclass("org.telegram.ui.Components.ShareAlert$ShareAlertDelegate")):
            def didShare(self):
                shared.append(1)

        Delegate().didShare()
        self.assertEqual(shared, [1])
        self.assertIs(jclass("org.telegram.ui.Components.ShareAlert$ShareAlertDelegate"), ShareAlert.ShareAlertDelegate)


if __name__ == "__main__":
    unittest.main()
