"""java.text: NumberFormat, DecimalFormat, DecimalFormatSymbols, MessageFormat, ChoiceFormat, Normalizer, StringCharacterIterator, Collator, BreakIterator
and DateFormatSymbols

numbers format in the en_US way (a point and commas); a Locale only picks the symbols for a few languages. rounding is HALF_EVEN as in the jdk"""

import re
import unicodedata
from decimal import ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR, ROUND_HALF_DOWN, ROUND_HALF_EVEN, ROUND_HALF_UP, ROUND_UP, Decimal, InvalidOperation

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jfunc import jstring
from .jlang import Object, jstr
from .jtime import DAYS, MONTHS
from .jutil import check_nonnull

_ROUNDING = {"UP": ROUND_UP, "DOWN": ROUND_DOWN, "CEILING": ROUND_CEILING, "FLOOR": ROUND_FLOOR, "HALF_UP": ROUND_HALF_UP, "HALF_DOWN": ROUND_HALF_DOWN,
             "HALF_EVEN": ROUND_HALF_EVEN}


@host_class("java.text.Format", interfaces=("java.io.Serializable", "java.lang.Cloneable"))
class Format(Object):
    @jmethod("format", "(Ljava/lang/Object;)Ljava/lang/String;")
    def format(self, value, *_rest):
        raise NotImplementedError


@host_class("java.text.DecimalFormatSymbols", interfaces=("java.io.Serializable", "java.lang.Cloneable"))
class DecimalFormatSymbols(Object):
    def __init__(self, locale=None):
        language = locale.getLanguage() if locale is not None else "en"
        self._dec, self._grp = ("," , " ") if language in ("ru", "uk", "pl", "cs", "fr", "sv", "fi", "nb", "bg") else (
            (",", ".") if language in ("de", "es", "it", "pt", "tr", "nl", "id") else (".", ","))
        self._minus, self._percent, self._zero = "-", "%", "0"

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Locale;)V")
    def _init(self, locale=None):
        DecimalFormatSymbols.__init__(self, locale)

    @jstatic("getInstance", "()Ljava/text/DecimalFormatSymbols;")
    @jstatic("getInstance", "(Ljava/util/Locale;)Ljava/text/DecimalFormatSymbols;")
    def getInstance(locale=None):
        return DecimalFormatSymbols(locale)

    @jmethod("getDecimalSeparator", "()C")
    def getDecimalSeparator(self):
        return ord(self._dec)

    @jmethod("setDecimalSeparator", "(C)V")
    def setDecimalSeparator(self, c):
        self._dec = chr(c)

    @jmethod("getGroupingSeparator", "()C")
    def getGroupingSeparator(self):
        return ord(self._grp)

    @jmethod("setGroupingSeparator", "(C)V")
    def setGroupingSeparator(self, c):
        self._grp = chr(c)

    @jmethod("getMinusSign", "()C")
    def getMinusSign(self):
        return ord(self._minus)

    @jmethod("getPercent", "()C")
    def getPercent(self):
        return ord(self._percent)

    @jmethod("getZeroDigit", "()C")
    def getZeroDigit(self):
        return ord(self._zero)


