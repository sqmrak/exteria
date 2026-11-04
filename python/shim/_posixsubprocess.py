"""_posixsubprocess for a system that cannot fork. the real module needs fork(), which the arm64 sdk of ios marks
unavailable, so the extension is not built. asyncio imports subprocess at the top and subprocess imports this, so without it
no plugin can use asyncio (zwylib is one). importing works; starting a process fails with the error below, and the audit
gate keeps subprocess away from plugins in any case"""

import errno


def fork_exec(*_args, **_kwargs):
    raise OSError(errno.ENOSYS, "a process cannot be started on ios")
