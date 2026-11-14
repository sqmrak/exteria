import java.time.*;
import java.time.format.*;
import java.time.temporal.*;
import java.util.*;

/** DateTimeFormatter and DateTimeFormatterBuilder: patterns, the iso formatters, parsing and resolving, texts of errors */
public class TimeFmt {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    /** the field maps of a Parsed shown in sorted order: the jdk prints them in hash order of the fields */
    static String norm(String s) {
        s = s.replace(",-1", "");
        StringBuilder sb = new StringBuilder();
        int i = 0;
        while (i < s.length()) {
            int a = s.indexOf('{', i);
            int b = a < 0 ? -1 : s.indexOf('}', a);
            if (a < 0 || b < 0) { sb.append(s.substring(i)); break; }
            String inner = s.substring(a + 1, b);
            sb.append(s, i, a);
            if (inner.contains("=") && !inner.contains("{")) {
                String[] parts = inner.split(", ");
                Arrays.sort(parts);
                sb.append('{').append(String.join(", ", parts)).append('}');
            } else sb.append('{').append(inner).append('}');
            i = b + 1;
        }
        return sb.toString();
    }
    static String ps(Object o) { return norm(String.valueOf(o)); }

    interface Thrower { Object run() throws Exception; }
    static void t(String name, Thrower r) {
        try { Object v = r.run(); p(name, v instanceof String ? norm((String) v) : v); }
        catch (Throwable e) { p(name, e.getClass().getName() + ": " + norm(String.valueOf(e.getMessage()))); }
    }

