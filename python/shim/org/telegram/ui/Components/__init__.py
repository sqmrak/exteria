"""org.telegram.ui.Components: the short notices of the android app, shown as a banner at the top"""

from android import _ui
from android.graphics import ColorMatrixColorFilter, Paint
from android.view import MATCH_PARENT, WRAP_CONTENT, Gravity, View, ViewGroup, _resolve
from android.widget import EditText, FrameLayout, ImageView, LinearLayout, TextView
from org.telegram.messenger import AndroidUtilities
from org.telegram.messenger.music import VideoPlayer  # noqa: F401
from android.graphics.drawable import Drawable
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


class RadialProgressView(View):
    """a ring. with setNoProgress(True), the default, a quarter turn of it spins; with setNoProgress(False) the arc of setProgress(0..1) is
    drawn. the spin is a frame every 100 ms for as long as the view is in a window, and stops when it leaves"""

    FRAME_MS = 100
    TURN = 30

    def __init__(self, context=None, *_resources):
        super().__init__(context)
        self._size = 40
        self._stroke = 3.0
        self._color = 0xFF2481CC
        self._progress = 0.0
        self._spinning = True
        self._angle = 0
        self._loop = 0

    def setSize(self, size):
        self._size = max(int(size), 1)
        self._request_layout()
        self.invalidate()

    def getSize(self):
        return self._size

    def setStrokeWidth(self, width):
        self._stroke = max(float(width), 1.0)
        self.invalidate()

    def setProgressColor(self, color):
        self._color = int(color) & 0xFFFFFFFF
        self.invalidate()

    def setProgress(self, value):
        self._progress = min(max(float(value), 0.0), 1.0)
        self.invalidate()

    def getProgress(self):
        return self._progress

    def setNoProgress(self, value):
        self._spinning = bool(value)
        self._restart()
        self.invalidate()

    def _content_size(self, max_w, max_h):
        return (self._size, self._size)

    def onDraw(self, canvas):
        from android.graphics import Paint, RectF
        paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.setStyle(Paint.Style.STROKE)
        paint.setStrokeWidth(self._stroke)
        paint.setColor(self._color)
        paint.setStrokeCap(Paint.Cap.ROUND)
        inset = self._stroke / 2.0
        ring = RectF(inset, inset, max(self.getWidth(), self._size) - inset, max(self.getHeight(), self._size) - inset)
        if self._spinning:
            canvas.drawArc(ring, self._angle, 270.0, False, paint)
        else:
            canvas.drawArc(ring, -90.0, 360.0 * self._progress, False, paint)

    def _restart(self):
        self._loop += 1
        if self._attached and self._spinning:
            self._schedule(self._loop)

    def _schedule(self, loop):
        from android.os import Handler

        def frame():
            if loop != self._loop or not self._attached or not self._spinning:
                return
            self._angle = (self._angle + RadialProgressView.TURN) % 360
            self.invalidate()
            self._schedule(loop)

        class Step:
            def run(self):
                frame()

        Handler().postDelayed(Step(), RadialProgressView.FRAME_MS)

    def onAttachedToWindow(self):
        self._restart()

    def onDetachedFromWindow(self):
        self._loop += 1


def _avatar_initials(first, last):
    """the first letter of the first name and of the last one, upper case; one letter when only one name is there, else nothing"""
    letters = []
    for name in (first, last):
        name = (name or "").strip()
        if name:
            letters.append(name[0].upper())
    return "".join(letters)


class AvatarDrawable(Drawable):
    """the round picture of a person or chat that has none: a color picked by the id and the initials. the colors are the seven of the classic
    client, in the order red, orange, violet, green, cyan, blue, pink; a person with ids 0 to 6 gets the color of the same number. setInfo takes a
    user or chat record (id and first_name, last_name or title), the three arguments (id, first name, last name), or an account first"""

    COLORS = (0xFFE56555, 0xFFF28C48, 0xFF8E85EE, 0xFF76C84D, 0xFF5FBED5, 0xFF549CDD, 0xFFF2749A)

    def __init__(self, *_chat_or_user):
        super().__init__()
        self._color = AvatarDrawable.COLORS[0]
        self._text = ""
        self._text_size = 0
        self._bounds = (0, 0, 0, 0)

    @staticmethod
    def getColorForId(identifier):
        identifier = int(identifier)
        index = identifier if 0 <= identifier < 7 else abs(identifier) % 7
        return AvatarDrawable.COLORS[index]

    def setInfo(self, *args):
        if len(args) == 3 and isinstance(args[0], int):
            identifier, first, last = args
        else:
            record = args[-1]
            if record is None:
                self._text = ""
                self._changed()
                return
            identifier = getattr(record, "id", 0)
            if getattr(record, "title", None) is not None:
                first, last = record.title, ""
            else:
                first, last = getattr(record, "first_name", ""), getattr(record, "last_name", "")
        self._color = AvatarDrawable.getColorForId(identifier)
        self._text = _avatar_initials(first, last)
        self._changed()

    def setColor(self, color):
        self._color = int(color) & 0xFFFFFFFF
        self._changed()

    def getColor(self):
        return self._color

    def setTextSize(self, size):
        self._text_size = int(size)
        self._changed()

    def getText(self):
        return self._text

    def getIntrinsicWidth(self):
        return -1

    def draw(self, canvas):
        from android.graphics import Paint, RectF
        left, top, right, bottom = self._bounds
        if right <= left or bottom <= top or not self._visible:
            return
        disc = self._paint_for(self._color)
        disc.setAntiAlias(True)
        canvas.drawOval(RectF(left, top, right, bottom), disc)
        if not self._text:
            return
        size = self._text_size or int((bottom - top) * 0.42)
        letters = Paint(Paint.ANTI_ALIAS_FLAG)
        letters.setColor(0xFFFFFFFF)
        letters.setAlpha(self._alpha)
        letters.setTextSize(size)
        letters.setTextAlign(Paint.Align.CENTER)
        metrics = letters.getFontMetrics()
        baseline = (top + bottom) / 2.0 - (metrics.ascent + metrics.descent) / 2.0
        canvas.drawText(self._text, (left + right) / 2.0, baseline, letters)


