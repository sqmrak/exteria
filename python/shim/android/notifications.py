"""notifications and alarms of android.app, made for ios

a notification is a notice of the app: on screen the banner of the app shows it, off screen the system notification center. what android does
with a notification that ios has no part of is stated here and not hidden: a content intent opens the app and nothing else, a notice cannot
be taken back from the screen before ios 10, and an alarm runs while the app runs

an alarm is a timer in the app (AlarmManager.OnAlarmListener). ios stops a sleeping app, so an alarm that falls due meanwhile runs when the app
is awake again, late; the app is kept awake in the background only as long as its notifications are on. that is the difference a plugin that
wants a notice at an exact time feels, and the one thing it cannot be given"""

import time

from android import _ui
from java.lang import IllegalArgumentException, IllegalStateException, NullPointerException, Object, UnsupportedOperationException

NOTICE_KEY_MAX = 128
ALARMS_MAX = 500
_PUMP_MS = 30000


class Notification(Object):
    CATEGORY_MESSAGE = "msg"
    CATEGORY_REMINDER = "reminder"
    CATEGORY_ALARM = "alarm"
    CATEGORY_EVENT = "event"
    CATEGORY_STATUS = "status"
    CATEGORY_PROGRESS = "progress"
    CATEGORY_SERVICE = "service"
    CATEGORY_CALL = "call"
    PRIORITY_MIN = -2
    PRIORITY_LOW = -1
    PRIORITY_DEFAULT = 0
    PRIORITY_HIGH = 1
    PRIORITY_MAX = 2
    FLAG_AUTO_CANCEL = 0x10
    DEFAULT_ALL = -1

    def __init__(self):
        self.channel_id = None
        self.title = None
        self.text = None
        self.big_text = None
        self.category = None
        self.priority = Notification.PRIORITY_DEFAULT
        self.auto_cancel = False
        self.contentIntent = None
        self.when = None
        self.icon = 0


class NotificationChannel(Object):
    def __init__(self, channel_id, name, importance):
        if channel_id is None:
            raise NullPointerException("id is null")
        if name is None:
            raise NullPointerException("name is null")
        self._id, self._name, self._importance = str(channel_id), str(name), int(importance)
        self._description = None

    def getId(self):
        return self._id

    def getName(self):
        return self._name

    def getImportance(self):
        return self._importance

    def setImportance(self, importance):
        self._importance = int(importance)

    def setDescription(self, text):
        self._description = None if text is None else str(text)

    def getDescription(self):
        return self._description

    def enableVibration(self, value):
        # the notice of the system makes its own sound and vibration, as the person set them for the app
        return None

    def enableLights(self, value):
        return None

    def setShowBadge(self, value):
        return None

    def setSound(self, uri, attributes):
        return None

    def setLockscreenVisibility(self, value):
        return None


class PendingIntent(Object):
    FLAG_ONE_SHOT = 0x40000000
    FLAG_NO_CREATE = 0x20000000
    FLAG_CANCEL_CURRENT = 0x10000000
    FLAG_UPDATE_CURRENT = 0x08000000
    FLAG_IMMUTABLE = 0x04000000
    FLAG_MUTABLE = 0x02000000

    def __init__(self, intent, flags):
        self._intent = intent
        self._flags = int(flags)

    @staticmethod
    def getActivity(context, request_code, intent, flags, *_options):
        if intent is None:
            raise NullPointerException("intent is null")
        return PendingIntent(intent, flags)

    getBroadcast = getService = getActivity

    def send(self, *_args):
        raise UnsupportedOperationException("an intent of the android client has no screen of the app to open, the notice opens the app itself")

    def cancel(self):
        return None


class NotificationManager(Object):
    IMPORTANCE_UNSPECIFIED = -1000
    IMPORTANCE_NONE = 0
    IMPORTANCE_MIN = 1
    IMPORTANCE_LOW = 2
    IMPORTANCE_DEFAULT = 3
    IMPORTANCE_HIGH = 4

    _instance = None

    @staticmethod
    def _get():
        if NotificationManager._instance is None:
            NotificationManager._instance = NotificationManager()
        return NotificationManager._instance

    def __init__(self):
        self._channels = {}

    def createNotificationChannel(self, channel):
        if channel is None:
            raise NullPointerException("channel is null")
        self._channels[channel.getId()] = channel

    def getNotificationChannel(self, channel_id):
        return self._channels.get(str(channel_id))

    def getNotificationChannels(self):
        from java.util import ArrayList
        return ArrayList(list(self._channels.values()))

    def deleteNotificationChannel(self, channel_id):
        self._channels.pop(str(channel_id), None)

    def areNotificationsEnabled(self):
        return bool((_ui.ask("app.notices_enabled") or {}).get("value"))

    @staticmethod
    def _key(tag, notice_id):
        key = "%s:%d" % (tag, int(notice_id)) if tag is not None else "%d" % int(notice_id)
        if len(key) > NOTICE_KEY_MAX:
            raise IllegalArgumentException("the tag of a notice is longer than %d characters" % NOTICE_KEY_MAX)
        return key

    def notify(self, *args):
        """notify(id, notification) and notify(tag, id, notification). a channel that was never created, as on android 8 and later, is an
        IllegalArgumentException; a channel with importance NONE is blocked and shows nothing"""
        if len(args) == 2:
            tag, notice_id, notification = None, args[0], args[1]
        elif len(args) == 3:
            tag, notice_id, notification = args
        else:
            raise TypeError("notify takes (id, notification) or (tag, id, notification)")
        if notification is None:
            raise NullPointerException("notification is null")
        if notification.channel_id is not None:
            channel = self._channels.get(notification.channel_id)
            if channel is None:
                raise IllegalArgumentException("no channel %r, create it with createNotificationChannel first" % (notification.channel_id,))
            if channel.getImportance() == NotificationManager.IMPORTANCE_NONE:
                return
        text = notification.big_text if notification.big_text is not None else notification.text
        try:
            _ui.ask("app.notice", key=self._key(tag, notice_id), title=notification.title or "", text=text or "")
        except RuntimeError as error:
            raise IllegalStateException(str(error)) from error

    def cancel(self, *args):
        """cancel(id) and cancel(tag, id): takes the notice off the screen where the system lets the app, from ios 10"""
        tag, notice_id = (None, args[0]) if len(args) == 1 else args
        _ui.ask("app.notice_cancel", key=self._key(tag, notice_id))

    def cancelAll(self):
        raise UnsupportedOperationException("the app takes back every notice itself when it opens, a plugin cannot list the ones it posted")


