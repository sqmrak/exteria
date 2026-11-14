"""androidx.core.content"""


class ContextCompat:
    @staticmethod
    def getDrawable(context, resource_id):
        raise NotImplementedError("the drawables of the android client are not part of the app, resource %r cannot be loaded" % (resource_id,))
