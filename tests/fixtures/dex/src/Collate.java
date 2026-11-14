import java.text.*;
import java.util.*;

/** java.text.Collator and RuleBasedCollator: the default order, strengths, keys, element iterators and rules of a program */
public class Collate {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    public static String run() {
        out = new StringBuilder();
        Collator c = Collator.getInstance(Locale.US);
        p("class", c.getClass().getName() + " " + c.getStrength() + " " + c.getDecomposition());
        List<String> all = new ArrayList<>();
        for (int i = 32; i < 127; i++) all.add(String.valueOf((char) i));
        for (int i = 160; i < 0x250; i++) all.add(String.valueOf((char) i));
        for (int i = 0x370; i < 0x380; i++) all.add(String.valueOf((char) i));
        for (int i = 0x2010; i < 0x2030; i++) all.add(String.valueOf((char) i));
        all.sort(c);
        StringBuilder sb = new StringBuilder();
        for (String s : all) sb.append(s);
        p("order", sb);
        String[][] sets = {
            {"a", "A", "b", "B", "a-b", "ab", "a b", "résumé", "resume", "Resume", "côte", "cote", "coté", "côté", "Ab", "aB", "10", "9", "a1", "a10", "a2", "", " ", "-", "a-", "-a"},
            {"æ", "ae", "AE", "Æ", "ad", "af", "ß", "ss", "SS", "ST", "su", "þ", "th", "TH", "ti", "œ", "oe", "of", "od"},
            {"ä", "a", "z", "å", "ö", "o", "ü", "u", "n", "ñ", "ö", "ä", "é", "é", "e", "f"},
            {"apple", "Apple", "APPLE", "apple pie", "apple-pie", "applepie", "apple_pie", "Apple Pie", "appl", "apples"},
            {"Ж", "А", "а", "α", "א", "一", "あ", "z", "Z", "1", "½", "①"},
            {"co-op", "coop", "co op", "Co-op", "COOP", "coöp", "coo"},
            {"x1", "x2", "x10", "X1", "x 1", "x-1", "x_1", "x.1"},
            {"\u0000a", "a", "a\u0000", "a­", "​a", "a​", "\ta", "a\t", "\na", "a\n"},
        };
        for (int k = 0; k < sets.length; k++) {
            for (int strength : new int[]{0, 1, 2, 3}) {
                for (int dec : new int[]{0, 1, 2}) {
                    Collator col = Collator.getInstance(Locale.US);
                    col.setStrength(strength);
                    col.setDecomposition(dec);
                    String[] arr = sets[k].clone();
                    Arrays.sort(arr, col);
                    p("sort " + k + " s" + strength + " d" + dec, Arrays.toString(arr).replace('\u0000', '0').replace('​', 'Z').replace('­', 'S'));
                }
            }
        }
        for (int strength : new int[]{0, 1, 2, 3}) {
            Collator col = Collator.getInstance(Locale.US);
            col.setStrength(strength);
            String[][] pairs = {{"a", "A"}, {"a", "á"}, {"á", "A"}, {"e", "é"}, {"a b", "ab"}, {"a-b", "ab"}, {"abc", "abd"}, {"abc", "ab"}, {"ab", "abc"}, {"", ""}, {"", "a"}, {"a", ""},
                {"", " "}, {" ", ""}, {"x", "x"}, {"æ", "ae"}, {"ß", "ss"}, {"á", "á"}, {"á", "á"}, {"Á", "á"}, {"co-op", "coop"}, {"coop", "co-op"}};
            for (String[] pr : pairs) {
                p("cmp s" + strength + " " + pr[0] + "|" + pr[1], col.compare(pr[0], pr[1]) + " " + col.equals(pr[0], pr[1]));
            }
        }
        // objects, errors
        try { p("obj", c.compare((Object) "a", (Object) "b")); } catch (Throwable e) { p("obj", e.getClass().getName()); }
        try { p("obj bad", c.compare((Object) 1, (Object) "b")); } catch (Throwable e) { p("obj bad", e.getClass().getName()); }
        try { p("obj bad2", c.compare((Object) "a", (Object) 2)); } catch (Throwable e) { p("obj bad2", e.getClass().getName()); }
        try { p("null", c.compare(null, "b")); } catch (Throwable e) { p("null", e.getClass().getName()); }
        try { c.setStrength(7); p("strength", "no"); } catch (Throwable e) { p("strength", e.getClass().getName() + ": " + e.getMessage()); }
        try { c.setDecomposition(7); p("decomp", "no"); } catch (Throwable e) { p("decomp", e.getClass().getName() + ": " + e.getMessage()); }
        p("constants", Collator.PRIMARY + " " + Collator.SECONDARY + " " + Collator.TERTIARY + " " + Collator.IDENTICAL + " " + Collator.NO_DECOMPOSITION + " " + Collator.CANONICAL_DECOMPOSITION + " " + Collator.FULL_DECOMPOSITION);
        p("equals", c.equals(Collator.getInstance(Locale.US)) + " " + c.equals((Object) "x"));
        Collator cl = (Collator) c.clone();
        cl.setStrength(Collator.PRIMARY);
        p("clone", cl.getStrength() + " " + c.getStrength() + " " + c.equals(cl));
        p("hash", c.hashCode() == Collator.getInstance(Locale.US).hashCode());
        // keys
        Collator pk = Collator.getInstance(Locale.US);
        for (int strength : new int[]{0, 1, 2}) {
            pk.setStrength(strength);
            String[] words = {"abc", "ABC", "abd", "ábc", "ab", "a b c", "", "zebra", "Zebra"};
            CollationKey[] keys = new CollationKey[words.length];
            for (int i = 0; i < words.length; i++) keys[i] = pk.getCollationKey(words[i]);
            Arrays.sort(keys);
            StringBuilder ks = new StringBuilder();
            for (CollationKey k : keys) ks.append(k.getSourceString()).append(',');
            p("keys s" + strength, ks);
            p("key cmp s" + strength, pk.getCollationKey("abc").compareTo(pk.getCollationKey("abd")) + " " + pk.getCollationKey("abc").compareTo(pk.getCollationKey("ABC")) + " " + pk.getCollationKey("abc").compareTo(pk.getCollationKey("abc")));
            p("key eq s" + strength, pk.getCollationKey("abc").equals(pk.getCollationKey("ABC")) + " " + (pk.getCollationKey("abc").hashCode() == pk.getCollationKey("abc").hashCode()));
        }
        p("key null", pk.getCollationKey(null));
        p("key bytes", pk.getCollationKey("a").toByteArray().length > 0);
        // element iterator
        RuleBasedCollator rb = (RuleBasedCollator) Collator.getInstance(Locale.US);
        for (String s : new String[]{"a", "A", "á", "æ", "ß", " ", "-", "́", "4", "一", "Ж", "ab", "a b", "ch", "", "​", "­"}) {
            CollationElementIterator it = rb.getCollationElementIterator(s);
            StringBuilder es = new StringBuilder();
            int o;
            while ((o = it.next()) != CollationElementIterator.NULLORDER) es.append(String.format("(%x,%x,%x) ", CollationElementIterator.primaryOrder(o), CollationElementIterator.secondaryOrder(o), CollationElementIterator.tertiaryOrder(o)));
            p("elements " + s.length() + " " + (s.isEmpty() ? 0 : (int) s.charAt(0)), es);
        }
        CollationElementIterator it = rb.getCollationElementIterator("abc");
        int first = it.next();
        int second = it.next();
        p("iter offset", it.getOffset());
        p("iter prev", it.previous() == second);
        it.reset();
        p("iter reset", it.next() == first);
        it.setOffset(2);
        p("iter setoffset", it.getOffset() + " " + (it.next() == CollationElementIterator.NULLORDER ? "end" : "more"));
        p("iter null", CollationElementIterator.NULLORDER);
        // rules of the program
        String[] rules = {"< a < b < c", "< c < b < a", "< a, A < b, B", "< a ; á < b", "< a < b & a < x", "< a < b < c & b < z", "< a = b < c",  "& a < b", "< b < a & c < a", "< a < b ; c < d", "< x < y < z @", "< a , A ; b < d"};
        for (String r : rules) {
            try {
                RuleBasedCollator col = new RuleBasedCollator(r);
                String[] words = {"a", "b", "c", "d", "x", "y", "z", "A", "B", "ch", "ca", "cb", "bá", "á", "ab", "ba", "e", "E", ""};
                Arrays.sort(words, col);
                p("rules " + r, Arrays.toString(words) + " " + col.getRules().equals(r) + " " + col.compare("a", "b") + " " + col.compare("a", "A") + " " + col.compare("b", "c"));
            } catch (Throwable e) { p("rules " + r, e.getClass().getName() + ": " + e.getMessage()); }
        }
        for (String r : new String[]{"< a <", "a < b", "< 'a", "& < a", "<", "&"}) {
            try { new RuleBasedCollator(r); p("badrules " + r, "ok"); }
            catch (Throwable e) { p("badrules " + r, e.getClass().getName() + ": " + e.getMessage()); }
        }
        try { new RuleBasedCollator(null); p("nullrules", "no"); } catch (Throwable e) { p("nullrules", e.getClass().getName()); }
        p("default rules", rb.getRules().length() + " " + rb.getRules().hashCode());
        return out.toString();
    }
}