    public static String run() {
        out = new StringBuilder();
        LocalDateTime dt = LocalDateTime.of(2024, 3, 5, 14, 7, 9, 123456789);
        LocalDateTime early = LocalDateTime.of(5, 1, 2, 0, 0, 0, 0);
        LocalDateTime night = LocalDateTime.of(2021, 12, 31, 0, 30, 0, 0);
        ZonedDateTime moscow = ZonedDateTime.of(dt, ZoneId.of("Europe/Moscow"));
        ZonedDateTime ny = ZonedDateTime.of(dt, ZoneId.of("America/New_York"));
        ZonedDateTime off = ZonedDateTime.of(dt, ZoneOffset.ofHoursMinutes(-3, -30));
        String[] patterns = {
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "y", "yy", "yyy", "yyyy", "yyyyy", "uuuu", "uu",
            "M/d/yy", "MM", "MMM", "MMMM", "MMMMM", "LLL", "LLLL", "d", "dd", "D", "DDD", "E", "EE", "EEE", "EEEE", "EEEEE",
            "e", "ee", "eee", "c", "a", "h", "hh", "H", "k", "K", "m", "s", "S", "SS", "SSSSSS", "SSSSSSSSS", "n", "nnnnnnnnnn", "N", "A",
            "G", "GGGG", "GGGGG", "Q", "QQ", "QQQ", "QQQQ", "QQQQQ", "q", "F",
            "h:mm a", "EEEE, MMMM d, y", "dd.MM.yyyy HH:mm", "'at' H 'o''clock'", "[yyyy][-MM]", "yyyy[-MM[-dd]]", "HH:mm[:ss]",
        };
        for (String s : patterns) {
            DateTimeFormatter f = DateTimeFormatter.ofPattern(s, Locale.US);
            t("fmt " + s, () -> f.format(dt));
            t("fmt early " + s, () -> f.format(early));
        }
        String[] zonePatterns = {"VV", "XXX", "XX", "X", "XXXX", "XXXXX", "xxx", "xx", "x", "xxxx", "xxxxx", "Z", "ZZ", "ZZZ", "ZZZZ", "ZZZZZ", "O", "OOOO"};
        for (String s : zonePatterns) {
            DateTimeFormatter f = DateTimeFormatter.ofPattern("HH:mm " + s, Locale.US);
            t("zone moscow " + s, () -> f.format(moscow));
            t("zone ny " + s, () -> f.format(ny));
            t("zone off " + s, () -> f.format(off));
            t("zone utc " + s, () -> f.format(dt.atZone(ZoneOffset.UTC)));
        }
        String[] bad = {"yyyy-MM-dd{", "'abc", "bbb", "dddd", "MMMMMM", "aa", "VVV", "OO", "ZZZZZZ", "xxxxxx", "hhh", "[", "]", "#", "pp", "pH"};
        for (String s : bad) {
            t("pattern " + s, () -> DateTimeFormatter.ofPattern(s, Locale.US).toString());
        }
        DateTimeFormatter[] iso = {DateTimeFormatter.ISO_LOCAL_DATE, DateTimeFormatter.ISO_LOCAL_TIME, DateTimeFormatter.ISO_LOCAL_DATE_TIME,
            DateTimeFormatter.ISO_OFFSET_DATE_TIME, DateTimeFormatter.ISO_ZONED_DATE_TIME, DateTimeFormatter.ISO_DATE_TIME, DateTimeFormatter.ISO_DATE,
            DateTimeFormatter.ISO_TIME, DateTimeFormatter.ISO_OFFSET_DATE, DateTimeFormatter.ISO_OFFSET_TIME, DateTimeFormatter.ISO_ORDINAL_DATE,
            DateTimeFormatter.ISO_INSTANT, DateTimeFormatter.BASIC_ISO_DATE, DateTimeFormatter.RFC_1123_DATE_TIME};
        String[] names = {"ISO_LOCAL_DATE", "ISO_LOCAL_TIME", "ISO_LOCAL_DATE_TIME", "ISO_OFFSET_DATE_TIME", "ISO_ZONED_DATE_TIME", "ISO_DATE_TIME",
            "ISO_DATE", "ISO_TIME", "ISO_OFFSET_DATE", "ISO_OFFSET_TIME", "ISO_ORDINAL_DATE", "ISO_INSTANT", "BASIC_ISO_DATE", "RFC_1123_DATE_TIME"};
        for (int i = 0; i < iso.length; i++) {
            DateTimeFormatter f = iso[i];
            String n = names[i];
            p("iso toString " + n, f);
            t("iso " + n + " dt", () -> f.format(dt));
            t("iso " + n + " night", () -> f.format(night));
            t("iso " + n + " moscow", () -> f.format(moscow));
            t("iso " + n + " off", () -> f.format(off));
            t("iso " + n + " date", () -> f.format(dt.toLocalDate()));
            t("iso " + n + " time", () -> f.format(dt.toLocalTime()));
            t("iso " + n + " instant", () -> f.format(Instant.ofEpochSecond(1700000000L, 5000000)));
            t("iso " + n + " instant zone", () -> f.withZone(ZoneOffset.UTC).format(Instant.ofEpochSecond(1700000000L, 5000000)));
        }
        t("instant plain", () -> DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(0)));
        t("instant micro", () -> DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(0, 123000)));
        t("instant nano", () -> DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(0, 1)));
        t("instant year5", () -> DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(300000000000L)));
        t("instant yearneg", () -> DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(-300000000000L)));
        // parsing
        String[][] parse = {
            {"ISO_LOCAL_DATE", "2024-03-05"}, {"ISO_LOCAL_DATE", "2024-3-5"}, {"ISO_LOCAL_DATE", "2024-02-30"}, {"ISO_LOCAL_DATE", "2023-02-29"},
            {"ISO_LOCAL_DATE", "+12345-01-01"}, {"ISO_LOCAL_DATE", "2024-13-01"}, {"ISO_LOCAL_DATE", "2024-03-05x"}, {"ISO_LOCAL_DATE", ""},
            {"ISO_LOCAL_TIME", "10:15"}, {"ISO_LOCAL_TIME", "10:15:30"}, {"ISO_LOCAL_TIME", "10:15:30.123456789"}, {"ISO_LOCAL_TIME", "24:00"},
            {"ISO_LOCAL_TIME", "10:15:30.1234567890"}, {"ISO_LOCAL_TIME", "25:00"}, {"ISO_LOCAL_TIME", "10:61"},
            {"ISO_LOCAL_DATE_TIME", "2024-03-05T10:15:30"}, {"ISO_LOCAL_DATE_TIME", "2024-03-05t10:15:30"}, {"ISO_LOCAL_DATE_TIME", "2024-03-05 10:15:30"},
            {"ISO_OFFSET_DATE_TIME", "2024-03-05T10:15:30+01:00"}, {"ISO_OFFSET_DATE_TIME", "2024-03-05T10:15:30Z"}, {"ISO_OFFSET_DATE_TIME", "2024-03-05T10:15:30"},
            {"ISO_ZONED_DATE_TIME", "2024-03-05T10:15:30+03:00[Europe/Moscow]"}, {"ISO_ZONED_DATE_TIME", "2024-03-05T10:15:30Z"},
            {"ISO_DATE_TIME", "2024-03-05T10:15:30+03:00[Europe/Moscow]"}, {"ISO_DATE_TIME", "2024-03-05T10:15"},
            {"ISO_INSTANT", "2024-03-05T10:15:30Z"}, {"ISO_INSTANT", "2024-03-05T10:15:30.5Z"}, {"ISO_INSTANT", "2024-03-05T10:15:30+01:00"},
            {"ISO_INSTANT", "2024-03-05T24:00:00Z"}, {"ISO_INSTANT", "2024-03-05T10:15Z"},
            {"ISO_ORDINAL_DATE", "2024-065"}, {"ISO_ORDINAL_DATE", "2023-366"}, {"BASIC_ISO_DATE", "20240305"}, {"BASIC_ISO_DATE", "20240305+0100"},
            {"RFC_1123_DATE_TIME", "Tue, 5 Mar 2024 10:15:30 GMT"}, {"RFC_1123_DATE_TIME", "5 Mar 2024 10:15 +0100"}, {"RFC_1123_DATE_TIME", "Wed, 5 Mar 2024 10:15:30 GMT"},
        };
        for (String[] c : parse) {
            DateTimeFormatter f = iso[Arrays.asList(names).indexOf(c[0])];
            t("parse " + c[0] + " " + c[1], () -> f.parse(c[1]).toString());
            t("parse ldt " + c[0] + " " + c[1], () -> LocalDateTime.parse(c[1], f).toString());
            t("parse ld " + c[0] + " " + c[1], () -> LocalDate.parse(c[1], f).toString());
            t("parse zdt " + c[0] + " " + c[1], () -> ZonedDateTime.parse(c[1], f).toString());
        }
        String[][] pp = {
            {"dd MMM yyyy", "05 Mar 2024"}, {"dd MMM yyyy", "05 mar 2024"}, {"dd MMMM yyyy", "05 March 2024"}, {"d.M.yy", "5.3.24"}, {"d.M.yy", "5.3.99"},
            {"yyyy-MM-dd HH:mm", "2024-03-05 14:07"}, {"yyyyMMdd", "20240305"}, {"yyyyMMddHHmmss", "20240305140709"}, {"HHmm", "1407"}, {"hh:mm a", "02:07 PM"},
            {"hh:mm a", "12:07 AM"}, {"h:mm a", "2:07 pm"}, {"EEE, d MMM yyyy", "Tue, 5 Mar 2024"}, {"EEE, d MMM yyyy", "Wed, 5 Mar 2024"}, {"EEEE", "Tuesday"},
            {"yyyy-MM-dd", "2024-02-31"}, {"yyyy-MM-dd", "2024-04-31"}, {"uuuu-MM-dd", "2024-02-30"}, {"yyyy-DDD", "2024-060"}, {"yyyy-DDD", "2023-366"},
            {"G yyyy", "BC 0044"}, {"GGGG yyyy", "Anno Domini 2024"}, {"yyyy-MM-dd'T'HH:mm:ss.SSS", "2024-03-05T14:07:09.123"}, {"HH:mm:ss.SSSSSS", "14:07:09.123456"},
            {"HH:mm:ss.SSS", "14:07:09.12"}, {"yyyy-MM-dd HH:mm:ss XXX", "2024-03-05 14:07:09 +03:00"}, {"yyyy-MM-dd HH:mm:ss XXX", "2024-03-05 14:07:09 Z"},
            {"yyyy-MM-dd HH:mm:ss VV", "2024-03-05 14:07:09 Europe/Moscow"}, {"yyyy-MM-dd HH:mm:ss VV", "2024-03-05 14:07:09 UTC"},
            {"yyyy-MM-dd HH:mm:ss VV", "2024-03-05 14:07:09 GMT+02:00"}, {"yyyy-MM-dd HH:mm:ss Z", "2024-03-05 14:07:09 +0300"},
            {"yyyy-MM-dd HH:mm:ss O", "2024-03-05 14:07:09 GMT+3"}, {"yyyy-MM-dd HH:mm:ss xx", "2024-03-05 14:07:09 -0530"},
            {"yyyy [MM]", "2024 03"}, {"yyyy [MM]", "2024 "}, {"QQQ yyyy", "Q2 2024"}, {"MM/dd", "02/30"}, {"yy", "24"}, {"yyyy", "12345"}, {"yyyy", "-0001"},
            {"HH:mm", "7:07"}, {"H:mm", "07:07"}, {"d MMMM", "5 March"}, {"kk:mm", "24:00"}, {"HH:mm", "24:00"}, {"HH:mm", "24:01"},
        };
        for (String[] c : pp) {
            DateTimeFormatter f = DateTimeFormatter.ofPattern(c[0], Locale.US);
            t("pp " + c[0] + " | " + c[1], () -> f.parse(c[1]).toString());
            t("pp ld " + c[0] + " | " + c[1], () -> LocalDate.parse(c[1], f).toString());
            t("pp lt " + c[0] + " | " + c[1], () -> LocalTime.parse(c[1], f).toString());
            t("pp ldt " + c[0] + " | " + c[1], () -> LocalDateTime.parse(c[1], f).toString());
            t("pp zdt " + c[0] + " | " + c[1], () -> ZonedDateTime.parse(c[1], f).toString());
            t("pp strict " + c[0] + " | " + c[1], () -> f.withResolverStyle(ResolverStyle.STRICT).parse(c[1]).toString());
            t("pp lenient " + c[0] + " | " + c[1], () -> f.withResolverStyle(ResolverStyle.LENIENT).parse(c[1]).toString());
        }
        // parse with a query, parseBest, ParsePosition, exceptions
        DateTimeFormatter f1 = DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US);
        t("query", () -> f1.parse("2024-03-05", LocalDate::from));
        t("query bad", () -> f1.parse("2024-03-05", LocalTime::from));
        t("query year", () -> f1.parse("2024-03-05", Year::from));
        t("query ym", () -> f1.parse("2024-03-05", YearMonth::from));
        t("best", () -> DateTimeFormatter.ISO_LOCAL_DATE_TIME.parseBest("2024-03-05T10:15", LocalDateTime::from, LocalDate::from));
        t("best date", () -> DateTimeFormatter.ISO_DATE_TIME.parseBest("2024-03-05", ZonedDateTime::from, LocalDateTime::from, LocalDate::from));
        t("best none", () -> DateTimeFormatter.ISO_DATE_TIME.parseBest("2024-03-05T10:15", ZonedDateTime::from, OffsetDateTime::from));
        t("pos", () -> { java.text.ParsePosition pos = new java.text.ParsePosition(5); Object o = f1.parse("xxxx 2024-03-05zz", pos); return o + " " + pos.getIndex(); });
        t("pos bad", () -> { java.text.ParsePosition pos = new java.text.ParsePosition(0); try { f1.parse("abc", pos); return "no"; } catch (DateTimeParseException e) { return e.getMessage() + " " + pos.getErrorIndex(); } });
        t("exc info", () -> { try { f1.parse("2024-03-0x"); return "no"; } catch (DateTimeParseException e) { return e.getParsedString() + " " + e.getErrorIndex(); } });
        t("exc long", () -> { try { f1.parse("2024-03-05 and a very long text after the date, which is longer than sixty four characters"); return "no"; } catch (DateTimeParseException e) { return e.getMessage(); } });
        t("exc resolve", () -> { try { f1.withResolverStyle(ResolverStyle.STRICT).parse("2024-02-30"); return "no"; } catch (DateTimeParseException e) { return e.getMessage() + " | " + e.getCause().getClass().getName(); } });
        t("format missing", () -> DateTimeFormatter.ofPattern("HH:mm", Locale.US).format(LocalDate.of(2024, 1, 1)));
        t("format missing zone", () -> DateTimeFormatter.ofPattern("yyyy VV", Locale.US).format(LocalDate.of(2024, 1, 1)));
        t("format zone override", () -> DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm XXX", Locale.US).withZone(ZoneOffset.ofHours(5)).format(Instant.ofEpochSecond(1700000000L)));
        t("format zone override zdt", () -> DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm XXX", Locale.US).withZone(ZoneOffset.ofHours(5)).format(moscow));
        t("format zone override local", () -> DateTimeFormatter.ofPattern("yyyy-MM-dd VV", Locale.US).withZone(ZoneId.of("Asia/Tokyo")).format(LocalDate.of(2024, 1, 1)));
        t("format instant", () -> DateTimeFormatter.ofPattern("yyyy", Locale.US).format(Instant.ofEpochSecond(0)));
        t("format year", () -> DateTimeFormatter.ofPattern("yyyy G", Locale.US).format(Year.of(2024)));
        t("format ym", () -> DateTimeFormatter.ofPattern("yyyy MMM", Locale.US).format(YearMonth.of(2024, 5)));
        t("format dow", () -> DateTimeFormatter.ofPattern("EEEE", Locale.US).format(DayOfWeek.MONDAY));
        t("null", () -> DateTimeFormatter.ofPattern("yyyy", Locale.US).format(null));
        // builder
        t("b1", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4).appendLiteral('/').appendValue(ChronoField.MONTH_OF_YEAR, 2).toFormatter().toString());
        t("b2", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4).appendLiteral('/').appendValue(ChronoField.MONTH_OF_YEAR, 2).toFormatter().format(dt));
        t("b3", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4, 10, SignStyle.ALWAYS).toFormatter().format(dt));
        t("b4", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4, 10, SignStyle.NEVER).toFormatter().format(LocalDate.of(-5, 1, 1)));
        t("b5", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4, 10, SignStyle.NORMAL).toFormatter().format(LocalDate.of(-5, 1, 1)));
        t("b6", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 2, 4, SignStyle.NOT_NEGATIVE).toFormatter().format(LocalDate.of(-5, 1, 1)));
        t("b7", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 2, 4, SignStyle.NOT_NEGATIVE).toFormatter().format(LocalDate.of(12345, 1, 1)));
        t("b8", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 2, 4, SignStyle.EXCEEDS_PAD).toFormatter().format(LocalDate.of(2024, 1, 1)));
        t("b9", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 2, 4, SignStyle.EXCEEDS_PAD).toFormatter().format(LocalDate.of(2024, 1, 1)));
        t("b10", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 2, 1980).toFormatter().toString());
        t("b11", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 2, 1980).toFormatter().format(LocalDate.of(2024, 1, 1)));
        t("b12", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 2, 1980).toFormatter().parse("79").toString());
        t("b13", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 2, 1980).toFormatter().parse("80").toString());
        t("b14", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 2, 1980).toFormatter().parse("2080").toString());
        t("b15", () -> new DateTimeFormatterBuilder().appendValueReduced(ChronoField.YEAR, 2, 4, LocalDate.of(2000, 1, 1)).toFormatter().parse("99").toString());
        t("b16", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 0, 9, true).toFormatter().toString());
        t("b17", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 2, 5, true).toFormatter().format(dt));
        t("b18", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 0, 9, true).toFormatter().format(dt.withNano(0)));
        t("b19", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 3, 3, false).toFormatter().format(dt));
        t("b20", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.MILLI_OF_SECOND, 0, 3, true).toFormatter().format(dt));
        t("b21", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.SECOND_OF_MINUTE, 0, 3, true).toFormatter().format(dt));
        t("b22", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 0, 9, true).toFormatter().parse(".5").toString());
        t("b23", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 3, 3, true).toFormatter().parse(".5").toString());
        t("b24", () -> new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR).toFormatter(Locale.US).format(dt));
        t("b25", () -> new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR, TextStyle.SHORT).toFormatter(Locale.US).format(dt));
        t("b26", () -> new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR, TextStyle.NARROW).toFormatter(Locale.US).format(dt));
        t("b27", () -> new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR, TextStyle.SHORT).toFormatter().toString());
        t("b28", () -> new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR).toFormatter().toString());
        t("b29", () -> new DateTimeFormatterBuilder().appendText(ChronoField.DAY_OF_MONTH, TextStyle.SHORT).toFormatter().format(dt));
        t("b30", () -> {
            Map<Long, String> m = new HashMap<>();
            m.put(1L, "one"); m.put(2L, "two"); m.put(3L, "three");
            DateTimeFormatter f = new DateTimeFormatterBuilder().appendText(ChronoField.MONTH_OF_YEAR, m).toFormatter();
            return f.format(LocalDate.of(2024, 3, 1)) + " " + f.format(LocalDate.of(2024, 5, 1)) + " " + f.parse("two").get(ChronoField.MONTH_OF_YEAR);
        });
        t("b31", () -> new DateTimeFormatterBuilder().appendPattern("yyyy-MM-dd").appendLiteral(" at ").appendPattern("HH:mm").toFormatter().format(dt));
        t("b32", () -> new DateTimeFormatterBuilder().appendPattern("yyyy-MM-dd").appendLiteral(" at ").appendPattern("HH:mm").toFormatter().toString());
        t("b33", () -> new DateTimeFormatterBuilder().optionalStart().appendPattern("HH:mm").optionalEnd().appendLiteral('!').toFormatter().toString());
        t("b34", () -> new DateTimeFormatterBuilder().optionalStart().appendPattern("HH:mm").optionalEnd().appendLiteral('!').toFormatter().format(dt.toLocalDate()));
        t("b35", () -> new DateTimeFormatterBuilder().optionalStart().appendPattern("HH:mm").optionalEnd().appendLiteral('!').toFormatter().format(dt));
        t("b36", () -> new DateTimeFormatterBuilder().appendPattern("HH").optionalStart().appendLiteral(':').appendPattern("mm").toFormatter().parse("14").toString());
        t("b37", () -> new DateTimeFormatterBuilder().appendPattern("HH").optionalStart().appendLiteral(':').appendPattern("mm").toFormatter().parse("14:30").toString());
        t("b38", () -> new DateTimeFormatterBuilder().appendPattern("HH").optionalStart().appendLiteral(':').appendPattern("mm").toFormatter().parse("14:3").toString());
        t("b39", () -> new DateTimeFormatterBuilder().optionalEnd().toFormatter().toString());
        t("b40", () -> new DateTimeFormatterBuilder().appendOptional(DateTimeFormatter.ISO_LOCAL_TIME).toFormatter().toString());
        t("b41", () -> new DateTimeFormatterBuilder().append(DateTimeFormatter.ISO_LOCAL_DATE).appendLiteral('T').appendOptional(DateTimeFormatter.ISO_LOCAL_TIME).toFormatter().parse("2024-03-05T10:15").toString());
        t("b42", () -> new DateTimeFormatterBuilder().append(DateTimeFormatter.ISO_LOCAL_DATE).appendLiteral('T').appendOptional(DateTimeFormatter.ISO_LOCAL_TIME).toFormatter().parse("2024-03-05T").toString());
        t("b43", () -> new DateTimeFormatterBuilder().padNext(5).appendValue(ChronoField.DAY_OF_MONTH).toFormatter().format(dt));
        t("b44", () -> new DateTimeFormatterBuilder().padNext(5, '*').appendValue(ChronoField.DAY_OF_MONTH).toFormatter().format(dt));
        t("b45", () -> new DateTimeFormatterBuilder().padNext(5, '*').appendValue(ChronoField.DAY_OF_MONTH).toFormatter().toString());
        t("b46", () -> new DateTimeFormatterBuilder().padNext(5, '*').appendValue(ChronoField.DAY_OF_MONTH).toFormatter().parse("***12").toString());
        t("b47", () -> new DateTimeFormatterBuilder().padNext(2).appendValue(ChronoField.YEAR).toFormatter().format(dt));
        t("b48", () -> new DateTimeFormatterBuilder().appendOffset("+HH:MM:ss", "Z").toFormatter().toString());
        t("b49", () -> new DateTimeFormatterBuilder().appendOffset("+HH:MM", "ZZ").toFormatter().format(off));
        t("b50", () -> new DateTimeFormatterBuilder().appendOffset("+HHMM", "+0").toFormatter().format(dt.atZone(ZoneOffset.UTC)));
        t("b51", () -> new DateTimeFormatterBuilder().appendOffset("bad", "Z").toFormatter().toString());
        for (String pat : new String[]{"+H", "+Hmm", "+H:mm", "+HMM", "+H:MM", "+HMMss", "+H:MM:ss", "+HMMSS", "+H:MM:SS", "+Hmmss", "+H:mm:ss", "+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss", "+HHMMSS", "+HH:MM:SS", "+HHmmss", "+HH:mm:ss"}) {
            for (int secs : new int[]{0, 3600, -3600, 36000, 5400, -5430, 3661, -45296, 61200}) {
                ZoneOffset o = ZoneOffset.ofTotalSeconds(secs);
                DateTimeFormatter f = new DateTimeFormatterBuilder().appendOffset(pat, "Z").toFormatter();
                String printed;
                try { printed = f.format(dt.atOffset(o)); } catch (Exception e) { printed = e.toString(); }
                String back;
                try { back = String.valueOf(f.parse(printed).get(ChronoField.OFFSET_SECONDS)); } catch (Exception e) { back = e.getClass().getSimpleName(); }
                p("offset " + pat + " " + secs, printed + " -> " + back);
            }
        }
        t("b52", () -> new DateTimeFormatterBuilder().appendLocalizedOffset(TextStyle.FULL).toFormatter().format(off));
        t("b53", () -> new DateTimeFormatterBuilder().appendLocalizedOffset(TextStyle.SHORT).toFormatter().format(off));
        t("b54", () -> new DateTimeFormatterBuilder().appendLocalizedOffset(TextStyle.SHORT).toFormatter().format(moscow));
        t("b55", () -> new DateTimeFormatterBuilder().appendLocalizedOffset(TextStyle.FULL).toFormatter().parse("GMT+03:00").toString());
        t("b56", () -> new DateTimeFormatterBuilder().appendLocalizedOffset(TextStyle.NARROW).toFormatter().toString());
        t("b57", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().format(moscow));
        t("b58", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().format(off));
        t("b60", () -> new DateTimeFormatterBuilder().appendZoneRegionId().toFormatter().format(moscow));
        t("b61", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().format(dt));
        t("b62", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().toString());
        t("b63", () -> new DateTimeFormatterBuilder().appendZoneRegionId().toFormatter().toString());
        t("b64", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("Europe/Moscow").toString());
        t("b65", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("America/Argentina/Buenos_Aires").toString());
        t("b66", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("+05:30").toString());
        t("b67", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("Nowhere/Land").toString());
        t("b68", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("UTC+3").toString());
        t("b69", () -> new DateTimeFormatterBuilder().appendZoneId().toFormatter().parse("GMT").toString());
        t("b70", () -> new DateTimeFormatterBuilder().appendInstant().toFormatter().toString());
        t("b71", () -> new DateTimeFormatterBuilder().appendInstant(3).toFormatter().format(Instant.ofEpochSecond(0, 1500000)));
        t("b72", () -> new DateTimeFormatterBuilder().appendInstant(0).toFormatter().format(Instant.ofEpochSecond(0, 1500000)));
        t("b73", () -> new DateTimeFormatterBuilder().appendInstant(-1).toFormatter().format(Instant.ofEpochSecond(0, 1500000)));
        t("b74", () -> new DateTimeFormatterBuilder().appendInstant(-1).toFormatter().format(Instant.ofEpochSecond(0)));
        t("b75", () -> new DateTimeFormatterBuilder().appendInstant(12).toFormatter().toString());
        t("b76", () -> new DateTimeFormatterBuilder().appendInstant(6).toFormatter().parse("2024-03-05T10:15:30.123456Z").toString());
        t("b77", () -> new DateTimeFormatterBuilder().appendInstant(6).toFormatter().parse("2024-03-05T10:15:30.123Z").toString());
        t("b78", () -> new DateTimeFormatterBuilder().parseCaseInsensitive().appendPattern("MMM").toFormatter(Locale.US).parse("mAr").toString());
        t("b79", () -> new DateTimeFormatterBuilder().parseCaseSensitive().appendPattern("MMM").toFormatter(Locale.US).parse("mAr").toString());
        t("b80", () -> new DateTimeFormatterBuilder().parseLenient().appendPattern("yyyy-MM-dd").toFormatter().parse("2024-3-5").toString());
        t("b81", () -> new DateTimeFormatterBuilder().parseStrict().appendPattern("yyyy-MM-dd").toFormatter().parse("2024-3-5").toString());
        t("b82", () -> new DateTimeFormatterBuilder().parseCaseInsensitive().parseLenient().toFormatter().toString());
        t("b83", () -> new DateTimeFormatterBuilder().parseDefaulting(ChronoField.YEAR, 2000).appendPattern("MM-dd").toFormatter().parse("03-05").toString());
        t("b84", () -> new DateTimeFormatterBuilder().parseDefaulting(ChronoField.YEAR, 2000).appendPattern("MM-dd").toFormatter().parse("03-05").query(java.time.temporal.TemporalQueries.localDate()));
        t("b85", () -> LocalDate.parse("03-05", new DateTimeFormatterBuilder().parseDefaulting(ChronoField.YEAR, 2000).appendPattern("MM-dd").toFormatter()).toString());
        t("b86", () -> LocalDateTime.parse("2024-03-05", new DateTimeFormatterBuilder().appendPattern("yyyy-MM-dd").parseDefaulting(ChronoField.HOUR_OF_DAY, 0).toFormatter()).toString());
        t("b87", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.HOUR_OF_DAY, 2).appendValue(ChronoField.MINUTE_OF_HOUR, 2).toFormatter().toString());
        t("b88", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.HOUR_OF_DAY, 2).appendValue(ChronoField.MINUTE_OF_HOUR, 2).toFormatter().parse("0930").toString());
        t("b89", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR).appendValue(ChronoField.MONTH_OF_YEAR, 2).appendValue(ChronoField.DAY_OF_MONTH, 2).toFormatter().parse("20240305").toString());
        t("b90", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR).appendValue(ChronoField.MONTH_OF_YEAR, 2).appendValue(ChronoField.DAY_OF_MONTH, 2).toFormatter().parse("1200101").toString());
        t("b91", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4).appendValue(ChronoField.DAY_OF_YEAR, 3).toFormatter().parse("2024065").toString());
        t("b92", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.MONTH_OF_YEAR).appendValue(ChronoField.DAY_OF_MONTH).toFormatter().parse("1231").toString());
        t("b93", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 4).appendFraction(ChronoField.NANO_OF_SECOND, 3, 3, false).toFormatter().parse("2024123").toString());
        t("b94", () -> new DateTimeFormatterBuilder().appendValue(null).toFormatter().toString());
        t("b95", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 0).toFormatter().toString());
        t("b96", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 5, 4, SignStyle.NORMAL).toFormatter().toString());
        t("b97", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR, 20).toFormatter().toString());
        t("b98", () -> new DateTimeFormatterBuilder().appendFraction(ChronoField.NANO_OF_SECOND, 5, 2, false).toFormatter().toString());
        t("b99", () -> new DateTimeFormatterBuilder().appendLiteral("").toFormatter().toString());
        t("b100", () -> new DateTimeFormatterBuilder().appendLiteral("it's").appendLiteral('\'').toFormatter().toString());
        t("b101", () -> new DateTimeFormatterBuilder().appendLiteral("it's").appendLiteral('\'').toFormatter().format(dt));
        t("b102", () -> new DateTimeFormatterBuilder().appendLiteral("ab").toFormatter().parse("ac").toString());
        t("b103", () -> new DateTimeFormatterBuilder().toFormatter().toString());
        t("b106", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.AMPM_OF_DAY).appendText(ChronoField.AMPM_OF_DAY, TextStyle.NARROW).toFormatter(Locale.US).format(dt));
        t("b107", () -> new DateTimeFormatterBuilder().appendText(ChronoField.ERA, TextStyle.FULL).toFormatter(Locale.US).format(early));
        t("b108", () -> new DateTimeFormatterBuilder().appendText(ChronoField.ERA, TextStyle.NARROW).toFormatter(Locale.US).format(LocalDate.of(-5, 1, 1)));
        t("b109", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR_OF_ERA).appendLiteral(' ').appendText(ChronoField.ERA).toFormatter(Locale.US).format(LocalDate.of(-5, 1, 1)));
        t("b110", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR_OF_ERA).appendLiteral(' ').appendText(ChronoField.ERA).toFormatter(Locale.US).parse("6 BC").toString());
        t("b111", () -> new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR_OF_ERA).appendLiteral(' ').appendText(ChronoField.ERA).toFormatter(Locale.US).parse("6 BC").query(TemporalQueries.localDate()));
        t("b112", () -> LocalDate.parse("6 BC", new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR_OF_ERA).appendLiteral(' ').appendText(ChronoField.ERA).appendPattern("-MM-dd").toFormatter(Locale.US)));
        t("b113", () -> LocalDate.parse("6 BC-03-01", new DateTimeFormatterBuilder().appendValue(ChronoField.YEAR_OF_ERA).appendLiteral(' ').appendText(ChronoField.ERA).appendPattern("-MM-dd").toFormatter(Locale.US)).toString());
        t("b114", () -> new DateTimeFormatterBuilder().appendPattern("yyyy-MM-dd").toFormatter().withZone(ZoneId.of("Asia/Tokyo")).getZone().toString());
        t("b115", () -> DateTimeFormatter.ISO_LOCAL_DATE.getResolverStyle().toString());
        t("b116", () -> DateTimeFormatter.ofPattern("yyyy", Locale.US).getResolverStyle().toString());
        t("b117", () -> DateTimeFormatter.ofPattern("yyyy", Locale.US).withResolverStyle(ResolverStyle.LENIENT).getResolverStyle().toString());
        t("b118", () -> DateTimeFormatter.ISO_LOCAL_DATE.getChronology().toString());
        t("b119", () -> DateTimeFormatter.ISO_LOCAL_DATE.getZone());
        t("b120", () -> DateTimeFormatter.ISO_LOCAL_DATE.withZone(ZoneOffset.UTC).getZone().toString());
        // localized
        for (FormatStyle fs : FormatStyle.values()) {
            t("loc date " + fs, () -> DateTimeFormatter.ofLocalizedDate(fs).withLocale(Locale.US).format(dt));
            t("loc time " + fs, () -> DateTimeFormatter.ofLocalizedTime(fs).withLocale(Locale.US).format(dt.atZone(ZoneOffset.UTC)).replace(' ', '_'));
            t("loc dt " + fs, () -> DateTimeFormatter.ofLocalizedDateTime(fs).withLocale(Locale.US).format(dt.atZone(ZoneOffset.UTC)).replace(' ', '_'));
            t("loc str " + fs, () -> DateTimeFormatter.ofLocalizedDate(fs).toString());
        }
        t("loc dt2", () -> DateTimeFormatter.ofLocalizedDateTime(FormatStyle.LONG, FormatStyle.SHORT).withLocale(Locale.US).format(dt.atZone(ZoneOffset.UTC)).replace(' ', '_'));
        t("loc str2", () -> DateTimeFormatter.ofLocalizedDateTime(FormatStyle.LONG, FormatStyle.SHORT).toString());
        t("loc pattern", () -> DateTimeFormatterBuilder.getLocalizedDateTimePattern(FormatStyle.MEDIUM, null, java.time.chrono.IsoChronology.INSTANCE, Locale.US));
        t("loc pattern2", () -> DateTimeFormatterBuilder.getLocalizedDateTimePattern(null, FormatStyle.SHORT, java.time.chrono.IsoChronology.INSTANCE, Locale.US).replace(' ', '_'));
        t("loc pattern3", () -> DateTimeFormatterBuilder.getLocalizedDateTimePattern(null, null, java.time.chrono.IsoChronology.INSTANCE, Locale.US));
        // methods on temporals
        t("ldt format", () -> dt.format(DateTimeFormatter.ofPattern("yyyy/MM/dd", Locale.US)));
        t("ld format", () -> dt.toLocalDate().format(DateTimeFormatter.ISO_DATE));
        t("zdt format", () -> moscow.format(DateTimeFormatter.RFC_1123_DATE_TIME));
        t("odt format", () -> moscow.toOffsetDateTime().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME));
        t("odt parse", () -> OffsetDateTime.parse("2024-03-05T10:15:30+01:00", DateTimeFormatter.ISO_OFFSET_DATE_TIME).toString());
        t("zdt parse", () -> ZonedDateTime.parse("Tue, 5 Mar 2024 10:15:30 +0100", DateTimeFormatter.RFC_1123_DATE_TIME).toString());
        t("zdt parse2", () -> ZonedDateTime.parse("2024-03-05T10:15:30", DateTimeFormatter.ISO_LOCAL_DATE_TIME.withZone(ZoneId.of("Asia/Tokyo"))).toString());
        t("instant from", () -> Instant.from(DateTimeFormatter.ISO_INSTANT.parse("2024-03-05T10:15:30Z")).toString());
        t("instant from zdt", () -> Instant.from(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse("2024-03-05T10:15:30+01:00")).toString());
        t("ldt from", () -> LocalDateTime.from(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse("2024-03-05T10:15:30+01:00")).toString());
        t("odt from", () -> OffsetDateTime.from(DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse("2024-03-05T10:15:30+01:00")).toString());
        t("ta get", () -> DateTimeFormatter.ISO_LOCAL_DATE.parse("2024-03-05").get(ChronoField.DAY_OF_YEAR));
        t("ta get2", () -> DateTimeFormatter.ISO_LOCAL_DATE.parse("2024-03-05").getLong(ChronoField.HOUR_OF_DAY));
        t("ta supported", () -> DateTimeFormatter.ISO_LOCAL_DATE.parse("2024-03-05").isSupported(ChronoField.YEAR) + " " + DateTimeFormatter.ISO_LOCAL_DATE.parse("2024-03-05").isSupported(ChronoField.HOUR_OF_DAY));
        t("ta query", () -> DateTimeFormatter.ISO_LOCAL_DATE.parse("2024-03-05").query(TemporalQueries.localTime()));
        return out.toString();
    }
}
