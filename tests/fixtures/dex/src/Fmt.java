import java.util.regex.*;

public class Fmt {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static String f(String fmt, Object... args) {
        try { return String.format(fmt, args); } catch (RuntimeException e) { return "!" + e.getClass().getSimpleName(); }
    }

    public static void run0() {}

    public static String run() {
        out = new StringBuilder();
        p("d", f("[%d|%5d|%-5d|%05d|%+d|% d|%,d|%(d]", 42, 42, 42, 42, 42, 42, 1234567, -42));
        p("dneg", f("[%d|%5d|%05d|%,d|%x|%X|%o]", -42, -42, -42, -1234567, -1, 255, 8));
        p("dlong", f("%d,%x,%d", Long.MIN_VALUE, -1L, (byte) -5));
        p("hex", f("%#x %#o %08x", 255, 8, 48879));
        p("f", f("[%f|%.2f|%8.3f|%-8.1f|%08.2f|%+.1f|%,.2f]", 3.14159265, 3.14159265, 3.14159265, 3.14159265, -3.14159265, 2.5, 1234567.891));
        p("fround", f("%.1f %.1f %.1f %.2f %.2f %.0f %.0f %.0f", 0.25, 0.35, 0.05, 1.005, 2.675, 0.5, 1.5, 2.5));
        p("fbig", f("%.3f %.10f %f", 1e10, 1e-7, 123456789.123456789));
        p("fspecial", f("%f %f %.1f %f", Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -0.0));
        p("ffloat", f("%.9f %.2f %s", 0.1f, 1.005f, 0.1f));
        p("e", f("[%e|%.2e|%12.4E|%.0e]", 12345.6789, 12345.6789, 0.000123456, 5.5));
        p("g", f("[%g|%.3g|%g|%g|%.3g]", 12345.6789, 12345.6789, 0.0001234, 1e10, 0.5));
        p("s", f("[%s|%10s|%-10s|%.3s|%S]", "text", "text", "text", "text", "text"));
        p("snull", f("[%s|%b|%c]", null, null, null));
        p("sobj", f("%s %s %s", 1.5f, 10L, new StringBuilder("sb")));
        p("b", f("[%b|%B|%b|%b]", true, false, "x", null));
        p("c", f("[%c|%C|%c|%5c]", 'a', 'b', 65, 'z'));
        p("pct", f("100%% sure %n").replace("\n", "NL"));
        p("index", f("%2$s %1$s %2$s %<s", "a", "b"));
        p("width", f("[%3d][%-3d][%3s]", 12345, 12345, "abcdef"));
        p("errors", f("%d", "x") + f("%s %s", "a") + f("%z", 1) + f("%.2d", 1));
        p("mixed", String.format("%s has %d items costing $%.2f (%5.1f%%)", "cart", 3, 19.989, 45.25));
        p("chars", f("%c%c%c", 'x', 'y', 'z'));
        p("h", f("%h %h", "hi", 255));

        Pattern pat = Pattern.compile("(\\w+)@(\\w+)\\.com");
        Matcher m = pat.matcher("mail bob@site.com and amy@corp.com now");
        StringBuilder sb = new StringBuilder();
        while (m.find()) sb.append(m.group()).append('|').append(m.group(1)).append('|').append(m.start()).append('-').append(m.end()).append(';');
        p("find", sb);
        p("groups", m.reset().find() + "," + m.groupCount());
        p("matches", "abc123".matches("[a-z]+\\d+") + "," + "abc".matches("ab") + "," + Pattern.matches("a.c", "abc"));
        p("replace", "a1b22c333".replaceAll("\\d+", "#") + "," + "a1b22c333".replaceFirst("\\d+", "<$0>") + "," + "x-y".replaceAll("(\\w)-(\\w)", "$2-$1"));
        p("split", join("a,b,,c,,".split(",")) + "|" + join("a,b,,c,,".split(",", -1)) + "|" + join("a,b,c".split(",", 2)) + "|" + join(" a  b ".split("\\s+")) + "|" + join("abc".split("")));
        p("split2", join("1.2.3".split("\\.")) + "|" + join("a1b2c3".split("\\d")) + "|" + join("".split(",")) + "|" + join(",a".split(",")));
        p("flags", Pattern.compile("ABC", Pattern.CASE_INSENSITIVE).matcher("xabcx").find() + "," + Pattern.compile("^b", Pattern.MULTILINE).matcher("a\nb").find()
            + "," + Pattern.compile("a.b").matcher("a\nb").find() + "," + Pattern.compile("a.b", Pattern.DOTALL).matcher("a\nb").find());
        p("named", Pattern.compile("(?<year>\\d{4})-(?<mon>\\d{2})").matcher("on 2024-05-17").replaceAll("${mon}/${year}"));
        Matcher nm = Pattern.compile("(?<k>[a-z]+)=(?<v>\\d+)").matcher("key=42");
        nm.find();
        p("namedgroup", nm.group("k") + "," + nm.group("v") + "," + nm.start("v"));
        p("quote", Pattern.quote("a.b") + "," + "a.b".matches(Pattern.quote("a.b")) + "," + "axb".matches(Pattern.quote("a.b")) + "," + Matcher.quoteReplacement("$1\\"));
        p("lazy", "<a><b>".replaceAll("<.+?>", "X") + "," + "<a><b>".replaceAll("<.+>", "X"));
        p("anchors", "foo bar".replaceAll("\\bb", "B") + "," + "tab\tsp".replaceAll("\\s", "_") + "," + "A1".replaceAll("[^0-9]", ""));
        p("lookahead", "price: 100 dollars".replaceAll("\\d+(?= dollars)", "N") + "," + "ab12".replaceAll("(?<=b)\\d", "X"));
        p("backref", "abab".matches("(ab)\\1") + "," + "aa bb cd".replaceAll("(\\w)\\1", "<$1$1>"));
        p("posix", "Hello World".replaceAll("\\p{Upper}", "_") + "," + "a1!".replaceAll("\\p{Punct}", "?") + "," + "ab c".replaceAll("\\p{Alpha}", "L"));
        p("region", Pattern.compile("\\d").matcher("a1b2").replaceAll("") + "," + Pattern.compile("o").matcher("foo").find(2));
        StringBuffer buf = new StringBuffer();
        Matcher am = Pattern.compile("\\d").matcher("a1b2c");
        while (am.find()) am.appendReplacement(buf, "[" + (Integer.parseInt(am.group()) * 2) + "]");
        am.appendTail(buf);
        p("append", buf);
        String bad;
        try { Pattern.compile("(unclosed"); bad = "no"; } catch (PatternSyntaxException e) { bad = "pse"; }
        try { "x".matches("[a-"); bad += ",no"; } catch (PatternSyntaxException e) { bad += ",pse"; }
        try { Pattern.compile("a").matcher("a").group(); bad += ",no"; } catch (IllegalStateException e) { bad += ",ise"; }
        try { Pattern.compile("(a)").matcher("a").replaceAll("$2"); bad += ",no"; } catch (IndexOutOfBoundsException e) { bad += ",ioobe"; }
        p("regexerrors", bad);
        return out.toString();
    }

    static String join(String[] parts) {
        StringBuilder b = new StringBuilder("[");
        for (String s : parts) b.append(s).append('/');
        return b.append(parts.length).append(']').toString();
    }
}
