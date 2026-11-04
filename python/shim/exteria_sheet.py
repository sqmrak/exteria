"""exteria only: a sheet over the app, like the one of the in-app browser, that shows a native surface and a pad of touch keys.

present() opens it at once, with a loading line; ready() starts the frames, fail() puts a text in place of the picture. the surface
is run by the app itself, a frame at a time, so a game does not pass through python. see app/platform/exteria_plugin_sheet.h"""

from android import _ui

_sheets = {}


class Sheet:
    def __init__(self, number, on_close, on_end):
        self.id = number
        self._on_close = on_close
        self._on_end = on_end

    def ready(self):
        """what the surface needs is loaded: the frames start"""
        _ui.ask("sheet.ready", id=self.id)

    def fail(self, text):
        """the surface will not run; the text is shown in its place"""
        _ui.ask("sheet.fail", id=self.id, text=str(text))

    def close(self):
        _ui.ask("sheet.close", id=self.id)


def present(title, surface, width, height, buttons, ended="", on_close=None, on_end=None):
    """buttons: [{"label", "key", "slot"}], slot one of up, down, left, right, a, b, c, t1, t2, t3. on_close() is called when the sheet
    goes, by the person or by close(); on_end() when the surface stopped by itself"""
    reply = _ui.ask("sheet.open", title=str(title), surface=str(surface), width=int(width), height=int(height),
                    buttons=list(buttons), ended=str(ended))
    sheet = Sheet(int(reply["id"]), on_close, on_end)
    _sheets[sheet.id] = sheet
    return sheet


def _closed(number):
    sheet = _sheets.pop(int(number), None)
    if sheet is not None and sheet._on_close is not None:
        sheet._on_close()


def _ended(number):
    sheet = _sheets.get(int(number))
    if sheet is not None and sheet._on_end is not None:
        sheet._on_end()
