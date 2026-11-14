import java.time.*;
import java.time.chrono.*;
import java.time.format.*;
import java.time.temporal.*;
import java.util.*;

/** java.time.chrono: ISO, Minguo, Thai Buddhist and Japanese calendars, eras, and TemporalQueries */
public class Chrono {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }
    interface Thrower { Object run() throws Exception; }
    static void t(String name, Thrower r) {
        try { p(name, r.run()); }
        catch (Throwable e) { p(name, e.getClass().getName() + ": " + e.getMessage()); }
    }

    public static String run() {
        out = new StringBuilder();
        LocalDate d = LocalDate.of(2024, 3, 5);
        LocalDate old = LocalDate.of(1900, 12, 31);
        LocalDate bc = LocalDate.of(-4, 2, 29);
        Chronology[] all = {IsoChronology.INSTANCE, MinguoChronology.INSTANCE, ThaiBuddhistChronology.INSTANCE, JapaneseChronology.INSTANCE};
        for (Chronology c : all) {
            String n = c.getId();
            p(n + " id", c.getId() + " " + c.getCalendarType() + " " + c);
            t(n + " date d", () -> c.date(d).toString());
            t(n + " date old", () -> c.date(old).toString());
            t(n + " date bc", () -> c.date(bc).toString());
            t(n + " ymd", () -> c.date(2024, 2, 29).toString());
            t(n + " ymd bad", () -> c.date(2023, 2, 29).toString());
            t(n + " yd", () -> c.dateYearDay(2024, 60).toString());
            t(n + " epoch", () -> c.dateEpochDay(19000).toString());
            t(n + " leap", () -> c.isLeapYear(2024) + " " + c.isLeapYear(2023) + " " + c.isLeapYear(2100));
            t(n + " eras", () -> c.eras().toString());
            t(n + " range year", () -> c.range(ChronoField.YEAR).toString());
            t(n + " range yoe", () -> c.range(ChronoField.YEAR_OF_ERA).toString());
            t(n + " range moy", () -> c.range(ChronoField.MONTH_OF_YEAR).toString());
            t(n + " compare", () -> c.compareTo(IsoChronology.INSTANCE) < 0 ? "lt" : c.compareTo(IsoChronology.INSTANCE) == 0 ? "eq" : "gt");
            t(n + " equals", () -> c.equals(Chronology.of(c.getId())) + " " + (c == Chronology.of(c.getCalendarType())));
            t(n + " hash", () -> c.hashCode() == Chronology.of(c.getId()).hashCode());
            t(n + " from", () -> Chronology.from(d).getId());
        }
        t("of bad", () -> Chronology.of("nope"));
        t("avail", () -> { List<String> ids = new ArrayList<>(); for (Chronology c : Chronology.getAvailableChronologies()) if (c instanceof IsoChronology || c instanceof MinguoChronology || c instanceof ThaiBuddhistChronology || c instanceof JapaneseChronology) ids.add(c.getId()); Collections.sort(ids); return ids; });
        // dates
        MinguoDate m = MinguoDate.of(113, 3, 5);
        ThaiBuddhistDate th = ThaiBuddhistDate.of(2567, 3, 5);
        JapaneseDate jp = JapaneseDate.of(2024, 3, 5);
        ChronoLocalDate[] dates = {m, th, jp, d};
        for (ChronoLocalDate x : dates) {
            String n = x.getClass().getSimpleName();
            p(n + " str", x);
            p(n + " era", x.getEra() + " " + x.getEra().getValue());
            p(n + " chrono", x.getChronology());
            p(n + " epoch", x.toEpochDay());
            p(n + " len", x.lengthOfMonth() + " " + x.lengthOfYear() + " " + x.isLeapYear());
            for (ChronoField f : new ChronoField[]{ChronoField.YEAR, ChronoField.YEAR_OF_ERA, ChronoField.ERA, ChronoField.MONTH_OF_YEAR, ChronoField.DAY_OF_MONTH, ChronoField.DAY_OF_YEAR, ChronoField.DAY_OF_WEEK, ChronoField.EPOCH_DAY, ChronoField.PROLEPTIC_MONTH, ChronoField.ALIGNED_WEEK_OF_MONTH, ChronoField.HOUR_OF_DAY}) {
                t(n + " get " + f, () -> x.getLong(f));
                t(n + " sup " + f, () -> x.isSupported(f));
            }
            t(n + " plusD", () -> x.plus(30, ChronoUnit.DAYS).toString());
            t(n + " plusM", () -> x.plus(11, ChronoUnit.MONTHS).toString());
            t(n + " plusY", () -> x.plus(5, ChronoUnit.YEARS).toString());
            t(n + " minusY", () -> x.minus(2000, ChronoUnit.YEARS).toString());
            t(n + " plusW", () -> x.plus(2, ChronoUnit.WEEKS).toString());
            t(n + " plusDec", () -> x.plus(1, ChronoUnit.DECADES).toString());
            t(n + " with year", () -> x.with(ChronoField.YEAR, 2000 + (x instanceof MinguoDate ? -1911 : x instanceof ThaiBuddhistDate ? 543 : 0)).toString());
            t(n + " with dom", () -> x.with(ChronoField.DAY_OF_MONTH, 29).toString());
            t(n + " with moy", () -> x.with(ChronoField.MONTH_OF_YEAR, 2).with(ChronoField.DAY_OF_MONTH, 30).toString());
            t(n + " with doy", () -> x.with(ChronoField.DAY_OF_YEAR, 366).toString());
            t(n + " until", () -> x.until(x.plus(400, ChronoUnit.DAYS)).toString());
            t(n + " until unit", () -> x.until(x.plus(400, ChronoUnit.DAYS), ChronoUnit.MONTHS));
            t(n + " cmp", () -> x.isBefore(x.plus(1, ChronoUnit.DAYS)) + " " + x.isAfter(x) + " " + x.isEqual(x) + " " + x.compareTo(x.plus(1, ChronoUnit.DAYS)));
            t(n + " eq", () -> x.equals(x.plus(0, ChronoUnit.DAYS)) + " " + x.equals(x.plus(1, ChronoUnit.DAYS)) + " " + (x.hashCode() == x.plus(0, ChronoUnit.DAYS).hashCode()));
            t(n + " atTime", () -> x.atTime(LocalTime.NOON).toString());
        }
        // conversions
        t("minguo from", () -> MinguoDate.from(d).toString());
        t("thai from", () -> ThaiBuddhistDate.from(d).toString());
        t("jp from", () -> JapaneseDate.from(d).toString());
        t("ld from", () -> LocalDate.from(m).toString() + " " + LocalDate.from(th) + " " + LocalDate.from(jp));
        t("minguo bc", () -> MinguoDate.from(LocalDate.of(1900, 1, 1)).toString());
        t("minguo bc2", () -> MinguoDate.from(LocalDate.of(1911, 12, 31)).toString() + " " + MinguoDate.from(LocalDate.of(1912, 1, 1)));
        t("thai bc", () -> ThaiBuddhistDate.from(LocalDate.of(-543, 6, 1)).toString() + " " + ThaiBuddhistDate.from(LocalDate.of(-544, 6, 1)));
        t("thai ofEra", () -> ThaiBuddhistChronology.INSTANCE.date(ThaiBuddhistEra.BEFORE_BE, 10, 1, 1).toString());
        t("minguo ofEra", () -> MinguoChronology.INSTANCE.date(MinguoEra.ROC, 5, 1, 1).toString());
        t("minguo prolepticYear", () -> MinguoChronology.INSTANCE.prolepticYear(MinguoEra.BEFORE_ROC, 5) + " " + MinguoChronology.INSTANCE.prolepticYear(MinguoEra.ROC, 5));
        t("thai prolepticYear", () -> ThaiBuddhistChronology.INSTANCE.prolepticYear(ThaiBuddhistEra.BEFORE_BE, 5) + " " + ThaiBuddhistChronology.INSTANCE.prolepticYear(ThaiBuddhistEra.BE, 5));
        t("iso prolepticYear", () -> IsoChronology.INSTANCE.prolepticYear(IsoEra.BCE, 5) + " " + IsoChronology.INSTANCE.prolepticYear(IsoEra.CE, 5));
        t("iso eraOf", () -> IsoChronology.INSTANCE.eraOf(0) + " " + IsoChronology.INSTANCE.eraOf(1));
        t("iso eraOf bad", () -> IsoChronology.INSTANCE.eraOf(2));
        t("minguo eraOf", () -> MinguoChronology.INSTANCE.eraOf(0) + " " + MinguoChronology.INSTANCE.eraOf(1));
        // japanese
        String[] eraNames = {"MEIJI", "TAISHO", "SHOWA", "HEISEI", "REIWA"};
        for (JapaneseEra e : JapaneseEra.values()) {
            p("jera " + e, e.getValue() + " " + e.getDisplayName(TextStyle.FULL, Locale.US));
        }
        t("jera of", () -> JapaneseEra.of(3) + " " + JapaneseEra.of(-1));
        t("jera of bad", () -> JapaneseEra.of(4));
        t("jera of bad2", () -> JapaneseEra.of(-2));
        t("jera valueOf", () -> JapaneseEra.valueOf("Heisei").getValue());
        t("jera valueOf bad", () -> JapaneseEra.valueOf("Foo"));
        t("jera const", () -> JapaneseEra.of(3) + " " + JapaneseEra.of(2) + " " + JapaneseEra.of(1));
        t("jp heisei", () -> JapaneseDate.of(JapaneseEra.of(2), 31, 4, 30).toString());
        t("jp reiwa1", () -> JapaneseDate.of(JapaneseEra.of(3), 1, 5, 1).toString());
        t("jp reiwa bad", () -> JapaneseDate.of(JapaneseEra.of(3), 1, 4, 30).toString());
        t("jp from 1989", () -> JapaneseDate.from(LocalDate.of(1989, 1, 7)) + " " + JapaneseDate.from(LocalDate.of(1989, 1, 8)));
        t("jp from 1873", () -> JapaneseDate.from(LocalDate.of(1873, 1, 1)).toString());
        t("jp from 1872", () -> JapaneseDate.from(LocalDate.of(1872, 12, 31)).toString());
        t("jp era of", () -> JapaneseDate.of(2019, 5, 1).getEra() + " " + JapaneseDate.of(2019, 4, 30).getEra());
        t("jp yoe", () -> JapaneseDate.of(2019, 5, 1).get(ChronoField.YEAR_OF_ERA) + " " + JapaneseDate.of(2019, 4, 30).get(ChronoField.YEAR_OF_ERA));
        // formatting with a chronology
        String[] pats = {"G y-MM-dd", "GGGG yyyy MMMM d", "GGGGG u", "yyyy/MM/dd", "G"};
        for (Chronology c : all) {
            for (String pat : pats) {
                DateTimeFormatter f = DateTimeFormatter.ofPattern(pat, Locale.US).withChronology(c);
                t("fmt " + c.getId() + " " + pat, () -> f.format(d));
                t("fmt old " + c.getId() + " " + pat, () -> f.format(old));
                t("fmt dated " + c.getId() + " " + pat, () -> f.format(c.date(d)));
            }
            t("fmt chrono " + c.getId(), () -> DateTimeFormatter.ISO_LOCAL_DATE.withChronology(c).getChronology().toString());
            t("fmt ISO " + c.getId(), () -> DateTimeFormatter.ISO_LOCAL_DATE.withChronology(c).format(d));
            t("fmt date.format " + c.getId(), () -> c.date(d).format(DateTimeFormatter.ofPattern("G y-MM-dd", Locale.US)));
        }
        // queries
        ZonedDateTime z = ZonedDateTime.of(2024, 3, 5, 10, 15, 30, 0, ZoneId.of("Europe/Moscow"));
        OffsetDateTime o = z.toOffsetDateTime();
        Object[] things = {d, LocalTime.NOON, LocalDateTime.of(d, LocalTime.NOON), z, o, Instant.ofEpochSecond(0)};
        for (Object th2 : things) {
            TemporalAccessor ta = (TemporalAccessor) th2;
            String n = th2.getClass().getSimpleName();
            t("q zoneId " + n, () -> ta.query(TemporalQueries.zoneId()));
            t("q zone " + n, () -> ta.query(TemporalQueries.zone()));
            t("q offset " + n, () -> ta.query(TemporalQueries.offset()));
            t("q ld " + n, () -> ta.query(TemporalQueries.localDate()));
            t("q lt " + n, () -> ta.query(TemporalQueries.localTime()));
            t("q chrono " + n, () -> ta.query(TemporalQueries.chronology()));
            t("q prec " + n, () -> ta.query(TemporalQueries.precision()));
        }
        t("ld chrono", () -> d.getChronology().toString() + " " + d.getEra() + " " + LocalDateTime.of(d, LocalTime.NOON).getChronology());
        t("iso date", () -> IsoChronology.INSTANCE.date(d).equals(d));
        t("iso ymd", () -> IsoChronology.INSTANCE.date(IsoEra.BCE, 5, 1, 1).toString());
        t("iso era", () -> IsoEra.CE.getDisplayName(TextStyle.FULL, Locale.US) + " " + IsoEra.BCE.getDisplayName(TextStyle.SHORT, Locale.US) + " " + IsoEra.CE.getDisplayName(TextStyle.NARROW, Locale.US));
        t("minguo era names", () -> MinguoEra.ROC.getDisplayName(TextStyle.FULL, Locale.US) + "|" + MinguoEra.BEFORE_ROC.getDisplayName(TextStyle.FULL, Locale.US) + "|" + MinguoEra.ROC.getDisplayName(TextStyle.SHORT, Locale.US) + "|" + MinguoEra.BEFORE_ROC.getDisplayName(TextStyle.SHORT, Locale.US));
        t("thai era names", () -> ThaiBuddhistEra.BE.getDisplayName(TextStyle.FULL, Locale.US) + "|" + ThaiBuddhistEra.BEFORE_BE.getDisplayName(TextStyle.FULL, Locale.US) + "|" + ThaiBuddhistEra.BE.getDisplayName(TextStyle.SHORT, Locale.US) + "|" + ThaiBuddhistEra.BEFORE_BE.getDisplayName(TextStyle.NARROW, Locale.US));
        t("era vals", () -> Arrays.toString(MinguoEra.values()) + Arrays.toString(ThaiBuddhistEra.values()) + Arrays.toString(IsoEra.values()));
        t("era of", () -> MinguoEra.of(1) + " " + ThaiBuddhistEra.of(0) + " " + IsoEra.of(1));
        t("era of bad", () -> MinguoEra.of(2));
        return out.toString();
    }
}
