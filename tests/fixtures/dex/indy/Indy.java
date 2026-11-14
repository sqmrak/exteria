import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.function.IntBinaryOperator;
import java.util.function.IntSupplier;
import java.util.function.LongUnaryOperator;
import java.util.function.Predicate;
import java.util.function.Supplier;
import java.util.function.ToIntFunction;
import java.util.function.UnaryOperator;

public class Indy {
    static StringBuilder out;
    static int counter;

    interface Shape { double area(); default String label() { return "shape:" + area(); } }
    interface Triple<A, B, C> { String join(A a, B b, C c); }
    interface Marker {}
    interface Narrow { void take(byte b, short s, char c, boolean z); }

    final int base;
    Indy(int base) { this.base = base; }
    Indy() { this(7); }

    int addBase(int v) { return base + v; }
    static int twice(int v) { return v * 2; }
    static String shout(String s) { return s.toUpperCase() + "!"; }
    static long widen(long v) { return v + 1; }
    static void bump() { counter++; }
    static boolean isPositive(int v) { return v > 0; }

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        counter = 0;

        Runnable r = () -> p("runnable", "ran");
        r.run();
        Runnable noCapture1 = () -> counter++;
        Runnable noCapture2 = () -> counter++;
        noCapture1.run(); noCapture2.run();
        p("counter", counter);

        int captured = 5;
        String text = "cap";
        Supplier<String> sup = () -> text + captured;
        p("supplier", sup.get());

        IntBinaryOperator add = (a, b) -> a + b;
        p("intop", add.applyAsInt(40, 2));
        IntSupplier is = () -> captured * 3;
        p("intsupplier", is.getAsInt());
        LongUnaryOperator lu = v -> v << 33;
        p("longop", lu.applyAsLong(3));

        Function<Integer, Integer> box = v -> v + 1;
        p("boxed", box.apply(41));
        Function<String, Integer> len = String::length;
        p("strlen", len.apply("hello"));
        Function<Integer, Long> toLong = Indy::widen;
        p("widening", toLong.apply(9));
        UnaryOperator<String> sh = Indy::shout;
        p("static ref", sh.apply("hey"));
        Indy instance = new Indy(100);
        Function<Integer, Integer> bound = instance::addBase;
        p("bound ref", bound.apply(5));
        BiFunction<Indy, Integer, Integer> unbound = Indy::addBase;
        p("unbound ref", unbound.apply(new Indy(1), 2));
        Supplier<Indy> ctor = Indy::new;
        p("ctor ref", ctor.get().base);
        Function<Integer, Indy> ctor2 = Indy::new;
        p("ctor ref 2", ctor2.apply(55).base);
        Runnable bump = Indy::bump;
        bump.run(); bump.run();
        p("static void", counter);
        Predicate<Integer> pos = Indy::isPositive;
        p("predicate", pos.test(3) + "," + pos.test(-3));
        ToIntFunction<String> parse = Integer::parseInt;
        p("parse", parse.applyAsInt("123"));

        Comparator<String> byLen = Comparator.comparingInt(String::length);
        List<String> words = new ArrayList<>();
        words.add("ccc"); words.add("a"); words.add("bb");
        words.sort(byLen.reversed());
        p("sorted", words);
        words.sort((x, y) -> x.compareTo(y));
        p("sorted2", words);
        p("stream", words.stream().map(String::toUpperCase).filter(s -> s.length() > 1).count());

        Shape sq = () -> 4.0;
        p("default method", sq.label());
        Triple<String, Integer, Double> tri = (a, b, c) -> a + b + c;
        p("triple", tri.join("x", 2, 3.5));
        Narrow narrow = (b, s, c, z) -> p("narrow", b + "," + s + "," + c + "," + z);
        narrow.take((byte) -3, (short) 300, 'q', true);

        Runnable thrower = () -> { throw new IllegalStateException("from lambda"); };
        try { thrower.run(); } catch (IllegalStateException e) { p("caught", e.getMessage()); }
        Function<Integer, Integer> npe = v -> v + 1;
        try { npe.apply(null); } catch (NullPointerException e) { p("unbox null", "npe"); }

        Object o = (Runnable & Marker) () -> {};
        p("marker", (o instanceof Marker) + "," + (o instanceof Runnable));
        p("same class", r.getClass() == r.getClass());
        p("lambda name", r.getClass().getName().contains("Lambda"));

        byte bb = 3; short ss = 9; char cc = 'z'; boolean zz = true; float ff = 1.5f; double dd = -0.25;
        long ll = 1L << 40; Object nul = null;
        String cat = "b=" + bb + " s=" + ss + " c=" + cc + " z=" + zz + " f=" + ff + " d=" + dd + " l=" + ll + " n=" + nul + " t=" + text;
        p("concat", cat);
        p("concat const", "a\u0001b" + captured);
        p("concat only", "" + captured + captured);
        String empty = "";
        p("concat empty", empty + empty);
        p("concat ref", "x" + new StringBuilder("sb") + new int[0].length);
        return out.toString();
    }
}
