"""java.time.chrono: Chronology with IsoChronology, MinguoChronology, ThaiBuddhistChronology and JapaneseChronology, the dates and eras of
each, and java.time.temporal.TemporalQueries

a date of a chronology other than ISO keeps the ISO LocalDate it stands for and shows the year, the era and the year of the era of its
calendar; months and days are those of the ISO calendar, as they are in these calendars. the Hijrah calendar needs the table of the
Umm al-Qura calendar and is not here"""

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jlang import Object, jstr
from .jtimeapi import (ChronoField, ChronoUnit, DateTimeException, Instant, LocalDate, LocalDateTime, LocalTime, OffsetDateTime, Period,
                       TextStyle, Year, ZonedDateTime, ZoneId, ZoneOffset, _make_enum, _field_range)
from .jutil import check_nonnull


def _dt_error(message):
    runtime.throw_new("java.time.DateTimeException", message)


def _iso_date(temporal):
    """the LocalDate of a temporal, an object of any chronology"""
    if isinstance(temporal, LocalDate):
        return temporal
    if isinstance(temporal, _ChronoDate):
        return temporal._d
    if hasattr(temporal, "toLocalDate"):
        return temporal.toLocalDate()
    from .jtimefmt import Parsed
    if isinstance(temporal, Parsed) and temporal.date is not None:
        return temporal.date
    _dt_error("Unable to obtain ChronoLocalDate from TemporalAccessor: %s of type %s" % (
        temporal.toString(), runtime.class_of(temporal).getName()))


IsoEra = _make_enum("java.time.chrono.IsoEra", ["BCE", "CE"])
MinguoEra = _make_enum("java.time.chrono.MinguoEra", ["BEFORE_ROC", "ROC"])
ThaiBuddhistEra = _make_enum("java.time.chrono.ThaiBuddhistEra", ["BEFORE_BE", "BE"])
host_class("java.time.chrono.Era", interface=True)(type("Era", (), {"__slots__": ()}))


def _era_methods(cls, names, full_names, narrow_names):
    cls.getValue = lambda self: self._ordinal
    cls.of = staticmethod(lambda n: cls._all[n] if n in (0, 1) else _dt_error("Invalid era: %d" % n))
    cls.getDisplayName = lambda self, style, locale=None: jstr(
        full_names[self._ordinal] if style._name.startswith("FULL") else narrow_names[self._ordinal] if style._name.startswith("NARROW")
        else names[self._ordinal])
    cls._era_text = staticmethod(lambda: {i: (names[i], full_names[i], narrow_names[i]) for i in (0, 1)})
    cls.getLong = lambda self, field: self._ordinal if field._name == "ERA" else _dt_error("Unsupported field: " + field.toString())
    cls.get = cls.getLong
    cls.isSupported = lambda self, field: 1 if getattr(field, "_name", "") == "ERA" else 0


_era_methods(IsoEra, ["BC", "AD"], ["Before Christ", "Anno Domini"], ["B", "A"])
_era_methods(MinguoEra, ["B.R.O.C.", "Minguo"], ["B.R.O.C.", "Minguo"], ["B.R.O.C.", "Minguo"])
_era_methods(ThaiBuddhistEra, ["BC", "BE"], ["BC", "BE"], ["BC", "BE"])


