"""calls into the app are served on its main thread only (uikit). a plugin worker thread, such as the one run_on_queue
starts, hands each call over through the ui token queue and waits for the answer"""

import threading

_WAIT_SECONDS = 10.0


def call(function):
    if threading.current_thread() is threading.main_thread():
        return function()
    from app.exteraless.plugins import PluginServices
    done = threading.Event()
    box = []

    def run():
        try:
            box.append((True, function()))
        except BaseException as error:
            box.append((False, error))
        finally:
            done.set()

    PluginServices.runOnUiThread(run)
    if not done.wait(_WAIT_SECONDS):
        raise TimeoutError("the main thread of the app did not answer in %d s" % _WAIT_SECONDS)
    ok, value = box[0]
    if not ok:
        raise value
    return value
