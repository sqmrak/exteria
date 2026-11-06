"""android.app: the activity a plugin finds as LaunchActivity.instance. one object, kept for the life of the process"""

from android import _ui
from android.content import Context, Intent
from android.view import DecorView
from java.lang import Object


class Window:
    def __init__(self, activity):
        self._activity = activity

    def getDecorView(self):
        return self._activity._decor


class Activity(Context):
    RESULT_OK = -1
    RESULT_CANCELED = 0

    def __init__(self):
        self._decor = DecorView(self)
        self._window = Window(self)
        self._context = self

    def getWindow(self):
        return self._window

    def isFinishing(self):
        return False

    def isDestroyed(self):
        return False

    def getApplicationContext(self):
        return self

    def getSystemService(self, name):
        if name == Context.SENSOR_SERVICE:
            from android.hardware import SensorManager
            return SensorManager.instance()
        raise LookupError("system service %r is not available" % (name,))

    def startActivityForResult(self, intent, request_code, *_options):
        """the picker of pictures of the app is the one screen an intent opens: ACTION_OPEN_DOCUMENT, GET_CONTENT or PICK for image/*. the
        answer comes later as onActivityResult(request_code, result_code, data) of the activity, see exteria_host.activity_result"""
        pictures = (Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT, Intent.ACTION_PICK)
        mime = intent.getType()
        if intent.getAction() not in pictures or mime is None or not (mime == "image/*" or mime.startswith("image/")):
            raise NotImplementedError("the app has no screen for the intent %s of type %s, only pictures can be picked" % (intent.getAction(), mime))
        _ui.ask("app.pick_image", request=int(request_code))

    def openMessage(self, *_args):
        raise NotImplementedError("opening a message in the app is not available to plugins on ios")

    def getResources(self):
        raise NotImplementedError("resources are not available on ios")


_time_picks = {}
_time_token = [0]


def ask_time(mode, initial, minimum_ms, done):
    """opens the wheel of the app: mode is "date", "time" or "datetime", initial the (year, month, day, hour, minute) it starts on as the calendar of the
    phone reads them (None for now), minimum_ms the earliest it can show. done(None) runs when the person cancels, else done((epoch, year, month, day, hour,
    minute)) with the choice. the zone of the phone is the app's to know, so the parts come from its calendar and python does not guess them"""
    _time_token[0] += 1
    token = _time_token[0]
    _time_picks[token] = done
    request = {"token": token, "mode": mode}
    if initial is not None:
        request["initial"] = [int(part) for part in initial]
    if minimum_ms is not None:
        request["minimum"] = minimum_ms / 1000.0
    try:
        _ui.ask("app.pick_time", **request)
    except BaseException:
        _time_picks.pop(token, None)
        raise


def _time_picked(token, chosen):
    done = _time_picks.pop(int(token), None)
    if done is not None:
        done(None if chosen is None else tuple(int(part) for part in chosen))


class DatePicker(Object):
    """the wheel of a date dialog, as far as a plugin limits it"""

    def __init__(self):
        self._minimum = None

    def setMinDate(self, milliseconds):
        self._minimum = int(milliseconds)

    def getMinDate(self):
        return self._minimum or 0


class _PickerDialog(Object):
    def __init__(self):
        self._title = None

    def setTitle(self, title):
        """the wheel of the app has no title bar, the dialog only has to take the words"""
        self._title = title


class DatePickerDialog(_PickerDialog):
    class OnDateSetListener:
        pass

    def __init__(self, context, listener, year, month, day):
        super().__init__()
        self._listener = listener
        self._start = (int(year), int(month), int(day))
        self._picker = DatePicker()

    def getDatePicker(self):
        return self._picker

    def show(self):
        year, month, day = self._start
        # the month of the dialog counts from 0 as on android, the wheel from 1
        ask_time("date", (year, month + 1, day, 0, 0), self._picker._minimum, self._chosen)

    def _chosen(self, parts):
        if parts is not None:
            _, year, month, day, _hour, _minute = parts
            on_set = getattr(self._listener, "onDateSet", None) or self._listener
            on_set(None, year, month - 1, day)


class TimePickerDialog(_PickerDialog):
    class OnTimeSetListener:
        pass

    def __init__(self, context, listener, hour, minute, is_24_hour):
        super().__init__()
        self._listener = listener
        self._start = (int(hour), int(minute))

    def show(self):
        hour, minute = self._start
        ask_time("time", (2000, 1, 1, hour, minute), None, self._chosen)

    def _chosen(self, parts):
        if parts is not None:
            on_set = getattr(self._listener, "onTimeSet", None) or self._listener
            on_set(None, parts[4], parts[5])


_activity = []


def activity():
    if not _activity:
        # the hooks of a plugin sit on LaunchActivity.onActivityResult, so the one activity is an instance of that class
        from org.telegram.ui import LaunchActivity
        _activity.append(LaunchActivity())
    return _activity[0]