class SizeNotifierFrameLayout(FrameLayout):
    """the root layout of a chat screen in the android client, which tells its delegate when the keyboard changes the size. the keyboard of ios is
    not followed here, so getKeyboardHeight is 0 and the delegate is kept and never called; the background image is the background of the view"""

    class SizeNotifierFrameLayoutDelegate:
        """a program implements onSizeChanged(keyboard_height, is_width_greater)"""

    def __init__(self, context=None, *_more):
        super().__init__(context)
        self._delegate = None
        self._image = None

    def setDelegate(self, delegate):
        self._delegate = delegate

    def getKeyboardHeight(self):
        return 0

    def measureKeyboardHeight(self):
        return 0

    def setBackgroundImage(self, drawable, motion=False):
        self._image = drawable
        self.setBackground(drawable)

    def getBackgroundImage(self):
        return self._image


class CheckBox2(View):
    """the round check box of the settings and share screens: a ring when off (drawn only with setDrawUnchecked), a disc with a tick when on.
    setColor takes the color of the ring and of the disc and of the tick, each a number or a theme key. setChecked takes an animated flag that the
    drawing here does not use, the box changes at once"""

    def __init__(self, context=None, size=21, *_resources):
        super().__init__(context)
        self._size = max(int(size), 1)
        self._checked = False
        self._draw_unchecked = False
        self._arc = 0
        self._number = -1
        self._colors = (0xFF8E8E93, 0xFF2481CC, 0xFFFFFFFF)

    def setColor(self, background, checked_background, check):
        self._colors = (background, checked_background, check)
        self.invalidate()

    def setDrawUnchecked(self, value):
        self._draw_unchecked = bool(value)
        self.invalidate()

    def setDrawBackgroundAsArc(self, kind):
        self._arc = int(kind)
        self.invalidate()

    def setNum(self, number):
        self._number = int(number)
        self.invalidate()

    def getNum(self):
        return self._number

    def setChecked(self, checked, animated=False):
        self._checked = bool(checked)
        self.invalidate()

    def isChecked(self):
        return self._checked

    def _content_size(self, max_w, max_h):
        return (self._size, self._size)

    @staticmethod
    def _color(value):
        if isinstance(value, str):
            from org.telegram.ui.ActionBar import Theme
            return Theme.getColor(value)
        return int(value) & 0xFFFFFFFF

    def onDraw(self, canvas):
        from android.graphics import Paint, Path, RectF
        size = float(max(self._size, min(self.getWidth(), self.getHeight())))
        if not self._checked and not self._draw_unchecked:
            return
        ring, disc, tick = (self._color(c) for c in self._colors)
        paint = Paint(Paint.ANTI_ALIAS_FLAG)
        stroke = max(size / 10.0, 1.0)
        box = RectF(stroke / 2.0, stroke / 2.0, size - stroke / 2.0, size - stroke / 2.0)
        if self._checked:
            paint.setColor(disc)
            canvas.drawOval(box, paint)
            paint.setColor(tick)
            paint.setStyle(Paint.Style.STROKE)
            paint.setStrokeWidth(stroke)
            paint.setStrokeCap(Paint.Cap.ROUND)
            mark = Path()
            mark.moveTo(size * 0.28, size * 0.52)
            mark.lineTo(size * 0.44, size * 0.68)
            mark.lineTo(size * 0.74, size * 0.34)
            canvas.drawPath(mark, paint)
        else:
            paint.setColor(ring)
            paint.setStyle(Paint.Style.STROKE)
            paint.setStrokeWidth(stroke)
            canvas.drawOval(box, paint)


class RLottieImageView(ImageView):
    """importable only: the player of Lottie animations of the android client. the app plays its animations with its own player and gives plugins no
    way to start one, so making a view raises NotImplementedError"""

    def __init__(self, *_arguments):
        raise NotImplementedError("a Lottie animation view has no equal a plugin can use, the animations of the app are played by the app")


class ShareAlert(Object):
    """importable only: the share sheet of the android client. making one raises NotImplementedError; ShareAlertDelegate, the interface a
    plugin implements to hear of the sharing, is there so that a class which extends it can be written"""

    class ShareAlertDelegate:
        """a program implements didShare(), didCopy() and the other callbacks of the delegate"""

    def __init__(self, *_arguments):
        raise NotImplementedError("the share sheet of the android client has no equal a plugin can open")
