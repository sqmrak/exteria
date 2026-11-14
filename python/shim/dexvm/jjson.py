"""org.json: JSONObject, JSONArray, JSONTokener, JSONStringer and JSONException

the behaviour is the one of the android runtime, not of the json.org reference: a JSONObject keeps insertion order,
put(name, null) removes the name, the tokener accepts comments, single quotes, unquoted names and `=`, `=>` and `;`
as separators, the typed getters coerce strings and numbers, and a double with an integral value prints without a
fraction. plugins written against android rely on every one of these"""

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jequals, jhash, jstring
from .jlang import Boolean, Byte, Character, Double, Float, Integer, Long, Object, Short, float_to_string
from .jlang import _parse_float
from .jmap import LinkedHashSet, Map
from .jutil import Collection, PyIterator, check_nonnull, iterate

# deep input is refused before the python stack gives out
MAX_DEPTH = 256

_NUMBER_BOXES = (Integer, Long, Short, Byte, Float, Double)

def _json_error(message):
    runtime.throw_new("org.json.JSONException", message)


@host_class("org.json.JSONException")
class JSONException(lookup_host("java.lang.Exception").py):
    pass


class _Null(Object):
    """JSONObject.NULL: equal to null and to itself, prints as null"""

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if other is None or other is self else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return 0

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "null"


NULL = _Null()


def _is_number(value):
    return isinstance(value, _NUMBER_BOXES)


def _check_double(value):
    if value != value or value in (float("inf"), float("-inf")):
        _json_error("Forbidden numeric value: " + float_to_string(value, False))
    return value


def number_to_string(number):
    """the text of a number: an integral double prints as a long, as android does, and -0.0 as -0"""
    value = float(number.doubleValue()) if hasattr(number, "doubleValue") else float(number.value)
    _check_double(value)
    if value == 0.0 and str(value).startswith("-"):
        return "-0"
    as_long = int(value) if abs(value) < 9.3e18 else None
    if as_long is not None and runtime.wrap64(as_long) == as_long and float(as_long) == value:
        return str(as_long)
    return number.toString()


def _quote(text):
    out = ['"']
    for char in text:
        code = ord(char)
        if char in '"\\':
            out.append("\\" + char)
        elif char == "/":
            out.append("\\/")
        elif char == "\t":
            out.append("\\t")
        elif char == "\b":
            out.append("\\b")
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif char == "\f":
            out.append("\\f")
        elif code <= 0x1F or code in (0x2028, 0x2029):
            out.append("\\u%04x" % code)
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def _to_boolean(value):
    if isinstance(value, Boolean):
        return bool(value.value)
    if value.__class__ is str:
        lowered = value.lower()
        if lowered == "true":
            return True
        if lowered == "false":
            return False
    return None


def _parse_double(text):
    try:
        return _parse_float(text)
    except lookup_host("java.lang.NumberFormatException").py:
        return None


def _to_double(value):
    if _is_number(value):
        return float(value.value)
    if value.__class__ is str:
        return _parse_double(value)
    return None


def _to_int(value):
    if isinstance(value, (Integer, Short, Byte)):
        return value.value
    if _is_number(value):
        return value.intValue()
    if value.__class__ is str:
        parsed = _parse_double(value)
        return None if parsed is None else runtime.d2i(parsed)
    return None


def _to_long(value):
    if isinstance(value, (Integer, Long, Short, Byte)):
        return value.value
    if _is_number(value):
        return value.longValue()
    if value.__class__ is str:
        parsed = _parse_double(value)
        return None if parsed is None else runtime.d2l(parsed)
    return None


def _to_text(value):
    if value.__class__ is str:
        return value
    return None if value is None else jstring(value)


def _mismatch(name, actual, required):
    if actual is None:
        _json_error("Value at %s is null." % name)
    _json_error("Value %s at %s of type %s cannot be converted to %s" % (
        jstring(actual), name, runtime.class_of(actual).getName(), required))


def _box_int(value):
    return Integer.valueOf(runtime.wrap32(value))


def _box_bool(value):
    return Boolean.TRUE if value else Boolean.FALSE


def wrap(value):
    """a java value as a json value: collections, arrays and maps become json containers, an unknown object its text
    when it belongs to the java packages, and null for anything else"""
    if value is None:
        return NULL
    if value is NULL or isinstance(value, (JSONArray, JSONObject)):
        return value
    if value.__class__ is str or isinstance(value, (Boolean, Character, Double, Float, Integer, Long, Short, Byte)):
        return value
    if value.__class__ is runtime.JArray or isinstance(value, Collection):
        return JSONArray(value)
    if isinstance(value, Map):
        return JSONObject(value)
    if runtime.class_of(value).getName().startswith("java."):
        return value.toString()
    return None