class AlarmManager(Object):
    RTC_WAKEUP = 0
    RTC = 1
    ELAPSED_REALTIME_WAKEUP = 2
    ELAPSED_REALTIME = 3

    class OnAlarmListener:
        """a program implements onAlarm()"""

    _instance = None

    @staticmethod
    def _get():
        if AlarmManager._instance is None:
            AlarmManager._instance = AlarmManager()
        return AlarmManager._instance

    def __init__(self):
        self._alarms = {}
        self._loop = 0
        self._armed_at = None

    def canScheduleExactAlarms(self):
        return True

    @staticmethod
    def _due_ms(kind, trigger):
        """the wall clock time in milliseconds the trigger means: RTC types name it, ELAPSED types count from the start of the phone"""
        kind, trigger = int(kind), int(trigger)
        if kind not in (0, 1, 2, 3):
            raise IllegalArgumentException("%d is not an alarm type" % kind)
        if kind in (2, 3):
            from android.os import SystemClock
            return int(time.time() * 1000) + (trigger - SystemClock.elapsedRealtime())
        return trigger

    def _set(self, kind, trigger, *rest):
        if len(rest) == 1:
            raise UnsupportedOperationException("an alarm that starts an activity, a service or a receiver has no equal here, use the form with a listener")
        if len(rest) != 3:
            raise TypeError("an alarm takes (type, trigger, tag, listener, handler)")
        tag, listener, handler = rest
        if listener is None:
            raise NullPointerException("listener is null")
        if listener not in self._alarms and len(self._alarms) >= ALARMS_MAX:
            raise IllegalStateException("more than %d alarms are waiting" % ALARMS_MAX)
        self._alarms[listener] = (self._due_ms(kind, trigger), tag, handler)
        self._pump()

    set = setExact = setAndAllowWhileIdle = setExactAndAllowWhileIdle = _set

    def setWindow(self, kind, start, length, *rest):
        self._set(kind, start, *rest)

    def cancel(self, target):
        """cancel(listener). a PendingIntent was never set, so there is nothing of it to cancel"""
        self._alarms.pop(target, None)

    def _pump(self):
        """one timer for every alarm: it wakes at the nearest one, or every half minute (the app takes a delay of a minute at most). a timer
        that already waits for the same time or an earlier one is kept, so setting a later alarm adds no timer"""
        if not self._alarms:
            return
        now = int(time.time() * 1000)
        wait = max(0, min(min(when for when, _t, _h in self._alarms.values()) - now, _PUMP_MS))
        if self._armed_at is not None and self._armed_at <= now + wait:
            return
        self._loop += 1
        loop = self._loop
        self._armed_at = now + wait
        from android.os import Handler

        class Step:
            def run(step):
                self._wake(loop)

        Handler().postDelayed(Step(), wait)

    def _wake(self, loop):
        if loop != self._loop:
            return
        self._armed_at = None
        now = int(time.time() * 1000)
        due = sorted(((when, listener, handler) for listener, (when, _tag, handler) in self._alarms.items() if when <= now), key=lambda row: row[0])
        for _when, listener, _handler in due:
            del self._alarms[listener]
        # the timer is set again before any listener runs, and each listener runs in a task of its own: one that fails is logged by the app and
        # neither stops the timer nor keeps the others from running
        self._pump()
        for _when, listener, handler in due:
            self._fire(listener, handler)

    @staticmethod
    def _fire(listener, handler):
        from android.os import Handler
        method = getattr(listener, "onAlarm", None)
        if method is None:
            raise IllegalStateException("%r has no onAlarm" % (listener,))

        class Run:
            def run(self):
                method()

        (handler if handler is not None else Handler()).post(Run())
