import plistlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from tools import make_assets


class AppIconTests(unittest.TestCase):
    def assert_launcher_icon(self, path, side=None, rounded=False):
        with Image.open(path) as icon:
            self.assertEqual(icon.format, "PNG")
            self.assertEqual(icon.mode, "RGBA" if rounded else "RGB", str(path))
            if rounded:
                self.assertEqual(icon.getpixel((0, 0))[3], 0, str(path))
                self.assertEqual(icon.getpixel((icon.width // 2, icon.height // 2))[3], 255, str(path))
            else:
                self.assertNotIn("transparency", icon.info, str(path))
            self.assertEqual(icon.width, icon.height, str(path))
            if side is not None:
                self.assertEqual(icon.size, (side, side), str(path))

    def test_primary_generator_rounds_legacy_sizes(self):
        rgb = np.full((make_assets.MASTER, make_assets.MASTER, 3), (41, 79, 113), dtype=np.uint8)
        with tempfile.TemporaryDirectory() as directory:
            make_assets.build_icons(rgb, directory)
            for name, side in make_assets.APP_ICONS.items():
                with self.subTest(name=name):
                    path = Path(directory) / name
                    rounded = side in make_assets.LEGACY_ICON_SIDES
                    self.assert_launcher_icon(path, side, rounded)
                    with Image.open(path) as icon:
                        self.assertEqual(icon.getpixel((side // 2, side // 2))[:3], (41, 79, 113))

    def test_alternate_generator_rounds_legacy_sizes(self):
        with tempfile.TemporaryDirectory() as directory:
            res = Path(directory) / "res"
            (res / "drawable").mkdir(parents=True)
            (res / "drawable-xxxhdpi").mkdir()
            for name in make_assets.ALTERNATE_ICONS:
                (res / "drawable" / (name + "_icon_background.xml")).write_text(
                    '<vector xmlns:android="http://schemas.android.com/apk/res/android">'
                    '<path android:fillColor="#294f71"/></vector>'
                )
                Image.new("RGBA", (48, 48), (200, 100, 80, 128)).save(
                    res / "drawable-xxxhdpi" / (name + "_icon_foreground.png")
                )
            out = Path(directory) / "icons"
            make_assets.build_alternate_icons(str(res), str(out))
            for name in make_assets.ALTERNATE_ICONS:
                for suffix, side in make_assets.ALTERNATE_ICON_SIZES:
                    with self.subTest(name=name, suffix=suffix):
                        self.assert_launcher_icon(out / (name.capitalize() + suffix + ".png"), side, side in make_assets.LEGACY_ICON_SIDES)

    def test_primary_icon_is_prerendered(self):
        root = Path(make_assets.ROOT)
        with (root / "packaging/Info.plist").open("rb") as handle:
            plist = plistlib.load(handle)
        # the 57, 114, 72 and 144 files carry their own corners; springboard of ios 5 and 6 masks an icon not marked pre-rendered, and the mask is
        # missing for an app installed from an ipa, which left a square icon
        self.assertTrue(plist["UIPrerenderedIcon"])
        for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            self.assertTrue(plist[key]["CFBundlePrimaryIcon"]["UIPrerenderedIcon"])

    def test_senkogram_generator(self):
        source = Path(make_assets.ROOT) / "resources/icons/source/senkogram.png"
        with tempfile.TemporaryDirectory() as directory:
            make_assets.build_senkogram_icons(source, directory)
            for suffix, side in make_assets.ALTERNATE_ICON_SIZES:
                self.assert_launcher_icon(Path(directory) / ("SenkoGram" + suffix + ".png"), side, side in make_assets.LEGACY_ICON_SIDES)
            for suffix, side in make_assets.SPLASH_SIDES:
                self.assert_launcher_icon(Path(directory) / ("splash_senkogram" + suffix + ".png"), side, True)

    def test_telegram_generator(self):
        source = Path(make_assets.ROOT) / "resources/icons/source/telegram.png"
        with tempfile.TemporaryDirectory() as directory:
            make_assets.build_image_icons(source, "Telegram", directory)
            for suffix, side in make_assets.ALTERNATE_ICON_SIZES:
                self.assert_launcher_icon(Path(directory) / ("Telegram" + suffix + ".png"), side, side in make_assets.LEGACY_ICON_SIDES)
            for suffix, side in make_assets.SPLASH_SIDES:
                self.assert_launcher_icon(Path(directory) / ("splash_telegram" + suffix + ".png"), side, True)

    def test_every_plist_icon_has_expected_shape(self):
        root = Path(make_assets.ROOT)
        with (root / "packaging/Info.plist").open("rb") as handle:
            plist = plistlib.load(handle)

        def icon_files(entry):
            if isinstance(entry, dict):
                for key, value in entry.items():
                    if key == "CFBundleIconFiles":
                        yield from value
                    else:
                        yield from icon_files(value)

        names = set(icon_files(plist))
        self.assertTrue(names)
        for name in sorted(names):
            with self.subTest(name=name):
                path = root / "resources/icons" / name
                with Image.open(path) as icon:
                    rounded = icon.width in make_assets.LEGACY_ICON_SIDES
                self.assert_launcher_icon(path, rounded=rounded)


if __name__ == "__main__":
    unittest.main()
