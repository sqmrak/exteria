"""android.widget: the layouts and the views a plugin builds a small panel from"""

from android import _ui
from android.view import (AT_MOST, EXACTLY, MATCH_PARENT, UNSPECIFIED, WRAP_CONTENT, DecorView, Gravity, MarginLayoutParams,
                          View, ViewGroup, _MODE_MASK, _argb, _place_frame_children, _resolve)
from android.util import TypedValue
from android.view import MotionEvent
from java.lang import Object


class FrameLayout(ViewGroup):
    class LayoutParams(MarginLayoutParams):
        def __init__(self, width=WRAP_CONTENT, height=WRAP_CONTENT, gravity=-1):
            super().__init__(width, height)
            self.gravity = gravity if isinstance(gravity, int) else -1

    def _default_params(self):
        return FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)

    def _on_measure(self, wspec, hspec):
        biggest_w = biggest_h = 0
        for child in self._visible_children():
            self._measure_child(child, wspec, hspec)
            left, top, right, bottom = self._margins(child)
            biggest_w = max(biggest_w, child._measured[0] + left + right)
            biggest_h = max(biggest_h, child._measured[1] + top + bottom)
        pad_w, pad_h = self._pad[0] + self._pad[2], self._pad[1] + self._pad[3]
        return (_resolve(wspec, biggest_w + pad_w), _resolve(hspec, biggest_h + pad_h))

    def _layout_children(self, width, height):
        _place_frame_children(self, width, height)


