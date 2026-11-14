"""android.provider: the column names a content resolver answers for a picked file, and the settings screens a plugin may ask about"""


class OpenableColumns:
    DISPLAY_NAME = "_display_name"
    SIZE = "_size"


class Settings:
    """of the android settings only the overlay permission, which is always there: a window of a plugin is a view of the overlay of the app,
    and no system permission stands between a plugin and it"""

    ACTION_MANAGE_OVERLAY_PERMISSION = "android.settings.action.MANAGE_OVERLAY_PERMISSION"

    @staticmethod
    def canDrawOverlays(context):
        return True
