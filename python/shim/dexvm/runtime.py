"""java value semantics the translated code leans on

values are python objects: int for boolean, byte, short, char, int and long (always in the signed range of their
type, a char as its code unit), float for float and double (a float rounded to 32 bits), str of utf-16 code units for
String, None for null, JArray for arrays. every function here returns a value in that representation"""

import math
import struct
import sys
import threading

from . import api, limits

INT_MIN = -0x80000000
INT_MAX = 0x7FFFFFFF
LONG_MIN = -0x8000000000000000
LONG_MAX = 0x7FFFFFFFFFFFFFFF

_FLOAT = struct.Struct("<f")
_DOUBLE = struct.Struct("<d")
_INT = struct.Struct("<i")
_UINT = struct.Struct("<I")
_LONG = struct.Struct("<q")
_ULONG = struct.Struct("<Q")


def throw_new(name, message=None):
    """raise a new instance of the host exception class name; the caller never returns"""
    host = api.lookup_host(name)
    if host is None:
        raise RuntimeError("java class missing for an error: " + name)
    raise make_throwable(host.py, message)


def make_throwable(py, message=None):
    exc = py.__new__(py)
    exc._message = message
    exc._cause = None
    return exc


def npe(what=None):
    throw_new("java.lang.NullPointerException", what)


def wrap32(value):
    return (value + 0x80000000 & 0xFFFFFFFF) - 0x80000000


def wrap64(value):
    return (value + 0x8000000000000000 & 0xFFFFFFFFFFFFFFFF) - 0x8000000000000000


def f32(value):
    """round a python float to the nearest float32 value, overflowing to infinity as the cast does"""
    try:
        return _FLOAT.unpack(_FLOAT.pack(value))[0]
    except OverflowError:
        return math.inf if value > 0 else -math.inf


def idiv(a, b):
    if b == 0:
        throw_new("java.lang.ArithmeticException", "divide by zero")
    quotient = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        quotient = -quotient
    return quotient if quotient != 0x80000000 else INT_MIN


def irem(a, b):
    if b == 0:
        throw_new("java.lang.ArithmeticException", "divide by zero")
    result = abs(a) % abs(b)
    return -result if a < 0 else result


def ldiv(a, b):
    if b == 0:
        throw_new("java.lang.ArithmeticException", "divide by zero")
    quotient = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        quotient = -quotient
    return quotient if quotient != 0x8000000000000000 else LONG_MIN


def lrem(a, b):
    if b == 0:
        throw_new("java.lang.ArithmeticException", "divide by zero")
    result = abs(a) % abs(b)
    return -result if a < 0 else result


def fdiv(a, b):
    try:
        return f32(a / b)
    except ZeroDivisionError:
        return _div_by_zero(a, b)


def ddiv(a, b):
    try:
        return a / b
    except ZeroDivisionError:
        return _div_by_zero(a, b)


def _div_by_zero(a, b):
    if a != a or a == 0:
        return math.nan
    negative = (a < 0) != (math.copysign(1.0, b) < 0)
    return -math.inf if negative else math.inf


def frem(a, b):
    return f32(drem(a, b))


def drem(a, b):
    if a != a or b != b or b == 0 or math.isinf(a):
        return math.nan
    if math.isinf(b):
        return a
    return math.fmod(a, b)


def d2i(value):
    if value != value:
        return 0
    if value >= 2147483647.0:
        return INT_MAX
    if value <= -2147483648.0:
        return INT_MIN
    return int(value)


def d2l(value):
    if value != value:
        return 0
    if value >= 9.223372036854775807e18:
        return LONG_MAX
    if value <= -9.223372036854775808e18:
        return LONG_MIN
    return int(value)


def cmpl(a, b):
    if a != a or b != b:
        return -1
    return (a > b) - (a < b)


def cmpg(a, b):
    if a != a or b != b:
        return 1
    return (a > b) - (a < b)


def bits_to_float(bits):
    """a dex register that holds raw 32-bit constant bits, read as a float"""
    return _FLOAT.unpack(_INT.pack(bits))[0]


def bits_to_double(bits):
    return _DOUBLE.unpack(_LONG.pack(bits))[0]


def as_float(value):
    return value if value.__class__ is float else bits_to_float(value)


def as_double(value):
    return value if value.__class__ is float else bits_to_double(value)


def float_bits(value):
    return _INT.unpack(_FLOAT.pack(value))[0]


def double_bits(value):
    return _LONG.unpack(_DOUBLE.pack(value))[0]