@host_class("java.text.NumberFormat")
class NumberFormat(Format):
    INTEGER_FIELD = 0
    FRACTION_FIELD = 1

    def __init__(self, symbols=None):
        self._sym = symbols or DecimalFormatSymbols()
        self._min_int, self._max_int, self._min_frac, self._max_frac = 1, 40, 0, 3
        self._group, self._group_size = True, 3
        self._prefix = self._suffix = self._neg_prefix = ""
        self._neg_suffix = ""
        self._mult = 1
        self._rounding = ROUND_HALF_EVEN
        self._parse_int = False
        self._sci = False

    @jstatic("getInstance", "()Ljava/text/NumberFormat;")
    @jstatic("getInstance", "(Ljava/util/Locale;)Ljava/text/NumberFormat;")
    @jstatic("getNumberInstance", "()Ljava/text/NumberFormat;")
    @jstatic("getNumberInstance", "(Ljava/util/Locale;)Ljava/text/NumberFormat;")
    def getInstance(locale=None):
        return DecimalFormat("#,##0.###", DecimalFormatSymbols(locale))

    @jstatic("getIntegerInstance", "()Ljava/text/NumberFormat;")
    @jstatic("getIntegerInstance", "(Ljava/util/Locale;)Ljava/text/NumberFormat;")
    def getIntegerInstance(locale=None):
        result = DecimalFormat("#,##0", DecimalFormatSymbols(locale))
        result._parse_int = True
        return result

    @jstatic("getPercentInstance", "()Ljava/text/NumberFormat;")
    @jstatic("getPercentInstance", "(Ljava/util/Locale;)Ljava/text/NumberFormat;")
    def getPercentInstance(locale=None):
        return DecimalFormat("#,##0%", DecimalFormatSymbols(locale))

    @jstatic("getCurrencyInstance", "()Ljava/text/NumberFormat;")
    @jstatic("getCurrencyInstance", "(Ljava/util/Locale;)Ljava/text/NumberFormat;")
    def getCurrencyInstance(locale=None):
        return DecimalFormat("¤#,##0.00", DecimalFormatSymbols(locale))

    @jstatic("getCompactNumberInstance", "()Ljava/text/NumberFormat;")
    def getCompactNumberInstance():
        runtime.throw_new("java.lang.UnsupportedOperationException", "compact number formats are not implemented")

    def setMaximumFractionDigits(self, n):
        self._max_frac = max(0, n)
        self._min_frac = min(self._min_frac, self._max_frac)

    def setMinimumFractionDigits(self, n):
        self._min_frac = max(0, n)
        self._max_frac = max(self._max_frac, self._min_frac)

    def setMaximumIntegerDigits(self, n):
        self._max_int = max(0, n)
        self._min_int = min(self._min_int, self._max_int)

    def setMinimumIntegerDigits(self, n):
        self._min_int = max(0, n)
        self._max_int = max(self._max_int, self._min_int)

    def getMaximumFractionDigits(self):
        return self._max_frac

    def getMinimumFractionDigits(self):
        return self._min_frac

    def getMaximumIntegerDigits(self):
        return self._max_int

    def getMinimumIntegerDigits(self):
        return self._min_int

    def setGroupingUsed(self, flag):
        self._group = bool(flag)

    def isGroupingUsed(self):
        return 1 if self._group else 0

    def setParseIntegerOnly(self, flag):
        self._parse_int = bool(flag)

    def isParseIntegerOnly(self):
        return 1 if self._parse_int else 0

    def setRoundingMode(self, mode):
        self._rounding = _ROUNDING[mode.name()]

    def getRoundingMode(self):
        name = [k for k, v in _ROUNDING.items() if v == self._rounding][0]
        return lookup_host("java.math.RoundingMode").py.valueOf(name)

    def setCurrency(self, currency):
        self._currency = currency

    def getCurrency(self):
        return getattr(self, "_currency", lookup_host("java.util.Currency").py.getInstance("USD"))

    @jmethod("format", "(D)Ljava/lang/String;")
    @jmethod("format", "(J)Ljava/lang/String;")
    @jmethod("format", "(Ljava/lang/Object;)Ljava/lang/String;")
    def format(self, value, *_rest):
        if hasattr(value, "_v") and not isinstance(value._v, float):
            number = Decimal(value._v) if isinstance(value._v, int) else Decimal(str(value._v))
        elif hasattr(value, "value"):
            number = Decimal(value.value) if not isinstance(value.value, bool) else Decimal(int(value.value))
        elif hasattr(value, "_u") and hasattr(value, "_s"):
            number = Decimal(value._u).scaleb(-value._s)
        elif isinstance(value, float):
            if value != value:
                return "NaN"
            if value in (float("inf"), float("-inf")):
                return ("-" if value < 0 else "") + self._prefix + "∞" + self._suffix
            number = Decimal(value)
        elif isinstance(value, int):
            number = Decimal(value)
        else:
            runtime.throw_new("java.lang.IllegalArgumentException", "Cannot format given Object as a Number")
        return jstr(self._render(number))

    def _render(self, number):
        negative = number < 0 or (number == 0 and str(number).startswith("-") and False)
        number = abs(number) * self._mult
        quantum = Decimal(1).scaleb(-self._max_frac)
        try:
            rounded = number.quantize(quantum, rounding=self._rounding)
        except InvalidOperation:
            rounded = number
        text = format(rounded, "f")
        integer, _, fraction = text.partition(".")
        fraction = fraction.rstrip("0") if len(fraction) > self._min_frac else fraction
        fraction = fraction.ljust(self._min_frac, "0")
        integer = integer.lstrip("0")
        integer = integer.rjust(self._min_int, "0")[-self._max_int:] if self._max_int < len(integer) else integer.rjust(self._min_int, "0")
        if self._group and self._group_size > 0:
            parts = []
            while len(integer) > self._group_size:
                parts.insert(0, integer[-self._group_size:])
                integer = integer[:-self._group_size]
            parts.insert(0, integer)
            integer = self._sym._grp.join(parts)
        body = integer + (self._sym._dec + fraction if fraction else "")
        if negative and rounded == 0:
            negative = False if False else negative
        prefix = (self._neg_prefix if negative else self._prefix)
        suffix = (self._neg_suffix if negative else self._suffix)
        return prefix + body + suffix

    @jmethod("parse", "(Ljava/lang/String;)Ljava/lang/Number;")
    def parse(self, text):
        raw = text
        for token in (self._prefix, self._neg_prefix):
            pass
        negative = text.startswith(self._neg_prefix) and self._neg_prefix != self._prefix and bool(self._neg_prefix)
        if negative:
            text = text[len(self._neg_prefix):]
        elif self._prefix and text.startswith(self._prefix):
            text = text[len(self._prefix):]
        match = re.match(r"[%s%s0-9]+" % (re.escape(self._sym._grp), re.escape(self._sym._dec)), text) if text else None
        if match is None or not any(c.isdigit() for c in match.group(0)):
            runtime.throw_new("java.text.ParseException", "Unparseable number: \"%s\"" % raw) if False else _parse_error(raw)
        number = match.group(0).replace(self._sym._grp, "").replace(self._sym._dec, ".")
        if self._parse_int and "." in number:
            number = number.split(".")[0]
        value = Decimal(number) / self._mult
        if negative or text.startswith("-"):
            value = -value
        Long = lookup_host("java.lang.Long").py
        Double = lookup_host("java.lang.Double").py
        if value == value.to_integral_value() and abs(value) < 2 ** 63:
            return Long.valueOf(int(value))
        return Double(float(value))


