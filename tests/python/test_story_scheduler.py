"""the story scheduler plugin on the shims: the button it puts beside publish, the wheel of the app for the time, the story it holds back from the screen of the
app and publishes later through the account operation story_post. the real plugin runs when EXTERIA_STORY_SCHEDULER names the file; the audience is a number the
app holds, as in exteria_plugin_story.m"""

import json
import os
import shutil
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from extera_utils import plugin_loader  # noqa: E402

SCHEDULER = os.environ.get("EXTERIA_STORY_SCHEDULER")
PLUGINS = None
_saved = {}


def setUpModule():
    global PLUGINS
    PLUGINS = tempfile.mkdtemp(prefix="exteria-stories-")
    _saved["dir"] = fake.plugins_dir
    _saved["cached"] = plugin_loader._plugins_dir_cached
    fake.plugins_dir = PLUGINS
    plugin_loader._plugins_dir_cached = None
    exteria_host._elyx_libraries()


def tearDownModule():
    fake.plugins_dir = _saved["dir"]
    plugin_loader._plugins_dir_cached = _saved["cached"]
    shutil.rmtree(PLUGINS, ignore_errors=True)


_waiting = []


def wait(until, seconds=6):
    """what the plugin posts to the main thread (run_on_ui_thread) runs here when its delay is up, as the main thread of the app runs it, and so do the answers of
    the app to a post"""
    end = time.time() + seconds
    while time.time() < end:
        now = time.time()
        while fake.timers:
            token, delay = fake.timers.pop(0)
            _waiting.append((now + delay / 1000.0, token))
        due = sorted(item for item in _waiting if item[0] <= now)
        _waiting[:] = [item for item in _waiting if item[0] > now]
        for _when, token in due:
            exteria_host.run_token(token)
        fakeapp.deliver()
        if until():
            return True
        time.sleep(0.005)
    return False


