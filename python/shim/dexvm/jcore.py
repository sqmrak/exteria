"""methods of java.lang that jlang leaves out: Character code point and surrogate helpers, unsigned Integer and Long
arithmetic, the rest of Math, the Boolean logical operators and a few StringBuilder members

they are added to the classes jlang registers, so a program finds them where the jdk has them"""

import math
import struct
import unicodedata

from . import runtime
from .api import jstatic, lookup_host
from .jlang import Boolean, Character, Double, Float, Integer, Long, Math, StringBuilder, jstr


def _attach(cls, name, descriptors, function, static=True):
    """register function on cls as name under each descriptor, the way the decorators of the class bodies do"""
    for descriptor in descriptors:
        function.__dict__.setdefault("_jsigs", []).append((name, descriptor))
    # several functions can share a name (subtractExact for int and for long): the typed table reads the marks on each function,
    # so each one is kept under a key of its own, and the plain name stays with the first
    key = name if name not in vars(cls) else "%s__%s" % (name, descriptors[0])
    if static:
        function.__dict__["_jstatic"] = True
        setattr(cls, key, staticmethod(function))
    else:
        setattr(cls, key, function)
    cls_host = getattr(cls, "_jhost", None)
    if cls_host is not None:
        cls_host._typed = None


def _cp(value):
    return ord(value) if isinstance(value, str) else value


def _is_high(c):
    return 0xD800 <= _cp(c) <= 0xDBFF


def _is_low(c):
    return 0xDC00 <= _cp(c) <= 0xDFFF


for _name, _fn in (("isHighSurrogate", _is_high), ("isLowSurrogate", _is_low),
                   ("isSurrogate", lambda c: 1 if 0xD800 <= _cp(c) <= 0xDFFF else 0)):
    _attach(Character, _name, ["(C)Z"], (lambda f: lambda c: 1 if f(c) else 0)(_fn))

_attach(Character, "isSurrogatePair", ["(CC)Z"], lambda high, low: 1 if _is_high(high) and _is_low(low) else 0)
_attach(Character, "charCount", ["(I)I"], lambda cp: 2 if cp >= 0x10000 else 1)
_attach(Character, "toCodePoint", ["(CC)I"], lambda high, low: ((_cp(high) - 0xD800) << 10) + (_cp(low) - 0xDC00) + 0x10000)
_attach(Character, "isBmpCodePoint", ["(I)Z"], lambda cp: 1 if 0 <= cp <= 0xFFFF else 0)
_attach(Character, "isSupplementaryCodePoint", ["(I)Z"], lambda cp: 1 if 0x10000 <= cp <= 0x10FFFF else 0)
_attach(Character, "isValidCodePoint", ["(I)Z"], lambda cp: 1 if 0 <= cp <= 0x10FFFF else 0)
_attach(Character, "highSurrogate", ["(I)C"], lambda cp: ((cp - 0x10000) >> 10) + 0xD800)
_attach(Character, "lowSurrogate", ["(I)C"], lambda cp: ((cp - 0x10000) & 0x3FF) + 0xDC00)
_attach(Character, "reverseBytes", ["(C)C"], lambda c: ((_cp(c) & 0xFF) << 8) | (_cp(c) >> 8))


def _code_point_at(text, index, limit=None):
    if text.__class__ is not str:
        text = text.toString() if not isinstance(text, list) else "".join(chr(u) for u in text)
    end = len(text) if limit is None else limit
    if index < 0 or index >= end:
        runtime.throw_new("java.lang.IndexOutOfBoundsException", "index %d, length %d" % (index, end))
    unit = ord(text[index])
    if 0xD800 <= unit <= 0xDBFF and index + 1 < end and 0xDC00 <= ord(text[index + 1]) <= 0xDFFF:
        return ((unit - 0xD800) << 10) + (ord(text[index + 1]) - 0xDC00) + 0x10000
    return unit


def _code_point_before(text, index):
    if index < 1 or index > len(text):
        runtime.throw_new("java.lang.IndexOutOfBoundsException", "index %d, length %d" % (index, len(text)))
    unit = ord(text[index - 1])
    if 0xDC00 <= unit <= 0xDFFF and index >= 2 and 0xD800 <= ord(text[index - 2]) <= 0xDBFF:
        return ((ord(text[index - 2]) - 0xD800) << 10) + (unit - 0xDC00) + 0x10000
    return unit