def _parse_error(text):
    error = runtime.make_throwable(lookup_host("java.text.ParseException").py, 'Unparseable number: "%s"' % text)
    error._offset = 0
    raise error


@host_class("java.text.DecimalFormat")
class DecimalFormat(NumberFormat):
    def __init__(self, pattern="#,##0.###", symbols=None):
        NumberFormat.__init__(self, symbols)
        self.applyPattern(pattern)

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/text/DecimalFormatSymbols;)V")
    def _init(self, pattern="#,##0.###", symbols=None):
        DecimalFormat.__init__(self, pattern, symbols)

    def _quote(self, text):
        return text.replace("'", "").replace("¤", self.getCurrency().getSymbol() if hasattr(self, "_currency") else "$")

    @jmethod("applyPattern", "(Ljava/lang/String;)V")
    def applyPattern(self, pattern):
        self._pattern = pattern
        positive, _, negative = pattern.partition(";")
        match = re.match(r"((?:'[^']*'|[^#0,.])*)([#0,.]*(?:E0+)?)((?:'[^']*'|.)*)\Z", positive)
        if match is None or not any(c in match.group(2) for c in "#0"):
            runtime.throw_new("java.lang.IllegalArgumentException", "Malformed pattern \"%s\"" % pattern)
        prefix, number, suffix = match.groups()
        self._mult = 1
        if "%" in prefix + suffix:
            self._mult = 100
        elif "‰" in prefix + suffix:
            self._mult = 1000
        self._prefix, self._suffix = self._quote(prefix), self._quote(suffix)
        integer, _, fraction = number.partition(".")
        self._group = "," in integer
        self._group_size = len(integer) - integer.rindex(",") - 1 if self._group else 3
        digits = integer.replace(",", "")
        self._min_int = digits.count("0")
        self._max_int = 40
        self._min_frac = fraction.count("0")
        self._max_frac = len(fraction)
        if negative:
            m2 = re.match(r"((?:'[^']*'|[^#0,.])*)([#0,.]*)((?:'[^']*'|.)*)\Z", negative)
            self._neg_prefix, self._neg_suffix = self._quote(m2.group(1)), self._quote(m2.group(3))
        else:
            self._neg_prefix, self._neg_suffix = "-" + self._prefix, self._suffix

    @jmethod("toPattern", "()Ljava/lang/String;")
    def toPattern(self):
        return self._pattern

    @jmethod("setDecimalFormatSymbols", "(Ljava/text/DecimalFormatSymbols;)V")
    def setDecimalFormatSymbols(self, symbols):
        self._sym = symbols

    @jmethod("getDecimalFormatSymbols", "()Ljava/text/DecimalFormatSymbols;")
    def getDecimalFormatSymbols(self):
        return self._sym

    @jmethod("setGroupingSize", "(I)V")
    def setGroupingSize(self, n):
        self._group_size = n

    @jmethod("getGroupingSize", "()I")
    def getGroupingSize(self):
        return self._group_size

    @jmethod("setPositivePrefix", "(Ljava/lang/String;)V")
    def setPositivePrefix(self, text):
        self._prefix = text

    @jmethod("setNegativePrefix", "(Ljava/lang/String;)V")
    def setNegativePrefix(self, text):
        self._neg_prefix = text

    @jmethod("setPositiveSuffix", "(Ljava/lang/String;)V")
    def setPositiveSuffix(self, text):
        self._suffix = text

    @jmethod("setNegativeSuffix", "(Ljava/lang/String;)V")
    def setNegativeSuffix(self, text):
        self._neg_suffix = text

    @jmethod("setMultiplier", "(I)V")
    def setMultiplier(self, n):
        self._mult = n


