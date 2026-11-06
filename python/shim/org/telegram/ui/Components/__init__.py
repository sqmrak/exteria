"""org.telegram.ui.Components: the short notices of the android app, shown as a banner at the top"""

from android import _ui
from android.graphics import ColorMatrixColorFilter, Paint
from android.view import MATCH_PARENT, WRAP_CONTENT, Gravity, View, ViewGroup, _resolve
from android.widget import EditText, FrameLayout, ImageView, LinearLayout, TextView
from org.telegram.messenger import AndroidUtilities
from org.telegram.messenger.music import VideoPlayer  # noqa: F401
from java.lang import Object


class AlertsCreator(Object):
    class ScheduleDatePickerDelegate:
        """the object a plugin gives to the schedule dialog; didSelectDate(notify, date) runs once the person chose"""

    class _ScheduleDialog:
        def __init__(self, delegate):
            self._delegate = delegate

        def show(self):
            import time
            from android.app import ask_time
            # a moment from now at the earliest: a time that has passed cannot be scheduled, and the wheel does not offer it
            ask_time("datetime", None, int((time.time() + 60) * 1000), self._chosen)
            return self

        def _chosen(self, parts):
            if parts is not None:
                self._delegate.didSelectDate(True, int(parts[0]))

    @staticmethod
    def createScheduleDatePickerDialog(context, dialog_id, delegate, *_ignored):
        """the wheel of the app for a date and a time, with the choice sent to delegate.didSelectDate(notify, date): the date is seconds since 1970"""
        return AlertsCreator._ScheduleDialog(delegate)


class Bulletin:
    def __init__(self, text):
        self._text = text

    def show(self, *_ignored):
        _ui.ask("ui.toast", text=self._text)
        return self


class BulletinFactory:
    class FileType:
        pass

    def __init__(self, fragment=None):
        self._fragment = fragment

    @staticmethod
    def of(fragment=None, *_ignored):
        return BulletinFactory(fragment)

    @staticmethod
    def _global():
        return BulletinFactory()

    @staticmethod
    def _text(args):
        strings = [a for a in args if isinstance(a, str)]
        return "\n".join(strings[:2]) if strings else ""

    def createSimpleBulletin(self, *args):
        # (icon, text), (icon, title, subtitle) and (icon, text, button, action): the words in front are the message
        strings = [a for a in args if isinstance(a, str)]
        has_action = any(callable(a) and not isinstance(a, str) for a in args)
        return Bulletin("\n".join(strings[:1] if has_action else strings[:2]))

    def createErrorBulletin(self, *args):
        return Bulletin(self._text(args))

    def createSuccessBulletin(self, *args):
        return Bulletin(self._text(args))

    def createCopyBulletin(self, *args):
        return Bulletin(self._text(args) or "Copied")


# the factory for no fragment is the member named global in the android app
setattr(BulletinFactory, "global", BulletinFactory._global)


class UItem(Object):
    """an item of the lists of the android app. a factory is recorded for a row a plugin builds itself; the settings page of
    the host shows such a row as unavailable, so no view is ever made from it"""

    class UItemFactory(Object):
        factories = []

        @staticmethod
        def setup(factory):
            kind = type(factory)
            UItem.UItemFactory.factories[:] = [known for known in UItem.UItemFactory.factories if type(known) is not kind]
            UItem.UItemFactory.factories.append(factory)

    @staticmethod
    def ofFactory(factory_class):
        item = UItem()
        item.factory = factory_class
        item.object = None
        return item

    @staticmethod
    def _row(kind, **fields):
        item = UItem()
        item.factory = None
        item.object = None
        item.kind = kind
        item.id = fields.pop("id", -1)
        for name, value in fields.items():
            setattr(item, name, value)
        return item

    @staticmethod
    def asRoundCheckbox(item_id, text):
        return UItem._row("round_checkbox", id=item_id, text=str(text), checked=False, padded=False)

    @staticmethod
    def asExteraExpandableSwitch(item_id, text, subtext, listener=None):
        return UItem._row("expandable_switch", id=item_id, text=str(text), subtext=str(subtext), listener=listener,
                          checked=False, collapsed=False, padded=False)

    @staticmethod
    def asSlideView(choices, chosen, when_chose):
        """a row that picks one of a few texts. the settings page shows it as a row of choices, and the answer is passed to when_chose (a Callback)"""
        return UItem._row("slide", choices=[str(choice) for choice in choices], chosen=int(chosen), whenChose=when_chose, intValue=int(chosen))

    def setChecked(self, value):
        self.checked = bool(value)
        return self

    def setCollapsed(self, value):
        self.collapsed = bool(value)
        return self

    def pad(self, *_amount):
        self.padded = True
        return self


