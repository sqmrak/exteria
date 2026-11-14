"""notices and alarms for ios: the notification classes of android.app that post through the app, and an alarm manager that is a timer of the app"""

import os
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import fakeapp  # noqa: E402

fake = fakeapp.fake
sys.path[:0] = [os.path.join(ROOT, "python", "shim"), os.path.join(ROOT, "third_party", "exteraless")]

import exteria_host  # noqa: E402
from android import notifications  # noqa: E402
from android.app import AlarmManager, Notification, NotificationChannel, NotificationManager, PendingIntent, activity  # noqa: E402
from android.content import Context, Intent  # noqa: E402
from androidx.core.app import NotificationCompat  # noqa: E402
from java import jclass  # noqa: E402
from java.lang import IllegalArgumentException, IllegalStateException, NullPointerException, UnsupportedOperationException  # noqa: E402


def builder(channel="c", title="Title", text="Body"):
    return NotificationCompat.Builder(activity(), channel).setContentTitle(title).setContentText(text)


class Notices(unittest.TestCase):
    def setUp(self):
        fake.notices.clear()
        fake.notices_cancelled.clear()
        fake.notices_on = True
        self.manager = activity().getSystemService(Context.NOTIFICATION_SERVICE)
        self.manager._channels.clear()
        self.manager.createNotificationChannel(NotificationChannel("c", "Reminders", NotificationManager.IMPORTANCE_HIGH))

    def test_the_service_is_the_notification_manager(self):
        self.assertIsInstance(self.manager, NotificationManager)
        self.assertIs(activity().getSystemService("notification"), self.manager)

    def test_a_notice_reaches_the_app_with_its_title_and_text(self):
        self.manager.notify(7, builder().build())
        self.assertEqual(fake.notices, [("7", "Title", "Body")])

    def test_the_big_text_replaces_the_text_and_a_tag_joins_the_key(self):
        note = builder().setStyle(NotificationCompat.BigTextStyle().bigText("long text")).build()
        self.manager.notify("remind", 3, note)
        self.assertEqual(fake.notices, [("remind:3", "Title", "long text")])

    def test_the_builder_keeps_what_it_is_given_and_accepts_the_dressing_calls(self):
        pending = PendingIntent.getActivity(activity(), 1, Intent(), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE)
        note = (builder().setCategory(Notification.CATEGORY_REMINDER).setPriority(Notification.PRIORITY_HIGH).setAutoCancel(True)
                .setContentIntent(pending).setSmallIcon(17).setColor(0xFF0000).setOnlyAlertOnce(True).setWhen(5).build())
        self.assertEqual((note.category, note.priority, note.auto_cancel, note.contentIntent, note.icon, note.when),
                         ("reminder", 1, True, pending, 17, 5))

    def test_a_notification_without_words_is_refused(self):
        with self.assertRaises(NullPointerException):
            NotificationCompat.Builder(activity(), "c").build()

    def test_a_channel_that_was_never_created_is_refused(self):
        with self.assertRaises(IllegalArgumentException):
            self.manager.notify(1, builder(channel="missing").build())
        self.assertEqual(fake.notices, [])

    def test_a_blocked_channel_shows_nothing(self):
        self.manager.createNotificationChannel(NotificationChannel("c", "Reminders", NotificationManager.IMPORTANCE_NONE))
        self.manager.notify(1, builder().build())
        self.assertEqual(fake.notices, [])

    def test_channels_are_kept_and_read_back(self):
        channel = self.manager.getNotificationChannel("c")
        channel.setDescription("about")
        channel.enableVibration(True)
        self.assertEqual((channel.getName(), channel.getImportance(), channel.getDescription()), ("Reminders", 4, "about"))
        self.assertEqual(self.manager.getNotificationChannels().size(), 1)
        self.manager.deleteNotificationChannel("c")
        self.assertIsNone(self.manager.getNotificationChannel("c"))
        with self.assertRaises(NullPointerException):
            NotificationChannel(None, "x", 3)

    def test_notices_switched_off_in_the_app_are_an_illegal_state(self):
        fake.notices_on = False
        self.assertFalse(self.manager.areNotificationsEnabled())
        with self.assertRaises(IllegalStateException):
            self.manager.notify(1, builder().build())
        fake.notices_on = True
        self.assertTrue(self.manager.areNotificationsEnabled())

    def test_cancel_goes_to_the_app_and_cancel_all_is_refused(self):
        self.manager.cancel(7)
        self.manager.cancel("t", 8)
        self.assertEqual(fake.notices_cancelled, ["7", "t:8"])
        with self.assertRaises(UnsupportedOperationException):
            self.manager.cancelAll()

    def test_a_tag_that_is_too_long_is_refused(self):
        with self.assertRaises(IllegalArgumentException):
            self.manager.notify("x" * 200, 1, builder().build())

    def test_a_pending_intent_cannot_be_sent(self):
        with self.assertRaises(UnsupportedOperationException):
            PendingIntent.getActivity(activity(), 0, Intent(), 0).send()
        with self.assertRaises(NullPointerException):
            PendingIntent.getActivity(activity(), 0, None, 0)

    def test_the_classes_resolve_by_their_java_names(self):
        for name in ("android.app.NotificationManager", "android.app.PendingIntent", "androidx.core.app.NotificationCompat",
                     "android.app.AlarmManager", "android.app.Notification", "android.app.NotificationChannel"):
            self.assertIsNotNone(jclass(name), name)


