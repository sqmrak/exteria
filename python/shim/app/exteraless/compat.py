"""classes of exteraGram that plugins import by name and that have little to do on ios"""

from java.lang import Object


class ExteraConfig(Object):
    @staticmethod
    def getPluginsSafeMode():
        """the safe mode of the android client switches plugin hooks off; the host has no such mode"""
        return False


class AppUtils(Object):
    """importable only: zwylib asks it for a Gson to print java objects, and no object of the shims is one"""


class ChatUtils(Object):
    """importable only: it resolves public channels through the client, which python cannot reach on ios"""