class LayoutHelper:
    """the layout params the android app builds with sizes in dp; one dp is one point here. MATCH_PARENT and WRAP_CONTENT
    stay what they are, and the margins and the gravity are set the way the overloads of the android class read them"""

    MATCH_PARENT = -1
    WRAP_CONTENT = -2

    @staticmethod
    def _size(value):
        return int(value) if value in (-1, -2) else AndroidUtilities.dp(value)

    @staticmethod
    def createFrame(width, height, gravity=-1, left=0, top=0, right=0, bottom=0):
        params = FrameLayout.LayoutParams(LayoutHelper._size(width), LayoutHelper._size(height), int(gravity))
        params.setMargins(AndroidUtilities.dp(left), AndroidUtilities.dp(top), AndroidUtilities.dp(right), AndroidUtilities.dp(bottom))
        return params

    @staticmethod
    def createLinear(width, height, *args):
        """(weight, gravity, l, t, r, b), (weight, l, t, r, b), (gravity, l, t, r, b), (weight, gravity), (l, t, r, b), (gravity) or (weight);
        a float or a value in 0..1 in the first place reads as a weight when more than the gravity is given, as the android overloads do"""
        weight, gravity, margins = 0.0, -1, (0, 0, 0, 0)
        if len(args) == 6:
            weight, gravity, margins = args[0], args[1], args[2:]
        elif len(args) == 5:
            if isinstance(args[0], float):
                weight, margins = args[0], args[1:]
            else:
                gravity, margins = args[0], args[1:]
        elif len(args) == 4:
            margins = args
        elif len(args) == 2:
            weight, gravity = args
        elif len(args) == 1:
            if isinstance(args[0], float):
                weight = args[0]
            else:
                gravity = args[0]
        elif args:
            raise TypeError("createLinear takes 2 to 8 arguments")
        params = LinearLayout.LayoutParams(LayoutHelper._size(width), LayoutHelper._size(height), float(weight))
        params.gravity = int(gravity)
        params.setMargins(*(AndroidUtilities.dp(m) for m in margins))
        return params

    @staticmethod
    def createScroll(width, height, gravity=-1, *margins):
        params = FrameLayout.LayoutParams(LayoutHelper._size(width), LayoutHelper._size(height), int(gravity))
        if margins:
            params.setMargins(*(AndroidUtilities.dp(m) for m in margins))
        return params


class BackupImageView(ImageView):
    """the image view of the android app that loads a file; here it shows a bitmap the plugin hands it, clipped at the radius"""

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._radius = 0

    def setRoundRadius(self, radius):
        from org.telegram.messenger.utils import ViewOutlineProviderImpl
        self._radius = int(radius)
        self.setOutlineProvider(ViewOutlineProviderImpl.boundsWithRoundRect(radius))
        self.setClipToOutline(self._radius > 0)

    def setImageBitmap(self, bitmap):
        super().setImageBitmap(bitmap)


class EditTextBoldCursor(EditText):
    """the text field of dialogs. the cursor is drawn by the system field, so only the text, the hint and the selection are here"""


