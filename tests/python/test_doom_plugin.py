import os
import shutil
import sys
import tempfile
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

# the engine is a c module in the app; here it is a recorder with the same calls
doom = types.ModuleType("_doom")
doom.WIDTH, doom.HEIGHT = 320, 200
doom.calls = []
doom.start_error = None


def start(wad, savedir):
    doom.calls.append(("start", wad, savedir))
    if doom.start_error:
        raise doom.start_error


doom.start = start
doom.key = lambda code, pressed: True
doom.error = lambda: "the engine stopped"
sys.modules["_doom"] = doom

import exteria_host  # noqa: E402


class DoomPlugin(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        fake.plugins_dir = self.dir
        shutil.copy(os.path.join(ROOT, "examples", "doom.plugin"), self.dir)
        self.path = os.path.join(self.dir, "doom.plugin")
        for store in (fake.ops, fake.timers, fake.sheets, fake.calls, fake.menu):
            del store[:]
        doom.calls[:] = []
        doom.start_error = None
        result = exteria_host.load(self.path, "doom")
        self.assertTrue(result["ok"], result)

    def tearDown(self):
        exteria_host.unload("doom")
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_timers(self):
        while fake.timers:
            token, delay = sorted(fake.timers, key=lambda t: t[1])[0]
            fake.timers.remove((token, delay))
            exteria_host.run_token(token)

    def sheet_calls(self, name):
        return [d for n, d in fake.calls if n == name]

    def open_from_menu(self):
        item_id = "item1"
        exteria_host.menu_click("doom", item_id, {})

    def test_metadata_and_permissions(self):
        meta = exteria_host.metadata(self.path)["meta"]
        self.assertEqual((meta["id"], meta["name"]), ("doom", "Doom"))
        self.assertIn("native", meta["permissions"])

    def test_the_menu_item_is_registered_for_the_plugins_page(self):
        self.assertEqual([item["text"] for item in fake.menu], ["Doom"])
        self.assertEqual(fake.menu[0]["menu_type"], "MAIN_MENU")

    def test_the_settings_page_has_a_play_button_that_opens_the_game(self):
        items = exteria_host.settings("doom")
        self.assertEqual([item["type"] for item in items], ["header", "text", "divider"])
        play = items[1]
        self.assertEqual(play["text"], "Играть")
        self.assertTrue(play["accent"] and play["callback_id"])
        exteria_host.setting_click("doom", play["callback_id"])
        self.assertEqual(len(fake.sheets), 1)

    def test_a_sheet_opens_at_once_and_the_game_starts_after_the_slide(self):
        self.open_from_menu()
        spec = fake.sheets[0]
        self.assertEqual((spec["title"], spec["surface"], spec["width"], spec["height"]), ("Doom", "doom", 320, 200))
        self.assertEqual([b["slot"] for b in spec["buttons"]], ["up", "left", "right", "down", "a", "b", "c", "t1", "t2", "t3"])
        self.assertEqual(spec["buttons"][4]["key"], 0xA3)
        # the arrows are shapes of the sheet, not characters, and the words are plain ascii that fits a key
        self.assertEqual([b.get("icon") for b in spec["buttons"][:4]], ["up", "left", "right", "down"])
        self.assertTrue(all(b["label"].isascii() for b in spec["buttons"] if "label" in b))
        self.assertEqual(doom.calls, [])
        self.assertEqual(self.sheet_calls("sheet.ready"), [])
        self.run_timers()
        wad = os.path.join(self.dir, ".data", "doom", "doom1.wad")
        self.assertEqual(doom.calls, [("start", wad, os.path.dirname(wad))])
        self.assertEqual(self.sheet_calls("sheet.ready"), [{"id": 1}])

    def test_a_second_tap_does_not_open_a_second_sheet(self):
        self.open_from_menu()
        self.open_from_menu()
        self.assertEqual(len(fake.sheets), 1)

    def test_a_closed_sheet_can_open_again_without_loading_twice(self):
        self.open_from_menu()
        self.run_timers()
        exteria_host.sheet_closed(1)
        self.open_from_menu()
        self.run_timers()
        self.assertEqual(len(fake.sheets), 2)
        self.assertEqual([c[0] for c in doom.calls], ["start"])
        self.assertEqual(len(self.sheet_calls("sheet.ready")), 2)

    def test_a_missing_wad_is_said_on_the_sheet_and_can_be_retried(self):
        doom.start_error = FileNotFoundError("cannot read")
        self.open_from_menu()
        self.run_timers()
        text = self.sheet_calls("sheet.fail")[0]["text"]
        self.assertIn("doom1.wad", text)
        self.assertEqual(self.sheet_calls("sheet.ready"), [])
        exteria_host.sheet_closed(1)
        doom.start_error = None
        self.open_from_menu()
        self.run_timers()
        self.assertEqual(len(self.sheet_calls("sheet.ready")), 1)

    def test_a_game_that_ended_puts_the_reason_on_the_sheet(self):
        self.open_from_menu()
        self.run_timers()
        exteria_host.sheet_ended(1)
        self.assertEqual(self.sheet_calls("sheet.fail")[-1]["text"], "the engine stopped")

    def test_unload_closes_the_sheet(self):
        self.open_from_menu()
        exteria_host.unload("doom")
        self.assertEqual(self.sheet_calls("sheet.close"), [{"id": 1}])


if __name__ == "__main__":
    unittest.main()
