"""android.view over the view bridge of android/_ui.py.

the tree, the layout and the property values live here. every change is queued for uikit and sent when the entry point that
called python returns. layout follows android: measure with specs, then place by gravity and margins, so getWidth,
getHeight and getLocationInWindow answer what a plugin expects. not implemented: drawing a view into a canvas,
long press, focus, and anything that needs the views of the host app, which has none the plugin can reach"""

from android import _ui
from java.lang import IllegalStateException, Object

UNSPECIFIED = 0
EXACTLY = 1 << 30
AT_MOST = 2 << 30
_MODE_MASK = 3 << 30

MATCH_PARENT = -1
WRAP_CONTENT = -2


def _argb(color):
    return int(color) & 0xFFFFFFFF


class HapticFeedbackConstants:
    LONG_PRESS = 0
    VIRTUAL_KEY = 1
    KEYBOARD_TAP = 3


class Gravity:
    NO_GRAVITY = 0
    CENTER_HORIZONTAL = 1
    CENTER_VERTICAL = 16
    LEFT = 3
    RIGHT = 5
    TOP = 48
    BOTTOM = 80
    START = 0x800003
    END = 0x800005
    CENTER = 17
    FILL = 119
    HORIZONTAL_GRAVITY_MASK = 7
    VERTICAL_GRAVITY_MASK = 112


class Surface:
    ROTATION_0 = 0
    ROTATION_90 = 1
    ROTATION_180 = 2
    ROTATION_270 = 3


class Display:
    def getRotation(self):
        return Surface.ROTATION_0


class WindowInsets:
    def getSystemWindowInsetTop(self):
        return int(_ui.screen().get("top", 0))

    def getSystemWindowInsetBottom(self):
        return int(_ui.screen().get("bottom", 0))

    def getSystemWindowInsetLeft(self):
        return 0

    def getSystemWindowInsetRight(self):
        return 0


class MotionEvent(Object):
    ACTION_DOWN = 0
    ACTION_UP = 1
    ACTION_MOVE = 2
    ACTION_CANCEL = 3
    ACTION_MASK = 0xFF

    def __init__(self, action, raw_x, raw_y, view=None, down_time=0.0, event_time=0.0):
        self._action = int(action)
        self._raw_x = float(raw_x)
        self._raw_y = float(raw_y)
        self._view = view
        self._down_time = down_time
        self._event_time = event_time

    def getAction(self):
        return self._action

    def getActionMasked(self):
        return self._action & self.ACTION_MASK

    def getRawX(self):
        return self._raw_x

    def getRawY(self):
        return self._raw_y

    def getX(self):
        if self._view is None:
            return self._raw_x
        return self._raw_x - self._view._origin()[0]

    def getY(self):
        if self._view is None:
            return self._raw_y
        return self._raw_y - self._view._origin()[1]

    def getPointerCount(self):
        return 1

    def getEventTime(self):
        return int(self._event_time * 1000)

    def getDownTime(self):
        return int(self._down_time * 1000)


class LayoutParams(Object):
    MATCH_PARENT = MATCH_PARENT
    WRAP_CONTENT = WRAP_CONTENT

    def __init__(self, width=WRAP_CONTENT, height=WRAP_CONTENT):
        if isinstance(width, LayoutParams):
            width, height = width.width, width.height
        self.width = int(width)
        self.height = int(height)


class MarginLayoutParams(LayoutParams):
    def __init__(self, width=WRAP_CONTENT, height=WRAP_CONTENT):
        source = width if isinstance(width, MarginLayoutParams) else None
        super().__init__(width, height)
        self.leftMargin = source.leftMargin if source else 0
        self.topMargin = source.topMargin if source else 0
        self.rightMargin = source.rightMargin if source else 0
        self.bottomMargin = source.bottomMargin if source else 0

    def setMargins(self, left, top, right, bottom):
        self.leftMargin, self.topMargin = int(left), int(top)
        self.rightMargin, self.bottomMargin = int(right), int(bottom)


class _MeasureSpec:
    UNSPECIFIED = UNSPECIFIED
    EXACTLY = EXACTLY
    AT_MOST = AT_MOST

    @staticmethod
    def makeMeasureSpec(size, mode):
        return (int(size) & ~_MODE_MASK) | int(mode)

    @staticmethod
    def getMode(spec):
        return spec & _MODE_MASK

    @staticmethod
    def getSize(spec):
        return spec & ~_MODE_MASK


def _resolve(spec, desired):
    mode, size = spec & _MODE_MASK, spec & ~_MODE_MASK
    if mode == EXACTLY:
        return size
    if mode == AT_MOST:
        return min(desired, size)
    return desired


def _call(listener, name, *args):
    method = getattr(listener, name, None)
    if method is not None:
        return method(*args)
    return listener(*args)


_dirty_roots = set()


def _laid_out(root):
    observer = getattr(root, "_observer", None)
    if observer is not None:
        observer.dispatchOnGlobalLayout()


def _layout_pass():
    for root in list(_dirty_roots):
        _dirty_roots.discard(root)
        root._layout_root()
        _laid_out(root)


_ui.on_flush(_layout_pass)

_draw_dirty = set()
# the biggest picture a view paints for itself: 4 megapixels is 16 MB of rgba, and the base64 of it goes to the app
MAX_DRAW_PIXELS = 4 * 1024 * 1024


