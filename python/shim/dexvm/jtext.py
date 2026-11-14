"""java.util.Formatter (String.format, printf), java.util.regex and Locale

%f, %e and %g round half up on the shortest decimal digits of the argument, the way java does, not on the exact
binary value: String.format("%.2f", 1.005) is 1.01 here as on a runtime, where C prints 1.00. a float argument is first
widened to double. regular expressions run on python's re after a translation of the java syntax (named groups, \\z,
\\h, \\R, \\Q..\\E, posix classes, the java meaning of . and of \\d \\w \\s \\b, which are ASCII only); character class
intersection and a few exotic constructs are refused with PatternSyntaxException"""

import math
import re

from . import runtime
from .api import host_class, jmethod, jstatic
from .jfunc import jstring
from .jlang import (Boolean, Byte, Character, Double, Float, Integer, Long, Object, Short, String, _StringImpl,
                    _cs, float_to_string, jstr)
from .jutil import check_nonnull, iterate, to_array


@host_class("java.util.Locale", final=True)
class Locale(Object):
    def __init__(self, language="", country="", variant=""):
        self._l, self._c, self._v = language, country, variant

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init(self, language):
        Locale.__init__(self, language)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;)V")
    def _init2(self, language, country):
        Locale.__init__(self, language, country)

    @jstatic("getDefault", "()Ljava/util/Locale;")
    def getDefault():
        return Locale.US

    @jstatic("forLanguageTag", "(Ljava/lang/String;)Ljava/util/Locale;")
    def forLanguageTag(tag):
        parts = tag.replace("_", "-").split("-")
        return Locale(parts[0], parts[1] if len(parts) > 1 else "")

    @jmethod("getLanguage", "()Ljava/lang/String;")
    def getLanguage(self):
        return self._l

    @jmethod("getCountry", "()Ljava/lang/String;")
    def getCountry(self):
        return self._c

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._l + ("_" + self._c if self._c else "")

    @jmethod("toLanguageTag", "()Ljava/lang/String;")
    def toLanguageTag(self):
        return (self._l or "und") + ("-" + self._c if self._c else "")

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Locale) and (other._l, other._c, other._v) == (self._l, self._c, self._v) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return hash((self._l, self._c)) & 0x7FFFFFFF


Locale.US = Locale("en", "US")
Locale.ENGLISH = Locale("en")
Locale.ROOT = Locale("")
Locale.UK = Locale("en", "GB")
Locale.GERMANY = Locale("de", "DE")
Locale.FRANCE = Locale("fr", "FR")
Locale.GERMAN = Locale("de")
Locale.FRENCH = Locale("fr")

_SEPARATORS = {"de": (",", "."), "fr": (",", " "), "ru": (",", " "), "es": (",", "."), "it": (",", "."),
               "pt": (",", "."), "tr": (",", ".")}


def _decimal_digits(value, single=False):
    """(digits, point) with value = 0.digits * 10**point for a finite non-zero magnitude, from the shortest text"""
    text = float_to_string(abs(value), single)
    mantissa, _, exponent = text.partition("E")
    integer, _, fraction = mantissa.partition(".")
    digits = integer + fraction
    point = len(integer) + (int(exponent) if exponent else 0)
    stripped = digits.lstrip("0")
    point -= len(digits) - len(stripped)
    return (stripped.rstrip("0") or "0"), point


def _round_half_up(digits, point, keep):
    """round the digit string to keep digits from the start; returns (digits, point) with a carry applied"""
    if keep >= len(digits):
        return digits, point
    if keep < 0:
        return "0", point
    up = digits[keep] >= "5"
    kept = digits[:keep]
    if not up:
        return kept or "0", point
    number = int(kept or "0") + 1
    text = str(number)
    if len(text) > len(kept):
        point += 1
    return text, point


def format_fixed(value, precision):
    if value == 0:
        return "0" + ("." + "0" * precision if precision else "")
    digits, point = _decimal_digits(value)
    digits, point = _round_half_up(digits, point, point + precision)
    if digits == "0":
        return "0" + ("." + "0" * precision if precision else "")
    if point <= 0:
        integer, fraction = "0", "0" * -point + digits
    elif point >= len(digits):
        integer, fraction = digits + "0" * (point - len(digits)), ""
    else:
        integer, fraction = digits[:point], digits[point:]
    fraction = (fraction + "0" * precision)[:precision]
    return integer + ("." + fraction if precision else "")


