"""the cache of translated methods

translating a method costs more than running it once, and a plugin loads the same dex on every launch. the cache keeps,
for a method, the compiled python code of its translation and the tables the code needs, in a folder the embedding names
with configure(). nothing is cached until it does

an entry is valid for one dex content (its sha-256), one method of it, one translator and one python: the translator is
identified by a digest of the code of translate.py and opcodes.py, so a change of either empties the cache by itself. a
translation also depends on what the translator asked about the classes around the method (which of them are classes of
a dex file, where their fields live); those answers are stored with the entry and asked again on every load, and an
entry whose answers changed is translated again

files are written to a temporary name and renamed, so a reader sees a whole entry or none. the total size is capped
(64 MiB) and so is one entry (2 MiB); the oldest entries go first. an entry that is damaged, truncated or of another
version is deleted and counted in stats. the folder must belong to the app: entries are read with marshal, whose input
must be trusted. a failure to write or read never stops the program, it is counted in stats and logged"""

import hashlib
import logging
import marshal
import os
import sys
import tempfile
import threading
import types

log = logging.getLogger("dexvm.cache")

MAGIC = b"DXM1"
MAX_TOTAL = 64 * 1024 * 1024
MAX_ENTRY = 2 * 1024 * 1024
SUFFIX = ".dxm"

_fingerprint = None
_cache = None


def fingerprint():
    """a digest of the translator and of the python that will run its output"""
    global _fingerprint
    if _fingerprint is None:
        from . import opcodes, translate
        digest = hashlib.sha256()
        digest.update(sys.version.encode())
        digest.update(str(marshal.version).encode())
        for module in (translate, opcodes):
            for name in sorted(vars(module)):
                value = vars(module)[name]
                members = [value] if isinstance(value, types.FunctionType) else (
                    [vars(value)[key] for key in sorted(vars(value))] if isinstance(value, type) and
                    value.__module__ == module.__name__ else [])
                for member in members:
                    function = getattr(member, "__func__", member)
                    code = getattr(function, "__code__", None)
                    if code is not None:
                        digest.update(name.encode())
                        digest.update(marshal.dumps(code))
        _fingerprint = digest.hexdigest()
    return _fingerprint


class RecordingEnv:
    """the translator's view of the classes around a method, remembering every question and its answer"""

    def __init__(self, env):
        self._env = env
        self.log = []

    def dex_class(self, descriptor):
        answer = self._env.dex_class(descriptor)
        self.log.append(("dex_class", descriptor, bool(answer)))
        return answer

    def instance_field(self, class_desc, name, type_desc):
        answer = self._env.instance_field(class_desc, name, type_desc)
        self.log.append(("instance_field", class_desc, name, type_desc, answer))
        return answer

    def own_static(self, class_desc, name, type_desc):
        answer = self._env.own_static(class_desc, name, type_desc)
        self.log.append(("own_static", class_desc, name, type_desc, answer))
        return answer


def still_true(entries, env):
    """whether the classes around a method still answer the questions of a stored translation as they did"""
    for entry in entries:
        kind, args, answer = entry[0], entry[1:-1], entry[-1]
        if getattr(env, kind)(*args) != answer:
            return False
    return True


