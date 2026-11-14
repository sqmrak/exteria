"""java.time.format: DateTimeFormatter and DateTimeFormatterBuilder (the printer-parser model of the jdk), SignStyle, ResolverStyle,
DecimalStyle, and the text of a parse (Parsed, a TemporalAccessor) that is resolved to a date, a time and a zone

a formatter is a list of elements. each element prints a field of a temporal or parses text into fields; optional sections, padding,
case and strictness settings are elements as in the jdk, so the toString of a formatter is the jdk text too. english is the only
locale: month, day, era and am/pm names are english, the localized styles are the en-US patterns of the jdk"""

import re

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jlang import Object, jstr
from .jtimeapi import (DAYS, MONTHS, ChronoField, DateTimeException, FormatStyle, Instant, LocalDate, LocalDateTime, LocalTime,
                       OffsetDateTime, TextStyle, Year, YearMonth, ZonedDateTime, ZoneId, ZoneOffset, _make_enum)
from .jutil import check_nonnull, iterate

_MIN64 = -(1 << 63)


def _throw(name, message=None):
    runtime.throw_new(name, message)


def _dt_error(message):
    runtime.throw_new("java.time.DateTimeException", message)


from .jmore import ResolverStyle, SignStyle  # noqa: E402


@host_class("java.time.format.DecimalStyle", final=True)
class DecimalStyle(Object):
    @staticmethod
    def of(locale):
        return DecimalStyle.STANDARD

    @staticmethod
    def ofDefaultLocale():
        return DecimalStyle.STANDARD

    @staticmethod
    def getAvailableLocales():
        from .jcoll import HashSet
        return HashSet()

    def getZeroDigit(self):
        return "0"

    def getPositiveSign(self):
        return "+"

    def getNegativeSign(self):
        return "-"

    def getDecimalSeparator(self):
        return "."

    def withZeroDigit(self, digit):
        return self if digit == "0" else _throw("java.lang.UnsupportedOperationException", "only the ascii digits are known")

    withPositiveSign = withNegativeSign = withDecimalSeparator = lambda self, c: self

    def equals(self, other):
        return 1 if isinstance(other, DecimalStyle) else 0

    def hashCode(self):
        return 182

    def toString(self):
        return "DecimalStyle[0+-.]"


DecimalStyle.STANDARD = DecimalStyle()


class PseudoField(Object):
    """a field that has no ChronoField: the quarter of the year and the localized day of the week"""

    def __init__(self, name, text):
        self._name, self._text = name, text

    def toString(self):
        return self._text

    def name(self):
        return self._name


QUARTER = PseudoField("QUARTER_OF_YEAR", "QuarterOfYear")
LOCAL_DAY_OF_WEEK = PseudoField("LOCALIZED_DAY_OF_WEEK", "DayOfWeek[WeekFields[SUNDAY,1]]")


def field_name(field):
    return check_nonnull(field)._name


def field_text(field):
    return field.toString()


_RANGES = {
    "NANO_OF_SECOND": (0, 999999999), "MICRO_OF_SECOND": (0, 999999), "MILLI_OF_SECOND": (0, 999), "SECOND_OF_MINUTE": (0, 59),
}


def _check_range(name, value, field_for_message=None):
    """ChronoField.checkValidValue with the jdk message"""
    field = getattr(ChronoField, name)
    field.checkValidValue(value)
    return value


_DOW_CLASS = lookup_host("java.time.DayOfWeek").py
_MONTH_CLASS = lookup_host("java.time.Month").py


