"""what the code run by the vm may reach

the vm runs in the process of the app with the rights of the app. an embedding that runs code it does not trust sets
FILE_ROOTS to the folders that code may use; every file operation of java.io checks the real path against them first
and raises SecurityException outside. the default is no restriction, which is not a sandbox: a wall against hostile
code is the job of the process, not of this check"""

import os

FILE_ROOTS = None


def check_path(path, mode):
    roots = FILE_ROOTS
    if roots is None:
        return
    resolved = os.path.realpath(path)
    for root in roots:
        base = os.path.realpath(root)
        if resolved == base or resolved.startswith(base.rstrip(os.sep) + os.sep):
            return
    from . import runtime
    runtime.throw_new("java.lang.SecurityException", "%s access to %s is outside the allowed folders" % (mode, path))
