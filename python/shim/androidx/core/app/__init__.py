"""androidx.core.app: the builder of notifications"""

from android.notifications import Notification
from java.lang import NullPointerException, Object


class NotificationCompat(Object):
    PRIORITY_MIN = Notification.PRIORITY_MIN
    PRIORITY_LOW = Notification.PRIORITY_LOW
    PRIORITY_DEFAULT = Notification.PRIORITY_DEFAULT
    PRIORITY_HIGH = Notification.PRIORITY_HIGH
    PRIORITY_MAX = Notification.PRIORITY_MAX
    CATEGORY_MESSAGE = Notification.CATEGORY_MESSAGE
    CATEGORY_REMINDER = Notification.CATEGORY_REMINDER
    CATEGORY_ALARM = Notification.CATEGORY_ALARM
    CATEGORY_EVENT = Notification.CATEGORY_EVENT
    CATEGORY_STATUS = Notification.CATEGORY_STATUS
    CATEGORY_PROGRESS = Notification.CATEGORY_PROGRESS
    CATEGORY_SERVICE = Notification.CATEGORY_SERVICE
    CATEGORY_CALL = Notification.CATEGORY_CALL
    DEFAULT_ALL = Notification.DEFAULT_ALL

    class Style(Object):
        pass

    class BigTextStyle(Style):
        def __init__(self):
            self._big = None

        def bigText(self, text):
            self._big = None if text is None else str(text)
            return self

    class Builder(Object):
        """Builder(context, channel_id). the calls that only dress the notice on android (icons, colors, vibration, lights, progress, actions)
        are accepted and leave the notice as the system draws it: a title and a text"""

        def __init__(self, context, channel_id=None):
            self._n = Notification()
            self._n.channel_id = None if channel_id is None else str(channel_id)

        def setContentTitle(self, text):
            self._n.title = None if text is None else str(text)
            return self

        def setContentText(self, text):
            self._n.text = None if text is None else str(text)
            return self

        def setStyle(self, style):
            if style is not None and hasattr(style, "_big"):
                self._n.big_text = style._big
            return self

        def setCategory(self, category):
            self._n.category = category
            return self

        def setPriority(self, priority):
            self._n.priority = int(priority)
            return self

        def setAutoCancel(self, value):
            self._n.auto_cancel = bool(value)
            return self

        def setContentIntent(self, intent):
            self._n.contentIntent = intent
            return self

        def setWhen(self, when):
            self._n.when = int(when)
            return self

        def setSmallIcon(self, icon, *_level):
            self._n.icon = icon if isinstance(icon, int) else 0
            return self

        def _dress(self, *_args, **_kwargs):
            return self

        setColor = setLargeIcon = setDefaults = setVibrate = setLights = setSound = setOnlyAlertOnce = setShowWhen = setOngoing = _dress
        setVisibility = setSubText = setTicker = setGroup = setProgress = setTimeoutAfter = setColorized = setLocalOnly = _dress

        def build(self):
            if self._n.title is None and self._n.text is None:
                raise NullPointerException("a notification needs a title or a text")
            return self._n
