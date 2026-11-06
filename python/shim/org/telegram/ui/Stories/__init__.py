"""org.telegram.ui.Stories: the controller a story goes through when it is published. the app publishes pictures of the signed in person only, so a story
that is not a picture, or one for a channel, is refused by name instead of going out wrong"""

from android import _ui
from java.lang import Object
from org.telegram.tgnet import requests

_forgotten = []


def _flush_forgotten():
    while _forgotten:
        _ui.ask("story.forget", token=_forgotten.pop())


_ui.on_flush(_flush_forgotten)


class StoriesController(Object):
    _instance = None

    @staticmethod
    def getInstance(*_account):
        if StoriesController._instance is None:
            StoriesController._instance = StoriesController()
        return StoriesController._instance

    def __init__(self):
        self._offered = None
        self._reached = False

    def uploadStory(self, entry, *_flags):
        """publishes the story. a plugin hooks this method to hold a story back, as the story scheduler does: a hook that sets a result takes the story
        and this body does not run"""
        if self._offered is entry:
            # the screen of the app offered the story and no hook took it: the app publishes it by itself
            self._reached = True
            return
        entry._post()

    def _offer(self, entry):
        """the story the screen of the app is about to publish, to the hooks: True when a hook took it"""
        self._offered, self._reached = entry, False
        try:
            self.uploadStory(entry, True)
        finally:
            self._offered = None
        return not self._reached


def _failed(text):
    from ui.bulletin import BulletinHelper
    BulletinHelper.show_error(text)


def post(entry, done=None):
    """sends the picture of entry to the story of the signed in person; done(error) runs when the server has answered, error the name of the failure or None"""
    if entry.isVideo:
        raise NotImplementedError("the app publishes pictures as stories only, not videos")
    if entry.peer is not None:
        raise NotImplementedError("the app publishes stories to the profile of the signed in person only, not to a channel or a group")
    if entry.file is None:
        raise ValueError("the story has no file")
    path = str(entry.file.getAbsolutePath())

    def finished(error):
        if entry._owned:
            import os
            try:
                os.remove(path)
            except OSError:
                pass
        if error is not None:
            from android_utils import log
            log("the story was not published: %s" % error)
            _failed("The story was not published: %s" % error)
        if done is not None:
            done(error)

    requests.submit("story_post", {"path": path, "caption": str(entry.caption or ""), "audience": int(entry._token)}, finished)