def format_scientific(value, precision, upper=False):
    if value == 0:
        mantissa = "0" + ("." + "0" * precision if precision else "")
        exponent = 0
    else:
        digits, point = _decimal_digits(value)
        digits, point = _round_half_up(digits, point, precision + 1)
        exponent = point - 1
        digits = (digits + "0" * (precision + 1))[:precision + 1]
        mantissa = digits[0] + ("." + digits[1:] if precision else "")
    text = "%se%s%02d" % (mantissa, "-" if exponent < 0 else "+", abs(exponent))
    return text.upper() if upper else text


def _group(integer, separator):
    out = []
    while len(integer) > 3:
        out.insert(0, integer[-3:])
        integer = integer[:-3]
    out.insert(0, integer)
    return separator.join(out)


_SPEC = re.compile(r"%(\d+\$)?([-#+ 0,(<]*)(\d+)?(\.\d+)?([tT]?[a-zA-Z%])")


def _illegal(kind, text):
    runtime.throw_new("java.util." + kind, text)


class Formattable:
    pass


def java_format(locale, fmt, args):
    """Formatter.format: the formatted text, or a java exception for a bad specifier or argument"""
    language = locale._l if locale is not None else ""
    decimal, grouping = _SEPARATORS.get(language, (".", ","))
    out = []
    position = 0
    ordinary = 0
    last = -1
    args = list(args) if args is not None else []
    while True:
        percent = fmt.find("%", position)
        if percent < 0:
            out.append(fmt[position:])
            break
        out.append(fmt[position:percent])
        match = _SPEC.match(fmt, percent)
        if match is None:
            _illegal("UnknownFormatConversionException", "Conversion = '%s'" % fmt[percent + 1:percent + 2])
        position = match.end()
        index_text, flags, width_text, precision_text, conversion = match.groups()
        if conversion == "n":
            out.append("\n")
            continue
        if conversion == "%":
            text = "%"
            width = int(width_text) if width_text else 0
            out.append(text.ljust(width) if "-" in flags else text.rjust(width))
            continue
        if "<" in flags:
            index = last
        elif index_text:
            index = int(index_text[:-1]) - 1
        else:
            index = ordinary
            ordinary += 1
        if index < 0 or index >= len(args):
            _illegal("MissingFormatArgumentException", "Format specifier '%s'" % match.group(0))
        last = index
        argument = args[index]
        width = int(width_text) if width_text else 0
        precision = int(precision_text[1:]) if precision_text else None
        if conversion.lower() in "docxt" and precision is not None:
            _illegal("IllegalFormatPrecisionException", str(precision))
        if not width_text and ("-" in flags or "0" in flags):
            _illegal("MissingFormatWidthException", match.group(0))
        out.append(_convert(argument, conversion, flags.replace("<", ""), width, precision, decimal, grouping, match.group(0)))
    return "".join(out)


def _pad(text, width, flags):
    if width and len(text) < width:
        return text.ljust(width) if "-" in flags else text.rjust(width)
    return text


def _number_value(argument):
    if isinstance(argument, (Integer, Long, Short, Byte)):
        return argument.value
    return None


