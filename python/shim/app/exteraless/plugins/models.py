"""CustomSetting of the plugin settings page: the row a plugin draws itself. the page of the host shows such a row as
unavailable, so the factory is recorded for the plugin that asks for it and no row is ever built from it"""

from java.lang import Object


class CustomSetting(Object):
    class Factory(Object):
        pass