@host_class("java.time.chrono.JapaneseEra", final=True, interfaces=("java.time.chrono.Era", "java.io.Serializable"))
class JapaneseEra(Object):
    # name, since (iso date), value
    _ERAS = [("Meiji", (1868, 1, 1), -1), ("Taisho", (1912, 7, 30), 0), ("Showa", (1926, 12, 25), 1), ("Heisei", (1989, 1, 8), 2),
             ("Reiwa", (2019, 5, 1), 3)]
    _SHOWN = {"Taisho": "Taish\u014d", "Showa": "Sh\u014dwa"}

    def __init__(self, name, since, value):
        self._name, self._since, self._value = name, LocalDate.of(*since), value

    def getValue(self):
        return self._value

    def getDisplayName(self, style, locale=None):
        shown = JapaneseEra._SHOWN.get(self._name, self._name)
        return jstr(shown if not style._name.startswith("NARROW") else self._name[0])

    def getLong(self, field):
        if field._name == "ERA":
            return self._value
        _dt_error("Unsupported field: " + field.toString())

    get = getLong

    def isSupported(self, field):
        return 1 if getattr(field, "_name", "") == "ERA" else 0

    def name(self):
        return self._name

    def toString(self):
        return self._name

    def equals(self, other):
        return 1 if other is self else 0

    def hashCode(self):
        return self._value

    @staticmethod
    def of(value):
        for era in JapaneseEra._all:
            if era._value == value:
                return era
        _dt_error("Invalid era: %d" % value)

    @staticmethod
    def valueOf(name):
        for era in JapaneseEra._all:
            if era._name == name:
                return era
        runtime.throw_new("java.lang.IllegalArgumentException", "japaneseEra is invalid")

    @staticmethod
    def values():
        from .jutil import to_array
        return to_array(list(JapaneseEra._all), "[Ljava/time/chrono/JapaneseEra;")

    @staticmethod
    def from_(date):
        d = _iso_date(date)
        if d.isBefore(LocalDate.of(1868, 1, 1)):
            _dt_error("JapaneseDate before Meiji 6 is not supported")
        found = None
        for era in JapaneseEra._all:
            if not d.isBefore(era._since):
                found = era
        return found


JapaneseEra._all = [JapaneseEra(*row) for row in JapaneseEra._ERAS]
for _era in JapaneseEra._all:
    setattr(JapaneseEra, _era._name.upper(), _era)
setattr(JapaneseEra, "from", JapaneseEra.from_)