def _draw_pass():
    """paint the views that draw themselves and are dirty, after the layout pass gave them a size"""
    import sys
    import traceback
    from android.graphics import Bitmap, Canvas
    for view in list(_draw_dirty):
        _draw_dirty.discard(view)
        if not view._attached:
            continue
        width, height = view._frame[2], view._frame[3]
        if width <= 0 or height <= 0:
            _draw_dirty.add(view)
            continue
        if width * height > MAX_DRAW_PIXELS:
            sys.stderr.write("E/View: %s is %dx%d, larger than the %d pixels a view paints for itself\n" % (
                type(view).__name__, width, height, MAX_DRAW_PIXELS))
            continue
        bitmap = Bitmap(width, height)
        try:
            view.draw(Canvas(bitmap))
        except Exception:
            # a view whose onDraw fails keeps what it drew; the next invalidate tries again
            traceback.print_exc(file=sys.stderr)
        _ui.emit("img", view._id, width, height, bitmap._base64())


_ui.on_flush(_draw_pass)


class View(Object):
    VISIBLE = 0
    INVISIBLE = 4
    GONE = 8
    MeasureSpec = _MeasureSpec
    NO_ID = -1

    class OnClickListener:
        pass

    class OnTouchListener:
        pass

    class OnLongClickListener:
        pass

    class OnAttachStateChangeListener:
        """a program implements onViewAttachedToWindow(view) and onViewDetachedFromWindow(view)"""

    class OnLayoutChangeListener:
        """a program implements onLayoutChange(view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom)"""

    class OnScrollChangeListener:
        """a program implements onScrollChange(view, scrollX, scrollY, oldScrollX, oldScrollY)"""

    _KIND = "view"

    def __init__(self, context=None, *_ignored):
        self._context = context
        self._id = _ui.new_id()
        self._view_id = View.NO_ID
        self._parent = None
        self._attached = False
        self._alpha = 1.0
        self._tx = self._ty = 0.0
        self._sx = self._sy = 1.0
        self._rot = 0.0
        self._elevation = 0.0
        self._vis = View.VISIBLE
        self._clickable = False
        self._enabled = True
        self._bg = None
        self._pad = [0, 0, 0, 0]
        self._lp = None
        self._frame = (0, 0, 0, 0)
        self._pushed_frame = None
        self._measured = (0, 0)
        self._tag = None
        self._on_click = None
        self._on_touch = None
        self._on_long_click = None
        self._attach_listeners = []
        self._layout_listeners = []
        self._measured_set = None
        self._animator = None

    # identity and tree

    def getViewTreeObserver(self):
        """one observer for the tree, kept by its root; it reports the layout passes of python"""
        root = self.getRootView()
        if getattr(root, "_observer", None) is None:
            root._observer = ViewTreeObserver()
        return root._observer

    def getContext(self):
        return self._context

    def getParent(self):
        return self._parent

    def getId(self):
        return self._view_id

    def setId(self, value):
        self._view_id = int(value)

    def findViewById(self, value):
        return self if self._view_id == value else None

    def setTag(self, tag, *_key):
        self._tag = tag

    def getTag(self, *_key):
        return self._tag

    def isAttachedToWindow(self):
        return self._attached

    def isShown(self):
        """attached, and neither it nor a parent is invisible or gone; the root of a native page also has to be on screen"""
        view = self
        while view is not None:
            if not view._attached or view._vis != View.VISIBLE or not getattr(view, "_shown", True):
                return False
            view = view._parent
        return True

    def setContentDescription(self, text):
        self._description = None if text is None else str(text)

    def getContentDescription(self):
        return getattr(self, "_description", None)

    def getRootView(self):
        view = self
        while view._parent is not None:
            view = view._parent
        return view

    def getRootWindowInsets(self):
        return WindowInsets()

    def getDisplay(self):
        return Display()

    # layout params, padding

    def getLayoutParams(self):
        return self._lp

    def setLayoutParams(self, params):
        self._lp = params
        self._request_layout()

    def _params(self):
        if self._lp is None:
            self._lp = self._default_params()
        return self._lp

    def _default_params(self):
        return MarginLayoutParams(WRAP_CONTENT, WRAP_CONTENT)

    def setPadding(self, left, top, right, bottom):
        self._pad = [int(left), int(top), int(right), int(bottom)]
        self._push(pad=self._pad)
        self._request_layout()

    def getPaddingLeft(self):
        return self._pad[0]

    def getPaddingTop(self):
        return self._pad[1]

    def getPaddingRight(self):
        return self._pad[2]

    def getPaddingBottom(self):
        return self._pad[3]

    # appearance

    def setVisibility(self, value):
        value = int(value)
        if value == self._vis:
            return
        was_gone = self._vis == View.GONE
        self._vis = value
        self._push(vis=value)
        if was_gone or value == View.GONE:
            self._request_layout()

    def getVisibility(self):
        return self._vis

    def setAlpha(self, value):
        self._alpha = float(value)
        self._push(alpha=self._alpha)

    def getAlpha(self):
        return self._alpha

    def setTranslationX(self, value):
        self._tx = float(value)
        self._push(tx=self._tx)

    def setTranslationY(self, value):
        self._ty = float(value)
        self._push(ty=self._ty)

    def getTranslationX(self):
        return self._tx

    def getTranslationY(self):
        return self._ty

    def setScaleX(self, value):
        self._sx = float(value)
        self._push(sx=self._sx)

    def setScaleY(self, value):
        self._sy = float(value)
        self._push(sy=self._sy)

    def getScaleX(self):
        return self._sx

    def getScaleY(self):
        return self._sy

    def setRotation(self, value):
        self._rot = float(value)
        self._push(rot=self._rot)

    def getRotation(self):
        return self._rot

    def setElevation(self, value):
        self._elevation = float(value)
        self._push(elev=self._elevation)

    def getElevation(self):
        return self._elevation

    def setBackground(self, drawable):
        old = self._bg
        if old is not None and hasattr(old, "_owners") and self in old._owners:
            old._owners.remove(self)
        self._bg = drawable
        if drawable is not None and hasattr(drawable, "_owners"):
            drawable._owners.append(self)
        self._push(bg=self._encode_bg())
        self._sync_bitmap_bg()

    setBackgroundDrawable = setBackground

    def setBackgroundColor(self, color):
        from android.graphics.drawable import ColorDrawable
        self.setBackground(ColorDrawable(color))

    def getBackground(self):
        return self._bg

    def setOutlineProvider(self, provider):
        self._outline = provider
        self._push_clip()

    def getOutlineProvider(self):
        return getattr(self, "_outline", None)

    def setClipToOutline(self, value):
        self._clip_to_outline = bool(value)
        self._push_clip()

    def getClipToOutline(self):
        return getattr(self, "_clip_to_outline", False)

    outlineProvider = property(getOutlineProvider, setOutlineProvider)
    clipToOutline = property(getClipToOutline, setClipToOutline)

    def _clip_radius(self):
        provider = self.getOutlineProvider()
        return float(provider.radius) if provider is not None and self.getClipToOutline() else 0.0

    def _push_clip(self):
        self._push(clip=self._clip_radius())

    def _encode_bg(self):
        if self._draws_itself():
            return None
        return self._bg._encode() if self._bg is not None else None

    def _bg_changed(self):
        self._push(bg=self._encode_bg())
        self._sync_bitmap_bg()

    def _sync_bitmap_bg(self):
        """a bitmap drawable is pixels on the layer of the view, the same op an ImageView uses. an ImageView draws its own bitmap"""
        render = getattr(self._bg, "_rendered", None)
        if render is None or not self._attached or self._KIND == "image":
            return
        bitmap = render()
        _ui.emit("img", self._id, bitmap.getWidth(), bitmap.getHeight(), bitmap._base64())

    # input

    def setClickable(self, value):
        self._clickable = bool(value)
        self._push_touch()

    def isClickable(self):
        return self._clickable

    def setEnabled(self, value):
        self._enabled = bool(value)

    def isEnabled(self):
        return self._enabled

    def setOnClickListener(self, listener):
        self._on_click = listener
        if listener is not None:
            self._clickable = True
        self._push_touch()

    def setOnTouchListener(self, listener):
        self._on_touch = listener
        self._push_touch()

    def hasOnClickListeners(self):
        return self._on_click is not None

    def performClick(self):
        if self._on_click is None:
            return False
        _call(self._on_click, "onClick", self)
        return True

    def performHapticFeedback(self, *_args):
        # the phones this runs on have no haptic engine, nothing was felt
        return False

    def _wants_touch(self):
        return (self._clickable or self._on_touch is not None or self._on_click is not None
                or self._on_long_click is not None or type(self).onTouchEvent is not View.onTouchEvent)

    def _push_touch(self):
        self._push(touch=self._wants_touch())

    # handler helpers

    def post(self, runnable):
        from android.os import Handler
        return Handler().post(runnable)

    def postDelayed(self, runnable, delay):
        from android.os import Handler
        return Handler().postDelayed(runnable, delay)

    def removeCallbacks(self, runnable):
        from android.os import Handler
        Handler().removeCallbacks(runnable)

    def startAnimation(self, animation):
        self.clearAnimation()
        self._animation = animation
        animation.start(self)

    def clearAnimation(self):
        if getattr(self, "_animation", None) is not None:
            self._animation.cancel()
            self._animation = None

    def getAnimation(self):
        return getattr(self, "_animation", None)

    def animate(self):
        if self._animator is None:
            self._animator = ViewPropertyAnimator(self)
        return self._animator

    def bringToFront(self):
        parent = self._parent
        if parent is not None:
            parent.removeView(self)
            parent.addView(self)

    def invalidate(self, *_region):
        """a view that draws itself (it overrides onDraw or draw) is painted again, into a bitmap the app shows on its layer,
        when the entry point that called python returns. the app draws nothing else for such a view: its background is drawn here too"""
        if self._draws_itself():
            _draw_dirty.add(self)

    postInvalidate = postInvalidateOnAnimation = invalidate

    def _draws_itself(self):
        cls = type(self)
        return self._KIND != "image" and (cls.onDraw is not View.onDraw or cls.draw is not View.draw
                                          or cls.dispatchDraw is not View.dispatchDraw)

    def draw(self, canvas):
        """background, then onDraw, then the children (they are layers of their own here), then the foreground"""
        background = self._bg
        if background is not None and hasattr(background, "draw") and getattr(type(background), "draw", None) is not None:
            width, height = self._frame[2], self._frame[3]
            background.setBounds(0, 0, width, height)
            try:
                background.draw(canvas)
            except NotImplementedError:
                pass
        self.onDraw(canvas)
        self.dispatchDraw(canvas)
        self.onDrawForeground(canvas)

    def onDraw(self, canvas):
        return None

    def dispatchDraw(self, canvas):
        return None

    def onDrawForeground(self, canvas):
        return None

    def onAttachedToWindow(self):
        return None

    def onDetachedFromWindow(self):
        return None

    def onSizeChanged(self, width, height, old_width, old_height):
        return None

    def onWindowVisibilityChanged(self, visibility):
        return None

    def onTouchEvent(self, event):
        return False

    def dispatchTouchEvent(self, event):
        taken = False
        if self._on_touch is not None:
            taken = bool(_call(self._on_touch, "onTouch", self, event))
        return taken or bool(self.onTouchEvent(event))

    def onMeasure(self, wspec, hspec):
        self.setMeasuredDimension(*self._on_measure(wspec, hspec))

    def setMeasuredDimension(self, width, height):
        self._measured_set = (int(width), int(height))

    def onLayout(self, changed, left, top, right, bottom):
        return None

    def layout(self, left, top, right, bottom):
        parent = self._parent
        if parent is not None:
            parent._place(self, left, top, right - left, bottom - top)

    def setFocusable(self, value):
        self._focusable = bool(value)

    def isFocusable(self):
        return getattr(self, "_focusable", False)

    setFocusableInTouchMode = setFocusable

    def setLongClickable(self, value):
        self._long_clickable = bool(value)

    def isLongClickable(self):
        return getattr(self, "_long_clickable", False) or self._on_long_click is not None

    def setOnLongClickListener(self, listener):
        self._on_long_click = listener
        self._push_touch()

    def addOnAttachStateChangeListener(self, listener):
        self._attach_listeners.append(listener)

    def removeOnAttachStateChangeListener(self, listener):
        if listener in self._attach_listeners:
            self._attach_listeners.remove(listener)

    def addOnLayoutChangeListener(self, listener):
        self._layout_listeners.append(listener)

    def removeOnLayoutChangeListener(self, listener):
        if listener in self._layout_listeners:
            self._layout_listeners.remove(listener)

    def getResources(self):
        from android.content.res import Resources
        return Resources.getSystem()

    def getGlobalVisibleRect(self, rect, offset=None):
        x, y = self._origin()
        width, height = self._frame[2], self._frame[3]
        screen = _ui.screen()
        left, top = max(0, int(x)), max(0, int(y))
        right, bottom = min(int(screen["w"]), int(x) + width), min(int(screen["h"]), int(y) + height)
        rect.set(left, top, right, bottom)
        return right > left and bottom > top

    def getSystemUiVisibility(self):
        return getattr(self, "_system_ui", 0)

    def setSystemUiVisibility(self, value):
        self._system_ui = int(value)

    def setLayerType(self, layer_type, paint=None):
        self._layer_type = layer_type

    def getLayerType(self):
        return getattr(self, "_layer_type", 0)

    def requestFocus(self, *_args):
        return False

    def clearFocus(self):
        return None

    def hasFocus(self):
        return False

    def getWindowToken(self):
        return None

    def requestRectangleOnScreen(self, rect, immediate=False):
        return False

    def setRenderEffect(self, effect):
        """a blur is drawn by the app over the view and what it holds (see apply_blur in exteria_plugin_ui.m); None takes it away"""
        radius = 0.0 if effect is None else effect._blur_radius()
        self._render_effect = effect
        self._push(blur=radius)

    def getRenderEffect(self):
        return getattr(self, "_render_effect", None)

    def requestLayout(self):
        self._request_layout()

    # geometry

    def _ensure_layout(self):
        root = self.getRootView()
        if root in _dirty_roots:
            _dirty_roots.discard(root)
            root._layout_root()
            _laid_out(root)

    def getLeft(self):
        self._ensure_layout()
        return self._frame[0]

    def getTop(self):
        self._ensure_layout()
        return self._frame[1]

    def getWidth(self):
        self._ensure_layout()
        return self._frame[2]

    def getHeight(self):
        self._ensure_layout()
        return self._frame[3]

    def getRight(self):
        return self.getLeft() + self.getWidth()

    def getBottom(self):
        return self.getTop() + self.getHeight()

    def getX(self):
        return self.getLeft() + self._tx

    def getY(self):
        return self.getTop() + self._ty

    def getMeasuredWidth(self):
        return self._measured[0]

    def getMeasuredHeight(self):
        return self._measured[1]

    def getScrollX(self):
        return 0

    def getScrollY(self):
        return 0

    def measure(self, wspec, hspec):
        if type(self).onMeasure is View.onMeasure:
            self._measured = self._on_measure(wspec, hspec)
            return
        self._measured_set = None
        self.onMeasure(wspec, hspec)
        if self._measured_set is None:
            raise IllegalStateException("onMeasure of %s did not call setMeasuredDimension" % type(self).__name__)
        self._measured = self._measured_set

    def _content_size(self, max_w, max_h):
        return (0, 0)

    def _on_measure(self, wspec, hspec):
        pad_w = self._pad[0] + self._pad[2]
        pad_h = self._pad[1] + self._pad[3]
        mode_w, mode_h = wspec & _MODE_MASK, hspec & _MODE_MASK
        max_w = (wspec & ~_MODE_MASK) - pad_w if mode_w != UNSPECIFIED else None
        max_h = (hspec & ~_MODE_MASK) - pad_h if mode_h != UNSPECIFIED else None
        cw, ch = self._content_size(max_w, max_h)
        return (_resolve(wspec, cw + pad_w), _resolve(hspec, ch + pad_h))

    def _origin(self):
        """top left corner in the window, translation included"""
        self._ensure_layout()
        x = y = 0.0
        view = self
        while view is not None and view._parent is not None:
            x += view._frame[0] + view._tx - view._parent._scroll_offset()[0]
            y += view._frame[1] + view._ty - view._parent._scroll_offset()[1]
            view = view._parent
        return (x, y)

    def getLocationInWindow(self, out):
        x, y = self._origin()
        out[0], out[1] = int(round(x)), int(round(y))

    getLocationOnScreen = getLocationInWindow

    def _scroll_offset(self):
        return (0, 0)

    def _request_layout(self):
        root = self.getRootView()
        if root._attached:
            _dirty_roots.add(root)

    # bridge

    def _initial_props(self):
        props = {"pad": self._pad, "alpha": self._alpha, "vis": self._vis, "touch": self._wants_touch(),
                 "tx": self._tx, "ty": self._ty, "sx": self._sx, "sy": self._sy, "rot": self._rot,
                 "elev": self._elevation, "bg": self._encode_bg(), "clip": self._clip_radius()}
        props.update(self._kind_props())
        effect = getattr(self, "_render_effect", None)
        if effect is not None:
            props["blur"] = effect._blur_radius()
        return props

    def _kind_props(self):
        return {}

    def _push(self, **props):
        if self._attached:
            _ui.set_props(self._id, props)

    def _attach(self):
        self._attached = True
        _ui.register(self._id, self)
        _ui.emit("new", self._id, self._KIND)
        _ui.set_props(self._id, self._initial_props())
        self._sync_bitmap_bg()
        self._pushed_frame = None
        if self._draws_itself():
            _draw_dirty.add(self)
        for listener in list(self._attach_listeners):
            _call(listener, "onViewAttachedToWindow", self)
        self.onAttachedToWindow()

    def _detach(self):
        self._attached = False
        _ui.forget(self._id)
        self._pushed_frame = None
        _draw_dirty.discard(self)
        self.onDetachedFromWindow()
        for listener in list(self._attach_listeners):
            _call(listener, "onViewDetachedFromWindow", self)

    def _layout_root(self):
        pass

    def _frame_changed(self, old, frame):
        old = old or (0, 0, 0, 0)
        if (old[2], old[3]) != (frame[2], frame[3]):
            self.onSizeChanged(frame[2], frame[3], old[2], old[3])
            if self._draws_itself():
                _draw_dirty.add(self)
            if getattr(self._bg, "_sized", False):
                self._sync_bitmap_bg()
        for listener in list(self._layout_listeners):
            _call(listener, "onLayoutChange", self, frame[0], frame[1], frame[0] + frame[2], frame[1] + frame[3],
                  old[0], old[1], old[0] + old[2], old[1] + old[3])


