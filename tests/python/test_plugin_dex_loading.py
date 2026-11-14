"""what the dex plugins of the catalog hit when they load: the string overloads of the number boxes, the primitive class objects a plugin hands to
getDeclaredMethod, jarray lists as the varargs of reflection, the TL_stars records and the reason shown for a plugin that did not load"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fakeapp  # noqa: E402,F401

sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import dexvm  # noqa: E402,F401
from dexvm import api, jreflect  # noqa: E402
from java import jclass  # noqa: E402


def static(owner, name, descriptor):
    return api.lookup_host(owner).typed()[(name, descriptor)][0]


class BoxStrings(unittest.TestCase):
    def test_a_box_made_from_text_holds_a_number(self):
        for owner, kind, text, expected in (
                ("java.lang.Double", "D", "-1", -1.0), ("java.lang.Double", "D", "2.5", 2.5),
                ("java.lang.Float", "F", "-1", -1.0), ("java.lang.Short", "S", "-7", -7), ("java.lang.Byte", "B", "12", 12)):
            box = static(owner, "valueOf", "(Ljava/lang/String;)L%s;" % owner.replace(".", "/"))(text)
            self.assertEqual(getattr(box, {"D": "doubleValue", "F": "floatValue", "S": "shortValue", "B": "byteValue"}[kind])(), expected, owner + " " + text)

    def test_text_that_is_not_a_number_is_a_number_format_exception(self):
        valueOf = static("java.lang.Double", "valueOf", "(Ljava/lang/String;)Ljava/lang/Double;")
        with self.assertRaises(Exception) as caught:
            valueOf("pixel")
        self.assertIn("NumberFormatException", type(caught.exception).__name__)


class ReflectionTypes(unittest.TestCase):
    def test_primitive_class_objects_tell_int_from_long(self):
        self.assertIs(jreflect._as_jtype(jclass("java.lang.Integer").TYPE), api.PRIMITIVES["I"])
        self.assertIs(jreflect._as_jtype(jclass("java.lang.Long").TYPE), api.PRIMITIVES["J"])
        self.assertIs(jreflect._as_jtype(jclass("java.lang.Float").TYPE), api.PRIMITIVES["F"])
        self.assertIs(jreflect._as_jtype(jclass("java.lang.Boolean").TYPE), api.PRIMITIVES["Z"])

    def test_a_python_list_is_the_varargs_of_getdeclaredmethod(self):
        wanted = jreflect._varargs(([jclass("java.lang.Integer").TYPE, jclass("java.lang.Float").TYPE],))
        self.assertEqual(wanted, [api.PRIMITIVES["I"], api.PRIMITIVES["F"]])

    def test_the_python_class_of_a_java_class_stands_for_its_vm_class(self):
        loader = jclass("java.lang.ClassLoader")
        self.assertIs(jreflect._as_jtype(loader), api.lookup_host("java.lang.ClassLoader"))


class StarRecords(unittest.TestCase):
    def test_tl_stars_is_a_class_of_the_tl_package(self):
        stars = jclass("org.telegram.tgnet.tl.TL_stars")
        gift = stars.TL_starGift(stars=50, title="cake")
        self.assertEqual((gift.stars, gift.title, gift.limited), (50, "cake", False))
        self.assertIsInstance(gift, stars.StarGift)

    def test_a_clone_copies_field_by_field(self):
        stars = jclass("org.telegram.tgnet.tl.TL_stars")
        donor = stars.TL_starGift(id=7, stars=50)
        clone = stars.TL_starGift()
        for field in ("id", "stars"):
            setattr(clone, field, getattr(donor, field))
        self.assertEqual((clone.id, clone.stars), (7, 50))

    def test_the_gift_list_holds_java_lists_and_the_unmodified_answer_is_apart(self):
        stars = jclass("org.telegram.tgnet.tl.TL_stars")
        gifts = stars.TL_starGifts(hash=3)
        gifts.gifts.add(stars.TL_starGift(id=1))
        self.assertEqual((gifts.hash, gifts.gifts.size()), (3, 1))
        self.assertNotIsInstance(stars.TL_starGiftsNotModified(), stars.TL_starGifts)

    def test_a_nested_class_is_found_by_its_dollar_name(self):
        self.assertIs(jclass("org.telegram.tgnet.tl.TL_stars$TL_starGift"), jclass("org.telegram.tgnet.tl.TL_stars").TL_starGift)


class RenderEffects(unittest.TestCase):
    def setUp(self):
        from android import _ui
        from android.app import activity
        from android.view import View
        self.ui = _ui
        self.decor = activity().getWindow().getDecorView()
        self.decor.removeAllViews()
        self.view = View(self.decor.getContext())
        self.decor.addView(self.view)
        _ui.flush()
        fakeapp.fake.ops.clear()

    def blur_ops(self):
        self.ui.flush()
        return [op[2]["blur"] for op in fakeapp.fake.ops if op[0] == "set" and op[1] == self.view._id and "blur" in op[2]]

    def test_a_blur_reaches_the_app_with_its_radius(self):
        effect = jclass("android.graphics.RenderEffect")
        tile = jclass("android.graphics.Shader").TileMode.MIRROR
        self.view.setRenderEffect(effect.createBlurEffect(8.0, 12.0, tile))
        self.assertEqual(self.blur_ops(), [12.0])
        self.assertIsNotNone(self.view.getRenderEffect())

    def test_none_takes_the_blur_away(self):
        effect = jclass("android.graphics.RenderEffect")
        tile = jclass("android.graphics.Shader").TileMode.CLAMP
        self.view.setRenderEffect(effect.createBlurEffect(4.0, 4.0, tile))
        self.blur_ops()
        fakeapp.fake.ops.clear()
        self.view.setRenderEffect(None)
        self.assertEqual(self.blur_ops(), [0.0])

    def test_a_chain_of_blurs_adds_up(self):
        effect = jclass("android.graphics.RenderEffect")
        tile = jclass("android.graphics.Shader").TileMode.CLAMP
        chain = effect.createChainEffect(effect.createBlurEffect(3.0, 3.0, tile), effect.createBlurEffect(5.0, 2.0, tile))
        self.view.setRenderEffect(chain)
        self.assertEqual(self.blur_ops(), [8.0])

    def test_a_kind_the_app_cannot_draw_is_named(self):
        effect = jclass("android.graphics.RenderEffect")
        from java.lang import UnsupportedOperationException
        with self.assertRaises(UnsupportedOperationException) as caught:
            self.view.setRenderEffect(effect.createOffsetEffect(1.0, 2.0))
        self.assertIn("offset", str(caught.exception))
        self.assertEqual(self.blur_ops(), [])

    def test_a_negative_radius_is_refused(self):
        effect = jclass("android.graphics.RenderEffect")
        from java.lang import IllegalArgumentException
        with self.assertRaises(IllegalArgumentException):
            effect.createBlurEffect(-1.0, 1.0, jclass("android.graphics.Shader").TileMode.CLAMP)


if __name__ == "__main__":
    unittest.main()