class _ChronoDate(Object):
    """a date of a chronology: the ISO date and the calendar of its year numbers"""

    _CHRONO = None
    _NO_ALIGNED = False

    def __init__(self, iso):
        self._d = iso

    def getChronology(self):
        return type(self)._CHRONO

    # year numbers of the calendar

    def _prolept(self):
        return self._CHRONO.prolepticOf(self._d)

    def _yoe(self):
        return self._CHRONO.yearOfEraOf(self._d)

    def getEra(self):
        return self._CHRONO.eraOfDate(self._d)

    def getLong(self, field):
        name = getattr(field, "_name", None)
        if self._NO_ALIGNED and name in self._ALIGNED:
            runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field.toString())
        if name == "YEAR":
            return self._prolept()
        if name == "YEAR_OF_ERA":
            return self._yoe()
        if name == "ERA":
            return self.getEra().getValue()
        if name == "PROLEPTIC_MONTH":
            return self._prolept() * 12 + self._d._m - 1
        if name in ("MONTH_OF_YEAR", "DAY_OF_MONTH", "DAY_OF_YEAR", "DAY_OF_WEEK", "EPOCH_DAY", "ALIGNED_WEEK_OF_MONTH",
                    "ALIGNED_DAY_OF_WEEK_IN_MONTH", "ALIGNED_WEEK_OF_YEAR", "ALIGNED_DAY_OF_WEEK_IN_YEAR"):
            return self._d.getLong(field)
        runtime.throw_new("java.time.temporal.UnsupportedTemporalTypeException", "Unsupported field: " + field.toString())

    def get(self, field):
        return self.getLong(field)

    _ALIGNED = ("ALIGNED_WEEK_OF_MONTH", "ALIGNED_DAY_OF_WEEK_IN_MONTH", "ALIGNED_WEEK_OF_YEAR", "ALIGNED_DAY_OF_WEEK_IN_YEAR")

    def isSupported(self, what):
        name = getattr(what, "_name", "")
        if self._NO_ALIGNED and name in self._ALIGNED:
            return 0
        if name in ("YEAR", "YEAR_OF_ERA", "ERA", "PROLEPTIC_MONTH", "MONTH_OF_YEAR", "DAY_OF_MONTH", "DAY_OF_YEAR", "DAY_OF_WEEK", "EPOCH_DAY",
                    "ALIGNED_WEEK_OF_MONTH", "ALIGNED_DAY_OF_WEEK_IN_MONTH", "ALIGNED_WEEK_OF_YEAR", "ALIGNED_DAY_OF_WEEK_IN_YEAR",
                    "DAYS", "WEEKS", "MONTHS", "YEARS", "DECADES", "CENTURIES", "MILLENNIA", "ERAS"):
            return 1
        return 0

    def range(self, field):
        if field._name == "DAY_OF_MONTH":
            from .jmore2 import ValueRange
            return ValueRange.of(1, self.lengthOfMonth())
        if field._name == "DAY_OF_YEAR":
            from .jmore2 import ValueRange
            return ValueRange.of(1, self.lengthOfYear())
        return self._CHRONO.range(field)

    def lengthOfMonth(self):
        return self._d.lengthOfMonth()

    def lengthOfYear(self):
        return self._d.lengthOfYear()

    def isLeapYear(self):
        return self._d.isLeapYear()

    def toEpochDay(self):
        return self._d.toEpochDay()

    def toLocalDate(self):
        return self._d

    def _wrap(self, iso):
        return self._CHRONO.date_of_iso(iso)

    def plus(self, amount, unit=None):
        if unit is None:
            return self._wrap(self._d.plus(amount) if not hasattr(amount, "addTo") else amount.addTo(self._d))
        return self._wrap(self._d.plus(amount, unit))

    def minus(self, amount, unit=None):
        if unit is None:
            return self._wrap(self._d.minus(amount))
        return self._wrap(self._d.minus(amount, unit))

    def plusDays(self, n):
        return self._wrap(self._d.plusDays(n))

    def plusWeeks(self, n):
        return self._wrap(self._d.plusWeeks(n))

    def plusMonths(self, n):
        return self._wrap(self._d.plusMonths(n))

    def plusYears(self, n):
        return self._wrap(self._d.plusYears(n))

    def minusDays(self, n):
        return self._wrap(self._d.minusDays(n))

    def minusWeeks(self, n):
        return self._wrap(self._d.minusWeeks(n))

    def minusMonths(self, n):
        return self._wrap(self._d.minusMonths(n))

    def minusYears(self, n):
        return self._wrap(self._d.minusYears(n))

    def _with(self, adjuster, value=None):
        if value is None:
            return self._wrap(self._d.with_(adjuster if not isinstance(adjuster, _ChronoDate) else adjuster._d))
        name = adjuster._name
        if name == "YEAR":
            return self._wrap(self._d.withYear(self._CHRONO.isoYear(value)))
        if name == "YEAR_OF_ERA":
            return self._wrap(self._d.withYear(self._CHRONO.isoYearFor(self.getEra(), value)))
        if name == "ERA":
            return self._wrap(self._d.withYear(self._CHRONO.isoYearFor(self._CHRONO.eraOf(value), self._yoe())))
        return self._wrap(self._d.with_(adjuster, value))

    def withDayOfMonth(self, n):
        return self._wrap(self._d.withDayOfMonth(n))

    def with_(self, adjuster, value=None):
        return self._with(adjuster, value)

    def withMonth(self, n):
        return self._wrap(self._d.withMonth(n))

    def withDayOfYear(self, n):
        return self._wrap(self._d.withDayOfYear(n))

    def withYear(self, year):
        return self._with(ChronoField.YEAR, year)

    def until(self, end, unit=None):
        if unit is None:
            p = self._d.until(_iso_date(end))
            return ChronoPeriodImpl(self._CHRONO, p._y, p._m, p._d)
        return self._d.until(_iso_date(end), unit)

    def isBefore(self, other):
        return self._d.isBefore(_iso_date(other))

    def isAfter(self, other):
        return self._d.isAfter(_iso_date(other))

    def isEqual(self, other):
        return self._d.isEqual(_iso_date(other))

    def compareTo(self, other):
        r = self._d.compareTo(_iso_date(other))
        return r

    def atTime(self, time):
        return ChronoDateTime(self, time)

    def format(self, formatter):
        return formatter.withChronology(self._CHRONO).format(self._d)

    def query(self, query):
        return query.queryFrom(self)

    def equals(self, other):
        return 1 if isinstance(other, _ChronoDate) and type(other) is type(self) and other._d.equals(self._d) else 0

    def hashCode(self):
        return runtime.wrap32(self._CHRONO.hashCode() ^ self._d.hashCode())

    def toString(self):
        yoe, moy, dom = self._yoe(), self._d._m, self._d._d
        return jstr("%s %s %d%s%d%s%d" % (self._CHRONO.toString(), self.getEra().toString(), yoe, "-0" if moy < 10 else "-", moy,
                                          "-0" if dom < 10 else "-", dom))


