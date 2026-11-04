"""android.view over the view bridge of android/_ui.py.

the tree, the layout and the property values live here. every change is queued for uikit and sent when the entry point that
called python returns. layout follows android: measure with specs, then place by gravity and margins, so getWidth,
getHeight and getLocationInWindow answer what a plugin expects. not implemented: drawing a view into a canvas,
long press, focus, and anything that needs the views of the host app, which has none the plugin can reach"""

from android import _ui
from java.lang import Object

UNSPECIFIED = 0
EXACTLY = 1 << 30
AT_MOST = 2 << 30
_MODE_MASK = 3 << 30

MATCH_PARENT = -1
WRAP_CONTENT = -2


def _argb(color):
    return int(color) & 0xFFFFFFFF


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


def _layout_pass():
    for root in list(_dirty_roots):
        _dirty_roots.discard(root)
        root._layout_root()


_ui.on_flush(_layout_pass)


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
        self._animator = None

    # identity and tree

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
        return self._clickable or self._on_touch is not None or self._on_click is not None

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

    def animate(self):
        if self._animator is None:
            self._animator = ViewPropertyAnimator(self)
        return self._animator

    def bringToFront(self):
        parent = self._parent
        if parent is not None:
            parent.removeView(self)
            parent.addView(self)

    def invalidate(self):
        pass

    def requestLayout(self):
        self._request_layout()

    # geometry

    def _ensure_layout(self):
        root = self.getRootView()
        if root in _dirty_roots:
            _dirty_roots.discard(root)
            root._layout_root()

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
        self._measured = self._on_measure(wspec, hspec)

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

    def _detach(self):
        self._attached = False
        _ui.forget(self._id)
        self._pushed_frame = None

    def _layout_root(self):
        pass


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
            child._layout_children(int(width), int(height))

    def _layout_root(self):
        screen = _ui.screen()
        width, height = int(screen["w"]), int(screen["h"])
        self.measure(width | EXACTLY, height | EXACTLY)
        self._frame = (0, 0, width, height)
        self._layout_children(width, height)
        self._push_frames()

    def _push_frames(self):
        for child in self._children:
            frame = child._frame
            if child._attached and frame != child._pushed_frame:
                child._pushed_frame = frame
                _ui.set_props(child._id, {"x": frame[0], "y": frame[1], "w": frame[2], "h": frame[3]})
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


def _gravity_of(params, default):
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
    taken = False
    if view._on_touch is not None:
        taken = bool(_call(view._on_touch, "onTouch", view, event))
    if action == MotionEvent.ACTION_DOWN:
        state["taken"] = taken
    elif action == MotionEvent.ACTION_UP:
        if not taken and not state["moved"] and view._on_click is not None and view._enabled:
            _call(view._on_click, "onClick", view)
            taken = True
    if action in (MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL):
        _touch_state.pop(view_id, None)
    return taken or state["taken"] or view._on_click is not None


_touch_state = {}