@host_class("java.text.ChoiceFormat")
class ChoiceFormat(NumberFormat):
    def __init__(self, limits, formats=None):
        if formats is None:
            pairs = [part.split("#", 1) if "#" in part else part.split("<", 1) for part in limits.split("|")]
            strict = ["<" in part and "#" not in part for part in limits.split("|")]
            self._limits = [float(a) for a, _ in pairs]
            self._formats = [b for _, b in pairs]
            self._strict = strict
        else:
            self._limits, self._formats, self._strict = [float(x) for x in limits], list(formats), [False] * len(formats)
        NumberFormat.__init__(self)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "([D[Ljava/lang/String;)V")
    def _init(self, limits, formats=None):
        ChoiceFormat.__init__(self, limits, formats)

    @jmethod("format", "(D)Ljava/lang/String;")
    @jmethod("format", "(J)Ljava/lang/String;")
    @jmethod("format", "(Ljava/lang/Object;)Ljava/lang/String;")
    def format(self, value, *_rest):
        number = float(value.value if hasattr(value, "value") else value)
        index = 0
        for i, limit in enumerate(self._limits):
            if number > limit or (number == limit and not self._strict[i]):
                index = i
        return self._formats[index] if self._limits and number >= self._limits[0] or True else self._formats[0]

    @jmethod("getLimits", "()[D")
    def getLimits(self):
        array = runtime.new_array("[D", 0)
        array.extend(self._limits)
        return array

    @jmethod("getFormats", "()[Ljava/lang/Object;")
    def getFormats(self):
        array = runtime.new_array("[Ljava/lang/Object;", 0)
        array.extend(self._formats)
        return array


