import java.text.Bidi;
import java.util.*;

/** java.text.Bidi: levels, runs, direction, line objects and visual reordering */
public class BidiText {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    static String describe(Bidi b) {
        StringBuilder sb = new StringBuilder();
        sb.append(b.isLeftToRight() ? "L" : "-").append(b.isRightToLeft() ? "R" : "-").append(b.isMixed() ? "M" : "-").append(b.baseIsLeftToRight() ? "l" : "r");
        sb.append(" base=").append(b.getBaseLevel()).append(" len=").append(b.getLength()).append(" runs=").append(b.getRunCount()).append(" levels=");
        for (int i = 0; i < b.getLength(); i++) sb.append(b.getLevelAt(i));
        sb.append(" runs:");
        for (int r = 0; r < b.getRunCount(); r++) sb.append(" [").append(b.getRunStart(r)).append(',').append(b.getRunLimit(r)).append(',').append(b.getRunLevel(r)).append(']');
        return sb.toString();
    }

    public static String run() {
        out = new StringBuilder();
        String hebrew = "אבג";
        String arabic = "العربية";
        String[] texts = {
            "", "abc", "abc def", hebrew, arabic, "abc " + hebrew + " def", hebrew + " abc " + hebrew, hebrew + " 123 " + hebrew, "abc 123", hebrew + "123",
            hebrew + " (abc)", "abc (" + hebrew + ")", "a" + hebrew + "b" + hebrew + "c", "123", "1,234.5 " + hebrew, hebrew + " 1,234.5", arabic + " 123",
            arabic + "١٢٣", "abc ١٢٣", "!!!", hebrew + "!", "abc!", "  abc  ", "  " + hebrew + "  ", hebrew + "́ a",
            "-5 " + hebrew, hebrew + " -5", "$5 " + hebrew, "5% " + hebrew, "a‫" + "bc‬" + "d", "a‮" + "bc‬" + "d", "‭abc" + hebrew + "‬",
            hebrew + "‪" + "abc‬" + hebrew, "abc\n" + hebrew, hebrew + "\nabc", "abc\t" + hebrew + "\tdef", "a b" + hebrew + " c d" + hebrew + " e",
            "http://x.y/" + hebrew, hebrew + " " + hebrew, "‫‫‫x‬‬‬",
        };
        int[] flags = {Bidi.DIRECTION_LEFT_TO_RIGHT, Bidi.DIRECTION_RIGHT_TO_LEFT, Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT, Bidi.DIRECTION_DEFAULT_RIGHT_TO_LEFT};
        for (String t : texts) {
            for (int f : flags) {
                Bidi b;
                try { b = new Bidi(t, f); } catch (Throwable e) { p("new " + f, e.getClass().getName()); continue; }
                p("bidi " + f + " " + t.replace('\n', '~').replace('\t', '^').replace('‪', '<').replace('‫', '(').replace('‬', '>').replace('‭', '[').replace('‮', ']'), describe(b));
            }
        }
        // line objects
        Bidi full = new Bidi("abc " + hebrew + " def " + hebrew + hebrew, Bidi.DIRECTION_LEFT_TO_RIGHT);
        for (int[] range : new int[][]{{0, 4}, {4, 8}, {2, 12}, {0, 0}, {5, 5}, {0, 14}, {3, 3}, {-1, 3}, {3, 2}, {0, 99}}) {
            try { p("line " + range[0] + "," + range[1], describe(full.createLineBidi(range[0], range[1]))); }
            catch (Throwable e) { p("line " + range[0] + "," + range[1], e.getClass().getName() + ": " + e.getMessage()); }
        }
        // out of range accessors
        try { p("level -1", full.getLevelAt(-1)); } catch (Throwable e) { p("level -1", e.getClass().getName()); }
        try { p("level 99", full.getLevelAt(99)); } catch (Throwable e) { p("level 99", e.getClass().getName()); }
        try { p("run 99", full.getRunStart(99)); } catch (Throwable e) { p("run 99", e.getClass().getName()); }
        // requiresBidi
        char[] mix = ("abc" + hebrew + "def").toCharArray();
        p("req all", Bidi.requiresBidi(mix, 0, mix.length));
        p("req ltr", Bidi.requiresBidi(mix, 0, 3));
        p("req rtl", Bidi.requiresBidi(mix, 3, 6));
        p("req end", Bidi.requiresBidi(mix, 6, 9));
        p("req empty", Bidi.requiresBidi(mix, 3, 3));
        p("req arabic", Bidi.requiresBidi(arabic.toCharArray(), 0, arabic.length()));
        p("req digits", Bidi.requiresBidi("123".toCharArray(), 0, 3));
        p("req embed", Bidi.requiresBidi("a‫b".toCharArray(), 0, 3));
        // reorderVisually
        byte[][] levelSets = {{0, 0, 0}, {1, 1, 1}, {0, 1, 1, 0}, {0, 1, 2, 1, 0}, {1, 2, 2, 1}, {0, 1, 2, 3, 2, 1, 0}, {2, 1, 0}, {1, 0, 1, 0, 1}, {}, {0}, {1}, {3, 3, 2, 2, 1}};
        for (byte[] ls : levelSets) {
            Object[] objs = new Object[ls.length];
            for (int i = 0; i < objs.length; i++) objs[i] = "o" + i;
            try { Bidi.reorderVisually(ls, 0, objs, 0, ls.length); p("reorder " + Arrays.toString(ls), Arrays.toString(objs)); }
            catch (Throwable e) { p("reorder " + Arrays.toString(ls), e.getClass().getName() + ": " + e.getMessage()); }
        }
        byte[] ls = {0, 1, 1, 0, 1, 0};
        Object[] os = {"a", "b", "c", "d", "e", "f"};
        Bidi.reorderVisually(ls, 1, os, 2, 3);
        p("reorder sub", Arrays.toString(os));
        try { Bidi.reorderVisually(ls, 4, os, 0, 5); p("reorder bad", "no"); } catch (Throwable e) { p("reorder bad", e.getClass().getName()); }
        // embeddings array
        char[] chars = ("abc" + hebrew).toCharArray();
        byte[] emb = {0, 0, 0, -1, -1, -1};
        try { p("emb", describe(new Bidi(chars, 0, emb, 0, chars.length, Bidi.DIRECTION_LEFT_TO_RIGHT))); } catch (Throwable e) { p("emb", e.getClass().getName() + ": " + e.getMessage()); }
        byte[] emb2 = {0, 1, 2, 0, 0, 0};
        try { p("emb2", describe(new Bidi(chars, 0, emb2, 0, chars.length, Bidi.DIRECTION_LEFT_TO_RIGHT))); } catch (Throwable e) { p("emb2", e.getClass().getName() + ": " + e.getMessage()); }
        try { p("chars sub", describe(new Bidi(chars, 2, null, 0, 3, Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT))); } catch (Throwable e) { p("chars sub", e.getClass().getName() + ": " + e.getMessage()); }
        try { p("chars bad", describe(new Bidi(chars, 4, null, 0, 5, 0))); } catch (Throwable e) { p("chars bad", e.getClass().getName() + ": " + e.getMessage()); }
        try { p("null", new Bidi((String) null, 0)); } catch (Throwable e) { p("null", e.getClass().getName()); }
        p("str", new Bidi("abc " + hebrew, 0).toString().replaceAll("@[0-9a-f]+", "@"));
        return out.toString();
    }
}