class Clock:
    """a clock the test sets, and the timers of the fake app run in the order of the time they fall due"""

    def __init__(self):
        self.now = 1_000_000_000.0

    def time(self):
        return self.now / 1000.0


class Alarms(unittest.TestCase):
    def setUp(self):
        fake.timers.clear()
        self.clock = Clock()
        self.saved = notifications.time
        notifications.time = types.SimpleNamespace(time=self.clock.time)
        self.manager = activity().getSystemService(Context.ALARM_SERVICE)
        self.manager._alarms.clear()
        self.manager._loop += 1
        self.manager._armed_at = None
        self.log = []

    def tearDown(self):
        notifications.time = self.saved
        self.manager._alarms.clear()
        self.manager._loop += 1
        self.manager._armed_at = None
        fake.timers.clear()

    def listener(self, name):
        log = self.log

        class On(AlarmManager.OnAlarmListener):
            def onAlarm(self):
                log.append(name)

        return On()

    def advance(self, until_ms):
        """runs the timers that fall due up to the time, moving the clock to each"""
        pending = [(self.clock.now + delay, n, token) for n, (token, delay) in enumerate(fake.timers)]
        fake.timers.clear()
        serial = len(pending)
        while pending:
            pending.sort()
            due, _n, token = pending[0]
            if due > until_ms:
                break
            pending.pop(0)
            self.clock.now = max(self.clock.now, due)
            exteria_host.run_token(token)
            for token, delay in fake.timers:
                serial += 1
                pending.append((self.clock.now + delay, serial, token))
            fake.timers.clear()
        self.clock.now = max(self.clock.now, until_ms)
        for token, delay in [(t, d) for _d, _n, t in pending for d in (0,)]:
            fake.timers.append((token, delay))

    def test_the_service_is_the_alarm_manager(self):
        self.assertIsInstance(self.manager, AlarmManager)
        self.assertTrue(self.manager.canScheduleExactAlarms())

    def test_an_alarm_runs_at_its_time_and_not_before(self):
        self.manager.setExact(AlarmManager.RTC_WAKEUP, int(self.clock.now) + 5000, "t", self.listener("a"), None)
        self.advance(self.clock.now + 4999)
        self.assertEqual(self.log, [])
        self.advance(self.clock.now + 2)
        self.assertEqual(self.log, ["a"])

    def test_a_long_wait_is_made_of_short_ones(self):
        self.manager.set(AlarmManager.RTC, int(self.clock.now) + 95000, "t", self.listener("a"), None)
        delays = [delay for _token, delay in fake.timers]
        self.assertEqual(delays, [30000])
        self.advance(self.clock.now + 94000)
        self.assertEqual(self.log, [])
        self.advance(self.clock.now + 2000)
        self.assertEqual(self.log, ["a"])

    def test_alarms_run_in_the_order_of_their_time_and_a_later_one_adds_no_timer(self):
        self.manager.setExact(0, int(self.clock.now) + 1000, "t", self.listener("early"), None)
        self.manager.setExact(0, int(self.clock.now) + 3000, "t", self.listener("late"), None)
        self.assertEqual(len(fake.timers), 1)
        self.advance(self.clock.now + 5000)
        self.assertEqual(self.log, ["early", "late"])

    def test_an_earlier_alarm_set_later_runs_first(self):
        self.manager.setExact(0, int(self.clock.now) + 3000, "t", self.listener("late"), None)
        self.manager.setExact(0, int(self.clock.now) + 1000, "t", self.listener("early"), None)
        self.advance(self.clock.now + 5000)
        self.assertEqual(self.log, ["early", "late"])

    def test_cancel_and_a_second_set_of_the_same_listener(self):
        first = self.listener("first")
        self.manager.setExact(0, int(self.clock.now) + 1000, "t", first, None)
        self.manager.cancel(first)
        self.advance(self.clock.now + 3000)
        self.assertEqual(self.log, [])
        second = self.listener("second")
        self.manager.setExact(0, int(self.clock.now) + 1000, "t", second, None)
        self.manager.setExact(0, int(self.clock.now) + 2000, "t", second, None)
        self.advance(self.clock.now + 1500)
        self.assertEqual(self.log, [])
        self.advance(self.clock.now + 1000)
        self.assertEqual(self.log, ["second"])

    def test_an_alarm_that_fell_due_while_the_app_slept_runs_when_it_wakes(self):
        self.manager.setExact(0, int(self.clock.now) + 5000, "t", self.listener("a"), None)
        token, _delay = fake.timers.pop(0)
        self.clock.now += 3_600_000
        exteria_host.run_token(token)
        self.advance(self.clock.now)
        self.assertEqual(self.log, ["a"])
        self.assertEqual(fake.timers, [])

    def test_a_listener_that_fails_does_not_stop_the_others(self):
        class Broken(AlarmManager.OnAlarmListener):
            def onAlarm(self):
                raise RuntimeError("plugin bug")

        self.manager.setExact(0, int(self.clock.now) + 1000, "t", Broken(), None)
        self.manager.setExact(0, int(self.clock.now) + 1000, "t", self.listener("ok"), None)
        self.manager.setExact(0, int(self.clock.now) + 90000, "t", self.listener("later"), None)
        saved, sys.stderr = sys.stderr, open(os.devnull, "w")
        try:
            self.advance(self.clock.now + 2000)
        finally:
            sys.stderr.close()
            sys.stderr = saved
        self.assertEqual(self.log, ["ok"])
        self.assertEqual(len(self.manager._alarms), 1)
        self.advance(self.clock.now + 100000)
        self.assertEqual(self.log, ["ok", "later"])

    def test_the_handler_a_plugin_names_runs_the_alarm(self):
        from android.os import Handler
        posted = []

        class Mine(Handler):
            def post(self, runnable):
                posted.append("post")
                return super().post(runnable)

        self.manager.setExact(0, int(self.clock.now) + 100, "t", self.listener("a"), Mine())
        self.advance(self.clock.now + 1000)
        self.assertEqual((self.log, posted), (["a"], ["post"]))

    def test_the_elapsed_types_count_from_the_start_of_the_phone(self):
        from android.os import SystemClock
        self.manager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + 4000, "t", self.listener("a"), None)
        due = list(self.manager._alarms.values())[0][0]
        self.assertAlmostEqual(due - int(self.clock.now), 4000, delta=50)

    def test_the_forms_that_cannot_work_are_refused_by_name(self):
        with self.assertRaises(UnsupportedOperationException):
            self.manager.setExact(0, 1, PendingIntent.getActivity(activity(), 0, Intent(), 0))
        with self.assertRaises(NullPointerException):
            self.manager.setExact(0, 1, "t", None, None)
        with self.assertRaises(IllegalArgumentException):
            self.manager.setExact(9, 1, "t", self.listener("a"), None)
        with self.assertRaises(TypeError):
            self.manager.setExact(0, 1, "t", self.listener("a"))

    def test_the_number_of_waiting_alarms_is_bounded(self):
        for index in range(notifications.ALARMS_MAX):
            self.manager._alarms[object()] = (int(self.clock.now) + 10 ** 9, "t", None)
        with self.assertRaises(IllegalStateException):
            self.manager.setExact(0, int(self.clock.now) + 1, "t", self.listener("one too many"), None)
        self.assertEqual(len(self.manager._alarms), notifications.ALARMS_MAX)


if __name__ == "__main__":
    unittest.main()
