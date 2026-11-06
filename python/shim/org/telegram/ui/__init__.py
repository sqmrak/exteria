"""org.telegram.ui: the activity and the fragment a plugin asks for the chat that is open"""

from android import _ui
from android.app import Activity, activity
from android.view import PageView
from java.lang import Object
from java.util import ArrayList
from org.telegram.tgnet import TLRPC


class CastSync(Object):
    """casting to another screen, which the app has no part of"""

    @staticmethod
    def isActive():
        return False


class BaseFragment(Object):
    def getParentActivity(self):
        return activity()

    def getFragmentView(self):
        """the views of the android fragment have no equal for a screen of the app, only SettingsActivity has a root a plugin can use"""
        return None

    def presentFragment(self, fragment):
        """opens a picker of the app; any other fragment is a screen of the android client the app has no equal of"""
        present = getattr(fragment, "_present", None)
        if present is None:
            raise TypeError("%s cannot be opened here" % type(fragment).__name__)
        present()
        return True

    def finishFragment(self, *_animated):
        """a picker closes itself when the person has chosen, so what is above it has nothing left to close. the screens
        under the pickers are the app's own and python does not close them"""


class ChatActivity(BaseFragment):
    class ReplyQuote(Object):
        """the words of an answered message that a reply quotes. telegram takes 1024 utf-16 units at most, so a longer text is cut there"""

        LIMIT = 1024

        def __init__(self, message, text, start=0):
            units = text.encode("utf-16-le")
            if len(units) > 2 * self.LIMIT:
                # never between the halves of a surrogate pair
                cut = 2 * self.LIMIT
                if 0xD800 <= int.from_bytes(units[cut - 2:cut], "little") < 0xDC00:
                    cut -= 2
                text = units[:cut].decode("utf-16-le")
            self.message = message
            self.text = text
            self.start = int(start)

        @staticmethod
        def make(message):
            """the whole text of a message as a quote, the shape of ReplyQuote.from in the android client"""
            return ChatActivity.ReplyQuote(message, str(message.messageOwner.message or ""), 0)

    def __init__(self, data):
        self._data = data

    def getDialogId(self):
        return int(self._data.get("dialog", 0))

    def getCurrentUser(self):
        user = self._data.get("user")
        return TLRPC.User(**user) if user else None

    def getCurrentChat(self):
        chat = self._data.get("chat")
        return TLRPC.Chat(**chat) if chat else None

    def getChatListView(self):
        return None

    def getChatActivityEnterView(self):
        return None


_picks = {}
_pick_token = [0]
_PICK_LIMIT = 100


def _pick(kinds, limit, done, cancelled):
    """opens the chat picker of the app. kinds: bit 1 users, 2 bots, 4 groups, 8 channels. done([signed ids]) is called once the
    person has chosen, ids as the android client writes them: negative for groups and channels. cancelled() is called instead when
    the person goes back, as onFragmentDestroy is on android"""
    _pick_token[0] += 1
    token = _pick_token[0]
    _picks[token] = (done, cancelled)
    try:
        _ui.ask("app.pick", token=token, types=int(kinds), limit=int(limit))
    except BaseException:
        _picks.pop(token, None)
        raise


def _pick_result(token, chosen):
    entry = _picks.pop(int(token), None)
    if entry is None:
        return
    done = entry[0]
    # dialog kinds of the app: 1 user, 2 bot, 3 group, 4 channel
    done([int(one["id"]) if int(one["kind"]) in (1, 2) else -int(one["id"]) for one in chosen])


def _pick_cancelled(token):
    entry = _picks.pop(int(token), None)
    if entry is not None:
        entry[1]()


class GroupCreateActivity(BaseFragment):
    """the picker of people and chats. the app lists what the adapter's contacts name: a user record for people and bots, a
    chat record for groups and channels, and a hook on the adapter may narrow that list, as zwylib does for chats only"""

    class GroupCreateActivityDelegate:
        """a plugin class implements didSelectUsers(a, count, ids)"""

    class GroupCreateAdapter(Object):
        def __init__(self, activity=None):
            self.contacts = ArrayList()
            self.contacts.add(TLRPC.User())
            self.contacts.add(TLRPC.Chat())

    def __init__(self, args=None):
        self._args = args
        self._delegate = None

    def setDelegate(self, delegate):
        self._delegate = delegate

    def select(self, ids, *_flags):
        raise NotImplementedError("the chat picker of the app cannot start with chats already selected")

    def onFragmentDestroy(self):
        """called when the picker is gone, after the answer; a hook on it learns that the person is done"""

    def _present(self):
        if self._delegate is None:
            raise ValueError("a picker needs a delegate")
        adapter = GroupCreateActivity.GroupCreateAdapter(self)
        kinds = 0
        for contact in adapter.contacts.toArray():
            if isinstance(contact, TLRPC.User):
                kinds |= 1 | 2
            elif isinstance(contact, TLRPC.Chat):
                kinds |= 4 | 8
        if not kinds:
            raise ValueError("the adapter lists nothing to pick")

        def chosen(ids):
            self._delegate.didSelectUsers(False, len(ids), ArrayList(ids))
            self.onFragmentDestroy()

        _pick(kinds, _PICK_LIMIT, chosen, self.onFragmentDestroy)


