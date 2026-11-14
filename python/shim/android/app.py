"""android.app: the activity a plugin finds as LaunchActivity.instance. one object, kept for the life of the process"""

from android import _ui
from android.content import Context, Intent
from android.view import DecorView, Window
from java.lang import IllegalStateException, Object


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
        if name == Context.NSD_SERVICE:
            from android.net.nsd import NsdManager
            return NsdManager._get()
        if name == Context.NOTIFICATION_SERVICE:
            from android.notifications import NotificationManager
            return NotificationManager._get()
        if name == Context.ALARM_SERVICE:
            from android.notifications import AlarmManager
            return AlarmManager._get()
        if name == Context.WINDOW_SERVICE:
            from android.view import WindowManager
            return WindowManager._get()
        if name == Context.CLIPBOARD_SERVICE:
            from android.content import ClipboardManager
            return ClipboardManager._get()
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


class Dialog(Object):
    """a view above the window with a dim scrim: the content view the program gives, centered, and a touch outside it dismisses
    the dialog when it is cancelable. there is no title bar, the program draws its own"""

    def __init__(self, context=None, theme=0):
        self._context = context if context is not None else activity()
        self._content = None
        self._window = _DialogWindow(self)
        self._cancelable = True
        self._outside = True
        self._on_dismiss = None
        self._on_cancel = None
        self._on_show = None
        self._scrim = None
        self._shown = False

    def getContext(self):
        return self._context

    def getWindow(self):
        return self._window

    def setContentView(self, view, params=None):
        self._content = view
        if self._scrim is not None:
            self._relayout()

    def setCancelable(self, flag):
        self._cancelable = bool(flag)

    def setCanceledOnTouchOutside(self, flag):
        self._outside = bool(flag)

    def setOnDismissListener(self, listener):
        self._on_dismiss = listener

    def setOnCancelListener(self, listener):
        self._on_cancel = listener

    def setOnShowListener(self, listener):
        self._on_show = listener

    def setTitle(self, title):
        self._title = title

    def isShowing(self):
        return self._shown

    def findViewById(self, view_id):
        return self._content.findViewById(view_id) if self._content is not None else None

    def _relayout(self):
        from android.view import Gravity, LayoutParams
        from android.widget import FrameLayout
        scrim = self._scrim
        scrim.removeAllViews()
        if self._content is None:
            return
        parent = self._content.getParent()
        if parent is not None:
            parent.removeView(self._content)
        width, height = self._window._width, self._window._height
        params = FrameLayout.LayoutParams(width, height, self._window._gravity)
        scrim.addView(self._content, params)

    def show(self):
        if self._shown:
            return
        if self._content is None:
            raise IllegalStateException("a dialog needs a content view")
        from android.view import LayoutParams
        from android.widget import FrameLayout
        decor = activity().getWindow().getDecorView()
        scrim = FrameLayout(decor.getContext())
        dim = self._window._dim
        if dim > 0:
            from android.graphics.drawable import ColorDrawable
            scrim.setBackground(ColorDrawable(int(dim * 255) << 24))
        scrim.setClickable(True)
        scrim.setOnClickListener(lambda _view: self.cancel() if self._cancelable and self._outside else None)
        self._scrim = scrim
        self._relayout()
        background = self._window._background
        if background is not None:
            self._content.setBackground(background)
        decor.addView(scrim, FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        self._shown = True
        _call(self._on_show, "onShow", self)

    def dismiss(self):
        if not self._shown:
            return
        self._shown = False
        scrim, self._scrim = self._scrim, None
        if scrim.getChildCount() and self._content is not None:
            scrim.removeView(self._content)
        parent = scrim.getParent()
        if parent is not None:
            parent.removeView(scrim)
        _call(self._on_dismiss, "onDismiss", self)

    hide = dismiss

    def cancel(self):
        if not self._shown:
            return
        _call(self._on_cancel, "onCancel", self)
        self.dismiss()

    def onBackPressed(self):
        if self._cancelable:
            self.cancel()


def _call(listener, name, *args):
    if listener is None:
        return None
    method = getattr(listener, name, None)
    return method(*args) if method is not None else listener(*args)


class _DialogWindow(Window):
    """the Window of a dialog: size, gravity, dim and background are the ones the dialog is laid out with"""

    def __init__(self, dialog):
        Window.__init__(self, dialog)
        from android.view import Gravity, LayoutParams
        self._width = LayoutParams.WRAP_CONTENT
        self._height = LayoutParams.WRAP_CONTENT
        self._gravity = Gravity.CENTER
        self._dim = 0.5
        self._background = None

    def getDecorView(self):
        return self._activity._content

    def setLayout(self, width, height):
        self._width, self._height = int(width), int(height)
        if self._activity._scrim is not None:
            self._activity._relayout()

    def setGravity(self, gravity):
        self._gravity = int(gravity)
        if self._activity._scrim is not None:
            self._activity._relayout()

    def setDimAmount(self, amount):
        self._dim = max(0.0, min(1.0, float(amount)))

    def setBackgroundDrawable(self, drawable):
        self._background = drawable
        if self._activity._content is not None and self._activity._shown:
            self._activity._content.setBackground(drawable)

    def setBackgroundDrawableResource(self, resource_id):
        from android.content.res import Resources
        Resources.getSystem().getDrawable(resource_id)


class AlertDialog(Dialog):
    """a dialog of a title, a message, a custom view and up to three buttons, laid out with the views of the shims"""

    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    class Builder(Object):
        def __init__(self, context=None, theme=0):
            self._context = context
            self._title = None
            self._message = None
            self._view = None
            self._buttons = {}
            self._cancelable = True
            self._on_dismiss = None
            self._on_cancel = None

        def setTitle(self, title):
            self._title = title
            return self

        def setMessage(self, message):
            self._message = message
            return self

        def setView(self, view):
            self._view = view
            return self

        def setCancelable(self, flag):
            self._cancelable = bool(flag)
            return self

        def setPositiveButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_POSITIVE] = (text, listener)
            return self

        def setNegativeButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_NEGATIVE] = (text, listener)
            return self

        def setNeutralButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_NEUTRAL] = (text, listener)
            return self

        def setOnDismissListener(self, listener):
            self._on_dismiss = listener
            return self

        def setOnCancelListener(self, listener):
            self._on_cancel = listener
            return self

        def create(self):
            dialog = AlertDialog(self._context)
            dialog._build(self)
            return dialog

        def show(self):
            dialog = self.create()
            dialog.show()
            return dialog

    def _build(self, builder):
        from android.graphics.drawable import GradientDrawable
        from android.view import Gravity, LayoutParams
        from android.widget import LinearLayout, TextView
        context = builder._context if builder._context is not None else self._context
        column = LinearLayout(context)
        column.setOrientation(LinearLayout.VERTICAL)
        column.setPadding(24, 20, 24, 12)
        card = GradientDrawable()
        card.setColor(0xFFFFFFFF)
        card.setCornerRadius(14.0)
        self._window.setBackgroundDrawable(card)
        if builder._title:
            title = TextView(context)
            title.setText(str(builder._title))
            title.setTextSize(18)
            title.setTextColor(0xFF000000)
            column.addView(title, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        if builder._message:
            message = TextView(context)
            message.setText(str(builder._message))
            message.setTextSize(15)
            message.setTextColor(0xFF333333)
            column.addView(message, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        if builder._view is not None:
            column.addView(builder._view)
        if builder._buttons:
            row = LinearLayout(context)
            row.setOrientation(LinearLayout.HORIZONTAL)
            for which in (AlertDialog.BUTTON_NEUTRAL, AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_POSITIVE):
                if which not in builder._buttons:
                    continue
                text, listener = builder._buttons[which]
                button = TextView(context)
                button.setText(str(text))
                button.setTextSize(15)
                button.setTextColor(0xFF2481CC)
                button.setPadding(16, 12, 16, 12)
                button.setClickable(True)
                button.setOnClickListener(self._button_handler(which, listener))
                row.addView(button, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
            column.addView(row, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        self.setContentView(column)
        self._cancelable = builder._cancelable
        self._on_dismiss = builder._on_dismiss
        self._on_cancel = builder._on_cancel
        self._buttons = {which: (listener, None) for which, (text, listener) in builder._buttons.items()}

    def _button_handler(self, which, listener):
        def clicked(_view):
            _call(listener, "onClick", self, which)
            self.dismiss()
        return clicked

    def getButton(self, which):
        return None

    def setMessage(self, text):
        return None


class ActivityThread:
    """of the android class only the application a plugin asks for. the thread object and its private fields (mActivities and the others
    a plugin reaches into by reflection) belong to the android runtime and are not there"""

    @staticmethod
    def currentApplication():
        return activity().getApplicationContext()


from android.notifications import AlarmManager, Notification, NotificationChannel, NotificationManager, PendingIntent  # noqa: E402,F401