def _scalar_text(value):
    """the json text of a value that is not a container"""
    if value is None or value is NULL or isinstance(value, Boolean):
        return jstring(value)
    if _is_number(value):
        return number_to_string(value)
    return _quote(jstring(value))


@host_class("org.json.JSONStringer")
class JSONStringer(Object):
    """a writer of json text: array(), object(), key() and value() calls, closed with endArray() and endObject()"""

    def __init__(self, indent=0):
        self._out = []
        self._indent = " " * indent
        self._stack = []

    @jmethod("<init>", "()V")
    def _init(self):
        JSONStringer.__init__(self)

    @jmethod("<init>", "(I)V")
    def _init_indent(self, indent):
        JSONStringer.__init__(self, indent)

    def _peek(self):
        if not self._stack:
            _json_error("Nesting problem")
        return self._stack[-1]

    def _newline(self):
        if self._indent:
            self._out.append("\n" + self._indent * len(self._stack))

    def _before_value(self):
        if not self._stack:
            return
        top = self._stack[-1]
        if top == "EMPTY_ARRAY":
            self._stack[-1] = "NONEMPTY_ARRAY"
            self._newline()
        elif top == "NONEMPTY_ARRAY":
            self._out.append(",")
            self._newline()
        elif top == "DANGLING_KEY":
            self._out.append(": " if self._indent else ":")
            self._stack[-1] = "NONEMPTY_OBJECT"
        else:
            _json_error("Nesting problem")

    def _open(self, empty, text):
        if not self._stack and self._out:
            _json_error("Nesting problem: multiple top-level roots")
        if len(self._stack) >= MAX_DEPTH:
            _json_error("Nesting problem: nested deeper than %d levels" % MAX_DEPTH)
        self._before_value()
        self._stack.append(empty)
        self._out.append(text)
        return self

    def _close(self, empty, nonempty, text):
        top = self._peek()
        if top != nonempty and top != empty:
            _json_error("Nesting problem")
        self._stack.pop()
        if top == nonempty:
            self._newline()
        self._out.append(text)
        return self

    @jmethod("array", "()Lorg/json/JSONStringer;")
    def array(self):
        return self._open("EMPTY_ARRAY", "[")

    @jmethod("endArray", "()Lorg/json/JSONStringer;")
    def endArray(self):
        return self._close("EMPTY_ARRAY", "NONEMPTY_ARRAY", "]")

    @jmethod("object", "()Lorg/json/JSONStringer;")
    def object(self):
        return self._open("EMPTY_OBJECT", "{")

    @jmethod("endObject", "()Lorg/json/JSONStringer;")
    def endObject(self):
        return self._close("EMPTY_OBJECT", "NONEMPTY_OBJECT", "}")

    @jmethod("key", "(Ljava/lang/String;)Lorg/json/JSONStringer;")
    def key(self, name):
        if name is None:
            _json_error("Names must be non-null")
        top = self._peek()
        if top == "NONEMPTY_OBJECT":
            self._out.append(",")
        elif top != "EMPTY_OBJECT":
            _json_error("Nesting problem")
        self._newline()
        self._stack[-1] = "DANGLING_KEY"
        self._out.append(_quote(name))
        return self

    @jmethod("value", "(Ljava/lang/Object;)Lorg/json/JSONStringer;")
    def value(self, value):
        if not self._stack:
            _json_error("Nesting problem")
        if isinstance(value, (JSONArray, JSONObject)):
            value.write_to(self)
            return self
        self._before_value()
        self._out.append(_scalar_text(value))
        return self

    @jmethod("value", "(Z)Lorg/json/JSONStringer;")
    def value_bool(self, flag):
        return self.value(_box_bool(flag))

    @jmethod("value", "(D)Lorg/json/JSONStringer;")
    def value_double(self, number):
        return self.value(Double(number))

    @jmethod("value", "(J)Lorg/json/JSONStringer;")
    def value_long(self, number):
        return self.value(Long.valueOf(number))

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "".join(self._out) if self._out else None


