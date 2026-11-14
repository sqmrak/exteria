"""builds _exteria_dexnative for the host python so the native path of the dex runtime can be tested

the sources are the ones the app links (core/dexnative and core/pyhost/exteria_dexnative_module.c), compiled with the cc
of the machine against the headers of the python that runs the tests. EXTERIA_DEXNATIVE_MODULE names a folder that
already holds the built module and skips the build. load() answers None when there is no compiler or no Python.h"""

import importlib
import os
import shutil
import sys
import sysconfig
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_module = []
_reason = []


def reason():
    return _reason[0] if _reason else ""


def load():
    if _module:
        return _module[0]
    found = None
    prebuilt = os.environ.get("EXTERIA_DEXNATIVE_MODULE")
    folder = prebuilt or _build()
    if folder:
        sys.path.insert(0, folder)
        try:
            found = importlib.import_module("_exteria_dexnative")
        except ImportError as error:
            _reason.append("the module did not import: %s" % error)
        finally:
            sys.path.remove(folder)
    _module.append(found)
    return found


def _build():
    compiler = os.environ.get("CC") or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    include = sysconfig.get_paths().get("include")
    if not compiler:
        _reason.append("no c compiler")
        return None
    if not include or not os.path.isfile(os.path.join(include, "Python.h")):
        _reason.append("no Python.h for this python")
        return None
    folder = tempfile.mkdtemp(prefix="exteria-dexnative-")
    suffix = sysconfig.get_config_var("EXT_SUFFIX") or ".so"
    command = [compiler, "-O2", "-std=c99", "-D_POSIX_C_SOURCE=200809L", "-D_DEFAULT_SOURCE", "-Wall", "-Wextra", "-Werror",
               "-Wno-cast-function-type", "-fPIC", "-shared", "-isystem", include,
               "-I" + os.path.join(ROOT, "core", "dexnative"), "-I" + os.path.join(ROOT, "core", "pyhost"),
               os.path.join(ROOT, "core", "pyhost", "exteria_dexnative_module.c"),
               os.path.join(ROOT, "core", "dexnative", "exteria_dexnative.c"),
               "-o", os.path.join(folder, "_exteria_dexnative" + suffix)]
    # posix_spawn, not subprocess: the shim of the dex runtime is on the path of these tests and its _posixsubprocess refuses
    # to start a process, as it must on ios
    log = os.path.join(folder, "build.log")
    actions = [(os.POSIX_SPAWN_OPEN, 1, log, os.O_WRONLY | os.O_CREAT, 0o600), (os.POSIX_SPAWN_DUP2, 1, 2)]
    pid = os.posix_spawnp(command[0], command, os.environ, file_actions=actions)
    _, status = os.waitpid(pid, 0)
    if status != 0:
        with open(log, encoding="utf-8", errors="replace") as handle:
            _reason.append("the build failed: %s" % handle.read()[-500:])
        return None
    return folder