@host_class("java.text.MessageFormat")
class MessageFormat(Format):
    def __init__(self, pattern, locale=None):
        self._pattern = check_nonnull(pattern)
        self._locale = locale

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;Ljava/util/Locale;)V")
    def _init(self, pattern, locale=None):
        MessageFormat.__init__(self, pattern, locale)

    @jstatic("format", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;")
    def static_format(pattern, arguments):
        return MessageFormat(pattern).format(arguments)

    @jmethod("toPattern", "()Ljava/lang/String;")
    def toPattern(self):
        return self._pattern

    @jmethod("format", "([Ljava/lang/Object;)Ljava/lang/String;")
    @jmethod("format", "(Ljava/lang/Object;)Ljava/lang/String;")
    def format(self, arguments, *_rest):
        arguments = list(arguments) if isinstance(arguments, list) else [arguments]
        out = []
        pos = 0
        text = self._pattern
        while pos < len(text):
            char = text[pos]
            if char == "'":
                if text[pos + 1:pos + 2] == "'":
                    out.append("'")
                    pos += 2
                    continue
                end = text.find("'", pos + 1)
                if end == -1:
                    out.append(text[pos + 1:])
                    break
                out.append(text[pos + 1:end])
                pos = end + 1
            elif char == "{":
                depth, end = 1, pos + 1
                while end < len(text) and depth:
                    depth += {"{": 1, "}": -1}.get(text[end], 0)
                    end += 1
                if depth:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Unmatched braces in the pattern.")
                out.append(self._element(text[pos + 1:end - 1], arguments))
                pos = end
            else:
                out.append(char)
                pos += 1
        return jstr("".join(out))

    def _element(self, spec, arguments):
        parts = spec.split(",", 2)
        try:
            index = int(parts[0].strip())
        except ValueError:
            runtime.throw_new("java.lang.IllegalArgumentException", "can't parse argument number: " + parts[0])
        if index >= len(arguments):
            return "{" + parts[0].strip() + "}"
        value = arguments[index]
        if value is None:
            return "null"
        kind = parts[1].strip() if len(parts) > 1 else ""
        style = parts[2].strip() if len(parts) > 2 else ""
        if kind == "number":
            fmt = {"": NumberFormat.getInstance(self._locale), "integer": NumberFormat.getIntegerInstance(self._locale),
                   "percent": NumberFormat.getPercentInstance(self._locale), "currency": NumberFormat.getCurrencyInstance(self._locale)}.get(style)
            return fmt.format(value) if fmt is not None else DecimalFormat(style).format(value)
        if kind == "choice":
            chosen = ChoiceFormat(style).format(value)
            return MessageFormat(chosen, self._locale).format(arguments) if "{" in chosen else chosen
        if kind in ("date", "time"):
            DateFormat = lookup_host("java.text.DateFormat").py
            styles = {"": 2, "short": 3, "medium": 2, "long": 1, "full": 0}
            if style in styles:
                formatter = DateFormat.getDateInstance(styles[style]) if kind == "date" else DateFormat.getTimeInstance(styles[style])
            else:
                formatter = lookup_host("java.text.SimpleDateFormat").py(style)
            return formatter.format(value)
        if hasattr(value, "value") and isinstance(getattr(value, "value", None), (int, float)) or hasattr(value, "_v"):
            return NumberFormat.getInstance(self._locale).format(value)
        if isinstance(value, (bool, int, float)):
            return NumberFormat.getInstance(self._locale).format(value) if not isinstance(value, bool) else ("true" if value else "false")
        return jstring(value)


@host_class("java.text.Normalizer", final=True)
class Normalizer(Object):
    @jstatic("normalize", "(Ljava/lang/CharSequence;Ljava/text/Normalizer$Form;)Ljava/lang/String;")
    def normalize(text, form):
        return jstr(unicodedata.normalize(form._name, str(text) if isinstance(text, str) else text.toString()))

    @jstatic("isNormalized", "(Ljava/lang/CharSequence;Ljava/text/Normalizer$Form;)Z")
    def isNormalized(text, form):
        return 1 if unicodedata.is_normalized(form._name, str(text) if isinstance(text, str) else text.toString()) else 0


@host_class("java.text.Normalizer$Form", final=True)
class NormalizerForm(Object):
    def __init__(self, name):
        self._name = name

    @jmethod("name", "()Ljava/lang/String;")
    @jmethod("toString", "()Ljava/lang/String;")
    def name(self):
        return self._name


for _n in ("NFD", "NFC", "NFKD", "NFKC"):
    setattr(NormalizerForm, _n, NormalizerForm(_n))


@host_class("java.text.StringCharacterIterator", interfaces=("java.text.CharacterIterator", "java.lang.Cloneable"))
class StringCharacterIterator(Object):
    DONE = 0xFFFF

    def __init__(self, text, first=0, second=None, third=None):
        self._t = text
        if second is None:
            self._begin, self._end, self._pos = 0, len(text), first
        else:
            self._begin, self._end, self._pos = first, second, third

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/String;I)V")
    @jmethod("<init>", "(Ljava/lang/String;III)V")
    def _init(self, text, first=0, second=None, third=None):
        StringCharacterIterator.__init__(self, text, first, second, third)

    def _cur(self):
        return ord(self._t[self._pos]) if self._begin <= self._pos < self._end else 0xFFFF

    @jmethod("first", "()C")
    def first(self):
        self._pos = self._begin
        return self._cur()

    @jmethod("last", "()C")
    def last(self):
        self._pos = max(self._begin, self._end - 1) if self._end > self._begin else self._end
        return self._cur()

    @jmethod("current", "()C")
    def current(self):
        return self._cur()

    @jmethod("next", "()C")
    def next(self):
        if self._pos < self._end - 1:
            self._pos += 1
            return self._cur()
        self._pos = self._end
        return 0xFFFF

    @jmethod("previous", "()C")
    def previous(self):
        if self._pos > self._begin:
            self._pos -= 1
            return self._cur()
        return 0xFFFF

    @jmethod("setIndex", "(I)C")
    def setIndex(self, position):
        if not self._begin <= position <= self._end:
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid index")
        self._pos = position
        return self._cur()

    @jmethod("getBeginIndex", "()I")
    def getBeginIndex(self):
        return self._begin

    @jmethod("getEndIndex", "()I")
    def getEndIndex(self):
        return self._end

    @jmethod("getIndex", "()I")
    def getIndex(self):
        return self._pos

    @jmethod("setText", "(Ljava/lang/String;)V")
    def setText(self, text):
        self._t, self._begin, self._end, self._pos = text, 0, len(text), 0

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return StringCharacterIterator(self._t, self._begin, self._end, self._pos)


