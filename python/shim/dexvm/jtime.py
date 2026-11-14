"""java.util.Date, TimeZone, Calendar, GregorianCalendar and java.text.DateFormat, SimpleDateFormat

time is milliseconds since the epoch. a calendar keeps its fields as the jdk does: a field that was set last wins when
the time is recomputed, fields outside their range roll into the next one (lenient), and add() keeps the wall clock of
the zone. the calendar is proleptic Gregorian: the jdk switches to the Julian calendar before 1582, which no program
of a chat client meets. names of months and days are english; a Locale picks only the first day of the week

zones come from the C library for the default zone (so the daylight rules of the device apply even where the python
zoneinfo database is absent), from zoneinfo for a named zone, and from the id itself for GMT+hh:mm. a zone id that
none of them knows answers as GMT, the jdk behaviour"""

import re
import time as _time

from . import runtime
from .api import host_class, jmethod, jstatic, lookup_host
from .jlang import Object, jstr
from .jutil import check_nonnull

try:
    import zoneinfo as _zoneinfo
except ImportError:
    _zoneinfo = None

MS_DAY = 86400000

ERA, YEAR, MONTH, WEEK_OF_YEAR, WEEK_OF_MONTH, DAY_OF_MONTH, DAY_OF_YEAR, DAY_OF_WEEK, DAY_OF_WEEK_IN_MONTH, \
    AM_PM, HOUR, HOUR_OF_DAY, MINUTE, SECOND, MILLISECOND, ZONE_OFFSET, DST_OFFSET = range(17)
FIELD_COUNT = 17

# what a cleared field reads as: the epoch date, so a program that sets only some fields starts from 1970-01-01
_CLEARED = {ERA: 1, YEAR: 1970, DAY_OF_MONTH: 1, DAY_OF_WEEK: 5, DAY_OF_WEEK_IN_MONTH: 1}

MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December")
DAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

# first day of the week 1 (Sunday) and one day in the first week, by country; every other region uses Monday and four
_SUNDAY_COUNTRIES = frozenset("US CA MX BR JP IL IN KR PH TW HK SA ZA TH VE CO PE AR ID".split())
_SUNDAY_LANGUAGES = frozenset("en ja ko he hi pt th".split())


def days_from_civil(year, month, day):
    year -= month <= 2
    era = year // 400
    yoe = year - era * 400
    doy = (153 * (month + (-3 if month > 2 else 9)) + 2) // 5 + day - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def civil_from_days(days):
    days += 719468
    era = days // 146097
    doe = days - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    year = yoe + era * 400
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    day = doy - (153 * mp + 2) // 5 + 1
    month = mp + 3 if mp < 10 else mp - 9
    return year + (month <= 2), month, day