class ViewPropertyAnimator(Object):
    def __init__(self, view):
        self._view = view
        self._reset()

    def _reset(self):
        self._targets = {}
        self._duration = 300
        self._delay = 0
        self._curve = "decel"
        self._end = None

    def translationX(self, value):
        self._targets["tx"] = float(value)
        return self

    def translationY(self, value):
        self._targets["ty"] = float(value)
        return self

    def translationXBy(self, value):
        self._targets["tx"] = self._targets.get("tx", self._view._tx) + float(value)
        return self

    def translationYBy(self, value):
        self._targets["ty"] = self._targets.get("ty", self._view._ty) + float(value)
        return self

    def scaleX(self, value):
        self._targets["sx"] = float(value)
        return self

    def scaleY(self, value):
        self._targets["sy"] = float(value)
        return self

    def alpha(self, value):
        self._targets["alpha"] = float(value)
        return self

    def rotation(self, value):
        self._targets["rot"] = float(value)
        return self

    def setDuration(self, ms):
        self._duration = int(ms)
        return self

    def setStartDelay(self, ms):
        self._delay = int(ms)
        return self

    def setInterpolator(self, interpolator):
        self._curve = getattr(interpolator, "curve", "decel")
        return self

    def withEndAction(self, runnable):
        self._end = runnable
        return self

    def cancel(self):
        if self._view._attached:
            _ui.emit("stop", self._view._id)
        self._reset()

    def start(self):
        view, targets = self._view, self._targets
        names = {"tx": "_tx", "ty": "_ty", "sx": "_sx", "sy": "_sy", "alpha": "_alpha", "rot": "_rot"}
        for key, value in targets.items():
            setattr(view, names[key], value)
        end, duration, delay = self._end, self._duration, self._delay
        if view._attached:
            _ui.emit("anim", view._id, dict(targets), duration, delay, self._curve)
        else:
            view._push(**targets)
        if end is not None:
            from android.os import Handler
            Handler().postDelayed(end, duration + delay)
        self._reset()