class LineProgressView(FrameLayout):
    """a track and a fill, progress from 0 to 1"""

    HEIGHT = 4

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._progress = 0.0
        self._track = View(context)
        self._fill = View(context)
        self.addView(self._track, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        self.addView(self._fill, FrameLayout.LayoutParams(0, MATCH_PARENT, Gravity.LEFT))
        self.setBackColor(0x33808080)
        self.setProgressColor(0xFF2481CC)

    @staticmethod
    def _shape(color):
        from android.graphics.drawable import GradientDrawable
        shape = GradientDrawable()
        shape.setCornerRadius(LineProgressView.HEIGHT / 2.0)
        shape.setColor(color)
        return shape

    def setBackColor(self, color):
        self._track.setBackground(self._shape(color))

    def setProgressColor(self, color):
        self._fill.setBackground(self._shape(color))

    def setProgress(self, value, animated=False):
        self._progress = min(max(float(value), 0.0), 1.0)
        self._request_layout()

    def getProgress(self):
        return self._progress

    def _on_measure(self, wspec, hspec):
        width = _resolve(wspec, 160)
        self._fill.getLayoutParams().width = int(round(width * self._progress))
        return super()._on_measure(wspec, hspec)


class CubicBezierInterpolator:
    """the named curves of the android app map to the nearest curve of the app (see android.view.animation)"""

    class _Curve:
        def __init__(self, curve):
            self.curve = curve

    DEFAULT = _Curve("ease")
    EASE_OUT = _Curve("decel")
    EASE_OUT_QUINT = _Curve("decel")
    EASE_IN = _Curve("accel")
    EASE_BOTH = _Curve("ease")


class ItemOptions:
    """the menu that opens at a view. rows are added with add(icon, text, red, runnable) and show() opens a popup under the view;
    the icon is a resource id of android, which does not exist here, so the rows are text"""

    ROW_HEIGHT = 44
    MENU_WIDTH = 220

    def __init__(self, anchor):
        self._anchor = anchor
        self._rows = []
        self._popup = None

    @staticmethod
    def makeOptions(*args):
        anchor = next((a for a in reversed(args) if isinstance(a, View)), None)
        if anchor is None:
            raise ValueError("makeOptions needs the view the menu opens at")
        return ItemOptions(anchor)

    def add(self, icon, text, *rest):
        """add(icon, text, runnable) or add(icon, text, red, runnable)"""
        if len(rest) == 1:
            red, action = False, rest[0]
        elif len(rest) == 2:
            red, action = rest
        else:
            raise TypeError("add takes (icon, text, runnable) or (icon, text, red, runnable)")
        self._rows.append((str(text), bool(red), action))
        return self

    def show(self):
        from android.graphics.drawable import GradientDrawable
        from android.widget import PopupWindow
        if not self._rows:
            raise ValueError("a menu without rows")
        context = self._anchor.getContext()
        column = LinearLayout(context)
        column.setOrientation(LinearLayout.VERTICAL)
        panel = GradientDrawable()
        panel.setCornerRadius(12.0)
        panel.setColor(0xFF2C2C2E)
        column.setBackground(panel)
        popup = PopupWindow(column, ItemOptions.MENU_WIDTH, WRAP_CONTENT, True)
        for text, red, action in self._rows:
            row = TextView(context)
            row.setText(text)
            row.setTextSize(16)
            row.setTextColor(0xFFFF453A if red else 0xFFFFFFFF)
            row.setGravity(Gravity.CENTER_VERTICAL)
            row.setPadding(16, 0, 16, 0)

            def clicked(_view, action=action):
                popup.dismiss()
                method = getattr(action, "run", None)
                (method if method is not None else action)()

            row.setOnClickListener(clicked)
            column.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, ItemOptions.ROW_HEIGHT))
        self._popup = popup
        popup.showAsDropDown(self._anchor, 0, 0)
        return self

    def dismiss(self):
        if self._popup is not None:
            self._popup.dismiss()


class _CardPaint(Paint):
    """the paint the settings page fills its cards with. a color filter that only scales alpha makes the cards see-through: the app
    applies that scale to its own cards. None puts them back"""

    def __init__(self):
        super().__init__()
        self._sent = 1.0

    def setColorFilter(self, color_filter):
        super().setColorFilter(color_filter)
        if color_filter is None:
            scale = 1.0
        else:
            scale = color_filter._alpha_scale() if isinstance(color_filter, ColorMatrixColorFilter) else None
        if scale is None:
            raise NotImplementedError("the cards of the settings page take a color filter that only scales alpha")
        if scale != self._sent:
            self._sent = scale
            _ui.ask("page.cards", alpha=scale)
        return color_filter


class RecyclerListView(ViewGroup):
    """the list of the settings page. the page draws its rows itself, so the list has no row views to walk (getChildCount is 0) and
    nothing to redraw: what a plugin changes on its paints reaches the page at once. the fields are the paints of the android list that
    a plugin reads by name"""

    sectionBackgroundPaint: Paint
    backgroundPaint: Paint
    sectionBackgroundStrokePaint: Paint

    def __init__(self, page):
        ViewGroup.__init__(self, None)
        self._page = page
        self.sectionBackgroundPaint = _CardPaint()
        self.backgroundPaint = Paint()
        self.sectionBackgroundStrokePaint = Paint()

    def getWidth(self):
        return self._page.fragmentView.getWidth()

    def getHeight(self):
        return self._page.fragmentView.getHeight()

    def invalidateViews(self):
        """the changes of a plugin are applied when it makes them"""