class LinearLayout(ViewGroup):
    HORIZONTAL = 0
    VERTICAL = 1

    class LayoutParams(MarginLayoutParams):
        def __init__(self, width=WRAP_CONTENT, height=WRAP_CONTENT, weight=0.0):
            super().__init__(width, height)
            self.weight = float(weight)
            self.gravity = -1

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._orientation = LinearLayout.HORIZONTAL
        self._gravity = Gravity.TOP | Gravity.LEFT

    def setOrientation(self, value):
        self._orientation = int(value)
        self._request_layout()

    def getOrientation(self):
        return self._orientation

    def setGravity(self, value):
        self._gravity = int(value)
        self._request_layout()

    def _default_params(self):
        if self._orientation == LinearLayout.VERTICAL:
            return LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        return LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)

    def _weight(self, child):
        return getattr(child._params(), "weight", 0.0)

    def _on_measure(self, wspec, hspec):
        vertical = self._orientation == LinearLayout.VERTICAL
        pad_w, pad_h = self._pad[0] + self._pad[2], self._pad[1] + self._pad[3]
        main_total = cross_max = 0
        weighted = []
        for child in self._visible_children():
            left, top, right, bottom = self._margins(child)
            if self._weight(child) > 0:
                weighted.append(child)
            if vertical:
                self._measure_child(child, wspec, hspec, 0, main_total)
                main_total += child._measured[1] + top + bottom
                cross_max = max(cross_max, child._measured[0] + left + right)
            else:
                self._measure_child(child, wspec, hspec, main_total, 0)
                main_total += child._measured[0] + left + right
                cross_max = max(cross_max, child._measured[1] + top + bottom)
        main_spec = hspec if vertical else wspec
        if weighted and (main_spec & _MODE_MASK) != UNSPECIFIED:
            spare = (main_spec & ~_MODE_MASK) - (pad_h if vertical else pad_w) - main_total
            total_weight = sum(self._weight(child) for child in weighted)
            for child in weighted:
                share = int(spare * self._weight(child) / total_weight) if spare > 0 else 0
                size = (child._measured[1] if vertical else child._measured[0]) + share
                cw, ch = child._measured
                left, top, right, bottom = self._margins(child)
                if vertical:
                    child.measure(self._child_spec(wspec, pad_w, left + right, child._params().width), size | EXACTLY)
                else:
                    child.measure(size | EXACTLY, self._child_spec(hspec, pad_h, top + bottom, child._params().height))
            main_total += max(spare, 0)
        if vertical:
            return (_resolve(wspec, cross_max + pad_w), _resolve(hspec, main_total + pad_h))
        return (_resolve(wspec, main_total + pad_w), _resolve(hspec, cross_max + pad_h))

    def _layout_children(self, width, height):
        vertical = self._orientation == LinearLayout.VERTICAL
        pad = self._pad
        children = self._visible_children()
        main_total = 0
        for child in children:
            left, top, right, bottom = self._margins(child)
            main_total += (child._measured[1] + top + bottom) if vertical else (child._measured[0] + left + right)
        area_w, area_h = width - pad[0] - pad[2], height - pad[1] - pad[3]
        horizontal = self._gravity & Gravity.HORIZONTAL_GRAVITY_MASK
        vertical_bits = self._gravity & Gravity.VERTICAL_GRAVITY_MASK
        if vertical:
            cursor = pad[1] + (area_h - main_total if vertical_bits == Gravity.BOTTOM else
                               (area_h - main_total) // 2 if vertical_bits == Gravity.CENTER_VERTICAL else 0)
        else:
            cursor = pad[0] + (area_w - main_total if horizontal == Gravity.RIGHT else
                               (area_w - main_total) // 2 if horizontal == Gravity.CENTER_HORIZONTAL else 0)
        for child in children:
            left, top, right, bottom = self._margins(child)
            cw, ch = child._measured
            own = getattr(child._params(), "gravity", -1)
            if vertical:
                bits = (own if own >= 0 else self._gravity) & Gravity.HORIZONTAL_GRAVITY_MASK
                if bits == Gravity.CENTER_HORIZONTAL:
                    x = pad[0] + (area_w - cw) // 2 + left - right
                elif bits == Gravity.RIGHT:
                    x = width - pad[2] - cw - right
                else:
                    x = pad[0] + left
                y = cursor + top
                self._place(child, x, y, cw, ch)
                cursor += ch + top + bottom
            else:
                bits = (own if own >= 0 else self._gravity) & Gravity.VERTICAL_GRAVITY_MASK
                if bits == Gravity.CENTER_VERTICAL:
                    y = pad[1] + (area_h - ch) // 2 + top - bottom
                elif bits == Gravity.BOTTOM:
                    y = height - pad[3] - ch - bottom
                else:
                    y = pad[1] + top
                x = cursor + left
                self._place(child, x, y, cw, ch)
                cursor += cw + left + right


class ScrollView(FrameLayout):
    _KIND = "scroll"

    def _on_measure(self, wspec, hspec):
        pad_w = self._pad[0] + self._pad[2]
        content_w = content_h = 0
        for child in self._visible_children():
            left, top, right, bottom = self._margins(child)
            child.measure(self._child_spec(wspec, pad_w, left + right, child._params().width), UNSPECIFIED)
            content_w = max(content_w, child._measured[0] + left + right)
            content_h = max(content_h, child._measured[1] + top + bottom)
        return (_resolve(wspec, content_w + pad_w), _resolve(hspec, content_h + self._pad[1] + self._pad[3]))

    def _push_content_size(self):
        extent = [0, 0]
        for child in self._visible_children():
            extent[0] = max(extent[0], child._frame[0] + child._frame[2])
            extent[1] = max(extent[1], child._frame[1] + child._frame[3])
        self._push(content=extent)


class _Text(str):
    """what getText() answers: the text with the methods of CharSequence a plugin calls on it"""

    def toString(self):
        return str(self)

    def length(self):
        return len(self)


class TextView(View):
    _KIND = "text"

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._text = ""
        self._color = 0xFF000000
        self._size = 14.0
        self._bold = False
        self._gravity = Gravity.TOP | Gravity.LEFT
        self._max_width = None
        self._lines = 0
        self._ellipsize = None

    def setSingleLine(self, single=True):
        self.setMaxLines(1 if single else 0)

    def setMaxLines(self, lines):
        self._lines = max(0, int(lines))
        self._push(lines=self._lines)
        self._request_layout()

    def getMaxLines(self):
        return self._lines or 2 ** 31 - 1

    def setEllipsize(self, where):
        """what is cut at the last line is shown cut: the label of the app has no mark for it, so the choice is kept for getEllipsize only"""
        self._ellipsize = where

    def getEllipsize(self):
        return self._ellipsize

    def setText(self, text, *_ignored):
        self._text = "" if text is None else str(text)
        # the label of the app draws plain text, the spans stay here for a movement method to find a tapped link
        self._spanned = text if hasattr(text, "getSpans") else None
        self._push(text=self._text)
        self._request_layout()

    def getText(self):
        return _Text(self._text)

    _movement = None
    _spanned = None

    def setMovementMethod(self, method):
        self._movement = method
        self._push_touch()

    def getMovementMethod(self):
        return self._movement

    def _wants_touch(self):
        return self._movement is not None or super()._wants_touch()

    def onTouchEvent(self, event):
        if self._movement is not None and self._spanned is not None:
            return bool(self._movement.onTouchEvent(self, self._spanned, event))
        return False

    def _line_end(self, text, start, width):
        """the index after the last character of the line that starts at start: the longest prefix the label sets on one line, cut back to a
        space when it would split a word (the label wraps whole words)"""
        line_h = _ui.measure_text("A", self._size, self._bold, 100000)[1]
        low, high = start + 1, len(text)
        if _ui.measure_text(text[start:high], self._size, self._bold, width)[1] <= line_h:
            return high
        while low < high:
            mid = (low + high + 1) // 2
            if _ui.measure_text(text[start:mid], self._size, self._bold, width)[1] <= line_h:
                low = mid
            else:
                high = mid - 1
        if low < len(text) and text[low] != " " and text[low - 1] != " ":
            space = text.rfind(" ", start, low)
            if space > start:
                return space + 1
        return low

    def getOffsetForPosition(self, x, y):
        """the index of the character under (x, y) of the view, for text laid out from the left. -1 when the point is below the text or to
        the right of the end of its line"""
        text = self._text
        line_h = _ui.measure_text("A", self._size, self._bold, 100000)[1]
        width = max(self.getWidth() - self._pad[0] - self._pad[2], 1)
        if self._max_width is not None:
            width = min(width, max(self._max_width - self._pad[0] - self._pad[2], 1))
        row = int((y - self._pad[1]) // line_h) if line_h else 0
        if row < 0:
            return 0
        start = 0
        while True:
            newline = text.find("\n", start)
            stop = len(text) if newline < 0 else newline
            first = start
            while True:
                end = stop if first >= stop else self._line_end(text[:stop], first, width)
                if row == 0:
                    return self._column(text[first:end], first, x - self._pad[0])
                row -= 1
                if end >= stop:
                    break
                first = end
            if newline < 0:
                return -1
            start = newline + 1

    def _column(self, line, first, x):
        reach = lambda count: _ui.measure_text(line[:count], self._size, self._bold, 100000)[0]
        if not line or x < 0:
            return first
        if reach(len(line)) <= x:
            return -1
        low, high = 1, len(line)
        while low < high:
            mid = (low + high) // 2
            if reach(mid) > x:
                high = mid
            else:
                low = mid + 1
        return first + low - 1

    def setTextColor(self, color):
        self._color = _argb(color)
        self._push(color=self._color)

    def setTextSize(self, *args):
        unit, value = (args[0], args[1]) if len(args) == 2 else (TypedValue.COMPLEX_UNIT_SP, args[0])
        self._size = float(value)
        self._push(size=self._size)
        self._request_layout()

    def setTypeface(self, typeface, *_style):
        self._bold = bool(getattr(typeface, "bold", False))
        self._push(bold=self._bold)
        self._request_layout()

    def setGravity(self, value):
        self._gravity = int(value)
        self._push(gravity=self._gravity)

    def setMaxWidth(self, value):
        self._max_width = int(value)
        self._request_layout()

    def _kind_props(self):
        return {"text": self._text, "color": self._color, "size": self._size, "bold": self._bold, "gravity": self._gravity, "lines": self._lines}

    def _content_size(self, max_w, max_h):
        pad_w = self._pad[0] + self._pad[2]
        limit = max_w
        if self._max_width is not None:
            cap = self._max_width - pad_w
            limit = cap if limit is None else min(limit, cap)
        line = _ui.measure_text("A", self._size, self._bold, 100000)[1]
        if not self._text:
            return (0, line)
        width, height = _ui.measure_text(self._text, self._size, self._bold, max(limit, 1) if limit is not None else 100000)
        if self._lines:
            height = min(height, line * self._lines)
        return (width, height)


class EditText(TextView):
    _KIND = "edit"

    _hint = ""
    _hint_color = None

    def setHint(self, text):
        self._hint = str(text)
        self._push(hint=self._hint)

    def setHintTextColor(self, color):
        # the field of a dialog is drawn by the system with the hint color it picks, so the color is not applied to it
        self._hint_color = _argb(color)


class Button(TextView):
    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self.setGravity(Gravity.CENTER)
        self.setClickable(True)


class CompoundButton(LinearLayout):
    """a square and a label in a row. the square is a GradientDrawable like the track of SeekBar: outlined when off and filled with the
    accent when on, with no check mark, as the label of the app draws no glyph the old fonts are known to have. it is a layout and not a
    TextView, so isinstance(view, TextView) is false; setText, getText, setTextColor, setTextSize, setTypeface, setGravity, setMaxLines
    and setSingleLine go to the label"""

    class OnCheckedChangeListener:
        """a plugin class implements onCheckedChanged(button, checked)"""

    BOX = 22
    GAP = 8
    ACCENT = 0xFF2481CC
    EDGE = 0xFF8E8E93

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._checked = False
        self._changed = None
        self._user_click = None
        self.setOrientation(LinearLayout.HORIZONTAL)
        self._gravity = Gravity.CENTER_VERTICAL | Gravity.LEFT
        self._box = View(context)
        self._label = TextView(context)
        box_params = LinearLayout.LayoutParams(CompoundButton.BOX, CompoundButton.BOX)
        box_params.rightMargin = CompoundButton.GAP
        self.addView(self._box, box_params)
        self.addView(self._label, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        self._draw_box()
        View.setOnClickListener(self, _Toggle(self))

    def _draw_box(self):
        from android.graphics.drawable import GradientDrawable
        shape = GradientDrawable()
        shape.setCornerRadius(CompoundButton.BOX / 4.0)
        if self._checked:
            shape.setColor(CompoundButton.ACCENT)
        else:
            shape.setColor(0x00000000)
            shape.setStroke(2, CompoundButton.EDGE)
        self._box.setBackground(shape)

    def setChecked(self, value):
        value = bool(value)
        if value == self._checked:
            return
        self._checked = value
        self._draw_box()
        _call_listener(self._changed, "onCheckedChanged", self, value)

    def isChecked(self):
        return self._checked

    def toggle(self):
        self.setChecked(not self._checked)

    def setOnCheckedChangeListener(self, listener):
        self._changed = listener

    def setOnClickListener(self, listener):
        self._user_click = listener

    def hasOnClickListeners(self):
        return self._user_click is not None

    def setText(self, text, *_ignored):
        self._label.setText(text)

    def getText(self):
        return self._label.getText()

    def setTextColor(self, color):
        self._label.setTextColor(color)

    def setTextSize(self, *args):
        self._label.setTextSize(*args)

    def setTypeface(self, typeface, *style):
        self._label.setTypeface(typeface, *style)

    def setMaxLines(self, lines):
        self._label.setMaxLines(lines)

    def setSingleLine(self, single=True):
        self._label.setSingleLine(single)

    def setButtonTintList(self, _colors):
        # the square is drawn from the accent, a tint list of the theme has no state to read from
        return None


class _Toggle:
    """the click of a CompoundButton: flips the state, then tells the listener a plugin set with setOnClickListener"""

    def __init__(self, button):
        self._button = button

    def onClick(self, view):
        self._button.toggle()
        _call_listener(self._button._user_click, "onClick", self._button)


class CheckBox(CompoundButton):
    pass


class HorizontalScrollView(ScrollView):
    """the scroll view of the app moves on both axes, so only the measure differs: the child gets the height of the view and any width"""

    def _on_measure(self, wspec, hspec):
        pad_h = self._pad[1] + self._pad[3]
        content_w = content_h = 0
        for child in self._visible_children():
            left, top, right, bottom = self._margins(child)
            child.measure(UNSPECIFIED, self._child_spec(hspec, pad_h, top + bottom, child._params().height))
            content_w = max(content_w, child._measured[0] + left + right)
            content_h = max(content_h, child._measured[1] + top + bottom)
        return (_resolve(wspec, content_w + self._pad[0] + self._pad[2]), _resolve(hspec, content_h + pad_h))


class ImageView(View):
    _KIND = "image"

    class ScaleType:
        FIT_XY = "fill"
        CENTER = "center"
        CENTER_CROP = "crop"
        CENTER_INSIDE = "fit"
        FIT_CENTER = "fit"

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._bitmap = None
        self._scale = ImageView.ScaleType.FIT_CENTER

    def setScaleType(self, scale):
        self._scale = scale
        self._push(scale=scale)

    def setImageBitmap(self, bitmap):
        self._bitmap = bitmap
        if bitmap is None:
            self._push(image=False)
        elif self._attached:
            self._send_bitmap()
        self._request_layout()

    def _send_bitmap(self):
        """a picture the app keeps is shown by its handle, any other bitmap goes over as pixels"""
        handle = getattr(self._bitmap, "_handle", None)
        if handle is not None:
            _ui.emit("nimg", self._id, self._bitmap._live())
        else:
            _ui.emit("img", self._id, self._bitmap.getWidth(), self._bitmap.getHeight(), self._bitmap._base64())

    def setColorFilter(self, *args):
        """a PorterDuffColorFilter, or a color and a mode, laid over the picture. SRC_ATOP and SRC_OVER put the color on the picture
        as it is (a dimming layer); the other modes need pixels the app does not hand to python"""
        from android.graphics import ColorFilter, PorterDuff, PorterDuffColorFilter
        if len(args) == 2:
            args = (PorterDuffColorFilter(args[0], args[1]),)
        color_filter = args[0] if len(args) == 1 else None
        if color_filter is None or not isinstance(color_filter, ColorFilter):
            raise TypeError("not a color filter: %r" % (args,))
        if not isinstance(color_filter, PorterDuffColorFilter) or color_filter._mode not in (PorterDuff.Mode.SRC_ATOP, PorterDuff.Mode.SRC_OVER):
            raise NotImplementedError("an image view takes a PorterDuffColorFilter of mode SRC_ATOP or SRC_OVER")
        self._tint = color_filter._color
        self._push(tint=self._tint)

    def clearColorFilter(self):
        self._tint = 0
        self._push(tint=0)

    def setNativeSurface(self, name):
        """exteria only: shows the frames a native module publishes under this name (see core/pyhost/exteria_surface.h). the view needs
        explicit layout params, the frame size is not known to python"""
        self._surface = str(name)
        if self._attached:
            _ui.emit("native", self._id, self._surface)

    def refreshSurface(self):
        """exteria only: shows the newest frame of the surface; cheap, the pixels do not pass through python"""
        if self._attached and getattr(self, "_surface", None):
            _ui.emit("native", self._id, self._surface)

    def _kind_props(self):
        return {"scale": self._scale, "tint": getattr(self, "_tint", 0)}

    def _attach(self):
        super()._attach()
        if self._bitmap is not None:
            self._send_bitmap()

    def _content_size(self, max_w, max_h):
        if self._bitmap is None:
            return (0, 0)
        return (self._bitmap.getWidth(), self._bitmap.getHeight())


class Toast:
    LENGTH_SHORT = 0
    LENGTH_LONG = 1

    def __init__(self, text):
        self._text = text

    @staticmethod
    def makeText(context, text, duration=0):
        return Toast(str(text))

    def show(self):
        _ui.ask("ui.toast", text=self._text)


class PopupWindow(Object):
    """a view above the window. a scrim the size of the screen catches the touches outside it (and dismisses the popup when
    it is outside touchable or focusable), the content is placed inside the scrim by gravity and offsets"""

    class OnDismissListener:
        """a plugin class implements onDismiss()"""

    def __init__(self, content=None, width=WRAP_CONTENT, height=WRAP_CONTENT, focusable=False):
        self._content = content
        self._width = int(width)
        self._height = int(height)
        self._focusable = bool(focusable)
        self._outside_touchable = False
        self._on_dismiss = None
        self._scrim = None
        self._background = None

    def setContentView(self, content):
        self._content = content

    def getContentView(self):
        return self._content

    def setWidth(self, value):
        self._width = int(value)

    def setHeight(self, value):
        self._height = int(value)

    def setFocusable(self, value):
        self._focusable = bool(value)

    def setOutsideTouchable(self, value):
        self._outside_touchable = bool(value)

    def setBackgroundDrawable(self, drawable):
        self._background = drawable
        if self._content is not None:
            self._content.setBackground(drawable)

    def setOnDismissListener(self, listener):
        self._on_dismiss = listener

    def isShowing(self):
        return self._scrim is not None

    def showAtLocation(self, parent, gravity, x, y):
        self._show(gravity, x, y)

    def showAsDropDown(self, anchor, x_offset=0, y_offset=0, *_gravity):
        """below the anchor, left edges aligned, as android; the anchor position is read in the window of the decor"""
        origin = [0, 0]
        anchor.getLocationInWindow(origin)
        self._show(Gravity.TOP | Gravity.LEFT, origin[0] + int(x_offset), origin[1] + anchor.getHeight() + int(y_offset))

    def _show(self, gravity, x, y):
        if self._content is None:
            raise ValueError("a popup needs a content view")
        if self._scrim is not None:
            self.dismiss()
        from android.app import activity
        decor = activity().getWindow().getDecorView()
        scrim = FrameLayout(decor.getContext())
        if self._focusable or self._outside_touchable:
            scrim.setOnClickListener(lambda _view: self.dismiss())
        if self._background is not None:
            self._content.setBackground(self._background)
        params = FrameLayout.LayoutParams(self._width, self._height, int(gravity))
        left = int(x) if int(gravity) & Gravity.HORIZONTAL_GRAVITY_MASK in (0, Gravity.LEFT) else 0
        top = int(y) if int(gravity) & Gravity.VERTICAL_GRAVITY_MASK in (0, Gravity.TOP) else 0
        params.setMargins(left, top, 0, 0)
        scrim.addView(self._content, params)
        decor.addView(scrim, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        self._scrim = scrim

    def dismiss(self):
        scrim, self._scrim = self._scrim, None
        if scrim is None:
            return
        scrim.removeView(self._content)
        parent = scrim.getParent()
        if parent is not None:
            parent.removeView(scrim)
        listener = self._on_dismiss
        if listener is not None:
            method = getattr(listener, "onDismiss", None)
            (method if method is not None else listener)()


class SeekBar(FrameLayout):
    """a track view and a fill view of the width of the progress inside a frame. a touch sets the progress from the x of the finger"""

    class OnSeekBarChangeListener:
        """a plugin class implements onProgressChanged(bar, progress, from_user), onStartTrackingTouch(bar) and onStopTrackingTouch(bar)"""

    HEIGHT = 4
    DEFAULT_WIDTH = 160

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._max = 100
        self._progress = 0
        self._listener = None
        self._drag = False
        self._track = View(context)
        self._fill = View(context)
        self.addView(self._track, FrameLayout.LayoutParams(MATCH_PARENT, SeekBar.HEIGHT, Gravity.CENTER_VERTICAL))
        self.addView(self._fill, FrameLayout.LayoutParams(0, SeekBar.HEIGHT, Gravity.CENTER_VERTICAL | Gravity.LEFT))
        self.setProgressTintColor(0xFF2481CC)
        self.setTrackTintColor(0x33808080)
        self.setOnTouchListener(self._touch)

    def _bar(self, view, color):
        from android.graphics.drawable import GradientDrawable
        shape = GradientDrawable()
        shape.setCornerRadius(SeekBar.HEIGHT / 2.0)
        shape.setColor(color)
        view.setBackground(shape)

    def setProgressTintColor(self, color):
        self._bar(self._fill, color)

    def setTrackTintColor(self, color):
        self._bar(self._track, color)

    def setMax(self, value):
        self._max = max(int(value), 1)
        self._progress = min(self._progress, self._max)
        self._request_layout()

    def getMax(self):
        return self._max

    def setProgress(self, value, *_animate):
        self._set(int(value), False)

    def getProgress(self):
        return self._progress

    def setOnSeekBarChangeListener(self, listener):
        self._listener = listener

    def _set(self, value, from_user):
        value = max(0, min(value, self._max))
        if value == self._progress:
            return
        self._progress = value
        self._request_layout()
        if self._listener is not None:
            _call_listener(self._listener, "onProgressChanged", self, value, from_user)

    def _on_measure(self, wspec, hspec):
        width = _resolve(wspec, SeekBar.DEFAULT_WIDTH)
        self._fill.getLayoutParams().width = int(round(width * self._progress / self._max))
        return super()._on_measure(wspec, hspec)

    def _touch(self, view, event):
        action = event.getAction()
        if action == MotionEvent.ACTION_DOWN:
            self._drag = True
            _call_listener(self._listener, "onStartTrackingTouch", self)
        if self._drag:
            self._set(round(self._max * min(max(event.getX() / max(self.getWidth(), 1), 0.0), 1.0)), True)
        if action in (MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL) and self._drag:
            self._drag = False
            _call_listener(self._listener, "onStopTrackingTouch", self)
        return True


def _call_listener(listener, name, *args):
    method = getattr(listener, name, None) if listener is not None else None
    if method is not None:
        return method(*args)
    return None