class ViewGroup(View):
    LayoutParams = LayoutParams
    MarginLayoutParams = MarginLayoutParams

    def __init__(self, context=None, *args):
        super().__init__(context, *args)
        self._children = []

    def _default_params(self):
        return LayoutParams(WRAP_CONTENT, WRAP_CONTENT)

    def addView(self, child, *args):
        index, params = -1, None
        for arg in args:
            if isinstance(arg, LayoutParams):
                params = arg
            elif isinstance(arg, int):
                index = arg
        if child._parent is not None:
            raise ValueError("the view already has a parent")
        if params is not None:
            child._lp = params
        child._parent = self
        if index < 0 or index > len(self._children):
            index = len(self._children)
        self._children.insert(index, child)
        if self._attached:
            self._attach_subtree(child, index)
        self._request_layout()

    def _attach_subtree(self, child, index):
        child._attach()
        if isinstance(child, ViewGroup):
            for position, grandchild in enumerate(child._children):
                child._attach_subtree(grandchild, position)
        _ui.emit("add", self._id, child._id, index)

    def removeView(self, child):
        if child not in self._children:
            return
        self._children.remove(child)
        child._parent = None
        if self._attached:
            self._detach_subtree(child)
            _ui.emit("rm", child._id)
        self._request_layout()

    def removeViewAt(self, index):
        self.removeView(self._children[index])

    def removeAllViews(self):
        for child in list(self._children):
            self.removeView(child)

    def _detach_subtree(self, view):
        view._detach()
        if isinstance(view, ViewGroup):
            for child in view._children:
                self._detach_subtree(child)

    def getChildCount(self):
        return len(self._children)

    def getChildAt(self, index):
        return self._children[index] if 0 <= index < len(self._children) else None

    def indexOfChild(self, child):
        return self._children.index(child) if child in self._children else -1

    def findViewById(self, value):
        if self._view_id == value:
            return self
        for child in self._children:
            found = child.findViewById(value)
            if found is not None:
                return found
        return None

    def bringChildToFront(self, child):
        if child in self._children:
            self.removeView(child)
            self.addView(child)

    def _visible_children(self):
        return [child for child in self._children if child._vis != View.GONE]

    def _child_spec(self, spec, padding, margins, dimension):
        mode, size = spec & _MODE_MASK, spec & ~_MODE_MASK
        avail = max(0, size - padding - margins)
        if dimension >= 0:
            return (dimension & ~_MODE_MASK) | EXACTLY
        if dimension == MATCH_PARENT:
            return (avail | EXACTLY) if mode in (EXACTLY, AT_MOST) else UNSPECIFIED
        return (avail | AT_MOST) if mode != UNSPECIFIED else UNSPECIFIED

    def _margins(self, child):
        params = child._params()
        if isinstance(params, MarginLayoutParams):
            return (params.leftMargin, params.topMargin, params.rightMargin, params.bottomMargin)
        return (0, 0, 0, 0)

    def _measure_child(self, child, wspec, hspec, used_w=0, used_h=0):
        left, top, right, bottom = self._margins(child)
        params = child._params()
        pw, ph = self._pad[0] + self._pad[2], self._pad[1] + self._pad[3]
        child.measure(self._child_spec(wspec, pw + used_w, left + right, params.width),
                      self._child_spec(hspec, ph + used_h, top + bottom, params.height))

    def _layout_children(self, width, height):
        pass

    def _place(self, child, left, top, width, height):
        child._frame = (int(left), int(top), int(width), int(height))
        if isinstance(child, ViewGroup):
            child._do_layout(int(width), int(height))

    def _layout_root(self):
        screen = _ui.screen()
        width, height = int(screen["w"]), int(screen["h"])
        self.measure(width | EXACTLY, height | EXACTLY)
        self._frame = (0, 0, width, height)
        self._do_layout(width, height)
        self._push_frames()

    def _do_layout(self, width, height):
        """a program that extends ViewGroup lays its children out in onLayout, with child.layout(l, t, r, b); the shims
        lay out their own in _layout_children"""
        if type(self).onLayout is not View.onLayout:
            self.onLayout(True, 0, 0, int(width), int(height))
        else:
            self._layout_children(width, height)

    def _push_frames(self):
        for child in self._children:
            frame = child._frame
            if child._attached and frame != child._pushed_frame:
                old = child._pushed_frame
                child._pushed_frame = frame
                _ui.set_props(child._id, {"x": frame[0], "y": frame[1], "w": frame[2], "h": frame[3]})
                child._frame_changed(old, frame)
            if isinstance(child, ViewGroup):
                child._push_frames()
                child._push_content_size()

    def _push_content_size(self):
        pass


