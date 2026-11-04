"""PyMethodHook and PyMethodReplacement: the callbacks the sdk builds around the handler object of a plugin"""

from base_plugin import dispatch_hook
from de.robv.android.xposed import XC_MethodHook
from extera_utils import plugin_loader


class PyMethodHook(XC_MethodHook):
    def __init__(self, plugin_id, hook, priority=0):
        self.plugin_id = plugin_id
        self.priority = priority
        self._hook = hook

    def _filters(self, filters):
        if filters:
            raise NotImplementedError("hook filters are not available on ios")

    setBeforeHookedFilters = setAfterHookedFilters = _filters

    def _call(self, attribute, param):
        if hasattr(self._hook, attribute):
            with plugin_loader.plugin_context(self.plugin_id):
                return dispatch_hook(self._hook, attribute, param)
        return None

    def beforeHookedMethod(self, param):
        self._call("before_hooked_method", param)

    def afterHookedMethod(self, param):
        self._call("after_hooked_method", param)


class PyMethodReplacement(PyMethodHook):
    def beforeHookedMethod(self, param):
        param.setResult(self._call("replace_hooked_method", param))

    def afterHookedMethod(self, param):
        pass