def _convert(argument, conversion, flags, width, precision, decimal, grouping, spec):
    upper = conversion.isupper() and conversion not in "XEGS" or conversion in "XEGSBHC"
    lowered = conversion.lower()
    if lowered == "s":
        text = "null" if argument is None else jstring(argument)
        if precision is not None:
            text = text[:precision]
        text = _pad(text, width, flags)
        return text.upper() if conversion == "S" else text
    if lowered == "b":
        text = "false" if argument is None or (isinstance(argument, Boolean) and not argument.value) else "true"
        if precision is not None:
            text = text[:precision]
        text = _pad(text, width, flags)
        return text.upper() if conversion == "B" else text
    if lowered == "c":
        if argument is None:
            text = "null"
        elif isinstance(argument, Character):
            text = chr(argument.value)
        elif isinstance(argument, (Integer, Short, Byte)):
            text = chr(argument.value) if 0 <= argument.value <= 0x10FFFF else _illegal(
                "IllegalFormatCodePointException", "Code point = %#x" % argument.value)
            text = jstr(text)
        else:
            _illegal("IllegalFormatConversionException", "%s != %s" % (conversion, runtime.type_name_of(argument)))
        text = _pad(text, width, flags)
        return text.upper() if conversion == "C" else text
    if lowered == "h":
        from .jfunc import jhash
        text = "null" if argument is None else "%x" % (jhash(argument) & 0xFFFFFFFF)
        return _pad(text.upper() if conversion == "H" else text, width, flags)
    if lowered in "dox":
        if argument is None:
            return _pad("null", width, flags)
        value = _number_value(argument)
        if value is None:
            big = getattr(argument, "_v", None)
            if isinstance(big, int):
                value = big
            else:
                _illegal("IllegalFormatConversionException", "%s != %s" % (conversion, runtime.type_name_of(argument)))
        if lowered == "d":
            digits = str(abs(value))
            if "," in flags:
                digits = _group(digits, grouping)
            sign = "-" if value < 0 else "+" if "+" in flags else " " if " " in flags else ""
            if "(" in flags and value < 0:
                text = "(" + digits + ")"
            elif "0" in flags and width:
                text = sign + digits.rjust(width - len(sign), "0")
            else:
                text = sign + digits
            return _pad(text, width, flags)
        bits = {Integer: 32, Long: 64, Short: 16, Byte: 8}.get(type(argument), None)
        if value < 0 and bits:
            value &= (1 << bits) - 1
        text = ("%o" if lowered == "o" else "%x") % value
        if "#" in flags:
            text = ("0" if lowered == "o" else "0x") + text
        if "0" in flags and width:
            text = text.rjust(width, "0")
        text = _pad(text, width, flags)
        return text.upper() if conversion == "X" else text
    if lowered in "efga":
        if argument is None:
            return _pad("null", width, flags)
        if isinstance(argument, (Float, Double)):
            value = float(argument.value)
        elif hasattr(argument, "doubleValue") and not isinstance(argument, (Integer, Long, Short, Byte)):
            value = argument.doubleValue()
        else:
            _illegal("IllegalFormatConversionException", "%s != %s" % (conversion, runtime.type_name_of(argument)))
        if value != value:
            return _pad("NaN", width, flags)
        negative = math.copysign(1.0, value) < 0 and value != 0 or (value == 0 and math.copysign(1.0, value) < 0)
        if math.isinf(value):
            text = "Infinity"
            sign = "-" if negative else "+" if "+" in flags else ""
            return _pad(sign + text, width, flags)
        magnitude = abs(value)
        if lowered == "f":
            body = format_fixed(magnitude, 6 if precision is None else precision)
            integer, _, fraction = body.partition(".")
            if "," in flags:
                integer = _group(integer, grouping)
            body = integer + (decimal + fraction if fraction else "")
        elif lowered == "e":
            body = format_scientific(magnitude, 6 if precision is None else precision, conversion == "E")
            body = body.replace(".", decimal)
        elif lowered == "g":
            p = 6 if precision is None else (1 if precision == 0 else precision)
            if magnitude == 0:
                body = format_fixed(0.0, p - 1)
            else:
                digits, point = _decimal_digits(magnitude)
                digits, point = _round_half_up(digits, point, p)
                rounded = float("0." + digits) * 10.0 ** point if digits != "0" else 0.0
                if 1e-4 <= rounded < 10.0 ** p:
                    body = format_fixed(magnitude, max(p - point, 0))
                else:
                    body = format_scientific(magnitude, p - 1, conversion == "G")
            body = body.replace(".", decimal)
        else:
            body = float.hex(magnitude)
        sign = "-" if negative else "+" if "+" in flags else " " if " " in flags else ""
        if "(" in flags and negative:
            text = "(" + body + ")"
        elif "0" in flags and width:
            text = sign + body.rjust(width - len(sign), "0")
        else:
            text = sign + body
        text = _pad(text, width, flags)
        return text.upper() if conversion in "EGA" else text
    if lowered == "t":
        _illegal("UnknownFormatConversionException", "Conversion = '%s'" % conversion)
    _illegal("UnknownFormatConversionException", "Conversion = '%s'" % conversion)