@host_class("java.time.chrono.ChronoPeriodImpl", final=True, interfaces=("java.time.chrono.ChronoPeriod",))
class ChronoPeriodImpl(Period):
    def __init__(self, chrono, y, m, d):
        Period.__init__(self, y, m, d)
        self._chrono = chrono

    def getChronology(self):
        return self._chrono

    def toString(self):
        return jstr(self._chrono.toString() + " " + Period.toString(self))


host_class("java.time.chrono.ChronoPeriod", interface=True)(type("ChronoPeriod", (), {"__slots__": ()}))


@host_class("java.time.chrono.ChronoLocalDateTimeImpl", final=True, interfaces=("java.time.chrono.ChronoLocalDateTime",))
class ChronoDateTime(Object):
    def __init__(self, date, time):
        self._date, self._time = date, time

    def toLocalDate(self):
        return self._date

    def toLocalTime(self):
        return self._time

    def getChronology(self):
        return self._date.getChronology()

    def format(self, formatter):
        return formatter.withChronology(self._date.getChronology()).format(LocalDateTime(self._date._d, self._time))

    def equals(self, other):
        return 1 if isinstance(other, ChronoDateTime) and other._date.equals(self._date) and other._time.equals(self._time) else 0

    def hashCode(self):
        return self._date.hashCode() ^ self._time.hashCode()

    def toString(self):
        return jstr(self._date.toString() + "T" + self._time.toString())


@host_class("java.time.chrono.Chronology", interface=True, interfaces=("java.lang.Comparable",))
class Chronology(Object):
    __slots__ = ()

    @staticmethod
    def of(name):
        check_nonnull(name)
        for chrono in _REGISTRY:
            if name in (chrono.getId(), chrono.getCalendarType()):
                return chrono
        for chrono in _REGISTRY:
            if name.lower() in (chrono.getId().lower(), chrono.getCalendarType().lower()):
                return chrono
        _dt_error("Unknown chronology: " + name)

    @staticmethod
    def ofLocale(locale):
        tag = str(locale.toString()) if locale is not None else ""
        if tag == "ja_JP_JP":
            return JapaneseChronology.INSTANCE
        if tag == "th_TH" or tag == "th_TH_TH":
            return ThaiBuddhistChronology.INSTANCE
        return IsoChronology.INSTANCE

    @staticmethod
    def from_(temporal):
        check_nonnull(temporal)
        if isinstance(temporal, _ChronoDate):
            return temporal.getChronology()
        return IsoChronology.INSTANCE

    @staticmethod
    def getAvailableChronologies():
        from .jmap import HashSet
        result = HashSet()
        for chrono in _REGISTRY:
            result.add(chrono)
        return result


