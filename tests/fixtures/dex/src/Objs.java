public class Objs {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static int counter;

    static abstract class Shape {
        static int made;
        final int id;
        String tag = "shape";
        Shape() { id = ++made; init(); }
        void init() { tag = tag + "!"; }
        abstract double area();
        public String toString() { return getClass().getSimpleName() + "#" + id + "[" + tag + "]"; }
    }

    static class Rect extends Shape {
        double w = 2, h = 3;
        Rect() { super(); }
        Rect(double w, double h) { this(); this.w = w; this.h = h; }
        void init() { tag = "rect-init"; }
        double area() { return w * h; }
    }

    static class Square extends Rect {
        Square(double s) { super(s, s); tag = "sq"; }
        double area() { return super.area() + 0.5; }
    }

    interface Greeter {
        String greet(String n);
        default String twice(String n) { return greet(n) + greet(n); }
    }

    interface Loud extends Greeter {
        default String twice(String n) { return greet(n).toUpperCase() + "?"; }
    }

    static class Hello implements Greeter {
        public String greet(String n) { return "hi " + n + ";"; }
    }

    static class Shout implements Loud {
        public String greet(String n) { return "yo " + n; }
    }

    static class Base {
        int x = 1;
        static String who() { return "base"; }
        String me() { return "Base"; }
        String call() { return me() + x; }
        String over(Object o) { return "obj"; }
        String over(String o) { return "str"; }
        String over(int o) { return "int"; }
        String over(long o) { return "long"; }
        String over(char o) { return "char"; }
        String over(double o) { return "double"; }
    }

    static class Derived extends Base {
        int x = 2;
        static String who() { return "derived"; }
        String me() { return "Derived"; }
        String both() { return x + ":" + super.x + ":" + ((Base) this).x + ":" + super.me(); }
    }

    static class Lazy {
        static { counter += 100; }
        static int value = counter++;
        static final int CONST = 7;
        static final String NAME = "lazy";
    }

    static class Boom {
        static int v = 1 / (counter - counter);
    }

    enum Color {
        RED("r"), GREEN("g"), BLUE("b") {
            String code() { return "B!"; }
        };
        final String c;
        Color(String c) { this.c = c; }
        String code() { return c; }
    }

    static class Counter {
        private int n;
        synchronized void inc() { n++; }
        int get() { synchronized (this) { return n; } }
    }

    class Inner {
        int v = counter + 5;
        int outerCounter() { return counter + v; }
    }

    static Object pick(int i) {
        switch (i) {
            case 0: return "s";
            case 1: return new Rect();
            case 2: return new int[2];
            case 3: return Color.GREEN;
            default: return null;
        }
    }

    public static String run() {
        out = new StringBuilder();
        Shape a = new Rect();
        Shape b = new Rect(4, 5);
        Shape c = new Square(3);
        p("shapes", a + "," + b + "," + c);
        p("areas", a.area() + "," + b.area() + "," + c.area());
        p("made", Shape.made);
        Greeter g = new Hello();
        p("hello", g.twice("bob"));
        p("shout", new Shout().twice("bob"));
        Base base = new Derived();
        p("virt", base.call() + "," + base.x + "," + ((Derived) base).x);
        p("both", ((Derived) base).both());
        p("static", Base.who() + "," + Derived.who());
        Base ov = new Base();
        char ch = 'c';
        p("over", ov.over("s") + "," + ov.over((Object) "s") + "," + ov.over(1) + "," + ov.over(1L)
            + "," + ov.over(ch) + "," + ov.over(1.5f) + "," + ov.over(null == null ? (Object) 1 : null));
        p("before", counter);
        p("const", Lazy.CONST + Lazy.NAME);
        p("afterconst", counter);
        p("lazy", Lazy.value);
        p("afterlazy", counter);
        String r1, r2;
        try { r1 = "" + Boom.v; } catch (ExceptionInInitializerError e) { r1 = "eiie:" + e.getCause().getClass().getName(); }
        try { r2 = "" + Boom.v; } catch (NoClassDefFoundError e) { r2 = "ncdfe"; }
        p("boom", r1 + "," + r2);
        StringBuilder cs = new StringBuilder();
        for (Color col : Color.values()) cs.append(col).append(col.ordinal()).append(col.code());
        p("enum", cs);
        p("valueOf", Color.valueOf("BLUE").code() + (Color.BLUE.getClass() == Color.class));
        Counter cn = new Counter();
        for (int i = 0; i < 1000; i++) cn.inc();
        p("sync", cn.get());
        p("inner", new Objs().new Inner().outerCounter());
        StringBuilder ins = new StringBuilder();
        for (int i = 0; i < 5; i++) {
            Object o = pick(i);
            ins.append(o instanceof String).append(o instanceof Shape).append(o instanceof int[])
               .append(o instanceof Enum).append(o instanceof Comparable).append(o == null).append('|');
        }
        p("instanceof", ins);
        String cc;
        try { Object o = "x"; cc = "" + (Integer) o; } catch (ClassCastException e) { cc = "cce"; }
        p("cast", cc);
        Runnable anon = new Runnable() {
            int calls;
            public void run() { calls++; counter += calls; }
        };
        anon.run(); anon.run();
        p("anon", counter);
        Object o1 = new Object();
        p("identity", (o1 == o1) + "," + o1.equals(o1) + "," + o1.equals(new Object()));
        p("classname", new Square(1).getClass().getName() + "," + int[].class.getName() + "," + String.class.getName());
        p("super", new Square(2).getClass().getSuperclass().getSimpleName());
        return out.toString();
    }
}