@host_class("java.text.BreakIterator", interfaces=("java.lang.Cloneable",))
class BreakIterator(Object):
    DONE = -1

    def __init__(self, kind, pattern):
        self._kind, self._re = kind, pattern
        self._text, self._bounds, self._i = "", [0], 0

    @jstatic("getWordInstance", "()Ljava/text/BreakIterator;")
    @jstatic("getWordInstance", "(Ljava/util/Locale;)Ljava/text/BreakIterator;")
    def getWordInstance(locale=None):
        return BreakIterator("word", re.compile(r"\w+|\s+|[^\w\s]", re.U))

    @jstatic("getSentenceInstance", "()Ljava/text/BreakIterator;")
    @jstatic("getSentenceInstance", "(Ljava/util/Locale;)Ljava/text/BreakIterator;")
    def getSentenceInstance(locale=None):
        return BreakIterator("sentence", re.compile(r".*?(?:[.!?…]+[\"')\]]*\s+|\n|$)", re.S))

    @jstatic("getLineInstance", "()Ljava/text/BreakIterator;")
    @jstatic("getLineInstance", "(Ljava/util/Locale;)Ljava/text/BreakIterator;")
    def getLineInstance(locale=None):
        return BreakIterator("line", re.compile(r"\S*\s+|\S+"))

    @jstatic("getCharacterInstance", "()Ljava/text/BreakIterator;")
    @jstatic("getCharacterInstance", "(Ljava/util/Locale;)Ljava/text/BreakIterator;")
    def getCharacterInstance(locale=None):
        return BreakIterator("character", re.compile(r"(?:[\ud800-\udbff][\udc00-\udfff]|.)[̀-ͯ‍️]*(?:‍(?:[\ud800-\udbff][\udc00-\udfff]|.)[️]?)*", re.S))

    @jmethod("setText", "(Ljava/lang/String;)V")
    def setText(self, text):
        self._text = text
        bounds = [0]
        pos = 0
        while pos < len(text):
            match = self._re.match(text, pos)
            end = match.end() if match and match.end() > pos else pos + 1
            bounds.append(end)
            pos = end
        self._bounds, self._i = bounds, 0

    @jmethod("first", "()I")
    def first(self):
        self._i = 0
        return self._bounds[0]

    @jmethod("last", "()I")
    def last(self):
        self._i = len(self._bounds) - 1
        return self._bounds[-1]

    @jmethod("next", "()I")
    def next(self):
        if self._i + 1 >= len(self._bounds):
            return -1
        self._i += 1
        return self._bounds[self._i]

    @jmethod("previous", "()I")
    def previous(self):
        if self._i == 0:
            return -1
        self._i -= 1
        return self._bounds[self._i]

    @jmethod("current", "()I")
    def current(self):
        return self._bounds[self._i]

    @jmethod("following", "(I)I")
    def following(self, offset):
        for index, bound in enumerate(self._bounds):
            if bound > offset:
                self._i = index
                return bound
        self._i = len(self._bounds) - 1
        return -1

    @jmethod("preceding", "(I)I")
    def preceding(self, offset):
        for index in range(len(self._bounds) - 1, -1, -1):
            if self._bounds[index] < offset:
                self._i = index
                return self._bounds[index]
        self._i = 0
        return -1

    @jmethod("isBoundary", "(I)Z")
    def isBoundary(self, offset):
        return 1 if offset in self._bounds else 0


