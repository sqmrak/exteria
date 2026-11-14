public class Arith {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static int idiv(int a, int b) { return a / b; }
    static int irem(int a, int b) { return a % b; }
    static long ldiv(long a, long b) { return a / b; }
    static long lrem(long a, long b) { return a % b; }

    public static String run() {
        out = new StringBuilder();
        int max = Integer.MAX_VALUE, min = Integer.MIN_VALUE;
        p("add", max + 1);
        p("sub", min - 1);
        p("mul", max * max);
        p("neg", -min);
        p("abs", Math.abs(min));
        p("div", min / -1);
        p("rem", min % -1);
        p("divneg", -7 / 2);
        p("remneg", -7 % 2);
        p("divneg2", 7 / -2);
        p("remneg2", 7 % -2);
        long lmax = Long.MAX_VALUE, lmin = Long.MIN_VALUE;
        p("ladd", lmax + 1);
        p("lmul", lmax * lmax);
        p("ldiv", lmin / -1L);
        p("lrem", lmin % -1L);
        p("ldivn", -7L / 2L);
        p("lremn", -7L % 2L);
        p("shl", 1 << 33);
        p("shr", -16 >> 2);
        p("ushr", -16 >>> 2);
        p("ushr0", -16 >>> 0);
        p("lshl", 1L << 65);
        p("lshr", -16L >> 2);
        p("lushr", -16L >>> 2);
        p("lushr0", -16L >>> 0);
        p("and", 0xF0F0 & 0xFF00);
        p("or", 0xF0F0 | 0x0F0F);
        p("xor", 0xF0F0 ^ 0xFFFF);
        p("not", ~12345);
        p("lnot", ~12345L);
        p("i2b", (byte) 200);
        p("i2s", (short) 70000);
        p("i2c", (int) (char) -1);
        p("l2i", (int) 0x1_2345_6789L);
        p("i2l", (long) -5);
        p("i2f", (float) 16777217);
        p("l2f", (float) 123456789012345L);
        p("l2d", (double) 123456789012345678L);
        p("f2i", (int) 1e20f);
        p("f2i2", (int) -1e20f);
        p("f2inan", (int) Float.NaN);
        p("d2i", (int) 3.99);
        p("d2in", (int) -3.99);
        p("d2l", (long) 1e30);
        p("d2l2", (long) -1e30);
        p("dnan", (long) Double.NaN);
        p("fadd", 0.1f + 0.2f);
        p("dadd", 0.1 + 0.2);
        p("fmul", 1.1f * 1.1f);
        p("dmul", 1.1 * 1.1);
        p("fdiv", 1f / 3f);
        p("ddiv", 1.0 / 3.0);
        p("f0", 1f / 0f);
        p("fn0", -1f / 0f);
        p("fnan", 0f / 0f);
        p("d0", 1.0 / 0.0);
        p("frem", 5.5f % 2f);
        p("drem", -5.5 % 2.0);
        p("drem0", 5.0 % 0.0);
        p("dreminf", 5.0 % Double.POSITIVE_INFINITY);
        p("fneg", -0.0f);
        p("dneg", -0.0);
        p("big", 1e10f);
        p("small", 1e-5f);
        p("mid", 123456.789f);
        p("dbig", 1.0E7);
        p("dsmall", 0.001);
        p("dsmaller", 0.0001);
        p("dpi", Math.PI);
        p("fmax", Float.MAX_VALUE);
        p("dmin", Double.MIN_VALUE);
        p("cmp1", Double.NaN < 1.0);
        p("cmp2", Double.NaN > 1.0);
        p("cmp3", Double.NaN == Double.NaN);
        p("cmp4", 0.0 == -0.0);
        p("cmp5", Float.compare(0.0f, -0.0f));
        p("lcmp", Long.compare(5L, 7L));
        p("cmpl", cmp(1.5f, 2.5f) + "," + cmp(2.5f, 1.5f) + "," + cmp(Float.NaN, 1f));
        p("round", Math.round(2.5) + "," + Math.round(-2.5) + "," + Math.round(2.4f));
        p("floor", Math.floor(-1.5) + "," + Math.ceil(-1.5));
        p("sqrt", Math.sqrt(2.0));
        p("pow", Math.pow(2.0, 10.0));
        p("hex", Integer.toHexString(-1) + "," + Long.toHexString(-1L) + "," + Integer.toBinaryString(10));
        p("parse", Integer.parseInt("-123") + Integer.parseInt("7f", 16));
        p("bitcount", Integer.bitCount(0xFF00FF) + "," + Long.bitCount(-1L));
        p("nlz", Integer.numberOfLeadingZeros(1) + "," + Integer.numberOfTrailingZeros(8));
        p("rot", Integer.rotateLeft(0x80000001, 1));
        p("char", (char) ('a' + 1));
        p("charint", 'a' + 1);
        int c = 0;
        c += 3.7;
        p("compound", c);
        byte b = 127;
        b++;
        p("byteinc", b);
        short s = -32768;
        s--;
        p("shortdec", s);
        char ch = 65535;
        ch++;
        p("charinc", (int) ch);
        long acc = 1;
        for (int i = 1; i <= 25; i++) acc *= i;
        p("fact25", acc);
        int h = 0;
        for (int i = 0; i < 100; i++) h = 31 * h + i;
        p("hash", h);
        p("divzero", thrown(0));
        p("remzero", thrown(1));
        p("ldivzero", thrown(2));
        p("lremzero", thrown(3));
        p("fzero", 5.0f / 0 + "," + (5 % 3.0));
        return out.toString();
    }

    static int cmp(float a, float b) {
        return a < b ? -1 : a > b ? 1 : a == b ? 0 : 2;
    }

    static String thrown(int which) {
        try {
            switch (which) {
                case 0: return "" + idiv(1, 0);
                case 1: return "" + irem(1, 0);
                case 2: return "" + ldiv(1, 0);
                default: return "" + lrem(1, 0);
            }
        } catch (ArithmeticException e) {
            return e.getClass().getName();
        }
    }
}