@host_class("org.json.JSONObject")
class JSONObject(Object):
    NULL = NULL

    def __init__(self, source=None, names=None):
        self._map = {}
        if source is None:
            return
        if source.__class__ is str:
            self._parse(source)
        elif isinstance(source, JSONTokener):
            self._read(source)
        elif isinstance(source, JSONObject):
            for name in iterate(names if names is not None else ()):
                value = source.opt(name)
                if value is not None:
                    self._map[name] = value
        else:
            if not isinstance(source, Map):
                runtime.throw_new("java.lang.ClassCastException", "not a Map")
            for entry in iterate(source.entrySet()):
                key = entry.getKey()
                if key.__class__ is not str:
                    runtime.npe()
                value = entry.getValue()
                self._map[key] = wrap(value)

    def _parse(self, text):
        self._read(JSONTokener(text))

    def _read(self, tokener):
        parsed = tokener.nextValue()
        if not isinstance(parsed, JSONObject):
            _json_error("Value %s of type %s cannot be converted to JSONObject" % (
                jstring(parsed), "null" if parsed is None else runtime.class_of(parsed).getName()))
        self._map = parsed._map

    @jmethod("<init>", "()V")
    def _init0(self):
        JSONObject.__init__(self)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init_string(self, text):
        JSONObject.__init__(self)
        self._parse(check_nonnull(text))

    @jmethod("<init>", "(Lorg/json/JSONTokener;)V")
    def _init_tokener(self, tokener):
        JSONObject.__init__(self)
        self._read(check_nonnull(tokener))

    @jmethod("<init>", "(Ljava/util/Map;)V")
    def _init_map(self, source):
        JSONObject.__init__(self, check_nonnull(source))

    @jmethod("<init>", "(Lorg/json/JSONObject;[Ljava/lang/String;)V")
    def _init_copy(self, source, names):
        JSONObject.__init__(self, check_nonnull(source), check_nonnull(names))

    @jmethod("length", "()I")
    def length(self):
        return len(self._map)

    def _store(self, name, value):
        self._map[_name(name)] = value
        return self

    @jmethod("put", "(Ljava/lang/String;Z)Lorg/json/JSONObject;")
    def put_bool(self, name, value):
        return self._store(name, _box_bool(value))

    @jmethod("put", "(Ljava/lang/String;D)Lorg/json/JSONObject;")
    def put_double(self, name, value):
        _check_double(value)
        return self._store(name, Double(value))

    @jmethod("put", "(Ljava/lang/String;I)Lorg/json/JSONObject;")
    def put_int(self, name, value):
        return self._store(name, _box_int(value))

    @jmethod("put", "(Ljava/lang/String;J)Lorg/json/JSONObject;")
    def put_long(self, name, value):
        return self._store(name, Long.valueOf(value))

    @jmethod("put", "(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;")
    def put(self, name, value):
        if value is None:
            self._map.pop(_name(name), None)
            return self
        if isinstance(value, (Double, Float)):
            _check_double(float(value.value))
        return self._store(name, value)

    @jmethod("putOpt", "(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;")
    def putOpt(self, name, value):
        if name is None or value is None:
            return self
        return self.put(name, value)

    @jmethod("accumulate", "(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;")
    def accumulate(self, name, value):
        current = self._map.get(_name(name))
        if current is None:
            return self.put(name, value)
        if isinstance(current, JSONArray):
            current.checkedPut(value)
        else:
            array = JSONArray()
            array.checkedPut(current)
            array.checkedPut(value)
            self._map[name] = array
        return self

    @jmethod("append", "(Ljava/lang/String;Ljava/lang/Object;)Lorg/json/JSONObject;")
    def append(self, name, value):
        current = self._map.get(_name(name))
        if isinstance(current, JSONArray):
            array = current
        elif current is None:
            array = JSONArray()
            self._map[name] = array
        else:
            _json_error("Key %s is not a JSONArray" % name)
        array.checkedPut(value)
        return self

    @jmethod("remove", "(Ljava/lang/String;)Ljava/lang/Object;")
    def remove(self, name):
        return self._map.pop(name, None)

    @jmethod("isNull", "(Ljava/lang/String;)Z")
    def isNull(self, name):
        value = self._map.get(name)
        return 1 if value is None or value is NULL else 0

    @jmethod("has", "(Ljava/lang/String;)Z")
    def has(self, name):
        return 1 if name in self._map else 0

    @jmethod("get", "(Ljava/lang/String;)Ljava/lang/Object;")
    def get(self, name):
        result = self._map.get(name)
        if result is None:
            _json_error("No value for " + jstring(name))
        return result

    @jmethod("opt", "(Ljava/lang/String;)Ljava/lang/Object;")
    def opt(self, name):
        return self._map.get(name)

    @jmethod("getBoolean", "(Ljava/lang/String;)Z")
    def getBoolean(self, name):
        value = self.get(name)
        result = _to_boolean(value)
        if result is None:
            _mismatch(name, value, "boolean")
        return 1 if result else 0

    @jmethod("optBoolean", "(Ljava/lang/String;)Z")
    @jmethod("optBoolean", "(Ljava/lang/String;Z)Z")
    def optBoolean(self, name, fallback=0):
        result = _to_boolean(self._map.get(name))
        return (1 if result else 0) if result is not None else (1 if fallback else 0)

    @jmethod("getDouble", "(Ljava/lang/String;)D")
    def getDouble(self, name):
        value = self.get(name)
        result = _to_double(value)
        if result is None:
            _mismatch(name, value, "double")
        return result

    @jmethod("optDouble", "(Ljava/lang/String;)D")
    @jmethod("optDouble", "(Ljava/lang/String;D)D")
    def optDouble(self, name, fallback=float("nan")):
        result = _to_double(self._map.get(name))
        return fallback if result is None else result

    @jmethod("getInt", "(Ljava/lang/String;)I")
    def getInt(self, name):
        value = self.get(name)
        result = _to_int(value)
        if result is None:
            _mismatch(name, value, "int")
        return result

    @jmethod("optInt", "(Ljava/lang/String;)I")
    @jmethod("optInt", "(Ljava/lang/String;I)I")
    def optInt(self, name, fallback=0):
        result = _to_int(self._map.get(name))
        return fallback if result is None else result

    @jmethod("getLong", "(Ljava/lang/String;)J")
    def getLong(self, name):
        value = self.get(name)
        result = _to_long(value)
        if result is None:
            _mismatch(name, value, "long")
        return result

    @jmethod("optLong", "(Ljava/lang/String;)J")
    @jmethod("optLong", "(Ljava/lang/String;J)J")
    def optLong(self, name, fallback=0):
        result = _to_long(self._map.get(name))
        return fallback if result is None else result

    @jmethod("getString", "(Ljava/lang/String;)Ljava/lang/String;")
    def getString(self, name):
        value = self.get(name)
        result = _to_text(value)
        if result is None:
            _mismatch(name, value, "String")
        return result

    @jmethod("optString", "(Ljava/lang/String;)Ljava/lang/String;")
    @jmethod("optString", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    def optString(self, name, fallback=""):
        result = _to_text(self._map.get(name))
        return fallback if result is None else result

    @jmethod("getJSONArray", "(Ljava/lang/String;)Lorg/json/JSONArray;")
    def getJSONArray(self, name):
        value = self.get(name)
        if not isinstance(value, JSONArray):
            _mismatch(name, value, "JSONArray")
        return value

    @jmethod("optJSONArray", "(Ljava/lang/String;)Lorg/json/JSONArray;")
    def optJSONArray(self, name):
        value = self._map.get(name)
        return value if isinstance(value, JSONArray) else None

    @jmethod("getJSONObject", "(Ljava/lang/String;)Lorg/json/JSONObject;")
    def getJSONObject(self, name):
        value = self.get(name)
        if not isinstance(value, JSONObject):
            _mismatch(name, value, "JSONObject")
        return value

    @jmethod("optJSONObject", "(Ljava/lang/String;)Lorg/json/JSONObject;")
    def optJSONObject(self, name):
        value = self._map.get(name)
        return value if isinstance(value, JSONObject) else None

    @jmethod("toJSONArray", "(Lorg/json/JSONArray;)Lorg/json/JSONArray;")
    def toJSONArray(self, names):
        result = JSONArray()
        if names is None:
            return None
        for index in range(names.length()):
            result.checkedPut(self._map.get(_to_text(names.opt(index))))
        return result

    @jmethod("keys", "()Ljava/util/Iterator;")
    def keys(self):
        return PyIterator(list(self._map))

    @jmethod("keySet", "()Ljava/util/Set;")
    def keySet(self):
        result = LinkedHashSet()
        for key in self._map:
            result.add(key)
        return result

    @jmethod("names", "()Lorg/json/JSONArray;")
    def names(self):
        if not self._map:
            return None
        result = JSONArray()
        for key in self._map:
            result.checkedPut(key)
        return result

    def write_to(self, stringer):
        stringer.object()
        for key, value in self._map.items():
            stringer.key(key).value(value)
        stringer.endObject()

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        stringer = JSONStringer()
        self.write_to(stringer)
        return stringer.toString()

    @jmethod("toString", "(I)Ljava/lang/String;")
    def toString_indent(self, indent):
        stringer = JSONStringer(indent)
        self.write_to(stringer)
        return stringer.toString()

    @jstatic("numberToString", "(Ljava/lang/Number;)Ljava/lang/String;")
    def numberToString(number):
        if number is None:
            _json_error("Number must be non-null")
        return number_to_string(number)

    @jstatic("quote", "(Ljava/lang/String;)Ljava/lang/String;")
    def quote(text):
        return '""' if text is None else _quote(text)

    @jstatic("wrap", "(Ljava/lang/Object;)Ljava/lang/Object;")
    def wrap(value):
        return wrap(value)


def _name(name):
    if name is None:
        _json_error("Names must be non-null")
    return name


@host_class("org.json.JSONArray")
class JSONArray(Object):
    def __init__(self, source=None):
        self._items = []
        if source is None:
            return
        if source.__class__ is str:
            self._read(JSONTokener(source))
        elif isinstance(source, JSONTokener):
            self._read(source)
        elif source.__class__ is runtime.JArray:
            for item in source:
                self.checkedPut(wrap(_widen(source, item)))
        else:
            for item in iterate(source):
                self.checkedPut(wrap(item))

    def _read(self, tokener):
        parsed = tokener.nextValue()
        if not isinstance(parsed, JSONArray):
            _json_error("Value %s of type %s cannot be converted to JSONArray" % (
                jstring(parsed), "null" if parsed is None else runtime.class_of(parsed).getName()))
        self._items = parsed._items

    @jmethod("<init>", "()V")
    def _init0(self):
        JSONArray.__init__(self)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init_string(self, text):
        JSONArray.__init__(self, check_nonnull(text))

    @jmethod("<init>", "(Lorg/json/JSONTokener;)V")
    def _init_tokener(self, tokener):
        JSONArray.__init__(self, check_nonnull(tokener))

    @jmethod("<init>", "(Ljava/util/Collection;)V")
    def _init_collection(self, source):
        JSONArray.__init__(self, source if source is not None else None)

    @jmethod("<init>", "(Ljava/lang/Object;)V")
    def _init_array(self, source):
        if source.__class__ is not runtime.JArray:
            _json_error("Not a primitive array: " + runtime.class_of(source).getName())
        JSONArray.__init__(self, source)

    def checkedPut(self, value):
        if isinstance(value, (Double, Float)):
            _check_double(float(value.value))
        self._items.append(value)
        return self

    @jmethod("length", "()I")
    def length(self):
        return len(self._items)

    @jmethod("put", "(Z)Lorg/json/JSONArray;")
    def put_bool(self, value):
        return self.checkedPut(_box_bool(value))

    @jmethod("put", "(D)Lorg/json/JSONArray;")
    def put_double(self, value):
        return self.checkedPut(Double(_check_double(value)))

    @jmethod("put", "(I)Lorg/json/JSONArray;")
    def put_int(self, value):
        return self.checkedPut(_box_int(value))

    @jmethod("put", "(J)Lorg/json/JSONArray;")
    def put_long(self, value):
        return self.checkedPut(Long.valueOf(value))

    @jmethod("put", "(Ljava/lang/Object;)Lorg/json/JSONArray;")
    def put(self, value):
        return self.checkedPut(value)

    def _put_at(self, index, value):
        if isinstance(value, (Double, Float)):
            _check_double(float(value.value))
        if index < 0:
            _json_error("Index %d out of range [0..%d)" % (index, len(self._items)))
        while len(self._items) <= index:
            self._items.append(NULL)
        self._items[index] = value
        return self

    @jmethod("put", "(IZ)Lorg/json/JSONArray;")
    def put_at_bool(self, index, value):
        return self._put_at(index, _box_bool(value))

    @jmethod("put", "(ID)Lorg/json/JSONArray;")
    def put_at_double(self, index, value):
        return self._put_at(index, Double(_check_double(value)))

    @jmethod("put", "(II)Lorg/json/JSONArray;")
    def put_at_int(self, index, value):
        return self._put_at(index, _box_int(value))

    @jmethod("put", "(IJ)Lorg/json/JSONArray;")
    def put_at_long(self, index, value):
        return self._put_at(index, Long.valueOf(value))

    @jmethod("put", "(ILjava/lang/Object;)Lorg/json/JSONArray;")
    def put_at(self, index, value):
        return self._put_at(index, value)

    @jmethod("isNull", "(I)Z")
    def isNull(self, index):
        value = self.opt(index)
        return 1 if value is None or value is NULL else 0

    @jmethod("get", "(I)Ljava/lang/Object;")
    def get(self, index):
        if not 0 <= index < len(self._items):
            _json_error("Index %d out of range [0..%d)" % (index, len(self._items)))
        value = self._items[index]
        if value is None:
            _json_error("Value at %d is null." % index)
        return value

    @jmethod("opt", "(I)Ljava/lang/Object;")
    def opt(self, index):
        return self._items[index] if 0 <= index < len(self._items) else None

    @jmethod("remove", "(I)Ljava/lang/Object;")
    def remove(self, index):
        if not 0 <= index < len(self._items):
            return None
        return self._items.pop(index)

    @jmethod("getBoolean", "(I)Z")
    def getBoolean(self, index):
        value = self.get(index)
        result = _to_boolean(value)
        if result is None:
            _mismatch(index, value, "boolean")
        return 1 if result else 0

    @jmethod("optBoolean", "(I)Z")
    @jmethod("optBoolean", "(IZ)Z")
    def optBoolean(self, index, fallback=0):
        result = _to_boolean(self.opt(index))
        return (1 if result else 0) if result is not None else (1 if fallback else 0)

    @jmethod("getDouble", "(I)D")
    def getDouble(self, index):
        value = self.get(index)
        result = _to_double(value)
        if result is None:
            _mismatch(index, value, "double")
        return result

    @jmethod("optDouble", "(I)D")
    @jmethod("optDouble", "(ID)D")
    def optDouble(self, index, fallback=float("nan")):
        result = _to_double(self.opt(index))
        return fallback if result is None else result

    @jmethod("getInt", "(I)I")
    def getInt(self, index):
        value = self.get(index)
        result = _to_int(value)
        if result is None:
            _mismatch(index, value, "int")
        return result

    @jmethod("optInt", "(I)I")
    @jmethod("optInt", "(II)I")
    def optInt(self, index, fallback=0):
        result = _to_int(self.opt(index))
        return fallback if result is None else result

    @jmethod("getLong", "(I)J")
    def getLong(self, index):
        value = self.get(index)
        result = _to_long(value)
        if result is None:
            _mismatch(index, value, "long")
        return result

    @jmethod("optLong", "(I)J")
    @jmethod("optLong", "(IJ)J")
    def optLong(self, index, fallback=0):
        result = _to_long(self.opt(index))
        return fallback if result is None else result

    @jmethod("getString", "(I)Ljava/lang/String;")
    def getString(self, index):
        value = self.get(index)
        result = _to_text(value)
        if result is None:
            _mismatch(index, value, "String")
        return result

    @jmethod("optString", "(I)Ljava/lang/String;")
    @jmethod("optString", "(ILjava/lang/String;)Ljava/lang/String;")
    def optString(self, index, fallback=""):
        result = _to_text(self.opt(index))
        return fallback if result is None else result

    @jmethod("getJSONArray", "(I)Lorg/json/JSONArray;")
    def getJSONArray(self, index):
        value = self.get(index)
        if not isinstance(value, JSONArray):
            _mismatch(index, value, "JSONArray")
        return value

    @jmethod("optJSONArray", "(I)Lorg/json/JSONArray;")
    def optJSONArray(self, index):
        value = self.opt(index)
        return value if isinstance(value, JSONArray) else None

    @jmethod("getJSONObject", "(I)Lorg/json/JSONObject;")
    def getJSONObject(self, index):
        value = self.get(index)
        if not isinstance(value, JSONObject):
            _mismatch(index, value, "JSONObject")
        return value

    @jmethod("optJSONObject", "(I)Lorg/json/JSONObject;")
    def optJSONObject(self, index):
        value = self.opt(index)
        return value if isinstance(value, JSONObject) else None

    @jmethod("toJSONObject", "(Lorg/json/JSONArray;)Lorg/json/JSONObject;")
    def toJSONObject(self, names):
        result = JSONObject()
        count = min(names.length(), len(self._items))
        if count == 0:
            return None
        for index in range(count):
            result.put(_to_text(names.opt(index)), self.opt(index))
        return result

    @jmethod("join", "(Ljava/lang/String;)Ljava/lang/String;")
    def join(self, separator):
        return separator.join(_scalar_or_container_text(item) for item in self._items)

    def write_to(self, stringer):
        stringer.array()
        for item in self._items:
            stringer.value(item)
        stringer.endArray()

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        stringer = JSONStringer()
        self.write_to(stringer)
        return stringer.toString()

    @jmethod("toString", "(I)Ljava/lang/String;")
    def toString_indent(self, indent):
        stringer = JSONStringer(indent)
        self.write_to(stringer)
        return stringer.toString()

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        if not isinstance(other, JSONArray) or len(other._items) != len(self._items):
            return 0
        return 1 if all(jequals(a, b) for a, b in zip(self._items, other._items)) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        total = 1
        for item in self._items:
            total = runtime.wrap32(total * 31 + jhash(item))
        return total


def _widen(array, item):
    """an element of a primitive array as the box a json value holds"""
    code = array.jtype.descriptor[1]
    if code == "Z":
        return _box_bool(item)
    if code == "I":
        return _box_int(item)
    if code == "J":
        return Long.valueOf(item)
    if code in "DF":
        return Double(item)
    if code == "C":
        return Character.valueOf(item)
    if code in "BS":
        return _box_int(item)
    return item


def _scalar_or_container_text(item):
    if isinstance(item, (JSONArray, JSONObject)):
        return item.toString()
    return _scalar_text(item)


@host_class("org.json.JSONTokener")
class JSONTokener(Object):
    """the reader behind JSONObject(String) and JSONArray(String)"""

    def __init__(self, text):
        # a leading byte order mark is not part of the json text
        if text is not None and text.startswith("﻿"):
            text = text[1:]
        self._in = text
        self._pos = 0
        self._depth = 0

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, text):
        JSONTokener.__init__(self, text)

    def _error(self, message):
        _json_error(message + self.toString())

    @jmethod("syntaxError", "(Ljava/lang/String;)Lorg/json/JSONException;")
    def syntaxError(self, message):
        return runtime.make_throwable(lookup_host("org.json.JSONException").py, message + self.toString())

    @jmethod("nextValue", "()Ljava/lang/Object;")
    def nextValue(self):
        char = self._next_clean()
        if char == -1:
            self._error("End of input")
        if char == "{":
            return self._read_object()
        if char == "[":
            return self._read_array()
        if char in "'\"":
            return self.nextString(char)
        self._pos -= 1
        return self._read_literal()

    def _next_clean(self):
        text = self._in
        while self._pos < len(text):
            char = text[self._pos]
            self._pos += 1
            if char in "\t\r\n ":
                continue
            if char == "/" and self._pos < len(text):
                follow = text[self._pos]
                if follow == "*":
                    self._pos += 1
                    end = text.find("*/", self._pos)
                    if end == -1:
                        self._error("Unterminated comment")
                    self._pos = end + 2
                    continue
                if follow == "/":
                    self._pos += 1
                    self._skip_line()
                    continue
                return char
            if char == "#":
                self._skip_line()
                continue
            return char
        return -1

    def _skip_line(self):
        text = self._in
        while self._pos < len(text):
            char = text[self._pos]
            self._pos += 1
            if char in "\r\n":
                break

    @jmethod("nextString", "(C)Ljava/lang/String;")
    def nextString(self, quote):
        if isinstance(quote, int):
            quote = chr(quote)
        text = self._in
        out = []
        start = self._pos
        while self._pos < len(text):
            char = text[self._pos]
            self._pos += 1
            if char == quote:
                if not out:
                    return text[start:self._pos - 1]
                out.append(text[start:self._pos - 1])
                return "".join(out)
            if char == "\\":
                if self._pos == len(text):
                    self._error("Unterminated escape sequence")
                out.append(text[start:self._pos - 1])
                out.append(self._read_escape())
                start = self._pos
        self._error("Unterminated string")

    def _read_escape(self):
        text = self._in
        char = text[self._pos]
        self._pos += 1
        if char == "u":
            if self._pos + 4 > len(text):
                self._error("Unterminated escape sequence")
            digits = text[self._pos:self._pos + 4]
            self._pos += 4
            try:
                return chr(int(digits, 16)) if all(c in "0123456789abcdefABCDEF" for c in digits) else self._bad_escape(digits)
            except ValueError:
                return self._bad_escape(digits)
        return {"t": "\t", "b": "\b", "n": "\n", "r": "\r", "f": "\f"}.get(char, char)

    def _bad_escape(self, digits):
        runtime.throw_new("java.lang.NumberFormatException", "Invalid escape sequence: \\u" + digits)

    def _read_literal(self):
        literal = self._next_to("{}[]/\\:,=;# \t\f")
        if not literal:
            self._error("Expected literal value")
        lowered = literal.lower()
        if lowered == "null":
            return NULL
        if lowered == "true":
            return Boolean.TRUE
        if lowered == "false":
            return Boolean.FALSE
        if "." not in literal:
            number = _parse_integer(literal)
            if number is not None:
                return number
        parsed = _parse_double(literal)
        return literal if parsed is None else Double(parsed)

    @jmethod("nextTo", "(Ljava/lang/String;)Ljava/lang/String;")
    def nextTo(self, excluded):
        return self._next_to(excluded)

    def _next_to(self, excluded):
        text = self._in
        start = self._pos
        while self._pos < len(text):
            if text[self._pos] in "\r\n" or text[self._pos] in excluded:
                break
            self._pos += 1
        return text[start:self._pos]

    def _enter(self):
        self._depth += 1
        if self._depth > MAX_DEPTH:
            self._error("Nesting too deep")

    def _read_object(self):
        self._enter()
        result = JSONObject()
        first = self._next_clean()
        if first == "}":
            self._depth -= 1
            return result
        if first != -1:
            self._pos -= 1
        while True:
            name = self.nextValue()
            if name.__class__ is not str:
                if name is None:
                    self._error("Names cannot be null")
                self._error("Names must be strings, but %s is of type %s" % (
                    jstring(name), runtime.class_of(name).getName()))
            separator = self._next_clean()
            if separator not in (":", "=") or separator == -1:
                self._error("Expected ':' after " + name)
            if self._pos < len(self._in) and self._in[self._pos] == ">":
                self._pos += 1
            result._map[name] = self.nextValue()
            ender = self._next_clean()
            if ender == "}":
                self._depth -= 1
                return result
            if ender not in (";", ","):
                self._error("Unterminated object")

    def _read_array(self):
        self._enter()
        result = JSONArray()
        has_trailing = False
        while True:
            char = self._next_clean()
            if char == -1:
                self._error("Unterminated array")
            if char == "]":
                if has_trailing:
                    result._items.append(None)
                self._depth -= 1
                return result
            if char in (",", ";"):
                result._items.append(None)
                has_trailing = True
                continue
            self._pos -= 1
            result._items.append(self.nextValue())
            char = self._next_clean()
            if char == "]":
                self._depth -= 1
                return result
            if char in (",", ";"):
                has_trailing = True
                continue
            self._error("Unterminated array")

    @jmethod("more", "()Z")
    def more(self):
        return 1 if self._pos < len(self._in) else 0

    @jmethod("next", "()C")
    def next(self):
        if self._pos < len(self._in):
            self._pos += 1
            return ord(self._in[self._pos - 1])
        return 0

    @jmethod("back", "()V")
    def back(self):
        self._pos -= 1
        if self._pos == -1:
            self._pos = 0

    @jmethod("nextClean", "()C")
    def nextClean(self):
        value = self._next_clean()
        return 0 if value == -1 else ord(value)

    @jmethod("skipPast", "(Ljava/lang/String;)V")
    def skipPast(self, target):
        index = self._in.find(target, self._pos)
        self._pos = len(self._in) if index == -1 else index + len(target)

    @jmethod("skipTo", "(C)C")
    def skipTo(self, char):
        char = chr(char) if isinstance(char, int) else char
        index = self._in.find(char, self._pos)
        if index == -1:
            return 0
        self._pos = index
        return ord(char)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return " at character %d of %s" % (self._pos, self._in)

    @jstatic("dehexchar", "(C)I")
    def dehexchar(char):
        char = chr(char) if isinstance(char, int) else char
        if "0" <= char <= "9":
            return ord(char) - 48
        if "A" <= char <= "F":
            return ord(char) - 55
        if "a" <= char <= "f":
            return ord(char) - 87
        return -1


def _parse_integer(literal):
    """what the android tokener makes of a literal with no dot: hex after 0x, octal after a leading 0, else decimal;
    an Integer when it fits, else a Long, and None when it is not a number in that base (so 08 reads as a double)"""
    text = literal
    base = 10
    if text[:2] in ("0x", "0X"):
        text = text[2:]
        base = 16
    elif text.startswith("0") and len(text) > 1:
        text = text[1:]
        base = 8
    digits = text[1:] if text[:1] in ("+", "-") and len(text) > 1 else text
    if not digits or not digits.isascii() or not digits.isalnum():
        return None
    try:
        value = int(text, base)
    except ValueError:
        return None
    if not -0x8000000000000000 <= value <= 0x7FFFFFFFFFFFFFFF:
        return None
    if -0x80000000 <= value <= 0x7FFFFFFF:
        return Integer.valueOf(value)
    return Long.valueOf(value)
