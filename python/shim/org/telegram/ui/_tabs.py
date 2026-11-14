"""MainTabsActivity: the bottom bar of the signed in app. the android client has one view per tab (TabView) that a plugin retitles, gives
an icon and a click listener; here a tab is a slot of the native bar, and every change is sent to the app (service tabs.set), which keeps it
across rebuilds of the bar. a tap on a slot with a listener comes back through exteria_host.tab_event instead of opening the screen"""

from android import _ui
from android.app import activity
from android.view import ViewGroup
from android.widget import ImageView
from java.util import ArrayList
from org.telegram.ui import BaseFragment

SLOTS = 4


class _TabImage(ImageView):
    """the icon of a tab; the bar draws it, so this view is never on the overlay"""

    def __init__(self, tab):
        super().__init__(activity())
        self._tab = tab

    def setImageDrawable(self, drawable):
        self._tab._set_icon(drawable)


class TabView(ViewGroup):
    def __init__(self, slot):
        super().__init__(activity())
        self._slot = slot
        self._title = None
        self._icon = None
        self._click = None
        self._hold = None
        self._image = _TabImage(self)

    def getChildCount(self):
        return 1

    def getChildAt(self, index):
        return self._image if index == 0 else None

    def setText(self, text):
        self._title = None if text is None else str(text)
        self._push()

    def _set_icon(self, drawable):
        self._icon = getattr(drawable, "_symbol", None)
        if drawable is not None and self._icon is None:
            raise TypeError("the bar draws only the icons of the app, not %s" % type(drawable).__name__)
        self._push()

    def setOnClickListener(self, listener):
        self._click = listener
        self._push()

    def setOnLongClickListener(self, listener):
        self._hold = listener
        self._push()

    def _push(self):
        _ui.ask("tabs.set", slot=self._slot, title=self._title, icon=self._icon,
                click=self._click is not None, hold=self._hold is not None)


class MainTabsActivity(BaseFragment):
    """the app tells it when the bar is built ("create") and comes on screen ("resume"), as it does for the settings page"""

    _single = []

    @staticmethod
    def instance():
        if not MainTabsActivity._single:
            MainTabsActivity._single.append(MainTabsActivity())
        return MainTabsActivity._single[0]

    def __init__(self):
        self.tabs = [TabView(slot) for slot in range(SLOTS)]

    def createView(self, context):
        return None

    def onResume(self):
        """called each time the main screen comes on screen"""

    def _event(self, event):
        if event == "create":
            self.createView(activity())
        elif event == "resume":
            self.onResume()
        else:
            raise ValueError("no such tabs event: %r" % (event,))

    def _tap(self, slot, kind):
        tab = self.tabs[slot]
        listener = tab._hold if kind == "hold" else tab._click
        if listener is not None:
            from android.view import _call
            _call(listener, "onLongClick" if kind == "hold" else "onClick", tab)


def fragment_stack():
    """what LaunchActivity.getActionBarLayout().getFragmentStack() holds: the main screen when the app has its bar up"""
    return ArrayList([MainTabsActivity.instance()]) if _ui.ask("tabs.state").get("value") else ArrayList()


def reset():
    """the last plugin went: the listeners go with it, the app puts its own titles and icons back"""
    for page in MainTabsActivity._single:
        page.tabs = [TabView(slot) for slot in range(SLOTS)]