_attach(Character, "codePointAt", ["(Ljava/lang/CharSequence;I)I", "([CI)I", "([CII)I"], _code_point_at)
_attach(Character, "codePointBefore", ["(Ljava/lang/CharSequence;I)I", "([CI)I"], _code_point_before)


def _code_point_count(text, start, end):
    text = text if text.__class__ is str else text.toString()
    count = 0
    index = start
    while index < end:
        index += 2 if _code_point_at(text, index, end) >= 0x10000 else 1
        count += 1
    return count


_attach(Character, "codePointCount", ["(Ljava/lang/CharSequence;II)I"], _code_point_count)


def _category(c):
    return unicodedata.category(chr(_cp(c))) if 0 <= _cp(c) <= 0x10FFFF and not 0xD800 <= _cp(c) <= 0xDFFF else "Cs"


_attach(Character, "isSpaceChar", ["(C)Z", "(I)Z"], lambda c: 1 if _category(c) in ("Zs", "Zl", "Zp") else 0)
_attach(Character, "isAlphabetic", ["(I)Z"],
        lambda c: 1 if _category(c) in ("Lu", "Ll", "Lt", "Lm", "Lo", "Nl") else 0)
_attach(Character, "isISOControl", ["(C)Z", "(I)Z"],
        lambda c: 1 if 0 <= _cp(c) <= 0x1F or 0x7F <= _cp(c) <= 0x9F else 0)
_attach(Character, "isDefined", ["(C)Z", "(I)Z"], lambda c: 0 if _category(c) == "Cn" else 1)
_attach(Character, "isJavaIdentifierStart", ["(C)Z", "(I)Z"],
        lambda c: 1 if _category(c)[0] == "L" or _category(c) in ("Nl", "Sc", "Pc") else 0)
_attach(Character, "isJavaIdentifierPart", ["(C)Z", "(I)Z"],
        lambda c: 1 if _category(c)[0] in "LN" or _category(c) in ("Sc", "Pc", "Mn", "Mc") or
        (0 <= _cp(c) <= 8 or 0xE <= _cp(c) <= 0x1B or 0x7F <= _cp(c) <= 0x9F) else 0)
_TYPES = {"Cn": 0, "Lu": 1, "Ll": 2, "Lt": 3, "Lm": 4, "Lo": 5, "Mn": 6, "Me": 7, "Mc": 8, "Nd": 9, "Nl": 10, "No": 11,
          "Zs": 12, "Zl": 13, "Zp": 14, "Cc": 15, "Cf": 16, "Co": 18, "Cs": 19, "Pd": 20, "Ps": 21, "Pe": 22, "Pc": 23,
          "Po": 24, "Sm": 25, "Sc": 26, "Sk": 27, "So": 28, "Pi": 29, "Pf": 30}
_attach(Character, "getType", ["(C)I", "(I)I"], lambda c: _TYPES.get(_category(c), 0))
_attach(Character, "isEmoji", ["(I)Z"],
        lambda c: 1 if 0x1F300 <= _cp(c) <= 0x1FAFF or 0x2600 <= _cp(c) <= 0x27BF else 0)


def _to_chars(cp, destination=None, index=0):
    if not 0 <= cp <= 0x10FFFF:
        runtime.throw_new("java.lang.IllegalArgumentException", "Not a valid Unicode code point: 0x%X" % cp)
    units = [cp] if cp < 0x10000 else [((cp - 0x10000) >> 10) + 0xD800, ((cp - 0x10000) & 0x3FF) + 0xDC00]
    if destination is None:
        array = runtime.new_array("[C", 0)
        array.extend(units)
        return array
    destination[index:index + len(units)] = units
    return len(units)


_attach(Character, "toChars", ["(I)[C", "(I[CI)I"], _to_chars)


def _u32(v):
    return v & 0xFFFFFFFF


def _u64(v):
    return v & 0xFFFFFFFFFFFFFFFF


_attach(Integer, "compareUnsigned", ["(II)I"], lambda a, b: (_u32(a) > _u32(b)) - (_u32(a) < _u32(b)))
_attach(Integer, "divideUnsigned", ["(II)I"],
        lambda a, b: runtime.wrap32(_u32(a) // _u32(b)) if _u32(b) else runtime.throw_new(
            "java.lang.ArithmeticException", "/ by zero"))
_attach(Integer, "remainderUnsigned", ["(II)I"],
        lambda a, b: runtime.wrap32(_u32(a) % _u32(b)) if _u32(b) else runtime.throw_new(
            "java.lang.ArithmeticException", "/ by zero"))