def is_leap(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def month_length(year, month0):
    if month0 == 1:
        return 29 if is_leap(year) else 28
    return 30 if month0 in (3, 5, 8, 10) else 31


def weekday(days):
    """1 for Sunday to 7 for Saturday, the DAY_OF_WEEK of an epoch day"""
    return (days + 4) % 7 + 1


class _Zone:
    """the rules of one zone: offset(utc_ms) is the total offset, raw the one without daylight saving"""

    def __init__(self, zone_id, kind, fixed=0, info=None):
        self.id = zone_id
        self.kind = kind
        self.fixed = fixed
        self.info = info
        self._raw = None

    def offset(self, utc_ms):
        if self.kind == "fixed":
            return self.fixed
        seconds = utc_ms // 1000
        try:
            if self.kind == "local":
                return _time.localtime(seconds).tm_gmtoff * 1000
            import datetime
            return int(datetime.datetime.fromtimestamp(seconds, self.info).utcoffset().total_seconds()) * 1000
        except (OverflowError, OSError, ValueError):
            return self.raw()

    def raw(self):
        if self._raw is None:
            if self.kind == "fixed":
                self._raw = self.fixed
            elif self.kind == "local":
                self._raw = -_time.timezone * 1000
            else:
                import datetime
                best = None
                for month in (1, 7):
                    moment = datetime.datetime(2021, month, 1, tzinfo=self.info)
                    if not moment.dst():
                        best = int(moment.utcoffset().total_seconds()) * 1000
                        break
                self._raw = best if best is not None else int(moment.utcoffset().total_seconds()) * 1000
        return self._raw

    def uses_dst(self):
        if self.kind == "fixed":
            return False
        base = 1609459200000
        return any(self.offset(base + step * 15724800000 // 2) != self.raw() for step in range(4))

    def local_to_utc(self, local_ms):
        guess = self.offset(local_ms - self.raw())
        return local_ms - self.offset(local_ms - guess)

    def short_name(self, utc_ms):
        offset = self.offset(utc_ms)
        if self.kind != "local" and self.id in ("UTC", "GMT"):
            return self.id
        if self.kind == "local":
            names = _time.tzname
            name = names[1] if offset != self.raw() and len(names) > 1 else names[0]
            if name:
                return name
        elif self.kind == "zone":
            import datetime
            try:
                name = datetime.datetime.fromtimestamp(utc_ms // 1000, self.info).tzname()
            except (OverflowError, OSError, ValueError):
                name = None
            if name and not name[0] in "+-":
                return name
        return _gmt_text(offset)


def _gmt_text(offset_ms, colon=True):
    minutes = abs(offset_ms) // 60000
    sign = "-" if offset_ms < 0 else "+"
    return "GMT%s%02d%s%02d" % (sign, minutes // 60, ":" if colon else "", minutes % 60)


_CUSTOM = re.compile(r"GMT([+-])(\d{1,2})(?::?(\d{2}))?\Z")
_zones = {}


def _find_zone(zone_id):
    """the _Zone of an id, or None; GMT and UTC are always known"""
    found = _zones.get(zone_id)
    if found is not None:
        return found
    if zone_id in ("GMT", "UTC", "Z", "UT"):
        found = _Zone("UTC" if zone_id == "UTC" else "GMT", "fixed", 0)
    else:
        match = _CUSTOM.match(zone_id)
        if match is not None:
            hours = int(match.group(2))
            minutes = int(match.group(3) or 0)
            if hours <= 23 and minutes <= 59:
                offset = (hours * 60 + minutes) * 60000 * (-1 if match.group(1) == "-" else 1)
                found = _Zone(_gmt_text(offset), "fixed", offset)
        elif _zoneinfo is not None:
            try:
                found = _Zone(zone_id, "zone", info=_zoneinfo.ZoneInfo(zone_id))
            except (_zoneinfo.ZoneInfoNotFoundError, ValueError, OSError):
                found = None
    if found is not None:
        _zones[zone_id] = found
    return found


def _local_zone_id():
    import os
    name = os.environ.get("TZ", "")
    if name.startswith(":"):
        name = name[1:]
    if not name:
        try:
            target = os.readlink("/etc/localtime")
            marker = "zoneinfo/"
            name = target[target.index(marker) + len(marker):] if marker in target else ""
        except OSError:
            name = ""
    if name:
        return name
    offset = _time.localtime().tm_gmtoff * 1000
    return _gmt_text(offset) if offset else "GMT"


_default = []


def default_zone():
    if not _default:
        _default.append(_Zone(_local_zone_id(), "local"))
    return _default[0]


@host_class("java.util.TimeZone", interfaces=("java.io.Serializable",))
class TimeZone(Object):
    SHORT = 0
    LONG = 1

    def __init__(self, zone=None):
        self._zone = zone or default_zone()

    @jstatic("getDefault", "()Ljava/util/TimeZone;")
    def getDefault():
        return TimeZone(default_zone())

    @jstatic("setDefault", "(Ljava/util/TimeZone;)V")
    def setDefault(zone):
        _default[:] = [zone._zone if zone is not None else _Zone(_local_zone_id(), "local")]

    @jstatic("getTimeZone", "(Ljava/lang/String;)Ljava/util/TimeZone;")
    def getTimeZone(zone_id):
        found = _find_zone(check_nonnull(zone_id))
        return TimeZone(found if found is not None else _find_zone("GMT"))

    @jstatic("getAvailableIDs", "()[Ljava/lang/String;")
    def getAvailableIDs():
        ids = sorted(_zoneinfo.available_timezones()) if _zoneinfo is not None else []
        array = runtime.new_array("[Ljava/lang/String;", 0)
        array.extend(["GMT", "UTC"] + [name for name in ids if name not in ("GMT", "UTC")])
        return array

    @jmethod("getID", "()Ljava/lang/String;")
    def getID(self):
        return self._zone.id

    @jmethod("getRawOffset", "()I")
    def getRawOffset(self):
        return self._zone.raw()

    @jmethod("getOffset", "(J)I")
    def getOffset(self, when):
        return self._zone.offset(when)

    @jmethod("useDaylightTime", "()Z")
    @jmethod("observesDaylightTime", "()Z")
    def useDaylightTime(self):
        return 1 if self._zone.uses_dst() else 0

    @jmethod("getDSTSavings", "()I")
    def getDSTSavings(self):
        return 3600000 if self._zone.uses_dst() else 0

    @jmethod("inDaylightTime", "(Ljava/util/Date;)Z")
    def inDaylightTime(self, date):
        return 1 if self._zone.offset(date._ms) != self._zone.raw() else 0

    @jmethod("getDisplayName", "()Ljava/lang/String;")
    def getDisplayName(self):
        return self._zone.id

    @jmethod("getDisplayName", "(ZI)Ljava/lang/String;")
    def getDisplayName_style(self, daylight, style):
        return self._zone.id if style == 1 else self._zone.short_name(_now_ms())

    @jmethod("hasSameRules", "(Ljava/util/TimeZone;)Z")
    def hasSameRules(self, other):
        return 1 if other is not None and other._zone.id == self._zone.id else 0

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return TimeZone(self._zone)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, TimeZone) and other._zone.id == self._zone.id else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        from .jfunc import string_hash
        return string_hash(self._zone.id)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "libcore.util.ZoneInfo[id=\"%s\",mRawOffset=%d]" % (self._zone.id, self._zone.raw())


def _now_ms():
    return int(_time.time() * 1000)


@host_class("java.util.Date", interfaces=("java.io.Serializable", "java.lang.Cloneable", "java.lang.Comparable"))
class Date(Object):
    def __init__(self, millis=None):
        self._ms = _now_ms() if millis is None else runtime.wrap64(millis)

    @jmethod("<init>", "()V")
    def _init0(self):
        Date.__init__(self)

    @jmethod("<init>", "(J)V")
    def _init_ms(self, millis):
        Date.__init__(self, millis)

    @jmethod("getTime", "()J")
    def getTime(self):
        return self._ms

    @jmethod("setTime", "(J)V")
    def setTime(self, millis):
        self._ms = millis

    @jmethod("before", "(Ljava/util/Date;)Z")
    def before(self, other):
        return 1 if self._ms < check_nonnull(other)._ms else 0

    @jmethod("after", "(Ljava/util/Date;)Z")
    def after(self, other):
        return 1 if self._ms > check_nonnull(other)._ms else 0

    @jmethod("compareTo", "(Ljava/util/Date;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        other = check_nonnull(other)
        return (self._ms > other._ms) - (self._ms < other._ms)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Date) and other._ms == self._ms else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return runtime.wrap32(self._ms ^ (self._ms >> 32))

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        return type(self)(self._ms)

    def _fields(self):
        calendar = GregorianCalendar()
        calendar.setTimeInMillis(self._ms)
        return calendar

    @jmethod("getYear", "()I")
    def getYear(self):
        return self._fields().get(YEAR) - 1900

    @jmethod("getMonth", "()I")
    def getMonth(self):
        return self._fields().get(MONTH)

    @jmethod("getDate", "()I")
    def getDate(self):
        return self._fields().get(DAY_OF_MONTH)

    @jmethod("getDay", "()I")
    def getDay(self):
        return self._fields().get(DAY_OF_WEEK) - 1

    @jmethod("getHours", "()I")
    def getHours(self):
        return self._fields().get(HOUR_OF_DAY)

    @jmethod("getMinutes", "()I")
    def getMinutes(self):
        return self._fields().get(MINUTE)

    @jmethod("getSeconds", "()I")
    def getSeconds(self):
        return self._fields().get(SECOND)

    @jmethod("getTimezoneOffset", "()I")
    def getTimezoneOffset(self):
        return -default_zone().offset(self._ms) // 60000

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        zone = default_zone()
        return _format("EEE MMM dd HH:mm:ss zzz yyyy", self._ms, zone)


def _decompose(ms, zone):
    local = ms + zone.offset(ms)
    days, in_day = divmod(local, MS_DAY)
    year, month, day = civil_from_days(days)
    return days, in_day, year, month - 1, day


def _locale_week(locale):
    """(first day of the week, minimal days in the first week) of a Locale or of the default one"""
    if locale is None:
        locale = lookup_host("java.util.Locale").py.getDefault()
    country = locale.getCountry()
    language = locale.getLanguage()
    if country in _SUNDAY_COUNTRIES or (not country and language in _SUNDAY_LANGUAGES):
        return 1, 1
    return 2, 4


@host_class("java.util.Calendar", interfaces=("java.io.Serializable", "java.lang.Cloneable", "java.lang.Comparable"))
class Calendar(Object):
    ERA = ERA
    YEAR = YEAR
    MONTH = MONTH
    WEEK_OF_YEAR = WEEK_OF_YEAR
    WEEK_OF_MONTH = WEEK_OF_MONTH
    DATE = DAY_OF_MONTH
    DAY_OF_MONTH = DAY_OF_MONTH
    DAY_OF_YEAR = DAY_OF_YEAR
    DAY_OF_WEEK = DAY_OF_WEEK
    DAY_OF_WEEK_IN_MONTH = DAY_OF_WEEK_IN_MONTH
    AM_PM = AM_PM
    HOUR = HOUR
    HOUR_OF_DAY = HOUR_OF_DAY
    MINUTE = MINUTE
    SECOND = SECOND
    MILLISECOND = MILLISECOND
    ZONE_OFFSET = ZONE_OFFSET
    DST_OFFSET = DST_OFFSET
    FIELD_COUNT = FIELD_COUNT
    SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY = range(1, 8)
    JANUARY, FEBRUARY, MARCH, APRIL, MAY, JUNE, JULY, AUGUST, SEPTEMBER, OCTOBER, NOVEMBER, DECEMBER, \
        UNDECIMBER = range(13)
    AM = 0
    PM = 1
    ALL_STYLES = 0
    SHORT = 1
    LONG = 2

    def __init__(self, zone=None, locale=None):
        self._zone = zone._zone if isinstance(zone, TimeZone) else default_zone()
        self._first, self._min_days = _locale_week(locale)
        self._lenient = True
        self._time = _now_ms()
        self._fields = [0] * FIELD_COUNT
        self._stamp = [0] * FIELD_COUNT
        self._counter = 2
        self._time_ok = True
        self._fields_ok = False

    @jstatic("getInstance", "()Ljava/util/Calendar;")
    @jstatic("getInstance", "(Ljava/util/TimeZone;)Ljava/util/Calendar;")
    @jstatic("getInstance", "(Ljava/util/Locale;)Ljava/util/Calendar;")
    @jstatic("getInstance", "(Ljava/util/TimeZone;Ljava/util/Locale;)Ljava/util/Calendar;")
    def getInstance(first=None, second=None):
        zone = first if isinstance(first, TimeZone) else None
        locale = second if second is not None else (first if first is not None and zone is None else None)
        return GregorianCalendar(zone, locale)

    def _compute_fields(self):
        if self._fields_ok:
            return
        zone = self._zone
        offset = zone.offset(self._time)
        days, in_day, year, month, day = _decompose(self._time, zone)
        fields = self._fields
        fields[ERA] = 1 if year > 0 else 0
        fields[YEAR] = year if year > 0 else 1 - year
        fields[MONTH] = month
        fields[DAY_OF_MONTH] = day
        fields[DAY_OF_YEAR] = days - days_from_civil(year, 1, 1) + 1
        dow = weekday(days)
        fields[DAY_OF_WEEK] = dow
        fields[DAY_OF_WEEK_IN_MONTH] = (day - 1) // 7 + 1
        fields[HOUR_OF_DAY] = in_day // 3600000
        fields[HOUR] = fields[HOUR_OF_DAY] % 12
        fields[AM_PM] = 1 if fields[HOUR_OF_DAY] >= 12 else 0
        fields[MINUTE] = in_day // 60000 % 60
        fields[SECOND] = in_day // 1000 % 60
        fields[MILLISECOND] = in_day % 1000
        fields[ZONE_OFFSET] = zone.raw()
        fields[DST_OFFSET] = offset - zone.raw()
        year_start = days_from_civil(year, 1, 1)
        fields[WEEK_OF_YEAR] = self._week_of_year(days, year, year_start)
        month_start = days_from_civil(year, month + 1, 1)
        fields[WEEK_OF_MONTH] = self._week_number(days, month_start)
        self._stamp[:] = [1] * FIELD_COUNT
        self._fields_ok = True

    def _first_week_start(self, first_day):
        """the epoch day the first week of the period starting at first_day begins on"""
        gap = (weekday(first_day) - self._first) % 7
        start = first_day - gap
        if 7 - gap < self._min_days:
            start += 7
        return start

    def _week_number(self, days, period_start):
        week = (days - self._first_week_start(period_start)) // 7 + 1
        return week if week > 0 else 0

    def _week_of_year(self, days, year, year_start):
        week = (days - self._first_week_start(year_start)) // 7 + 1
        if week >= 1:
            next_start = self._first_week_start(days_from_civil(year + 1, 1, 1))
            if days >= next_start:
                return 1
            return week
        previous = self._first_week_start(days_from_civil(year - 1, 1, 1))
        return (days - previous) // 7 + 1

    def _compute_time(self):
        if self._time_ok:
            return
        fields = self._fields
        stamp = self._stamp
        year = fields[YEAR]
        if fields[ERA] == 0 and stamp[ERA] >= stamp[YEAR]:
            year = 1 - year
        month = fields[MONTH]
        year += month // 12
        month %= 12
        first_of_month = days_from_civil(year, month + 1, 1)
        dow_stamp = stamp[DAY_OF_WEEK]
        best = stamp[DAY_OF_MONTH]
        choice = "dom"
        for name, value in (("wom", max(stamp[WEEK_OF_MONTH], dow_stamp)),
                            ("dowim", max(stamp[DAY_OF_WEEK_IN_MONTH], dow_stamp)),
                            ("doy", stamp[DAY_OF_YEAR]),
                            ("woy", max(stamp[WEEK_OF_YEAR], dow_stamp))):
            if value > best:
                best = value
                choice = name
        dow = fields[DAY_OF_WEEK]
        if choice == "dom":
            days = first_of_month + fields[DAY_OF_MONTH] - 1
        elif choice == "doy":
            days = days_from_civil(year, 1, 1) + fields[DAY_OF_YEAR] - 1
        elif choice == "wom":
            days = self._first_week_start(first_of_month) + (fields[WEEK_OF_MONTH] - 1) * 7 + (dow - self._first) % 7
        elif choice == "woy":
            start = self._first_week_start(days_from_civil(year, 1, 1))
            days = start + (fields[WEEK_OF_YEAR] - 1) * 7 + (dow - self._first) % 7
        else:
            count = fields[DAY_OF_WEEK_IN_MONTH]
            if count > 0:
                days = first_of_month + (dow - weekday(first_of_month)) % 7 + (count - 1) * 7
            else:
                last = first_of_month + month_length(year, month) - 1
                days = last - (weekday(last) - dow) % 7 + (count + 1) * 7
        hour_stamp = max(stamp[HOUR], stamp[AM_PM])
        if stamp[HOUR_OF_DAY] >= hour_stamp:
            hour = fields[HOUR_OF_DAY]
        else:
            hour = fields[HOUR] + 12 * fields[AM_PM]
        in_day = ((hour * 60 + fields[MINUTE]) * 60 + fields[SECOND]) * 1000 + fields[MILLISECOND]
        local = days * MS_DAY + in_day
        if stamp[ZONE_OFFSET] > 1 or stamp[DST_OFFSET] > 1:
            self._time = local - fields[ZONE_OFFSET] - fields[DST_OFFSET]
        else:
            self._time = self._zone.local_to_utc(local)
        self._time_ok = True
        self._fields_ok = False

    def _check_field(self, field):
        if not 0 <= field < FIELD_COUNT:
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException", "index=%d length=%d" % (field, FIELD_COUNT))

    @jmethod("get", "(I)I")
    def get(self, field):
        self._check_field(field)
        self._compute_time()
        self._compute_fields()
        return self._fields[field]

    @jmethod("set", "(II)V")
    @jmethod("set", "(III)V")
    @jmethod("set", "(IIIII)V")
    @jmethod("set", "(IIIIII)V")
    def set(self, first, second, day=None, hour=None, minute=None, sec=None):
        if day is not None:
            self.set_date(first, second, day, hour, minute, sec)
            return
        self.set_field(first, second)

    def set_field(self, field, value):
        self._check_field(field)
        if self._time_ok and not self._fields_ok:
            self._compute_fields()
        if not self._lenient and not self._in_range(field, value):
            runtime.throw_new("java.lang.IllegalArgumentException", "Unknown field value")
        self._fields[field] = value
        self._counter += 1
        self._stamp[field] = self._counter
        self._time_ok = False
        self._fields_ok = True

    def _in_range(self, field, value):
        low = self.getMinimum(field)
        high = self.getMaximum(field)
        return low <= value <= high

    def set_date(self, year, month, day, hour=None, minute=None, second=None):
        self.set_field(YEAR, year)
        self.set_field(MONTH, month)
        self.set_field(DAY_OF_MONTH, day)
        if hour is not None:
            self.set_field(HOUR_OF_DAY, hour)
            self.set_field(MINUTE, minute)
        if second is not None:
            self.set_field(SECOND, second)

    @jmethod("clear", "()V")
    @jmethod("clear", "(I)V")
    def clear(self, field=None):
        if field is None:
            self._fields = [0] * FIELD_COUNT
            self._stamp = [0] * FIELD_COUNT
            for index, default in _CLEARED.items():
                self._fields[index] = default
        else:
            if self._time_ok and not self._fields_ok:
                self._compute_fields()
            self._fields[field] = _CLEARED.get(field, 0)
            self._stamp[field] = 0
        self._time_ok = False
        self._fields_ok = True

    @jmethod("isSet", "(I)Z")
    def isSet(self, field):
        return 1 if self._stamp[field] else 0

    @jmethod("getTimeInMillis", "()J")
    def getTimeInMillis(self):
        self._compute_time()
        return self._time

    @jmethod("setTimeInMillis", "(J)V")
    def setTimeInMillis(self, millis):
        self._time = runtime.wrap64(millis)
        self._time_ok = True
        self._fields_ok = False
        self._stamp = [0] * FIELD_COUNT

    @jmethod("getTime", "()Ljava/util/Date;")
    def getTime(self):
        return Date(self.getTimeInMillis())

    @jmethod("setTime", "(Ljava/util/Date;)V")
    def setTime(self, date):
        self.setTimeInMillis(check_nonnull(date)._ms)

    @jmethod("getTimeZone", "()Ljava/util/TimeZone;")
    def getTimeZone(self):
        return TimeZone(self._zone)

    @jmethod("setTimeZone", "(Ljava/util/TimeZone;)V")
    def setTimeZone(self, zone):
        self._compute_time()
        self._zone = check_nonnull(zone)._zone
        self._fields_ok = False

    @jmethod("setLenient", "(Z)V")
    def setLenient(self, flag):
        self._lenient = bool(flag)

    @jmethod("isLenient", "()Z")
    def isLenient(self):
        return 1 if self._lenient else 0

    @jmethod("getFirstDayOfWeek", "()I")
    def getFirstDayOfWeek(self):
        return self._first

    @jmethod("setFirstDayOfWeek", "(I)V")
    def setFirstDayOfWeek(self, day):
        self._compute_time()
        self._first = day
        self._fields_ok = False

    @jmethod("getMinimalDaysInFirstWeek", "()I")
    def getMinimalDaysInFirstWeek(self):
        return self._min_days

    @jmethod("setMinimalDaysInFirstWeek", "(I)V")
    def setMinimalDaysInFirstWeek(self, days):
        self._compute_time()
        self._min_days = days
        self._fields_ok = False

    def add_ms(self, delta):
        self._compute_time()
        self._time += delta
        self._fields_ok = False
        self._stamp = [0] * FIELD_COUNT

    @jmethod("add", "(II)V")
    def add(self, field, amount):
        if amount == 0:
            return
        self._check_field(field)
        self._compute_time()
        self._compute_fields()
        if field in (ZONE_OFFSET, DST_OFFSET):
            runtime.throw_new("java.lang.IllegalArgumentException", "")
        if field in (YEAR, MONTH, ERA):
            if field == ERA:
                self.set_field(ERA, min(1, max(0, self._fields[ERA] + amount)))
                return
            year = self._fields[YEAR] if self._fields[ERA] else 1 - self._fields[YEAR]
            month = self._fields[MONTH]
            if field == YEAR:
                year += amount
            else:
                month += amount
                year += month // 12
                month %= 12
            day = min(self._fields[DAY_OF_MONTH], month_length(year, month))
            self._reset_date(year, month, day)
            return
        if field in (WEEK_OF_YEAR, WEEK_OF_MONTH, DAY_OF_WEEK_IN_MONTH):
            amount *= 7
            field = DAY_OF_MONTH
        if field in (DAY_OF_MONTH, DAY_OF_YEAR, DAY_OF_WEEK):
            days, in_day, year, month, day = _decompose(self._time, self._zone)
            self._reset_date(year, month, day + amount)
            return
        if field == AM_PM:
            self.add_ms(amount * 12 * 3600000)
        elif field in (HOUR, HOUR_OF_DAY):
            self.add_ms(amount * 3600000)
        elif field == MINUTE:
            self.add_ms(amount * 60000)
        elif field == SECOND:
            self.add_ms(amount * 1000)
        else:
            self.add_ms(amount)

    def _reset_date(self, year, month, day):
        """the same wall clock time on another date"""
        _, in_day, _, _, _ = _decompose(self._time, self._zone)
        year += month // 12
        month %= 12
        local = (days_from_civil(year, month + 1, 1) + day - 1) * MS_DAY + in_day
        self._time = self._zone.local_to_utc(local)
        self._fields_ok = False
        self._stamp = [0] * FIELD_COUNT

    @jmethod("roll", "(IZ)V")
    @jmethod("roll", "(II)V")
    def roll(self, field, amount):
        amount = (1 if amount else -1) if isinstance(amount, bool) else amount
        self._compute_time()
        self._compute_fields()
        low = self.getActualMinimum(field)
        high = self.getActualMaximum(field)
        value = self._fields[field]
        span = high - low + 1
        value = low + (value - low + amount) % span
        if field == YEAR or field == ERA:
            self.add(field, amount)
            return
        self.set_field(field, value)
        self._compute_time()

    @jmethod("getActualMaximum", "(I)I")
    def getActualMaximum(self, field):
        self._compute_time()
        self._compute_fields()
        year = self._fields[YEAR] if self._fields[ERA] else 1 - self._fields[YEAR]
        month = self._fields[MONTH]
        if field == DAY_OF_MONTH:
            return month_length(year, month)
        if field == DAY_OF_YEAR:
            return 366 if is_leap(year) else 365
        if field == WEEK_OF_YEAR:
            start = self._first_week_start(days_from_civil(year, 1, 1))
            end = self._first_week_start(days_from_civil(year + 1, 1, 1))
            return (end - start) // 7
        if field == WEEK_OF_MONTH:
            start = self._first_week_start(days_from_civil(year, month + 1, 1))
            end_month = days_from_civil(year, month + 1, 1) + month_length(year, month)
            return (end_month - 1 - start) // 7 + 1
        if field == DAY_OF_WEEK_IN_MONTH:
            return (month_length(year, month) - 1) // 7 + 1
        return self.getMaximum(field)

    @jmethod("getActualMinimum", "(I)I")
    def getActualMinimum(self, field):
        return self.getMinimum(field)

    @jmethod("getMaximum", "(I)I")
    @jmethod("getLeastMaximum", "(I)I")
    def getMaximum(self, field):
        return (1, 292278994, 11, 53, 6, 31, 366, 7, 6, 1, 11, 23, 59, 59, 999, 14 * 3600000, 2 * 3600000)[field]

    @jmethod("getMinimum", "(I)I")
    @jmethod("getGreatestMinimum", "(I)I")
    def getMinimum(self, field):
        return (0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, -13 * 3600000, 0)[field]

    @jmethod("getDisplayName", "(IILjava/util/Locale;)Ljava/lang/String;")
    def getDisplayName(self, field, style, locale):
        value = self.get(field)
        if field == MONTH:
            name = MONTHS[value]
        elif field == DAY_OF_WEEK:
            name = DAYS[value - 1]
        elif field == AM_PM:
            return "AM" if value == 0 else "PM"
        elif field == ERA:
            return "AD" if value else "BC"
        else:
            return None
        return name if style == 2 else name[:3]

    @jmethod("before", "(Ljava/lang/Object;)Z")
    def before(self, other):
        return 1 if isinstance(other, Calendar) and self.getTimeInMillis() < other.getTimeInMillis() else 0

    @jmethod("after", "(Ljava/lang/Object;)Z")
    def after(self, other):
        return 1 if isinstance(other, Calendar) and self.getTimeInMillis() > other.getTimeInMillis() else 0

    @jmethod("compareTo", "(Ljava/util/Calendar;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        a = self.getTimeInMillis()
        b = check_nonnull(other).getTimeInMillis()
        return (a > b) - (a < b)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Calendar) and other.getTimeInMillis() == self.getTimeInMillis() \
            and other._zone.id == self._zone.id and other._first == self._first \
            and other._min_days == self._min_days and other._lenient == self._lenient else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        value = self.getTimeInMillis()
        return runtime.wrap32(value ^ (value >> 32))

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        copy = type(self).__new__(type(self))
        copy.__dict__.update(self.__dict__)
        copy._fields = list(self._fields)
        copy._stamp = list(self._stamp)
        return copy

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "java.util.GregorianCalendar[time=%d,zone=%s]" % (self.getTimeInMillis(), self._zone.id)


@host_class("java.util.GregorianCalendar")
class GregorianCalendar(Calendar):
    BC = 0
    AD = 1

    @jmethod("<init>", "()V")
    def _init0(self):
        Calendar.__init__(self)

    @jmethod("<init>", "(Ljava/util/TimeZone;)V")
    def _init_zone(self, zone):
        Calendar.__init__(self, zone)

    @jmethod("<init>", "(Ljava/util/Locale;)V")
    def _init_locale(self, locale):
        Calendar.__init__(self, None, locale)

    @jmethod("<init>", "(Ljava/util/TimeZone;Ljava/util/Locale;)V")
    def _init_zone_locale(self, zone, locale):
        Calendar.__init__(self, zone, locale)

    @jmethod("<init>", "(III)V")
    @jmethod("<init>", "(IIIII)V")
    @jmethod("<init>", "(IIIIII)V")
    def _init_fields(self, year, month, day, hour=None, minute=None, second=None):
        Calendar.__init__(self)
        self.clear()
        self.set_date(year, month, day, hour, minute, second)

    @jmethod("isLeapYear", "(I)Z")
    def isLeapYear(self, year):
        return 1 if is_leap(year) else 0


@host_class("java.text.ParsePosition")
class ParsePosition(Object):
    def __init__(self, index=0):
        self._index = index
        self._error = -1

    @jmethod("<init>", "(I)V")
    def _init(self, index):
        ParsePosition.__init__(self, index)

    @jmethod("getIndex", "()I")
    def getIndex(self):
        return self._index

    @jmethod("setIndex", "(I)V")
    def setIndex(self, index):
        self._index = index

    @jmethod("getErrorIndex", "()I")
    def getErrorIndex(self):
        return self._error

    @jmethod("setErrorIndex", "(I)V")
    def setErrorIndex(self, index):
        self._error = index


@host_class("java.text.ParseException")
class ParseException(lookup_host("java.lang.Exception").py):
    _offset = 0

    @jmethod("<init>", "(Ljava/lang/String;I)V")
    def _init(self, message, offset):
        self._message = message
        self._cause = None
        self._offset = offset

    @jmethod("getErrorOffset", "()I")
    def getErrorOffset(self):
        return self._offset


@host_class("java.text.FieldPosition")
class FieldPosition(Object):
    def __init__(self, field=0):
        self._field = field
        self._begin = 0
        self._end = 0

    @jmethod("<init>", "(I)V")
    def _init(self, field):
        FieldPosition.__init__(self, field)

    @jmethod("getBeginIndex", "()I")
    def getBeginIndex(self):
        return self._begin

    @jmethod("getEndIndex", "()I")
    def getEndIndex(self):
        return self._end


_VALID = frozenset("GyYMLwWDdFEuaHkKhmsSzZX")
_TOKEN = re.compile(r"'(?:[^']|'')*'|''|([A-Za-z])\1*|[^A-Za-z']+")


def _tokens(pattern, valid=None):
    """(letter, count) for a pattern letter run, (None, text) for literal text"""
    out = []
    for match in _TOKEN.finditer(pattern):
        text = match.group(0)
        if text[0].isalpha():
            out.append((text[0], len(text)))
        elif text == "''":
            out.append((None, "'"))
        elif text[0] == "'":
            out.append((None, text[1:-1].replace("''", "'")))
        else:
            out.append((None, text))
    if re.search(r"'(?:[^']|'')*\Z", pattern) and pattern.count("'") % 2:
        runtime.throw_new("java.lang.IllegalArgumentException", "Unterminated quote")
    for letter, _ in out:
        if letter is not None and letter not in (valid or _VALID):
            runtime.throw_new("java.lang.IllegalArgumentException", "Illegal pattern character '%s'" % letter)
    return out


def _unparseable(text, offset):
    error = runtime.make_throwable(ParseException, 'Unparseable date: "%s"' % text)
    error._offset = offset
    raise error


def _pad(value, width):
    text = str(abs(value))
    return ("-" if value < 0 else "") + text.rjust(width, "0")


def _format(pattern, ms, zone, calendar=None):
    cal = calendar if calendar is not None else GregorianCalendar()
    cal._zone = zone
    cal.setTimeInMillis(ms)
    out = []
    for letter, count in _tokens(pattern):
        if letter is None:
            out.append(count)
            continue
        get = cal.get
        if letter == "G":
            out.append("AD" if get(ERA) else "BC")
        elif letter in "yY":
            year = get(YEAR)
            out.append(_pad(year % 100, 2) if count == 2 else _pad(year, count))
        elif letter in "ML":
            month = get(MONTH)
            if count >= 4:
                out.append(MONTHS[month])
            elif count == 3:
                out.append(MONTHS[month][:3])
            else:
                out.append(_pad(month + 1, count))
        elif letter == "E":
            name = DAYS[get(DAY_OF_WEEK) - 1]
            out.append(name if count >= 4 else name[:3])
        elif letter == "u":
            out.append(_pad((get(DAY_OF_WEEK) + 5) % 7 + 1, count))
        elif letter == "a":
            out.append("PM" if get(AM_PM) else "AM")
        elif letter == "H":
            out.append(_pad(get(HOUR_OF_DAY), count))
        elif letter == "k":
            out.append(_pad(get(HOUR_OF_DAY) or 24, count))
        elif letter == "K":
            out.append(_pad(get(HOUR), count))
        elif letter == "h":
            out.append(_pad(get(HOUR) or 12, count))
        elif letter == "m":
            out.append(_pad(get(MINUTE), count))
        elif letter == "s":
            out.append(_pad(get(SECOND), count))
        elif letter == "S":
            out.append(_pad(get(MILLISECOND), count))
        elif letter == "d":
            out.append(_pad(get(DAY_OF_MONTH), count))
        elif letter == "D":
            out.append(_pad(get(DAY_OF_YEAR), count))
        elif letter == "F":
            out.append(_pad(get(DAY_OF_WEEK_IN_MONTH), count))
        elif letter == "w":
            out.append(_pad(get(WEEK_OF_YEAR), count))
        elif letter == "W":
            out.append(_pad(get(WEEK_OF_MONTH), count))
        elif letter == "z":
            out.append(zone.id if count >= 4 and zone.kind != "fixed" else zone.short_name(ms))
        elif letter == "Z":
            out.append(_offset_text(zone.offset(ms), "rfc"))
        else:
            out.append(_offset_text(zone.offset(ms), "iso", count))
    return jstr("".join(out))


def _offset_text(offset_ms, style, count=2):
    minutes = abs(offset_ms) // 60000
    sign = "-" if offset_ms < 0 else "+"
    hours, rest = divmod(minutes, 60)
    if style == "rfc":
        return "%s%02d%02d" % (sign, hours, rest)
    if offset_ms == 0:
        return "Z"
    if count == 1:
        return "%s%02d" % (sign, hours)
    if count == 2:
        return "%s%02d%02d" % (sign, hours, rest)
    return "%s%02d:%02d" % (sign, hours, rest)


class _Reader:
    """a position in the text being parsed"""

    def __init__(self, text, pos):
        self.text = text
        self.pos = pos

    def number(self, width=None, signed=False):
        text = self.text
        start = self.pos
        pos = start
        if signed and pos < len(text) and text[pos] in "+-":
            pos += 1
        digits = pos
        limit = len(text) if width is None else min(len(text), pos + width)
        while pos < limit and text[pos].isascii() and text[pos].isdigit():
            pos += 1
        if pos == digits:
            return None
        self.pos = pos
        return int(text[start:pos])

    def name(self, names):
        rest = self.text[self.pos:].lower()
        best = None
        for index, name in names:
            if rest.startswith(name.lower()) and (best is None or len(name) > len(best[1])):
                best = (index, name)
        if best is None:
            return None
        self.pos += len(best[1])
        return best[0]


def _parse(pattern, text, pos, zone, lenient, century_start):
    """(milliseconds, end position) of text read by the pattern from pos, or (None, error position)"""
    tokens = _tokens(pattern)
    reader = _Reader(text, pos)
    cal = GregorianCalendar()
    cal._zone = zone
    cal.clear()
    cal.setLenient(lenient)
    offset = None
    pm = None
    hour12 = None
    for index, (letter, count) in enumerate(tokens):
        if letter is None:
            if not text.startswith(count, reader.pos):
                return None, reader.pos
            reader.pos += len(count)
            continue
        start = reader.pos
        numeric = letter in "yYMLdDFwWHkKhmsSu" and not (letter in "ML" and count >= 3)
        width = None
        if numeric and index + 1 < len(tokens) and tokens[index + 1][0] is not None \
                and tokens[index + 1][0] in "yYMLdDFwWHkKhmsSu":
            width = count
        if letter in "yY":
            value = reader.number(width, signed=True)
            if value is None:
                return None, start
            if count <= 2 and reader.pos - start == 2:
                base = century_start
                year = base - base % 100 + value
                if year < base:
                    year += 100
                value = year
            cal.set(YEAR, value)
        elif letter in "ML":
            if count >= 3:
                names = [(i, m) for i, m in enumerate(MONTHS)] + [(i, m[:3]) for i, m in enumerate(MONTHS)]
                value = reader.name(names)
                if value is None:
                    return None, start
                cal.set(MONTH, value)
            else:
                value = reader.number(width)
                if value is None:
                    return None, start
                cal.set(MONTH, value - 1)
        elif letter == "E":
            names = [(i + 1, d) for i, d in enumerate(DAYS)] + [(i + 1, d[:3]) for i, d in enumerate(DAYS)]
            value = reader.name(names)
            if value is None:
                return None, start
            cal.set(DAY_OF_WEEK, value)
        elif letter == "u":
            value = reader.number(width)
            if value is None:
                return None, start
            cal.set(DAY_OF_WEEK, value % 7 + 1)
        elif letter == "a":
            value = reader.name([(0, "AM"), (1, "PM")])
            if value is None:
                return None, start
            pm = value
        elif letter == "G":
            value = reader.name([(0, "BC"), (1, "AD")])
            if value is None:
                return None, start
            cal.set(ERA, value)
        elif letter in "zZX":
            offset_ms = _read_zone(reader)
            if offset_ms is None:
                return None, start
            offset = offset_ms
        else:
            value = reader.number(width)
            if value is None:
                return None, start
            field = {"d": DAY_OF_MONTH, "D": DAY_OF_YEAR, "F": DAY_OF_WEEK_IN_MONTH, "w": WEEK_OF_YEAR,
                     "W": WEEK_OF_MONTH, "H": HOUR_OF_DAY, "m": MINUTE, "s": SECOND, "S": MILLISECOND}.get(letter)
            if letter == "k":
                field, value = HOUR_OF_DAY, 0 if value == 24 else value
            elif letter == "K":
                field = HOUR
            elif letter == "h":
                field, hour12 = HOUR, value
                value %= 12
            cal.set(field, value)
    if pm is not None:
        cal.set(AM_PM, pm)
    if offset is not None:
        cal._zone = _Zone(_gmt_text(offset), "fixed", offset)
    if not lenient:
        try:
            cal.getTimeInMillis()
            for field in (MONTH, DAY_OF_MONTH, HOUR_OF_DAY, MINUTE, SECOND):
                if cal._stamp[field] > 1 and not cal._in_range(field, cal._fields[field]):
                    return None, pos
            if cal._stamp[DAY_OF_MONTH] > 1 and cal._fields[DAY_OF_MONTH] > month_length(
                    cal._fields[YEAR], cal._fields[MONTH]):
                return None, pos
        except Exception:
            return None, pos
    return cal.getTimeInMillis(), reader.pos


def _read_zone(reader):
    """the offset in ms of GMT+03:00, +0300, +03, Z or UTC at the reader, or None"""
    text = reader.text
    rest = text[reader.pos:]
    match = re.match(r"(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})?", rest)
    if match is not None:
        reader.pos += match.end()
        value = (int(match.group(2)) * 60 + int(match.group(3) or 0)) * 60000
        return -value if match.group(1) == "-" else value
    for name in ("UTC", "GMT", "Z"):
        if rest.startswith(name):
            reader.pos += len(name)
            return 0
    match = re.match(r"[A-Za-z]{2,5}", rest)
    if match is not None:
        zone = _find_zone(match.group(0))
        if zone is not None:
            reader.pos += match.end()
            return zone.raw()
    return None


@host_class("java.text.DateFormat", interfaces=("java.lang.Cloneable", "java.io.Serializable"))
class DateFormat(Object):
    FULL = 0
    LONG = 1
    MEDIUM = 2
    SHORT = 3
    DEFAULT = 2

    _DATE = ("EEEE, MMMM d, y", "MMMM d, y", "MMM d, y", "M/d/yy")
    _TIME = ("h:mm:ss a zzzz", "h:mm:ss a z", "h:mm:ss a", "h:mm a")

    def __init__(self):
        self._zone = default_zone()
        self._lenient = True
        self._pattern = ""
        self._century = _now_ms() // 31556952000 + 1970 - 80

    @jstatic("getDateInstance", "()Ljava/text/DateFormat;")
    @jstatic("getDateInstance", "(I)Ljava/text/DateFormat;")
    @jstatic("getDateInstance", "(ILjava/util/Locale;)Ljava/text/DateFormat;")
    def getDateInstance(style=2, locale=None):
        return SimpleDateFormat(DateFormat._DATE[style])

    @jstatic("getTimeInstance", "()Ljava/text/DateFormat;")
    @jstatic("getTimeInstance", "(I)Ljava/text/DateFormat;")
    @jstatic("getTimeInstance", "(ILjava/util/Locale;)Ljava/text/DateFormat;")
    def getTimeInstance(style=2, locale=None):
        return SimpleDateFormat(DateFormat._TIME[style])

    @jstatic("getDateTimeInstance", "()Ljava/text/DateFormat;")
    @jstatic("getDateTimeInstance", "(II)Ljava/text/DateFormat;")
    @jstatic("getDateTimeInstance", "(IILjava/util/Locale;)Ljava/text/DateFormat;")
    def getDateTimeInstance(date_style=2, time_style=2, locale=None):
        return SimpleDateFormat(DateFormat._DATE[date_style] + ", " + DateFormat._TIME[time_style])

    @jstatic("getInstance", "()Ljava/text/DateFormat;")
    def getInstance():
        return SimpleDateFormat(DateFormat._DATE[3] + ", " + DateFormat._TIME[3])

    @jmethod("setTimeZone", "(Ljava/util/TimeZone;)V")
    def setTimeZone(self, zone):
        self._zone = check_nonnull(zone)._zone

    @jmethod("getTimeZone", "()Ljava/util/TimeZone;")
    def getTimeZone(self):
        return TimeZone(self._zone)

    @jmethod("setLenient", "(Z)V")
    def setLenient(self, flag):
        self._lenient = bool(flag)

    @jmethod("isLenient", "()Z")
    def isLenient(self):
        return 1 if self._lenient else 0

    @jmethod("getCalendar", "()Ljava/util/Calendar;")
    def getCalendar(self):
        return GregorianCalendar(TimeZone(self._zone))

    @jmethod("setCalendar", "(Ljava/util/Calendar;)V")
    def setCalendar(self, calendar):
        self._zone = check_nonnull(calendar)._zone

    @jmethod("format", "(Ljava/util/Date;)Ljava/lang/String;")
    @jmethod("format", "(Ljava/lang/Object;)Ljava/lang/String;")
    @jmethod("format", "(Ljava/util/Date;Ljava/lang/StringBuffer;Ljava/text/FieldPosition;)Ljava/lang/StringBuffer;")
    @jmethod("format", "(Ljava/lang/Object;Ljava/lang/StringBuffer;Ljava/text/FieldPosition;)Ljava/lang/StringBuffer;")
    def format(self, value, buffer=None, position=None):
        if isinstance(value, Date):
            millis = value._ms
        elif hasattr(value, "longValue"):
            millis = value.longValue()
        else:
            runtime.throw_new("java.lang.IllegalArgumentException", "Cannot format given Object as a Date")
        text = _format(self._pattern, millis, self._zone)
        if buffer is None:
            return text
        buffer.append(text)
        return buffer

    @jmethod("parse", "(Ljava/lang/String;)Ljava/util/Date;")
    @jmethod("parse", "(Ljava/lang/String;Ljava/text/ParsePosition;)Ljava/util/Date;")
    def parse(self, text, position=None):
        start = 0 if position is None else position._index
        millis, end = _parse(self._pattern, check_nonnull(text), start, self._zone, self._lenient, self._century)
        if millis is None:
            if position is None:
                _unparseable(text, end)
            position._error = end
            return None
        if position is not None:
            position._index = end
        return Date(millis)


@host_class("java.text.SimpleDateFormat")
class SimpleDateFormat(DateFormat):
    def __init__(self, pattern="M/d/yy h:mm a", locale=None):
        DateFormat.__init__(self)
        _tokens(check_nonnull(pattern))
        self._pattern = pattern

    @jmethod("<init>", "()V")
    def _init0(self):
        SimpleDateFormat.__init__(self)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init1(self, pattern):
        SimpleDateFormat.__init__(self, pattern)

    @jmethod("<init>", "(Ljava/lang/String;Ljava/util/Locale;)V")
    def _init2(self, pattern, locale):
        SimpleDateFormat.__init__(self, pattern, locale)

    @jmethod("toPattern", "()Ljava/lang/String;")
    def toPattern(self):
        return self._pattern

    @jmethod("applyPattern", "(Ljava/lang/String;)V")
    def applyPattern(self, pattern):
        _tokens(check_nonnull(pattern))
        self._pattern = pattern

    @jmethod("set2DigitYearStart", "(Ljava/util/Date;)V")
    def set2DigitYearStart(self, date):
        calendar = GregorianCalendar()
        calendar.setTimeInMillis(check_nonnull(date)._ms)
        self._century = calendar.get(YEAR)