class SurfaceView(View):
    """named so a plugin can test for it; there is no video surface behind it"""


class TextureView(View):
    """named so a plugin can test for it; there is no video surface behind it"""


class DecorView(ViewGroup):
    """the overlay the app lays above its windows. it is the root of every tree a plugin can reach"""

    _KIND = "view"

    def __init__(self, context=None):
        super().__init__(context)
        self._id = _ui.ROOT
        self._attached = True
        _ui.register(_ui.ROOT, self)

    def _default_params(self):
        return LayoutParams(MATCH_PARENT, MATCH_PARENT)

    def _measure_child(self, child, wspec, hspec, used_w=0, used_h=0):
        super()._measure_child(child, wspec, hspec, used_w, used_h)

    def _on_measure(self, wspec, hspec):
        for child in self._visible_children():
            self._measure_child(child, wspec, hspec)
        return (wspec & ~_MODE_MASK, hspec & ~_MODE_MASK)

    def _layout_children(self, width, height):
        _place_frame_children(self, width, height)

    def _request_layout(self):
        _dirty_roots.add(self)


class PageView(DecorView):
    """the root of the views a plugin puts on a page of the app itself (the settings tab). the page owns a transparent layer under its
    table and registers it under page_id, so what python adds to this root appears there. the size is the one the page reports, since
    the layer is laid out by uikit and not by python"""

    def __init__(self, context, page_id):
        ViewGroup.__init__(self, context)
        self._id = page_id
        self._attached = True
        self._size = (0, 0)
        self._shown = False
        _ui.register(page_id, self)

    def _layout_root(self):
        width, height = self._size
        self.measure(width | EXACTLY, height | EXACTLY)
        self._frame = (0, 0, width, height)
        self._do_layout(width, height)
        self._push_frames()

    def resize(self, width, height):
        if (int(width), int(height)) != self._size:
            self._size = (int(width), int(height))
            self._request_layout()

    def rebind(self):
        """the page made its layer again: the views of the plugin are sent to it once more, in their order"""
        children = list(self._children)
        for child in children:
            self._detach_subtree(child)
        for position, child in enumerate(children):
            self._attach_subtree(child, position)
        self._request_layout()

    def setShown(self, shown):
        self._shown = bool(shown)