_attach(Integer, "toUnsignedLong", ["(I)J"], _u32)
_attach(Integer, "toUnsignedString", ["(I)Ljava/lang/String;"], lambda v: str(_u32(v)))
_attach(Long, "compareUnsigned", ["(JJ)I"], lambda a, b: (_u64(a) > _u64(b)) - (_u64(a) < _u64(b)))
_attach(Long, "divideUnsigned", ["(JJ)J"],
        lambda a, b: runtime.wrap64(_u64(a) // _u64(b)) if _u64(b) else runtime.throw_new(
            "java.lang.ArithmeticException", "/ by zero"))
_attach(Long, "remainderUnsigned", ["(JJ)J"],
        lambda a, b: runtime.wrap64(_u64(a) % _u64(b)) if _u64(b) else runtime.throw_new(
            "java.lang.ArithmeticException", "/ by zero"))
_attach(Long, "toUnsignedString", ["(J)Ljava/lang/String;"], lambda v: str(_u64(v)))


def _parse_unsigned(text, radix, bits):
    try:
        if text is None or text.startswith("-") or text.startswith("+") and len(text) == 1:
            raise ValueError
        value = int(text.lstrip("+"), radix)
    except (ValueError, AttributeError):
        runtime.throw_new("java.lang.NumberFormatException", "For input string: \"%s\"" % (text,))
    if value >= 1 << bits:
        runtime.throw_new("java.lang.NumberFormatException", "String value %s exceeds range of unsigned %s." % (
            text, "int" if bits == 32 else "long"))
    return value


_attach(Integer, "parseUnsignedInt", ["(Ljava/lang/String;)I", "(Ljava/lang/String;I)I"],
        lambda text, radix=10: runtime.wrap32(_parse_unsigned(text, radix, 32)))
_attach(Long, "parseUnsignedLong", ["(Ljava/lang/String;)J", "(Ljava/lang/String;I)J"],
        lambda text, radix=10: runtime.wrap64(_parse_unsigned(text, radix, 64)))


def _decode(text, bits):
    if text is None:
        runtime.npe()
    if not text:
        runtime.throw_new("java.lang.NumberFormatException", "Zero length string")
    sign = -1 if text[0] == "-" else 1
    body = text[1:] if text[0] in "+-" else text
    radix = 10
    if body[:2] in ("0x", "0X"):
        radix, body = 16, body[2:]
    elif body[:1] == "#":
        radix, body = 16, body[1:]
    elif len(body) > 1 and body[0] == "0":
        radix, body = 8, body[1:]
    try:
        value = sign * int(body, radix)
    except ValueError:
        runtime.throw_new("java.lang.NumberFormatException", "For input string: \"%s\"" % text)
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not low <= value <= high:
        runtime.throw_new("java.lang.NumberFormatException", "For input string: \"%s\"" % text)
    return value


_attach(Integer, "decode", ["(Ljava/lang/String;)Ljava/lang/Integer;"], lambda t: Integer.valueOf(_decode(t, 32)))
_attach(Long, "decode", ["(Ljava/lang/String;)Ljava/lang/Long;"], lambda t: Long.valueOf(_decode(t, 64)))
_attach(Long, "rotateLeft", ["(JI)J"],
        lambda v, d: runtime.wrap64((_u64(v) << (d & 63) | _u64(v) >> (64 - (d & 63))) & 0xFFFFFFFFFFFFFFFF))
_attach(Long, "rotateRight", ["(JI)J"],
        lambda v, d: runtime.wrap64((_u64(v) >> (d & 63) | _u64(v) << (64 - (d & 63))) & 0xFFFFFFFFFFFFFFFF))
_attach(Long, "reverse", ["(J)J"], lambda v: runtime.wrap64(int("{:064b}".format(_u64(v))[::-1], 2)))
_attach(Long, "highestOneBit", ["(J)J"], lambda v: runtime.wrap64(1 << (_u64(v).bit_length() - 1)) if v else 0)
_attach(Long, "lowestOneBit", ["(J)J"], lambda v: runtime.wrap64(v & -v))


def _exact(op, bits):
    low, high = -(1 << (bits - 1)), (1 << (bits - 1)) - 1

    def run(*args):
        value = op(*args)
        if not low <= value <= high:
            runtime.throw_new("java.lang.ArithmeticException", "integer overflow" if bits == 32 else "long overflow")
        return value
    return run


