"""org.telegram.ui.Gifts: importable only, the gift screens of the app open from its own screens"""

from java.lang import Object


class GiftSheet(Object):
    """GiftSheet(context, account, user_id, ...) is the sheet that sends a gift in the android client. a plugin that imports it still loads, and
    making one raises NotImplementedError: the gift screens of the app are opened by the person from a profile, and python cannot open them"""

    def __init__(self, *_arguments):
        raise NotImplementedError("the gift sheet of the android client has no equal a plugin can open, the gifts are sent from a profile of the app")