setattr(Chronology, "from", Chronology.from_)
host_class("java.time.chrono.AbstractChronology", abstract=True, interfaces=("java.time.chrono.Chronology",))(
    type("AbstractChronology", (Object,), {}))


class _BaseChronology(Object):
    _ID = _TYPE = ""

    def getId(self):
        return self._ID

    def getCalendarType(self):
        return self._TYPE

    def toString(self):
        return self._ID

    def equals(self, other):
        return 1 if other is self else 0

    def hashCode(self):
        return hash_string(self._ID) ^ 0x7c

    def compareTo(self, other):
        a, b = self._ID, other.getId()
        return (a > b) - (a < b)

    def range(self, field):
        from .jmore2 import ValueRange
        return _field_range(field)

    def isLeapYear(self, year):
        d = self.isoYear(year)
        return 1 if (d % 4 == 0 and (d % 100 != 0 or d % 400 == 0)) else 0

    # to the iso calendar
    def isoYear(self, prolept):
        return prolept

    def prolepticOf(self, iso):
        return iso._y

    def yearOfEraOf(self, iso):
        return iso._y if iso._y >= 1 else 1 - iso._y

    def eraOfDate(self, iso):
        return IsoEra.CE if iso._y >= 1 else IsoEra.BCE

    def eraOf(self, value):
        return IsoEra.of(value)

    def eras(self):
        from .jmap import ArrayList
        result = ArrayList()
        for era in self._eras_list():
            result.add(era)
        return result

    def prolepticYear(self, era, year_of_era):
        return self.isoYearFor(era, year_of_era) - self._offset() if self._offset() else self.isoYearFor(era, year_of_era)

    def isoYearFor(self, era, yoe):
        return yoe if era.getValue() == 1 else 1 - yoe

    def _offset(self):
        return 0

    # dates

    def date_of_iso(self, iso):
        return self._DATE(iso)

    def date(self, a, month=None, day=None, day2=None):
        if month is None:
            return self.date_of_iso(_iso_date(a))
        if day2 is not None:
            era, yoe, m, d = a, month, day, day2
            return self.date_of_iso(LocalDate.of(self.isoYearFor(era, yoe), m, d))
        return self.date_of_iso(LocalDate.of(self.isoYear(a), month, day))

    def dateYearDay(self, a, b, c=None):
        if c is not None:
            return self.date_of_iso(LocalDate.ofYearDay(self.isoYearFor(a, b), c))
        return self.date_of_iso(LocalDate.ofYearDay(self.isoYear(a), b))

    def dateEpochDay(self, day):
        return self.date_of_iso(LocalDate.ofEpochDay(day))

    def dateNow(self, clock=None):
        return self.date_of_iso(LocalDate.now(clock))

    def localDateTime(self, temporal):
        return LocalDateTime(_iso_date(temporal), temporal.toLocalTime() if hasattr(temporal, "toLocalTime") else LocalTime.MIDNIGHT)

    def period(self, y, m, d):
        return Period(y, m, d)

    def era_table(self):
        return {e.getValue(): (str(e.getDisplayName(TextStyle.SHORT)), str(e.getDisplayName(TextStyle.FULL)),
                               str(e.getDisplayName(TextStyle.NARROW))) for e in self._eras_list()}

    def convert_adapter(self, adapter):
        """the fields of the date of an adapter in the numbers of this calendar"""
        d = adapter.date
        if d is None:
            return
        adapter.extra.update({"YEAR": self.prolepticOf(d), "YEAR_OF_ERA": self.yearOfEraOf(d), "ERA": self.eraOfDate(d).getValue(),
                              "PROLEPTIC_MONTH": self.prolepticOf(d) * 12 + d._m - 1})


def hash_string(text):
    h = 0
    for ch in text:
        h = (31 * h + ord(ch)) & 0xFFFFFFFF
    return runtime.wrap32(h)