def _gravity_of(params, default):
    # a WindowManager.LayoutParams keeps the gravity the plugin set (0 means the center for a window) and the one the layout uses apart
    gravity = getattr(params, "_layout_gravity", None)
    if gravity is None:
        gravity = getattr(params, "gravity", -1)
    return default if gravity is None or gravity < 0 else gravity


def _place_frame_children(group, width, height):
    pad = group._pad
    for child in group._visible_children():
        params = child._params()
        left_m, top_m, right_m, bottom_m = group._margins(child)
        cw, ch = child._measured
        gravity = _gravity_of(params, Gravity.TOP | Gravity.LEFT)
        horizontal = gravity & Gravity.HORIZONTAL_GRAVITY_MASK
        vertical = gravity & Gravity.VERTICAL_GRAVITY_MASK
        area_w = width - pad[0] - pad[2]
        area_h = height - pad[1] - pad[3]
        if horizontal == Gravity.CENTER_HORIZONTAL:
            x = pad[0] + (area_w - cw) // 2 + left_m - right_m
        elif horizontal == Gravity.RIGHT:
            x = width - pad[2] - cw - right_m
        else:
            x = pad[0] + left_m
        if vertical == Gravity.CENTER_VERTICAL:
            y = pad[1] + (area_h - ch) // 2 + top_m - bottom_m
        elif vertical == Gravity.BOTTOM:
            y = height - pad[3] - ch - bottom_m
        else:
            y = pad[1] + top_m
        group._place(child, x, y, cw, ch)