class JArray(list):
    """a java array: a list of fixed length that remembers its type. the translated code checks bounds itself"""

    __slots__ = ("jtype",)

    def __init__(self, jtype, values=()):
        list.__init__(self, values)
        self.jtype = jtype

    @property
    def length(self):
        return len(self)

    def clone(self):
        return JArray(self.jtype, self)

    def getClass(self):
        return self.jtype

    def hashCode(self):
        return id(self) >> 4 & 0x7FFFFFFF

    def equals(self, other):
        return self is other

    def toString(self):
        return "%s@%x" % (self.jtype.getName(), self.hashCode())

    def __eq__(self, other):
        return self is other

    def __ne__(self, other):
        return self is not other

    __hash__ = object.__hash__


_DEFAULTS = {"Z": 0, "B": 0, "S": 0, "C": 0, "I": 0, "J": 0, "F": 0.0, "D": 0.0}

# byte, short, char and boolean values are narrowed to their type when they are stored
_NARROW = {
    "Z": lambda v: v & 1,
    "B": lambda v: (v + 128 & 0xFF) - 128,
    "S": lambda v: (v + 32768 & 0xFFFF) - 32768,
    "C": lambda v: v & 0xFFFF,
}


def default_value(code):
    return _DEFAULTS.get(code)


_array_types = {}
_array_lock = threading.Lock()


def array_type_of(descriptor, component=None):
    """the ArrayType of an array descriptor over primitives and host classes; a loader that knows dex classes passes the component itself"""
    found = _array_types.get(descriptor) if component is None else None
    if found is not None:
        return found
    if component is None:
        element = descriptor[1:]
        if len(element) == 1:
            component = api.PRIMITIVES[element]
        elif element[0] == "[":
            component = array_type_of(element)
        else:
            component = api.lookup_host(element[1:-1].replace("/", "."))
            if component is None:
                raise_no_class(element)
    found = api.ArrayType(descriptor, component)
    if component is None or not getattr(component, "loader_bound", False):
        with _array_lock:
            found = _array_types.setdefault(descriptor, found)
    return found


def raise_no_class(descriptor):
    throw_new("java.lang.NoClassDefFoundError", api.binary_name(descriptor))


def new_array(jtype, length):
    """a zeroed array; jtype is an ArrayType or an array descriptor of primitives and host classes"""
    if isinstance(jtype, str):
        jtype = array_type_of(jtype)
    if length < 0:
        throw_new("java.lang.NegativeArraySizeException", str(length))
    if length > limits.MAX_ARRAY_LENGTH:
        throw_new("java.lang.OutOfMemoryError", "Failed to allocate an array of %d elements" % length)
    limits.charge_elements(length)
    code = jtype.descriptor[1]
    default = _DEFAULTS.get(code)
    return JArray(jtype, [default] * length)


def new_multi_array(jtype, dims):
    """new int[a][b]: jtype is the full array type, dims the sizes given"""
    for size in dims:
        if size < 0:
            throw_new("java.lang.NegativeArraySizeException", str(size))

    def build(kind, depth):
        array = new_array(kind, dims[depth])
        if depth + 1 < len(dims):
            inner = kind.component
            for index in range(len(array)):
                array[index] = build(inner, depth + 1)
        return array
    return build(jtype, 0)


def array_from(jtype, values):
    return JArray(jtype, values)


def aioobe(array, index):
    if array is None:
        npe()
    throw_new("java.lang.ArrayIndexOutOfBoundsException",
              "length=%d; index=%d" % (len(array), index))


def array_store_check(array, value):
    """aput-object: the value must fit the component type, else ArrayStoreException"""
    if value is None:
        return
    component = array.jtype.component
    if not instance_of(value, component):
        throw_new("java.lang.ArrayStoreException", type_name_of(value))


def array_fill(array, width, raw):
    """fill-array-data: the payload bytes, little endian elements of width bytes"""
    if array is None:
        npe()
    code = array.jtype.descriptor[1]
    count = len(raw) // width
    if count > len(array):
        throw_new("java.lang.ArrayIndexOutOfBoundsException", "length=%d; index=%d" % (len(array), count - 1))
    if code == "F":
        values = struct.unpack("<%df" % count, raw)
    elif code == "D":
        values = struct.unpack("<%dd" % count, raw)
    elif code in ("B", "Z"):
        values = struct.unpack("<%db" % count, raw) if code == "B" else tuple(raw)
    elif code == "S":
        values = struct.unpack("<%dh" % count, raw)
    elif code == "C":
        values = struct.unpack("<%dH" % count, raw)
    elif code == "I":
        values = struct.unpack("<%di" % count, raw)
    elif code == "J":
        values = struct.unpack("<%dq" % count, raw)
    else:
        throw_new("java.lang.IllegalArgumentException", "array payload for a reference array")
    array[:count] = values


