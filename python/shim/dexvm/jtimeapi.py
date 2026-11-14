"""java.time: LocalDate, LocalTime, LocalDateTime, Instant, Duration, Period, ZoneId, ZoneOffset, ZonedDateTime, OffsetDateTime, Year, YearMonth,
Clock, DayOfWeek, Month, ChronoUnit, ChronoField, TemporalAdjusters and DateTimeFormatter

the calendar is the ISO one, proleptic Gregorian, like java.time. time zones come from jtime (the C library for the default zone, zoneinfo for named
ones). a formatter pattern uses the letters y u M L d D E a H h k K m s S n z O X x Z V and quotes; month and day names are english"""

import re
import time as _time

from . import runtime
from .api import host_class, jmethod, lookup_host
from .jfunc import jequals, jstring, string_hash
from .jlang import Object, jstr
from .jtime import (DAYS, MONTHS, MS_DAY, _Zone, _find_zone, _gmt_text, civil_from_days, days_from_civil, default_zone, is_leap,
                    month_length, _tokens)
from .jutil import check_nonnull

_LETTERS = frozenset("GyuMLdDEeaHkKhmsSnzOXxZV")
DateTimeException = lookup_host("java.time.DateTimeException").py


def _define(table):
    for line in table.strip().splitlines():
        name, parent = line.split()
        host_class(name)(type(name.rsplit(".", 1)[1], (lookup_host(parent).py,), {"__module__": __name__}))


_define("""
java.time.format.DateTimeParseException java.time.DateTimeException
java.time.temporal.UnsupportedTemporalTypeException java.time.DateTimeException
java.time.zone.ZoneRulesException java.time.DateTimeException
""")

for _name in ("Temporal", "TemporalAccessor", "TemporalAmount", "TemporalUnit", "TemporalField", "TemporalAdjuster", "TemporalQuery",
              "ChronoLocalDate", "ChronoLocalDateTime", "ChronoZonedDateTime"):
    host_class("java.time.temporal." + _name if not _name.startswith("Chrono") else "java.time.chrono." + _name, interface=True,
               interfaces=(("java.time.temporal.TemporalAccessor",) if _name in ("Temporal",) else
                           ("java.time.temporal.Temporal",) if _name.startswith("Chrono") else ()))(
        type(_name, (), {"__slots__": ()}))


def _throw(message):
    runtime.throw_new("java.time.DateTimeException", message)


def _check(value, low, high, name):
    if not low <= value <= high:
        _throw("Invalid value for %s (valid values %d - %d): %d" % (name, low, high, value))
    return value


class _Enum(Object):
    _names = ()

    def __init__(self, name, ordinal):
        self._name = name
        self._ordinal = ordinal

    def name(self):
        return self._name

    def ordinal(self):
        return self._ordinal

    def toString(self):
        return self._name

    def compareTo(self, other):
        return self._ordinal - other._ordinal

    def getDeclaringClass(self):
        return runtime.class_of(self)

    @classmethod
    def _values(cls):
        array = runtime.new_array("[L" + cls._jname.replace(".", "/") + ";", 0)
        array.extend(cls._all)
        return array

    @classmethod
    def _value_of(cls, name):
        if name is None:
            runtime.npe("Name is null")
        for item in cls._all:
            if item._name == name:
                return item
        runtime.throw_new("java.lang.IllegalArgumentException", "No enum constant %s.%s" % (cls._jname, name))


def _make_enum(jname, names, extra=None):
    simple = jname.rsplit(".", 1)[1]
    cls = type(simple, (_Enum,), {"_jname": jname})
    # a java static method is called without the class: bind it here
    cls.values = staticmethod(lambda: cls._values())
    cls.valueOf = staticmethod(lambda name: cls._value_of(name))
    cls._all = []
    for index, name in enumerate(names):
        item = cls(name, index)
        setattr(cls, name, item)
        cls._all.append(item)
    return host_class(jname, interfaces=("java.lang.Comparable",))(cls)


DayOfWeek = _make_enum("java.time.DayOfWeek", [d.upper() for d in DAYS[1:]] + ["SUNDAY"])
Month = _make_enum("java.time.Month", [m.upper() for m in MONTHS])
ChronoUnit = _make_enum("java.time.temporal.ChronoUnit", ["NANOS", "MICROS", "MILLIS", "SECONDS", "MINUTES", "HOURS", "HALF_DAYS", "DAYS",
                                                         "WEEKS", "MONTHS", "YEARS", "DECADES", "CENTURIES", "MILLENNIA", "ERAS", "FOREVER"])
ChronoField = _make_enum("java.time.temporal.ChronoField", ["NANO_OF_SECOND", "NANO_OF_DAY", "MICRO_OF_SECOND", "MICRO_OF_DAY", "MILLI_OF_SECOND",
                                                           "MILLI_OF_DAY", "SECOND_OF_MINUTE", "SECOND_OF_DAY", "MINUTE_OF_HOUR", "MINUTE_OF_DAY",
                                                           "HOUR_OF_AMPM", "CLOCK_HOUR_OF_AMPM", "HOUR_OF_DAY", "CLOCK_HOUR_OF_DAY", "AMPM_OF_DAY",
                                                           "DAY_OF_WEEK", "ALIGNED_DAY_OF_WEEK_IN_MONTH", "ALIGNED_DAY_OF_WEEK_IN_YEAR", "DAY_OF_MONTH",
                                                           "DAY_OF_YEAR", "EPOCH_DAY", "ALIGNED_WEEK_OF_MONTH", "ALIGNED_WEEK_OF_YEAR",
                                                           "MONTH_OF_YEAR", "PROLEPTIC_MONTH", "YEAR_OF_ERA", "YEAR", "ERA",
                                                           "INSTANT_SECONDS", "OFFSET_SECONDS"])
TextStyle = _make_enum("java.time.format.TextStyle", ["FULL", "FULL_STANDALONE", "SHORT", "SHORT_STANDALONE", "NARROW", "NARROW_STANDALONE"])
FormatStyle = _make_enum("java.time.format.FormatStyle", ["FULL", "LONG", "MEDIUM", "SHORT"])

_UNIT_NANOS = {"NANOS": 1, "MICROS": 1000, "MILLIS": 10 ** 6, "SECONDS": 10 ** 9, "MINUTES": 60 * 10 ** 9, "HOURS": 3600 * 10 ** 9,
               "HALF_DAYS": 43200 * 10 ** 9, "DAYS": 86400 * 10 ** 9, "WEEKS": 7 * 86400 * 10 ** 9}
_UNIT_MONTHS = {"MONTHS": 1, "YEARS": 12, "DECADES": 120, "CENTURIES": 1200, "MILLENNIA": 12000}


def _day_of_week(item):
    return DayOfWeek._all[item]


def _month_names(style, month):
    name = MONTHS[month - 1]
    return name if style._name.startswith("FULL") else (name[0] if style._name.startswith("NARROW") else name[:3])


def _display(item, style, table):
    index = item._ordinal
    name = table[index]
    return name if style._name.startswith("FULL") else (name[0] if style._name.startswith("NARROW") else name[:3])


