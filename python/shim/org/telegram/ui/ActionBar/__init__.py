"""org.telegram.ui.ActionBar"""

from android import _ui


class _ThemeMeta(type):
    def __getattr__(cls, name):
        # Theme.key_x is the string "x" in the android app; the host maps the name to a color of the current look
        if name.startswith("key_"):
            return name[4:]
        raise AttributeError(name)


class Theme(metaclass=_ThemeMeta):
    class ResourcesProvider:
        """the interface plugin classes implement to hand a dialog its own colors"""

    @staticmethod
    def getColor(key, *_ignored):
        return int((_ui.ask("theme.color", key=str(key)) or {}).get("value", 0xFF000000)) & 0xFFFFFFFF

    @staticmethod
    def isCurrentThemeDark():
        return bool((_ui.ask("theme.dark") or {}).get("value"))

    @staticmethod
    def unrefAudioVisualizeDrawable(_message):
        """the android client counts the visualizer drawables of the songs and frees one when its song goes; the app draws none, so none is held"""


class AlertDialog:
    """the dialog of the android app, shown by the dialogs of the host app. buttons and lists report back by token (see _alert_result)"""

    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    class OnButtonClickListener:
        pass

    class Builder:
        def __init__(self, context=None, *args):
            kind = [a for a in args if isinstance(a, int)]
            if kind and kind[0] != 0:
                raise NotImplementedError("progress and spinner dialogs are not available on ios")
            self._title = ""
            self._message = ""
            self._buttons = {}
            self._items = None
            self._field = None
            self._dismiss = None
            self._cancel = None

        def setTitle(self, text):
            self._title = str(text)
            return self

        def setMessage(self, text):
            self._message = str(text)
            return self

        def setPositiveButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_POSITIVE] = (str(text), listener)
            return self

        def setNegativeButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_NEGATIVE] = (str(text), listener)
            return self

        def setNeutralButton(self, text, listener=None):
            self._buttons[AlertDialog.BUTTON_NEUTRAL] = (str(text), listener)
            return self

        def setItems(self, items, *rest):
            self._items = ([str(item) for item in items], rest[-1] if rest else None)
            return self

        def setOnDismissListener(self, listener):
            self._dismiss = listener
            return self

        def setOnCancelListener(self, listener):
            self._cancel = listener
            return self

        def setView(self, view, *_args):
            """a dialog shows one text field: the view may hold one EditText, which becomes the field of the dialog, and nothing else"""
            from android.widget import EditText
            leaves = []

            def collect(node):
                children = getattr(node, "_children", None)
                if children is None:
                    leaves.append(node)
                for child in children or ():
                    collect(child)

            collect(view)
            fields = [leaf for leaf in leaves if isinstance(leaf, EditText)]
            # a label or a picture next to the field would be dropped, and a dialog that silently loses it is worse than a refusal
            if len(fields) != 1 or len(leaves) != 1:
                raise NotImplementedError("a view inside a dialog is not available on ios, except one text field")
            self._field = fields[0]
            return self

        def setMessageTextViewClickable(self, _value):
            pass

        def setDimEnabled(self, _value):
            pass

        def setOnBackButtonListener(self, _listener):
            pass

        def create(self):
            return AlertDialog(self)

        def show(self):
            dialog = AlertDialog(self)
            dialog.show()
            return dialog

    def __init__(self, builder, *progress):
        if progress:
            raise NotImplementedError("progress and spinner dialogs are not available on ios")
        self._builder = builder
        self._showing = False

    def setCancelable(self, _value):
        pass

    def setCanceledOnTouchOutside(self, _value):
        pass

    def isShowing(self):
        return self._showing

    def getButton(self, _which):
        return None

    def show(self):
        from android import _ui
        builder = self._builder
        token = _next_token()
        self._showing = True
        _pending[token] = self
        if builder._items is not None:
            _ui.ask("ui.choose", token=token, title=builder._title, items=builder._items[0])
            return
        # the order of an ios alert: the cancel first, then the others; the negative button is the cancel
        order = [w for w in (AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL, AlertDialog.BUTTON_POSITIVE) if w in builder._buttons]
        if not order:
            order = [AlertDialog.BUTTON_POSITIVE]
            builder._buttons[AlertDialog.BUTTON_POSITIVE] = ("OK", None)
        self._order = order
        cancel = order.index(AlertDialog.BUTTON_NEGATIVE) if AlertDialog.BUTTON_NEGATIVE in order else -1
        field = None
        if builder._field is not None:
            field = {"initial": str(builder._field.getText()), "placeholder": str(getattr(builder._field, "_hint", ""))}
        _ui.ask("ui.alert", token=token, title=builder._title, message=builder._message,
                buttons=[builder._buttons[w][0] for w in order], cancel=cancel, field=field)

    def dismiss(self):
        self._showing = False

    def _answered(self, index, text=""):
        self._showing = False
        builder = self._builder
        if builder._field is not None:
            # the field of the dialog is the view the plugin handed over, so it reads its answer from it
            builder._field.setText(text)
        if builder._items is not None:
            listener = builder._items[1]
            if listener is not None:
                _call(listener, "onClick", self, index)
        else:
            which = self._order[index]
            listener = builder._buttons[which][1]
            if listener is not None:
                _call(listener, "onClick", self, which)
        if builder._dismiss is not None:
            _call(builder._dismiss, "onDismiss", self)