for _bits, _t in ((32, "I"), (64, "J")):
    _attach(Math, "subtractExact", ["(%s%s)%s" % (_t, _t, _t)], _exact(lambda a, b: a - b, _bits))
    _attach(Math, "negateExact", ["(%s)%s" % (_t, _t)], _exact(lambda a: -a, _bits))
    _attach(Math, "incrementExact", ["(%s)%s" % (_t, _t)], _exact(lambda a: a + 1, _bits))
    _attach(Math, "decrementExact", ["(%s)%s" % (_t, _t)], _exact(lambda a: a - 1, _bits))
    _attach(Math, "absExact", ["(%s)%s" % (_t, _t)], _exact(abs, _bits))


def _safe(fn):
    def run(*args):
        try:
            return fn(*args)
        except ValueError:
            return math.nan
        except OverflowError:
            return math.inf
    return run


for _name, _fn in (("cbrt", lambda a: math.copysign(abs(a) ** (1.0 / 3.0), a) if a == a and not math.isinf(a) else a),
                   ("asin", math.asin), ("acos", math.acos), ("atan", math.atan), ("sinh", math.sinh),
                   ("cosh", math.cosh), ("tanh", math.tanh), ("expm1", math.expm1),
                   ("log1p", lambda a: -math.inf if a == -1 else math.log1p(a)),
                   ("toRadians", lambda a: a / 180.0 * math.pi), ("toDegrees", lambda a: a * 180.0 / math.pi)):
    _attach(Math, _name, ["(D)D"], _safe(_fn))
_attach(Math, "rint", ["(D)D"], lambda a: float(round(a)) if a == a and not math.isinf(a) else a)
_attach(Math, "copySign", ["(DD)D", "(FF)F"], lambda a, b: math.copysign(a, b))
_attach(Math, "ulp", ["(D)D"], lambda a: math.ulp(a))
_attach(Math, "nextUp", ["(D)D"], lambda a: math.nextafter(a, math.inf))
_attach(Math, "nextDown", ["(D)D"], lambda a: math.nextafter(a, -math.inf))
_attach(Math, "fma", ["(DDD)D"], lambda a, b, c: math.fma(a, b, c) if hasattr(math, "fma") else a * b + c)


def _clamp(value, low, high):
    if low > high:
        runtime.throw_new("java.lang.IllegalArgumentException", "%s > %s" % (low, high))
    return min(high, max(low, value))


_attach(Math, "clamp", ["(JII)I", "(JJJ)J", "(DDD)D", "(FFF)F"], _clamp)


_attach(Double, "isFinite", ["(D)Z"], lambda v: 1 if math.isfinite(v) else 0)
_attach(Double, "sum", ["(DD)D"], lambda a, b: a + b)
_attach(Double, "toHexString", ["(D)Ljava/lang/String;"], lambda v: float.hex(v).replace("0x", "0x"))
_attach(Float, "isFinite", ["(F)Z"], lambda v: 1 if math.isfinite(v) else 0)
_attach(Float, "sum", ["(FF)F"], lambda a, b: runtime.f32(a + b))
_attach(Boolean, "logicalAnd", ["(ZZ)Z"], lambda a, b: 1 if a and b else 0)
_attach(Boolean, "logicalOr", ["(ZZ)Z"], lambda a, b: 1 if a or b else 0)
_attach(Boolean, "logicalXor", ["(ZZ)Z"], lambda a, b: 1 if bool(a) != bool(b) else 0)


def _sb_last_index_of(self, text, start=None):
    whole = self._text()
    return whole.rfind(text) if start is None else whole.rfind(text, 0, max(start, -1) + len(text)) if start >= 0 else -1


_attach(StringBuilder, "lastIndexOf", ["(Ljava/lang/String;)I", "(Ljava/lang/String;I)I"], _sb_last_index_of, static=False)
_attach(StringBuilder, "subSequence", ["(II)Ljava/lang/CharSequence;"],
        lambda self, start, end: self.substring(start, end), static=False)
_attach(StringBuilder, "capacity", ["()I"], lambda self: max(16, len(self._text())), static=False)


def _sb_append_cp(self, cp):
    self._parts.append(jstr(chr(cp)))
    return self


_attach(StringBuilder, "appendCodePoint", ["(I)Ljava/lang/StringBuilder;"], _sb_append_cp, static=False)
_attach(StringBuilder, "codePointAt", ["(I)I"], lambda self, index: _code_point_at(self._text(), index), static=False)
