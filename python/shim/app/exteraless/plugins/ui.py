"""PluginSettingsActivity of exteraGram: the screen of the settings a plugin builds. presenting it opens the page of the app for that plugin"""

from android import _ui
from java.lang import IllegalArgumentException, IllegalStateException, NullPointerException, Object


class PluginSettingsActivity(Object):
    """PluginSettingsActivity(plugin) and PluginSettingsActivity.of(id). it is a fragment only to be passed to presentFragment: the page is the
    app's own screen for the plugin, and it needs the plugin to be running and to have built settings"""

    def __init__(self, plugin):
        if plugin is None:
            raise NullPointerException("plugin == null")
        plugin_id = plugin.getId() if hasattr(plugin, "getId") else plugin
        if not isinstance(plugin_id, str) or not plugin_id:
            raise IllegalArgumentException("a plugin or the id of one is needed, not %r" % (plugin,))
        self._id = plugin_id

    @staticmethod
    def of(plugin_id):
        return PluginSettingsActivity(plugin_id)

    def getPluginId(self):
        return self._id

    def _present(self):
        try:
            _ui.ask("app.plugin_settings", plugin=self._id)
        except RuntimeError as error:
            raise IllegalStateException(str(error)) from error