@host_class("java.util.Formatter", interfaces=("java.io.Closeable", "java.io.Flushable"))
class Formatter(Object):
    def __init__(self, sink=None, locale=None):
        from .jlang import StringBuilder
        self._sink = sink if sink is not None else StringBuilder.__new__(StringBuilder)
        if sink is None:
            self._sink._parts = []
        self._locale = locale

    @jmethod("<init>", "()V")
    def _init(self):
        Formatter.__init__(self)

    @jmethod("<init>", "(Ljava/lang/Appendable;)V")
    def _init_sink(self, sink):
        Formatter.__init__(self, sink)

    @jmethod("format", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/util/Formatter;")
    def format(self, fmt, args):
        self._sink.append(java_format(self._locale, check_nonnull(fmt), args))
        return self

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._sink.toString()

    @jmethod("close", "()V")
    @jmethod("flush", "()V")
    def close(self):
        return None


def string_format(template, args):
    return jstr(java_format(None, check_nonnull(template), args))


def string_format_locale(locale, template, args):
    return jstr(java_format(locale, check_nonnull(template), args))


def string_formatted(template, args):
    return string_format(template, args)


CASE_INSENSITIVE, MULTILINE, DOTALL, UNICODE_CASE, COMMENTS, LITERAL = 2, 8, 32, 64, 4, 16
UNIX_LINES, CANON_EQ, UNICODE_CHARACTER_CLASS = 1, 128, 256

_POSIX = {
    "Lower": "a-z", "Upper": "A-Z", "ASCII": "\\x00-\\x7f", "Alpha": "a-zA-Z", "Digit": "0-9", "Alnum": "a-zA-Z0-9",
    "Punct": "!-/:-@\\[-`{-~", "Graph": "!-~", "Print": " -~", "Blank": " \\t", "Cntrl": "\\x00-\\x1f\\x7f",
    "XDigit": "0-9a-fA-F", "Space": " \\t\\n\\x0b\\f\\r",
}
_LINE_END = "\\n\\r\\u0085\\u2028\\u2029"

_JAVA_WHITESPACE = {9, 10, 11, 12, 13, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x1680, 0x2028, 0x2029, 0x205F, 0x3000} | \
    set(range(0x2000, 0x2007)) | set(range(0x2008, 0x200B))


def _unicode_predicate(name):
    """a test on one character for a unicode category or a java character class; None for a name this does not know. strings
    here are utf-16 code units, so only the basic plane is looked at"""
    import unicodedata
    category = unicodedata.category
    if name in ("javaWhitespace", "IsWhite_Space", "IsWhiteSpace"):
        if name == "javaWhitespace":
            return lambda c: ord(c) in _JAVA_WHITESPACE
        return lambda c: category(c) in ("Zs", "Zl", "Zp") or ord(c) in (9, 10, 11, 12, 13, 0x85)
    if name == "javaSpaceChar":
        return lambda c: category(c) in ("Zs", "Zl", "Zp")
    if name in ("IsAlphabetic", "javaAlphabetic"):
        return lambda c: c.isalpha() or category(c) == "Nl"
    if name in ("IsLetter", "javaLetter"):
        return lambda c: category(c)[0] == "L"
    if name in ("IsDigit", "javaDigit"):
        return lambda c: category(c) == "Nd"
    if name == "javaLetterOrDigit":
        return lambda c: category(c)[0] == "L" or category(c) == "Nd"
    if name in ("IsUppercase", "javaUpperCase"):
        return lambda c: c.isupper()
    if name in ("IsLowercase", "javaLowerCase"):
        return lambda c: c.islower()
    if name == "javaTitleCase" or name == "IsTitlecase":
        return lambda c: category(c) == "Lt"
    if name in ("IsPunctuation",):
        return lambda c: category(c)[0] == "P"
    if name in ("IsControl", "javaISOControl"):
        return lambda c: category(c) == "Cc"
    if name == "LC":
        return lambda c: category(c) in ("Lu", "Ll", "Lt")
    if re.fullmatch(r"[LMNPSZC][a-z]?", name) and (len(name) == 1 or name in _CATEGORIES):
        return (lambda c: category(c)[0] == name) if len(name) == 1 else (lambda c: category(c) == name)
    return None


_CATEGORIES = frozenset("Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn".split())
_SPANS = {}


def _unicode_span(name, negate):
    """the inside of a re character class for a unicode property (all of it, or all but it)"""
    key = (name, negate)
    found = _SPANS.get(key)
    if found is not None:
        return found
    test = _unicode_predicate(name)
    if test is None:
        return None
    ranges = []
    start = None
    for code in range(0x10000):
        inside = bool(test(chr(code))) != negate
        if inside and start is None:
            start = code
        elif not inside and start is not None:
            ranges.append((start, code - 1))
            start = None
    if start is not None:
        ranges.append((start, 0xFFFF))
    text = "".join("\\u%04x" % a if a == b else "\\u%04x-\\u%04x" % (a, b) for a, b in ranges)
    _SPANS[key] = text
    return text


def _syntax(message, pattern, index=-1):
    runtime.throw_new("java.util.regex.PatternSyntaxException", "%s near index %d\n%s" % (message, index, pattern))


def translate_regex(pattern, flags):
    """python re source for a java pattern. the flags are applied by the caller"""
    if flags & LITERAL:
        return re.escape(pattern)
    out = []
    i = 0
    n = len(pattern)
    in_class = 0
    dotall = bool(flags & DOTALL)
    while i < n:
        c = pattern[i]
        if c == "\\":
            i += 1
            if i >= n:
                _syntax("Unexpected internal error", pattern, i)
            d = pattern[i]
            if d == "Q":
                end = pattern.find("\\E", i + 1)
                literal = pattern[i + 1:] if end < 0 else pattern[i + 1:end]
                out.append(re.escape(literal))
                i = n if end < 0 else end + 1
            elif d == "z":
                out.append("\\Z")
            elif d == "Z":
                out.append("(?=\\n?\\Z)")
            elif d == "h":
                out.append("[ \\t\\xa0\\u1680\\u180e\\u2000-\\u200a\\u202f\\u205f\\u3000]" if not in_class else " \\t\\xa0")
            elif d == "R":
                out.append("(?:\\r\\n|[\\n\\x0b\\f\\r\\x85\\u2028\\u2029])")
            elif d in "pP":
                name, i = _property(pattern, i)
                span = _POSIX.get(name)
                if span is None:
                    span = _unicode_span(name, d == "P")
                    if span is None:
                        _syntax("Unknown character property name {%s}" % name, pattern, i)
                    out.append(span if in_class else "[%s]" % span)
                elif in_class:
                    out.append(span if d == "p" else "")
                else:
                    out.append("[%s%s]" % ("^" if d == "P" else "", span))
            elif d == "G":
                out.append("")
            elif d == "e":
                out.append("\\x1b")
            elif d == "a":
                out.append("\\x07")
            elif d == "x" and i + 1 < n and pattern[i + 1] == "{":
                end = pattern.find("}", i)
                out.append("\\U%08x" % int(pattern[i + 2:end], 16))
                i = end
            elif d == "k":
                end = pattern.find(">", i)
                out.append("(?P=%s)" % pattern[i + 2:end])
                i = end
            elif d.isdigit() and d != "0":
                out.append("\\" + d)
            elif d in "dDwWsSbBAntrfv0uUxcN" or not d.isalnum():
                if d == "v" and not in_class:
                    out.append("[\\n\\x0b\\f\\r\\x85\\u2028\\u2029]")
                elif d == "s" and not in_class:
                    out.append("[ \\t\\n\\x0b\\f\\r]")
                elif d == "S" and not in_class:
                    out.append("[^ \\t\\n\\x0b\\f\\r]")
                elif d == "s" and in_class:
                    out.append(" \\t\\n\\x0b\\f\\r")
                else:
                    out.append("\\" + d)
            else:
                _syntax("Illegal/unsupported escape sequence", pattern, i)
            i += 1
            continue
        if in_class:
            if c == "[":
                if pattern.startswith("[", i) and in_class >= 1:
                    _syntax("character class union and intersection are not supported", pattern, i)
            elif c == "]":
                in_class -= 1
                out.append("]")
                i += 1
                continue
            elif c == "&" and pattern.startswith("&&", i):
                _syntax("character class intersection is not supported", pattern, i)
            out.append(c)
            i += 1
            continue
        if c == "[":
            in_class = 1
            out.append("[")
            i += 1
            if i < n and pattern[i] == "^":
                out.append("^")
                i += 1
            if i < n and pattern[i] == "]":
                out.append("\\]")
                i += 1
            continue
        if c == "(" and pattern.startswith("(?<", i) and i + 3 < n and pattern[i + 3] not in "=!":
            end = pattern.find(">", i)
            out.append("(?P<%s>" % pattern[i + 3:end])
            i = end + 1
            continue
        if c == "." and not dotall:
            out.append("[^%s]" % _LINE_END if not flags & UNIX_LINES else "[^\\n]")
            i += 1
            continue
        if c in "*+?}" and i + 1 < n and pattern[i + 1] == "+" and not (c == "?" and False):
            # possessive quantifier: python 3.11 knows it
            out.append(c + "+")
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _property(pattern, i):
    if i + 1 < len(pattern) and pattern[i + 1] == "{":
        end = pattern.find("}", i)
        return pattern[i + 2:end], end
    return pattern[i + 1], i + 1


@host_class("java.util.regex.MatchResult", interface=True)
class MatchResult:
    __slots__ = ()


@host_class("java.util.regex.Pattern", final=True, interfaces=("java.io.Serializable",))
class Pattern(Object):
    CASE_INSENSITIVE, MULTILINE, DOTALL, UNICODE_CASE, COMMENTS, LITERAL = 2, 8, 32, 64, 4, 16
    UNIX_LINES, CANON_EQ, UNICODE_CHARACTER_CLASS = 1, 128, 256
    _cache = {}

    def __init__(self, source, flags=0):
        self._source = source
        self._flags = flags
        python_flags = re.ASCII
        if flags & CASE_INSENSITIVE:
            python_flags |= re.IGNORECASE
            if flags & UNICODE_CASE:
                python_flags &= ~re.ASCII
        if flags & MULTILINE:
            python_flags |= re.MULTILINE
        if flags & DOTALL:
            python_flags |= re.DOTALL
        if flags & COMMENTS:
            python_flags |= re.VERBOSE
        if flags & UNICODE_CHARACTER_CLASS:
            python_flags &= ~re.ASCII
        translated = translate_regex(source, flags)
        try:
            self._re = re.compile(translated, python_flags)
        except re.error as error:
            _syntax(str(error), source, error.pos if error.pos is not None else -1)
        except RecursionError:
            _syntax("Pattern too complex", source)

    @jstatic("compile", "(Ljava/lang/String;)Ljava/util/regex/Pattern;")
    @jstatic("compile", "(Ljava/lang/String;I)Ljava/util/regex/Pattern;")
    def compile(source, flags=0):
        key = (source, flags)
        found = Pattern._cache.get(key)
        if found is None:
            found = Pattern(check_nonnull(source), flags)
            if len(Pattern._cache) > 256:
                Pattern._cache.clear()
            Pattern._cache[key] = found
        return found

    @jstatic("matches", "(Ljava/lang/String;Ljava/lang/CharSequence;)Z")
    def matches_static(source, text):
        return Pattern.compile(source).matcher(text).matches()

    @jstatic("quote", "(Ljava/lang/String;)Ljava/lang/String;")
    def quote(text):
        return "\\Q" + text.replace("\\E", "\\E\\\\E\\Q") + "\\E"

    @jmethod("matcher", "(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;")
    def matcher(self, text):
        return Matcher(self, _cs(text))

    @jmethod("pattern", "()Ljava/lang/String;")
    @jmethod("toString", "()Ljava/lang/String;")
    def pattern(self):
        return self._source

    @jmethod("flags", "()I")
    def flags(self):
        return self._flags

    @jmethod("split", "(Ljava/lang/CharSequence;)[Ljava/lang/String;")
    @jmethod("split", "(Ljava/lang/CharSequence;I)[Ljava/lang/String;")
    def split(self, text, limit=0):
        return split_text(self, _cs(text), limit)

    @jmethod("asPredicate", "()Ljava/util/function/Predicate;")
    def asPredicate(self):
        from .jfunc import Predicate, _Lambda
        return _Lambda("test", lambda s: bool(self.matcher(s).find()), Predicate)


def split_text(pattern, text, limit):
    if limit == 1 or not text:
        return to_array([text], "[Ljava/lang/String;")
    pieces = []
    index = 0
    for found in pattern._re.finditer(text):
        if limit > 0 and len(pieces) == limit - 1:
            break
        if found.end() == 0:
            continue
        if found.start() == found.end() and found.start() >= len(text):
            continue
        if found.start() == 0 and found.end() > 0 and index == 0 and found.start() == found.end():
            continue
        pieces.append(text[index:found.start()])
        index = found.end()
    if not pieces and index == 0:
        return to_array([text], "[Ljava/lang/String;")
    pieces.append(text[index:])
    if limit == 0:
        while pieces and pieces[-1] == "":
            pieces.pop()
    return to_array(pieces, "[Ljava/lang/String;")


@host_class("java.util.regex.Matcher", final=True, interfaces=("java.util.regex.MatchResult",))
class Matcher(Object):
    def __init__(self, pattern, text):
        self._p = pattern
        self._t = text
        self._m = None
        self._pos = 0
        self._append = 0
        self._region = (0, len(text))

    def _need(self):
        if self._m is None:
            runtime.throw_new("java.lang.IllegalStateException", "No match found")
        return self._m

    @jmethod("matches", "()Z")
    def matches(self):
        self._m = self._p._re.fullmatch(self._t, *self._region)
        return 1 if self._m else 0

    @jmethod("lookingAt", "()Z")
    def lookingAt(self):
        self._m = self._p._re.match(self._t, *self._region)
        return 1 if self._m else 0

    @jmethod("find", "()Z")
    @jmethod("find", "(I)Z")
    def find(self, start=None):
        if start is not None:
            if start < 0 or start > len(self._t):
                runtime.throw_new("java.lang.IndexOutOfBoundsException", "Illegal start index")
            self.reset()
            self._pos = start
        if self._pos > self._region[1]:
            self._m = None
            return 0
        found = self._p._re.search(self._t, self._pos, self._region[1])
        self._m = found
        if found is None:
            self._pos = len(self._t) + 1
            return 0
        self._pos = found.end() + (1 if found.end() == found.start() else 0)
        return 1

    @jmethod("group", "()Ljava/lang/String;")
    @jmethod("group", "(I)Ljava/lang/String;")
    @jmethod("group", "(Ljava/lang/String;)Ljava/lang/String;")
    def group(self, which=0):
        found = self._need()
        try:
            return found.group(which)
        except IndexError:
            runtime.throw_new("java.lang.IndexOutOfBoundsException", "No group %s" % which)

    @jmethod("groupCount", "()I")
    def groupCount(self):
        return self._p._re.groups

    @jmethod("start", "()I")
    @jmethod("start", "(I)I")
    @jmethod("start", "(Ljava/lang/String;)I")
    def start(self, which=0):
        return self._need().start(which)

    @jmethod("end", "()I")
    @jmethod("end", "(I)I")
    @jmethod("end", "(Ljava/lang/String;)I")
    def end(self, which=0):
        return self._need().end(which)

    @jmethod("reset", "()Ljava/util/regex/Matcher;")
    @jmethod("reset", "(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;")
    def reset(self, text=None):
        if text is not None:
            self._t = _cs(text)
        self._m = None
        self._pos = 0
        self._append = 0
        self._region = (0, len(self._t))
        return self

    @jmethod("region", "(II)Ljava/util/regex/Matcher;")
    def region(self, start, end):
        self.reset()
        self._region = (start, end)
        self._pos = start
        return self

    @jmethod("hitEnd", "()Z")
    def hitEnd(self):
        return 1 if self._m is None or self._m.end() == len(self._t) else 0

    def _expand(self, replacement):
        found = self._need()
        out = []
        i = 0
        while i < len(replacement):
            c = replacement[i]
            if c == "\\":
                i += 1
                if i >= len(replacement):
                    runtime.throw_new("java.lang.IllegalArgumentException", "character to be escaped is missing")
                out.append(replacement[i])
            elif c == "$":
                i += 1
                if i >= len(replacement):
                    runtime.throw_new("java.lang.IllegalArgumentException", "Illegal group reference: group index is missing")
                if replacement[i] == "{":
                    end = replacement.find("}", i)
                    name = replacement[i + 1:end]
                    try:
                        value = found.group(name)
                    except (IndexError, error_type):
                        runtime.throw_new("java.lang.IllegalArgumentException", "No group with name {%s}" % name)
                    i = end
                elif replacement[i].isdigit():
                    number = int(replacement[i])
                    while i + 1 < len(replacement) and replacement[i + 1].isdigit() and number * 10 + int(replacement[i + 1]) <= self._p._re.groups:
                        i += 1
                        number = number * 10 + int(replacement[i])
                    if number > self._p._re.groups:
                        runtime.throw_new("java.lang.IndexOutOfBoundsException", "No group %d" % number)
                    value = found.group(number)
                else:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Illegal group reference")
                out.append(value or "")
            else:
                out.append(c)
            i += 1
        return "".join(out)

    @jmethod("replaceAll", "(Ljava/lang/String;)Ljava/lang/String;")
    def replaceAll(self, replacement):
        self.reset()
        out = []
        last = 0
        while self.find():
            out.append(self._t[last:self._m.start()])
            out.append(self._expand(replacement))
            last = self._m.end()
        out.append(self._t[last:])
        return "".join(out)

    @jmethod("replaceFirst", "(Ljava/lang/String;)Ljava/lang/String;")
    def replaceFirst(self, replacement):
        self.reset()
        if not self.find():
            return self._t
        return self._t[:self._m.start()] + self._expand(replacement) + self._t[self._m.end():]

    @jmethod("appendReplacement", "(Ljava/lang/StringBuffer;Ljava/lang/String;)Ljava/util/regex/Matcher;")
    @jmethod("appendReplacement", "(Ljava/lang/StringBuilder;Ljava/lang/String;)Ljava/util/regex/Matcher;")
    def appendReplacement(self, builder, replacement):
        found = self._need()
        builder.append(self._t[self._append:found.start()])
        builder.append(self._expand(replacement))
        self._append = found.end()
        return self

    @jmethod("appendTail", "(Ljava/lang/StringBuffer;)Ljava/lang/StringBuffer;")
    @jmethod("appendTail", "(Ljava/lang/StringBuilder;)Ljava/lang/StringBuilder;")
    def appendTail(self, builder):
        builder.append(self._t[self._append:])
        return builder

    @jstatic("quoteReplacement", "(Ljava/lang/String;)Ljava/lang/String;")
    def quoteReplacement(text):
        return text.replace("\\", "\\\\").replace("$", "\\$")

    @jmethod("toMatchResult", "()Ljava/util/regex/MatchResult;")
    def toMatchResult(self):
        copy = Matcher(self._p, self._t)
        copy._m = self._m
        return copy


error_type = re.error


def string_matches(self, regex):
    return 1 if Pattern.compile(regex).matcher(self).matches() else 0


def string_replace_all(self, regex, replacement):
    return Pattern.compile(regex).matcher(self).replaceAll(replacement)


def string_replace_first(self, regex, replacement):
    return Pattern.compile(regex).matcher(self).replaceFirst(replacement)


def string_split(self, regex, limit=0):
    if len(regex) == 1 and regex not in ".$|()[{^?*+\\" or (len(regex) == 2 and regex[0] == "\\" and not regex[1].isalnum()):
        separator = regex[-1]
        pieces = []
        index = 0
        while True:
            found = self.find(separator, index)
            if found < 0 or (limit > 0 and len(pieces) == limit - 1):
                break
            pieces.append(self[index:found])
            index = found + 1
        if not pieces and index == 0:
            return to_array([self], "[Ljava/lang/String;")
        pieces.append(self[index:])
        if limit == 0:
            while pieces and pieces[-1] == "":
                pieces.pop()
        return to_array(pieces, "[Ljava/lang/String;")
    return split_text(Pattern.compile(regex), self, limit)