@host_class("java.time.chrono.IsoChronology", final=True, interfaces=("java.time.chrono.Chronology",))
class IsoChronology(_BaseChronology):
    _ID, _TYPE = "ISO", "iso8601"

    def _eras_list(self):
        return [IsoEra.BCE, IsoEra.CE]

    def date_of_iso(self, iso):
        return iso

    def isLeapYear(self, year):
        return 1 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 0

    def era_table(self):
        return {0: ("BC", "Before Christ", "B"), 1: ("AD", "Anno Domini", "A")}

    def isoYearFor(self, era, yoe):
        if not isinstance(era, IsoEra):
            runtime.throw_new("java.lang.ClassCastException", "Era must be IsoEra")
        return yoe if era.getValue() == 1 else 1 - yoe

    def prolepticYear(self, era, yoe):
        return self.isoYearFor(era, yoe)

    def date(self, a, month=None, day=None, day2=None):
        if month is None:
            return _iso_date(a)
        if day2 is not None:
            return LocalDate.of(self.isoYearFor(a, month), day, day2)
        return LocalDate.of(a, month, day)

    def dateYearDay(self, a, b, c=None):
        if c is not None:
            return LocalDate.ofYearDay(self.isoYearFor(a, b), c)
        return LocalDate.ofYearDay(a, b)

    def zonedDateTime(self, a, zone=None):
        if zone is None:
            return ZonedDateTime.from_(a)
        return ZonedDateTime.ofInstant(a, zone)

    def resolveDate(self, fields, style):
        from .jtimefmt import Parsed, resolve
        return None


IsoChronology.INSTANCE = IsoChronology()


class _MinguoDateT(_ChronoDate):
    pass


class _OffsetChronology(_BaseChronology):
    """a calendar whose proleptic year is the ISO year shifted by a constant, with two eras"""

    _SHIFT = 0       # proleptic = iso - SHIFT
    _ERA = None

    def _offset(self):
        return self._SHIFT

    def isoYear(self, prolept):
        return prolept + self._SHIFT

    def prolepticOf(self, iso):
        return iso._y - self._SHIFT

    def yearOfEraOf(self, iso):
        p = iso._y - self._SHIFT
        return p if p >= 1 else 1 - p

    def eraOfDate(self, iso):
        return self._ERA.all_[1] if iso._y - self._SHIFT >= 1 else self._ERA.all_[0]

    def eraOf(self, value):
        return self._ERA.of(value)

    def _eras_list(self):
        return list(self._ERA._all)

    def isoYearFor(self, era, yoe):
        p = yoe if era.getValue() == 1 else 1 - yoe
        return p + self._SHIFT

    def prolepticYear(self, era, yoe):
        if not isinstance(era, self._ERA):
            runtime.throw_new("java.lang.ClassCastException", "Era must be " + self._ERA.__name__)
        return yoe if era.getValue() == 1 else 1 - yoe

    def isLeapYear(self, year):
        iso = year + self._SHIFT
        return 1 if (iso % 4 == 0 and (iso % 100 != 0 or iso % 400 == 0)) else 0

    def range(self, field):
        from .jmore2 import ValueRange
        name = field._name
        lo, hi = -999999999 - self._SHIFT, 999999999 - self._SHIFT
        if name == "YEAR":
            return ValueRange.of(lo, hi)
        if name == "YEAR_OF_ERA":
            a, b = -lo + 1, hi
            return ValueRange.of(1, min(a, b), max(a, b))
        return _field_range(field)


MinguoEra.all_ = MinguoEra._all
ThaiBuddhistEra.all_ = ThaiBuddhistEra._all


@host_class("java.time.chrono.MinguoDate", final=True, interfaces=("java.time.chrono.ChronoLocalDate", "java.io.Serializable"))
class MinguoDate(_ChronoDate):
    @staticmethod
    def of(y, m, d):
        return MinguoChronology.INSTANCE.date(y, m, d)

    @staticmethod
    def now(clock=None):
        return MinguoChronology.INSTANCE.dateNow(clock)

    @staticmethod
    def from_(temporal):
        return MinguoChronology.INSTANCE.date(temporal)


