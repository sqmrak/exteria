"""org.telegram.ui.Stories.recorder: the story a person made and the page of the sheet that asks who sees it. the screen of the app that makes a story stands
in for the sheet: it builds a page when it holds a picture, so a plugin that hooks the page can put a button beside "publish" and take the story when it is
published (exteria_host.story_page, story_schedule, story_intercept)"""

from android import _ui
from android.view import View, _call
from java.io import File
from java.lang import Object


class StoryEntry(Object):
    """a story ready to go up. the app fills file, caption and the audience (held by the app under a number); a plugin that restores a story after a restart
    builds an empty one and fills the same fields, with no audience, which means everyone"""

    def __init__(self):
        self.file = None
        self.fileDeletable = True
        self.isVideo = False
        self.caption = ""
        self.pinned = True
        self.period = 86400
        self.peer = None
        self.currentAccount = 0
        self._token = 0
        self._owned = False

    def __del__(self):
        # a story the plugin let go of will not be published: its audience is freed in the app, and so is the file the app made for it
        if getattr(self, "_token", 0):
            from org.telegram.ui.Stories import _forgotten
            _forgotten.append(self._token)
        if getattr(self, "_owned", False) and self.file is not None:
            import os
            try:
                os.remove(str(self.file.getAbsolutePath()))
            except OSError:
                pass

    def _post(self):
        from org.telegram.ui.Stories import post
        post(self)


class ButtonWithCounterView(Object):
    """the button of the sheet. one that was not given a click listener presses publish on the screen of the app"""

    def __init__(self, press=None):
        self._visibility = View.VISIBLE
        self._text = ""
        self._on_click = None
        self._on_long_click = None
        self._long_clickable = False
        self._press = press

    def setVisibility(self, visibility):
        self._visibility = int(visibility)

    def getVisibility(self):
        return self._visibility

    def setText(self, text, animated=False):
        self._text = str(text)

    def getText(self):
        return self._text

    def setOnClickListener(self, listener):
        self._on_click = listener

    def setOnLongClickListener(self, listener):
        self._on_long_click = listener
        if listener is not None:
            self._long_clickable = True

    def setLongClickable(self, value):
        self._long_clickable = bool(value)

    def performHapticFeedback(self, *_args):
        return False

    def performClick(self):
        if self._on_click is not None:
            _call(self._on_click, "onClick", self)
            return True
        if self._press is not None:
            self._press()
            return True
        return False

    def performLongClick(self):
        if self._on_long_click is None or not self._long_clickable:
            return False
        return bool(_call(self._on_long_click, "onLongClick", self))


def _press_publish():
    _ui.ask("story.publish")


class StoryPrivacyBottomSheet(Object):
    class Page(Object):
        """the page that holds the button to publish (button) and the one beside it (button2), hidden until a plugin shows it"""

        button: object = None
        button2: object = None

        def __init__(self):
            self.button = ButtonWithCounterView(_press_publish)
            self.button2 = ButtonWithCounterView()
            self.button2.setVisibility(View.GONE)
            self.bind()
            self.updateButton()

        def bind(self, *_args):
            """the page is filled with the choices of the sheet; a plugin hooks it to change the page"""

        def updateButton(self, *_args):
            """the buttons take the look of the choice; a plugin hooks it to change them"""


_pages = []


def story_page():
    """a page for the picture the screen of the app holds, and the words of the button beside publish when a plugin put one there, else None"""
    page = StoryPrivacyBottomSheet.Page()
    _pages[:] = [page]
    second = page.button2
    if second.getVisibility() == View.VISIBLE and second.getText():
        return {"title": second.getText()}
    return None


def story_schedule(long_press):
    """the button beside publish was tapped, or publish was held"""
    if not _pages:
        raise RuntimeError("the story screen has not built its page")
    page = _pages[0]
    if long_press:
        page.button.performLongClick()
    else:
        page.button2.performClick()


def story_intercept(path, caption, token):
    """a story the screen of the app is about to publish. {"taken": a plugin held it back, "keep": it still reads the file}"""
    from org.telegram.ui.Stories import StoriesController
    entry = StoryEntry()
    entry.file = File(path)
    entry.caption = caption
    entry._token = int(token)
    entry._owned = True
    if not StoriesController.getInstance()._offer(entry):
        # the app publishes it and deletes the file itself, and holds the audience until then
        entry._token, entry._owned = 0, False
        return {"taken": False, "keep": False}
    return {"taken": True, "keep": entry.fileDeletable is False}