@unittest.skipUnless(SCHEDULER, "set EXTERIA_STORY_SCHEDULER to the story_scheduler .plugin")
class Scheduler(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fake.language = "en"
        cls.path = os.path.join(PLUGINS, "story_scheduler.plugin")
        shutil.copy(SCHEDULER, cls.path)
        result = exteria_host.load(cls.path, "story_scheduler")
        assert result["ok"], result
        cls.plugin = plugin_loader.plugins["story_scheduler"].instance

    @classmethod
    def tearDownClass(cls):
        exteria_host.unload("story_scheduler")

    def setUp(self):
        fake.time_picks.clear()
        fake.story_presses = 0
        fake.story_forgotten.clear()
        fake.saved.pop("stories", None)
        self.plugin._pending_time = None
        self.dir = tempfile.mkdtemp(prefix="exteria-story-files-")
        exteria_host.story_page()

    def tearDown(self):
        self.plugin._clear_all()
        shutil.rmtree(self.dir, ignore_errors=True)

    def picture(self, name="shot.jpg"):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as handle:
            handle.write(b"\xff\xd8jpeg")
        return path

    def choose(self, seconds_from_now):
        """the person picks a time on the wheel"""
        self.assertEqual(len(fake.time_picks), 1)
        token = fake.time_picks.pop()["token"]
        exteria_host.time_picked(token, [int(time.time()) + seconds_from_now, 2030, 1, 1, 12, 0])

    def test_the_page_offers_a_button_with_the_words_of_the_plugin(self):
        self.assertEqual(exteria_host.story_page(), {"title": "Schedule for later"})
        fake.language = "ru"
        exteria_host.language_changed()
        try:
            self.assertEqual(exteria_host.story_page(), {"title": "Отложить публикацию"})
        finally:
            fake.language = "en"
            exteria_host.language_changed()

    def test_a_story_that_was_not_scheduled_is_left_to_the_app(self):
        path = self.picture()
        self.assertEqual(exteria_host.story_intercept(path, "hi", 7), {"taken": False, "keep": False})
        # the app publishes the file and deletes it itself, and holds the audience until then
        self.assertTrue(os.path.exists(path))
        self.assertEqual(self.plugin._items(), [])
        exteria_host.story_page()
        self.assertEqual(fake.story_forgotten, [])

    def test_the_button_opens_the_wheel_and_the_choice_presses_publish_and_holds_the_story(self):
        exteria_host.story_schedule(False)
        self.assertEqual([(p["mode"]) for p in fake.time_picks], ["datetime"])
        self.assertGreater(fake.time_picks[0]["minimum"], time.time())
        self.choose(3600)
        self.assertTrue(wait(lambda: fake.story_presses == 1))
        path = self.picture()
        self.assertEqual(exteria_host.story_intercept(path, "caption", 9), {"taken": True, "keep": True})
        [item] = self.plugin._items()
        self.assertEqual((item["caption"], item["status"], item["is_video"], item["peer_title"]), ("caption", "pending", False, "My profile"))
        self.assertTrue(os.path.isfile(item["media_path"]))
        self.assertTrue(item["media_path"].startswith(os.path.join(PLUGINS, "story_scheduler", "media")))
        self.assertTrue(os.path.exists(path))
        self.assertNotIn("stories", fake.saved)

    def test_a_time_that_has_passed_is_refused(self):
        exteria_host.story_schedule(False)
        fake.calls.clear()
        self.choose(-10)
        self.assertTrue(wait(lambda: any(c[0] == "ui.toast" and "future" in c[1]["text"] for c in fake.calls)))
        self.assertEqual(fake.story_presses, 0)

    def test_cancelling_the_wheel_does_nothing(self):
        exteria_host.story_schedule(False)
        exteria_host.time_picked(fake.time_picks.pop()["token"], None)
        time.sleep(0.05)
        self.assertEqual(fake.story_presses, 0)
        self.assertEqual(self.plugin._items(), [])

    def test_holding_publish_opens_the_same_wheel(self):
        exteria_host.story_schedule(True)
        self.assertEqual(len(fake.time_picks), 1)

    def hold(self, path, token, caption="later"):
        exteria_host.story_schedule(False)
        self.choose(3600)
        self.assertTrue(wait(lambda: fake.story_presses >= 1))
        return exteria_host.story_intercept(path, caption, token)

    def test_a_due_story_goes_up_with_its_file_caption_and_audience_and_the_file_goes_after(self):
        path = self.picture()
        self.assertTrue(self.hold(path, 12)["taken"])
        [item] = self.plugin._items()
        self.plugin._mutate(lambda queue: queue[0].update(scheduled_at=int(time.time()) - 1))
        self.plugin._publish_story(item["id"])
        self.assertTrue(wait(lambda: fake.saved.get("stories")))
        [post] = fake.saved["stories"]
        self.assertEqual((post["path"], post["caption"], post["audience"]), (path, "later", 12))
        self.assertTrue(wait(lambda: not os.path.exists(path)))
        self.assertTrue(wait(lambda: not self.plugin._items()))

    def test_a_story_the_server_refused_tells_the_person_and_the_file_still_goes(self):
        path = self.picture()
        self.hold(path, 3)
        [item] = self.plugin._items()
        fake.saved["errors"]["story_post"] = "STORY_PERIOD_INVALID"
        before = len([c for c in fake.saved["calls"] if c[0] == "story_post"])
        try:
            self.plugin._publish_story(item["id"])
            self.assertTrue(wait(lambda: len([c for c in fake.saved["calls"] if c[0] == "story_post"]) > before))
            self.assertTrue(wait(lambda: not os.path.exists(path)))
            self.assertTrue(any(c[0] == "ui.toast" for c in fake.calls))
        finally:
            del fake.saved["errors"]["story_post"]

    def test_a_story_removed_from_the_queue_frees_its_audience_and_its_file(self):
        path = self.picture()
        self.hold(path, 21)
        [item] = self.plugin._items()
        self.plugin._remove_story(item["id"])
        exteria_host.story_page()
        self.assertTrue(wait(lambda: 21 in fake.story_forgotten))
        self.assertFalse(os.path.exists(path))
        self.assertFalse(os.path.exists(item["media_path"]))

    def test_a_story_restored_after_a_restart_goes_to_everyone_and_a_video_is_refused(self):
        media = os.path.join(PLUGINS, "story_scheduler", "media", "old.jpg")
        with open(media, "wb") as handle:
            handle.write(b"x")
        video = os.path.join(PLUGINS, "story_scheduler", "media", "old.mp4")
        with open(video, "wb") as handle:
            handle.write(b"x")
        now = int(time.time())
        base = {"scheduled_at": now - 5, "created_at": now, "account": 0, "peer_id": 0, "peer_title": "x", "caption": "back", "pinned": True, "period": 86400,
                "status": "pending", "attempts": 0}
        self.plugin._mutate(lambda queue: queue.extend([dict(base, id="photo", media_path=media, is_video=False), dict(base, id="clip", media_path=video, is_video=True)]))
        self.plugin._publish_story("photo")
        self.assertTrue(wait(lambda: fake.saved.get("stories")))
        self.assertEqual((fake.saved["stories"][0]["audience"], fake.saved["stories"][0]["caption"]), (0, "back"))
        self.plugin._publish_story("clip")
        self.assertTrue(wait(lambda: any(i["id"] == "clip" and i["attempts"] == 1 for i in self.plugin._items())))
        self.assertEqual(len(fake.saved["stories"]), 1)

    def test_the_drawer_item_opens_the_list_and_a_card_for_each_story(self):
        path = self.picture()
        self.hold(path, 4)
        fake.ops.clear()
        [row] = [item for item in fake.menu if item["menu_type"] == "DRAWER_MENU"]
        self.assertEqual(row["text"], "Scheduled stories")
        self.plugin._show_stories_sheet()
        from android import _ui
        _ui.flush()
        texts = [op[2].get("text") for op in fake.ops if op[0] == "set" and isinstance(op[2], dict)]
        self.assertTrue(any(t == "Scheduled stories" for t in texts))
        self.assertTrue(any(t == "Publish" for t in texts))
        self.assertTrue(any(t == "Delete" for t in texts))
        self.plugin._dismiss_sheet()

    def test_the_settings_page_counts_the_queue(self):
        path = self.picture()
        self.hold(path, 5)
        rows = exteria_host.settings("story_scheduler")
        self.assertIn("Scheduled: 1 story", [row.get("subtext") for row in rows])


class Shims(unittest.TestCase):
    """the classes a plugin that schedules stories asks for, without the plugin"""

    def test_the_date_and_time_dialogs_report_the_parts_of_the_phone_calendar(self):
        from android.app import DatePickerDialog, TimePickerDialog
        got = []

        class OnDate(DatePickerDialog.OnDateSetListener):
            def onDateSet(self, view, year, month, day):
                got.append(("date", year, month, day))

        class OnTime(TimePickerDialog.OnTimeSetListener):
            def onTimeSet(self, view, hour, minute):
                got.append(("time", hour, minute))

        fake.time_picks.clear()
        dialog = DatePickerDialog(None, OnDate(), 2030, 0, 5)
        dialog.getDatePicker().setMinDate(1000)
        dialog.show()
        [ask] = fake.time_picks
        self.assertEqual((ask["mode"], ask["initial"], ask["minimum"]), ("date", [2030, 1, 5, 0, 0], 1.0))
        exteria_host.time_picked(ask["token"], [0, 2031, 3, 9, 0, 0])
        fake.time_picks.clear()
        TimePickerDialog(None, OnTime(), 7, 30, True).show()
        [ask] = fake.time_picks
        self.assertEqual((ask["mode"], ask["initial"][3:]), ("time", [7, 30]))
        exteria_host.time_picked(ask["token"], [0, 2000, 1, 1, 8, 45])
        cancelled = len(got)
        TimePickerDialog(None, OnTime(), 7, 30, True).show()
        exteria_host.time_picked(fake.time_picks[-1]["token"], None)
        self.assertEqual(got, [("date", 2031, 2, 9), ("time", 8, 45)])
        self.assertEqual(len(got), cancelled)

    def test_a_video_frame_is_refused_by_name(self):
        from android.media import MediaMetadataRetriever
        retriever = MediaMetadataRetriever()
        with self.assertRaises(NotImplementedError):
            retriever.setDataSource("/x.mp4")
        retriever.release()


if __name__ == "__main__":
    unittest.main()
