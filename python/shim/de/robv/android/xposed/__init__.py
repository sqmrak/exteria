"""xposed over the methods of the python classes of the shims.

there is no art to patch on ios; a method of a shim class is replaced by a wrapper that runs the callbacks around the
original, with the semantics of xposed: a before callback that sets a result or a throwable skips the original and the
callbacks after it, after callbacks run in reverse order and may change the result. the classes of the app itself
(chat cells, fragments) have no shim and no method to hook"""

import functools
import threading

from java.lang import Object


class XC_MethodHook(Object):
    class MethodHookParam(Object):
        def __init__(self, method, this_object, args):
            self.method = method
            self.thisObject = this_object
            self.args = list(args)
            self._result = None
            self._throwable = None
            self._finished = False

        def getResult(self):
            return self._result

        def setResult(self, result):
            self._result = result
            self._throwable = None
            self._finished = True

        def getThrowable(self):
            return self._throwable

        def hasThrowable(self):
            return self._throwable is not None

        def setThrowable(self, throwable):
            self._throwable = throwable
            self._result = None
            self._finished = True

        def getResultOrThrowable(self):
            if self._throwable is not None:
                raise self._throwable
            return self._result

    class Unhook(Object):
        def __init__(self, member, callback):
            self._member = member
            self._callback = callback

        def getHookedMethod(self):
            return self._member

        def getCallback(self):
            return self._callback

        def unhook(self):
            XposedBridge._remove(self)

    def beforeHookedMethod(self, param):
        pass

    def afterHookedMethod(self, param):
        pass


class _Chain:
    """the callbacks on one method and the original they wrap"""

    def __init__(self, target, name, original):
        self.target = target
        self.name = name
        self.original = original
        self.entries = []
        self.counter = 0


def _priority_of(callback):
    return getattr(callback, "priority", 0)


class XposedBridge:
    _lock = threading.RLock()
    _chains = {}

    @staticmethod
    def hookMethod(member, callback):
        from java.lang.reflect import Constructor, Method
        if isinstance(member, Constructor):
            raise NotImplementedError("constructors of the shim classes are not hookable")
        if not isinstance(member, Method):
            raise TypeError("not a method: %r" % (member,))
        target = member.getDeclaringClass()._py
        key = (target, member.getName())
        with XposedBridge._lock:
            chain = XposedBridge._chains.get(key)
            if chain is None:
                original = vars(target)[member.getName()]
                chain = _Chain(target, member.getName(), original)
                setattr(target, member.getName(), XposedBridge._wrapper(chain, member))
                XposedBridge._chains[key] = chain
            unhook = XC_MethodHook.Unhook(member, callback)
            chain.counter += 1
            chain.entries.append((-_priority_of(callback), chain.counter, unhook))
            chain.entries.sort(key=lambda entry: entry[:2])
        return unhook

    @staticmethod
    def _remove(unhook):
        member = unhook.getHookedMethod()
        key = (member.getDeclaringClass()._py, member.getName())
        with XposedBridge._lock:
            chain = XposedBridge._chains.get(key)
            if chain is None:
                return
            chain.entries = [entry for entry in chain.entries if entry[2] is not unhook]
            if not chain.entries:
                setattr(chain.target, chain.name, chain.original)
                del XposedBridge._chains[key]

    @staticmethod
    def _wrapper(chain, member):
        original = chain.original

        def run(this, args):
            param = XC_MethodHook.MethodHookParam(member, this, args)
            with XposedBridge._lock:
                callbacks = [entry[2].getCallback() for entry in chain.entries]
            entered = []
            for callback in callbacks:
                try:
                    callback.beforeHookedMethod(param)
                except Exception:
                    XposedBridge._report(member, callback, "before")
                    param._result, param._throwable, param._finished = None, None, False
                    continue
                entered.append(callback)
                if param._finished:
                    break
            if not param._finished:
                function = getattr(original, "__func__", original)
                try:
                    param._result = function(*param.args) if isinstance(original, staticmethod) else function(this, *param.args)
                except BaseException as error:
                    param._throwable = error
            for callback in reversed(entered):
                kept = param._result, param._throwable
                try:
                    callback.afterHookedMethod(param)
                except Exception:
                    XposedBridge._report(member, callback, "after")
                    param._result, param._throwable = kept
            if param._throwable is not None:
                raise param._throwable
            return param._result

        # wraps keeps the signature, so the parameter count of a hooked method stays what reflection reports
        function = getattr(original, "__func__", original)
        if isinstance(original, staticmethod):
            return staticmethod(functools.wraps(function)(lambda *args: run(None, args)))
        if isinstance(original, classmethod):
            return classmethod(functools.wraps(function)(lambda cls, *args: run(cls, args)))
        return functools.wraps(function)(lambda this, *args: run(this, args))

    @staticmethod
    def _report(member, callback, phase):
        import traceback
        from android_utils import log
        log("xposed: %s callback of %s failed\n%s" % (phase, member.toString(), traceback.format_exc()))

    @staticmethod
    def hookAllMethods(target, name, callback):
        return [XposedBridge.hookMethod(method, callback) for method in target.getDeclaredMethods() if method.getName() == name]