@host_class("java.text.DateFormatSymbols", interfaces=("java.io.Serializable", "java.lang.Cloneable"))
class DateFormatSymbols(Object):
    def __init__(self, locale=None):
        pass

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(Ljava/util/Locale;)V")
    def _init(self, locale=None):
        return None

    @jstatic("getInstance", "()Ljava/text/DateFormatSymbols;")
    @jstatic("getInstance", "(Ljava/util/Locale;)Ljava/text/DateFormatSymbols;")
    def getInstance(locale=None):
        return DateFormatSymbols()

    def _strings(self, items):
        array = runtime.new_array("[Ljava/lang/String;", 0)
        array.extend(items)
        return array

    @jmethod("getMonths", "()[Ljava/lang/String;")
    def getMonths(self):
        return self._strings(MONTHS + [""])

    @jmethod("getShortMonths", "()[Ljava/lang/String;")
    def getShortMonths(self):
        return self._strings([m[:3] for m in MONTHS] + [""])

    @jmethod("getWeekdays", "()[Ljava/lang/String;")
    def getWeekdays(self):
        return self._strings([""] + list(DAYS))

    @jmethod("getShortWeekdays", "()[Ljava/lang/String;")
    def getShortWeekdays(self):
        return self._strings([""] + [d[:3] for d in DAYS])

    @jmethod("getAmPmStrings", "()[Ljava/lang/String;")
    def getAmPmStrings(self):
        return self._strings(["AM", "PM"])

    @jmethod("getEras", "()[Ljava/lang/String;")
    def getEras(self):
        return self._strings(["BC", "AD"])
