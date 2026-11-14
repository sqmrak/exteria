public class Deps {
    public static String run() {
        StringBuilder b = new StringBuilder();
        try { b.append(Gone.value()); } catch (NoClassDefFoundError e) { b.append("ncdfe;"); }
        try { b.append(new Gone().toString()); } catch (NoClassDefFoundError e) { b.append("ncdfe2;"); }
        try { Object o = "x"; b.append(o instanceof Gone); } catch (NoClassDefFoundError e) { b.append("ncdfe3;"); }
        try { throw new RuntimeException("rt"); } catch (Gone e) { b.append("no;"); } catch (RuntimeException e) { b.append("skip;"); }
        try { b.append(Gone.class == null); } catch (NoClassDefFoundError e) { b.append("ncdfe4;"); }
        try { Object o = "x"; Gone g = (Gone) o; b.append(g == null); } catch (NoClassDefFoundError e) { b.append("ncdfe5;"); }
        return b.toString();
    }

    public static int works() { return 41 + 1; }
}