DayOfWeek.getValue = lambda self: self._ordinal + 1
DayOfWeek.of = staticmethod(lambda n: DayOfWeek._all[_check(n, 1, 7, "DayOfWeek") - 1])
DayOfWeek.plus = lambda self, days: DayOfWeek._all[(self._ordinal + days) % 7]
DayOfWeek.minus = lambda self, days: DayOfWeek._all[(self._ordinal - days) % 7]
DayOfWeek.getDisplayName = lambda self, style, locale=None: _display(self, style, DAYS[1:] + DAYS[:1])
Month.getValue = lambda self: self._ordinal + 1
Month.of = staticmethod(lambda n: Month._all[_check(n, 1, 12, "MonthOfYear") - 1])
Month.plus = lambda self, months: Month._all[(self._ordinal + months) % 12]
Month.minus = lambda self, months: Month._all[(self._ordinal - months) % 12]
Month.length = lambda self, leap: 29 if self._ordinal == 1 and leap else month_length(2001, self._ordinal)
Month.maxLength = lambda self: month_length(2000, self._ordinal)
Month.minLength = lambda self: month_length(2001, self._ordinal)
Month.getDisplayName = lambda self, style, locale=None: _month_names(style, self._ordinal + 1)
ChronoUnit.getDuration = lambda self: Duration.ofNanos(_UNIT_NANOS[self._name]) if self._name in _UNIT_NANOS else (
    Duration.ofSeconds(31556952 * _UNIT_MONTHS[self._name] // 12) if self._name in _UNIT_MONTHS else Duration.ofSeconds(2 ** 62))
ChronoUnit.between = lambda self, a, b: a.until(b, self)
ChronoUnit.isDateBased = lambda self: 1 if self._ordinal >= 7 and self._name != "FOREVER" else 0
ChronoUnit.isTimeBased = lambda self: 1 if self._ordinal < 7 else 0


def _camel(name):
    return "".join(part.capitalize() for part in name.split("_")).replace("Ampm", "AmPm")


ChronoUnit.toString = lambda self: _camel(self._name)
ChronoField.toString = lambda self: _camel(self._name)

_FIELD_RANGES = {
    "NANO_OF_SECOND": (0, 999999999), "NANO_OF_DAY": (0, 86400 * 10 ** 9 - 1), "MICRO_OF_SECOND": (0, 999999),
    "MICRO_OF_DAY": (0, 86400 * 10 ** 6 - 1), "MILLI_OF_SECOND": (0, 999), "MILLI_OF_DAY": (0, 86400000 - 1),
    "SECOND_OF_MINUTE": (0, 59), "SECOND_OF_DAY": (0, 86399), "MINUTE_OF_HOUR": (0, 59), "MINUTE_OF_DAY": (0, 1439),
    "HOUR_OF_AMPM": (0, 11), "CLOCK_HOUR_OF_AMPM": (1, 12), "HOUR_OF_DAY": (0, 23), "CLOCK_HOUR_OF_DAY": (1, 24),
    "AMPM_OF_DAY": (0, 1), "DAY_OF_WEEK": (1, 7), "DAY_OF_MONTH": (1, 28, 31), "DAY_OF_YEAR": (1, 365, 366),
    "EPOCH_DAY": (-365243219162, 365241780471), "MONTH_OF_YEAR": (1, 12),
    "PROLEPTIC_MONTH": (-999999999 * 12, 999999999 * 12 + 11), "YEAR": (-999999999, 999999999), "ERA": (0, 1),
    "YEAR_OF_ERA": (1, 999999999, 1000000000), "ALIGNED_DAY_OF_WEEK_IN_MONTH": (1, 7), "ALIGNED_DAY_OF_WEEK_IN_YEAR": (1, 7),
    "ALIGNED_WEEK_OF_MONTH": (1, 4, 5), "ALIGNED_WEEK_OF_YEAR": (1, 53),
    "INSTANT_SECONDS": (-0x8000000000000000, 0x7FFFFFFFFFFFFFFF), "OFFSET_SECONDS": (-18 * 3600, 18 * 3600),
}


def _field_range(self):
    from .jmore2 import ValueRange
    return ValueRange.of(*_FIELD_RANGES[self._name])


ChronoField.range = _field_range
ChronoField.checkValidValue = lambda self, value: _field_range(self).checkValidValue(value, self)
ChronoField.checkValidIntValue = lambda self, value: _field_range(self).checkValidIntValue(value, self)
ChronoField.isDateBased = lambda self: 1 if self._ordinal >= 15 and self._name not in ("INSTANT_SECONDS", "OFFSET_SECONDS") else 0
ChronoField.isTimeBased = lambda self: 1 if self._ordinal < 15 else 0


def _unit(unit):
    return unit if isinstance(unit, _Enum) else check_nonnull(unit)


def _div(a, b):
    """floor division as java.lang.Math.floorDiv"""
    return a // b


class Duration(Object):
    """seconds and nanoseconds of a span of time, with the sign on the seconds as java.time does"""

    def __init__(self, seconds=0, nanos=0):
        seconds += nanos // 10 ** 9
        self._s = seconds
        self._n = nanos % 10 ** 9

    @staticmethod
    def ofDays(n):
        return Duration(n * 86400)

    @staticmethod
    def ofHours(n):
        return Duration(n * 3600)

    @staticmethod
    def ofMinutes(n):
        return Duration(n * 60)

    @staticmethod
    def ofSeconds(n, adjust=0):
        return Duration(n, adjust)

    @staticmethod
    def ofMillis(n):
        return Duration(n // 1000, (n % 1000) * 10 ** 6)

    @staticmethod
    def ofNanos(n):
        return Duration(0, n)

    @staticmethod
    def of(amount, unit):
        return Duration.ZERO.plus(amount, unit)

    @staticmethod
    def between(start, end):
        return Duration.ofNanos(start.until(end, ChronoUnit.NANOS))

    def _total(self):
        return self._s * 10 ** 9 + self._n

    def getSeconds(self):
        return self._s

    def getNano(self):
        return self._n

    def toDays(self):
        return int(self._s / 86400) if self._s >= 0 else -((-self._s) // 86400)

    def toHours(self):
        return int(self._s / 3600) if self._s >= 0 else -((-self._s) // 3600)

    def toMinutes(self):
        return int(self._s / 60) if self._s >= 0 else -((-self._s) // 60)

    def toSeconds(self):
        return self._s

    def toMillis(self):
        return self._s * 1000 + self._n // 10 ** 6

    def toNanos(self):
        return runtime.wrap64(self._total())

    def toHoursPart(self):
        return self.toHours() % 24

    def toMinutesPart(self):
        return self.toMinutes() % 60

    def toSecondsPart(self):
        return self._s % 60

    def toMillisPart(self):
        return self._n // 10 ** 6

    def toNanosPart(self):
        return self._n

    def isZero(self):
        return 1 if self._total() == 0 else 0

    def isNegative(self):
        return 1 if self._s < 0 else 0

    def plus(self, first, unit=None):
        if unit is None:
            return Duration(0, self._total() + first._total())
        if isinstance(unit, _Enum) and unit._name in _UNIT_NANOS:
            return Duration(0, self._total() + first * _UNIT_NANOS[unit._name])
        _throw("Unit must not have an estimated duration")

    def minus(self, first, unit=None):
        if unit is None:
            return Duration(0, self._total() - first._total())
        return self.plus(-first, unit)

    def plusDays(self, n):
        return Duration(0, self._total() + n * 86400 * 10 ** 9)

    def plusHours(self, n):
        return Duration(0, self._total() + n * 3600 * 10 ** 9)

    def plusMinutes(self, n):
        return Duration(0, self._total() + n * 60 * 10 ** 9)

    def plusSeconds(self, n):
        return Duration(0, self._total() + n * 10 ** 9)

    def plusMillis(self, n):
        return Duration(0, self._total() + n * 10 ** 6)

    def plusNanos(self, n):
        return Duration(0, self._total() + n)

    def minusDays(self, n):
        return self.plusDays(-n)

    def minusHours(self, n):
        return self.plusHours(-n)

    def minusMinutes(self, n):
        return self.plusMinutes(-n)

    def minusSeconds(self, n):
        return self.plusSeconds(-n)

    def minusMillis(self, n):
        return self.plusMillis(-n)

    def minusNanos(self, n):
        return self.plusNanos(-n)

    def multipliedBy(self, n):
        return Duration(0, self._total() * n)

    def dividedBy(self, divisor):
        if isinstance(divisor, Duration):
            return self._total() // divisor._total() if divisor._total() else runtime.throw_new("java.lang.ArithmeticException", "Cannot divide by zero")
        if divisor == 0:
            runtime.throw_new("java.lang.ArithmeticException", "Cannot divide by zero")
        total = self._total()
        quotient = abs(total) // abs(divisor)
        return Duration(0, quotient if (total < 0) == (divisor < 0) else -quotient)

    def negated(self):
        return Duration(0, -self._total())

    def abs(self):
        return self.negated() if self._s < 0 else self

    def compareTo(self, other):
        return (self._total() > other._total()) - (self._total() < other._total())

    def equals(self, other):
        return 1 if isinstance(other, Duration) and other._total() == self._total() else 0

    def hashCode(self):
        return runtime.wrap32(self._s ^ (self._s >> 32)) + 51 * self._n

    def toString(self):
        if self._total() == 0:
            return "PT0S"
        total_s = self._s + (1 if self._s < 0 and self._n > 0 else 0)
        hours = int(total_s / 3600)
        minutes = int((total_s % 3600 if total_s >= 0 else -((-total_s) % 3600)) / 60)
        seconds = total_s % 60 if total_s >= 0 else -((-total_s) % 60)
        out = ["PT"]
        if hours:
            out.append("%dH" % hours)
        if minutes:
            out.append("%dM" % minutes)
        if seconds == 0 and self._n == 0 and len(out) > 1:
            return "".join(out)
        if self._s < 0 and self._n > 0:
            if seconds == 0:
                out.append("-0")
            else:
                out.append(str(seconds))
        else:
            out.append(str(seconds))
        if self._n > 0:
            fraction = (10 ** 9 - self._n if self._s < 0 else self._n)
            out.append(("%09d" % fraction).rstrip("0").join([".", ""]))
        out.append("S")
        return "".join(out)

    @staticmethod
    def parse(text):
        match = re.match(r"([-+]?)P(?:([-+]?\d+)D)?(?:T(?:([-+]?\d+)H)?(?:([-+]?\d+)M)?(?:([-+]?\d+)(?:[.,](\d{0,9}))?S)?)?\Z", text, re.I)
        if match is None or text.upper() in ("P", "PT", "-P", "-PT") or text.upper().endswith("T"):
            runtime.throw_new("java.time.format.DateTimeParseException", "Text cannot be parsed to a Duration")
        sign, days, hours, minutes, seconds, fraction = match.groups()
        total = (int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes or 0) * 60 + int(seconds or 0)) * 10 ** 9
        if fraction:
            part = int(fraction.ljust(9, "0"))
            total += -part if (seconds or "").startswith("-") else part
        return Duration(0, -total if sign == "-" else total)


Duration.ZERO = Duration(0)
host_class("java.time.Duration", interfaces=("java.time.temporal.TemporalAmount", "java.lang.Comparable"))(Duration)


class Period(Object):
    def __init__(self, years=0, months=0, days=0):
        self._y, self._m, self._d = years, months, days

    ofYears = staticmethod(lambda n: Period(n, 0, 0))
    ofMonths = staticmethod(lambda n: Period(0, n, 0))
    ofWeeks = staticmethod(lambda n: Period(0, 0, n * 7))
    ofDays = staticmethod(lambda n: Period(0, 0, n))
    of = staticmethod(lambda y, m, d: Period(y, m, d))

    @staticmethod
    def between(start, end):
        return start.until(end)

    def getYears(self):
        return self._y

    def getMonths(self):
        return self._m

    def getDays(self):
        return self._d

    def toTotalMonths(self):
        return self._y * 12 + self._m

    def isZero(self):
        return 0 if (self._y or self._m or self._d) else 1

    def isNegative(self):
        return 1 if self._y < 0 or self._m < 0 or self._d < 0 else 0

    def plusDays(self, n):
        return Period(self._y, self._m, self._d + n)

    def plusMonths(self, n):
        return Period(self._y, self._m + n, self._d)

    def plusYears(self, n):
        return Period(self._y + n, self._m, self._d)

    def plus(self, other):
        return Period(self._y + other._y, self._m + other._m, self._d + other._d)

    def minus(self, other):
        return Period(self._y - other._y, self._m - other._m, self._d - other._d)

    def multipliedBy(self, n):
        return Period(self._y * n, self._m * n, self._d * n)

    def negated(self):
        return self.multipliedBy(-1)

    def normalized(self):
        total = self.toTotalMonths()
        years = int(total / 12)
        return Period(years, total - years * 12, self._d)

    def equals(self, other):
        return 1 if isinstance(other, Period) and (other._y, other._m, other._d) == (self._y, self._m, self._d) else 0

    def hashCode(self):
        return runtime.wrap32(self._y + (self._m << 8 | self._m >> 24) + (self._d << 16 | self._d >> 16))

    def toString(self):
        if not (self._y or self._m or self._d):
            return "P0D"
        return "P" + ("%dY" % self._y if self._y else "") + ("%dM" % self._m if self._m else "") + ("%dD" % self._d if self._d else "")

    @staticmethod
    def parse(text):
        match = re.match(r"([-+]?)P(?:([-+]?\d+)Y)?(?:([-+]?\d+)M)?(?:([-+]?\d+)W)?(?:([-+]?\d+)D)?\Z", text, re.I)
        if match is None or text.upper() in ("P", "-P", "+P"):
            runtime.throw_new("java.time.format.DateTimeParseException", "Text cannot be parsed to a Period")
        sign, y, m, w, d = match.groups()
        f = -1 if sign == "-" else 1
        return Period(f * int(y or 0), f * int(m or 0), f * (int(w or 0) * 7 + int(d or 0)))


Period.ZERO = Period(0, 0, 0)
host_class("java.time.Period", interfaces=("java.time.temporal.TemporalAmount",))(Period)


class ZoneId(Object):
    """a zone id: a region (Europe/Moscow), an offset (+03:00, Z) or UTC and GMT"""

    def __init__(self, zone_id, zone):
        self._id = zone_id
        self._zone = zone

    @staticmethod
    def of(text):
        if text in ("Z",):
            return ZoneOffset.UTC
        if text[:1] in "+-":
            return ZoneOffset.of(text)
        if text.startswith(("UTC", "GMT", "UT")) and len(text) > 3 and text[len(text.rstrip("0123456789:+-")) - 0:] is not None:
            prefix = "UTC" if text.startswith("UTC") else ("GMT" if text.startswith("GMT") else "UT")
            offset = ZoneOffset.of(text[len(prefix):])
            return ZoneRegion(prefix + ("" if offset._seconds == 0 else offset._id), offset._zone)
        zone = _find_zone(text)
        if zone is None:
            runtime.throw_new("java.time.zone.ZoneRulesException", "Unknown time-zone ID: " + text)
        return ZoneRegion(text, zone)

    @staticmethod
    def systemDefault():
        zone = default_zone()
        return ZoneRegion(zone.id, zone)

    @staticmethod
    def getAvailableZoneIds():
        from .jcoll import HashSet
        result = HashSet()
        try:
            import zoneinfo
            for name in zoneinfo.available_timezones():
                result.add(name)
        except ImportError:
            pass
        return result

    def getId(self):
        return self._id

    def getRules(self):
        return ZoneRules(self._zone)

    def normalized(self):
        return self

    def offset_at(self, epoch_seconds):
        return self._zone.offset(epoch_seconds * 1000) // 1000

    def equals(self, other):
        return 1 if isinstance(other, ZoneId) and other._id == self._id else 0

    def hashCode(self):
        return string_hash(self._id)

    def toString(self):
        return self._id

    def getDisplayName(self, style, locale=None):
        return self._id


host_class("java.time.ZoneId", interfaces=("java.io.Serializable",))(ZoneId)


class ZoneRegion(ZoneId):
    pass


host_class("java.time.ZoneRegion")(ZoneRegion)


class ZoneRules(Object):
    def __init__(self, zone):
        self._zone = zone

    def getOffset(self, when):
        seconds = when._epoch_seconds() if hasattr(when, "_epoch_seconds") else when.getEpochSecond()
        if isinstance(when, LocalDateTime):
            utc = self._zone.local_to_utc(when._epoch_local() * 1000)
            return ZoneOffset.ofTotalSeconds(self._zone.offset(utc) // 1000)
        return ZoneOffset.ofTotalSeconds(self._zone.offset(seconds * 1000) // 1000)

    def isDaylightSavings(self, instant):
        return 1 if self._zone.offset(instant.getEpochSecond() * 1000) != self._zone.raw() else 0

    def getStandardOffset(self, instant):
        return ZoneOffset.ofTotalSeconds(self._zone.raw() // 1000)

    def isFixedOffset(self):
        return 0 if self._zone.uses_dst() else 1


host_class("java.time.zone.ZoneRules")(ZoneRules)


class ZoneOffset(ZoneId):
    def __init__(self, seconds):
        text = "Z" if seconds == 0 else "%s%02d:%02d%s" % ("-" if seconds < 0 else "+", abs(seconds) // 3600, abs(seconds) // 60 % 60,
                                                          (":%02d" % (abs(seconds) % 60)) if abs(seconds) % 60 else "")
        ZoneId.__init__(self, text, _Zone(_gmt_text(seconds * 1000) if seconds else "GMT", "fixed", seconds * 1000))
        self._seconds = seconds

    @staticmethod
    def ofTotalSeconds(seconds):
        _check(seconds, -64800, 64800, "totalSeconds")
        return ZoneOffset(seconds)

    @staticmethod
    def ofHours(hours):
        return ZoneOffset.ofTotalSeconds(hours * 3600)

    @staticmethod
    def ofHoursMinutes(hours, minutes):
        return ZoneOffset.ofTotalSeconds(hours * 3600 + minutes * 60)

    @staticmethod
    def of(text):
        if text == "Z":
            return ZoneOffset.UTC
        match = re.match(r"([+-])(\d{1,2})(?::?(\d{2}))?(?::?(\d{2}))?\Z", text)
        if match is None:
            _throw("Invalid ID for ZoneOffset, invalid format: " + text)
        sign = -1 if match.group(1) == "-" else 1
        return ZoneOffset.ofTotalSeconds(sign * (int(match.group(2)) * 3600 + int(match.group(3) or 0) * 60 + int(match.group(4) or 0)))

    def getTotalSeconds(self):
        return self._seconds

    def compareTo(self, other):
        return other._seconds - self._seconds

    def getRules(self):
        return ZoneRules(self._zone)


ZoneOffset.UTC = ZoneOffset(0)
ZoneOffset.MIN = ZoneOffset(-64800)
ZoneOffset.MAX = ZoneOffset(64800)
host_class("java.time.ZoneOffset", interfaces=("java.lang.Comparable",))(ZoneOffset)


def _parse_error(text, what):
    runtime.throw_new("java.time.format.DateTimeParseException", "Text '%s' could not be parsed at index 0" % text)


class LocalDate(Object):
    def __init__(self, year, month, day):
        self._y, self._m, self._d = year, month, day

    @staticmethod
    def of(year, month, day):
        month = month._ordinal + 1 if isinstance(month, _Enum) else month
        _check(year, -999999999, 999999999, "Year")
        _check(month, 1, 12, "MonthOfYear")
        if not 1 <= day <= 31:
            _throw("Invalid value for DayOfMonth (valid values 1 - 28/31): %d" % day)
        if day > month_length(year, month - 1):
            _throw("Invalid date 'February 29' as '%d' is not a leap year" % year if month == 2 and day == 29 else
                   "Invalid date '%s %d'" % (MONTHS[month - 1].upper(), day))
        return LocalDate(year, month, day)

    @staticmethod
    def ofEpochDay(days):
        y, m, d = civil_from_days(days)
        return LocalDate(y, m, d)

    @staticmethod
    def ofYearDay(year, day):
        return LocalDate.ofEpochDay(days_from_civil(year, 1, 1) + day - 1)

    @staticmethod
    def now(clock=None):
        zone = clock._zone if isinstance(clock, Clock) else (clock if isinstance(clock, ZoneId) else ZoneId.systemDefault())
        return ZonedDateTime.ofInstant(Instant.ofEpochMilli(_now(clock)), zone).toLocalDate()

    @staticmethod
    def parse(text, formatter=None):
        if formatter is not None:
            return formatter._parse_to(text, "date")
        match = re.match(r"(-?\d{4,9})-(\d{2})-(\d{2})\Z", text)
        if match is None:
            _parse_error(text, "date")
        try:
            return LocalDate.of(int(match.group(1)), int(match.group(2)), int(match.group(3)))
        except DateTimeException as error:
            runtime.throw_new("java.time.format.DateTimeParseException", "Text '%s' could not be parsed: %s" % (text, error.getMessage()))

    def getYear(self):
        return self._y

    def getMonthValue(self):
        return self._m

    def getMonth(self):
        return Month._all[self._m - 1]

    def getDayOfMonth(self):
        return self._d

    def getDayOfYear(self):
        return self.toEpochDay() - days_from_civil(self._y, 1, 1) + 1

    def getDayOfWeek(self):
        return DayOfWeek._all[(self.toEpochDay() + 3) % 7]

    def isLeapYear(self):
        return 1 if is_leap(self._y) else 0

    def lengthOfMonth(self):
        return month_length(self._y, self._m - 1)

    def lengthOfYear(self):
        return 366 if is_leap(self._y) else 365

    def toEpochDay(self):
        return days_from_civil(self._y, self._m, self._d)

    def _with_days(self, days):
        return LocalDate.ofEpochDay(days)

    def plusDays(self, n):
        return self._with_days(self.toEpochDay() + n)

    def plusWeeks(self, n):
        return self.plusDays(n * 7)

    def plusMonths(self, n):
        total = self._y * 12 + self._m - 1 + n
        year, month = divmod(total, 12)
        return LocalDate(year, month + 1, min(self._d, month_length(year, month)))

    def plusYears(self, n):
        return LocalDate(self._y + n, self._m, min(self._d, month_length(self._y + n, self._m - 1)))

    def minusDays(self, n):
        return self.plusDays(-n)

    def minusWeeks(self, n):
        return self.plusWeeks(-n)

    def minusMonths(self, n):
        return self.plusMonths(-n)

    def minusYears(self, n):
        return self.plusYears(-n)

    def plus(self, first, unit=None):
        if unit is None:
            return self.plusYears(first._y).plusMonths(first._m).plusDays(first._d) if isinstance(first, Period) else self.plusDays(first.toDays())
        name = unit._name
        if name == "DAYS":
            return self.plusDays(first)
        if name == "WEEKS":
            return self.plusWeeks(first)
        if name in _UNIT_MONTHS:
            return self.plusMonths(first * _UNIT_MONTHS[name])
        runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported unit: " + unit.toString())

    def minus(self, first, unit=None):
        if unit is None:
            return self.plus(first.negated())
        return self.plus(-first, unit)

    def withDayOfMonth(self, d):
        return LocalDate.of(self._y, self._m, d)

    def withMonth(self, m):
        _check(m, 1, 12, "MonthOfYear")
        return LocalDate(self._y, m, min(self._d, month_length(self._y, m - 1)))

    def withYear(self, y):
        return LocalDate(y, self._m, min(self._d, month_length(y, self._m - 1)))

    def withDayOfYear(self, d):
        return LocalDate.ofYearDay(self._y, d)

    def with_(self, adjuster, value=None):
        if value is None:
            return adjuster.adjustInto(self) if hasattr(adjuster, "adjustInto") else adjuster(self)
        name = adjuster._name
        if name == "DAY_OF_MONTH":
            return self.withDayOfMonth(value)
        if name == "MONTH_OF_YEAR":
            return self.withMonth(value)
        if name == "YEAR":
            return self.withYear(value)
        if name == "DAY_OF_YEAR":
            return self.withDayOfYear(value)
        if name == "DAY_OF_WEEK":
            return self.plusDays(value - self.getDayOfWeek().getValue())
        if name == "EPOCH_DAY":
            return LocalDate.ofEpochDay(value)
        runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + adjuster.toString())

    def get(self, field):
        return self.getLong(field)

    def getLong(self, field):
        name = field._name
        table = {"DAY_OF_MONTH": self._d, "MONTH_OF_YEAR": self._m, "YEAR": self._y, "DAY_OF_YEAR": self.getDayOfYear(),
                 "DAY_OF_WEEK": self.getDayOfWeek().getValue(), "EPOCH_DAY": self.toEpochDay(), "PROLEPTIC_MONTH": self._y * 12 + self._m - 1,
                 "YEAR_OF_ERA": self._y if self._y >= 1 else 1 - self._y, "ERA": 1 if self._y >= 1 else 0,
                 "ALIGNED_WEEK_OF_MONTH": (self._d - 1) // 7 + 1, "ALIGNED_DAY_OF_WEEK_IN_MONTH": (self._d - 1) % 7 + 1,
                 "ALIGNED_WEEK_OF_YEAR": (self.getDayOfYear() - 1) // 7 + 1,
                 "ALIGNED_DAY_OF_WEEK_IN_YEAR": (self.getDayOfYear() - 1) % 7 + 1}
        if name not in table:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field.toString())
        return table[name]

    def isSupported(self, what):
        return 1 if getattr(what, "_name", "") in ("DAY_OF_MONTH", "MONTH_OF_YEAR", "YEAR", "DAY_OF_YEAR", "DAY_OF_WEEK", "EPOCH_DAY", "DAYS", "YEAR_OF_ERA", "ERA",
                                                  "ALIGNED_WEEK_OF_MONTH", "ALIGNED_DAY_OF_WEEK_IN_MONTH", "ALIGNED_WEEK_OF_YEAR",
                                                  "ALIGNED_DAY_OF_WEEK_IN_YEAR", "PROLEPTIC_MONTH", "WEEKS", "MONTHS", "YEARS", "DECADES", "CENTURIES") else 0

    def atStartOfDay(self, zone=None):
        local = LocalDateTime(self, LocalTime.MIDNIGHT)
        return local if zone is None else ZonedDateTime.of(local, zone)

    def atTime(self, first, minute=None, second=0, nano=0):
        if isinstance(first, LocalTime):
            return LocalDateTime(self, first)
        return LocalDateTime(self, LocalTime.of(first, minute, second, nano))

    def isBefore(self, other):
        return 1 if self.toEpochDay() < other.toEpochDay() else 0

    def isAfter(self, other):
        return 1 if self.toEpochDay() > other.toEpochDay() else 0

    def isEqual(self, other):
        return 1 if self.toEpochDay() == other.toEpochDay() else 0

    def compareTo(self, other):
        return (self._y - other._y) or (self._m - other._m) or (self._d - other._d)

    def until(self, end, unit=None):
        if unit is None:
            total = (end._y * 12 + end._m - 1) - (self._y * 12 + self._m - 1)
            days = end._d - self._d
            if total > 0 and days < 0:
                total -= 1
                days = end.toEpochDay() - self.plusMonths(total).toEpochDay()
            elif total < 0 and days > 0:
                total += 1
                days -= end.lengthOfMonth()
            years = int(total / 12)
            return Period(years, total - years * 12, days)
        end = end.toLocalDate() if not isinstance(end, LocalDate) else end
        name = unit._name
        if name == "DAYS":
            return end.toEpochDay() - self.toEpochDay()
        if name == "WEEKS":
            return int((end.toEpochDay() - self.toEpochDay()) / 7)
        if name in _UNIT_MONTHS:
            months = (end._y * 12 + end._m - 1) - (self._y * 12 + self._m - 1)
            if months > 0 and end._d < self._d:
                months -= 1
            elif months < 0 and end._d > self._d:
                months += 1
            return int(months / _UNIT_MONTHS[name])
        runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported unit: " + unit.toString())

    def format(self, formatter):
        return formatter.format(self)

    def toLocalDate(self):
        return self

    def equals(self, other):
        return 1 if isinstance(other, LocalDate) and (other._y, other._m, other._d) == (self._y, self._m, self._d) else 0

    def hashCode(self):
        return runtime.wrap32((self._y & 0xFFFFF800) ^ ((self._y << 11) + (self._m << 6) + self._d))

    def toString(self):
        y = self._y
        year = ("%04d" % y) if 0 <= y <= 9999 else ("+%d" % y if y > 9999 else ("-%04d" % -y if y > -1000 else "%d" % y))
        return "%s-%02d-%02d" % (year, self._m, self._d)

    def datesUntil(self, end):
        return BaseStreamOf([LocalDate.ofEpochDay(d) for d in range(self.toEpochDay(), end.toEpochDay())])


def BaseStreamOf(items):
    from .jstream import BaseStream
    return BaseStream.from_items(items)


LocalDate.EPOCH = LocalDate(1970, 1, 1)
LocalDate.MIN = LocalDate(-999999999, 1, 1)
LocalDate.MAX = LocalDate(999999999, 12, 31)
setattr(LocalDate, "with", LocalDate.with_)
host_class("java.time.LocalDate", interfaces=("java.time.temporal.Temporal", "java.time.temporal.TemporalAdjuster", "java.time.chrono.ChronoLocalDate",
                                              "java.lang.Comparable", "java.io.Serializable"))(LocalDate)


class LocalTime(Object):
    def __init__(self, hour, minute, second, nano):
        self._h, self._mi, self._s, self._n = hour, minute, second, nano

    @staticmethod
    def of(hour, minute, second=0, nano=0):
        _check(hour, 0, 23, "HourOfDay")
        _check(minute, 0, 59, "MinuteOfHour")
        _check(second, 0, 59, "SecondOfMinute")
        _check(nano, 0, 999999999, "NanoOfSecond")
        return LocalTime(hour, minute, second, nano)

    @staticmethod
    def ofSecondOfDay(seconds):
        _check(seconds, 0, 86399, "SecondOfDay")
        return LocalTime(seconds // 3600, seconds // 60 % 60, seconds % 60, 0)

    @staticmethod
    def ofNanoOfDay(nanos):
        _check(nanos, 0, 86400 * 10 ** 9 - 1, "NanoOfDay")
        seconds, nano = divmod(nanos, 10 ** 9)
        return LocalTime(seconds // 3600, seconds // 60 % 60, seconds % 60, nano)

    @staticmethod
    def now(clock=None):
        zone = clock._zone if isinstance(clock, Clock) else (clock if isinstance(clock, ZoneId) else ZoneId.systemDefault())
        return ZonedDateTime.ofInstant(Instant.ofEpochMilli(_now(clock)), zone).toLocalTime()

    @staticmethod
    def parse(text, formatter=None):
        if formatter is not None:
            return formatter._parse_to(text, "time")
        match = re.match(r"(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?\Z", text)
        if match is None:
            _parse_error(text, "time")
        h, m, s, f = match.groups()
        try:
            return LocalTime.of(int(h), int(m), int(s or 0), int((f or "0").ljust(9, "0")))
        except DateTimeException as error:
            runtime.throw_new("java.time.format.DateTimeParseException", "Text '%s' could not be parsed: %s" % (text, error.getMessage()))

    def getHour(self):
        return self._h

    def getMinute(self):
        return self._mi

    def getSecond(self):
        return self._s

    def getNano(self):
        return self._n

    def toSecondOfDay(self):
        return self._h * 3600 + self._mi * 60 + self._s

    def toNanoOfDay(self):
        return self.toSecondOfDay() * 10 ** 9 + self._n

    def _plus_nanos(self, nanos):
        return LocalTime.ofNanoOfDay((self.toNanoOfDay() + nanos) % (86400 * 10 ** 9))

    def plusHours(self, n):
        return self._plus_nanos(n % 24 * 3600 * 10 ** 9)

    def plusMinutes(self, n):
        return self._plus_nanos(n % 1440 * 60 * 10 ** 9)

    def plusSeconds(self, n):
        return self._plus_nanos(n % 86400 * 10 ** 9)

    def plusNanos(self, n):
        return self._plus_nanos(n % (86400 * 10 ** 9))

    def minusHours(self, n):
        return self.plusHours(-n)

    def minusMinutes(self, n):
        return self.plusMinutes(-n)

    def minusSeconds(self, n):
        return self.plusSeconds(-n)

    def minusNanos(self, n):
        return self.plusNanos(-n)

    def plus(self, first, unit=None):
        if unit is None:
            return self._plus_nanos(first._total() % (86400 * 10 ** 9))
        return self._plus_nanos(first * _UNIT_NANOS[unit._name] % (86400 * 10 ** 9))

    def minus(self, first, unit=None):
        return self.plus(first.negated()) if unit is None else self.plus(-first, unit)

    def withHour(self, h):
        return LocalTime.of(h, self._mi, self._s, self._n)

    def withMinute(self, m):
        return LocalTime.of(self._h, m, self._s, self._n)

    def withSecond(self, s):
        return LocalTime.of(self._h, self._mi, s, self._n)

    def withNano(self, n):
        return LocalTime.of(self._h, self._mi, self._s, n)

    def truncatedTo(self, unit):
        size = _UNIT_NANOS[unit._name]
        return LocalTime.ofNanoOfDay(self.toNanoOfDay() // size * size)

    def isBefore(self, other):
        return 1 if self.toNanoOfDay() < other.toNanoOfDay() else 0

    def isAfter(self, other):
        return 1 if self.toNanoOfDay() > other.toNanoOfDay() else 0

    def compareTo(self, other):
        return (self.toNanoOfDay() > other.toNanoOfDay()) - (self.toNanoOfDay() < other.toNanoOfDay())

    def until(self, end, unit):
        return int((end.toLocalTime().toNanoOfDay() - self.toNanoOfDay()) / _UNIT_NANOS[unit._name])

    def atDate(self, date):
        return LocalDateTime(date, self)

    def get(self, field):
        return self.getLong(field)

    def getLong(self, field):
        name = field._name
        table = {"HOUR_OF_DAY": self._h, "MINUTE_OF_HOUR": self._mi, "SECOND_OF_MINUTE": self._s, "NANO_OF_SECOND": self._n,
                 "MILLI_OF_SECOND": self._n // 10 ** 6, "SECOND_OF_DAY": self.toSecondOfDay(), "NANO_OF_DAY": self.toNanoOfDay(),
                 "MINUTE_OF_DAY": self._h * 60 + self._mi, "HOUR_OF_AMPM": self._h % 12, "AMPM_OF_DAY": self._h // 12}
        if name not in table:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field.toString())
        return table[name]

    def format(self, formatter):
        return formatter.format(self)

    def toLocalTime(self):
        return self

    def equals(self, other):
        return 1 if isinstance(other, LocalTime) and other.toNanoOfDay() == self.toNanoOfDay() else 0

    def hashCode(self):
        n = self.toNanoOfDay()
        return runtime.wrap32(n ^ (n >> 32))

    def toString(self):
        out = "%02d:%02d" % (self._h, self._mi)
        if self._s or self._n:
            out += ":%02d" % self._s
            if self._n:
                out += "." + (("%03d" % (self._n // 10 ** 6)) if self._n % 10 ** 6 == 0 else (("%06d" % (self._n // 1000)) if self._n % 1000 == 0 else "%09d" % self._n))
        return out


LocalTime.MIDNIGHT = LocalTime.MIN = LocalTime(0, 0, 0, 0)
LocalTime.NOON = LocalTime(12, 0, 0, 0)
LocalTime.MAX = LocalTime(23, 59, 59, 999999999)
host_class("java.time.LocalTime", interfaces=("java.time.temporal.Temporal", "java.time.temporal.TemporalAdjuster", "java.lang.Comparable"))(LocalTime)


class LocalDateTime(Object):
    def __init__(self, date, time):
        self._date, self._time = date, time

    @staticmethod
    def of(first, month=None, day=None, hour=0, minute=0, second=0, nano=0):
        if isinstance(first, LocalDate):
            return LocalDateTime(first, month)
        return LocalDateTime(LocalDate.of(first, month, day), LocalTime.of(hour, minute, second, nano))

    @staticmethod
    def ofEpochSecond(seconds, nano, offset):
        local = seconds + offset._seconds
        return LocalDateTime(LocalDate.ofEpochDay(local // 86400), LocalTime.ofNanoOfDay((local % 86400) * 10 ** 9 + nano))

    @staticmethod
    def ofInstant(instant, zone):
        return ZonedDateTime.ofInstant(instant, zone).toLocalDateTime()

    @staticmethod
    def now(clock=None):
        zone = clock._zone if isinstance(clock, Clock) else (clock if isinstance(clock, ZoneId) else ZoneId.systemDefault())
        return ZonedDateTime.ofInstant(Instant.ofEpochMilli(_now(clock)), zone).toLocalDateTime()

    @staticmethod
    def parse(text, formatter=None):
        if formatter is not None:
            return formatter._parse_to(text, "datetime")
        if "T" not in text:
            _parse_error(text, "datetime")
        date, _, time = text.partition("T")
        return LocalDateTime(LocalDate.parse(date), LocalTime.parse(time))

    def _epoch_local(self):
        return self._date.toEpochDay() * 86400 + self._time.toSecondOfDay()

    def toLocalDate(self):
        return self._date

    def toLocalTime(self):
        return self._time

    def getYear(self):
        return self._date._y

    def getMonthValue(self):
        return self._date._m

    def getMonth(self):
        return self._date.getMonth()

    def getDayOfMonth(self):
        return self._date._d

    def getDayOfYear(self):
        return self._date.getDayOfYear()

    def getDayOfWeek(self):
        return self._date.getDayOfWeek()

    def getHour(self):
        return self._time._h

    def getMinute(self):
        return self._time._mi

    def getSecond(self):
        return self._time._s

    def getNano(self):
        return self._time._n

    def _plus_nanos(self, nanos):
        total = self._time.toNanoOfDay() + nanos
        days, rest = divmod(total, 86400 * 10 ** 9)
        return LocalDateTime(self._date.plusDays(days), LocalTime.ofNanoOfDay(rest))

    def plusYears(self, n):
        return LocalDateTime(self._date.plusYears(n), self._time)

    def plusMonths(self, n):
        return LocalDateTime(self._date.plusMonths(n), self._time)

    def plusWeeks(self, n):
        return LocalDateTime(self._date.plusWeeks(n), self._time)

    def plusDays(self, n):
        return LocalDateTime(self._date.plusDays(n), self._time)

    def plusHours(self, n):
        return self._plus_nanos(n * 3600 * 10 ** 9)

    def plusMinutes(self, n):
        return self._plus_nanos(n * 60 * 10 ** 9)

    def plusSeconds(self, n):
        return self._plus_nanos(n * 10 ** 9)

    def plusNanos(self, n):
        return self._plus_nanos(n)

    def minusYears(self, n):
        return self.plusYears(-n)

    def minusMonths(self, n):
        return self.plusMonths(-n)

    def minusWeeks(self, n):
        return self.plusWeeks(-n)

    def minusDays(self, n):
        return self.plusDays(-n)

    def minusHours(self, n):
        return self.plusHours(-n)

    def minusMinutes(self, n):
        return self.plusMinutes(-n)

    def minusSeconds(self, n):
        return self.plusSeconds(-n)

    def plus(self, first, unit=None):
        if unit is None:
            if isinstance(first, Period):
                return LocalDateTime(self._date.plus(first), self._time)
            return self._plus_nanos(first._total())
        if unit._name in _UNIT_NANOS and unit._name not in ("DAYS", "WEEKS"):
            return self._plus_nanos(first * _UNIT_NANOS[unit._name])
        return LocalDateTime(self._date.plus(first, unit), self._time)

    def minus(self, first, unit=None):
        return self.plus(first.negated()) if unit is None else self.plus(-first, unit)

    def withYear(self, v):
        return LocalDateTime(self._date.withYear(v), self._time)

    def withMonth(self, v):
        return LocalDateTime(self._date.withMonth(v), self._time)

    def withDayOfMonth(self, v):
        return LocalDateTime(self._date.withDayOfMonth(v), self._time)

    def withHour(self, v):
        return LocalDateTime(self._date, self._time.withHour(v))

    def withMinute(self, v):
        return LocalDateTime(self._date, self._time.withMinute(v))

    def withSecond(self, v):
        return LocalDateTime(self._date, self._time.withSecond(v))

    def withNano(self, v):
        return LocalDateTime(self._date, self._time.withNano(v))

    def truncatedTo(self, unit):
        if unit._name == "DAYS":
            return LocalDateTime(self._date, LocalTime.MIDNIGHT)
        return LocalDateTime(self._date, self._time.truncatedTo(unit))

    def atZone(self, zone):
        return ZonedDateTime.of(self, zone)

    def atOffset(self, offset):
        return OffsetDateTime(self, offset)

    def toEpochSecond(self, offset):
        return self._epoch_local() - offset._seconds

    def toInstant(self, offset):
        return Instant(self.toEpochSecond(offset), self._time._n)

    def isBefore(self, other):
        return 1 if self.compareTo(other) < 0 else 0

    def isAfter(self, other):
        return 1 if self.compareTo(other) > 0 else 0

    def isEqual(self, other):
        return 1 if self.compareTo(other) == 0 else 0

    def compareTo(self, other):
        return self._date.compareTo(other._date) or self._time.compareTo(other._time)

    def until(self, end, unit):
        end = end.toLocalDateTime() if not isinstance(end, LocalDateTime) else end
        name = unit._name
        if name in _UNIT_NANOS:
            nanos = (end._date.toEpochDay() - self._date.toEpochDay()) * 86400 * 10 ** 9 + end._time.toNanoOfDay() - self._time.toNanoOfDay()
            return int(nanos / _UNIT_NANOS[name])
        end_date = end._date
        if end_date.isAfter(self._date) and end._time.isBefore(self._time):
            end_date = end_date.minusDays(1)
        elif end_date.isBefore(self._date) and end._time.isAfter(self._time):
            end_date = end_date.plusDays(1)
        return self._date.until(end_date, unit)

    def get(self, field):
        return self.getLong(field)

    def getLong(self, field):
        try:
            return self._time.getLong(field)
        except DateTimeException:
            return self._date.getLong(field)

    def format(self, formatter):
        return formatter.format(self)

    def toLocalDateTime(self):
        return self

    def equals(self, other):
        return 1 if isinstance(other, LocalDateTime) and other._date.equals(self._date) and other._time.equals(self._time) else 0

    def hashCode(self):
        return self._date.hashCode() ^ self._time.hashCode()

    def toString(self):
        return self._date.toString() + "T" + self._time.toString()


LocalDateTime.MIN = LocalDateTime(LocalDate.MIN, LocalTime.MIN)
LocalDateTime.MAX = LocalDateTime(LocalDate.MAX, LocalTime.MAX)
host_class("java.time.LocalDateTime", interfaces=("java.time.temporal.Temporal", "java.time.chrono.ChronoLocalDateTime", "java.lang.Comparable"))(LocalDateTime)


class Instant(Object):
    def __init__(self, seconds, nanos=0):
        seconds += nanos // 10 ** 9
        self._s, self._n = seconds, nanos % 10 ** 9

    @staticmethod
    def now(clock=None):
        return Instant.ofEpochMilli(_now(clock))

    @staticmethod
    def ofEpochSecond(seconds, adjust=0):
        return Instant(seconds, adjust)

    @staticmethod
    def ofEpochMilli(millis):
        return Instant(millis // 1000, millis % 1000 * 10 ** 6)

    @staticmethod
    def parse(text, formatter=None):
        match = re.match(r"(-?\d{4,9})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:\d{2})\Z", text)
        if match is None:
            _parse_error(text, "instant")
        y, mo, d, h, mi, s, f, z = match.groups()
        local = LocalDateTime.of(int(y), int(mo), int(d), int(h), int(mi), int(s or 0), int((f or "0").ljust(9, "0")))
        return local.toInstant(ZoneOffset.of(z))

    def getEpochSecond(self):
        return self._s

    def getNano(self):
        return self._n

    def toEpochMilli(self):
        return self._s * 1000 + self._n // 10 ** 6

    def _total(self):
        return self._s * 10 ** 9 + self._n

    def plusSeconds(self, n):
        return Instant(self._s + n, self._n)

    def plusMillis(self, n):
        return Instant(self._s, self._n + n * 10 ** 6)

    def plusNanos(self, n):
        return Instant(self._s, self._n + n)

    def minusSeconds(self, n):
        return self.plusSeconds(-n)

    def minusMillis(self, n):
        return self.plusMillis(-n)

    def minusNanos(self, n):
        return self.plusNanos(-n)

    def plus(self, first, unit=None):
        if unit is None:
            return Instant(self._s, self._n + first._total())
        if unit._name not in _UNIT_NANOS:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported unit: " + unit.toString())
        return Instant(self._s, self._n + first * _UNIT_NANOS[unit._name])

    def minus(self, first, unit=None):
        return self.plus(first.negated()) if unit is None else self.plus(-first, unit)

    def truncatedTo(self, unit):
        size = _UNIT_NANOS[unit._name]
        return Instant(0, self._total() // size * size)

    def isBefore(self, other):
        return 1 if self._total() < other._total() else 0

    def isAfter(self, other):
        return 1 if self._total() > other._total() else 0

    def compareTo(self, other):
        return (self._total() > other._total()) - (self._total() < other._total())

    def until(self, end, unit):
        return int((end._total() - self._total()) / _UNIT_NANOS[unit._name])

    def atZone(self, zone):
        return ZonedDateTime.ofInstant(self, zone)

    def atOffset(self, offset):
        return OffsetDateTime.ofInstant(self, offset)

    def get(self, field):
        return self.getLong(field)

    def getLong(self, field):
        return {"INSTANT_SECONDS": self._s, "NANO_OF_SECOND": self._n, "MILLI_OF_SECOND": self._n // 10 ** 6}[field._name]

    def equals(self, other):
        return 1 if isinstance(other, Instant) and other._total() == self._total() else 0

    def hashCode(self):
        return runtime.wrap32((self._s ^ (self._s >> 32)) + 51 * self._n)

    def toString(self):
        local = LocalDateTime.ofEpochSecond(self._s, self._n, ZoneOffset.UTC)
        text = local.toString()
        if local._time._s == 0 and local._time._n == 0:
            text += ":00"
        return text + "Z"


Instant.EPOCH = Instant(0)
host_class("java.time.Instant", interfaces=("java.time.temporal.Temporal", "java.time.temporal.TemporalAdjuster", "java.lang.Comparable"))(Instant)


def _now(clock):
    if isinstance(clock, Clock):
        return clock._millis()
    return int(_time.time() * 1000)


class Clock(Object):
    def __init__(self, zone, fixed=None, offset=0):
        self._zone, self._fixed, self._offset = zone, fixed, offset

    @staticmethod
    def systemUTC():
        return Clock(ZoneOffset.UTC)

    @staticmethod
    def systemDefaultZone():
        return Clock(ZoneId.systemDefault())

    @staticmethod
    def system(zone):
        return Clock(zone)

    @staticmethod
    def fixed(instant, zone):
        return Clock(zone, instant.toEpochMilli())

    @staticmethod
    def offset(clock, duration):
        return Clock(clock._zone, clock._fixed, clock._offset + duration.toMillis())

    def _millis(self):
        return (self._fixed if self._fixed is not None else int(_time.time() * 1000)) + self._offset

    def millis(self):
        return self._millis()

    def instant(self):
        return Instant.ofEpochMilli(self._millis())

    def getZone(self):
        return self._zone

    def withZone(self, zone):
        return Clock(zone, self._fixed, self._offset)


host_class("java.time.Clock")(Clock)


class ZonedDateTime(Object):
    def __init__(self, local, offset, zone):
        self._local, self._offset, self._zone = local, offset, zone

    @staticmethod
    def of(first, zone_or_month=None, *rest):
        if isinstance(first, LocalDateTime):
            zone = zone_or_month
        elif isinstance(first, LocalDate):
            first, zone = LocalDateTime(first, zone_or_month), rest[0]
        else:
            zone = rest[-1]
            first = LocalDateTime.of(first, zone_or_month, *rest[:-1])
        utc = zone._zone.local_to_utc(first._epoch_local() * 1000)
        offset = ZoneOffset.ofTotalSeconds(zone._zone.offset(utc) // 1000)
        # a time in a gap moves forward by the gap, as java.time does
        real = LocalDateTime.ofEpochSecond(utc // 1000, first._time._n, offset)
        return ZonedDateTime(real, offset, zone)

    @staticmethod
    def ofInstant(instant, zone):
        offset = ZoneOffset.ofTotalSeconds(zone._zone.offset(instant._s * 1000) // 1000)
        return ZonedDateTime(LocalDateTime.ofEpochSecond(instant._s, instant._n, offset), offset, zone)

    @staticmethod
    def now(clock=None):
        zone = clock._zone if isinstance(clock, Clock) else (clock if isinstance(clock, ZoneId) else ZoneId.systemDefault())
        return ZonedDateTime.ofInstant(Instant.ofEpochMilli(_now(clock)), zone)

    @staticmethod
    def parse(text, formatter=None):
        if formatter is not None:
            return formatter._parse_to(text, "zoned")
        match = re.match(r"(.+?)(Z|[+-]\d{2}:\d{2})(?:\[(.+)\])?\Z", text)
        if match is None:
            _parse_error(text, "zoned")
        local = LocalDateTime.parse(match.group(1))
        offset = ZoneOffset.of(match.group(2))
        zone = ZoneId.of(match.group(3)) if match.group(3) else offset
        return ZonedDateTime.ofInstant(local.toInstant(offset), zone)

    def toLocalDateTime(self):
        return self._local

    def toLocalDate(self):
        return self._local._date

    def toLocalTime(self):
        return self._local._time

    def getOffset(self):
        return self._offset

    def getZone(self):
        return self._zone

    def toInstant(self):
        return self._local.toInstant(self._offset)

    def toEpochSecond(self):
        return self._local.toEpochSecond(self._offset)

    def toOffsetDateTime(self):
        return OffsetDateTime(self._local, self._offset)

    def withZoneSameInstant(self, zone):
        return ZonedDateTime.ofInstant(self.toInstant(), zone)

    def withZoneSameLocal(self, zone):
        return ZonedDateTime.of(self._local, zone)

    def _local_op(self, name, *args):
        return ZonedDateTime.of(getattr(self._local, name)(*args), self._zone)

    def _instant_op(self, name, *args):
        return ZonedDateTime.ofInstant(getattr(self.toInstant(), name)(*args), self._zone)

    def plusYears(self, n):
        return self._local_op("plusYears", n)

    def plusMonths(self, n):
        return self._local_op("plusMonths", n)

    def plusWeeks(self, n):
        return self._local_op("plusWeeks", n)

    def plusDays(self, n):
        return self._local_op("plusDays", n)

    def plusHours(self, n):
        return self._instant_op("plusSeconds", n * 3600)

    def plusMinutes(self, n):
        return self._instant_op("plusSeconds", n * 60)

    def plusSeconds(self, n):
        return self._instant_op("plusSeconds", n)

    def plusNanos(self, n):
        return self._instant_op("plusNanos", n)

    def minusYears(self, n):
        return self.plusYears(-n)

    def minusMonths(self, n):
        return self.plusMonths(-n)

    def minusWeeks(self, n):
        return self.plusWeeks(-n)

    def minusDays(self, n):
        return self.plusDays(-n)

    def minusHours(self, n):
        return self.plusHours(-n)

    def minusMinutes(self, n):
        return self.plusMinutes(-n)

    def minusSeconds(self, n):
        return self.plusSeconds(-n)

    def plus(self, first, unit=None):
        if unit is None:
            return self._local_op("plus", first) if isinstance(first, Period) else self._instant_op("plus", first)
        if unit._name in _UNIT_NANOS and unit._name not in ("DAYS", "WEEKS"):
            return self._instant_op("plus", first, unit)
        return self._local_op("plus", first, unit)

    def minus(self, first, unit=None):
        return self.plus(first.negated()) if unit is None else self.plus(-first, unit)

    def getYear(self):
        return self._local.getYear()

    def getMonthValue(self):
        return self._local.getMonthValue()

    def getMonth(self):
        return self._local.getMonth()

    def getDayOfMonth(self):
        return self._local.getDayOfMonth()

    def getDayOfYear(self):
        return self._local.getDayOfYear()

    def getDayOfWeek(self):
        return self._local.getDayOfWeek()

    def getHour(self):
        return self._local.getHour()

    def getMinute(self):
        return self._local.getMinute()

    def getSecond(self):
        return self._local.getSecond()

    def getNano(self):
        return self._local.getNano()

    def withHour(self, v):
        return self._local_op("withHour", v)

    def withMinute(self, v):
        return self._local_op("withMinute", v)

    def withSecond(self, v):
        return self._local_op("withSecond", v)

    def withDayOfMonth(self, v):
        return self._local_op("withDayOfMonth", v)

    def withMonth(self, v):
        return self._local_op("withMonth", v)

    def withYear(self, v):
        return self._local_op("withYear", v)

    def truncatedTo(self, unit):
        return self._local_op("truncatedTo", unit)

    def isBefore(self, other):
        return self.toInstant().isBefore(other.toInstant())

    def isAfter(self, other):
        return self.toInstant().isAfter(other.toInstant())

    def isEqual(self, other):
        return 1 if self.toInstant().equals(other.toInstant()) else 0

    def compareTo(self, other):
        return self.toInstant().compareTo(other.toInstant()) or self._local.compareTo(other._local)

    def until(self, end, unit):
        end = end if isinstance(end, ZonedDateTime) else end.atZone(self._zone)
        if unit._name in _UNIT_NANOS and unit._name not in ("DAYS", "WEEKS"):
            return self.toInstant().until(end.toInstant(), unit)
        return self._local.until(end.withZoneSameInstant(self._zone)._local, unit)

    def get(self, field):
        return self.getLong(field)

    def getLong(self, field):
        if field._name == "OFFSET_SECONDS":
            return self._offset._seconds
        if field._name == "INSTANT_SECONDS":
            return self.toEpochSecond()
        return self._local.getLong(field)

    def format(self, formatter):
        return formatter.format(self)

    def equals(self, other):
        return 1 if isinstance(other, ZonedDateTime) and other._local.equals(self._local) and other._offset.equals(self._offset) \
            and other._zone.equals(self._zone) else 0

    def hashCode(self):
        return self._local.hashCode() ^ self._offset.hashCode() ^ ((self._zone.hashCode() << 3 | self._zone.hashCode() >> 29) & 0xFFFFFFFF)

    def toString(self):
        text = self._local.toString() + self._offset.toString()
        if isinstance(self._zone, ZoneOffset) is False or self._zone is not self._offset:
            if self._zone._id != self._offset._id:
                text += "[" + self._zone._id + "]"
        if self._local._time._s == 0 and self._local._time._n == 0:
            text = self._local._date.toString() + "T" + "%02d:%02d" % (self._local._time._h, self._local._time._mi) + self._offset.toString() + (
                "[" + self._zone._id + "]" if self._zone._id != self._offset._id else "")
        return text


host_class("java.time.ZonedDateTime", interfaces=("java.time.temporal.Temporal", "java.time.chrono.ChronoZonedDateTime", "java.lang.Comparable"))(ZonedDateTime)


class OffsetDateTime(Object):
    def __init__(self, local, offset):
        self._local, self._offset = local, offset

    @staticmethod
    def of(first, offset_or_month=None, *rest):
        if isinstance(first, LocalDateTime):
            return OffsetDateTime(first, offset_or_month)
        return OffsetDateTime(LocalDateTime.of(first, offset_or_month, *rest[:-1]), rest[-1])

    @staticmethod
    def ofInstant(instant, zone):
        offset = ZoneOffset.ofTotalSeconds(zone._zone.offset(instant._s * 1000) // 1000)
        return OffsetDateTime(LocalDateTime.ofEpochSecond(instant._s, instant._n, offset), offset)

    @staticmethod
    def now(clock=None):
        return ZonedDateTime.now(clock).toOffsetDateTime()

    @staticmethod
    def parse(text, formatter=None):
        if formatter is not None:
            return formatter._parse_to(text, "offset")
        return ZonedDateTime.parse(text).toOffsetDateTime()

    def toLocalDateTime(self):
        return self._local

    def toLocalDate(self):
        return self._local._date

    def toLocalTime(self):
        return self._local._time

    def getOffset(self):
        return self._offset

    def toInstant(self):
        return self._local.toInstant(self._offset)

    def toEpochSecond(self):
        return self._local.toEpochSecond(self._offset)

    def toZonedDateTime(self):
        return ZonedDateTime(self._local, self._offset, self._offset)

    def atZoneSameInstant(self, zone):
        return ZonedDateTime.ofInstant(self.toInstant(), zone)

    def withOffsetSameInstant(self, offset):
        return OffsetDateTime.ofInstant(self.toInstant(), offset)

    def plus(self, *args):
        return OffsetDateTime(self._local.plus(*args), self._offset)

    def minus(self, *args):
        return OffsetDateTime(self._local.minus(*args), self._offset)

    def plusDays(self, n):
        return OffsetDateTime(self._local.plusDays(n), self._offset)

    def plusHours(self, n):
        return OffsetDateTime(self._local.plusHours(n), self._offset)

    def plusMinutes(self, n):
        return OffsetDateTime(self._local.plusMinutes(n), self._offset)

    def plusSeconds(self, n):
        return OffsetDateTime(self._local.plusSeconds(n), self._offset)

    def getYear(self):
        return self._local.getYear()

    def getMonthValue(self):
        return self._local.getMonthValue()

    def getDayOfMonth(self):
        return self._local.getDayOfMonth()

    def getHour(self):
        return self._local.getHour()

    def getMinute(self):
        return self._local.getMinute()

    def getSecond(self):
        return self._local.getSecond()

    def isBefore(self, other):
        return self.toInstant().isBefore(other.toInstant())

    def isAfter(self, other):
        return self.toInstant().isAfter(other.toInstant())

    def compareTo(self, other):
        return self.toInstant().compareTo(other.toInstant()) or self._local.compareTo(other._local)

    def format(self, formatter):
        return formatter.format(self)

    def equals(self, other):
        return 1 if isinstance(other, OffsetDateTime) and other._local.equals(self._local) and other._offset.equals(self._offset) else 0

    def hashCode(self):
        return self._local.hashCode() ^ self._offset.hashCode()

    def toString(self):
        return self._local.toString() + self._offset.toString()


host_class("java.time.OffsetDateTime", interfaces=("java.time.temporal.Temporal", "java.lang.Comparable"))(OffsetDateTime)


class Year(Object):
    def __init__(self, value):
        self._v = value

    of = staticmethod(lambda v: Year(v))
    now = staticmethod(lambda clock=None: Year(LocalDate.now(clock)._y))
    isLeap = staticmethod(lambda y: 1 if is_leap(y) else 0)
    parse = staticmethod(lambda text: Year(int(text)))

    def getValue(self):
        return self._v

    def isLeap_(self):
        return 1 if is_leap(self._v) else 0

    def length(self):
        return 366 if is_leap(self._v) else 365

    def plusYears(self, n):
        return Year(self._v + n)

    def minusYears(self, n):
        return Year(self._v - n)

    def atDay(self, day):
        return LocalDate.ofYearDay(self._v, day)

    def atMonth(self, month):
        return YearMonth(self._v, month if isinstance(month, int) else month._ordinal + 1)

    def isBefore(self, other):
        return 1 if self._v < other._v else 0

    def isAfter(self, other):
        return 1 if self._v > other._v else 0

    def compareTo(self, other):
        return self._v - other._v

    def equals(self, other):
        return 1 if isinstance(other, Year) and other._v == self._v else 0

    def hashCode(self):
        return self._v

    def toString(self):
        return str(self._v)


host_class("java.time.Year", interfaces=("java.time.temporal.Temporal", "java.lang.Comparable"))(Year)


class YearMonth(Object):
    def __init__(self, year, month):
        self._y, self._m = year, month

    @staticmethod
    def of(year, month):
        return YearMonth(year, _check(month._ordinal + 1 if isinstance(month, _Enum) else month, 1, 12, "MonthOfYear"))

    @staticmethod
    def now(clock=None):
        d = LocalDate.now(clock)
        return YearMonth(d._y, d._m)

    @staticmethod
    def from_(date):
        return YearMonth(date._y, date._m) if hasattr(date, "_y") else YearMonth(date.getYear(), date.getMonthValue())

    @staticmethod
    def parse(text):
        match = re.match(r"(-?\d{4,9})-(\d{2})\Z", text)
        if match is None:
            _parse_error(text, "yearmonth")
        return YearMonth.of(int(match.group(1)), int(match.group(2)))

    def getYear(self):
        return self._y

    def getMonthValue(self):
        return self._m

    def getMonth(self):
        return Month._all[self._m - 1]

    def lengthOfMonth(self):
        return month_length(self._y, self._m - 1)

    def lengthOfYear(self):
        return 366 if is_leap(self._y) else 365

    def isLeapYear(self):
        return 1 if is_leap(self._y) else 0

    def atDay(self, day):
        return LocalDate.of(self._y, self._m, day)

    def atEndOfMonth(self):
        return LocalDate(self._y, self._m, self.lengthOfMonth())

    def plusMonths(self, n):
        total = self._y * 12 + self._m - 1 + n
        return YearMonth(total // 12, total % 12 + 1)

    def minusMonths(self, n):
        return self.plusMonths(-n)

    def plusYears(self, n):
        return YearMonth(self._y + n, self._m)

    def minusYears(self, n):
        return self.plusYears(-n)

    def isBefore(self, other):
        return 1 if self.compareTo(other) < 0 else 0

    def isAfter(self, other):
        return 1 if self.compareTo(other) > 0 else 0

    def compareTo(self, other):
        return (self._y - other._y) or (self._m - other._m)

    def format(self, formatter):
        return formatter.format(self.atDay(1))

    def equals(self, other):
        return 1 if isinstance(other, YearMonth) and (other._y, other._m) == (self._y, self._m) else 0

    def hashCode(self):
        return self._y ^ (self._m << 27)

    def toString(self):
        return "%04d-%02d" % (self._y, self._m)


setattr(YearMonth, "from", YearMonth.from_)
host_class("java.time.YearMonth", interfaces=("java.time.temporal.Temporal", "java.lang.Comparable"))(YearMonth)


class TemporalAdjusters(Object):
    @staticmethod
    def firstDayOfMonth():
        return lambda d: d.withDayOfMonth(1)

    @staticmethod
    def lastDayOfMonth():
        return lambda d: d.withDayOfMonth(d.toLocalDate().lengthOfMonth())

    @staticmethod
    def firstDayOfNextMonth():
        return lambda d: d.withDayOfMonth(1).plusMonths(1)

    @staticmethod
    def firstDayOfYear():
        return lambda d: d.withMonth(1).withDayOfMonth(1)

    @staticmethod
    def lastDayOfYear():
        return lambda d: d.withMonth(12).withDayOfMonth(31)

    @staticmethod
    def firstDayOfNextYear():
        return lambda d: d.withMonth(1).withDayOfMonth(1).plusYears(1)

    @staticmethod
    def next(day):
        return lambda d: d.plusDays((day._ordinal - d.getDayOfWeek()._ordinal - 1) % 7 + 1)

    @staticmethod
    def nextOrSame(day):
        return lambda d: d.plusDays((day._ordinal - d.getDayOfWeek()._ordinal) % 7)

    @staticmethod
    def previous(day):
        return lambda d: d.minusDays((d.getDayOfWeek()._ordinal - day._ordinal - 1) % 7 + 1)

    @staticmethod
    def previousOrSame(day):
        return lambda d: d.minusDays((d.getDayOfWeek()._ordinal - day._ordinal) % 7)


host_class("java.time.temporal.TemporalAdjusters", final=True)(TemporalAdjusters)


def _adjust(self, adjuster):
    return adjuster(self) if callable(adjuster) and not hasattr(adjuster, "adjustInto") else adjuster.adjustInto(self)


_LOCAL_DATE_WITH = LocalDate.with_
for _cls in (LocalDate, LocalDateTime, ZonedDateTime):
    _cls.with_ = (lambda cls: lambda self, a, v=None: (
        _adjust(self, a) if v is None else (_LOCAL_DATE_WITH(self, a, v) if cls is LocalDate else
                                           type(self)(self._date.with_(a, v), self._time) if cls is LocalDateTime else self)))(_cls)
    setattr(_cls, "with", _cls.with_)