def dispatch_touch(view_id, action, raw_x, raw_y, now):
    """a touch from uikit on a view that asked for touches. True when a listener took it"""
    view = _ui.lookup(view_id)
    if view is None:
        return False
    state = _touch_state.get(view_id)
    if action == MotionEvent.ACTION_DOWN or state is None:
        state = {"down": (raw_x, raw_y), "time": now, "taken": False, "moved": False}
        _touch_state[view_id] = state
    elif action == MotionEvent.ACTION_MOVE:
        if abs(raw_x - state["down"][0]) > 12 or abs(raw_y - state["down"][1]) > 12:
            state["moved"] = True
    event = MotionEvent(action, raw_x, raw_y, view, state["time"], now)
    taken = bool(view.dispatchTouchEvent(event))
    if action == MotionEvent.ACTION_DOWN:
        state["taken"] = taken
    elif action == MotionEvent.ACTION_UP:
        if not taken and not state["moved"] and view._enabled:
            if view._on_long_click is not None and now - state["time"] >= 0.5:
                # the app reports a touch when it starts and when it ends, so a long press is told when the finger lifts
                taken = bool(_call(view._on_long_click, "onLongClick", view))
            if not taken and view._on_click is not None:
                _call(view._on_click, "onClick", view)
                taken = True
    if action in (MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL):
        _touch_state.pop(view_id, None)
    return taken or state["taken"] or view._on_click is not None


_touch_state = {}


class ViewParent:
    """what getParent() answers to: a ViewGroup"""


class ViewTreeObserver(Object):
    """listeners of the tree. only the global layout listener is called: it runs after every layout pass python makes. the draw and
    scroll listeners are kept and handed back on removal, but the views here do not draw or scroll under python, so they never fire"""

    class OnGlobalLayoutListener:
        """a program implements onGlobalLayout()"""

    class OnPreDrawListener:
        """a program implements onPreDraw() and returns whether the drawing goes on"""

    class OnDrawListener:
        """a program implements onDraw()"""

    class OnScrollChangedListener:
        """a program implements onScrollChanged()"""

    def __init__(self):
        self._layout = []
        self._other = []

    def addOnGlobalLayoutListener(self, listener):
        self._layout.append(listener)

    def removeOnGlobalLayoutListener(self, listener):
        if listener in self._layout:
            self._layout.remove(listener)

    def addOnPreDrawListener(self, listener):
        self._other.append(listener)

    def addOnDrawListener(self, listener):
        self._other.append(listener)

    def addOnScrollChangedListener(self, listener):
        self._other.append(listener)

    def removeOnPreDrawListener(self, listener):
        if listener in self._other:
            self._other.remove(listener)

    removeOnDrawListener = removeOnScrollChangedListener = removeOnPreDrawListener

    def isAlive(self):
        return True

    def dispatchOnGlobalLayout(self):
        import sys
        import traceback
        for listener in list(self._layout):
            try:
                _call(listener, "onGlobalLayout")
            except Exception:
                # one listener that fails must not stop the layout pass of every other plugin
                traceback.print_exc(file=sys.stderr)


class ViewConfiguration(Object):
    """the touch constants of the platform in points, the values iOS uses for its own gestures"""

    _instance = None

    @staticmethod
    def get(context=None):
        if ViewConfiguration._instance is None:
            ViewConfiguration._instance = ViewConfiguration()
        return ViewConfiguration._instance

    def getScaledTouchSlop(self):
        return 10

    getScaledPagingTouchSlop = getScaledTouchSlop

    def getScaledDoubleTapSlop(self):
        return 100

    def getScaledMinimumFlingVelocity(self):
        return 50

    def getScaledMaximumFlingVelocity(self):
        return 8000

    def getScaledScrollFactor(self):
        return 64

    @staticmethod
    def getLongPressTimeout():
        return 500

    @staticmethod
    def getTapTimeout():
        return 100

    @staticmethod
    def getDoubleTapTimeout():
        return 300

    @staticmethod
    def getPressedStateDuration():
        return 64

    @staticmethod
    def getScrollFriction():
        return 0.015


class Outline(Object):
    def __init__(self):
        self._shape = None
        self._alpha = 0.0

    def setEmpty(self):
        self._shape = None

    def isEmpty(self):
        return self._shape is None

    def setRect(self, left, top=None, right=None, bottom=None):
        self.setRoundRect(left, top, right, bottom, 0.0)

    def setRoundRect(self, left, top=None, right=None, bottom=None, radius=0.0):
        if top is None:
            rect = left
            left, top, right, bottom, radius = rect.left, rect.top, rect.right, rect.bottom, right or 0.0
        self._shape = ("round", left, top, right, bottom, float(radius))

    def setOval(self, left, top=None, right=None, bottom=None):
        if top is None:
            rect = left
            left, top, right, bottom = rect.left, rect.top, rect.right, rect.bottom
        self._shape = ("oval", left, top, right, bottom, 0.0)

    def getRadius(self):
        return self._shape[5] if self._shape is not None and self._shape[0] == "round" else -1.0

    def setAlpha(self, alpha):
        self._alpha = float(alpha)

    def getAlpha(self):
        return self._alpha


class ViewOutlineProvider(Object):
    """a program overrides getOutline(view, outline); the shims keep the provider on the view and never ask for the outline"""

    BACKGROUND = None
    BOUNDS = None
    PADDED_BOUNDS = None

    def getOutline(self, view, outline):
        return None