class MethodCache:
    def __init__(self, directory, max_total=MAX_TOTAL, max_entry=MAX_ENTRY):
        self.directory = directory
        self.max_total = max_total
        self.max_entry = max_entry
        self.stats = {"hits": 0, "misses": 0, "stores": 0, "rejected": 0, "oversize": 0, "evicted": 0, "errors": 0}
        self.last_error = None
        self._lock = threading.Lock()
        self._total = None
        os.makedirs(directory, exist_ok=True)
        self._sweep_temporaries()

    def _sweep_temporaries(self):
        for name in os.listdir(self.directory):
            if name.startswith(".tmp-"):
                self._remove(os.path.join(self.directory, name))

    def _remove(self, path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        except OSError as error:
            self._fail("remove %s" % path, error)

    def _fail(self, what, error):
        self.stats["errors"] += 1
        self.last_error = "%s: %s" % (what, error)
        # a folder that cannot be written fails on every method: say it once and then at every hundredth failure
        if self.stats["errors"] % 100 == 1:
            log.warning("dex method cache: %s (%d failures so far)", self.last_error, self.stats["errors"])

    def path(self, key):
        return os.path.join(self.directory, hashlib.sha256(key.encode()).hexdigest() + SUFFIX)

    def get(self, key):
        """the stored payload for key or None"""
        path = self.path(key)
        try:
            with open(path, "rb") as handle:
                data = handle.read(self.max_entry + 4096)
        except FileNotFoundError:
            self.stats["misses"] += 1
            return None
        except OSError as error:
            self._fail("read %s" % path, error)
            return None
        payload = self._open(data, key)
        if payload is None:
            self.stats["rejected"] += 1
            self._forget(path, len(data))
            return None
        try:
            os.utime(path)
        except OSError:
            pass
        self.stats["hits"] += 1
        return payload

    def _open(self, data, key):
        if len(data) < 36 or data[:4] != MAGIC or len(data) > self.max_entry + 4096:
            return None
        body = data[36:]
        if hashlib.sha256(body).digest() != data[4:36]:
            return None
        try:
            stored_key, payload = marshal.loads(body)
        except (EOFError, ValueError, TypeError):
            return None
        return payload if stored_key == key else None

    def put(self, key, payload):
        """store payload (marshal-able) under key; entries over the limit are skipped"""
        try:
            body = marshal.dumps((key, payload))
        except ValueError as error:
            self._fail("marshal", error)
            return
        data = MAGIC + hashlib.sha256(body).digest() + body
        if len(data) > self.max_entry:
            self.stats["oversize"] += 1
            return
        path = self.path(key)
        try:
            handle, temporary = tempfile.mkstemp(prefix=".tmp-", dir=self.directory)
            try:
                with os.fdopen(handle, "wb") as out:
                    out.write(data)
                os.replace(temporary, path)
            except BaseException:
                self._remove(temporary)
                raise
        except OSError as error:
            self._fail("write %s" % path, error)
            return
        self.stats["stores"] += 1
        with self._lock:
            if self._total is None:
                self._total = self._scan()
            else:
                self._total += len(data)
            if self._total > self.max_total:
                self._trim()

    def _scan(self):
        total = 0
        for name in os.listdir(self.directory):
            if name.endswith(SUFFIX):
                try:
                    total += os.stat(os.path.join(self.directory, name)).st_size
                except OSError:
                    pass
        return total

    def _forget(self, path, size):
        self._remove(path)
        with self._lock:
            if self._total is not None:
                self._total = max(self._total - size, 0)

    def _trim(self):
        """drop the least recently used entries until the cache is at nine tenths of its limit"""
        entries = []
        for name in os.listdir(self.directory):
            if name.endswith(SUFFIX):
                path = os.path.join(self.directory, name)
                try:
                    status = os.stat(path)
                except OSError:
                    continue
                entries.append((status.st_mtime, status.st_size, path))
        entries.sort()
        total = sum(size for _, size, _ in entries)
        goal = self.max_total * 9 // 10
        for _, size, path in entries:
            if total <= goal:
                break
            self._remove(path)
            total -= size
            self.stats["evicted"] += 1
        self._total = total

    def clear(self):
        for name in os.listdir(self.directory):
            if name.endswith(SUFFIX) or name.startswith(".tmp-"):
                self._remove(os.path.join(self.directory, name))
        with self._lock:
            self._total = 0


def configure(directory, max_total=MAX_TOTAL, max_entry=MAX_ENTRY):
    """start caching translated methods in directory; None stops. returns the cache"""
    global _cache
    _cache = None if directory is None else MethodCache(directory, max_total, max_entry)
    return _cache


def current():
    return _cache


def method_key(dex_digest, method_index):
    return "%s:%d:%s" % (dex_digest, method_index, fingerprint())
