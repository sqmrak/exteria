public class Flow {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

    static int ack(int m, int n) {
        if (m == 0) return n + 1;
        if (n == 0) return ack(m - 1, 1);
        return ack(m - 1, ack(m, n - 1));
    }

    static int sw(int x) {
        switch (x) {
            case 0: return 10;
            case 1: return 11;
            case 2: return 12;
            case 4: return 14;
            case 5: return 15;
            default: return -1;
        }
    }

    static int sparse(int x) {
        switch (x) {
            case -1000: return 1;
            case 7: return 2;
            case 100000: return 3;
            case Integer.MIN_VALUE: return 4;
            default: return 0;
        }
    }

    static int strsw(String s) {
        switch (s) {
            case "alpha": return 1;
            case "beta": return 2;
            case "gamma": return 3;
            case "Aa": return 4;
            case "BB": return 5;
            default: return 0;
        }
    }

    static String fin(int mode) {
        StringBuilder b = new StringBuilder();
        try {
            b.append("t");
            if (mode == 1) throw new IllegalStateException("x");
            if (mode == 2) return b.append("r").toString();
            b.append("e");
        } catch (IllegalStateException e) {
            b.append("c");
        } finally {
            b.append("f");
        }
        return b.toString();
    }

    static String nested(int mode) {
        StringBuilder b = new StringBuilder();
        try {
            try {
                if (mode == 0) throw new RuntimeException("a");
                if (mode == 1) throw new Error("b");
                b.append("ok");
            } catch (RuntimeException e) {
                b.append("inner");
                throw new IllegalArgumentException("c", e);
            } finally {
                b.append("-f1");
            }
        } catch (IllegalArgumentException e) {
            b.append("-outer:").append(e.getCause().getMessage());
        } catch (Throwable e) {
            b.append("-throwable:").append(e.getMessage());
        } finally {
            b.append("-f2");
        }
        return b.toString();
    }

    static int loops() {
        int total = 0;
        outer:
        for (int i = 0; i < 20; i++) {
            for (int j = 0; j < 20; j++) {
                if (j > i) continue outer;
                if (i * j > 150) break outer;
                total += i ^ j;
            }
        }
        int k = 0;
        do { k += 3; } while (k < 100);
        while (k > 0) { k -= 7; total += k; }
        return total;
    }

    static int collatz(long n) {
        int steps = 0;
        while (n != 1) {
            n = (n & 1) == 0 ? n / 2 : 3 * n + 1;
            steps++;
        }
        return steps;
    }

    static boolean even(int n) { return n == 0 || odd(n - 1); }
    static boolean odd(int n) { return n != 0 && even(n - 1); }

    static int deep(int n) { return n == 0 ? 0 : 1 + deep(n - 1); }

    public static String run() {
        out = new StringBuilder();
        p("fib", fib(18));
        p("ack", ack(2, 3));
        StringBuilder s = new StringBuilder();
        for (int i = -1; i < 7; i++) s.append(sw(i)).append(',');
        p("switch", s);
        s.setLength(0);
        for (int x : new int[]{-1000, 7, 100000, Integer.MIN_VALUE, 3}) s.append(sparse(x)).append(',');
        p("sparse", s);
        s.setLength(0);
        for (String x : new String[]{"alpha", "beta", "gamma", "Aa", "BB", "delta"}) s.append(strsw(x)).append(',');
        p("strswitch", s);
        p("fin0", fin(0));
        p("fin1", fin(1));
        p("fin2", fin(2));
        p("nested0", nested(0));
        p("nested1", nested(1));
        p("nested2", nested(2));
        p("loops", loops());
        p("collatz", collatz(27));
        p("even", even(30) + "," + odd(7));
        p("deep", deep(2500));
        long sum = 0;
        for (int i = 0; i < 20000; i++) sum += i % 7 * (i & 3);
        p("sum", sum);
        return out.toString();
    }
}
