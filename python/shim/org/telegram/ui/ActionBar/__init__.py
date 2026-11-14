"""org.telegram.ui.ActionBar"""

from android import _ui
from android.view import WRAP_CONTENT, Gravity, View
from java.lang import Object
from android.widget import FrameLayout, ImageView, LinearLayout, PopupWindow, TextView


def __getattr__(name):
    # BaseFragment is org.telegram.ui.ActionBar.BaseFragment in the android client; the shim writes it with the screens in org.telegram.ui
    if name == "BaseFragment":
        from org.telegram.ui import BaseFragment
        return BaseFragment
    raise AttributeError(name)


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
    def multAlpha(color, alpha):
        """the color with its alpha multiplied"""
        color = int(color) & 0xFFFFFFFF
        return ((int(round(((color >> 24) & 255) * alpha)) & 255) << 24) | (color & 0xFFFFFF)

    @staticmethod
    def blendOver(background, foreground):
        """foreground composited over background, both ARGB"""
        fa = ((int(foreground) >> 24) & 255) / 255.0
        out = 0xFF000000
        for shift in (16, 8, 0):
            b = (int(background) >> shift) & 255
            f = (int(foreground) >> shift) & 255
            out |= int(round(b * (1 - fa) + f * fa)) << shift
        return out & 0xFFFFFFFF

    @staticmethod
    def createSimpleSelectorRoundRectDrawable(radius, default_color, pressed_color, *_selected):
        """a round rectangle of the default color. the pressed color is what android shows while a finger is down; the app draws no
        pressed state, so the drawable is the default one"""
        from android.graphics.drawable import GradientDrawable
        shape = GradientDrawable()
        shape.setCornerRadius(float(radius))
        shape.setColor(default_color)
        return shape

    @staticmethod
    def createRoundRectDrawable(radius, color):
        return Theme.createSimpleSelectorRoundRectDrawable(radius, color, color)

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
            # 2 is the loading dialog and 3 the spinner: both show the message with a bar the plugin moves and the buttons it gave
            self._progress = bool(kind and kind[0] in (2, 3))
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

    def __init__(self, builder, *_progress):
        self._builder = builder
        self._showing = False
        self._token = None
        self._text = builder._message
        self._percent = 0

    def setMessage(self, text):
        """the text of a dialog that is up; a progress dialog shows it at once"""
        self._text = str(text)
        self._update()

    def setProgress(self, percent):
        self._percent = max(0, min(100, int(percent)))
        self._update()

    def _update(self):
        if self._showing and self._token is not None and self._builder._progress:
            from android import _ui
            _ui.ask("progress.update", token=self._token, message=self._text, percent=self._percent)

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
        self._token = token
        _pending[token] = self
        if builder._progress:
            # the panel of the app keeps the bar and the text, and reports a button by its place in this list
            order = [w for w in (AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL, AlertDialog.BUTTON_POSITIVE) if w in builder._buttons]
            self._order = order
            _ui.ask("progress.show", token=token, title=builder._title, message=self._text, percent=self._percent, buttons=[builder._buttons[w][0] for w in order])
            return
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
        if self._showing and self._token is not None and self._builder._progress:
            from android import _ui
            _pending.pop(self._token, None)
            _ui.ask("progress.close", token=self._token)
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