def type_name_of(value):
    return class_of(value).getName()


def class_of(value):
    """the JType of a value, the runtime class getClass() answers with"""
    if value is None:
        npe()
    jtype = getattr(value.__class__, "_jclass", None)
    if jtype is not None:
        return jtype
    if value.__class__ is JArray:
        return value.jtype
    host = api.host_for_pytype(value.__class__)
    if host is None:
        return api.lookup_host("java.lang.Object")
    return host


def instance_of(value, jtype):
    """value is a non-null instance of the type"""
    if value is None:
        return False
    return bool(jtype.isInstance(value))


def check_cast(value, jtype):
    if value is not None and not jtype.isInstance(value):
        throw_new("java.lang.ClassCastException",
                  "%s cannot be cast to %s" % (type_name_of(value), jtype.getName()))
    return value


class Monitor:
    """the lock of an object: reentrant, with wait and notify"""

    __slots__ = ("condition", "owner", "count")

    def __init__(self):
        self.condition = threading.Condition(threading.RLock())
        self.owner = None
        self.count = 0


_monitors = {}
_monitor_guard = threading.Lock()


def monitor_of(obj):
    if obj is None:
        npe()
    try:
        monitor = obj.__dict__["_jmonitor"]
    except (AttributeError, KeyError):
        pass
    else:
        return monitor
    key = id(obj)
    with _monitor_guard:
        entry = _monitors.get(key)
        if entry is None:
            monitor = Monitor()
            # objects that cannot carry an attribute (str, int) are held by id for the life of the process, java strings used as locks are literals
            try:
                obj.__dict__["_jmonitor"] = monitor
            except (AttributeError, TypeError):
                _monitors[key] = (obj, monitor)
            return monitor
        return entry[1]


def monitor_enter(obj):
    monitor = monitor_of(obj)
    monitor.condition.acquire()
    monitor.owner = threading.get_ident()
    monitor.count += 1


def monitor_exit(obj):
    monitor = monitor_of(obj)
    if monitor.owner != threading.get_ident():
        throw_new("java.lang.IllegalMonitorStateException", "object not locked by thread before unlock")
    monitor.count -= 1
    if monitor.count == 0:
        monitor.owner = None
    monitor.condition.release()


def monitor_wait(obj, timeout_ms=0):
    monitor = monitor_of(obj)
    if monitor.owner != threading.get_ident():
        throw_new("java.lang.IllegalMonitorStateException", "object not locked by thread before wait()")
    saved = monitor.count
    monitor.owner = None
    monitor.count = 0
    try:
        monitor.condition.wait(timeout_ms / 1000.0 if timeout_ms else None)
    finally:
        monitor.owner = threading.get_ident()
        monitor.count = saved


def monitor_notify(obj, everyone=False):
    monitor = monitor_of(obj)
    if monitor.owner != threading.get_ident():
        throw_new("java.lang.IllegalMonitorStateException", "object not locked by thread before notify()")
    if everyone:
        monitor.condition.notify_all()
    else:
        monitor.condition.notify()


def to_throwable(error):
    """the java throwable a python exception stands for. a java throwable is itself; the python errors the vm itself causes map to the java error they would be, any other python exception is an InternalError carrying its text"""
    base = api.lookup_host("java.lang.Throwable")
    if isinstance(error, base.py):
        return error
    if isinstance(error, (AttributeError, TypeError)) and "NoneType" in str(error):
        return make_throwable(api.lookup_host("java.lang.NullPointerException").py, str(error))
    if isinstance(error, RecursionError):
        return make_throwable(api.lookup_host("java.lang.StackOverflowError").py, None)
    if isinstance(error, MemoryError):
        return make_throwable(api.lookup_host("java.lang.OutOfMemoryError").py, None)
    if isinstance(error, AttributeError):
        return make_throwable(api.lookup_host("java.lang.NoSuchMethodError").py, str(error))
    if isinstance(error, ZeroDivisionError):
        return make_throwable(api.lookup_host("java.lang.ArithmeticException").py, "divide by zero")
    if isinstance(error, KeyboardInterrupt):
        raise error
    wrapped = make_throwable(api.lookup_host("java.lang.InternalError").py,
                             "%s: %s" % (type(error).__name__, error))
    wrapped.__cause__ = error
    return wrapped


# called when a java thread starts, on the starting thread; each returns a function the new thread runs first
THREAD_START_HOOKS = []

# the interpreter limit a java program needs: javac code recurses thousands of frames deep
RECURSION_LIMIT = 6000


def configure_interpreter():
    if sys.getrecursionlimit() < RECURSION_LIMIT:
        sys.setrecursionlimit(RECURSION_LIMIT)