class Window(Object):
    """the window of an activity. what a program sets here is kept and read back: the app owns its status bar and its flags, so
    none of it changes how the app looks"""

    FEATURE_NO_TITLE = 1
    ID_ANDROID_CONTENT = 0x01020002

    def __init__(self, activity):
        self._activity = activity
        self._flags = 0
        self._status_bar_color = 0xFF000000
        self._navigation_bar_color = 0xFF000000
        self._soft_input_mode = 0

    def getDecorView(self):
        return self._activity._decor

    def getContext(self):
        return self._activity

    def getStatusBarColor(self):
        return self._status_bar_color

    def setStatusBarColor(self, color):
        self._status_bar_color = int(color) & 0xFFFFFFFF

    def getNavigationBarColor(self):
        return self._navigation_bar_color

    def setNavigationBarColor(self, color):
        self._navigation_bar_color = int(color) & 0xFFFFFFFF

    def addFlags(self, flags):
        self._flags |= flags

    def clearFlags(self, flags):
        self._flags &= ~flags

    def setFlags(self, flags, mask):
        self._flags = (self._flags & ~mask) | (flags & mask)

    def getFlags(self):
        return self._flags

    def setSoftInputMode(self, mode):
        self._soft_input_mode = mode

    def getSoftInputMode(self):
        return self._soft_input_mode


class WindowManager(Object):
    """the window service. a window is a view of the overlay the app lays above its screens (the DecorView), placed by gravity and the offsets x and
    y as the android window manager places it: from the edge the gravity names, from the center when it names none. the types and flags are
    kept for the plugin to read back. FLAG_NOT_FOCUSABLE is how every view of the overlay behaves, a keyboard needs the dialog of the app, and
    a view that has a touch or click listener gets touches whatever FLAG_NOT_TOUCHABLE says"""

    class LayoutParams(MarginLayoutParams):
        TYPE_APPLICATION = 2
        TYPE_APPLICATION_PANEL = 1000
        TYPE_PHONE = 2002
        TYPE_SYSTEM_ALERT = 2003
        TYPE_TOAST = 2005
        TYPE_APPLICATION_OVERLAY = 2038
        FLAG_NOT_FOCUSABLE = 0x8
        FLAG_NOT_TOUCH_MODAL = 0x20
        FLAG_NOT_TOUCHABLE = 0x10
        FLAG_KEEP_SCREEN_ON = 0x80
        FLAG_LAYOUT_IN_SCREEN = 0x100
        FLAG_LAYOUT_NO_LIMITS = 0x200
        FLAG_FULLSCREEN = 0x400
        FLAG_WATCH_OUTSIDE_TOUCH = 0x40000

        def __init__(self, *args):
            super().__init__(MATCH_PARENT, MATCH_PARENT)
            self.x = self.y = 0
            self.gravity = Gravity.NO_GRAVITY
            self.type = 0
            self.flags = 0
            self.format = -1
            self.alpha = 1.0
            self.token = None
            if len(args) == 1:
                self.type = int(args[0])
            elif len(args) == 2:
                self.type, self.flags = int(args[0]), int(args[1])
            elif len(args) == 3:
                self.type, self.flags, self.format = (int(a) for a in args)
            elif len(args) == 5:
                self.width, self.height, self.type, self.flags, self.format = (int(a) for a in args)
            elif len(args) == 7:
                self.width, self.height, self.x, self.y, self.type, self.flags, self.format = (int(a) for a in args)
            elif args:
                raise TypeError("WindowManager.LayoutParams takes 0, 1, 2, 3, 5 or 7 arguments, got %d" % len(args))

        def _lay_out(self):
            """the margins and the gravity the frame layout reads, from gravity, x and y"""
            gravity = self.gravity if self.gravity else Gravity.CENTER
            self._layout_gravity = gravity
            horizontal, vertical = gravity & Gravity.HORIZONTAL_GRAVITY_MASK, gravity & Gravity.VERTICAL_GRAVITY_MASK
            self.leftMargin = self.rightMargin = self.topMargin = self.bottomMargin = 0
            if horizontal == Gravity.RIGHT:
                self.rightMargin = int(self.x)
            else:
                self.leftMargin = int(self.x)
            if vertical == Gravity.BOTTOM:
                self.bottomMargin = int(self.y)
            else:
                self.topMargin = int(self.y)

    _instance = None

    @staticmethod
    def _get():
        if WindowManager._instance is None:
            WindowManager._instance = WindowManager()
        return WindowManager._instance

    @staticmethod
    def _root():
        from android.app import activity
        return activity().getWindow().getDecorView()

    @staticmethod
    def _checked(params):
        from java.lang import IllegalArgumentException
        if not isinstance(params, WindowManager.LayoutParams):
            raise IllegalArgumentException("Params must be WindowManager.LayoutParams")
        return params

    def addView(self, view, params):
        from java.lang import IllegalStateException, NullPointerException
        if view is None:
            raise NullPointerException("view must not be null")
        self._checked(params)._lay_out()
        if view.getParent() is not None:
            raise IllegalStateException("View %s has already been added to the window manager." % (view,))
        self._root().addView(view, params)
        if params.alpha != 1.0:
            view.setAlpha(params.alpha)

    def updateViewLayout(self, view, params):
        from java.lang import IllegalArgumentException
        self._checked(params)._lay_out()
        if view is None or view.getParent() is not self._root():
            raise IllegalArgumentException("View not attached to window manager")
        view.setLayoutParams(params)
        view.setAlpha(params.alpha)

    def removeView(self, view):
        from java.lang import IllegalArgumentException
        if view is None or view.getParent() is not self._root():
            raise IllegalArgumentException("View not attached to window manager")
        self._root().removeView(view)

    removeViewImmediate = removeView