class Adapter:
    """the fields of one temporal object: a date, a time, an offset, a zone and the instant it stands for"""

    def __init__(self, temporal):
        self.temporal = temporal
        self.date = self.time = self.offset = self.zone = self.epoch = None
        self.extra = {}
        self.region_zone = None
        t = temporal
        if isinstance(t, Parsed):
            self.date, self.time, self.zone = t.date, t.time, t.zone
            self.extra = dict(t.fields)
            if t.zone is not None and isinstance(t.zone, ZoneOffset):
                self.offset = t.zone
            if "OFFSET_SECONDS" in t.fields:
                self.offset = ZoneOffset.ofTotalSeconds(t.fields["OFFSET_SECONDS"])
            if "INSTANT_SECONDS" in t.fields:
                self.epoch = t.fields["INSTANT_SECONDS"]
            return
        if isinstance(t, LocalDate):
            self.date = t
        elif isinstance(t, LocalTime):
            self.time = t
        elif isinstance(t, LocalDateTime):
            self.date, self.time = t._date, t._time
        elif isinstance(t, ZonedDateTime):
            self.date, self.time = t._local._date, t._local._time
            self.offset, self.zone = t._offset, t._zone
            self.epoch = t.toEpochSecond()
        elif isinstance(t, OffsetDateTime):
            self.date, self.time = t._local._date, t._local._time
            self.offset, self.zone = t._offset, t._offset
            self.epoch = t.toEpochSecond()
        elif isinstance(t, Instant):
            self.epoch = t._s
            self.extra = {"NANO_OF_SECOND": t._n, "MICRO_OF_SECOND": t._n // 1000, "MILLI_OF_SECOND": t._n // 10 ** 6}
        elif isinstance(t, Year):
            self.extra = {"YEAR": t._v, "YEAR_OF_ERA": t._v if t._v >= 1 else 1 - t._v, "ERA": 1 if t._v >= 1 else 0}
        elif isinstance(t, YearMonth):
            y = t._y
            self.extra = {"YEAR": y, "MONTH_OF_YEAR": t._m, "PROLEPTIC_MONTH": y * 12 + t._m - 1,
                          "YEAR_OF_ERA": y if y >= 1 else 1 - y, "ERA": 1 if y >= 1 else 0}
        elif isinstance(t, _DOW_CLASS):
            self.extra = {"DAY_OF_WEEK": t._ordinal + 1}
        elif isinstance(t, _MONTH_CLASS):
            self.extra = {"MONTH_OF_YEAR": t._ordinal + 1}
        elif hasattr(t, "getLong") and hasattr(t, "isSupported"):
            self.generic = True
        else:
            _dt_error("Unable to obtain a temporal from " + str(t))

    def get(self, name):
        """the value of the field with that ChronoField name, or None when the temporal does not have it"""
        if name in self.extra:
            return self.extra[name]
        d, t = self.date, self.time
        if d is not None:
            if name == "YEAR":
                return d._y
            if name == "YEAR_OF_ERA":
                return d._y if d._y >= 1 else 1 - d._y
            if name == "ERA":
                return 1 if d._y >= 1 else 0
            if name == "MONTH_OF_YEAR":
                return d._m
            if name == "DAY_OF_MONTH":
                return d._d
            if name == "DAY_OF_YEAR":
                return d.getDayOfYear()
            if name == "DAY_OF_WEEK":
                return d.getDayOfWeek()._ordinal + 1
            if name == "EPOCH_DAY":
                return d.toEpochDay()
            if name == "PROLEPTIC_MONTH":
                return d._y * 12 + d._m - 1
            if name == "ALIGNED_WEEK_OF_MONTH":
                return (d._d - 1) // 7 + 1
            if name == "ALIGNED_DAY_OF_WEEK_IN_MONTH":
                return (d._d - 1) % 7 + 1
            if name == "ALIGNED_WEEK_OF_YEAR":
                return (d.getDayOfYear() - 1) // 7 + 1
            if name == "ALIGNED_DAY_OF_WEEK_IN_YEAR":
                return (d.getDayOfYear() - 1) % 7 + 1
            if name == "QUARTER_OF_YEAR":
                return (d._m - 1) // 3 + 1
            if name == "LOCALIZED_DAY_OF_WEEK":
                return (d.getDayOfWeek()._ordinal + 1) % 7 + 1
        if t is not None:
            h, mi, s, n = t._h, t._mi, t._s, t._n
            table = {"HOUR_OF_DAY": h, "CLOCK_HOUR_OF_DAY": h or 24, "HOUR_OF_AMPM": h % 12, "CLOCK_HOUR_OF_AMPM": h % 12 or 12,
                     "AMPM_OF_DAY": h // 12, "MINUTE_OF_HOUR": mi, "MINUTE_OF_DAY": h * 60 + mi, "SECOND_OF_MINUTE": s,
                     "SECOND_OF_DAY": h * 3600 + mi * 60 + s, "NANO_OF_SECOND": n, "MICRO_OF_SECOND": n // 1000,
                     "MILLI_OF_SECOND": n // 10 ** 6, "NANO_OF_DAY": (h * 3600 + mi * 60 + s) * 10 ** 9 + n,
                     "MICRO_OF_DAY": (h * 3600 + mi * 60 + s) * 10 ** 6 + n // 1000,
                     "MILLI_OF_DAY": (h * 3600 + mi * 60 + s) * 1000 + n // 10 ** 6}
            if name in table:
                return table[name]
        if name == "OFFSET_SECONDS" and self.offset is not None:
            return self.offset._seconds
        if name == "INSTANT_SECONDS" and self.epoch is not None:
            return self.epoch
        if getattr(self, "generic", False):
            try:
                field = getattr(ChronoField, name, None)
                if field is not None and self.temporal.isSupported(field):
                    return self.temporal.getLong(field)
            except Exception:
                return None
        return None


def with_zone_override(temporal, zone):
    """the temporal as a formatter with a zone prints it (DateTimePrintContext.adjust)"""
    if zone is None:
        return Adapter(temporal), None
    a = Adapter(temporal)
    if a.epoch is not None and not isinstance(temporal, Parsed):
        if isinstance(temporal, Instant):
            zoned = ZonedDateTime.ofInstant(temporal, zone)
        elif isinstance(temporal, (ZonedDateTime, OffsetDateTime)):
            zoned = ZonedDateTime.ofInstant(temporal.toInstant(), zone)
        else:
            zoned = None
        if zoned is not None:
            return Adapter(zoned), zone
    if isinstance(zone, ZoneOffset) and a.offset is not None and a.offset._seconds != zone._seconds:
        _dt_error("Unable to apply override zone '%s' because the temporal object being formatted has a different offset but does not represent an instant: %s" % (
            zone.toString(), temporal.toString()))
    a.zone = zone
    if isinstance(zone, ZoneOffset):
        a.offset = zone
    return a, zone


class PrintContext:
    def __init__(self, adapter):
        self.a = adapter
        self.optional = 0
        self.chrono = None

    def value(self, field):
        v = self.a.get(field_name(field))
        if v is None and self.optional == 0:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field_text(field))
        return v


class ParseContext:
    def __init__(self, text, strict_style=True):
        self.text = text
        self.case = True
        self.strict = True
        self.chrono = None
        self.stack = [Unresolved()]

    @property
    def cur(self):
        return self.stack[-1]

    def start_optional(self):
        self.stack.append(self.cur.copy())

    def end_optional(self, ok):
        if ok:
            del self.stack[-2]
        else:
            self.stack.pop()

    def set_field(self, field, value, err, ok):
        name = field_name(field)
        old = self.cur.fields.get(name)
        if old is not None and old != value:
            return ~err
        self.cur.fields[name] = value
        return ok

    def set_zone(self, zone):
        self.cur.zone = zone

    def starts(self, pos, literal):
        chunk = self.text[pos:pos + len(literal)]
        return chunk == literal if self.case else chunk.lower() == literal.lower()


class Unresolved:
    def __init__(self):
        self.fields = {}
        self.zone = None

    def copy(self):
        c = Unresolved()
        c.fields = dict(self.fields)
        c.zone = self.zone
        return c


_EXCEED = [10 ** i for i in range(19)]


class Literal:
    def __init__(self, text):
        self.text = text

    def format(self, pc, out):
        out.append(self.text)
        return True

    def parse(self, cc, text, pos):
        if pos > len(text) or pos < 0:
            raise IndexError
        if not cc.starts(pos, self.text):
            return ~pos
        return pos + len(self.text)

    def __str__(self):
        return "'" + self.text.replace("'", "''") + "'" if len(self.text) != 1 or self.text != "'" else "''"


class Settings:
    def __init__(self, kind):
        self.kind = kind

    def format(self, pc, out):
        return True

    def parse(self, cc, text, pos):
        if self.kind == 0:
            cc.case = True
        elif self.kind == 1:
            cc.case = False
        elif self.kind == 2:
            cc.strict = True
        else:
            cc.strict = False
        return pos

    def __str__(self):
        return ["ParseCaseSensitive(true)", "ParseCaseSensitive(false)", "ParseStrict(true)", "ParseStrict(false)"][self.kind]


class Defaulting:
    def __init__(self, field, value):
        self.field, self.value = field, value

    def format(self, pc, out):
        return True

    def parse(self, cc, text, pos):
        if cc.cur.fields.get(field_name(self.field)) is None:
            cc.set_field(self.field, self.value, pos, pos)
        return pos

    def __str__(self):
        return "Default(%s,%d)" % (field_text(self.field), self.value)


def _sign_parse(style, positive, strict, fixed):
    n = style._ordinal
    if n == 0:
        return not positive or not strict
    if n in (1, 4):
        return True
    return not strict and not fixed


class Number:
    def __init__(self, field, min_width, max_width, sign, subsequent=0):
        self.field, self.min, self.max, self.sign, self.subsequent = field, min_width, max_width, sign, subsequent

    def with_fixed(self):
        if self.subsequent == -1:
            return self
        return Number(self.field, self.min, self.max, self.sign, -1)

    def with_subsequent(self, width):
        return Number(self.field, self.min, self.max, self.sign, self.subsequent + width)

    def is_fixed(self, cc):
        return self.subsequent == -1 or (self.subsequent > 0 and self.min == self.max and self.sign is SignStyle.NOT_NEGATIVE)

    def format(self, pc, out):
        value = pc.value(self.field)
        if value is None:
            return False
        return self._print(value, out)

    def _print(self, value, out):
        digits = str(abs(value))
        if len(digits) > self.max:
            _dt_error("Field %s cannot be printed as the value %d exceeds the maximum print width of %d" % (
                field_text(self.field), value, self.max))
        digits = digits.rjust(self.min, "0")
        if value >= 0:
            n = self.sign._ordinal
            if n == 4:
                if self.min < 19 and value >= _EXCEED[self.min]:
                    out.append("+")
            elif n == 1:
                out.append("+")
        else:
            n = self.sign._ordinal
            if n in (0, 4, 1):
                out.append("-")
            elif n == 3:
                _dt_error("Field %s cannot be printed as the value %d cannot be negative according to the SignStyle" % (
                    field_text(self.field), value))
        out.append(digits)
        return True

    def set_value(self, cc, value, start, end):
        return cc.set_field(self.field, value, start, end)

    def parse(self, cc, text, pos):
        length = len(text)
        if pos == length:
            return ~pos
        sign = text[pos]
        negative = positive = False
        start = pos
        if sign == "+":
            if not _sign_parse(self.sign, True, cc.strict, self.min == self.max):
                return ~pos
            positive = True
            pos += 1
        elif sign == "-":
            if not _sign_parse(self.sign, False, cc.strict, self.min == self.max):
                return ~pos
            negative = True
            pos += 1
        elif self.sign is SignStyle.ALWAYS and cc.strict:
            return ~pos
        fixed = self.is_fixed(cc)
        eff_min = self.min if cc.strict or fixed else 1
        min_end = pos + eff_min
        if min_end > length:
            return ~pos
        eff_max = (self.max if cc.strict or fixed else 9) + max(self.subsequent, 0)
        total = 0
        begin = pos
        for attempt in range(2):
            max_end = min(pos + eff_max, length)
            while pos < max_end:
                ch = text[pos]
                pos += 1
                if not "0" <= ch <= "9":
                    pos -= 1
                    if pos < min_end:
                        return ~begin
                    break
                total = total * 10 + (ord(ch) - 48)
            if self.subsequent > 0 and attempt == 0:
                parse_len = pos - begin
                eff_max = max(eff_min, parse_len - self.subsequent)
                pos = begin
                total = 0
            else:
                break
        if negative:
            if total == 0 and cc.strict:
                return ~(begin - 1)
            total = -total
        elif self.sign is SignStyle.EXCEEDS_PAD and cc.strict:
            parse_len = pos - begin
            if positive:
                if parse_len <= self.min:
                    return ~(begin - 1)
            elif parse_len > self.min:
                return ~begin
        if pos == begin and not (total or eff_min == 0):
            return ~begin
        return self.set_value(cc, total, begin, pos)

    def __str__(self):
        if self.min == 1 and self.max == 19 and self.sign is SignStyle.NORMAL:
            return "Value(%s)" % field_text(self.field)
        if self.min == self.max and self.sign is SignStyle.NOT_NEGATIVE:
            return "Value(%s,%d)" % (field_text(self.field), self.min)
        return "Value(%s,%d,%d,%s)" % (field_text(self.field), self.min, self.max, self.sign.name())


class Reduced(Number):
    def __init__(self, field, min_width, max_width, base, base_date=None, subsequent=0):
        Number.__init__(self, field, min_width, max_width, SignStyle.NOT_NEGATIVE, subsequent)
        self.base, self.base_date = base, base_date

    def with_fixed(self):
        return Reduced(self.field, self.min, self.max, self.base, self.base_date, -1) if self.subsequent != -1 else self

    def with_subsequent(self, width):
        return Reduced(self.field, self.min, self.max, self.base, self.base_date, self.subsequent + width)

    def _base_value(self):
        if self.base_date is not None:
            return self.base_date._y
        return self.base

    def format(self, pc, out):
        value = pc.value(self.field)
        if value is None:
            return False
        value = abs(value)
        base = self._base_value()
        range_ = _EXCEED[self.min]
        if base <= value < base + range_:
            value %= range_
        else:
            value %= _EXCEED[self.max]
        return self._print(value, out)

    def set_value(self, cc, value, start, end):
        base = self._base_value()
        parse_len = end - start
        if parse_len == self.min and value >= 0:
            range_ = _EXCEED[self.min]
            last = base % range_
            basic = base - last
            value = basic + value if base > 0 else basic - value
            if value < base:
                value += range_
        return cc.set_field(self.field, value, start, end)

    def __str__(self):
        return "ReducedValue(%s,%d,%d,%s)" % (field_text(self.field), self.min, self.max,
                                              self.base_date.toString() if self.base_date is not None else self.base)


class Fraction:
    def __init__(self, field, min_width, max_width, point):
        self.field, self.min, self.max, self.point = field, min_width, max_width, point

    def _range(self):
        name = field_name(self.field)
        low, high = {"NANO_OF_SECOND": (0, 999999999), "MICRO_OF_SECOND": (0, 999999), "MILLI_OF_SECOND": (0, 999),
                     "SECOND_OF_MINUTE": (0, 59), "MINUTE_OF_HOUR": (0, 59), "HOUR_OF_DAY": (0, 23)}[name][:2]
        return low, high

    def is_fixed(self):
        return self.min == self.max and not self.point

    def format(self, pc, out):
        value = pc.value(self.field)
        if value is None:
            return False
        low, high = self._range()
        digits9 = (value - low) * 10 ** 9 // (high - low + 1)
        text = ("%09d" % digits9).rstrip("0")
        if not text:
            if self.min > 0:
                if self.point:
                    out.append(".")
                out.append("0" * self.min)
        else:
            width = min(max(len(text), self.min), self.max)
            out.append("." if self.point else "")
            out.append(("%09d" % digits9).ljust(width, "0")[:width])
        return True

    def parse(self, cc, text, pos):
        eff_min = self.min if cc.strict or self.is_fixed() else 0
        eff_max = self.max if cc.strict or self.is_fixed() else 9
        length = len(text)
        if pos == length:
            return ~pos if eff_min > 0 else pos
        if self.point:
            if text[pos] != ".":
                return ~pos if eff_min > 0 else pos
            pos += 1
        min_end = pos + eff_min
        if min_end > length:
            return ~pos
        max_end = min(pos + eff_max, length)
        total = 0
        p = pos
        while p < max_end:
            ch = text[p]
            p += 1
            if not "0" <= ch <= "9":
                if p - 1 < min_end:
                    return ~pos
                p -= 1
                break
            total = total * 10 + (ord(ch) - 48)
        count = p - pos
        if count == 0 and eff_min > 0:
            return ~pos
        low, high = self._range()
        value = low + (total * (high - low + 1)) // (10 ** count) if count else low
        return cc.set_field(self.field, value, pos, p)

    def __str__(self):
        return "Fraction(%s,%d,%d%s)" % (field_text(self.field), self.min, self.max, ",DecimalPoint" if self.point else "")


_ERA_TEXT = {0: ("BC", "Before Christ", "B"), 1: ("AD", "Anno Domini", "A")}
_AMPM_TEXT = {0: ("AM", "AM", "a"), 1: ("PM", "PM", "p")}
_DOW = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
_QUARTER_TEXT = {i: ("Q%d" % i, "%s quarter" % ("1st", "2nd", "3rd", "4th")[i - 1], str(i)) for i in range(1, 5)}


def text_table(field, chrono=None):
    """value -> (short, full, narrow) for a field that has names, else None"""
    name = field_name(field)
    if name == "ERA" and chrono is not None:
        return chrono.era_table()
    if name == "MONTH_OF_YEAR":
        return {i + 1: (m[:3], m, m[0]) for i, m in enumerate(MONTHS)}
    if name == "DAY_OF_WEEK":
        return {i + 1: (d[:3], d, d[0]) for i, d in enumerate(_DOW)}
    if name == "LOCALIZED_DAY_OF_WEEK":
        order = _DOW[-1:] + _DOW[:-1]
        return {i + 1: (d[:3], d, d[0]) for i, d in enumerate(order)}
    if name == "ERA":
        return _ERA_TEXT
    if name == "AMPM_OF_DAY":
        return _AMPM_TEXT
    if name == "QUARTER_OF_YEAR":
        return _QUARTER_TEXT
    return None


def _style_index(style):
    n = style._name
    return 1 if n.startswith("FULL") else 2 if n.startswith("NARROW") else 0


class Text:
    def __init__(self, field, style, custom=None):
        self.field, self.style, self.custom = field, style, custom
        self.number = Number(field, 1, 19, SignStyle.NORMAL)

    def _names(self, chrono=None):
        if self.custom is not None:
            return {k: (v, v, v) for k, v in self.custom.items()}
        return text_table(self.field, chrono)

    def format(self, pc, out):
        value = pc.value(self.field)
        if value is None:
            return False
        table = self._names(pc.chrono)
        if table is not None and value in table:
            out.append(table[value][_style_index(self.style)])
            return True
        return self.number.format(pc, out)

    def parse(self, cc, text, pos):
        length = len(text)
        if pos < 0 or pos > length:
            raise IndexError
        table = self._names(cc.chrono)
        if table is not None:
            best = None
            indexes = (_style_index(self.style),) if cc.strict else (0, 1, 2)
            for value, names in table.items():
                for i in indexes:
                    name = names[i]
                    if name and cc.starts(pos, name):
                        if best is None or len(name) > best[1]:
                            best = (value, len(name))
            if best is not None:
                return cc.set_field(self.field, best[0], pos, pos + best[1])
            if cc.strict:
                return ~pos
        return self.number.parse(cc, text, pos)

    def __str__(self):
        if self.style is TextStyle.FULL:
            return "Text(%s)" % field_text(self.field)
        return "Text(%s,%s)" % (field_text(self.field), self.style.name())


_OFFSET_PATTERNS = ["+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss", "+HHMMSS", "+HH:MM:SS", "+HHmmss", "+HH:mm:ss",
                    "+H", "+Hmm", "+H:mm", "+HMM", "+H:MM", "+HMMss", "+H:MM:ss", "+HMMSS", "+H:MM:SS", "+Hmmss", "+H:mm:ss"]


class Offset:
    def __init__(self, pattern, no_offset):
        if pattern not in _OFFSET_PATTERNS:
            runtime.throw_new("java.lang.IllegalArgumentException", "Invalid zone offset pattern: " + pattern)
        self.pattern, self.type, self.no = pattern, _OFFSET_PATTERNS.index(pattern), no_offset
        self.colon = ":" in pattern
        self.padded = self.type < 11

    def format(self, pc, out):
        seconds = pc.a.get("OFFSET_SECONDS")
        if seconds is None:
            if pc.optional == 0:
                runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: OffsetSeconds")
            return False
        if seconds == 0:
            out.append(self.no)
            return True
        absh = abs(seconds // 3600 if seconds >= 0 else -((-seconds) // 3600)) % 100
        absm = abs(int(seconds / 60)) % 60
        abss = abs(seconds) % 60
        t = self.type - 11 if self.type >= 11 else self.type
        buf = "-" if seconds < 0 else "+"
        buf += ("%02d" % absh) if self.padded or absh >= 10 else str(absh)
        output = absh
        if (3 <= t <= 8) or (t >= 9 and abss > 0) or (t >= 1 and absm > 0):
            buf += (":" if self.colon else "") + "%02d" % absm
            output += absm
            if t in (7, 8) or (t >= 5 and abss > 0):
                buf += (":" if self.colon else "") + "%02d" % abss
                output += abss
        if output == 0:
            buf = self.no
        out.append(buf)
        return True

    def parse(self, cc, text, pos):
        length = len(text)
        no_len = len(self.no)
        if no_len == 0:
            if pos == length:
                return cc.set_field(ChronoField.OFFSET_SECONDS, 0, pos, pos)
        else:
            if pos == length:
                return ~pos
            if cc.starts(pos, self.no):
                return cc.set_field(ChronoField.OFFSET_SECONDS, 0, pos, pos + no_len)
        sign = text[pos]
        if sign in "+-":
            negative = -1 if sign == "-" else 1
            array = [pos + 1, 0, 0, 0]
            t = self.type - 11 if self.type >= 11 else self.type
            if not self._parse_hour(array, text) and \
                    not self._parse_number(array, 2, text, 3 <= t <= 8) and \
                    not self._parse_number(array, 3, text, False):
                total = negative * (array[1] * 3600 + array[2] * 60 + array[3])
                return cc.set_field(ChronoField.OFFSET_SECONDS, total, pos, array[0])
        if no_len == 0:
            return cc.set_field(ChronoField.OFFSET_SECONDS, 0, pos, pos)
        return ~pos

    def _parse_hour(self, array, text):
        """True when the hour could not be parsed"""
        pos = array[0]
        run = 0
        while pos + run < len(text) and "0" <= text[pos + run] <= "9":
            run += 1
        if run == 0:
            return True
        t = self.type - 11 if self.type >= 11 else self.type
        if self.padded:
            if run < 2:
                return True
            width = 2
        elif self.colon:
            width = 2 if run >= 2 else 1
        elif t == 0:
            width = 2 if run >= 2 else 1
        else:
            width = 1 if run % 2 else 2
        value = int(text[pos:pos + width])
        if value > 23:
            if width == 2 and not self.padded:
                width, value = 1, int(text[pos])
            else:
                return True
        array[1] = value
        array[0] = pos + width
        return False

    def _parse_number(self, array, arrayIndex, parse, required):
        """True when the field could not be parsed"""
        t = self.type - 11 if self.type >= 11 else self.type
        if (t + 3) // 2 < arrayIndex:
            return False
        pos = array[0]
        if t % 2 == 0 and arrayIndex > 1:
            if pos + 1 > len(parse) or parse[pos] != ":":
                return required
            pos += 1
        if pos + 2 > len(parse):
            return required
        ch1, ch2 = parse[pos], parse[pos + 1]
        pos += 2
        if not ("0" <= ch1 <= "9") or not ("0" <= ch2 <= "9"):
            return required
        value = (ord(ch1) - 48) * 10 + (ord(ch2) - 48)
        if value > 59:
            return required
        array[arrayIndex] = value
        array[0] = pos
        return False

    def __str__(self):
        return "Offset(%s,'%s')" % (self.pattern, self.no.replace("'", "''"))


class LocalizedOffset:
    def __init__(self, style):
        self.style = style

    def format(self, pc, out):
        seconds = pc.a.get("OFFSET_SECONDS")
        if seconds is None:
            if pc.optional == 0:
                runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: OffsetSeconds")
            return False
        out.append("GMT")
        if seconds != 0:
            absh = abs(seconds // 3600 if seconds >= 0 else -((-seconds) // 3600)) % 100
            absm = abs(int(seconds / 60)) % 60
            abss = abs(seconds) % 60
            out.append("-" if seconds < 0 else "+")
            if self.style is TextStyle.FULL:
                out.append("%02d:%02d" % (absh, absm))
                if abss:
                    out.append(":%02d" % abss)
            else:
                out.append(str(absh))
                if absm or abss:
                    out.append(":%02d" % absm)
                    if abss:
                        out.append(":%02d" % abss)
        return True

    def parse(self, cc, text, pos):
        if not cc.starts(pos, "GMT"):
            return ~pos
        pos += 3
        if pos == len(text) or text[pos] not in "+-":
            return cc.set_field(ChronoField.OFFSET_SECONDS, 0, pos - 3, pos)
        match = re.compile(r"([+-])(\d{1,2})(?::(\d{2}))?(?::(\d{2}))?").match(text, pos)
        if match is None:
            return ~pos
        sign = -1 if match.group(1) == "-" else 1
        total = sign * (int(match.group(2)) * 3600 + int(match.group(3) or 0) * 60 + int(match.group(4) or 0))
        return cc.set_field(ChronoField.OFFSET_SECONDS, total, pos, match.end())

    def __str__(self):
        return "LocalizedOffset(%s)" % self.style.name()


_ZONE_CHARS = re.compile(r"[A-Za-z0-9/_+\-:.~]+")


class ZoneIdElement:
    def __init__(self, region_only=False, text_style=None):
        self.region_only, self.text_style = region_only, text_style

    def format(self, pc, out):
        zone = pc.a.zone
        if zone is None:
            if pc.optional > 0:
                return False
            _dt_error("Unable to extract ZoneId from temporal %s" % (pc.a.temporal.toString()))
        if self.region_only and isinstance(zone, ZoneOffset):
            if pc.optional > 0:
                return False
            _dt_error("Unable to extract ZoneId from temporal %s" % pc.a.temporal.toString())
        if self.text_style is not None and not isinstance(zone, ZoneOffset):
            epoch = pc.a.epoch
            name = zone.getId()
            if self.text_style is not TextStyle.FULL and epoch is not None and hasattr(zone, "_zone"):
                try:
                    name = zone._zone.short_name(epoch * 1000)
                except Exception:
                    pass
            out.append(name)
        else:
            out.append(zone.getId())
        return True

    def parse(self, cc, text, pos):
        length = len(text)
        if pos > length:
            raise IndexError
        if pos == length:
            return ~pos
        ch = text[pos]
        if ch in "+-":
            offset = Offset("+HH:MM:ss", "Z")
            sub = ParseContext(text)
            result = offset.parse(sub, text, pos)
            if result < 0:
                return result
            seconds = sub.cur.fields["OFFSET_SECONDS"]
            cc.set_zone(ZoneOffset.ofTotalSeconds(seconds))
            return result
        if length >= pos + 2:
            c2 = text[pos + 1]
            if cc.case and text[pos] in "Uu" and False:
                pass
        for prefix in ("UTC", "GMT", "UT"):
            if cc.starts(pos, prefix):
                end = pos + len(prefix)
                if end < length and text[end] in "+-":
                    sub = ParseContext(text)
                    result = Offset("+HH:MM:ss", "0").parse(sub, text, end)
                    if result >= 0:
                        seconds = sub.cur.fields.get("OFFSET_SECONDS", 0)
                        cc.set_zone(ZoneId.of(prefix) if seconds == 0 else ZoneId.of(prefix + ZoneOffset.ofTotalSeconds(seconds).getId()))
                        return result
                if prefix != "UT" or True:
                    if not (end < length and _ZONE_CHARS.match(text, end) and text[end] not in "+-" and prefix == "UT"):
                        cc.set_zone(ZoneId.of(prefix))
                        return end
        if ch == "Z" or (not cc.case and ch == "z"):
            if not self.region_only:
                cc.set_zone(ZoneOffset.UTC)
                return pos + 1
        match = _ZONE_CHARS.match(text, pos)
        if match is None:
            return ~pos
        candidate = match.group(0)
        while candidate:
            try:
                zone = ZoneId.of(candidate)
                cc.set_zone(zone)
                return pos + len(candidate)
            except Exception:
                candidate = candidate[:-1]
        return ~pos

    def __str__(self):
        if self.text_style is not None:
            return "ZoneText(%s)" % self.text_style.name()
        return "ZoneRegionId()" if self.region_only else "ZoneId()"


class InstantElement:
    def __init__(self, digits):
        self.digits = digits

    def format(self, pc, out):
        seconds = pc.a.get("INSTANT_SECONDS")
        if seconds is None:
            if pc.optional == 0:
                runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: InstantSeconds")
            return False
        nanos = pc.a.get("NANO_OF_SECOND")
        if nanos is None:
            nanos = 0
        digits = self.digits
        in_nano = nanos if nanos is not None else 0
        local = LocalDateTime.ofEpochSecond(seconds, 0, ZoneOffset.UTC)
        year = local._date._y
        if year < 10000 and year >= 0:
            out.append("%04d" % year)
        else:
            out.append(("+" if year > 9999 else "") + str(year) if year > 9999 else "-%04d" % (-year) if year > -10000 else str(year))
        d = local._date
        t = local._time
        out.append("-%02d-%02dT%02d:%02d:%02d" % (d._m, d._d, t._h, t._mi, t._s))
        if digits == -2:
            if in_nano:
                out.append(".")
                if in_nano % 1000000 == 0:
                    out.append("%03d" % (in_nano // 1000000))
                elif in_nano % 1000 == 0:
                    out.append("%06d" % (in_nano // 1000))
                else:
                    out.append("%09d" % in_nano)
        elif digits > 0 or (digits == -1 and in_nano > 0):
            out.append(".")
            n = digits
            text = "%09d" % in_nano
            if digits == -1:
                text = text.rstrip("0")
            else:
                text = text[:n].ljust(n, "0")
            out.append(text)
        out.append("Z")
        return True

    def parse(self, cc, text, pos):
        min_digits = 0 if self.digits < 0 else self.digits
        max_digits = 9 if self.digits < 0 else self.digits
        sub = ParseContext(text)
        sub.case = cc.case
        parts = [Number(ChronoField.YEAR, 4, 10, SignStyle.EXCEEDS_PAD), Literal("-"), Number(ChronoField.MONTH_OF_YEAR, 2, 2, SignStyle.NOT_NEGATIVE),
                 Literal("-"), Number(ChronoField.DAY_OF_MONTH, 2, 2, SignStyle.NOT_NEGATIVE), Literal("T"),
                 Number(ChronoField.HOUR_OF_DAY, 2, 2, SignStyle.NOT_NEGATIVE), Literal(":"),
                 Number(ChronoField.MINUTE_OF_HOUR, 2, 2, SignStyle.NOT_NEGATIVE), Literal(":"),
                 Number(ChronoField.SECOND_OF_MINUTE, 2, 2, SignStyle.NOT_NEGATIVE),
                 Fraction(ChronoField.NANO_OF_SECOND, min_digits, max_digits, True), Offset("+HH:MM:ss", "Z")]
        p = pos
        for part in parts:
            p = part.parse(sub, text, p)
            if p < 0:
                return p
        f = sub.cur.fields
        year, month, day = f["YEAR"], f["MONTH_OF_YEAR"], f["DAY_OF_MONTH"]
        hour, minute, second, nano = f["HOUR_OF_DAY"], f["MINUTE_OF_HOUR"], f["SECOND_OF_MINUTE"], f.get("NANO_OF_SECOND", 0)
        offset = f.get("OFFSET_SECONDS", 0)
        days = 0
        if hour == 24 and minute == 0 and second == 0 and nano == 0:
            hour, days = 0, 1
        elif hour == 23 and minute == 59 and second == 60:
            second = 59
        try:
            date = LocalDate.of(year, month, day)
            local = LocalDateTime(date, LocalTime.of(hour, minute, second, 0))
            epoch = local.toEpochSecond(ZoneOffset.UTC) + days * 86400 - offset
        except Exception:
            return ~pos
        r = cc.set_field(ChronoField.INSTANT_SECONDS, epoch, pos, p)
        if r < 0:
            return r
        return cc.set_field(ChronoField.NANO_OF_SECOND, nano, pos, r)

    def __str__(self):
        return "ParseCaseSensitive(false)" if False else "Instant()"


_LOCALIZED_DATE = {"FULL": "EEEE, MMMM d, y", "LONG": "MMMM d, y", "MEDIUM": "MMM d, y", "SHORT": "M/d/yy"}
_LOCALIZED_TIME = {"FULL": "h:mm:ss a zzzz", "LONG": "h:mm:ss a z", "MEDIUM": "h:mm:ss a", "SHORT": "h:mm a"}
_LOCALIZED_JOIN = {"FULL": "{1}, {0}", "LONG": "{1}, {0}", "MEDIUM": "{1}, {0}", "SHORT": "{1}, {0}"}


def localized_pattern(date_style, time_style):
    if date_style is not None and time_style is not None:
        join = _LOCALIZED_JOIN[date_style.name()]
        return join.replace("{1}", _LOCALIZED_DATE[date_style.name()]).replace("{0}", _LOCALIZED_TIME[time_style.name()])
    if date_style is not None:
        return _LOCALIZED_DATE[date_style.name()]
    return _LOCALIZED_TIME[time_style.name()]


class Localized:
    def __init__(self, date_style, time_style):
        self.date_style, self.time_style = date_style, time_style

    def _formatter(self):
        return DateTimeFormatterBuilder().appendPattern(localized_pattern(self.date_style, self.time_style)).toFormatter()

    def format(self, pc, out):
        return self._formatter()._printer.format(pc, out)

    def parse(self, cc, text, pos):
        return self._formatter()._printer.parse(cc, text, pos)

    def __str__(self):
        return "Localized(%s,%s)" % (self.date_style.name() if self.date_style else "", self.time_style.name() if self.time_style else "")


class ChronologyId:
    def format(self, pc, out):
        out.append("ISO")
        return True

    def parse(self, cc, text, pos):
        for name in ("ISO", "Minguo", "ThaiBuddhist", "Japanese", "Hijrah-umalqura"):
            if cc.starts(pos, name):
                return pos + len(name)
        return ~pos

    def __str__(self):
        return "ChronologyId(Chronology)"


class Pad:
    def __init__(self, element, width, char):
        self.element, self.width, self.char = element, width, char

    def format(self, pc, out):
        mark = len(out)
        buf = []
        if not self.element.format(pc, buf):
            return False
        text = "".join(buf)
        if len(text) > self.width:
            _dt_error("Cannot print as output of %d characters exceeds pad width of %d" % (len(text), self.width))
        out.append(self.char * (self.width - len(text)) + text)
        return True

    def parse(self, cc, text, pos):
        strict = cc.strict
        if pos > len(text):
            raise IndexError
        if pos == len(text):
            return ~pos
        end = pos + self.width
        if end > len(text):
            if strict:
                return ~pos
            end = len(text)
        p = pos
        while p < end and text[p] == self.char:
            p += 1
        result = self.element.parse(cc, text[:end], p)
        if result != end and strict:
            return ~(pos + p)
        return result

    def __str__(self):
        return "Pad(%s,%d%s" % (self.element, self.width, ")" if self.char == " " else ",'%s')" % self.char)


class Composite:
    def __init__(self, elements, optional=False):
        self.elements, self.optional = elements, optional

    def with_optional(self, optional):
        return self if optional == self.optional else Composite(self.elements, optional)

    def format(self, pc, out):
        mark = len(out)
        if self.optional:
            pc.optional += 1
        try:
            for element in self.elements:
                if not element.format(pc, out):
                    del out[mark:]
                    return True
        finally:
            if self.optional:
                pc.optional -= 1
        return True

    def parse(self, cc, text, pos):
        if self.optional:
            cc.start_optional()
            p = pos
            for element in self.elements:
                p = element.parse(cc, text, p)
                if p < 0:
                    cc.end_optional(False)
                    return pos
            cc.end_optional(True)
            return p
        p = pos
        for element in self.elements:
            p = element.parse(cc, text, p)
            if p < 0:
                return p
        return p

    def __str__(self):
        if not self.elements:
            return "[]" if self.optional else "()"
        return ("[" if self.optional else "(") + "".join(str(e) for e in self.elements) + ("]" if self.optional else ")")


def _field(name):
    return getattr(ChronoField, name)


_PATTERN_FIELDS = {
    "G": "ERA", "y": "YEAR_OF_ERA", "u": "YEAR", "Q": QUARTER, "q": QUARTER, "M": "MONTH_OF_YEAR", "L": "MONTH_OF_YEAR",
    "D": "DAY_OF_YEAR", "d": "DAY_OF_MONTH", "F": "ALIGNED_WEEK_OF_MONTH", "E": "DAY_OF_WEEK", "a": "AMPM_OF_DAY",
    "H": "HOUR_OF_DAY", "k": "CLOCK_HOUR_OF_DAY", "K": "HOUR_OF_AMPM", "h": "CLOCK_HOUR_OF_AMPM", "m": "MINUTE_OF_HOUR",
    "s": "SECOND_OF_MINUTE", "S": "NANO_OF_SECOND", "A": "MILLI_OF_DAY", "n": "NANO_OF_SECOND", "N": "NANO_OF_DAY",
}


def _pf(letter):
    f = _PATTERN_FIELDS[letter]
    return f if isinstance(f, PseudoField) else _field(f)


@host_class("java.time.format.DateTimeFormatterBuilder", final=True)
class DateTimeFormatterBuilder(Object):
    def __init__(self, parent=None, optional=False):
        self._parent, self._optional = parent, optional
        self._elements = []
        self._pad_next_width = 0
        self._pad_next_char = " "
        self._value_index = -1
        self._active = self

    @jmethod("<init>", "()V")
    def _init(self):
        DateTimeFormatterBuilder.__init__(self)

    @staticmethod
    def getLocalizedDateTimePattern(date_style, time_style=None, chrono=None, locale=None):
        if isinstance(date_style, FormatStyle.__mro__[0]) is False:
            pass
        if date_style is None and time_style is None:
            runtime.throw_new("java.lang.IllegalArgumentException", "Either dateStyle or timeStyle must be non-null")
        return jstr(localized_pattern(date_style, time_style))

    # settings

    def parseCaseSensitive(self):
        self._append_internal(Settings(0))
        return self

    def parseCaseInsensitive(self):
        self._append_internal(Settings(1))
        return self

    def parseStrict(self):
        self._append_internal(Settings(2))
        return self

    def parseLenient(self):
        self._append_internal(Settings(3))
        return self

    def parseDefaulting(self, field, value):
        check_nonnull(field)
        self._append_internal(Defaulting(field, value))
        return self

    def _a(self):
        return self._active

    # values

    def appendValue(self, field, width=None, max_width=None, sign=None):
        if field is None:
            runtime.throw_new("java.lang.NullPointerException", "field")
        if width is None:
            self._append_value(Number(field, 1, 19, SignStyle.NORMAL))
        elif max_width is None:
            if width < 1 or width > 19:
                runtime.throw_new("java.lang.IllegalArgumentException", "The width must be from 1 to 19 inclusive but was %d" % width)
            self._append_value(Number(field, width, width, SignStyle.NOT_NEGATIVE))
        else:
            check_nonnull(sign)
            if width == max_width and sign is SignStyle.NOT_NEGATIVE:
                return self.appendValue(field, max_width)
            if width < 1 or width > 19:
                runtime.throw_new("java.lang.IllegalArgumentException", "The minimum width must be from 1 to 19 inclusive but was %d" % width)
            if max_width < 1 or max_width > 19:
                runtime.throw_new("java.lang.IllegalArgumentException", "The maximum width must be from 1 to 19 inclusive but was %d" % max_width)
            if max_width < width:
                runtime.throw_new("java.lang.IllegalArgumentException", "The maximum width must exceed or equal the minimum width but %d < %d" % (max_width, width))
            self._append_value(Number(field, width, max_width, sign))
        return self

    def appendValueReduced(self, field, width, max_width, base):
        check_nonnull(field)
        if width < 1 or width > 10:
            runtime.throw_new("java.lang.IllegalArgumentException", "The minWidth must be from 1 to 10 inclusive but was %d" % width)
        if max_width < 1 or max_width > 10:
            runtime.throw_new("java.lang.IllegalArgumentException", "The maxWidth must be from 1 to 10 inclusive but was %d" % max_width)
        if max_width < width:
            runtime.throw_new("java.lang.IllegalArgumentException", "The maxWidth must exceed or equal the minWidth but %d < %d" % (max_width, width))
        if isinstance(base, int):
            self._append_value(Reduced(field, width, max_width, base))
        else:
            self._append_value(Reduced(field, width, max_width, 0, base))
        return self

    def _append_value(self, element):
        a = self._active
        if a._value_index >= 0:
            index = a._value_index
            base = a._elements[index]
            if element.min == element.max and element.sign is SignStyle.NOT_NEGATIVE and \
                    not (isinstance(element, Reduced) and False):
                base = base.with_subsequent(element.max)
                self._append_internal(element.with_fixed())
                a._value_index = index
            else:
                base = base.with_fixed()
                a._value_index = self._append_internal(element)
            a._elements[index] = base
        else:
            a._value_index = self._append_internal(element)

    def appendFraction(self, field, min_width, max_width, decimal_point):
        check_nonnull(field)
        if min_width < 0 or min_width > 9:
            runtime.throw_new("java.lang.IllegalArgumentException", "Minimum width must be from 0 to 9 inclusive but was %d" % min_width)
        if max_width < 1 or max_width > 9:
            runtime.throw_new("java.lang.IllegalArgumentException", "Maximum width must be from 1 to 9 inclusive but was %d" % max_width)
        if max_width < min_width:
            runtime.throw_new("java.lang.IllegalArgumentException", "Maximum width must exceed or equal the minimum width but %d < %d" % (max_width, min_width))
        element = Fraction(field, min_width, max_width, bool(decimal_point))
        if min_width == max_width and not decimal_point:
            self._append_fraction_value(element)
        else:
            self._append_internal(element)
        return self

    def _append_fraction_value(self, element):
        # a fraction without a decimal point of fixed width takes part in adjacent value parsing
        number = _FractionAsNumber(element)
        self._append_value(number)

    # text

    def appendText(self, field, style_or_map=None):
        check_nonnull(field)
        if style_or_map is None:
            style_or_map = TextStyle.FULL
        if isinstance(style_or_map, _EnumBase):
            self._append_internal(Text(field, style_or_map))
        else:
            custom = {}
            for entry in iterate(style_or_map.entrySet()):
                key = entry.getKey()
                custom[getattr(key, "value", key)] = entry.getValue()
            self._append_internal(Text(field, TextStyle.FULL, custom))
        return self

    # literals

    def appendLiteral(self, text):
        check_nonnull(text)
        if isinstance(text, int):
            text = chr(text)
        if len(text) > 0:
            self._append_internal(Literal(text))
        return self

    def appendOffsetId(self):
        self._append_internal(Offset("+HH:MM:ss", "Z"))
        return self

    def appendOffset(self, pattern, no_offset_text):
        check_nonnull(pattern)
        check_nonnull(no_offset_text)
        self._append_internal(Offset(pattern, no_offset_text))
        return self

    def appendLocalizedOffset(self, style):
        check_nonnull(style)
        if style is not TextStyle.FULL and style is not TextStyle.SHORT:
            runtime.throw_new("java.lang.IllegalArgumentException", "Style must be either full or short")
        self._append_internal(LocalizedOffset(style))
        return self

    def appendZoneId(self):
        self._append_internal(ZoneIdElement())
        return self

    def appendZoneRegionId(self):
        self._append_internal(ZoneIdElement(True))
        return self

    def appendZoneOrOffsetId(self):
        self._append_internal(ZoneIdElement())
        return self

    def appendZoneText(self, style, preferred=None):
        self._append_internal(ZoneIdElement(False, check_nonnull(style)))
        return self

    def appendGenericZoneText(self, style, preferred=None):
        self._append_internal(ZoneIdElement(False, check_nonnull(style)))
        return self

    def appendInstant(self, digits=-2):
        if digits < -2 or digits > 9:
            runtime.throw_new("java.lang.IllegalArgumentException", "The fractional digits must be from -1 to 9 inclusive but was %d" % digits)
        self._append_internal(InstantElement(digits))
        return self

    def appendChronologyId(self):
        self._append_internal(ChronologyId())
        return self

    def appendChronologyText(self, style):
        self._append_internal(ChronologyId())
        return self

    def appendLocalized(self, date_style, time_style):
        if date_style is None and time_style is None:
            runtime.throw_new("java.lang.IllegalArgumentException", "Either the date or time style must be non-null")
        self._append_internal(Localized(date_style, time_style))
        return self

    def append(self, formatter):
        check_nonnull(formatter)
        self._append_internal(formatter._printer.with_optional(False))
        return self

    def appendOptional(self, formatter):
        check_nonnull(formatter)
        self._append_internal(formatter._printer.with_optional(True))
        return self

    def appendPattern(self, pattern):
        check_nonnull(pattern)
        self._parse_pattern(pattern)
        return self

    def padNext(self, width, char=" "):
        if isinstance(char, int):
            char = chr(char)
        if width < 1:
            runtime.throw_new("java.lang.IllegalArgumentException", "The pad width must be at least one but was %d" % width)
        self._active._pad_next_width = width
        self._active._pad_next_char = char
        self._active._value_index = -1
        return self

    def optionalStart(self):
        self._active._value_index = -1
        child = DateTimeFormatterBuilder(self._active, True)
        self._active = child
        return self

    def optionalEnd(self):
        if self._active._parent is None:
            runtime.throw_new("java.lang.IllegalStateException", "Cannot call optionalEnd() as there was no previous call to optionalStart()")
        if self._active._elements:
            composite = Composite(self._active._elements, self._active._optional)
            self._active = self._active._parent
            self._append_internal(composite)
        else:
            self._active = self._active._parent
        return self

    def _append_internal(self, element):
        a = self._active
        if a._pad_next_width > 0:
            if element is not None:
                element = Pad(element, a._pad_next_width, a._pad_next_char)
            a._pad_next_width = 0
            a._pad_next_char = " "
        a._elements.append(element)
        a._value_index = -1
        return len(a._elements) - 1

    def toFormatter(self, locale=None):
        return self._to_formatter(ResolverStyle.SMART)

    def _to_formatter(self, resolver, chrono=None):
        while self._active._parent is not None:
            self.optionalEnd()
        composite = Composite(self._elements, False)
        return DateTimeFormatter(composite, resolver, chrono)

    def toString(self):
        return jstr(str(Composite(self._elements, self._optional)))

    # pattern

    def _parse_pattern(self, pattern):
        pos = 0
        n = len(pattern)
        while pos < n:
            cur = pattern[pos]
            if ("A" <= cur <= "Z") or ("a" <= cur <= "z"):
                start = pos
                pos += 1
                while pos < n and pattern[pos] == cur:
                    pos += 1
                count = pos - start
                if cur == "p":
                    pad = 0
                    if pos < n:
                        cur = pattern[pos]
                        if ("A" <= cur <= "Z") or ("a" <= cur <= "z"):
                            pad = count
                            start = pos
                            pos += 1
                            while pos < n and pattern[pos] == cur:
                                pos += 1
                            count = pos - start
                    if pad == 0:
                        runtime.throw_new("java.lang.IllegalArgumentException", "Pad letter 'p' must be followed by valid pad pattern: " + pattern)
                    self.padNext(pad)
                self._letter(cur, count, pattern)
                pos -= 1
            elif cur == "'":
                start = pos
                pos += 1
                while pos < n:
                    if pattern[pos] == "'":
                        if pos + 1 < n and pattern[pos + 1] == "'":
                            pos += 1
                        else:
                            break
                    pos += 1
                if pos >= n:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Pattern ends with an incomplete string literal: " + pattern)
                text = pattern[start + 1:pos]
                if not text:
                    self.appendLiteral("'")
                else:
                    self.appendLiteral(text.replace("''", "'"))
            elif cur == "[":
                self.optionalStart()
            elif cur == "]":
                if self._active._parent is None:
                    runtime.throw_new("java.lang.IllegalArgumentException", "Pattern invalid as it contains ] without previous [")
                self.optionalEnd()
            elif cur in "{}#":
                runtime.throw_new("java.lang.IllegalArgumentException", "Pattern includes reserved character: '%s'" % cur)
            else:
                self.appendLiteral(cur)
            pos += 1

    def _letter(self, cur, count, pattern):
        def too_many():
            runtime.throw_new("java.lang.IllegalArgumentException", "Too many pattern letters: " + cur)
        if cur in "uy":
            if count == 2:
                self.appendValueReduced(_pf(cur), 2, 2, LocalDate.of(2000, 1, 1))
            elif count < 4:
                self.appendValue(_pf(cur), count, 19, SignStyle.NORMAL)
            else:
                self.appendValue(_pf(cur), count, 19, SignStyle.EXCEEDS_PAD)
        elif cur in "GEeccQqMLaB" or cur == "c":
            self._text_letter(cur, count)
        elif cur in "dhHKkms":
            if count == 1:
                self.appendValue(_pf(cur))
            elif count == 2:
                self.appendValue(_pf(cur), count)
            else:
                too_many()
        elif cur == "D":
            if count == 1:
                self.appendValue(_pf(cur))
            elif count in (2, 3):
                self.appendValue(_pf(cur), count, 3, SignStyle.NOT_NEGATIVE)
            else:
                too_many()
        elif cur == "F":
            if count == 1:
                self.appendValue(_pf(cur))
            else:
                too_many()
        elif cur == "S":
            self.appendFraction(ChronoField.NANO_OF_SECOND, count, count, False)
        elif cur == "A" or cur == "n" or cur == "N":
            self.appendValue(_pf(cur), count, 19, SignStyle.NOT_NEGATIVE)
        elif cur == "V":
            if count != 2:
                runtime.throw_new("java.lang.IllegalArgumentException", "Pattern letter count must be 2: " + cur)
            self.appendZoneId()
        elif cur == "v":
            if count == 1:
                self.appendGenericZoneText(TextStyle.SHORT)
            elif count == 4:
                self.appendGenericZoneText(TextStyle.FULL)
            else:
                runtime.throw_new("java.lang.IllegalArgumentException", "Wrong number of pattern letters: " + cur)
        elif cur == "z":
            if count > 4:
                too_many()
            self.appendZoneText(TextStyle.FULL if count == 4 else TextStyle.SHORT)
        elif cur == "O":
            if count == 1:
                self.appendLocalizedOffset(TextStyle.SHORT)
            elif count == 4:
                self.appendLocalizedOffset(TextStyle.FULL)
            else:
                runtime.throw_new("java.lang.IllegalArgumentException", "Pattern letter count must be 1 or 4: " + cur)
        elif cur == "X":
            if count > 5:
                too_many()
            self.appendOffset(_OFFSET_PATTERNS[count + (0 if count == 1 else 1)], "Z")
        elif cur == "x":
            if count > 5:
                too_many()
            zero = "+00" if count == 1 else ("+00:00" if count % 2 == 0 and False else "+0000" if count % 2 == 0 else "+00:00")
            if count == 1:
                zero = "+00"
            elif count in (2, 4):
                zero = "+0000"
            else:
                zero = "+00:00"
            self.appendOffset(_OFFSET_PATTERNS[count + (0 if count == 1 else 1)], zero)
        elif cur == "Z":
            if count < 4:
                self.appendOffset("+HHMM", "+0000")
            elif count == 4:
                self.appendLocalizedOffset(TextStyle.FULL)
            elif count == 5:
                self.appendOffset("+HH:MM:ss", "Z")
            else:
                too_many()
        else:
            runtime.throw_new("java.lang.IllegalArgumentException", "Unknown pattern letter: " + cur)

    def _text_letter(self, cur, count):
        def too_many():
            runtime.throw_new("java.lang.IllegalArgumentException", "Too many pattern letters: " + cur)
        if cur == "G":
            if count > 5:
                too_many()
            self.appendText(_field("ERA"), (TextStyle.SHORT, TextStyle.SHORT, TextStyle.SHORT, TextStyle.FULL, TextStyle.NARROW)[count - 1])
        elif cur == "a":
            if count != 1:
                too_many()
            self.appendText(_field("AMPM_OF_DAY"), TextStyle.SHORT)
        elif cur in "ML":
            if count == 1:
                self.appendValue(_field("MONTH_OF_YEAR"))
            elif count == 2:
                self.appendValue(_field("MONTH_OF_YEAR"), 2)
            elif count == 3:
                self.appendText(_field("MONTH_OF_YEAR"), TextStyle.SHORT)
            elif count == 4:
                self.appendText(_field("MONTH_OF_YEAR"), TextStyle.FULL)
            elif count == 5:
                self.appendText(_field("MONTH_OF_YEAR"), TextStyle.NARROW)
            else:
                too_many()
        elif cur in "Qq":
            if count == 1:
                self.appendValue(QUARTER)
            elif count == 2:
                self.appendValue(QUARTER, 2)
            elif count == 3:
                self.appendText(QUARTER, TextStyle.SHORT)
            elif count == 4:
                self.appendText(QUARTER, TextStyle.FULL)
            elif count == 5:
                self.appendText(QUARTER, TextStyle.NARROW)
            else:
                too_many()
        elif cur in "Eec":
            if cur == "E":
                if count > 5:
                    too_many()
                self.appendText(_field("DAY_OF_WEEK"), (TextStyle.SHORT, TextStyle.SHORT, TextStyle.SHORT, TextStyle.FULL, TextStyle.NARROW)[count - 1])
            elif count == 1:
                self.appendValue(LOCAL_DAY_OF_WEEK)
            elif count == 2 and cur == "c":
                self.appendValue(LOCAL_DAY_OF_WEEK)
            elif count == 2:
                self.appendValue(LOCAL_DAY_OF_WEEK, 2)
            elif count > 5:
                too_many()
            else:
                self.appendText(_field("DAY_OF_WEEK"), (TextStyle.SHORT, TextStyle.SHORT, TextStyle.SHORT, TextStyle.FULL, TextStyle.NARROW)[count - 1])
        else:
            runtime.throw_new("java.lang.IllegalArgumentException", "Unknown pattern letter: " + cur)


_EnumBase = lookup_host("java.time.format.TextStyle").py.__mro__[1]


class _FractionAsNumber(Number):
    """a fraction of fixed width without a decimal point, adjacent to other values"""

    def __init__(self, fraction, subsequent=0):
        Number.__init__(self, fraction.field, fraction.min, fraction.max, SignStyle.NOT_NEGATIVE, subsequent)
        self.fraction = fraction

    def with_fixed(self):
        return _FractionAsNumber(self.fraction, -1) if self.subsequent != -1 else self

    def with_subsequent(self, width):
        return _FractionAsNumber(self.fraction, self.subsequent + width)

    def format(self, pc, out):
        return self.fraction.format(pc, out)

    def parse(self, cc, text, pos):
        width = self.max
        if self.subsequent > 0:
            pass
        length = len(text)
        end = pos + width
        if end > length:
            return ~pos
        digits = text[pos:end]
        if not digits.isdigit():
            return ~pos
        return self.fraction.parse(cc, text[:end], pos)

    def __str__(self):
        return str(self.fraction)


class Parsed(Object):
    """the fields found by a parse, resolved to a date and a time where the fields allow it"""

    def __init__(self, fields, zone):
        self.fields = dict(fields)
        self.zone = zone
        self.date = None
        self.time = None
        self.excess_days = 0
        self._text = ""

    def isSupported(self, field):
        if field is None:
            return 0
        name = getattr(field, "_name", None)
        if name is None:
            return 0
        if name in self.fields:
            return 1
        return 1 if Adapter(self).get(name) is not None else 0

    def getLong(self, field):
        name = field_name(field)
        value = Adapter(self).get(name)
        if value is None:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field_text(field))
        return value

    def get(self, field):
        value = self.getLong(field)
        if not -(1 << 31) <= value < (1 << 31):
            _dt_error("Invalid value for %s: %d" % (field_text(field), value))
        return value

    def query(self, query):
        return query.queryFrom(self)

    def toString(self):
        fields = "{" + ", ".join("%s=%d" % (_field_title(k), v) for k, v in self.fields.items()) + "}"
        text = "%s,%s" % (fields, lookup_host("java.time.chrono.IsoChronology").py.INSTANCE.toString())
        if self.zone is not None:
            text += "," + self.zone.toString()
        if self.date is not None or self.time is not None:
            text += " resolved to "
            if self.date is not None:
                text += self.date.toString()
                if self.time is not None:
                    text += "T" + self.time.toString()
            else:
                text += self.time.toString()
        return jstr(text)


host_class("java.time.format.Parsed", final=True, interfaces=("java.time.temporal.TemporalAccessor",))(Parsed)


def _strictly(style):
    return style is ResolverStyle.STRICT


def _merge(fields, name, value, style):
    old = fields.get(name)
    if old is not None and old != value:
        _dt_error("Conflict found: %s %d differs from %s %d while resolving  %s" % (
            _field_title(name), old, _field_title(name), value, name))
    fields[name] = value


def _field_title(name):
    from .jtimeapi import _camel
    return _camel(name)


def _valid(name, value, style):
    if style is not ResolverStyle.LENIENT:
        _field(name).checkValidValue(value)
    return value


def resolve(parsed, style):
    f = parsed.fields
    # instant to the date and time of the zone
    if "INSTANT_SECONDS" in f and (parsed.zone is not None or "OFFSET_SECONDS" in f):
        zone = parsed.zone if parsed.zone is not None else ZoneOffset.ofTotalSeconds(f["OFFSET_SECONDS"])
        instant = Instant(f["INSTANT_SECONDS"], f.get("NANO_OF_SECOND", 0))
        z = ZonedDateTime.ofInstant(instant, zone)
        _resolve_set(f, "EPOCH_DAY", z._local._date.toEpochDay())
        _resolve_set(f, "NANO_OF_DAY", z._local._time.toNanoOfDay())
        if "OFFSET_SECONDS" not in f and isinstance(zone, ZoneOffset):
            f["OFFSET_SECONDS"] = zone._seconds
    _resolve_date(parsed, style)
    _resolve_time(parsed, style)
    if parsed.date is not None and parsed.excess_days:
        parsed.date = parsed.date.plusDays(parsed.excess_days)
        parsed.excess_days = 0
    # fields that the date and time hold must agree with them
    if parsed.date is not None or parsed.time is not None:
        adapter = Adapter(parsed)
        adapter.extra = {}
        for name in list(f):
            if name in ("INSTANT_SECONDS", "OFFSET_SECONDS"):
                continue
            actual = adapter.get(name)
            if actual is not None and actual != f[name]:
                _dt_error("Conflict found: Field %s %d differs from %s %d derived from %s" % (
                    _field_title(name), actual, _field_title(name), f[name],
                    (parsed.date.toString() if parsed.date is not None else parsed.time.toString())))
            if actual is not None:
                del f[name]
    if parsed.date is not None and parsed.time is not None and "INSTANT_SECONDS" not in f:
        local = LocalDateTime(parsed.date, parsed.time)
        if "OFFSET_SECONDS" in f:
            f["INSTANT_SECONDS"] = local.toEpochSecond(ZoneOffset.ofTotalSeconds(f["OFFSET_SECONDS"]))
        elif parsed.zone is not None:
            f["INSTANT_SECONDS"] = ZonedDateTime.of(local, parsed.zone).toEpochSecond()


def _resolve_set(f, name, value):
    if name in f and f[name] != value:
        _dt_error("Conflict found: %s %d differs from %s %d while resolving  %s" % (
            _field_title(name), f[name], _field_title(name), value, name))
    f[name] = value


def _resolve_date(parsed, style):
    f = parsed.fields
    if "EPOCH_DAY" in f:
        parsed.date = LocalDate.ofEpochDay(f.pop("EPOCH_DAY"))
        return
    if "PROLEPTIC_MONTH" in f:
        pm = f.pop("PROLEPTIC_MONTH")
        _valid("PROLEPTIC_MONTH", pm, style)
        _merge(f, "MONTH_OF_YEAR", pm % 12 + 1, style)
        _merge(f, "YEAR", pm // 12, style)
    if "YEAR_OF_ERA" in f:
        yoe = f.pop("YEAR_OF_ERA")
        _valid("YEAR_OF_ERA", yoe, style)
        era = f.pop("ERA", None)
        year = f.get("YEAR")
        if era is None:
            if style is ResolverStyle.STRICT:
                if year is not None:
                    _merge(f, "YEAR", yoe if year > 0 else 1 - yoe, style)
                else:
                    f["YEAR_OF_ERA"] = yoe
            else:
                _merge(f, "YEAR", yoe if (year is None or year > 0) else 1 - yoe, style)
        elif era == 1:
            _merge(f, "YEAR", yoe, style)
        elif era == 0:
            _merge(f, "YEAR", 1 - yoe, style)
        else:
            _dt_error("Invalid value for era: %d" % era)
    elif "ERA" in f:
        _valid("ERA", f["ERA"], style)
    if "YEAR" not in f:
        return
    year = f["YEAR"]
    if "MONTH_OF_YEAR" in f:
        if "DAY_OF_MONTH" in f:
            moy, dom = f.pop("MONTH_OF_YEAR"), f.pop("DAY_OF_MONTH")
            year = f.pop("YEAR")
            if style is ResolverStyle.LENIENT:
                parsed.date = LocalDate.of(year, 1, 1).plusMonths(moy - 1).plusDays(dom - 1)
                return
            _valid("YEAR", year, style)
            _valid("MONTH_OF_YEAR", moy, style)
            _valid("DAY_OF_MONTH", dom, style)
            if style is ResolverStyle.SMART:
                if moy in (4, 6, 9, 11):
                    dom = min(dom, 30)
                elif moy == 2:
                    dom = min(dom, 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28)
            parsed.date = LocalDate.of(year, moy, dom)
            return
        if "ALIGNED_WEEK_OF_MONTH" in f and "ALIGNED_DAY_OF_WEEK_IN_MONTH" in f:
            moy = f.pop("MONTH_OF_YEAR")
            aw, ad = f.pop("ALIGNED_WEEK_OF_MONTH"), f.pop("ALIGNED_DAY_OF_WEEK_IN_MONTH")
            year = f.pop("YEAR")
            _valid("ALIGNED_WEEK_OF_MONTH", aw, style)
            _valid("ALIGNED_DAY_OF_WEEK_IN_MONTH", ad, style)
            parsed.date = LocalDate.of(year, moy, 1).plusDays((aw - 1) * 7 + (ad - 1))
            return
    if "DAY_OF_YEAR" in f:
        doy = f.pop("DAY_OF_YEAR")
        year = f.pop("YEAR")
        if style is ResolverStyle.LENIENT:
            parsed.date = LocalDate.ofYearDay(year, 1).plusDays(doy - 1)
        else:
            _valid("DAY_OF_YEAR", doy, style)
            if doy == 366 and not (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)):
                _dt_error("Invalid date 'DayOfYear 366' as '%d' is not a leap year" % year)
            parsed.date = LocalDate.ofYearDay(year, doy)
        return
    if "ALIGNED_WEEK_OF_YEAR" in f and "ALIGNED_DAY_OF_WEEK_IN_YEAR" in f:
        aw, ad = f.pop("ALIGNED_WEEK_OF_YEAR"), f.pop("ALIGNED_DAY_OF_WEEK_IN_YEAR")
        year = f.pop("YEAR")
        parsed.date = LocalDate.ofYearDay(year, 1).plusDays((aw - 1) * 7 + (ad - 1))


def _resolve_time(parsed, style):
    f = parsed.fields
    if "CLOCK_HOUR_OF_DAY" in f:
        ch = f.pop("CLOCK_HOUR_OF_DAY")
        if style is not ResolverStyle.LENIENT:
            _valid("CLOCK_HOUR_OF_DAY", ch, style)
        _merge(f, "HOUR_OF_DAY", 0 if ch == 24 else ch, style)
    if "CLOCK_HOUR_OF_AMPM" in f:
        ch = f.pop("CLOCK_HOUR_OF_AMPM")
        if style is not ResolverStyle.LENIENT:
            _valid("CLOCK_HOUR_OF_AMPM", ch, style)
        _merge(f, "HOUR_OF_AMPM", 0 if ch == 12 else ch, style)
    if "AMPM_OF_DAY" in f and "HOUR_OF_AMPM" in f:
        ap, hap = f.pop("AMPM_OF_DAY"), f.pop("HOUR_OF_AMPM")
        if style is not ResolverStyle.LENIENT:
            _valid("AMPM_OF_DAY", ap, style)
            _valid("HOUR_OF_AMPM", hap, style)
        _merge(f, "HOUR_OF_DAY", ap * 12 + hap, style)
    if "NANO_OF_DAY" in f:
        nod = f.pop("NANO_OF_DAY")
        if style is not ResolverStyle.LENIENT:
            _valid("NANO_OF_DAY", nod, style)
        _merge(f, "HOUR_OF_DAY", nod // 3600000000000, style)
        _merge(f, "MINUTE_OF_HOUR", nod // 60000000000 % 60, style)
        _merge(f, "SECOND_OF_MINUTE", nod // 1000000000 % 60, style)
        _merge(f, "NANO_OF_SECOND", nod % 1000000000, style)
    if "MICRO_OF_DAY" in f:
        v = f.pop("MICRO_OF_DAY")
        _valid("MICRO_OF_DAY", v, style)
        _merge(f, "SECOND_OF_DAY", v // 1000000, style)
        _merge(f, "MICRO_OF_SECOND", v % 1000000, style)
    if "MILLI_OF_DAY" in f:
        v = f.pop("MILLI_OF_DAY")
        _valid("MILLI_OF_DAY", v, style)
        _merge(f, "SECOND_OF_DAY", v // 1000, style)
        _merge(f, "MILLI_OF_SECOND", v % 1000, style)
    if "SECOND_OF_DAY" in f:
        v = f.pop("SECOND_OF_DAY")
        _valid("SECOND_OF_DAY", v, style)
        _merge(f, "HOUR_OF_DAY", v // 3600, style)
        _merge(f, "MINUTE_OF_HOUR", v // 60 % 60, style)
        _merge(f, "SECOND_OF_MINUTE", v % 60, style)
    if "MINUTE_OF_DAY" in f:
        v = f.pop("MINUTE_OF_DAY")
        _valid("MINUTE_OF_DAY", v, style)
        _merge(f, "HOUR_OF_DAY", v // 60, style)
        _merge(f, "MINUTE_OF_HOUR", v % 60, style)
    if "MILLI_OF_SECOND" in f and "MICRO_OF_SECOND" in f:
        ms = f.pop("MILLI_OF_SECOND")
        us = f.pop("MICRO_OF_SECOND")
        _merge(f, "MICRO_OF_SECOND", ms * 1000 + us % 1000, style)
    if "MICRO_OF_SECOND" in f and "NANO_OF_SECOND" not in f:
        f["NANO_OF_SECOND"] = f.pop("MICRO_OF_SECOND") * 1000
    elif "MILLI_OF_SECOND" in f and "NANO_OF_SECOND" not in f:
        f["NANO_OF_SECOND"] = f.pop("MILLI_OF_SECOND") * 1000000
    elif "NANO_OF_SECOND" in f:
        f.pop("MICRO_OF_SECOND", None)
        f.pop("MILLI_OF_SECOND", None)
    if "NANO_OF_SECOND" in f and "INSTANT_SECONDS" in f:
        f.setdefault("MICRO_OF_SECOND", f["NANO_OF_SECOND"] // 1000)
        f.setdefault("MILLI_OF_SECOND", f["NANO_OF_SECOND"] // 1000000)
    if "HOUR_OF_DAY" in f:
        hod = f["HOUR_OF_DAY"]
        moh, som, nos = f.get("MINUTE_OF_HOUR"), f.get("SECOND_OF_MINUTE"), f.get("NANO_OF_SECOND")
        if (moh is None and (som is not None or nos is not None)) or (moh is not None and som is None and nos is not None):
            return
        m, s, n = moh or 0, som or 0, nos or 0
        if style is ResolverStyle.LENIENT:
            total = hod * 3600 * 10 ** 9 + m * 60 * 10 ** 9 + s * 10 ** 9 + n
            parsed.excess_days = total // (86400 * 10 ** 9)
            parsed.time = LocalTime.ofNanoOfDay(total % (86400 * 10 ** 9))
        else:
            if style is ResolverStyle.SMART and hod == 24 and m == 0 and s == 0 and n == 0:
                hod = 0
                parsed.excess_days = 1
            _valid("HOUR_OF_DAY", hod, style)
            if moh is not None:
                _valid("MINUTE_OF_HOUR", m, style)
            if som is not None:
                _valid("SECOND_OF_MINUTE", s, style)
            if nos is not None:
                _valid("NANO_OF_SECOND", n, style)
            parsed.time = LocalTime.of(hod, m, s, n)
        for key in ("HOUR_OF_DAY", "MINUTE_OF_HOUR", "SECOND_OF_MINUTE", "NANO_OF_SECOND", "MICRO_OF_SECOND", "MILLI_OF_SECOND"):
            f.pop(key, None)


def _abbreviate(text):
    return text[:64] + "..." if len(text) > 64 else text


def _parse_exception(text, index, message, cause=None):
    cls = lookup_host("java.time.format.DateTimeParseException").py
    error = runtime.make_throwable(cls, message)
    error._parsed_string = text
    error._error_index = index
    if cause is not None:
        error._cause = cause
    return error


def _install_parse_exception():
    cls = lookup_host("java.time.format.DateTimeParseException").py
    cls.getParsedString = lambda self: getattr(self, "_parsed_string", "")
    cls.getErrorIndex = lambda self: getattr(self, "_error_index", 0)


_install_parse_exception()


@host_class("java.time.format.DateTimeFormatter", final=True)
class DateTimeFormatter(Object):
    def __init__(self, printer, resolver=ResolverStyle.SMART, chrono=None, zone=None, locale=None):
        self._printer = printer
        self._resolver = resolver
        self._chrono = chrono
        self._zone = zone
        self._locale = locale

    def _copy(self, **changes):
        c = DateTimeFormatter(self._printer, self._resolver, self._chrono, self._zone, self._locale)
        for key, value in changes.items():
            setattr(c, "_" + key, value)
        return c

    @staticmethod
    def ofPattern(pattern, locale=None):
        return DateTimeFormatterBuilder().appendPattern(check_nonnull(pattern)).toFormatter()

    @staticmethod
    def ofLocalizedDate(style):
        return DateTimeFormatterBuilder().appendLocalized(check_nonnull(style), None)._to_formatter(ResolverStyle.SMART)

    @staticmethod
    def ofLocalizedTime(style):
        return DateTimeFormatterBuilder().appendLocalized(None, check_nonnull(style))._to_formatter(ResolverStyle.SMART)

    @staticmethod
    def ofLocalizedDateTime(date_style, time_style=None):
        return DateTimeFormatterBuilder().appendLocalized(check_nonnull(date_style), check_nonnull(time_style if time_style is not None else date_style))._to_formatter(ResolverStyle.SMART)

    def withZone(self, zone):
        return self._copy(zone=zone)

    def withLocale(self, locale):
        return self._copy(locale=locale)

    def localizedBy(self, locale):
        return self._copy(locale=locale)

    def withResolverStyle(self, style):
        return self._copy(resolver=check_nonnull(style))

    def withChronology(self, chrono):
        return self._copy(chrono=chrono)

    def withDecimalStyle(self, style):
        return self

    def withResolverFields(self, *fields):
        return self

    def getZone(self):
        return self._zone

    def getLocale(self):
        return self._locale if self._locale is not None else lookup_host("java.util.Locale").py.getDefault()

    def getResolverStyle(self):
        return self._resolver

    def getChronology(self):
        if self._chrono is not None:
            return self._chrono
        return lookup_host("java.time.chrono.IsoChronology").py.INSTANCE

    def getDecimalStyle(self):
        return DecimalStyle.STANDARD

    def getResolverFields(self):
        return None

    def toString(self):
        text = str(self._printer)
        if text.startswith("(") and text.endswith(")"):
            text = text[1:-1]
        return jstr(text)

    # formatting

    def format(self, temporal):
        out = []
        self.formatTo(temporal, out)
        return jstr("".join(out))

    def formatTo(self, temporal, appendable):
        if temporal is None:
            runtime.throw_new("java.lang.NullPointerException", "temporal")
        check_nonnull(appendable)
        adapter = self._adapter_for(temporal)
        pc = PrintContext(adapter)
        pc.chrono = self._chrono if self._chrono is not None and hasattr(self._chrono, "era_table") else None
        out = []
        try:
            self._printer.format(pc, out)
        except Exception as error:
            if hasattr(error, "getMessage") or isinstance(error, runtime.JavaThrowable if hasattr(runtime, "JavaThrowable") else ()):
                raise
            raise
        text = "".join(out)
        if isinstance(appendable, list):
            appendable.append(text)
        else:
            appendable.append(jstr(text))

    def _adapter_for(self, temporal):
        adapter, _ = with_zone_override(temporal, self._zone)
        if self._chrono is not None and getattr(self._chrono, "convert_adapter", None) is not None:
            self._chrono.convert_adapter(adapter)
        return adapter

    # parsing

    def _raw_parse(self, text, pos, throw=True):
        cc = ParseContext(text)
        end = self._printer.parse(cc, text, pos)
        return cc, end

    def parseUnresolved(self, text, position):
        check_nonnull(text)
        cc = ParseContext(text)
        start = position.getIndex()
        try:
            end = self._printer.parse(cc, text, start)
        except IndexError:
            position.setErrorIndex(start)
            return None
        if end < 0:
            position.setErrorIndex(~end)
            return None
        position.setIndex(end)
        p = Parsed(cc.cur.fields, cc.cur.zone)
        p._text = text
        return p

    def _parse_resolved(self, text, query_name=None):
        text = str(text)
        cc = ParseContext(text)
        cc.chrono = self._chrono if self._chrono is not None and hasattr(self._chrono, "era_table") else None
        try:
            end = self._printer.parse(cc, text, 0)
        except IndexError:
            raise _parse_exception(text, 0, "Text '%s' could not be parsed at index 0" % _abbreviate(text))
        if end < 0:
            raise _parse_exception(text, ~end, "Text '%s' could not be parsed at index %d" % (_abbreviate(text), ~end))
        if end < len(text):
            raise _parse_exception(text, end, "Text '%s' could not be parsed, unparsed text found at index %d" % (_abbreviate(text), end))
        parsed = Parsed(cc.cur.fields, cc.cur.zone)
        if parsed.zone is None and self._zone is not None:
            parsed.zone = self._zone
        parsed._text = text
        try:
            resolve(parsed, self._resolver)
        except Exception as error:
            message = getattr(error, "getMessage", None)
            if message is not None and "DateTimeException" in type(error).__mro__[0].__name__ or True:
                try:
                    detail = error.getMessage()
                except Exception:
                    raise
                raise _parse_exception(text, 0, "Text '%s' could not be parsed: %s" % (_abbreviate(text), detail), error)
            raise
        return parsed

    def parse(self, text, second=None):
        check_nonnull(text)
        if second is None:
            return self._parse_resolved(text)
        if hasattr(second, "getIndex"):
            pos = second
            cc = ParseContext(str(text))
            try:
                end = self._printer.parse(cc, str(text), pos.getIndex())
            except IndexError:
                end = ~pos.getIndex()
            if end < 0:
                pos.setErrorIndex(~end)
                raise _parse_exception(str(text), ~end, "Text '%s' could not be parsed at index %d" % (_abbreviate(str(text)), ~end))
            parsed = Parsed(cc.cur.fields, cc.cur.zone)
            if parsed.zone is None and self._zone is not None:
                parsed.zone = self._zone
            try:
                resolve(parsed, self._resolver)
            except Exception as error:
                raise _parse_exception(str(text), pos.getIndex(), "Text '%s' could not be parsed: %s" % (_abbreviate(str(text)), error.getMessage()), error)
            pos.setIndex(end)
            return parsed
        parsed = self._parse_resolved(text)
        try:
            return second.queryFrom(parsed)
        except Exception as error:
            if hasattr(error, "getMessage") and "DateTimeException" in [c.__name__ for c in type(error).__mro__]:
                raise _parse_exception(str(text), 0, "Text '%s' could not be parsed: %s" % (_abbreviate(str(text)), error.getMessage()), error)
            raise

    def parseBest(self, text, *queries):
        check_nonnull(text)
        if len(queries) == 1 and not hasattr(queries[0], "queryFrom"):
            queries = tuple(queries[0])
        if len(queries) < 2:
            runtime.throw_new("java.lang.IllegalArgumentException", "At least two queries must be specified")
        parsed = self._parse_resolved(text)
        for query in queries:
            try:
                return query.queryFrom(parsed)
            except Exception as error:
                if "DateTimeException" in [c.__name__ for c in type(error).__mro__]:
                    continue
                raise
        raise _parse_exception(str(text), 0, "Text '%s' could not be parsed: Unable to convert parsed text using any of the specified queries" % _abbreviate(str(text)))

    def _parse_to(self, text, kind):
        parsed = self._parse_resolved(text)
        try:
            return convert(parsed, kind)
        except Exception as error:
            if "DateTimeException" in [c.__name__ for c in type(error).__mro__]:
                raise _parse_exception(str(text), 0, "Text '%s' could not be parsed: %s" % (_abbreviate(str(text)), error.getMessage()), error)
            raise

    def toFormat(self, parse_query=None):
        runtime.throw_new("java.lang.UnsupportedOperationException", "java.text.Format is not supported for DateTimeFormatter")

    def equals(self, other):
        return 1 if self is other else 0

    def hashCode(self):
        return id(self) & 0x7FFFFFFF


def _no(name, temporal):
    _dt_error("Unable to obtain %s from TemporalAccessor: %s of type %s" % (name, temporal.toString(), runtime.class_of(temporal).getName()))


def to_date(t):
    if isinstance(t, LocalDate):
        return t
    if isinstance(t, Parsed):
        if t.date is not None:
            return t.date
        _no("LocalDate", t)
    if hasattr(t, "toLocalDate"):
        return t.toLocalDate()
    _no("LocalDate", t)


def to_time(t):
    if isinstance(t, LocalTime):
        return t
    if isinstance(t, Parsed):
        if t.time is not None:
            return t.time
        _no("LocalTime", t)
    if hasattr(t, "toLocalTime"):
        return t.toLocalTime()
    _no("LocalTime", t)


def to_datetime(t):
    if isinstance(t, LocalDateTime):
        return t
    if isinstance(t, Parsed):
        if t.date is not None and t.time is not None:
            return LocalDateTime(t.date, t.time)
        _no("LocalDateTime", t)
    if hasattr(t, "toLocalDateTime"):
        return t.toLocalDateTime()
    _no("LocalDateTime", t)


def _zone_of_parsed(t):
    if t.zone is not None:
        return t.zone
    if "OFFSET_SECONDS" in t.fields:
        return ZoneOffset.ofTotalSeconds(t.fields["OFFSET_SECONDS"])
    return None


def to_zoned(t):
    if isinstance(t, ZonedDateTime):
        return t
    if isinstance(t, OffsetDateTime):
        return ZonedDateTime.ofInstant(t.toInstant(), t._offset)
    if isinstance(t, Parsed):
        zone = _zone_of_parsed(t)
        if zone is not None:
            if "INSTANT_SECONDS" in t.fields:
                return ZonedDateTime.ofInstant(Instant(t.fields["INSTANT_SECONDS"], t.fields.get("NANO_OF_SECOND", 0)), zone)
            if t.date is not None and t.time is not None:
                return ZonedDateTime.of(LocalDateTime(t.date, t.time), zone)
    _no("ZonedDateTime", t)


def to_offset(t):
    if isinstance(t, OffsetDateTime):
        return t
    if isinstance(t, ZonedDateTime):
        return t.toOffsetDateTime()
    if isinstance(t, Parsed):
        if "OFFSET_SECONDS" in t.fields and t.date is not None and t.time is not None:
            return OffsetDateTime(LocalDateTime(t.date, t.time), ZoneOffset.ofTotalSeconds(t.fields["OFFSET_SECONDS"]))
        if "INSTANT_SECONDS" in t.fields and _zone_of_parsed(t) is not None:
            return ZonedDateTime.ofInstant(Instant(t.fields["INSTANT_SECONDS"], t.fields.get("NANO_OF_SECOND", 0)), _zone_of_parsed(t)).toOffsetDateTime()
    _no("OffsetDateTime", t)


def to_instant(t):
    if isinstance(t, Instant):
        return t
    if isinstance(t, (ZonedDateTime, OffsetDateTime)):
        return t.toInstant()
    if isinstance(t, Parsed) and "INSTANT_SECONDS" in t.fields:
        return Instant(t.fields["INSTANT_SECONDS"], t.fields.get("NANO_OF_SECOND", 0))
    _no("Instant", t)


def convert(parsed, kind):
    return {"date": to_date, "time": to_time, "datetime": to_datetime, "zoned": to_zoned, "offset": to_offset, "instant": to_instant}[kind](parsed)


def _install_from():
    for cls, func in ((LocalDate, to_date), (LocalTime, to_time), (LocalDateTime, to_datetime), (ZonedDateTime, to_zoned),
                      (OffsetDateTime, to_offset), (Instant, to_instant)):
        method = staticmethod(func)
        setattr(cls, "from_", method)
        setattr(cls, "from", method)


_install_from()


def _year_from(t):
    if isinstance(t, Year):
        return t
    a = Adapter(t)
    value = a.get("YEAR")
    if value is None:
        _no("Year", t)
    return Year.of(value)


def _year_month_from(t):
    if isinstance(t, YearMonth):
        return t
    a = Adapter(t)
    y, m = a.get("YEAR"), a.get("MONTH_OF_YEAR")
    if y is None or m is None:
        _no("YearMonth", t)
    return YearMonth.of(y, m)


for _cls, _func in ((Year, _year_from), (YearMonth, _year_month_from)):
    setattr(_cls, "from_", staticmethod(_func))
    setattr(_cls, "from", staticmethod(_func))


def _builder():
    return DateTimeFormatterBuilder()


def _make_constants():
    b = _builder
    year = ChronoField.YEAR
    iso_local_date = b().appendValue(year, 4, 10, SignStyle.EXCEEDS_PAD).appendLiteral("-").appendValue(
        ChronoField.MONTH_OF_YEAR, 2).appendLiteral("-").appendValue(ChronoField.DAY_OF_MONTH, 2)._to_formatter(ResolverStyle.STRICT)
    iso_offset_date = b().parseCaseInsensitive().append(iso_local_date).parseLenient().appendOffsetId().parseStrict()._to_formatter(ResolverStyle.STRICT)
    iso_date = b().parseCaseInsensitive().append(iso_local_date).optionalStart().parseLenient().appendOffsetId().parseStrict()._to_formatter(
        ResolverStyle.STRICT)
    iso_local_time = b().appendValue(ChronoField.HOUR_OF_DAY, 2).appendLiteral(":").appendValue(ChronoField.MINUTE_OF_HOUR, 2).optionalStart() \
        .appendLiteral(":").appendValue(ChronoField.SECOND_OF_MINUTE, 2).optionalStart().appendFraction(
            ChronoField.NANO_OF_SECOND, 0, 9, True)._to_formatter(ResolverStyle.STRICT)
    iso_offset_time = b().parseCaseInsensitive().append(iso_local_time).parseLenient().appendOffsetId().parseStrict()._to_formatter(
        ResolverStyle.STRICT)
    iso_time = b().parseCaseInsensitive().append(iso_local_time).optionalStart().parseLenient().appendOffsetId().parseStrict()._to_formatter(
        ResolverStyle.STRICT)
    iso_local_date_time = b().parseCaseInsensitive().append(iso_local_date).appendLiteral("T").append(iso_local_time)._to_formatter(ResolverStyle.STRICT)
    iso_offset_date_time = b().parseCaseInsensitive().append(iso_local_date_time).parseLenient().appendOffsetId().parseStrict()._to_formatter(
        ResolverStyle.STRICT)
    iso_zoned = b().append(iso_offset_date_time).optionalStart().appendLiteral("[").parseCaseSensitive().appendZoneRegionId().appendLiteral(
        "]")._to_formatter(ResolverStyle.STRICT)
    iso_date_time = b().append(iso_local_date_time).optionalStart().parseLenient().appendOffsetId().parseStrict().optionalStart().appendLiteral(
        "[").parseCaseSensitive().appendZoneRegionId().appendLiteral("]")._to_formatter(ResolverStyle.STRICT)
    iso_ordinal = b().parseCaseInsensitive().appendValue(year, 4, 10, SignStyle.EXCEEDS_PAD).appendLiteral("-").appendValue(
        ChronoField.DAY_OF_YEAR, 3).optionalStart().parseLenient().appendOffsetId().parseStrict()._to_formatter(ResolverStyle.STRICT)
    iso_instant = b().parseCaseInsensitive().appendInstant()._to_formatter(ResolverStyle.STRICT)
    basic = b().parseCaseInsensitive().appendValue(year, 4).appendValue(ChronoField.MONTH_OF_YEAR, 2).appendValue(
        ChronoField.DAY_OF_MONTH, 2).optionalStart().parseLenient().appendOffset("+HHMMss", "Z").parseStrict()._to_formatter(ResolverStyle.STRICT)
    dow = {i + 1: _DOW[i][:3] for i in range(7)}
    moy = {i + 1: MONTHS[i][:3] for i in range(12)}
    from .jmap import HashMap
    dow_map, moy_map = HashMap(), HashMap()
    from .jlang import Long
    for k, v in dow.items():
        dow_map.put(Long.valueOf(k), v)
    for k, v in moy.items():
        moy_map.put(Long.valueOf(k), v)
    rfc = b().parseCaseInsensitive().parseLenient().optionalStart().appendText(ChronoField.DAY_OF_WEEK, dow_map).appendLiteral(", ").optionalEnd() \
        .appendValue(ChronoField.DAY_OF_MONTH, 1, 2, SignStyle.NOT_NEGATIVE).appendLiteral(" ").appendText(ChronoField.MONTH_OF_YEAR, moy_map) \
        .appendLiteral(" ").appendValue(year, 4).appendLiteral(" ").appendValue(ChronoField.HOUR_OF_DAY, 2).appendLiteral(":").appendValue(
            ChronoField.MINUTE_OF_HOUR, 2).optionalStart().appendLiteral(":").appendValue(ChronoField.SECOND_OF_MINUTE, 2).optionalEnd() \
        .appendLiteral(" ").appendOffset("+HHMM", "GMT")._to_formatter(ResolverStyle.SMART)
    for name, value in (("ISO_LOCAL_DATE", iso_local_date), ("ISO_OFFSET_DATE", iso_offset_date), ("ISO_DATE", iso_date),
                        ("ISO_LOCAL_TIME", iso_local_time), ("ISO_OFFSET_TIME", iso_offset_time), ("ISO_TIME", iso_time),
                        ("ISO_LOCAL_DATE_TIME", iso_local_date_time), ("ISO_OFFSET_DATE_TIME", iso_offset_date_time),
                        ("ISO_ZONED_DATE_TIME", iso_zoned), ("ISO_DATE_TIME", iso_date_time), ("ISO_ORDINAL_DATE", iso_ordinal),
                        ("ISO_INSTANT", iso_instant), ("BASIC_ISO_DATE", basic), ("RFC_1123_DATE_TIME", rfc)):
        setattr(DateTimeFormatter, name, value)


_make_constants()
