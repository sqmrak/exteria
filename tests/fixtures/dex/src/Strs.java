public class Strs {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    public static String run() {
        out = new StringBuilder();
        String s = "Hello, World";
        p("len", s.length());
        p("charAt", s.charAt(4) + "," + (int) s.charAt(7));
        p("sub", s.substring(7) + "|" + s.substring(2, 5));
        p("index", s.indexOf('o') + "," + s.indexOf("o", 5) + "," + s.lastIndexOf('o') + "," + s.indexOf("xyz") + "," + s.indexOf("World"));
        p("case", s.toUpperCase() + s.toLowerCase());
        p("trim", "[" + "  pad \t".trim() + "]");
        p("eq", s.equals("Hello, World") + "," + s.equals(null) + "," + s.equalsIgnoreCase("hello, WORLD") + "," + "a".equals(1));
        p("cmp", "abc".compareTo("abd") + "," + "b".compareTo("a") + "," + "abc".compareTo("ab") + "," + "".compareTo("a"));
        p("hash", s.hashCode() + "," + "".hashCode() + "," + "polygenelubricants".hashCode());
        p("contains", s.contains("lo, W") + "," + s.startsWith("Hell") + "," + s.endsWith("ld") + "," + s.startsWith("World", 7));
        p("replace", s.replace('l', 'L') + "," + s.replace("World", "There"));
        p("concat", "a".concat("b") + 1 + 2L + 3.5f + 4.25 + 'c' + true + null);
        p("empty", "".isEmpty() + "," + " ".isEmpty());
        p("intern", ("he" + "llo") == "hello");
        p("valueOf", String.valueOf(12) + String.valueOf(true) + String.valueOf('x') + String.valueOf(1.5));
        char[] cs = s.toCharArray();
        cs[0] = 'J';
        p("chars", new String(cs) + "," + new String(cs, 1, 3) + "," + String.valueOf(cs, 7, 5));
        byte[] bytes = "héllo 中".getBytes();
        StringBuilder bs = new StringBuilder();
        for (byte b : bytes) bs.append(b & 0xFF).append(' ');
        p("utf8", bs.toString() + new String(bytes));
        String uni = "a😀b";
        p("surrogate", uni.length() + "," + uni.codePointAt(1) + "," + (int) uni.charAt(1) + "," + (int) uni.charAt(2));
        StringBuilder sb = new StringBuilder("abc");
        sb.append(1).append('x').append(2.5).append(true).append((Object) null).append(new char[]{'y', 'z'});
        sb.insert(0, "<<").insert(2, 9).reverse();
        p("sb", sb);
        sb.setLength(5);
        sb.setCharAt(1, 'Q');
        sb.deleteCharAt(0);
        sb.replace(0, 2, "__");
        p("sb2", sb + "," + sb.length() + "," + sb.indexOf("_") + "," + sb.charAt(2));
        p("intstr", Integer.toString(-255, 16) + "," + Integer.toString(255, 2) + "," + Long.toString(Long.MIN_VALUE));
        p("parse", Integer.valueOf("42") + Integer.parseInt("+7"));
        String bad;
        try { Integer.parseInt("12x"); bad = "no"; } catch (NumberFormatException e) { bad = "nfe"; }
        p("nfe", bad);
        String nul = null;
        String npe;
        try { npe = "" + nul.length(); } catch (NullPointerException e) { npe = "npe"; }
        p("npe", npe);
        String sioobe;
        try { s.charAt(99); sioobe = "no"; } catch (StringIndexOutOfBoundsException e) { sioobe = "sioobe"; }
        p("sioobe", sioobe);
        p("boxes", Integer.valueOf(127) == Integer.valueOf(127));
        p("boxes2", Integer.valueOf(1000) == Integer.valueOf(1000));
        p("boxeq", Integer.valueOf(1000).equals(Integer.valueOf(1000)) + "," + Long.valueOf(5).equals(5) + "," + Long.valueOf(5).equals(5L));
        Object o = 42;
        Object d = 4.5;
        Object c = 'c';
        Object bo = true;
        p("autobox", o + "," + d + "," + c + "," + bo + "," + (o instanceof Integer) + (d instanceof Double) + (c instanceof Character) + (bo instanceof Boolean));
        long big = 1L << 40;
        Long boxed = big;
        p("unbox", boxed + 1 + "," + boxed.hashCode() + "," + Double.valueOf(1.5).hashCode() + "," + Boolean.hashCode(true));
        p("minmax", Integer.MAX_VALUE + "," + Integer.MIN_VALUE + "," + Long.MAX_VALUE + "," + Byte.MIN_VALUE + "," + Short.MAX_VALUE + "," + (int) Character.MAX_VALUE);
        p("char", Character.isDigit('7') + "," + Character.isLetter('x') + "," + Character.toUpperCase('q') + "," + Character.getNumericValue('z') + "," + Character.isWhitespace(' '));
        return out.toString();
    }
}