class ActionBarMenuSubItem(LinearLayout):
    """a row of a popup menu: an icon and a text. the icon is a picture or a drawable; a resource number of the android client names no
    picture of the app, so it is refused. ActionBarMenuSubItem(context, top, bottom) and the one with a resources provider are the same"""

    ICON = 20

    def __init__(self, context=None, *_flags):
        super().__init__(context)
        self.setOrientation(LinearLayout.HORIZONTAL)
        self.setGravity(Gravity.CENTER_VERTICAL)
        self.setPadding(16, 8, 16, 8)
        self._icon = ImageView(context)
        self._text = TextView(context)
        self._text.setTextSize(16)
        self._text.setTextColor(0xFFFFFFFF)
        params = LinearLayout.LayoutParams(self.ICON, self.ICON)
        params.rightMargin = 12
        self.addView(self._icon, params)
        self.addView(self._text, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        self._icon.setVisibility(View.GONE)

    def setText(self, text):
        self._text.setText(text)

    def getTextView(self):
        return self._text

    def setTextAndIcon(self, text, icon, *_more):
        self._text.setText(text)
        self.setIcon(icon)

    def setIcon(self, icon):
        if isinstance(icon, int):
            raise NotImplementedError("the icon %d is a resource of the android client, give a Drawable" % icon)
        if icon is None:
            self._icon.setVisibility(View.GONE)
            return
        bitmap = getattr(icon, "getBitmap", None)
        if bitmap is not None:
            self._icon.setImageBitmap(bitmap())
        else:
            self._icon.setBackground(icon)
        self._icon.setVisibility(View.VISIBLE)

    def setColors(self, text_color, icon_color):
        from android.graphics import PorterDuff
        self._text.setTextColor(text_color)
        # an image view tints with SRC_ATOP or SRC_OVER only
        self._icon.setColorFilter(icon_color, PorterDuff.Mode.SRC_ATOP)

    def setSelectorColor(self, color):
        # a touch on a row of the menu is shown by the sheet of the app, not by this view
        return None


class ActionBarPopupWindow(PopupWindow):
    """the popup of the menus of the app: a PopupWindow of a column of rows. it appears at once, without the scale animation of the android
    client, so startAnimation has nothing left to start"""

    class ActionBarPopupWindowLayout(LinearLayout):
        """the column of rows. getItemsCount counts the rows that are shown"""

        def __init__(self, context=None, *_resources):
            super().__init__(context)
            self.setOrientation(LinearLayout.VERTICAL)
            self._from_bottom = False
            self._key_listener = None
            self._fit = False

        def setShownFromBottom(self, value):
            self._from_bottom = bool(value)

        def isShownFromBottom(self):
            return self._from_bottom

        def setDispatchKeyEventListener(self, listener):
            self._key_listener = listener

        def setFitItems(self, value):
            self._fit = bool(value)

        def getItemsCount(self):
            return len([child for child in self._children if child.getVisibility() != View.GONE])

        def getItemAt(self, index):
            return self._children[index]

    def __init__(self, content=None, width=None, height=None, focusable=False, *_more):
        # ActionBarPopupWindow(context) has no content yet; ActionBarPopupWindow(content, width, height[, focusable]) has
        if not isinstance(content, View):
            content = None
        if width is None:
            width, height = -2, -2
        super().__init__(content, width, height, focusable)

    def startAnimation(self):
        return None

    def dismiss(self, animated=True):
        super().dismiss()


class ActionBar(FrameLayout):
    """the bar at the top of a screen of the android client: a title and a subtitle, and the listener that is told which item of its menu
    was chosen. the menu itself is the app's, so a listener is kept for a plugin that reads it back and the app never calls it"""

    class ActionBarMenuOnItemClick(Object):
        """the base a plugin extends: onItemClick(item_id) is empty, as in the client, and canOpenMenu() allows it"""

        def onItemClick(self, item_id):
            return None

        def canOpenMenu(self):
            return True

    def __init__(self, context=None, *_resources):
        super().__init__(context)
        self._title = TextView(context)
        self._title.setTextSize(18)
        self._subtitle = TextView(context)
        self._subtitle.setTextSize(13)
        self._subtitle.setVisibility(View.GONE)
        column = LinearLayout(context)
        column.setOrientation(LinearLayout.VERTICAL)
        column.addView(self._title, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        column.addView(self._subtitle, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        self.addView(column, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER_VERTICAL | Gravity.LEFT))
        self._on_item_click = None

    def setTitle(self, text):
        self._title.setText(text)

    def getTitle(self):
        return str(self._title.getText())

    def getTitleTextView(self):
        return self._title

    def setSubtitle(self, text):
        self._subtitle.setText(text or "")
        self._subtitle.setVisibility(View.VISIBLE if text else View.GONE)

    def getSubtitleTextView(self):
        return self._subtitle

    def setActionBarMenuOnItemClick(self, listener):
        self._on_item_click = listener

    def getActionBarMenuOnItemClick(self):
        return self._on_item_click