@host_class("java.time.chrono.ThaiBuddhistDate", final=True, interfaces=("java.time.chrono.ChronoLocalDate", "java.io.Serializable"))
class ThaiBuddhistDate(_ChronoDate):
    @staticmethod
    def of(y, m, d):
        return ThaiBuddhistChronology.INSTANCE.date(y, m, d)

    @staticmethod
    def now(clock=None):
        return ThaiBuddhistChronology.INSTANCE.dateNow(clock)

    @staticmethod
    def from_(temporal):
        return ThaiBuddhistChronology.INSTANCE.date(temporal)


@host_class("java.time.chrono.MinguoChronology", final=True, interfaces=("java.time.chrono.Chronology",))
class MinguoChronology(_OffsetChronology):
    _ID, _TYPE, _SHIFT, _ERA, _DATE = "Minguo", "roc", 1911, MinguoEra, MinguoDate


@host_class("java.time.chrono.ThaiBuddhistChronology", final=True, interfaces=("java.time.chrono.Chronology",))
class ThaiBuddhistChronology(_OffsetChronology):
    _ID, _TYPE, _SHIFT, _ERA, _DATE = "ThaiBuddhist", "buddhist", -543, ThaiBuddhistEra, ThaiBuddhistDate


MinguoChronology.INSTANCE = MinguoChronology()
ThaiBuddhistChronology.INSTANCE = ThaiBuddhistChronology()
MinguoDate._CHRONO = MinguoChronology.INSTANCE
ThaiBuddhistDate._CHRONO = ThaiBuddhistChronology.INSTANCE
setattr(MinguoDate, "from", MinguoDate.from_)
setattr(ThaiBuddhistDate, "from", ThaiBuddhistDate.from_)


@host_class("java.time.chrono.JapaneseDate", final=True, interfaces=("java.time.chrono.ChronoLocalDate", "java.io.Serializable"))
class JapaneseDate(_ChronoDate):
    _NO_ALIGNED = True

    @staticmethod
    def of(*args):
        return JapaneseChronology.INSTANCE.date(*args)

    @staticmethod
    def now(clock=None):
        return JapaneseChronology.INSTANCE.dateNow(clock)

    @staticmethod
    def from_(temporal):
        return JapaneseChronology.INSTANCE.date(temporal)

    @staticmethod
    def ofEra(era, yoe, month, day):
        return JapaneseChronology.INSTANCE.date(era, yoe, month, day)


setattr(JapaneseDate, "from", JapaneseDate.from_)


@host_class("java.time.chrono.JapaneseChronology", final=True, interfaces=("java.time.chrono.Chronology",))
class JapaneseChronology(_BaseChronology):
    _ID, _TYPE, _DATE = "Japanese", "japanese", JapaneseDate

    def prolepticOf(self, iso):
        return iso._y

    def yearOfEraOf(self, iso):
        era = JapaneseEra.from_(iso)
        return iso._y - era._since._y + 1

    def eraOfDate(self, iso):
        return JapaneseEra.from_(iso)

    def eraOf(self, value):
        return JapaneseEra.of(value)

    def _eras_list(self):
        return list(JapaneseEra._all)

    def isoYearFor(self, era, yoe):
        if not isinstance(era, JapaneseEra):
            runtime.throw_new("java.lang.ClassCastException", "Era must be JapaneseEra")
        return era._since._y + yoe - 1

    def prolepticYear(self, era, yoe):
        return self.isoYearFor(era, yoe)

    def date(self, a, month=None, day=None, day2=None):
        if month is None:
            return self.date_of_iso(_iso_date(a))
        if day2 is not None:
            iso = LocalDate.of(self.isoYearFor(a, month), day, day2)
            if JapaneseEra.from_(iso) is not a:
                _dt_error("year, month, and day not valid for Era")
            return self.date_of_iso(iso)
        return self.date_of_iso(LocalDate.of(a, month, day))

    def date_of_iso(self, iso):
        if iso.isBefore(LocalDate.of(1873, 1, 1)):
            _dt_error("JapaneseDate before Meiji 6 is not supported")
        return JapaneseDate(iso)

    def range(self, field):
        from .jmore2 import ValueRange
        if field._name == "YEAR_OF_ERA":
            return ValueRange.of(1, 15, 999999999 - 2019)
        if field._name == "YEAR":
            return ValueRange.of(1873, 999999999)
        return _field_range(field)


