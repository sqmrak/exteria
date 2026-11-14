public class Arrs {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static final int[] TABLE = {1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987};
    static final byte[] BYTES = {-128, -1, 0, 1, 127, (byte) 200};
    static final char[] CHARS = {'a', 'b', 'é', '中', '￿'};
    static final short[] SHORTS = {-32768, 32767, 0, -1};
    static final long[] LONGS = {Long.MIN_VALUE, -1L, 0L, 1L << 40, Long.MAX_VALUE};
    static final float[] FLOATS = {0.0f, -0.0f, 1.5f, 3.4028235e38f, 1e-45f, Float.NaN};
    static final double[] DOUBLES = {0.0, 1.0, -2.5, 1e300, Double.POSITIVE_INFINITY};
    static final boolean[] BOOLS = {true, false, true};

    static String join(Object arr) {
        StringBuilder b = new StringBuilder();
        if (arr instanceof int[]) { for (int x : (int[]) arr) b.append(x).append(' '); }
        else if (arr instanceof byte[]) { for (byte x : (byte[]) arr) b.append(x).append(' '); }
        else if (arr instanceof char[]) { for (char x : (char[]) arr) b.append((int) x).append(' '); }
        else if (arr instanceof short[]) { for (short x : (short[]) arr) b.append(x).append(' '); }
        else if (arr instanceof long[]) { for (long x : (long[]) arr) b.append(x).append(' '); }
        else if (arr instanceof float[]) { for (float x : (float[]) arr) b.append(x).append(' '); }
        else if (arr instanceof double[]) { for (double x : (double[]) arr) b.append(x).append(' '); }
        else if (arr instanceof boolean[]) { for (boolean x : (boolean[]) arr) b.append(x).append(' '); }
        return b.toString();
    }

    static String tryIndex(int[] a, int i) {
        try { return "" + a[i]; } catch (ArrayIndexOutOfBoundsException e) { return "oob"; }
    }

    public static String run() {
        out = new StringBuilder();
        p("table", join(TABLE));
        p("bytes", join(BYTES));
        p("chars", join(CHARS));
        p("shorts", join(SHORTS));
        p("longs", join(LONGS));
        p("floats", join(FLOATS));
        p("doubles", join(DOUBLES));
        p("bools", join(BOOLS));
        int[][] grid = new int[4][5];
        for (int i = 0; i < 4; i++) for (int j = 0; j < 5; j++) grid[i][j] = i * j;
        int tot = 0;
        for (int[] row : grid) for (int v : row) tot += v;
        p("grid", tot + "," + grid.length + "," + grid[0].length);
        long[][][] cube = new long[2][3][];
        p("cube", cube.length + "," + cube[1].length + "," + (cube[1][2] == null));
        int[][] ragged = {{1}, {2, 3}, {}, null};
        p("ragged", ragged[1][1] + "," + ragged[2].length + "," + (ragged[3] == null));
        p("oob", tryIndex(TABLE, 16) + "," + tryIndex(TABLE, -1) + "," + tryIndex(TABLE, 15) + "," + tryIndex(null == null ? TABLE : null, 0));
        String neg;
        try { neg = "" + new int[-1].length; } catch (NegativeArraySizeException e) { neg = "nase"; }
        p("negsize", neg);
        Object[] objs = new String[2];
        String store;
        try { objs[0] = "ok"; objs[1] = Integer.valueOf(3); store = "no"; } catch (ArrayStoreException e) { store = "ase"; }
        p("store", store + objs[0]);
        int[] copy = TABLE.clone();
        copy[0] = 99;
        p("clone", TABLE[0] + "," + copy[0] + "," + (copy != TABLE) + "," + copy.length);
        int[] dst = new int[10];
        System.arraycopy(TABLE, 2, dst, 3, 5);
        System.arraycopy(dst, 3, dst, 4, 5);
        p("arraycopy", join(dst));
        String acx;
        try { System.arraycopy(TABLE, 10, dst, 0, 9); acx = "no"; } catch (ArrayIndexOutOfBoundsException e) { acx = "oob"; }
        p("arraycopybad", acx);
        byte[] bb = new byte[4];
        bb[0] = (byte) 255; bb[1] = (byte) 128; bb[2] = (byte) (bb[0] + bb[1]); bb[3] = (byte) (bb[0] >> 1);
        p("bytearith", join(bb));
        char[] cc = new char[3];
        cc[0] = (char) -1; cc[1] = (char) 65; cc[2]++;
        p("chararith", join(cc));
        float[] ff = new float[3];
        ff[0] = 1; ff[1] = 0; ff[2] = ff[0] / 3;
        p("floatarr", join(ff));
        double[] dd = new double[2];
        dd[0] = 2; dd[1] = dd[0] * 0.1;
        p("doublearr", join(dd));
        boolean[] bo = new boolean[3];
        bo[1] = true;
        p("boolarr", join(bo));
        p("types", TABLE.getClass().getName() + "," + grid.getClass().getName() + "," + new String[0].getClass().getName()
            + "," + (TABLE.getClass().getComponentType() == int.class) + "," + TABLE.getClass().isArray());
        String[] words = {"pear", "apple", "fig"};
        for (int i = 0; i < words.length; i++) for (int j = i + 1; j < words.length; j++)
            if (words[j].compareTo(words[i]) < 0) { String t = words[i]; words[i] = words[j]; words[j] = t; }
        p("sorted", words[0] + words[1] + words[2]);
        return out.toString();
    }
}