class DialogsActivity(BaseFragment):
    """the picker of one chat. the kinds follow the allow keys of the arguments, all of them allowed when a key is absent"""

    DIALOGS_TYPE_ADD_USERS_TO = 2

    class DialogsActivityDelegate:
        """a plugin class implements didSelectDialogs(fragment, dids, message, param, notify, scheduleDate, repeatPeriod, topicsFragment)"""

    class TopicKey(Object):
        def __init__(self, dialog_id, topic_id=0):
            self.dialogId = int(dialog_id)
            self.topicId = int(topic_id)

    def __init__(self, args=None):
        self._args = args
        self._delegate = None

    def setDelegate(self, delegate):
        self._delegate = delegate

    def onFragmentDestroy(self):
        """called when the picker is gone, after the answer; a hook on it learns that the person is done"""

    def _flag(self, *keys):
        values = [self._args.get(key) for key in keys if self._args is not None and self._args.containsKey(key)]
        return True if not values else any(bool(value) for value in values)

    def _present(self):
        if self._delegate is None:
            raise ValueError("a picker needs a delegate")
        kinds = (1 if self._flag("allowUsers") else 0) | (2 if self._flag("allowBots") else 0)
        kinds |= (4 if self._flag("allowGroups", "allowMegagroups", "allowLegacyGroups") else 0)
        kinds |= (8 if self._flag("allowChannels") else 0)
        if not kinds:
            raise ValueError("the arguments allow no kind of chat")

        def chosen(ids):
            keys = ArrayList([DialogsActivity.TopicKey(one) for one in ids])
            self._delegate.didSelectDialogs(self, keys, None, False, True, 0, 0, None)
            self.onFragmentDestroy()

        _pick(kinds, 1, chosen, self.onFragmentDestroy)


class SettingsActivity(BaseFragment):
    """the settings tab. the app tells it when its page is built, comes on screen and goes away (exteria_host.fragment_event), and a
    plugin hooks createView, onResume and onPause as it does on android. fragmentView is the root of the views the plugin puts under
    the rows of the page; listView stands for the rows (see RecyclerListView)"""

    PAGE_ID = -1
    _single = []

    fragmentView: PageView
    listView: object

    @staticmethod
    def instance():
        if not SettingsActivity._single:
            SettingsActivity._single.append(SettingsActivity())
        return SettingsActivity._single[0]

    def __init__(self):
        from org.telegram.ui.Components import RecyclerListView
        self.fragmentView = PageView(activity(), SettingsActivity.PAGE_ID)
        self.listView = RecyclerListView(self)
        self.listView._parent = self.fragmentView

    def getFragmentView(self):
        return self.fragmentView

    def createView(self, context):
        """called once the page has its layer; the answer is the root of the plugin's views"""
        return self.fragmentView

    def onResume(self):
        """called each time the tab comes on screen"""

    def onPause(self):
        """called each time the tab goes off screen"""

    def _event(self, event, width, height):
        self.fragmentView.resize(width, height)
        if event == "create":
            # the page may have made its layer again, which is empty
            self.fragmentView.rebind()
            self.createView(activity())
        elif event == "resume":
            self.fragmentView.setShown(True)
            self.onResume()
        elif event == "pause":
            self.onPause()
            self.fragmentView.setShown(False)
        elif event != "layout":
            raise ValueError("no such page event: %r" % (event,))


def reset_pages():
    """the last plugin went: what plugins put on the pages of the app is taken off, and the cards are as the app draws them"""
    for page in SettingsActivity._single:
        page.fragmentView.removeAllViews()
        page.listView.sectionBackgroundPaint.setColorFilter(None)


def _fragment():
    data = _ui.ask("app.current") or {}
    if data.get("kind") == "settings":
        return SettingsActivity.instance()
    if data.get("kind") == "chat":
        return ChatActivity(data)
    if data.get("kind") == "other":
        return BaseFragment()
    return None


class _LaunchMeta(type):
    @property
    def instance(cls):
        return activity()


class LaunchActivity(Activity, metaclass=_LaunchMeta):
    def onActivityResult(self, request_code, result_code, data):
        """the app calls this when a screen it opened for a plugin has an answer (exteria_host.activity_result), and a plugin hooks it to
        take the answer, as it does on android"""

    @staticmethod
    def getLastFragment():
        return _fragment()

    @staticmethod
    def getLastFragmentIncludeMainTabs():
        return _fragment()


# from is a keyword of python, the factory is the member named from in the android client
setattr(ChatActivity.ReplyQuote, "from", staticmethod(ChatActivity.ReplyQuote.make))