JapaneseChronology.INSTANCE = JapaneseChronology()
JapaneseDate._CHRONO = JapaneseChronology.INSTANCE
_REGISTRY = [IsoChronology.INSTANCE, MinguoChronology.INSTANCE, ThaiBuddhistChronology.INSTANCE, JapaneseChronology.INSTANCE]

# the iso calendar for temporals of java.time

LocalDate.getChronology = lambda self: IsoChronology.INSTANCE
LocalDateTime.getChronology = lambda self: IsoChronology.INSTANCE
ZonedDateTime.getChronology = lambda self: IsoChronology.INSTANCE
LocalDate.getEra = lambda self: IsoEra.CE if self._y >= 1 else IsoEra.BCE


class _Query(Object):
    def __init__(self, name, func):
        self._n, self._f = name, func

    def queryFrom(self, temporal):
        return self._f(temporal)

    def toString(self):
        return self._n


def _adapter(temporal):
    from .jtimefmt import Adapter
    return Adapter(temporal)


def _zone_of(t):
    a = _adapter(t)
    return a.zone


def _offset_of(t):
    a = _adapter(t)
    if a.offset is not None:
        return a.offset
    return None


def _precision(t):
    a = _adapter(t)
    if isinstance(t, Instant):
        return ChronoUnit.NANOS
    if a.time is not None:
        return ChronoUnit.NANOS
    if a.date is not None:
        return ChronoUnit.DAYS
    return None


@host_class("java.time.temporal.TemporalQueries", final=True)
class TemporalQueries(Object):
    @staticmethod
    def zoneId():
        return _Q_ZONEID

    @staticmethod
    def chronology():
        return _Q_CHRONO

    @staticmethod
    def precision():
        return _Q_PRECISION

    @staticmethod
    def zone():
        return _Q_ZONE

    @staticmethod
    def offset():
        return _Q_OFFSET

    @staticmethod
    def localDate():
        return _Q_DATE

    @staticmethod
    def localTime():
        return _Q_TIME


def _zone_id_query(t):
    z = _zone_of(t)
    return None if isinstance(z, ZoneOffset) else z


def _zone_query(t):
    z = _zone_id_query(t)
    return z if z is not None else _offset_of(t)


def _local_date_query(t):
    a = _adapter(t)
    return a.date


def _local_time_query(t):
    a = _adapter(t)
    return a.time


_Q_ZONEID = _Query("ZoneId", _zone_id_query)
_Q_CHRONO = _Query("Chronology", lambda t: IsoChronology.INSTANCE if _adapter(t).date is not None else None)
_Q_PRECISION = _Query("Precision", _precision)
_Q_ZONE = _Query("Zone", _zone_query)
_Q_OFFSET = _Query("Offset", _offset_of)
_Q_DATE = _Query("LocalDate", _local_date_query)
_Q_TIME = _Query("LocalTime", _local_time_query)


for _cls in (LocalDate, LocalTime, LocalDateTime, ZonedDateTime, OffsetDateTime, Instant):
    if not hasattr(_cls, "query"):
        _cls.query = lambda self, q: q.queryFrom(self)


setattr(_ChronoDate, "with", _ChronoDate.with_)
