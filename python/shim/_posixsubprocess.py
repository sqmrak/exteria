"""_posixsubprocess for a system that cannot fork. the real module needs fork(), which the arm64 sdk of ios marks
unavailable, so the extension is not built. subprocess calls fork_exec here, and this one starts the program with
os.posix_spawn, which both slices of the app have: the descriptors of the child are made with file actions, the failure of
the exec comes back as an exception of the parent instead of through the error pipe.

what posix_spawn cannot do is refused with ENOSYS, never ignored: preexec_fn, uid, gid, extra groups, umask and
start_new_session. a working directory is made by the shell of the device, which changes into it and execs the program, so cwd
needs /bin/sh and the child sees the path of the program as its argv[0]. asyncio imports subprocess at the top, so this module
also keeps every plugin that uses asyncio importable. the audit gate of the plugin sdk lets a plugin start a process only
with the native permission"""

import errno
import os
import signal
import threading

# one spawn at a time: the descriptors passed to a child are made inheritable in the parent for the length of the call
_lock = threading.Lock()

_REFUSED = "a process on ios is started with posix_spawn, which cannot set %s of the child"


def _refuse(what):
    raise OSError(errno.ENOSYS, _REFUSED % what)


def _leaking_fds(keep):
    """the open descriptors above 2 that a child would inherit: those not marked close-on-exec and not asked for. python makes
    its own descriptors close-on-exec, so this finds what native code left open"""
    try:
        names = os.listdir("/dev/fd")
    except OSError:
        return []
    found = []
    for name in names:
        if not name.isdigit():
            continue
        fd = int(name)
        if fd < 3 or fd in keep:
            continue
        try:
            if os.get_inheritable(fd):
                found.append(fd)
        except OSError:
            # the descriptor of the listing itself, closed by now
            pass
    return found


def fork_exec(args, executable_list, close_fds, pass_fds, cwd, env_list, p2cread, p2cwrite, c2pread, c2pwrite, errread, errwrite,
              errpipe_read, errpipe_write, restore_signals, call_setsid, pgid_to_set, gid, extra_groups, uid, child_umask,
              preexec_fn, allow_vfork):
    if preexec_fn is not None:
        _refuse("a function to run before the exec")
    if gid is not None or extra_groups is not None or uid is not None:
        _refuse("the user or the group")
    if child_umask is not None and child_umask >= 0:
        _refuse("the umask")
    if call_setsid:
        _refuse("a new session")

    if cwd is not None:
        args, executable_list = _in_directory(args, executable_list, cwd)

    # no list means the child inherits the environment of this process
    env = os.environ
    if env_list is not None:
        env = {}
        for entry in env_list:
            name, _, value = os.fsencode(entry).partition(b"=")
            env[name] = value

    options = {}
    if restore_signals:
        options["setsigdef"] = [signal.SIGPIPE] + ([signal.SIGXFSZ] if hasattr(signal, "SIGXFSZ") else [])
    if pgid_to_set is not None and pgid_to_set >= 0:
        options["setpgroup"] = pgid_to_set

    with _lock:
        lifted = []

        def lift(fd):
            """a descriptor that sits on 0, 1 or 2 would be overwritten by the duplication of another, so it is moved above them first"""
            if 0 <= fd < 3:
                moved = os.dup(fd)
                lifted.append(moved)
                return moved
            return fd

        actions = []
        for source, target in ((p2cread, 0), (c2pwrite, 1), (errwrite, 2)):
            if source != -1:
                actions.append((os.POSIX_SPAWN_DUP2, lift(source), target))
        inherited = [fd for fd in pass_fds if fd > 2 and fd != errpipe_write]
        if close_fds:
            for fd in _leaking_fds(set(inherited)):
                actions.append((os.POSIX_SPAWN_CLOSE, fd))
        made_inheritable = []
        try:
            for fd in inherited:
                if not os.get_inheritable(fd):
                    os.set_inheritable(fd, True)
                    made_inheritable.append(fd)
            return _spawn(args, executable_list, env, actions, options)
        finally:
            for fd in made_inheritable:
                try:
                    os.set_inheritable(fd, False)
                except OSError:
                    pass
            for fd in lifted:
                os.close(fd)


SHELL = "/bin/sh"
_CHANGE_DIRECTORY = 'cd -- "$1" || exit 126; shift; exec "$@"'


def _in_directory(args, executable_list, cwd):
    """the arguments of the shell that runs the program in cwd. the directory and the program are checked here, so the errors are
    the ones the real module raises and not an exit status of the shell"""
    directory = os.fsdecode(cwd)
    if not os.path.isdir(directory):
        raise OSError(errno.ENOTDIR if os.path.exists(directory) else errno.ENOENT, os.strerror(errno.ENOTDIR if os.path.exists(directory) else errno.ENOENT), directory)
    if not os.access(directory, os.X_OK):
        raise OSError(errno.EACCES, os.strerror(errno.EACCES), directory)
    if not os.path.exists(SHELL):
        raise OSError(errno.ENOENT, "the working directory of a program is made by the shell of the device, and it has none", SHELL)
    name = os.fsencode(args[0]) if args else b""
    for path in executable_list:
        # a relative path is the one of the new directory, the way the exec of the real child sees it
        full = path if os.path.isabs(path) else os.path.join(os.fsencode(directory), path)
        if os.path.isfile(full) and os.access(full, os.X_OK) and (path == name or path.endswith(b"/" + name)):
            return [SHELL, "-c", _CHANGE_DIRECTORY, "sh", directory, os.fsdecode(path)] + list(args[1:]), (os.fsencode(SHELL),)
    raise OSError(errno.ENOENT, os.strerror(errno.ENOENT), os.fsdecode(name))


def _spawn(args, executable_list, env, actions, options):
    """the first program of the list that starts: a missing file or directory goes on to the next, any other error is kept and
    raised at the end, as the real module reports them"""
    kept = errno.ENOENT
    for path in executable_list:
        try:
            return os.posix_spawn(path, args, env, file_actions=actions, **options)
        except OSError as error:
            if error.errno not in (errno.ENOENT, errno.ENOTDIR):
                kept = error.errno
    raise OSError(kept, os.strerror(kept), os.fsdecode(args[0]) if args else None)
