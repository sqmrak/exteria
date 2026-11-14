"""org.telegram.messenger.browser: Browser opens an address through the app

the app routes it as it does a tap on a link in a chat: t.me and tg:// links open inside the app, http and https open in the browser
the person chose in the settings (the in-app sheet, the system browser, chrome, firefox or brave). the flags of the android call (custom
tabs, force browser, the telegraph preview) have no equal there, so they are accepted and the choice of the person decides. any other
scheme is refused: the app hands them to the system, and a plugin may not start other apps"""

from android import _ui
from java.lang import IllegalArgumentException, Object

_TELEGRAM_HOSTS = ("t.me", "telegram.me", "telegram.dog")


def _text(address):
    if address is None:
        raise IllegalArgumentException("url == null")
    return str(address.toString() if hasattr(address, "toString") else address)


class Browser(Object):
    class Progress:
        """a program implements end() and init()"""

    @staticmethod
    def openUrl(context, address, *_flags):
        """openUrl(context, url | uri [, customTabs [, tryTelegraph [, progress]]]) and the other arities of the android client"""
        text = _text(address)
        try:
            _ui.ask("app.open_url", url=text)
        except RuntimeError as error:
            raise IllegalArgumentException(str(error)) from error

    @staticmethod
    def isInternalUrl(address, *_flags):
        """whether the app opens the address itself: the tg scheme and the telegram hosts"""
        from urllib.parse import urlsplit
        parts = urlsplit(_text(address))
        return parts.scheme == "tg" or (parts.scheme in ("http", "https") and (parts.hostname or "").lower() in _TELEGRAM_HOSTS)

    @staticmethod
    def isTelegraphUrl(address, *_flags):
        from urllib.parse import urlsplit
        return (urlsplit(_text(address)).hostname or "").lower() in ("telegra.ph", "graph.org")

    @staticmethod
    def isInternalUri(address, *_flags):
        return Browser.isInternalUrl(address)