_pending = {}
_token = [0]


def _next_token():
    _token[0] += 1
    return _token[0]


def _call(listener, name, *args):
    method = getattr(listener, name, None)
    return method(*args) if method is not None else listener(*args)


def _alert_result(token, index, text=""):
    """the person picked a button or an item of a dialog; text is the field of the dialog when it has one"""
    dialog = _pending.pop(int(token), None)
    if dialog is not None:
        dialog._answered(int(index), text)


class BottomSheet:
    """a panel that slides up from the bottom edge over a dimmed scrim. the content is the custom view; a touch on the scrim
    dismisses it unless setCanDismissWithTouchOutside(False) or setCancelable(False) was called. a swipe down is not read"""

    DIM = 0x99000000
    SLIDE_MS = 220

    class Builder:
        """BottomSheet.Builder: the view goes in with setCustomView, create() gives the sheet and show() opens it"""

        def __init__(self, context=None, *flags):
            self._sheet = BottomSheet(context, *flags)

        def setCustomView(self, view):
            self._sheet.setCustomView(view)
            return self

        def setCancelable(self, value):
            self._sheet.setCancelable(value)
            return self

        def setOnDismissListener(self, listener):
            self._sheet.setOnDismissListener(listener)
            return self

        def create(self):
            return self._sheet

        def show(self):
            self._sheet.show()
            return self._sheet

    def __init__(self, context=None, *_flags):
        self._context = context
        self._content = None
        self._cancelable = True
        self._outside = True
        self._on_dismiss = None
        self._scrim = None
        self._panel = None

    def setCustomView(self, view):
        self._content = view

    def setCancelable(self, value):
        self._cancelable = bool(value)

    def setCanDismissWithTouchOutside(self, value):
        self._outside = bool(value)

    def setCanDismissWithSwipe(self, value):
        """a swipe is not read here, the setting only has to be accepted so the sheet can only close the way the plugin allows"""

    def setOnDismissListener(self, listener):
        self._on_dismiss = listener

    def isShowing(self):
        return self._scrim is not None

    def show(self):
        if self._content is None:
            raise ValueError("a sheet needs a custom view")
        if self._scrim is not None:
            return
        from android.app import activity
        from android.graphics.drawable import ColorDrawable, GradientDrawable
        from android.view import MATCH_PARENT, WRAP_CONTENT, Gravity
        from android.widget import FrameLayout
        decor = activity().getWindow().getDecorView()
        scrim = FrameLayout(decor.getContext())
        scrim.setBackground(ColorDrawable(BottomSheet.DIM))
        scrim.setOnClickListener(lambda _view: self.dismiss() if self._cancelable and self._outside else None)
        panel = FrameLayout(decor.getContext())
        shape = GradientDrawable()
        shape.setCornerRadius(16.0)
        shape.setColor(0xFF1C1C1E)
        panel.setBackground(shape)
        panel.setClickable(True)
        panel.addView(self._content, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        scrim.addView(panel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))
        decor.addView(scrim, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        self._scrim, self._panel = scrim, panel
        height = max(panel.getMeasuredHeight(), 1)
        panel.setTranslationY(float(height))
        panel.animate().translationY(0.0).setDuration(BottomSheet.SLIDE_MS).start()

    def dismiss(self):
        scrim, self._scrim = self._scrim, None
        if scrim is None:
            return
        self._panel.removeView(self._content)
        scrim.getParent().removeView(scrim)
        self._panel = None
        listener = self._on_dismiss
        if listener is None:
            return
        on_dismiss = getattr(listener, "onDismiss", None)
        if on_dismiss is not None:
            on_dismiss(self)
        else:
            run = getattr(listener, "run", None)
            (run if run is not None else listener)()


